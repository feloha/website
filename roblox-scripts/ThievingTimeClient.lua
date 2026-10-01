-- ThievingTimeClient (LocalScript in StarterPlayerScripts)
-- Presentation for THIEVING TIME: the start announcement, a short siren, a
-- compact event card, and a steal preview when you click an enemy black hole.
-- Every rule is decided by ThievingTimeServer; this script only shows results.
--
-- The announcement and the event card live in the shared HudStack column
-- under the Stardust counter (ReplicatedStorage.HudStack), so they never
-- overlap MainHUD or the island event card.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("ThievingTimeConfig"))
local GuiStyle = require(ReplicatedStorage:WaitForChild("GuiStyle"))
local HudStack = require(ReplicatedStorage:WaitForChild("HudStack"))

local Format do
	local module = ReplicatedStorage:FindFirstChild("NumberFormatter")
	local ok, result = pcall(function() return module and require(module) end)
	Format = (ok and type(result) == "table" and result) or {
		Abbreviate = function(n) return tostring(math.floor(tonumber(n) or 0)) end,
	}
end

local UiResponsive do
	local module = ReplicatedStorage:FindFirstChild("UiResponsive")
	local ok, result = pcall(function() return module and require(module) end)
	UiResponsive = if ok and type(result) == "table" then result else nil
end

local GuiService = game:GetService("GuiService")

local Settings do
	local module = ReplicatedStorage:FindFirstChild("ClientSettings")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then Settings = result end
	end
end

local function optionalModule(name)
	local module = ReplicatedStorage:FindFirstChild(name)
	local ok, result = pcall(function() return module and require(module) end)
	return if ok and type(result) == "table" then result else nil
end
local Sounds = optionalModule("GameSounds")
local Coordinator = optionalModule("PresentationCoordinator")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("ThievingTimeRemotes")
local announce = remotes:WaitForChild("Announce")
local previewSteal = remotes:WaitForChild("PreviewSteal")
local requestSteal = remotes:WaitForChild("RequestSteal")

local FONT = GuiStyle.FONT
local NAVY = Color3.fromRGB(8, 12, 28)
local PANEL = Color3.fromRGB(10, 14, 32)
local RED = Color3.fromRGB(255, 70, 70)
local AMBER = Color3.fromRGB(255, 196, 72)
local GREEN = Color3.fromRGB(70, 220, 110)
local LOCK_BLUE = Color3.fromRGB(96, 176, 255)
local DIM = Color3.fromRGB(150, 168, 210)
local C = HudStack.COLORS
local P = Config.Presentation

local ANNOUNCE_TITLE = P.AnnounceTitle or "THIEVING TIME!"
local LOCK_ADVICE = P.AnnounceSubtitle or "Lock your base to protect your black holes."
local ANNOUNCE_SECONDS = math.clamp(tonumber(P.BannerSeconds) or 3.6, 3, 4)
local STEAL_HINT = "Click an enemy black hole to steal."
local TITLE_GRADIENT = ColorSequence.new(Color3.fromRGB(255, 236, 120), Color3.fromRGB(255, 92, 72))
local CARD_TITLE_COLOR = Color3.fromRGB(255, 112, 92)

local old = playerGui:FindFirstChild("ThievingTimeHUD")
if old then old:Destroy() end

-- Holds the steal preview only. The announcement and card are in HudStack.
local gui = Instance.new("ScreenGui")
gui.Name = "ThievingTimeHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 60
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local camera = workspace.CurrentCamera

local function autoScale(guiObject)
	local scale = Instance.new("UIScale")
	scale.Parent = guiObject
	local function refresh()
		local viewport = camera.ViewportSize
		if viewport.X < 1 then return end
		scale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.55, 1)
			* math.clamp(math.min(viewport.X / 1920, viewport.Y / 1080), 1, 1.6)   -- grows past 1080p
	end
	refresh()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	return scale
end

local function label(parent, props)
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = FONT
	text.TextScaled = true
	text.TextWrapped = props.Wrap == true
	text.Text = props.Text or ""
	text.TextColor3 = props.Color or Color3.new(1, 1, 1)
	text.TextXAlignment = props.AlignX or Enum.TextXAlignment.Center
	text.AnchorPoint = props.AnchorPoint or Vector2.zero
	text.Position = props.Position
	text.Size = props.Size
	text.ZIndex = props.ZIndex or 2
	text.Parent = parent
	if props.Max then
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = props.Max
		cap.Parent = text
	end
	if props.Stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = props.Stroke
		stroke.Color = NAVY
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = text
	end
	return text
end

-- "07:32"
local function cardClock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function setText(object, text)
	if object.Text ~= text then object.Text = text end
