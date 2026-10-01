-- BaseAttackClient (LocalScript in StarterPlayer > StarterPlayerScripts)
-- Black hole attack presentation for player bases and world targets:
--   charge -> overhead view -> pick a base or world target -> cinematic
--   -> summary -> return home.
-- The server decides every outcome; this script only presents it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SizeVariants = require(ReplicatedStorage:WaitForChild("SizeVariantConfig"))
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local Config do
	-- BaseAttackConfig must be the settings table. If another script was pasted
	-- into it, say so plainly instead of failing with a confusing error.
	local module = ReplicatedStorage:WaitForChild("BaseAttackConfig")
	local ok, result = pcall(require, module)
	if not ok or type(result) ~= "table" or type(result.Rules) ~= "table" then
		error("[BaseAttack] ReplicatedStorage.BaseAttackConfig is not the attack settings module"
			.. " (it may contain another script's code). Paste the BaseAttackConfig ModuleScript back in. Details: "
			.. tostring(if ok then "returned " .. typeof(result) else result), 0)
	end
	Config = result
end
local VFX = require(ReplicatedStorage:WaitForChild("BaseAttackVFX"))
local WorldTargetClient = require(ReplicatedStorage:WaitForChild("WorldTargetClient"))
local TierConfig = require(ReplicatedStorage:WaitForChild("BlackHoleTierConfig"))
local GuiStyle = require(ReplicatedStorage:WaitForChild("GuiStyle"))


local UiResponsive do
	local module = ReplicatedStorage:FindFirstChild("UiResponsive")
	local ok, result = pcall(function() return module and require(module) end)
	UiResponsive = if ok and type(result) == "table" then result else nil
end

local function targetingHint()
	if UiResponsive and UiResponsive.IsGamepad() then
		return "D-pad to choose  •  A to attack  •  B to cancel"
	elseif UiResponsive and UiResponsive.IsTouch() then
		return "Tap an enemy base or the central island, then tap again"
	end
	return "Click an enemy base or the central island  •  Esc to cancel"
end

local Format do
	local module = ReplicatedStorage:FindFirstChild("NumberFormatter")
	local ok, result = pcall(function() return module and require(module) end)
	Format = (ok and type(result) == "table" and result) or {
		Abbreviate = function(n) return tostring(math.floor(tonumber(n) or 0)) end,
	}
end

local Settings do
	local module = ReplicatedStorage:FindFirstChild("ClientSettings")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then Settings = result end
	end
end

-- Keep waiting instead of giving up: a slow server start must not leave the
-- ATTACK button dead for the whole session.
local remotes = ReplicatedStorage:FindFirstChild("BaseAttackRemotes")
do
	local waited, warned = 0, false
	while not remotes do
		task.wait(0.5)
		waited += 0.5
		remotes = ReplicatedStorage:FindFirstChild("BaseAttackRemotes")
		if not remotes and waited >= 15 and not warned then
			warned = true
			warn("[BaseAttack] Still waiting for BaseAttackRemotes. Check the Output for a red error"
				.. " or a [BaseAttackServer] warning on the Server side.")
		end
	end
end
local requestAttack = remotes:WaitForChild("RequestBaseAttack")
local startedEvent = remotes:WaitForChild("BaseAttackStarted")
local finishedEvent = remotes:WaitForChild("BaseAttackFinished")

WorldTargetClient.Init(remotes)

local TAG = "BlackHole"
local FONT = GuiStyle.FONT
local COLORS = Config.Colors

local PANEL = Color3.fromRGB(10, 14, 32)
local RIM = Color3.fromRGB(58, 118, 222)
local NAVY = Color3.fromRGB(8, 12, 28)
local TEXT = Color3.fromRGB(255, 255, 255)
local TEXT_DIM = Color3.fromRGB(138, 160, 205)
local GOLD = Color3.fromRGB(255, 215, 90)
local GREEN = Color3.fromRGB(56, 222, 104)

local DEFAULT_SUB = "Click an enemy base or the central island  •  Esc to cancel"

local REASONS = {
	own = "That's your own base.",
	locked = "That base is protected.",
	busy = "That target is already under attack.",
	empty = "Nothing there your black hole can consume.",
	destroyed = "It's destroyed. Wait for the next event.",
	rebuilding = "It's still rebuilding.",
	closed = "The island event hasn't started yet.",
	cooling = "This black hole is still recharging.",
}

-- ===================== STATE =====================
local state = "idle" -- idle | charging | overhead | locking | cinematic | summary | returning
local attackerHole = nil
local attackerTier = 1
local originalFov = 70
local pendingAttackId = nil
local activePlan = nil
local lockedKey = nil
local hoveredKey = nil
local indicatorsVisible = false

local receivedPlans = {}
local finishedData = {}
local indicators = {}

local enterOverhead, cancelTargeting, returnHome, lockTarget
local runAttackerCinematic, showSummary, closeSummary

-- ===================== HELPERS =====================
local function formatClock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function qualityKey()
	local quality = Settings and Settings.Get and Settings.Get("Quality")
	if quality == "LOW" or quality == "HIGH" then return quality end
	return "MODERATE"
end

local function glowFor(tier)
	local data = TierConfig.GetTier(tier)
	return (data and (data.GlowColor or data.DiskGlowColor)) or Color3.fromRGB(150, 110, 255)
end

local function diskFor(tier)
	local data = TierConfig.GetTier(tier)
	return (data and (data.DiskGlowColor or data.GlowColor)) or Color3.fromRGB(120, 160, 255)
end

local function serverElapsed(plan)
	return workspace:GetServerTimeNow() - plan.startTime
end

-- Cooldown belongs to each black hole, not to the player.
local function cooldownRemaining(hole)
	if not hole or remotes:GetAttribute("DebugNoCooldown") == true then return 0 end
	return math.max((tonumber(hole:GetAttribute("AttackCooldownUntil")) or 0) - os.time(), 0)
end

local function heldHole()
	for _, hole in ipairs(CollectionService:GetTagged(TAG)) do
		if hole:GetAttribute("HeldBy") == player.UserId
			and tonumber(hole:GetAttribute("OwnerUserId")) == player.UserId then
			return hole
		end
	end
	return nil
end

local function ownerOfPlate(plate)
	local id = tonumber(plate:GetAttribute("OwnerUserId"))
	return id and Players:GetPlayerByUserId(id) or nil
end

local function make(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function text(parent, props)
	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextScaled = true,
		Text = props.Text or "",
		TextColor3 = props.Color or TEXT,
		TextXAlignment = props.AlignX or Enum.TextXAlignment.Center,
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Position = props.Position,
		Size = props.Size,
		ZIndex = props.ZIndex or 3,
	}, parent)
	if props.Max then
		make("UITextSizeConstraint", { MaxTextSize = props.Max }, label)
	end
	if props.Stroke then
		make("UIStroke", {
			Thickness = props.Stroke,
			Color = NAVY,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}, label)
	end
	return label
end

local function autoScale(guiObject)
	local scale = make("UIScale", {}, guiObject)
	local function refresh()
		local vp = camera.ViewportSize
		if vp.X < 1 then return end
		scale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.55, 1)
			* math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 1, 1.6)   -- grows past 1080p
	end
	refresh()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
end

local function statusColor(status)
	if status == "own" then return COLORS.Own end
	if status == "locked" or status == "rebuilding" or status == "closed" then return COLORS.Locked end
	if status == "busy" then return COLORS.Busy end
	if status == "empty" or status == "destroyed" then return COLORS.Empty end
	if status == "world" then return COLORS.World end
	return COLORS.Attackable
end

local function findWorldModel(targetId)
	for _, model in ipairs(WorldTargetClient.GetModels()) do
		if model:GetAttribute("WT_Id") == targetId then return model end
	end
	return nil
end

-- ===================== HUD / CONTROLS =====================
local HUD_NAMES = {
	"MainHUD", "BlackHoleActionUI", "SettingsHUD", "CosmicIndexHUD",
	"BlackHoleIncomeSourceUI", "BaseProtectedToast", "HudStack",
}
local hiddenHud = {}

local function hideHud()
	for _, name in ipairs(HUD_NAMES) do
		local screen = playerGui:FindFirstChild(name)
		if screen and screen:IsA("ScreenGui") and screen.Enabled then
			hiddenHud[screen] = true
			screen.Enabled = false
		end
	end
end