end

local function setColor(object, color)
	if object.TextColor3 ~= color then object.TextColor3 = color end
end

local function setShown(object, shown)
	if object.Visible ~= shown then object.Visible = shown end
end

-- ===================== EVENT CHIP =====================
-- One compact line beside the island card:  THIEVING TIME   03:09  🛡
-- The shield shows your base state without repeating the Lock Base countdown
-- (that lives on the Lock Base button). Tap for the details and how to steal.
local CHIP_WIDTH = 300
local card = HudStack.Card("ThievingTimeCard", 10, C.Red)
card.Frame.Size = UDim2.fromOffset(CHIP_WIDTH, 0)
do
	local padding = card.Frame:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingBottom = UDim.new(0, 8)
		padding.PaddingLeft = UDim.new(0, 12)
		padding.PaddingRight = UDim.new(0, 12)
	end
	local list = card.Frame:FindFirstChildOfClass("UIListLayout")
	if list then list.Padding = UDim.new(0, 4) end
end

local function chipText(parent, props)
	local text = Instance.new("TextLabel")
	text.Name = props.Name or "Text"
	text.BackgroundTransparency = 1
	text.Font = FONT
	text.Text = props.Text or ""
	text.TextColor3 = props.Color or Color3.new(1, 1, 1)
	text.TextScaled = true
	text.TextXAlignment = props.AlignX or Enum.TextXAlignment.Left
	text.AnchorPoint = props.AnchorPoint or Vector2.zero
	text.Position = props.Position or UDim2.new()
	text.Size = props.Size or UDim2.fromScale(1, 1)
	text.ZIndex = 3
	text.Parent = parent
	local cap = Instance.new("UITextSizeConstraint")
	cap.MinTextSize = 10
	cap.MaxTextSize = props.Max or 20
	cap.Parent = text
	HudStack.Stroke(text, NAVY, props.Stroke or 2, true)
	return text
end

local topRow = Instance.new("TextButton")
topRow.Name = "TopRow"
topRow.LayoutOrder = 1
topRow.Size = UDim2.new(1, 0, 0, 24)
topRow.BackgroundTransparency = 1
topRow.AutoButtonColor = false
topRow.Text = ""
topRow.ZIndex = 3
topRow.Parent = card.Frame
local cardTitle = chipText(topRow, { Name = "Title", Text = "THIEVING TIME", Color = CARD_TITLE_COLOR, Size = UDim2.new(1, -120, 1, 0) })
local cardTimer = chipText(topRow, {
	Name = "Timer", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -46, 0, 0), Size = UDim2.fromOffset(62, 24),
	AlignX = Enum.TextXAlignment.Right,
})
local cardShield = chipText(topRow, {
	Name = "Shield", Text = "🛡", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -18, 0.5, 0),
	Size = UDim2.fromOffset(22, 22), AlignX = Enum.TextXAlignment.Center, Max = 18, Stroke = 1.5,
})
local cardChevron = chipText(topRow, {
	Name = "More", Text = "▼", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.fromOffset(14, 14), AlignX = Enum.TextXAlignment.Center, Max = 12, Color = C.Dim, Stroke = 1.5,
})

local details = Instance.new("Frame")
details.Name = "Details"
details.LayoutOrder = 2
details.Size = UDim2.new(1, 0, 0, 40)
details.BackgroundTransparency = 1
details.Visible = false
details.Parent = card.Frame
local cardStatus = chipText(details, { Name = "Status", Size = UDim2.new(1, 0, 0, 18), Max = 15, Stroke = 1.5 })
local cardHint = chipText(details, { Name = "Hint", Position = UDim2.fromOffset(0, 21), Size = UDim2.new(1, 0, 0, 17), Max = 14, Color = C.Dim, Stroke = 1.5 })

topRow.Activated:Connect(function()
	details.Visible = not details.Visible
	cardChevron.Text = if details.Visible then "▲" else "▼"
end)

-- ===================== SIREN =====================
-- Plays through the SFX sound group, so the Settings SFX slider applies.
local function sfxGroup()
	local group = SoundService:FindFirstChild("BH_SFX")
	return if group and group:IsA("SoundGroup") then group else nil
end

local function soundAllowed()
	local volume = Settings and Settings.Get and tonumber(Settings.Get("SfxVolume"))
	return volume == nil or volume > 0
end

local function sirenSound(soundId)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = P.SirenVolume
	sound.SoundGroup = sfxGroup()
	sound.Parent = SoundService
	return sound
end