local function restoreHud()
	for screen in pairs(hiddenHud) do
		if screen.Parent then screen.Enabled = true end
	end
	table.clear(hiddenHud)
end

local savedLabelMode = nil

local function suppressLabels()
	if not (Settings and Settings.Get and Settings.Set) or savedLabelMode ~= nil then return end
	savedLabelMode = Settings.Get("LabelMode")
	if savedLabelMode ~= "Off" then
		Settings.Set("LabelMode", "Off", true)
	end
end

local function restoreLabels()
	if savedLabelMode == nil then return end
	if savedLabelMode ~= "Off" and Settings then
		Settings.Set("LabelMode", savedLabelMode, true)
	end
	savedLabelMode = nil
end

local controls = nil
task.spawn(function()
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	end)
	if ok and module then controls = module:GetControls() end
end)

local function setControls(enabled)
	if not controls then return end
	pcall(function()
		if enabled then controls:Enable() else controls:Disable() end
	end)
end

-- ===================== CAMERA =====================
local cam = { keys = nil, start = 0, duration = 1, easing = nil, onDone = nil, done = true, hold = nil, shake = 0 }

local function catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (p2 - p0) * t
		+ (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
		+ (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

local function evaluate(keys, t)
	local n = #keys
	if t <= keys[1].t then return keys[1].pos, keys[1].look, keys[1].fov end
	if t >= keys[n].t then return keys[n].pos, keys[n].look, keys[n].fov end

	for i = 1, n - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b.t then
			local u = (t - a.t) / math.max(b.t - a.t, 1e-4)
			local k0 = keys[math.max(i - 1, 1)]
			local k3 = keys[math.min(i + 2, n)]
			local smooth = u * u * (3 - 2 * u)
			return catmull(k0.pos, a.pos, b.pos, k3.pos, u),
				catmull(k0.look, a.look, b.look, k3.look, u),
				a.fov + (b.fov - a.fov) * smooth
		end
	end
	return keys[n].pos, keys[n].look, keys[n].fov
end

local function easeInOut(t)
	t = math.clamp(t, 0, 1)
	return if t < 0.5 then 4 * t * t * t else 1 - (-2 * t + 2) ^ 3 / 2
end

local function playPath(keys, duration, easing, onDone)
	camera.CameraType = Enum.CameraType.Scriptable
	cam.keys = keys
	cam.start = os.clock()
	cam.duration = math.max(duration, 0.01)
	cam.easing = easing
	cam.onDone = onDone
	cam.done = false
	cam.hold = nil
end

local function holdAt(pos, look, fov)
	camera.CameraType = Enum.CameraType.Scriptable
	cam.keys = nil
	cam.hold = { pos = pos, look = look, fov = fov, start = os.clock() }
end

local function addShake(amount)
	cam.shake = math.max(cam.shake, amount)
end

local function restoreCamera()
	cam.keys, cam.hold, cam.shake = nil, nil, 0
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then camera.CameraSubject = humanoid end
	camera.FieldOfView = originalFov
end

RunService:BindToRenderStep("BaseAttackCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if state == "idle" then return end

	local pos, look, fov
	if cam.keys then
		local raw = math.clamp((os.clock() - cam.start) / cam.duration, 0, 1)
		local t = if cam.easing == "inout" then easeInOut(raw) else raw
		pos, look, fov = evaluate(cam.keys, t)
		if raw >= 1 and not cam.done then
			cam.done = true
			local callback = cam.onDone
			cam.onDone = nil
			if callback then task.spawn(callback) end
		end
	elseif cam.hold then
		local h = cam.hold
		local s = os.clock() - h.start
		pos = h.pos + Vector3.new(math.sin(s * 0.35) * 1.5, math.sin(s * 0.5) * 0.8, math.cos(s * 0.3) * 1.5)
		look, fov = h.look, h.fov
	else
		return
	end

	if cam.shake > 0.01 then
		pos += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * cam.shake
		cam.shake *= math.exp(-dt * 6)
	end

	camera.CFrame = CFrame.lookAt(pos, look)
	camera.FieldOfView = fov
end)

-- ===================== UI =====================
local old = playerGui:FindFirstChild("BaseAttackHUD")
if old then old:Destroy() end
local oldTags = playerGui:FindFirstChild("BaseAttackTags")
if oldTags then oldTags:Destroy() end
local oldAnchors = workspace:FindFirstChild("BaseAttackTagAnchors")
if oldAnchors then oldAnchors:Destroy() end

local gui = make("ScreenGui", {
	Name = "BaseAttackHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 95,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local tagFolder = make("Folder", { Name = "BaseAttackTags" }, playerGui)
local tagAnchorFolder = make("Folder", { Name = "BaseAttackTagAnchors" }, workspace)

-- Banner
local banner = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 22),
	Size = UDim2.fromOffset(680, 80),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
GuiStyle.Corner(banner, 0.3)
GuiStyle.Stroke(banner, RIM, 3)
autoScale(banner)

local bannerTitle = text(banner, {
	Position = UDim2.fromOffset(22, 8), Size = UDim2.new(1, -170, 0, 38),
	AlignX = Enum.TextXAlignment.Left, Max = 30, Stroke = 3,
})
local bannerSub = text(banner, {
	Position = UDim2.fromOffset(22, 46), Size = UDim2.new(1, -170, 0, 22),
	AlignX = Enum.TextXAlignment.Left, Max = 16, Color = TEXT_DIM,
})

local cancelButton = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.5, 0),
	Size = UDim2.fromOffset(124, 50),
	BackgroundColor3 = GuiStyle.COL.X,
	AutoButtonColor = false,
	Font = FONT,
	Text = "CANCEL",
	TextScaled = true,
	TextColor3 = TEXT,
}, banner)
GuiStyle.Corner(cancelButton, 0.3)
GuiStyle.Stroke(cancelButton, GuiStyle.COL.XBorder, 3)
GuiStyle.TextStroke(cancelButton, 2.5)
make("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }, cancelButton)

local bannerToken = 0

local function showBanner(title, sub)
	bannerToken += 1
	bannerTitle.Text = title
	bannerSub.Text = sub or ""
	bannerSub.TextColor3 = TEXT_DIM
	cancelButton.Visible = state == "overhead" or state == "charging"
	banner.Visible = true
end

local function hideBanner()
	bannerToken += 1
	banner.Visible = false
end

local function flashBanner(message)
	bannerToken += 1
	local token = bannerToken
	bannerSub.Text = message
	bannerSub.TextColor3 = COLORS.Busy
	task.delay(2.2, function()
		if bannerToken == token and state == "overhead" then
			bannerSub.Text = DEFAULT_SUB
			bannerSub.TextColor3 = TEXT_DIM
		end
	end)
end

-- Hover card
local hoverCard = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Size = UDim2.fromOffset(250, 176),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
GuiStyle.Corner(hoverCard, 0.12)
local hoverStroke = GuiStyle.Stroke(hoverCard, COLORS.Attackable, 3)
autoScale(hoverCard)

local hoverAvatar = make("ImageLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(56, 56),
	BackgroundColor3 = Color3.fromRGB(22, 34, 78),
	BorderSizePixel = 0,
	ZIndex = 3,
}, hoverCard)
GuiStyle.Corner(hoverAvatar, 1)
local hoverAvatarStroke = GuiStyle.Stroke(hoverAvatar, RIM, 2)
local hoverIcon = text(hoverAvatar, {
	Text = "★", Position = UDim2.fromScale(0.15, 0.1), Size = UDim2.fromScale(0.7, 0.75),
	Color = COLORS.World, Stroke = 2, ZIndex = 4,
})
hoverIcon.Visible = false

local hoverName = text(hoverCard, { Position = UDim2.new(0, 10, 0, 72), Size = UDim2.new(1, -20, 0, 24), Max = 20, Stroke = 2 })
local hoverPower = text(hoverCard, { Position = UDim2.new(0, 10, 0, 98), Size = UDim2.new(1, -20, 0, 20), Max = 16, Stroke = 2, Color = GOLD })
local hoverReward = text(hoverCard, { Position = UDim2.new(0, 10, 0, 120), Size = UDim2.new(1, -20, 0, 18), Max = 15, Stroke = 2, Color = GREEN })
local hoverStatus = text(hoverCard, { Position = UDim2.new(0, 10, 0, 144), Size = UDim2.new(1, -20, 0, 22), Max = 17, Stroke = 2 })