local function playSiren()
	if not soundAllowed() then return end

	-- The event-start sound (GameSounds THIEVING_EVENT_START_ID) replaces the old
	-- siren once it has an id. It plays with the banner, once per real start
	-- (joining mid-event shows the banner silently). Quieter over a mutation reveal.
	if Sounds and Sounds.Has and Sounds.Has("THIEVING_EVENT_START_ID") then
		local volume = if Coordinator then Coordinator.SoundVolume("critical") else 1
		if volume > 0 then
			pcall(Sounds.Play, "THIEVING_EVENT_START_ID", { volume = volume })
		end
		return
	end

	if P.SirenSoundId ~= "" then
		local sound = sirenSound(P.SirenSoundId)
		sound:Play()
		task.delay(P.SirenSeconds, function()
			sound:Stop()
			sound:Destroy()
		end)
		return
	end

	-- Fallback two-tone, "wee-woo", from the existing UI sound.
	local sound = sirenSound(P.FallbackToneId)
	task.spawn(function()
		local high = true
		local elapsed = 0
		while elapsed < P.SirenSeconds and sound.Parent do
			sound.PlaybackSpeed = if high then 1.7 else 1.25
			sound.TimePosition = 0
			sound:Play()
			high = not high
			task.wait(0.22)
			elapsed += 0.22
		end
		sound:Destroy()
	end)
end

-- ===================== STATE =====================
local function isActive()
	return remotes:GetAttribute("Active") == true
		and os.time() < (tonumber(remotes:GetAttribute("EndsAt")) or 0)
end

local dirty = true
local function markDirty()
	dirty = true
end

local announcement = nil   -- the announcement this script is showing

-- One announcement per event start; the siren plays once, with it.
local function announceStart(withSiren)
	local mine = {}
	announcement = mine
	card:SetVisible(false)

	if withSiren then
		playSiren()
	end

	HudStack.Announce({
		key = "ThievingTime",
		priority = 10,
		title = ANNOUNCE_TITLE,
		subtitle = STEAL_HINT .. "  " .. LOCK_ADVICE,
		accent = C.Red,
		gradient = TITLE_GRADIENT,
		seconds = ANNOUNCE_SECONDS,
		onHide = function()
			if announcement == mine then
				announcement = nil
				markDirty()
			end
		end,
	})
end

-- ===================== STEAL PREVIEW =====================
local panelWrap = Instance.new("Frame")
panelWrap.AnchorPoint = Vector2.new(0.5, 0.5)
panelWrap.Position = UDim2.fromScale(0.5, 0.5)
panelWrap.Size = UDim2.fromOffset(470, 410)
panelWrap.BackgroundTransparency = 1
panelWrap.Visible = false
panelWrap.Parent = gui
if UiResponsive then
	-- Fit the screen instead of a 1280x720 ratio, so the rules stay readable on phones.
	local panelScale = Instance.new("UIScale")
	panelScale.Parent = panelWrap
	local function fitPanel()
		panelScale.Scale = UiResponsive.FitScale(470, 410, { margin = 14, min = 0.5 })
	end
	fitPanel()
	UiResponsive.Changed:Connect(fitPanel)
else
	autoScale(panelWrap)
end

local panel = Instance.new("Frame")
panel.Size = UDim2.fromScale(1, 1)
panel.Active = true -- clicks on the panel never fall through to the world
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.Parent = panelWrap
GuiStyle.Corner(panel, 0.06)
local panelStroke = GuiStyle.Stroke(panel, RED, 3)
local panelPop = Instance.new("UIScale")
panelPop.Parent = panel

local panelTitle = label(panel, { Text = "STEAL THIS BLACK HOLE?", Position = UDim2.new(0, 20, 0, 14), Size = UDim2.new(1, -40, 0, 36), Max = 28, Stroke = 3 })
local targetLine = label(panel, { Position = UDim2.new(0, 20, 0, 54), Size = UDim2.new(1, -40, 0, 26), Max = 20, Stroke = 2, Color = AMBER })
local ownerLine = label(panel, { Position = UDim2.new(0, 20, 0, 80), Size = UDim2.new(1, -40, 0, 20), Max = 16, Color = DIM })
local statusLine = label(panel, { Position = UDim2.new(0, 20, 0, 106), Size = UDim2.new(1, -40, 0, 30), Max = 22, Stroke = 2.5 })
local priceLine = label(panel, { Position = UDim2.new(0, 20, 0, 138), Size = UDim2.new(1, -40, 0, 22), Max = 18, Stroke = 2 })

local conditions = label(panel, {
	Position = UDim2.new(0, 24, 0, 166), Size = UDim2.new(1, -48, 0, 118),
	Max = 14, Color = DIM, AlignX = Enum.TextXAlignment.Left, Wrap = true,
})
conditions.TextYAlignment = Enum.TextYAlignment.Top