-- Attack tag
local attackTag = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 22),
	Size = UDim2.fromOffset(460, 46),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
GuiStyle.Corner(attackTag, 1)
local attackTagStroke = GuiStyle.Stroke(attackTag, COLORS.Attackable, 3)
autoScale(attackTag)
local attackTagText = text(attackTag, { Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 1, -16), Max = 22, Stroke = 2.5 })

local function showAttackTag(plan)
	if plan.targetType == "World" then
		attackTagText.Text = "CONSUMING THE " .. string.upper(tostring(plan.targetName))
		attackTagStroke.Color = COLORS.World
	else
		attackTagText.Text = "CONSUMING  " .. string.upper(tostring(plan.targetName)) .. "'S BASE"
		attackTagStroke.Color = COLORS.Attackable
	end
	attackTag.Visible = true
end

local function hideAttackTag()
	attackTag.Visible = false
end

-- Island attacks never take the camera, so results arrive as a short pill
-- above the carry card instead of a full screen summary.
local toast = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -196),
	Size = UDim2.fromOffset(430, 44),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
GuiStyle.Corner(toast, 1)
local toastStroke = GuiStyle.Stroke(toast, COLORS.World, 3)
autoScale(toast)
local toastText = text(toast, { Position = UDim2.fromOffset(14, 7), Size = UDim2.new(1, -28, 1, -14), Max = 20, Stroke = 2.5 })
local toastScale = make("UIScale", {}, toast)
local toastToken = 0

local function showToast(message, color, seconds)
	toastToken += 1
	local token = toastToken
	toastText.Text = message
	toastStroke.Color = color or COLORS.World
	toast.Visible = true
	toastScale.Scale = 0.85
	TweenService:Create(toastScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	task.delay(seconds or 3, function()
		if toastToken == token then toast.Visible = false end
	end)
end

-- Victim warning
local warning = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 96),
	Size = UDim2.fromOffset(540, 54),
	BackgroundColor3 = Color3.fromRGB(120, 20, 34),
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
GuiStyle.Corner(warning, 0.4)
GuiStyle.Stroke(warning, COLORS.Busy, 3)
autoScale(warning)
local warningText = text(warning, { Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 1, -16), Max = 24, Stroke = 2.5 })
local warningToken = 0

local function showWarning(attackerName)
	warningToken += 1
	local token = warningToken
	warningText.Text = "⚠ " .. string.upper(tostring(attackerName)) .. " IS CONSUMING YOUR BASE!"
	warning.Visible = true
	task.delay(4, function()
		if warningToken == token then warning.Visible = false end
	end)
end

-- Summary
local summaryWrap = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(440, 330),
	BackgroundTransparency = 1,
	Visible = false,
}, gui)
autoScale(summaryWrap)

local summary = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
}, summaryWrap)
GuiStyle.Corner(summary, 0.06)
local summaryStroke = GuiStyle.Stroke(summary, RIM, 3)
local summaryPop = make("UIScale", {}, summary)

local summaryTitle = text(summary, { Text = "ATTACK COMPLETE", Position = UDim2.new(0, 20, 0, 18), Size = UDim2.new(1, -40, 0, 42), Max = 34, Stroke = 3 })
local summaryTarget = text(summary, { Position = UDim2.new(0, 20, 0, 60), Size = UDim2.new(1, -40, 0, 22), Max = 17, Color = TEXT_DIM })

local function summaryRow(y, color)
	local label = text(summary, {
		Position = UDim2.new(0, 28, 0, y), Size = UDim2.new(0.55, -28, 0, 26),
		AlignX = Enum.TextXAlignment.Left, Max = 19, Color = TEXT_DIM,
	})
	local value = text(summary, {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -28, 0, y), Size = UDim2.new(0.45, -28, 0, 26),
		AlignX = Enum.TextXAlignment.Right, Max = 21, Color = color or TEXT, Stroke = 2,
	})
	return { label = label, value = value }
end

local rowA = summaryRow(100, TEXT)
local rowB = summaryRow(136, GOLD)
local rowC = summaryRow(172, GREEN)
local rowD = summaryRow(208, GREEN)

local returnButton = make("TextButton", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.new(1, -48, 0, 54),
	BackgroundColor3 = GuiStyle.COL.Green,
	AutoButtonColor = false,
	Font = FONT,
	Text = "RETURN",
	TextScaled = true,
	TextColor3 = TEXT,
}, summary)
GuiStyle.Corner(returnButton, 0.28)
GuiStyle.Stroke(returnButton, GuiStyle.COL.GreenDark, 3)
GuiStyle.TextStroke(returnButton, 3)
make("UIPadding", { PaddingTop = UDim.new(0, 11), PaddingBottom = UDim.new(0, 11) }, returnButton)

local summaryToken = 0

local function setRow(row, label, value, visible)
	row.label.Text = label
	row.value.Text = value
	row.label.Visible = visible ~= false
	row.value.Visible = visible ~= false
end

local function fillSummary(plan)
	local data = finishedData[plan.id]
	summaryTarget.Text = "vs " .. tostring(plan.targetName)

	if plan.targetType == "World" then
		local destroyed = data and data.destroyed and plan.fatal
		summaryTitle.Text = if destroyed then "★ TARGET DESTROYED ★" else "ATTACK COMPLETE"
		summaryTitle.TextColor3 = if destroyed then COLORS.World else TEXT
		summaryStroke.Color = COLORS.World

		local model = findWorldModel(plan.targetId)
		local healthText = "—"
		if model then
			local stateNow = model:GetAttribute("WT_State")
			healthText = if stateNow ~= "Alive" then "DESTROYED"
				else Format.Abbreviate(model:GetAttribute("WT_Health") or 0)
				.. " / " .. Format.Abbreviate(model:GetAttribute("WT_MaxHealth") or 0)
		end

		local bonus = data and data.bonus or 0
		setRow(rowA, "Damage Dealt", Format.Abbreviate(if data then data.damage else plan.damage) .. " HP")
		setRow(rowB, "Health Left", healthText)
		setRow(rowC, "Stardust Earned", "★" .. Format.Abbreviate(data and data.gained or 0))
		setRow(rowD, "Destroy Bonus", "★" .. Format.Abbreviate(bonus), bonus > 0)
	else
		summaryTitle.Text = "ATTACK COMPLETE"
		summaryTitle.TextColor3 = TEXT
		summaryStroke.Color = RIM

		local stolen = data and data.stolen or 0
		local absorbedText = tostring(if data then data.absorbed else #plan.objects)
		if data and (data.damaged or 0) > 0 then
			absorbedText ..= "  (+" .. data.damaged .. " damaged)"
		end
		setRow(rowA, "Objects Absorbed", absorbedText)
		setRow(rowB, "Power Consumed", "★" .. Format.Abbreviate(if data then data.powerConsumed else plan.totalPower) .. "/s")
		setRow(rowC, "Stardust Earned", "★" .. Format.Abbreviate(if data then data.gained else plan.totalGain))
		setRow(rowD, "Stardust Stolen", "★" .. Format.Abbreviate(stolen), stolen > 0)
	end
end

local function hideSummary()
	summaryToken += 1
	summaryWrap.Visible = false
end

local function showFloating(position, message)
	local anchor = make("Part", {
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		Transparency = 1, Size = Vector3.one * 0.2,
		CFrame = CFrame.new(position + Vector3.new((math.random() - 0.5) * 10, -6 + math.random() * 5, (math.random() - 0.5) * 10)),
	}, workspace)

	local billboard = make("BillboardGui", {
		Adornee = anchor, Size = UDim2.fromOffset(240, 52),
		AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 2000, ResetOnSpawn = false,
	}, anchor)

	local label = text(billboard, { Text = message, Position = UDim2.new(), Size = UDim2.fromScale(1, 1), Color = GOLD, Stroke = 3 })

	TweenService:Create(anchor, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = anchor.CFrame + Vector3.new(0, 8, 0) }):Play()
	task.delay(0.7, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play() end
		end
	end)
	Debris:AddItem(anchor, 1.4)
end

-- ===================== INDICATORS =====================
local function clearIndicators()
	for key, entry in pairs(indicators) do
		entry.ring:Destroy()
		entry.tag:Destroy()
		if entry.tagAnchor then entry.tagAnchor:Destroy() end
		if entry.kind == "world" then
			WorldTargetClient.SetFocus(key:GetAttribute("WT_Id"), false)
		end
	end
	table.clear(indicators)
	indicatorsVisible = false
end

local function makeRing()
	return make("CylinderHandleAdornment", {
		Name = "TargetRing",
		Adornee = workspace.Terrain,
		Height = 0.8,
		Radius = 1,
		InnerRadius = 0.9,
		Transparency = 1,
		Color3 = COLORS.Attackable,
		Visible = false,
	}, workspace.Terrain)
end

local function makeTag(adornee, offsetY, width)
	local tag = make("BillboardGui", {
		Name = "TargetTag",
		Adornee = adornee,
		Size = UDim2.fromOffset(width, 34),
		StudsOffset = Vector3.new(0, offsetY, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 5000,
		Enabled = false,
		ResetOnSpawn = false,
	}, tagFolder)

	local pill = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}, tag)
	GuiStyle.Corner(pill, 1)
	local stroke = GuiStyle.Stroke(pill, COLORS.Own, 2)
	local label = text(pill, { Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 1, -8), Max = 18, Stroke = 2 })
	return tag, label, stroke
end

local function buildIndicators()
	clearIndicators()

	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("BasePart")
			and instance.Name:lower():find("plate", 1, true)
			and not CollectionService:HasTag(instance, TAG) then
			local owner = ownerOfPlate(instance)
			if owner then
				local tag, tagText, tagStroke = makeTag(instance, 10, 150)
				indicators[instance] = {
					kind = "plate", ring = makeRing(), tag = tag, tagText = tagText, tagStroke = tagStroke,
					owner = owner, status = "attackable", total = 0, eligible = 0, reward = 0,
				}
			end
		end
	end

	for _, model in ipairs(WorldTargetClient.GetModels()) do
		local info = WorldTargetClient.InfoFor(model)
		local anchor = make("Part", {
			Name = "WorldTagAnchor", Anchored = true, CanCollide = false, CanQuery = false,
			CanTouch = false, Transparency = 1, Size = Vector3.one * 0.2,
			CFrame = CFrame.new(info.top),
		}, tagAnchorFolder)
		local tag, tagText, tagStroke = makeTag(anchor, 14, 220)
		indicators[model] = {
			kind = "world", ring = makeRing(), tag = tag, tagText = tagText, tagStroke = tagStroke,
			tagAnchor = anchor, info = info, status = "world", damage = 0,
		}
	end
end

local function plateStatus(owner)
	if owner == player then return "own" end
	if (tonumber(owner:GetAttribute("BaseLockedUntil")) or 0) > os.time() then return "locked" end
	if owner:GetAttribute("UnderAttackBy") ~= nil then return "busy" end
	return "attackable"
end

local function worldStatus(info)
	local status = WorldTargetClient.StatusFor(info)
	if status == "Destroyed" then return "destroyed" end
	if status == "Rebuilding" then return "rebuilding" end
	if status == "Closed" then return "closed" end
	local config = Config.WorldTargets[info.id]
	if config and info.activeAttacks >= (config.MaxConcurrentAttacks or 1) then return "busy" end
	return "world"
end

local function estimateForPlate(owner)
	local maxTier = attackerTier + Config.Rules.MaxTierAbove
	local attackerPower = attackerHole and (tonumber(attackerHole:GetAttribute("StellarPower")) or 0) or 0
	local total, eligible, rewardSum = 0, 0, 0

	for _, hole in ipairs(CollectionService:GetTagged(TAG)) do
		if tonumber(hole:GetAttribute("OwnerUserId")) == owner.UserId then
			local power = tonumber(hole:GetAttribute("StellarPower")) or 0
			total += power
			local held = hole:GetAttribute("HeldBy")
			if (held == nil or held == 0)
				and (tonumber(hole:GetAttribute("Tier")) or 1) <= maxTier
				and not hole:GetAttribute("BeingConsumed")
				and not hole:GetAttribute("Defeated") then
				-- Same formulas the server uses, from the replicated health.
				local maxHealth = tonumber(hole:GetAttribute("MaxHealth"))
					or Config.HoleMaxHealth(tonumber(hole:GetAttribute("Tier")) or 1)
				local health = tonumber(hole:GetAttribute("Health")) or maxHealth
				local applied = math.min(Config.HoleDamageFor(attackerTier, maxHealth), health)
				eligible += 1
				rewardSum += Config.HoleHitReward(power, attackerPower, applied, maxHealth)
			end
		end
	end

	-- Targets are random, so expect the average hit, times the number of hits.
	local count = math.min(Config.ConsumeCountFor(attackerTier), eligible)
	local average = if eligible > 0 then rewardSum / eligible else 0
	return total, eligible, math.floor(average * count)
end

local function entryCenter(key, entry)
	if entry.kind == "world" then return entry.info.base end
	return key.Position + Vector3.new(0, key.Size.Y * 0.5, 0)
end

local function entryRadius(key, entry)
	if entry.kind == "world" then return entry.info.radius * 1.35 end
	return math.max(key.Size.X, key.Size.Z) * 0.5
end

local avatarCache = {}

local function setHovered(key)
	if hoveredKey == key then return end
	hoveredKey = if key and indicators[key] then key else nil

	if not hoveredKey then
		hoverCard.Visible = false
		return
	end

	local entry = indicators[hoveredKey]

	if entry.kind == "world" then
		hoverIcon.Visible = true
		hoverAvatar.Image = ""
		hoverAvatarStroke.Color = COLORS.World
		hoverName.Text = string.upper(entry.info.name)
	else
		hoverIcon.Visible = false
		hoverAvatarStroke.Color = RIM
		local owner = entry.owner
		local userId = owner.UserId
		hoverName.Text = owner.DisplayName
		hoverAvatar.Image = avatarCache[userId] or ""

		if not avatarCache[userId] then
			task.spawn(function()
				local ok, content = pcall(function()
					return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
				end)
				if ok and content then
					avatarCache[userId] = content
					local current = hoveredKey and indicators[hoveredKey]
					if current and current.kind == "plate" and current.owner.UserId == userId then
						hoverAvatar.Image = content
					end
				end
			end)
		end
	end

	VFX.PlaySound("Ui", camera.CFrame.Position)
end

local function refreshStatuses()
	for key, entry in pairs(indicators) do
		local gone = not key.Parent or (entry.kind == "plate" and not entry.owner.Parent)
		if gone then
			entry.ring:Destroy()
			entry.tag:Destroy()
			if entry.tagAnchor then entry.tagAnchor:Destroy() end
			indicators[key] = nil
			if hoveredKey == key then setHovered(nil) end
		elseif entry.kind == "world" then
			entry.info = WorldTargetClient.InfoFor(key)
			entry.status = worldStatus(entry.info)
			entry.damage = WorldTargetClient.EstimateDamage(key, attackerTier)
			entry.tagAnchor.CFrame = CFrame.new(entry.info.top)
			entry.tag.Enabled = indicatorsVisible

			local wstatus, wleft = WorldTargetClient.StatusFor(entry.info)
			entry.tagText.Text = if wstatus == "Open" then entry.info.title .. "  " .. formatClock(wleft)
				elseif wstatus == "Closed" then "EVENT IN  " .. formatClock(wleft)
				elseif wstatus == "Destroyed" then "DESTROYED"
				else entry.info.title
			entry.tagStroke.Color = statusColor(entry.status)
			entry.tagText.TextColor3 = if entry.status == "world" then COLORS.World else TEXT
			WorldTargetClient.SetFocus(entry.info.id, indicatorsVisible)
		else
			local status = plateStatus(entry.owner)
			entry.total, entry.eligible, entry.reward = estimateForPlate(entry.owner)
			if status == "attackable" and entry.eligible == 0 then
				status = "empty"
			end
			entry.status = status
			entry.tag.Enabled = indicatorsVisible and (status == "own" or status == "locked")
			entry.tagText.Text = if status == "own" then "YOUR BASE" else "🛡 LOCKED"
			entry.tagStroke.Color = statusColor(status)
		end
	end
end

local function setIndicatorsVisible(visible)
	indicatorsVisible = visible
	refreshStatuses()
end

local function isSelectable(entry)
	return entry.status == "attackable" or entry.status == "world"
end