local policyLine = label(panel, {
	Position = UDim2.new(0, 24, 0, 286), Size = UDim2.new(1, -48, 0, 44),
	Max = 14, Color = AMBER, AlignX = Enum.TextXAlignment.Left, Wrap = true,
})
policyLine.TextYAlignment = Enum.TextYAlignment.Top

local function button(text, color, border, x)
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0, 1)
	b.Position = UDim2.new(x, if x == 0 then 20 else 6, 1, -18)
	b.Size = UDim2.new(0.5, -26, 0, 50)
	b.BackgroundColor3 = color
	b.AutoButtonColor = false
	b.Font = FONT
	b.Text = text
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = panel
	GuiStyle.Corner(b, 0.3)
	GuiStyle.Stroke(b, border, 3)
	GuiStyle.TextStroke(b, 2.5)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 11)
	pad.PaddingBottom = UDim.new(0, 11)
	pad.Parent = b
	return b
end

local stealButton = button("STEAL", GuiStyle.COL.Green, GuiStyle.COL.GreenDark, 0)
local closeButton = button("CLOSE", GuiStyle.COL.X, GuiStyle.COL.XBorder, 0.5)

local currentHole = nil
local canBuy = false
local panelToken = 0

local function closePanel()
	panelToken += 1
	currentHole = nil
	panelWrap.Visible = false
end

local function fillPanel(preview)
	local target = preview.target
	if target then
		targetLine.Text = ("T%d  %s  •  ★%s/s"):format(target.tier, tostring(target.name), Format.Abbreviate(target.power))
		ownerLine.Text = "Owned by " .. tostring(target.ownerName)
	else
		targetLine.Text = "—"
		ownerLine.Text = ""
	end

	if preview.status == "eligible" then
		statusLine.Text = "✓ ELIGIBLE"
		statusLine.TextColor3 = GREEN
		panelStroke.Color = GREEN
	elseif preview.status == "protected" then
		statusLine.Text = if preview.reason and preview.reason:find("BASE LOCKED")
			then "🔒 BASE LOCKED — PROTECTED"
			else "🛡 " .. tostring(preview.reason)
		statusLine.TextColor3 = LOCK_BLUE
		panelStroke.Color = LOCK_BLUE
	else
		statusLine.Text = tostring(preview.reason or "Not available")
		statusLine.TextColor3 = RED
		panelStroke.Color = RED
	end

	priceLine.Text = if preview.purchaseEnabled and preview.price
		then "Price:  R$ " .. tostring(preview.price)
		else "Price:  not set yet"
	priceLine.TextColor3 = AMBER

	local lines = {}
	for _, line in ipairs(preview.conditions or {}) do
		table.insert(lines, "•  " .. line)
	end
	conditions.Text = table.concat(lines, "\n")
	policyLine.Text = if preview.testMode
		then "TEST MODE: new-player and last-black-hole protection are off. Base locks still apply."
		else tostring(preview.unavailablePolicy or "")

	canBuy = preview.ok == true and preview.purchaseEnabled == true
	stealButton.Text = if preview.purchaseEnabled then "STEAL" else "COMING SOON"
	stealButton.BackgroundColor3 = if canBuy then GuiStyle.COL.Green else Color3.fromRGB(96, 100, 130)
end

local function openPreview(hole)
	panelToken += 1
	local token = panelToken
	currentHole = hole

	local ok, preview = pcall(function()
		return previewSteal:InvokeServer(hole)
	end)
	if panelToken ~= token then return end
	if not ok or type(preview) ~= "table" then return end

	fillPanel(preview)
	panelWrap.Visible = true
	if UiResponsive and UiResponsive.IsGamepad() then
		GuiService.SelectedObject = if canBuy then stealButton else closeButton
	end
	panelPop.Scale = 0.9
	TweenService:Create(panelPop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

stealButton.Activated:Connect(function()
	if not canBuy or not currentHole then return end
	-- Rechecked on the server. No prompt opens while purchases are disabled.
	local hole = currentHole
	local ok, result = pcall(function()
		return requestSteal:InvokeServer(hole)
	end)
	if ok and type(result) == "table" and not result.ok then
		statusLine.Text = tostring(result.reason)
		statusLine.TextColor3 = RED
	end
end)

closeButton.Activated:Connect(closePanel)

-- ===================== TARGETING =====================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function holeUnder(ray)
	rayParams.FilterDescendantsInstances = CollectionService:GetTagged("BlackHole")
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 600, rayParams)
	return hit and hit.Instance
end