local function drawIndicators()
	local pulse = 0.5 + 0.5 * math.sin(os.clock() * 16)
	for key, entry in pairs(indicators) do
		if not indicatorsVisible then
			entry.ring.Visible = false
		else
			local hovered = key == hoveredKey
			local world = entry.kind == "world"
			local radius = entryRadius(key, entry) * (if hovered then 1.1 else 1.05)
			local transparency = if hovered then 0.05
				elseif isSelectable(entry) then (if world then 0.25 else 0.4)
				else 0.62
			if state == "locking" and key == lockedKey then
				transparency = 0.05 + 0.5 * pulse
			end

			entry.ring.Visible = true
			entry.ring.Color3 = statusColor(entry.status)
			entry.ring.Radius = radius
			entry.ring.InnerRadius = radius * (if hovered or world then 0.86 else 0.93)
			entry.ring.Transparency = transparency
			entry.ring.CFrame = CFrame.new(entryCenter(key, entry) + Vector3.new(0, 0.4, 0))
				* CFrame.Angles(math.rad(90), 0, 0)
		end
	end
end

-- World targets first (their box can overlap the ground plane), then plates.
local function targetUnderRay(ray)
	local model = WorldTargetClient.TargetUnderRay(ray)
	if model and indicators[model] then return model end

	local best, bestDistance = nil, math.huge
	for key, entry in pairs(indicators) do
		if entry.kind == "plate" then
			local top = key.Position.Y + key.Size.Y * 0.5
			if math.abs(ray.Direction.Y) > 1e-4 then
				local t = (top - ray.Origin.Y) / ray.Direction.Y
				if t > 0 and t < bestDistance then
					local hit = ray.Origin + ray.Direction * t
					local localPoint = key.CFrame:PointToObjectSpace(Vector3.new(hit.X, key.Position.Y, hit.Z))
					if math.abs(localPoint.X) <= key.Size.X * 0.55 and math.abs(localPoint.Z) <= key.Size.Z * 0.55 then
						best, bestDistance = key, t
					end
				end
			end
		end
	end
	return best
end

local function updateHoverCard()
	local key = hoveredKey
	local entry = key and indicators[key]
	if not entry then
		hoverCard.Visible = false
		return
	end

	local anchorPoint = if entry.kind == "world"
		then entry.info.top + Vector3.new(0, 4, 0)
		else key.Position + Vector3.new(0, key.Size.Y * 0.5 + 6, 0)

	local screen, onScreen = camera:WorldToViewportPoint(anchorPoint)
	if not onScreen then
		hoverCard.Visible = false
		return
	end

	local vp = camera.ViewportSize
	hoverCard.Visible = true
	hoverCard.Position = UDim2.fromOffset(math.clamp(screen.X, 135, vp.X - 135), math.clamp(screen.Y - 20, 200, vp.Y - 10))

	local status = entry.status
	local color = statusColor(status)
	hoverStroke.Color = color
	hoverStatus.TextColor3 = color
	hoverReward.Text = ""

	if entry.kind == "world" then
		local info = entry.info
		hoverPower.Text = if info.state == "Alive"
			then "HP  " .. Format.Abbreviate(info.health) .. " / " .. Format.Abbreviate(info.maxHealth)
			else "HP  0 / " .. Format.Abbreviate(info.maxHealth)

		local _, eventLeft = WorldTargetClient.StatusFor(info)

		if state == "locking" and key == lockedKey then
			hoverStatus.Text = "LAUNCHING…"
		elseif status == "world" then
			hoverReward.Text = "YOUR DAMAGE  " .. Format.Abbreviate(entry.damage)
				.. "  •  EVENT " .. formatClock(eventLeft)
			hoverStatus.Text = if UiResponsive and UiResponsive.IsGamepad() then "PRESS A TO ATTACK"
				elseif UserInputService.MouseEnabled then "CLICK TO ATTACK" else "TAP AGAIN TO ATTACK"
		elseif status == "closed" then
			hoverStatus.Text = "EVENT IN  " .. formatClock(eventLeft)
		elseif status == "destroyed" then
			hoverStatus.Text = if eventLeft > 0 then "NEXT EVENT  " .. formatClock(eventLeft) else "DESTROYED"
		elseif status == "rebuilding" then
			hoverStatus.Text = "REBUILDING…"
		else
			hoverStatus.Text = info.attackers .. " ATTACKING — FULL"
		end
		return
	end

	hoverPower.Text = "★ POWER  " .. Format.Abbreviate(entry.total) .. "/s"

	if state == "locking" and key == lockedKey then
		hoverStatus.Text = "LOCKING TARGET…"
	elseif status == "attackable" then
		hoverReward.Text = "REWARD ≈ ★" .. Format.Abbreviate(entry.reward)
		hoverStatus.Text = if UiResponsive and UiResponsive.IsGamepad() then "PRESS A TO ATTACK"
			elseif UserInputService.MouseEnabled then "CLICK TO ATTACK" else "TAP AGAIN TO ATTACK"
	elseif status == "locked" then
		local left = (tonumber(entry.owner:GetAttribute("BaseLockedUntil")) or 0) - os.time()
		hoverStatus.Text = "🛡 LOCKED  " .. formatClock(left)
	elseif status == "own" then
		hoverStatus.Text = "YOUR BASE"
	elseif status == "busy" then
		hoverStatus.Text = "UNDER ATTACK"
	else
		hoverStatus.Text = "NOTHING TO CONSUME"
	end
end

local function overheadFrame()
	local sum, count = Vector3.zero, 0
	for key, entry in pairs(indicators) do
		sum += entryCenter(key, entry)
		count += 1
	end

	if count == 0 then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local p = if root then root.Position else Vector3.zero
		return p + Vector3.new(0, 160, 50), p
	end

	local centroid = sum / count
	local radius = 0
	for key, entry in pairs(indicators) do
		local center = entryCenter(key, entry)
		local flat = Vector3.new(center.X - centroid.X, 0, center.Z - centroid.Z).Magnitude
		radius = math.max(radius, flat + entryRadius(key, entry))
	end

	local c = Config.Camera
	local height = math.clamp(radius * c.OverheadHeightPerRadius, c.OverheadMinHeight, c.OverheadMaxHeight)
	return centroid + Vector3.new(0, height, height * math.max(c.OverheadTilt, 0.05)), centroid
end

-- ===================== CHARGE FX =====================
local chargeCleanup = {}

local function stopChargeFx()
	for _, cleanup in ipairs(chargeCleanup) do
		pcall(cleanup)
	end
	table.clear(chargeCleanup)
end

local function startChargeFx(hole)
	stopChargeFx()
	local tier = tonumber(hole:GetAttribute("Tier")) or 1
	local color = glowFor(tier)
	local model = VFX.FindVisualModel(SizeVariants.WorldCenter(hole), 8)

	local highlight = make("Highlight", {
		Name = "LaunchHighlight",
		Adornee = model or hole,
		FillColor = color,
		OutlineColor = color,
		FillTransparency = 0.85,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
	}, workspace)
	local pulse = TweenService:Create(highlight,
		TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ FillTransparency = 0.45 })
	pulse:Play()
	table.insert(chargeCleanup, function()
		pulse:Cancel()
		highlight:Destroy()
	end)

	local visual = SizeVariants.Diameter(hole)
	local field = VFX.CreatePullField(function()
		return if hole.Parent then SizeVariants.WorldCenter(hole) else nil
	end, math.max(visual * 1.6, 6), color, qualityKey())
	table.insert(chargeCleanup, field.Destroy)

	VFX.PlaySound("Charge", SizeVariants.WorldCenter(hole))
end

-- ===================== PLAYER BASE SEQUENCE =====================
local function geometryFor(plan)
	local size = plan.targetSize
	local width = math.max(size.X, size.Z)
	local visual = Config.Visual
	local apexHeight = math.clamp(width * visual.ApexHeightShare, visual.ApexMin, visual.ApexMax)
	local base = plan.targetPosition
	local apex = base + Vector3.new(0, apexHeight, 0)

	local back = Vector3.new(plan.originPosition.X - base.X, 0, plan.originPosition.Z - base.Z)
	back = if back.Magnitude > 1 then back.Unit else Vector3.zAxis

	return {
		width = width,
		half = width * 0.5,
		apexHeight = apexHeight,
		base = base,
		apex = apex,
		highSky = apex + Vector3.new(0, apexHeight * 0.6, 0),
		projectionSize = math.clamp(width * visual.ProjectionSizeShare, visual.ProjectionMin, visual.ProjectionMax),
		back = back,
		side = Vector3.new(-back.Z, 0, back.X),
		origin = plan.originPosition,
	}
end

local function buildCinematicKeys(plan, g)
	local T = Config.Timing
	local d = plan.duration
	local absorbStart = plan.absorbStart
	local span = (d - T.Collapse) - absorbStart
	local from = camera.CFrame

	local function key(seconds, pos, look, fov)
		return { t = math.clamp(seconds / d, 0, 1), pos = pos, look = look, fov = fov or Config.Camera.DefaultFov }
	end

	return {
		key(0, from.Position, from.Position + from.LookVector * 60),
		key(T.Travel * 0.55, g.base + g.back * g.half * 3.2 + Vector3.new(0, g.apexHeight * 1.6, 0), g.highSky, 76),
		key(T.Travel + T.Arrival * 0.5, g.base + g.back * g.half * 1.15 + Vector3.new(0, 7, 0), g.highSky:Lerp(g.apex, 0.6), 78),
		key(absorbStart + span * 0.15, g.base + (g.back + g.side * 0.6).Unit * g.half * 2.2 + Vector3.new(0, g.apexHeight * 0.55, 0), g.base + Vector3.new(0, g.apexHeight * 0.4, 0), 72),
		key(absorbStart + span * 0.42, g.base + (g.side - g.back * 0.3).Unit * g.half * 1.05 + Vector3.new(0, 6, 0), g.base + Vector3.new(0, 5, 0), 66),
		key(absorbStart + span * 0.72, g.base + (g.side * 0.4 - g.back).Unit * g.half * 1.4 + Vector3.new(0, g.apexHeight * 0.5, 0), g.base + Vector3.new(0, g.apexHeight * 0.7, 0), 70),
		key(d, g.base + (g.back * 0.8 + g.side).Unit * g.half * 2.6 + Vector3.new(0, g.apexHeight * 0.9, 0), g.apex, 72),
	}
end

-- A shower of gold Stardust sparks bursting outwards when the attacker's
-- reward lands (one pooled emitter, moved to each impact).
local stardustBurst do
	local holder, emitter
	function stardustBurst(position, count)
		if not holder or not holder.Parent then
			holder = Instance.new("Part")
			holder.Name = "AttackStardustBurst"
			holder.Anchored = true
			holder.CanCollide = false
			holder.CanQuery = false
			holder.CanTouch = false
			holder.Transparency = 1
			holder.Size = Vector3.one * 0.2
			holder.Parent = workspace
			emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Enabled = false
			emitter.LightEmission = 1
			emitter.LightInfluence = 0
			emitter.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 190, 40))
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
			emitter.Lifetime = NumberRange.new(0.5, 0.9)
			emitter.Speed = NumberRange.new(18, 30)
			emitter.Drag = 4
			emitter.Acceleration = Vector3.new(0, -20, 0)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Parent = holder
		end
		holder.CFrame = CFrame.new(position)
		emitter:Emit(count)
	end
end

local function playBaseSequence(plan, isAttacker)
	local g = geometryFor(plan)
	local T = Config.Timing
	local quality = qualityKey()
	local fragmentCount = Config.Fragments[quality] or Config.Fragments.MODERATE
	local glow = glowFor(plan.attackerTier)
	local disk = diskFor(plan.attackerTier)

	local function at(seconds, callback)
		local delay = seconds - serverElapsed(plan)
		if delay < -0.75 then return end
		task.delay(math.max(delay, 0), callback)
	end

	local startSky = g.origin + Vector3.new(0, g.apexHeight * 1.2, 0)
	local projection = VFX.CreateProjection(plan.attackerTier, g.projectionSize, glow, quality, startSky, plan.attackerMutation)
	projection.SetScale(0.35, 0)
	projection.SetScale(1, T.Travel)
	projection.SetSpin(1.2)
	projection.Fly(startSky, g.highSky, T.Travel, g.apexHeight * 0.8)

	local column = nil

	at(T.Travel, function()
		projection.Fly(g.highSky, g.apex, T.Arrival * 0.7, 0)
		projection.SetSpin(2.4, 0.6)
		VFX.PlaySound("Charge", g.apex)
		if isAttacker then VFX.SetDarken(1, 0.8) end
	end)

	at(T.Travel + T.Arrival * 0.45, function()
		column = VFX.CreateColumn(g.base + Vector3.new(0, 0.3, 0), g.apex, g.half * 1.05, g.projectionSize * 0.16, disk, quality)
		column.SetIntensity(1, T.Arrival * 0.55)
		projection.Pulse(0.5)
	end)

	local lastImpact = 0

	for _, entry in ipairs(plan.objects) do
		local tier = tonumber(entry.tier) or 1
		local breakAt = plan.absorbStart + entry.at
		local waves = if tier > 32 then 3 elseif tier > 16 then 2 else 1
		local resist = if tier > 32 then 0.7 elseif tier > 24 then 0.4 else 0
		local extent = if entry.hole and entry.hole.Parent then SizeVariants.Diameter(entry.hole) else (tonumber(entry.extent) or 4)
		local visualPosition = if entry.hole and entry.hole.Parent then SizeVariants.WorldCenter(entry.hole) else entry.position
		local colors = { glowFor(tier), Color3.fromRGB(14, 12, 24) }
		-- Older plans (no health data) always break, as before.
		local fatal = entry.fatal ~= false
		local share = math.clamp((tonumber(entry.damage) or 0) / math.max(tonumber(entry.maxHealth) or 1, 1), 0, 1)

		at(breakAt - resist - 0.3, function()
			colors = VFX.SampleColors(visualPosition, extent + 4, colors)
			if resist > 0 then
				VFX.Tug(visualPosition, g.apex, colors[1], resist + 0.3, VFX.FindVisualModel(visualPosition, extent + 4))
			end
		end)

		at(breakAt, function()
			-- A surviving hole sheds a smaller stream sized by the damage it took;
			-- a defeated one breaks apart fully. Either way the stream ends in the core.
			local count = if fatal
				then math.floor(fragmentCount * (0.7 + 0.15 * waves))
				else math.max(math.floor(fragmentCount * 0.6 * share), 3)
			VFX.SpawnBreakup({
				position = visualPosition,
				extent = extent,
				colors = colors,
				count = count,
				waves = if fatal then waves else 1,
				axis = g.base,
				apex = g.apex,
				destination = projection.Destination,
				apexRadius = g.projectionSize * 0.12,
				duration = T.FragmentTravel,
				direction = 1,
				sizeScale = if fatal then 1 else 0.7,
			})
			if isAttacker then addShake(if fatal then 0.25 else 0.12) end
		end)

		local impactAt = breakAt + T.FragmentTravel * 0.95
		lastImpact = math.max(lastImpact, impactAt)

		at(impactAt, function()
			projection.Pulse((0.35 + math.min(tier / 48, 1) * 0.35) * (if fatal then 1 else 0.6))
			VFX.PlaySound("Impact", g.apex)
			-- Every hit sends a small cosmic ring out of the black hole, bigger
			-- for a defeated target.
			VFX.Shockwave(g.apex, g.half * (if fatal then 1.1 else 0.7), colors[1], 0.35)
			if isAttacker then
				addShake(0.5)
				showFloating(g.apex, "★ +" .. Format.Abbreviate(entry.gain or 0))
				stardustBurst(g.apex, if fatal then 22 else 12)
			end
		end)
	end

	at(lastImpact + 0.05, function()
		projection.Flare()
	end)

	at(plan.duration - T.Collapse, function()
		if column then column.Collapse(T.Collapse * 0.8) end
		projection.Collapse(T.Collapse)
		VFX.Shockwave(g.apex, g.half * 1.8, disk, 0.8)
		VFX.PlaySound("Collapse", g.apex)
		if isAttacker then
			addShake(1.4)
			local anyFatal = false
			for _, object in ipairs(plan.objects) do
				if object.fatal ~= false then anyFatal = true break end
			end
			showFloating(g.apex, if anyFatal then "★ ABSORBED" else "★ DAMAGED")
		end
	end)

	at(plan.duration + 0.3, function()
		projection.Destroy()
	end)
end

local function playSequence(plan, isAttacker)
	if plan.targetType == "World" then
		-- WorldTargetClient nudges the camera itself; it never takes control.
		WorldTargetClient.PlaySequence(plan, isAttacker)
	else
		playBaseSequence(plan, isAttacker)
	end