UserInputService.InputBegan:Connect(function(input, processed)
	if (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) and panelWrap.Visible then
		closePanel()
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(panelWrap) then
			GuiService.SelectedObject = nil
		end
		return
	end
	if processed or not isActive() then return end
	-- The attack overhead view and cinematics own clicks while they run.
	if camera.CameraType == Enum.CameraType.Scriptable then return end

	-- Gamepad: aim with the camera and press Y to inspect the black hole in the middle.
	if input.KeyCode == Enum.KeyCode.ButtonY then
		local viewport = camera.ViewportSize
		local hole = holeUnder(camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5))
		if hole and tonumber(hole:GetAttribute("OwnerUserId")) ~= player.UserId then
			openPreview(hole)
		end
		return
	end

	local isTouch = input.UserInputType == Enum.UserInputType.Touch
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and not isTouch then return end

	-- Touch positions exclude the top bar inset; the mouse location includes it.
	local ray
	if isTouch then
		ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
	else
		local mouse = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	end
	local hole = holeUnder(ray)
	if hole and tonumber(hole:GetAttribute("OwnerUserId")) ~= player.UserId then
		openPreview(hole)
	end
end)

-- ===================== CARD UPDATES =====================
local function refreshCard(now)
	if not isActive() then
		card:SetVisible(false)
		if panelWrap.Visible then closePanel() end
		return
	end

	setText(cardTimer, cardClock((tonumber(remotes:GetAttribute("EndsAt")) or 0) - now))
	setColor(cardTimer, if (tonumber(remotes:GetAttribute("EndsAt")) or 0) - now <= 30 then C.Amber else Color3.new(1, 1, 1))

	-- BaseLockedUntil is set by LockBaseServer. Until it has replicated, nothing
	-- is guessed. The countdown itself stays on the Lock Base button.
	local lockedUntil = player:GetAttribute("BaseLockedUntil")
	local protected = lockedUntil ~= nil and (tonumber(lockedUntil) or 0) > now
	setShown(cardShield, lockedUntil ~= nil)
	cardShield.TextTransparency = if protected then 0 else 0.55
	if lockedUntil == nil then
		setText(cardStatus, "Checking your base…")
		setColor(cardStatus, C.Dim)
	elseif protected then
		setText(cardStatus, "Your base is shielded")
		setColor(cardStatus, C.Green)
	else
		setText(cardStatus, "Your base is unlocked: press LOCK BASE")
		setColor(cardStatus, C.Amber)
	end
	card:SetAccent(if protected then C.Green else C.Red)

	local hint
	if UiResponsive and UiResponsive.IsGamepad() then
		hint = "Aim at an enemy black hole and press Y to steal."
	elseif (UiResponsive and UiResponsive.IsTouch())
		or (not UiResponsive and UserInputService.TouchEnabled and not UserInputService.MouseEnabled) then
		hint = "Tap an enemy black hole to steal."
	else
		hint = STEAL_HINT
	end
	setText(cardHint, hint)

	if announcement then
		card:SetVisible(false)
	elseif not card.Frame.Visible then
		card:SetVisible(true)
		card:FadeIn()
	end
end

remotes:GetAttributeChangedSignal("Active"):Connect(markDirty)
remotes:GetAttributeChangedSignal("EndsAt"):Connect(markDirty)
player:GetAttributeChangedSignal("BaseLockedUntil"):Connect(markDirty)

-- Joined mid-event: show the announcement once, without the siren.
if isActive() then
	announceStart(false)
end

-- Text changes at most once a second (or right away when state changes).
local lastSecond = -1
RunService.Heartbeat:Connect(function()
	local now = os.time()
	if now == lastSecond and not dirty then return end
	lastSecond = now
	dirty = false
	refreshCard(now)
end)

-- ===================== EVENTS =====================
announce.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.kind == "Start" then
		announceStart(true)
	elseif payload.kind == "End" then
		announcement = nil
		HudStack.Dismiss("ThievingTime")
		closePanel()
	end
	markDirty()
end)

-- ===================== TEST CONTROLS =====================
-- The server only creates DebugToggle in Studio or for listed test users, and
-- checks every request again.
if Config.Debug.StudioCommands then
	task.spawn(function()
		local debugRemote = remotes:WaitForChild("DebugToggle", 10)
		if not debugRemote then return end
		print("[ThievingTime] Test keys: T = start/stop, Shift+T = test protections on/off, Ctrl+T = status.")
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or input.KeyCode ~= Enum.KeyCode.T then return end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
				debugRemote:FireServer("relax")
			elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
				debugRemote:FireServer("status")
			else
				debugRemote:FireServer("toggle")
			end
		end)
	end)
end