end

-- ===================== FLOW =====================
local function finishReturn()
	restoreCamera()
	restoreHud()
	restoreLabels()
	setControls(true)
	hideAttackTag()
	state = "idle"
	attackerHole = nil
	activePlan = nil
	pendingAttackId = nil
	lockedKey = nil
end

local function beginLaunch()
	if state ~= "idle" then
		return { ok = false, reason = "Attack already in progress." }
	end

	local hole = heldHole()
	if not hole then
		return { ok = false, reason = "Hold a black hole first." }
	end

	local remaining = cooldownRemaining(hole)
	if remaining > 0 then
		return { ok = false, reason = "This black hole recharges in " .. formatClock(remaining) }
	end

	attackerTier = tonumber(hole:GetAttribute("Tier")) or 1
	buildIndicators()

	local targets = 0
	for _, entry in pairs(indicators) do
		if entry.kind == "world" or entry.owner ~= player then
			targets += 1
		end
	end
	if targets == 0 then
		clearIndicators()
		return { ok = false, reason = "Nothing to attack right now." }
	end

	attackerHole = hole
	state = "charging"
	originalFov = camera.FieldOfView

	hideHud()
	suppressLabels()
	setControls(false)
	startChargeFx(hole)

	local from = camera.CFrame
	local holePosition = hole.Position
	local back = Vector3.new(from.Position.X - holePosition.X, 0, from.Position.Z - holePosition.Z)
	back = if back.Magnitude > 1 then back.Unit else Vector3.zAxis
	local overPos, overLook = overheadFrame()

	playPath({
		{ t = 0, pos = from.Position, look = from.Position + from.LookVector * 20, fov = originalFov },
		{ t = 0.3, pos = holePosition + back * 22 + Vector3.new(0, 10, 0), look = holePosition, fov = originalFov + 4 },
		{ t = 0.62, pos = holePosition + back * 40 + Vector3.new(0, 70, 0), look = holePosition:Lerp(overLook, 0.4), fov = Config.Camera.RiseFov },
		{ t = 1, pos = overPos, look = overLook, fov = Config.Camera.DefaultFov },
	}, Config.Timing.Charge + Config.Timing.Rise, "inout", enterOverhead)

	addShake(0.25)
	return { ok = true }
end

enterOverhead = function()
	if state ~= "charging" then return end
	state = "overhead"
	stopChargeFx()

	local overPos, overLook = overheadFrame()
	holdAt(overPos, overLook, Config.Camera.DefaultFov)
	setIndicatorsVisible(true)
	showBanner("CHOOSE A TARGET TO CONSUME", targetingHint())
	VFX.PlaySound("Ui", camera.CFrame.Position)
end

returnHome = function()
	state = "returning"
	local from = camera.CFrame
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")

	local endLook, endPos
	if root then
		endLook = root.Position + Vector3.new(0, 1.5, 0)
		endPos = endLook - root.CFrame.LookVector * 14 + Vector3.new(0, 6, 0)
	else
		endPos = from.Position
		endLook = from.Position + from.LookVector * 10
	end

	playPath({
		{ t = 0, pos = from.Position, look = from.Position + from.LookVector * 40, fov = camera.FieldOfView },
		{ t = 0.5, pos = endLook + Vector3.new(0, 90, 40), look = endLook, fov = Config.Camera.RiseFov },
		{ t = 1, pos = endPos, look = endLook, fov = originalFov },
	}, 1.7, "inout", function()
		if state == "returning" then finishReturn() end
	end)
end

cancelTargeting = function()
	if state ~= "overhead" and state ~= "charging" then return end
	stopChargeFx()
	setHovered(nil)
	clearIndicators()
	hideBanner()
	returnHome()
end

lockTarget = function(key)
	local entry = indicators[key]
	if state ~= "overhead" or not entry then return end

	if not isSelectable(entry) then
		flashBanner(REASONS[entry.status] or "You can't attack that.")
		return
	end

	if not attackerHole or not attackerHole.Parent
		or attackerHole:GetAttribute("HeldBy") ~= player.UserId then
		flashBanner("You're no longer holding a black hole.")
		return
	end

	state = "locking"
	lockedKey = key

	local isWorld = entry.kind == "world"
	local target, label, targetName
	if isWorld then
		target = "world:" .. tostring(entry.info.id)
		targetName = entry.info.name
		label = "Launching at the " .. targetName .. "…"
	else
		target = entry.owner.UserId
		label = "Launching at " .. entry.owner.DisplayName .. "'s base…"
	end

	showBanner("TARGET LOCKED", label)
	VFX.PlaySound("Ui", camera.CFrame.Position)

	local hole = attackerHole
	task.spawn(function()
		local ok, result = pcall(function()
			return requestAttack:InvokeServer(hole, target)
		end)
		if state ~= "locking" then return end

		if not ok or type(result) ~= "table" or not result.ok then
			state = "overhead"
			lockedKey = nil
			showBanner("CHOOSE A TARGET TO CONSUME", targetingHint())
			flashBanner((type(result) == "table" and result.reason) or "Attack failed.")
			return
		end

		pendingAttackId = result.attackId

		if isWorld then
			-- Island attacks hand control straight back. You watch it happen
			-- while you keep playing, and so does everyone else attacking it.
			setHovered(nil)
			clearIndicators()
			hideBanner()
			showToast("LAUNCHED AT " .. string.upper(tostring(targetName))
				.. "  •  RECHARGES IN " .. formatClock(result.cooldown or 0))
			returnHome()
			return
		end

		local plan = receivedPlans[pendingAttackId]
		if plan then runAttackerCinematic(plan) end
	end)
end

runAttackerCinematic = function(plan)
	if state ~= "locking" or activePlan then return end
	state = "cinematic"
	activePlan = plan

	setHovered(nil)
	clearIndicators()
	hideBanner()
	showAttackTag(plan)

	-- Player base attacks keep their cinematic. World targets never get one.
	local keys = buildCinematicKeys(plan, geometryFor(plan))

	playPath(keys, plan.duration, nil, nil)
	cam.start = os.clock() - serverElapsed(plan)

	playSequence(plan, true)

	task.delay(math.max(plan.duration - serverElapsed(plan), 0) + 0.25, function()
		showSummary(plan)
	end)
end

showSummary = function(plan)
	if state ~= "cinematic" or activePlan ~= plan then return end
	state = "summary"
	hideAttackTag()
	fillSummary(plan)

	summaryToken += 1
	local token = summaryToken
	summaryPop.Scale = 0.9
	summaryWrap.Visible = true
	TweenService:Create(summaryPop, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	VFX.PlaySound("Ui", camera.CFrame.Position)

	task.delay(Config.Timing.SummaryAutoClose, function()
		if summaryToken == token and state == "summary" then
			closeSummary()
		end
	end)
end

closeSummary = function()
	if state ~= "summary" then return end
	hideSummary()
	VFX.SetDarken(0, 0.6)
	returnHome()
end

local function forceReset()
	stopChargeFx()
	setHovered(nil)
	clearIndicators()
	hideBanner()
	hideSummary()
	VFX.SetDarken(0, 0.3)
	finishReturn()
end

-- ===================== INPUT =====================
cancelButton.Activated:Connect(function()
	cancelTargeting()
end)

returnButton.Activated:Connect(function()
	closeSummary()
end)

-- Gamepad: cycle through attackable targets left to right on screen.
local function cycleTarget(direction)
	local list = {}
	for key, entry in pairs(indicators) do
		if isSelectable(entry) then
			local screen, onScreen = camera:WorldToViewportPoint(entryCenter(key, entry))
			if onScreen then
				table.insert(list, { key = key, x = screen.X, y = screen.Y })
			end
		end
	end
	if #list == 0 then return end
	table.sort(list, function(a, b) return a.x < b.x end)

	local index = 0
	for i, item in ipairs(list) do
		if item.key == hoveredKey then index = i end
	end
	if index == 0 then
		local center = camera.ViewportSize * 0.5
		local bestDistance = math.huge
		for i, item in ipairs(list) do
			local distance = (Vector2.new(item.x, item.y) - center).Magnitude
			if distance < bestDistance then index, bestDistance = i, distance end
		end
	else
		index = ((index - 1 + direction) % #list) + 1
	end
	setHovered(list[index].key)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		if state == "overhead" or state == "charging" then
			cancelTargeting()
		elseif state == "summary" then
			closeSummary()
		end
		return
	end

	if state == "overhead" then
		local key = input.KeyCode
		if key == Enum.KeyCode.DPadRight or key == Enum.KeyCode.ButtonR1 then
			cycleTarget(1)
			return
		elseif key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.ButtonL1 then
			cycleTarget(-1)
			return
		elseif key == Enum.KeyCode.ButtonA then
			if hoveredKey then
				lockTarget(hoveredKey)
			else
				cycleTarget(1)
			end
			return
		end
	end

	if processed or state ~= "overhead" then return end

	local isTouch = input.UserInputType == Enum.UserInputType.Touch
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and not isTouch then return end

	local key = targetUnderRay(camera:ScreenPointToRay(input.Position.X, input.Position.Y))
	if not key then return end

	if isTouch and hoveredKey ~= key then
		setHovered(key)
		return
	end

	setHovered(key)
	lockTarget(key)
end)

local statusClock, hoverClock = 0, 0

RunService.RenderStepped:Connect(function(dt)
	if state ~= "overhead" and state ~= "locking" then return end

	statusClock -= dt
	if statusClock <= 0 then
		statusClock = 0.25
		refreshStatuses()
	end

	hoverClock -= dt
	local usingGamepad = UiResponsive ~= nil and UiResponsive.IsGamepad()
	if state == "overhead" and hoverClock <= 0 and UserInputService.MouseEnabled and not usingGamepad then
		hoverClock = 0.05
		local mouse = UserInputService:GetMouseLocation()
		setHovered(targetUnderRay(camera:ViewportPointToRay(mouse.X, mouse.Y)))
	elseif state == "overhead" and hoverClock <= 0 and usingGamepad and not hoveredKey then
		-- Start a gamepad player on the target nearest the middle of the screen.
		hoverClock = 0.25
		cycleTarget(1)
	end

	drawIndicators()
	updateHoverCard()
end)

-- ===================== SERVER EVENTS =====================
startedEvent.OnClientEvent:Connect(function(plan)
	if type(plan) ~= "table" then return end
	local isWorld = plan.targetType == "World"
	if not isWorld and (type(plan.objects) ~= "table" or #plan.objects == 0) then return end

	local mine = plan.attackerUserId == player.UserId

	-- Island attacks are watched live by everyone, attacker included.
	if isWorld then
		local range = Config.Visual.ViewerDistance * 2
		if mine or (camera.CFrame.Position - plan.targetPosition).Magnitude <= range then
			playSequence(plan, mine)
		end
		return
	end

	if mine then
		receivedPlans[plan.id] = plan
		task.delay(60, function() receivedPlans[plan.id] = nil end)

		if state == "locking" and pendingAttackId == plan.id then
			runAttackerCinematic(plan)
		elseif state == "idle" then
			playSequence(plan, false)
		end
		return
	end

	if plan.targetUserId == player.UserId then
		showWarning(plan.attackerName)
	end

	if (camera.CFrame.Position - plan.targetPosition).Magnitude <= Config.Visual.ViewerDistance then
		playSequence(plan, false)
	end
end)

finishedEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or not data.id then return end
	finishedData[data.id] = data
	task.delay(60, function() finishedData[data.id] = nil end)

	-- World results land as a pill; base attacks keep the summary panel.
	if data.targetType == "World" then
		local parts = {
			Format.Abbreviate(data.damage or 0) .. " DAMAGE",
			"★" .. Format.Abbreviate(data.gained or 0),
		}
		if (data.bonus or 0) > 0 then
			table.insert(parts, "DESTROY BONUS ★" .. Format.Abbreviate(data.bonus))
		end
		showToast(table.concat(parts, "  •  "),
			if data.destroyed then COLORS.World else GREEN, 4)
		return
	end

	if state == "summary" and activePlan and activePlan.id == data.id then
		fillSummary(activePlan)
	end
end)

player.CharacterAdded:Connect(function()
	if state ~= "idle" then forceReset() end
end)

-- ===================== CARRY CARD HOOK =====================
local existingToggle = playerGui:FindFirstChild("ToggleAttackTargeting")
if existingToggle then existingToggle:Destroy() end

local toggle = Instance.new("BindableFunction")
toggle.Name = "ToggleAttackTargeting"
toggle.OnInvoke = function()
	if state == "overhead" or state == "charging" then
		cancelTargeting()
		return { ok = true }
	end
	return beginLaunch()
end
toggle.Parent = playerGui

local ATTACK_COLORS = ColorSequence.new(Color3.fromRGB(255, 98, 88), Color3.fromRGB(218, 44, 62))
local COOLDOWN_COLORS = ColorSequence.new(Color3.fromRGB(128, 118, 160), Color3.fromRGB(84, 76, 116))

local function findPath(root, ...)
	local node = root
	for _, name in ipairs({ ... }) do
		if not node then return nil end
		node = node:FindFirstChild(name)
	end
	return node
end

-- The button follows the cooldown of the hole in your hands.
task.spawn(function()
	local lastFace, lastMode = nil, nil

	while gui.Parent do
		task.wait(0.2)

		local face = findPath(playerGui, "BlackHoleActionUI", "Root", "CarryCard", "ActionPanel", "AttackSlot", "Attack")
		if face ~= lastFace then
			lastFace, lastMode = face, nil
		end

		if face then
			local label = findPath(face, "Content", "Label")
			local icon = findPath(face, "Content", "Icon")
			local gradient = face:FindFirstChildOfClass("UIGradient")
			local remaining = cooldownRemaining(heldHole())

			if label and icon and label.Text ~= "CANCEL" then
				if remaining > 0 then
					label.Text = "CHARGING " .. formatClock(remaining)
					label.TextSize = 20
					if lastMode ~= "cooldown" then
						icon.Text = "⏳"
						if gradient then gradient.Color = COOLDOWN_COLORS end
						lastMode = "cooldown"
					end
				elseif lastMode ~= "ready" then
					label.Text = "ATTACK"
					label.TextSize = 26
					icon.Text = "⚔"
					if gradient then gradient.Color = ATTACK_COLORS end
					lastMode = "ready"
				end
			end
		end
	end
end)

-- ===================== STUDIO DEBUG =====================
if RunService:IsStudio() then
	task.spawn(function()
		local debugRemote = remotes:WaitForChild("WorldTargetDebug", 10)
		if not debugRemote then return end

		local hint = text(gui, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 12, 1, -12),
			Size = UDim2.fromOffset(620, 22),
			AlignX = Enum.TextXAlignment.Left,
			Max = 15,
			Stroke = 2,
			Color = Color3.fromRGB(255, 220, 120),
		})

		-- Letter keys: Studio and the Roblox client already use most F-keys
		-- (F9 opens the developer console, F11 goes fullscreen).
		local function refreshHint()
			hint.Text = ("DEBUG  B launch · G start/stop event · J reset HP · K 25%% HP · L destroy · H rebuild · N no-cooldown [%s]")
				:format(if remotes:GetAttribute("DebugNoCooldown") then "ON" else "OFF")
		end
		refreshHint()
		remotes:GetAttributeChangedSignal("DebugNoCooldown"):Connect(refreshHint)
		-- Only with a keyboard: on a phone (or the device emulator) the keys
		-- can't be pressed and the line just covers the bottom of the screen.
		local function refreshHintVisible()
			hint.Visible = UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled
		end
		refreshHintVisible()
		UserInputService.LastInputTypeChanged:Connect(refreshHintVisible)

		local commands = {
			[Enum.KeyCode.G] = "event",
			[Enum.KeyCode.J] = "reset",
			[Enum.KeyCode.K] = "quarter",
			[Enum.KeyCode.L] = "destroy",
			[Enum.KeyCode.H] = "respawn",
			[Enum.KeyCode.N] = "cooldown",
		}

		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then return end

			if input.KeyCode == Enum.KeyCode.B then
				local result = toggle:Invoke()
				if type(result) == "table" and result.ok == false then
					warn("[BaseAttack DEBUG] Launch refused:", result.reason)
				end
				return
			end

			local command = commands[input.KeyCode]
			if command then
				local models = WorldTargetClient.GetModels()
				local targetId = models[1] and models[1]:GetAttribute("WT_Id") or nil
				debugRemote:FireServer(command, targetId)
			end
		end)
	end)
end

print("[BaseAttackClient] Ready.")