-- PlaytimeAwardsClient (LocalScript in StarterPlayerScripts)
-- Playtime Rewards window, in the same style as the Store: blue gradient
-- header, the shared red X (GuiStyle.MakePlaytimeX), dark gradient cards with
-- outlines, glossy text and green buttons.
--
--   * Rewards come from PlaytimeAwardsConfig (Stardust, XP, boosts, shields).
--   * Every claim is checked and granted by PlaytimeAwardsServer; this script
--     only shows what the server says was granted.
--   * States: counting down / NEXT / CLAIM / CLAIMED (text + colour, never
--     colour alone). "Claim all" collects every ready reward in one request.
--   * The 6-hour Cosmic Jackpot is the featured panel on the right (on phones
--     it's the first row of the list).
-- Uses GuiManager, so opening another popup closes this one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GuiManager = require(ReplicatedStorage:WaitForChild("GuiManager"))
local GuiStyle = require(ReplicatedStorage:WaitForChild("GuiStyle"))
local Config = require(ReplicatedStorage:WaitForChild("PlaytimeAwardsConfig"))
local RewardIcons = require(ReplicatedStorage:WaitForChild("RewardIcons"))

local function optional(name)
	local module = ReplicatedStorage:FindFirstChild(name)
	local ok, result = pcall(function() return module and require(module) end)
	return if ok and type(result) == "table" then result else nil
end

local UiResponsive = optional("UiResponsive")
local Sounds = optional("GameSounds")
local StardustCollectAnimator = optional("StardustCollectAnimator")

local remotes = ReplicatedStorage:WaitForChild("PlaytimeAwardsRemotes")
local claimRemote = remotes:WaitForChild("Claim")
local claimAllRemote = remotes:WaitForChild("ClaimAll", 10)

local FONT = GuiStyle.FONT
local COL = GuiStyle.COL

-- The Secret Store's palette, so this window belongs beside it.
local C = {
	Shadow = Color3.fromRGB(3, 6, 26),
	ShadowSoft = Color3.fromRGB(14, 10, 46),
	ShellNavy = Color3.fromRGB(10, 18, 58),
	BorderBlue = Color3.fromRGB(46, 134, 255),
	EdgeCyan = Color3.fromRGB(111, 232, 255),
	BodyTop = Color3.fromRGB(28, 48, 146),
	BodyMid = Color3.fromRGB(15, 26, 94),
	BodyBottom = Color3.fromRGB(24, 38, 124),
	CardEdge = Color3.fromRGB(10, 22, 70),
	CardRim = Color3.fromRGB(86, 222, 255),
	Magenta = Color3.fromRGB(246, 62, 216),
	MagentaDeep = Color3.fromRGB(150, 16, 132),
	Gold = Color3.fromRGB(255, 206, 64),
	GoldDeep = Color3.fromRGB(186, 106, 10),
	Cream = Color3.fromRGB(255, 252, 240),
	Ink = Color3.fromRGB(14, 22, 58),
}

local UIAssets do
	local module = ReplicatedStorage:FindFirstChild("UIAssets")
	local ok, value = pcall(function() return module and require(module) end)
	UIAssets = if ok and type(value) == "table" then value else {}
end

-- A tight aura: concentric rings, each fading top and bottom. One ring on its
-- own always shows its own outline, which is what makes a glow look like a
-- translucent circle laid on top.
local function softGlow(parent, props)
	local halo = Instance.new("Frame")
	halo.Name = props.Name or "Glow"
	halo.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
	halo.Position = props.Position or UDim2.fromScale(0.5, 0.5)
	halo.Size = props.Size or UDim2.fromScale(1, 1)
	halo.BackgroundTransparency = 1
	halo.BorderSizePixel = 0
	halo.ZIndex = props.ZIndex or 1
	halo.Parent = parent

	local base = props.Transparency or 0.86
	for index, ring in ipairs({
		{ 1.18, 0.82 }, { 0.94, 0.6 }, { 0.72, 0.38 }, { 0.5, 0.17 }, { 0.3, 0 },
		}) do
		local layer = Instance.new("Frame")
		layer.Name = "Ring" .. index
		layer.AnchorPoint = Vector2.new(0.5, 0.5)
		layer.Position = UDim2.fromScale(0.5, 0.5)
		layer.Size = UDim2.fromScale(ring[1], ring[1])
		layer.BackgroundColor3 = props.Color or C.EdgeCyan
		layer.BackgroundTransparency = base + (1 - base) * ring[2]
		layer.BorderSizePixel = 0
		layer.ZIndex = halo.ZIndex
		layer.Parent = halo
		GuiStyle.Corner(layer, props.Radius or 1)

		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, 0.4),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.65, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = layer
	end
	return halo
end

-- Light across a panel, rather than a shape sitting behind the artwork.
--
-- softGlow builds concentric rounded rectangles and its gradient tapers only
-- vertically, so however faint it gets, its left and right edges stay hard and
-- the whole thing reads as an object. This spans its parent's full width, so
-- there are no free edges to notice, and grades away at the top and bottom,
-- which is what light actually looks like. Use it for a card's interior; keep
-- softGlow for the places where a round bloom is the point.
local function ambientLight(parent, props)
	local wash = Instance.new("Frame")
	wash.Name = props.Name or "Light"
	wash.AnchorPoint = Vector2.new(0.5, 0)
	wash.Position = props.Position or UDim2.new(0.5, 0, 0, 0)
	wash.Size = props.Size or UDim2.new(1, 0, 0, 120)
	wash.BackgroundColor3 = props.Color or C.EdgeCyan
	wash.BackgroundTransparency = props.Transparency or 0.86
	wash.BorderSizePixel = 0
	wash.ZIndex = props.ZIndex or 1
	wash.Parent = parent
	GuiStyle.Corner(wash, props.Radius or 0.09)

	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.24, 0.58),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.76, 0.58),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = wash
	return wash
end

-- A four-point sparkle: two crossed arms, each tapering to its tips, over a
-- soft round bloom. Rounded ends on their own only make a plus sign.
local function makeSparkle(parent, props)
	local spark = Instance.new("Frame")
	spark.Name = props.Name or "Sparkle"
	spark.AnchorPoint = Vector2.new(0.5, 0.5)
	spark.Position = props.Position or UDim2.fromScale(0.5, 0.5)
	spark.Size = UDim2.fromOffset(props.Size or 14, props.Size or 14)
	spark.BackgroundTransparency = 1
	spark.Rotation = props.Rotation or 0
	spark.ZIndex = props.ZIndex or 20
	spark.Parent = parent

	local colour = props.Color or Color3.new(1, 1, 1)
	local alpha = props.Transparency or 0.2

	local bloom = Instance.new("Frame")
	bloom.Name = "Bloom"
	bloom.AnchorPoint = Vector2.new(0.5, 0.5)
	bloom.Position = UDim2.fromScale(0.5, 0.5)
	bloom.Size = UDim2.fromScale(0.84, 0.84)
	bloom.BackgroundColor3 = colour
	bloom.BackgroundTransparency = math.min(alpha + (1 - alpha) * 0.7, 0.97)
	bloom.BorderSizePixel = 0
	bloom.ZIndex = spark.ZIndex
	bloom.Parent = spark
	GuiStyle.Corner(bloom, 1)

	for _, arm in ipairs({
		{ Name = "Vertical", Size = UDim2.new(0.17, 0, 1, 0), Rotation = 90 },
		{ Name = "Horizontal", Size = UDim2.new(1, 0, 0.17, 0), Rotation = 0 },
		}) do
		local bar = Instance.new("Frame")
		bar.Name = arm.Name
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = arm.Size
		bar.BackgroundColor3 = colour
		bar.BackgroundTransparency = alpha
		bar.BorderSizePixel = 0
		bar.ZIndex = spark.ZIndex + 1
		bar.Parent = spark
		GuiStyle.Corner(bar, 1)

		local taper = Instance.new("UIGradient")
		taper.Rotation = arm.Rotation
		taper.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.26, 0.55),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.74, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		taper.Parent = bar
	end

	local core = Instance.new("Frame")
	core.Name = "Core"
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromScale(0.3, 0.3)
	core.BackgroundColor3 = colour:Lerp(Color3.new(1, 1, 1), 0.7)
	core.BackgroundTransparency = math.max(alpha - 0.1, 0)
	core.BorderSizePixel = 0
	core.ZIndex = spark.ZIndex + 2
	core.Parent = spark
	GuiStyle.Corner(core, 1)
	return spark
end

-- Light catching an edge, done with thick faint strokes on shell frames. A
-- stroke draws outside its own border and is not clipped by the parent, which
-- is how the glow escapes a window that clips its contents.
local function outerAura(parent, colour, rings)
	for index, ring in ipairs(rings) do
		local shell = Instance.new("Frame")
		shell.Name = "Aura" .. index
		shell.AnchorPoint = Vector2.new(0.5, 0.5)
		shell.Position = UDim2.fromScale(0.5, 0.5)
		shell.Size = UDim2.fromScale(1, 1)
		shell.BackgroundTransparency = 1
		shell.BorderSizePixel = 0
		shell.ZIndex = ring.ZIndex or 1
		shell.Parent = parent
		GuiStyle.Corner(shell, ring.Radius or 0.05)
		local edge = GuiStyle.Stroke(shell, colour, ring.Thickness)
		edge.Transparency = ring.Transparency
	end
end
local WHITE = Color3.new(1, 1, 1)
local COUNT = #Config.Milestones

local STATE_COLORS = {
	locked = COL.Outline,
	next = COL.Cyan,
	ready = COL.Green,
	claimed = Color3.fromRGB(70, 90, 130),
}

local old = playerGui:FindFirstChild("PlaytimeAwardsUI")
if old then old:Destroy() end
local oldBlur = Lighting:FindFirstChild("PlaytimeAwardsBlur")
if oldBlur then oldBlur:Destroy() end

-- A sparkle that breathes on its own clock. Phase is a 0-1 offset so a group
-- of them never blinks in step, which is the thing that reads as a cheap UI
-- rather than as light.
local function twinkle(spark, phase, period)
	if not spark then return end
	local bloom = spark:FindFirstChild("Bloom")

	local scale = Instance.new("UIScale")
	scale.Name = "Twinkle"
	scale.Parent = spark

	task.delay(phase * period, function()
		if not spark.Parent then return end
		TweenService:Create(scale,
			TweenInfo.new(period * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.06 }):Play()
		if bloom then
			local dim = math.min(bloom.BackgroundTransparency + 0.18, 0.99)
			TweenService:Create(bloom,
				TweenInfo.new(period * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundTransparency = dim }):Play()
		end
	end)
end

-- Hover and press on a button, as one owner of one UIScale. The press has to
-- cancel the hover or the two tween the same property against each other.
local function addPressFeel(button, scale)
	local current
	local function play(target, seconds, style, direction)
		if current then current:Cancel() end
		current = TweenService:Create(scale,
			TweenInfo.new(seconds, style, direction), { Scale = target })
		current:Play()
		return current
	end

	button.MouseEnter:Connect(function()
		play(1.028, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)
	button.MouseLeave:Connect(function()
		play(1, 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)
	button.MouseButton1Down:Connect(function()
		play(0.962, 0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)
	button.MouseButton1Up:Connect(function()
		play(1.02, 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out).Completed:Once(function()
			play(1, 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end)
	end)
end

local function sfx(slot)
	if Sounds then pcall(Sounds.Play, slot) end
end

-- Same text helper as the Store.
local function makeText(parent, props)
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "TextLabel"
	label.BackgroundTransparency = 1
	label.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	label.Position = props.Position or UDim2.fromScale(0, 0)
	label.Size = props.Size or UDim2.fromOffset(100, 40)
	label.Text = props.Text or ""
	label.Font = FONT
	label.TextWrapped = props.TextWrapped or false
	label.TextColor3 = props.TextColor3 or COL.Light
	label.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center
	label.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	label.ZIndex = props.ZIndex or 1
	label.Parent = parent
	label.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = props.MinTextSize or 12
	constraint.MaxTextSize = props.MaxTextSize or 32
	constraint.Parent = label
	constraint:SetAttribute("BaseMin", constraint.MinTextSize)   -- applyLayout scales it
	if props.Stroke ~= false then
		GuiStyle.TextStroke(label, props.StrokeThickness or 2)
	end
	if props.Gloss then
		GuiStyle.GlossText(label)
	end
	return label
end

local function greenButton(parent, props)
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 1)
	button.Position = props.Position
	button.Size = props.Size
	button.BackgroundColor3 = COL.Green
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = props.ZIndex or 20
	button.Parent = parent
	GuiStyle.Corner(button, 0.3)
	GuiStyle.Stroke(button, Color3.fromRGB(10, 92, 44), 3.5)
	local fill = GuiStyle.Gradient(button, Color3.fromRGB(150, 255, 128), COL.GreenDark)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	-- Not GuiStyle.AddHoverScale: that connects hover only, and a press tween
	-- added beside it would fight the hover tween over the same Scale.
	addPressFeel(button, scale)

	do
		-- Gloss across the upper half, and a soft shadow under the whole
		-- thing, which is what gives these buttons their moulded look.
		local gloss = Instance.new("Frame")
		gloss.Name = "Gloss"
		gloss.AnchorPoint = Vector2.new(0.5, 0)
		gloss.Position = UDim2.new(0.5, 0, 0, 4)
		gloss.Size = UDim2.new(1, -14, 0.46, 0)
		gloss.BackgroundColor3 = Color3.fromRGB(226, 255, 190)
		gloss.BackgroundTransparency = 0.55
		gloss.BorderSizePixel = 0
		gloss.ZIndex = button.ZIndex
		gloss.Parent = button
		GuiStyle.Corner(gloss, 0.6)

		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(0, 1)
		fade.Parent = gloss

		local lip = Instance.new("Frame")
		lip.Name = "Lip"
		lip.AnchorPoint = Vector2.new(0.5, 1)
		lip.Position = UDim2.new(0.5, 0, 1, -4)
		lip.Size = UDim2.new(1, -18, 0, 4)
		lip.BackgroundColor3 = Color3.fromRGB(16, 120, 54)
		lip.BackgroundTransparency = 0.35
		lip.BorderSizePixel = 0
		lip.ZIndex = button.ZIndex
		lip.Parent = button
		GuiStyle.Corner(lip, 1)
	end
	local label = makeText(button, {
		Name = "Label", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.72, 0), Text = props.Text or "CLAIM", ZIndex = button.ZIndex + 1,
		StrokeThickness = 2.5, Gloss = true, MinTextSize = 14, MaxTextSize = props.MaxTextSize or 26,
	})
	button.MouseEnter:Connect(function() sfx("UI_HOVER_ID") end)
	return button, label, fill, scale
end

-- Artwork buttons. Where UIAssets carries the picture the ImageButton IS the
-- surface: no frame, no gradient, no stroke and no label under it, because a
-- finished button asset already contains its own wording and edge. The only
-- thing kept in reserve is a text fallback that stays invisible unless the
-- picture has not arrived after eight seconds -- a moderation hold or a bad id
-- should leave a readable button, not an invisible one.
local BUTTON_ART = nil
do
	local map = UIAssets.PlaytimeButtons
	if type(map) == "table" and type(map.Claim) == "string" and map.Claim ~= "" then
		BUTTON_ART = map
	end
end

-- Is this object actually being drawn? An ancestor with Visible = false
-- hides everything under it, and Roblox does not fetch an image for anything
-- it is not drawing -- so "how long has it failed to load" is only a fair
-- question while the answer could have been yes.
local function onScreen(object)
	while object and object:IsA("GuiObject") do
		if not object.Visible then return false end
		object = object.Parent
	end
	return true
end

local function imageButton(parent, props)
	local button = Instance.new("ImageButton")
	button.Name = props.Name or "Button"
	button.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 1)
	button.Position = props.Position
	button.Size = props.Size
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Image = props.Image
	-- Fit, so a finished asset is never stretched: it letterboxes inside the
	-- slot and keeps whatever proportions it was drawn at.
	button.ScaleType = Enum.ScaleType.Fit
	button.ZIndex = props.ZIndex or 20
	button.Parent = parent

	local scale = Instance.new("UIScale")
	scale.Parent = button
	addPressFeel(button, scale)

	-- The last resort, and nothing more. It is invisible unless the picture
	-- has failed to arrive after eight seconds OF BEING ON SCREEN, and it goes
	-- away again the moment the picture does arrive.
	local spare = makeText(button, {
		Name = "Fallback", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.8, 0, 0.4, 0), Text = props.Text or "", ZIndex = button.ZIndex + 1,
		StrokeThickness = 3, MinTextSize = 12, MaxTextSize = 26,
	})
	spare.Visible = false
	-- Built now rather than at the moment of failure, so the fallback never
	-- adds instances to a live button. Invisible while the background is.
	button.BackgroundColor3 = COL.Green
	GuiStyle.Corner(button, 0.3)

	task.spawn(function()
		-- Counts only the time the button is genuinely rendered. Measuring
		-- from build time is what made this fire on every button in every
		-- session: the popup is hidden then, and a claim button is hidden
		-- until its reward is ready, so the image could not have loaded yet.
		local seen = 0
		while button.Parent do
			if button.IsLoaded then
				-- Late arrivals count. This used to stop watching once it had
				-- said no, which is why the word sat on top of the artwork.
				if spare.Visible then
					spare.Visible = false
					button.BackgroundTransparency = 1
				end
				return
			end
			if onScreen(button) then
				seen += 0.4
				if seen >= 8 and not spare.Visible then
					spare.Visible = true
					button.BackgroundTransparency = 0
				end
			end
			task.wait(0.4)
		end
	end)

	button.MouseEnter:Connect(function() sfx("UI_HOVER_ID") end)
	return button, spare, scale
end

local function setButtonEnabled(button, fill, enabled)
	button.Active = enabled
	button.AutoButtonColor = false
	if enabled then
		fill.Color = ColorSequence.new(Color3.fromRGB(85, 255, 110), COL.GreenDark)
	else
		fill.Color = ColorSequence.new(Color3.fromRGB(120, 130, 170), Color3.fromRGB(70, 78, 110))
	end
end

-- ===================== WINDOW =====================
local gui = Instance.new("ScreenGui")
gui.Name = "PlaytimeAwardsUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.IgnoreGuiInset = true
if UiResponsive and UiResponsive.UseModalInsets then UiResponsive.UseModalInsets(gui) end   -- below the top bar
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = gui

-- GuiManager animates this full-screen group; the popup keeps its own
-- responsive UIScale (one UIScale per object).
local popupGroup = Instance.new("Frame")
popupGroup.Name = "PlaytimePopupGroup"
popupGroup.AnchorPoint = Vector2.new(0.5, 0.5)
popupGroup.Position = UDim2.fromScale(0.5, 0.5)
popupGroup.Size = UDim2.fromScale(1, 1)
popupGroup.BackgroundTransparency = 1
popupGroup.Visible = false
popupGroup.Parent = root

local popup = Instance.new("Frame")
popup.Name = "PlaytimePopup"
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.Position = UDim2.fromScale(0.5, 0.5)
popup.Size = UDim2.fromOffset(1420, 982)
popup.BackgroundColor3 = C.ShellNavy
popup.BackgroundTransparency = 0
popup.Active = true
popup.ClipsDescendants = true
popup.ZIndex = 10
popup.Parent = popupGroup
GuiStyle.Corner(popup, 0.05)
GuiStyle.Stroke(popup, C.BorderBlue, 6)

-- Behind the window: a soft navy shadow and a tight blue aura.
do
	local shadow = Instance.new("Frame")
	shadow.Name = "WindowShadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, 0, 0.5, 14)
	shadow.Size = UDim2.new(1, -16, 1, -8)
	shadow.BackgroundColor3 = C.ShadowSoft
	shadow.BackgroundTransparency = 0.62
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 8
	shadow.Parent = popup
	GuiStyle.Corner(shadow, 0.05)

	local glow = Instance.new("Frame")
	glow.Name = "WindowGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, -4, 1, -4)
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.ZIndex = 9
	glow.Parent = popup
	outerAura(glow, C.BorderBlue, {
		{ Thickness = 4, Transparency = 0.55, ZIndex = 9, Radius = 0.05 },
		{ Thickness = 11, Transparency = 0.82, ZIndex = 9, Radius = 0.05 },
		{ Thickness = 22, Transparency = 0.93, ZIndex = 9, Radius = 0.05 },
	})
end

-- The lit interior, inset so a band of the navy shell shows between the bright
-- frame and the bright inside. That band is what makes the frame read as
-- structure rather than as an outline.
local interior = Instance.new("Frame")
interior.Name = "Interior"
interior.Position = UDim2.fromOffset(11, 11)
interior.Size = UDim2.new(1, -22, 1, -22)
interior.BackgroundColor3 = Color3.new(1, 1, 1)   -- gradient carries the colour
interior.BorderSizePixel = 0
interior.ClipsDescendants = true
interior.ZIndex = 10
interior.Parent = popup
GuiStyle.Corner(interior, 0.04)

do
	local sky = Instance.new("UIGradient")
	sky.Rotation = 90
	sky.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.BodyTop),
		ColorSequenceKeypoint.new(0.55, C.BodyMid),
		ColorSequenceKeypoint.new(1, C.BodyBottom),
	})
	sky.Parent = interior

	-- Wide, very faint colour fields: depth without anything reading as fog.
	local function field(x, y, size, tint, alpha)
		local blob = Instance.new("Frame")
		blob.Name = "ColourField"
		blob.AnchorPoint = Vector2.new(0.5, 0.5)
		blob.Position = UDim2.fromScale(x, y)
		blob.Size = UDim2.fromScale(size, size * 0.72)
		blob.BackgroundColor3 = tint
		blob.BackgroundTransparency = alpha
		blob.BorderSizePixel = 0
		blob.ZIndex = 10
		blob.Parent = interior
		GuiStyle.Corner(blob, 1)

		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = blob
	end
	field(0.18, 0.14, 0.7, Color3.fromRGB(96, 158, 255), 0.82)
	field(0.8, 0.18, 0.55, Color3.fromRGB(150, 128, 255), 0.86)
	field(0.5, 0.6, 1.05, Color3.fromRGB(14, 24, 92), 0.8)
	field(0.12, 0.88, 0.62, Color3.fromRGB(168, 140, 255), 0.84)
	field(0.9, 0.84, 0.64, Color3.fromRGB(96, 206, 255), 0.84)

	-- Pastel cloud banks along the bottom corners, as the reference has.
	-- Cloud banks: bigger, brighter and pushed further off the edges than
	-- before, because at the old size they read as faint smudges rather than
	-- the pastel masses the reference frames its window with. They sit at
	-- ZIndex 10, under everything, and hang off the bottom and sides so they
	-- never come near a button.
	for _, cloud in ipairs({
		{ X = 0.04, Y = 1.03, W = 0.46, H = 0.34, Alpha = 0.56, Tint = Color3.fromRGB(198, 206, 255) },
		{ X = 0.22, Y = 1.0, W = 0.32, H = 0.25, Alpha = 0.64, Tint = Color3.fromRGB(176, 214, 255) },
		{ X = 0.5, Y = 1.02, W = 0.3, H = 0.19, Alpha = 0.74, Tint = Color3.fromRGB(206, 190, 255) },
		{ X = 0.78, Y = 1.0, W = 0.32, H = 0.25, Alpha = 0.64, Tint = Color3.fromRGB(176, 214, 255) },
		{ X = 0.96, Y = 1.03, W = 0.46, H = 0.34, Alpha = 0.56, Tint = Color3.fromRGB(198, 206, 255) },
		-- Side banks, mostly off the edge.
		{ X = -0.03, Y = 0.66, W = 0.22, H = 0.38, Alpha = 0.76, Tint = Color3.fromRGB(168, 190, 255) },
		{ X = 1.03, Y = 0.74, W = 0.22, H = 0.38, Alpha = 0.76, Tint = Color3.fromRGB(180, 178, 255) },
		}) do
		local puff = Instance.new("Frame")
		puff.Name = "Cloud"
		puff.AnchorPoint = Vector2.new(0.5, 1)
		puff.Position = UDim2.fromScale(cloud.X, cloud.Y)
		puff.Size = UDim2.fromScale(cloud.W, cloud.H)
		puff.BackgroundColor3 = cloud.Tint
		puff.BackgroundTransparency = cloud.Alpha
		puff.BorderSizePixel = 0
		puff.ZIndex = 10
		puff.Parent = interior
		GuiStyle.Corner(puff, 1)

		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.45, 0),
			NumberSequenceKeypoint.new(1, 0.25),
		})
		fade.Parent = puff
	end

	-- Star points, kept to the margins and the gaps.
	for index, spot in ipairs({
		{ 0.02, 0.3, 4 }, { 0.015, 0.62, 3 }, { 0.03, 0.86, 3 },
		{ 0.98, 0.26, 4 }, { 0.986, 0.58, 3 }, { 0.97, 0.82, 3 },
		{ 0.3, 0.965, 3 }, { 0.62, 0.972, 3 }, { 0.46, 0.05, 3 },
		{ 0.07, 0.12, 3 }, { 0.93, 0.1, 3 },
		{ 0.012, 0.44, 3 }, { 0.99, 0.42, 3 }, { 0.025, 0.72, 2 },
		{ 0.975, 0.7, 2 }, { 0.16, 0.055, 3 }, { 0.82, 0.045, 3 },
		{ 0.38, 0.985, 2 }, { 0.72, 0.99, 2 }, { 0.5, 0.03, 2 },
		{ 0.055, 0.2, 2 }, { 0.945, 0.22, 2 },
		}) do
		local dot = Instance.new("Frame")
		dot.Name = "Star" .. index
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(spot[1], spot[2])
		dot.Size = UDim2.fromOffset(spot[3], spot[3])
		dot.BackgroundColor3 = if index % 3 == 0 then C.EdgeCyan else Color3.new(1, 1, 1)
		dot.BackgroundTransparency = 0.3
		dot.BorderSizePixel = 0
		dot.ZIndex = 11
		dot.Parent = interior
		GuiStyle.Corner(dot, 1)
	end

	-- Larger gold and cyan glints around the outside, as the reference has.
	makeSparkle(interior, { Position = UDim2.fromScale(0.03, 0.2), Size = 26,
		Color = Color3.fromRGB(255, 226, 130), Transparency = 0.18, ZIndex = 11, Rotation = 12 })
	makeSparkle(interior, { Position = UDim2.fromScale(0.97, 0.68), Size = 24,
		Color = Color3.fromRGB(255, 232, 160), Transparency = 0.2, ZIndex = 11, Rotation = -8 })
	makeSparkle(interior, { Position = UDim2.fromScale(0.965, 0.16), Size = 18,
		Color = C.EdgeCyan, Transparency = 0.28, ZIndex = 11, Rotation = 20 })
	makeSparkle(interior, { Position = UDim2.fromScale(0.028, 0.78), Size = 20,
		Color = Color3.fromRGB(206, 160, 255), Transparency = 0.3, ZIndex = 11, Rotation = -18 })
	makeSparkle(interior, { Position = UDim2.fromScale(0.5, 0.995), Size = 16,
		Color = Color3.fromRGB(255, 226, 130), Transparency = 0.34, ZIndex = 11, Rotation = 6 })
	makeSparkle(interior, { Position = UDim2.fromScale(0.075, 0.955), Size = 28,
		Color = Color3.fromRGB(255, 220, 118), Transparency = 0.2, ZIndex = 11, Rotation = -10 })
	makeSparkle(interior, { Position = UDim2.fromScale(0.93, 0.94), Size = 25,
		Color = Color3.fromRGB(255, 232, 150), Transparency = 0.24, ZIndex = 11, Rotation = 16 })
	makeSparkle(interior, { Position = UDim2.fromScale(0.015, 0.5), Size = 21,
		Color = Color3.new(1, 1, 1), Transparency = 0.32, ZIndex = 11, Rotation = -4 })

	-- The frame's specular: a cyan edge, a near-white line just inside it, and
	-- a wide faint bloom outside. One flat stroke reads as a border; three
	-- graded ones read as a lit bevel.
	local innerEdge = Instance.new("Frame")
	innerEdge.Name = "InnerEdge"
	innerEdge.Position = UDim2.fromOffset(4, 4)
	innerEdge.Size = UDim2.new(1, -8, 1, -8)
	innerEdge.BackgroundTransparency = 1
	innerEdge.ZIndex = 60
	innerEdge.Parent = interior
	GuiStyle.Corner(innerEdge, 0.04)
	local edge = GuiStyle.Stroke(innerEdge, C.EdgeCyan, 3)
	edge.Transparency = 0.08

	local highlight = Instance.new("Frame")
	highlight.Name = "InnerHighlight"
	highlight.Position = UDim2.fromOffset(7, 7)
	highlight.Size = UDim2.new(1, -14, 1, -14)
	highlight.BackgroundTransparency = 1
	highlight.ZIndex = 60
	highlight.Parent = interior
	GuiStyle.Corner(highlight, 0.04)
	local white = GuiStyle.Stroke(highlight, Color3.fromRGB(226, 248, 255), 1.5)
	white.Transparency = 0.45
	-- Brightest along the top, gone by the bottom: light from above.
	local sheen = Instance.new("UIGradient")
	sheen.Rotation = 90
	sheen.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.45, 0.55),
		NumberSequenceKeypoint.new(1, 0.9),
	})
	sheen.Parent = white

	-- The corner mask. ClipsDescendants is rectangular, so the cloud bank
	-- paints into the square part of the interior's rounded corners. A stroke
	-- draws outside its own frame and follows the UICorner, so this covers the
	-- wedge between the rounded silhouette and the rectangle -- and only that.
	local cornerMask = Instance.new("Frame")
	cornerMask.Name = "CornerMask"
	cornerMask.Size = UDim2.fromScale(1, 1)
	cornerMask.BackgroundTransparency = 1
	cornerMask.ZIndex = 57
	cornerMask.Parent = interior
	GuiStyle.Corner(cornerMask, 0.04)
	local seal = GuiStyle.Stroke(cornerMask, C.ShellNavy, 14)
	seal.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local bloom = Instance.new("Frame")
	bloom.Name = "EdgeBloom"
	bloom.Position = UDim2.fromOffset(1, 1)
	bloom.Size = UDim2.new(1, -2, 1, -2)
	bloom.BackgroundTransparency = 1
	bloom.ZIndex = 59
	bloom.Parent = interior
	GuiStyle.Corner(bloom, 0.04)
	local haze = GuiStyle.Stroke(bloom, C.EdgeCyan, 8)
	haze.Transparency = 0.82
end

local popupScale = Instance.new("UIScale")
popupScale.Name = "ResponsiveScale"
popupScale.Parent = popup

GuiManager:Register("PlaytimeAwards", popupGroup, {
	BlurSize = 12,
	OpenScale = 0.9,
	OpenOvershootScale = 1.02,
	CloseBounceScale = 1.01,
	CloseScale = 0.9,
})

-- Header --------------------------------------------------------------------------
local HEADER_H = 166

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = Color3.new(1, 1, 1)   -- gradient carries the colour
header.ZIndex = 20
header.Parent = interior
GuiStyle.Corner(header, 0.16)
GuiStyle.Stroke(header, C.CardEdge, 3)
GuiStyle.Gradient(header, Color3.fromRGB(48, 88, 228), Color3.fromRGB(14, 26, 104))

do
	-- Cosmic backdrop behind the branding, and a bright line along the top.
	local shine = Instance.new("Frame")
	shine.Name = "HeaderShine"
	shine.AnchorPoint = Vector2.new(0.5, 0)
	shine.Position = UDim2.new(0.5, 0, 0, 5)
	shine.Size = UDim2.new(0.95, 0, 0, 18)
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.8
	shine.BorderSizePixel = 0
	shine.ZIndex = 21
	shine.Parent = header
	GuiStyle.Corner(shine, 1)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0, 1)
	fade.Parent = shine

	for index, spot in ipairs({
		{ 0.09, 0.2, 3 }, { 0.2, 0.82, 3 }, { 0.33, 0.16, 3 },
		{ 0.42, 0.86, 2 }, { 0.5, 0.2, 2 }, { 0.58, 0.78, 3 },
		{ 0.14, 0.1, 2 }, { 0.27, 0.9, 2 }, { 0.38, 0.12, 3 },
		{ 0.47, 0.92, 2 }, { 0.54, 0.1, 2 }, { 0.62, 0.22, 2 },
		{ 0.68, 0.88, 3 }, { 0.05, 0.62, 2 }, { 0.72, 0.14, 2 },
		{ 0.24, 0.3, 2 }, { 0.31, 0.72, 2 }, { 0.44, 0.24, 2 },
		{ 0.52, 0.8, 2 }, { 0.6, 0.34, 2 }, { 0.12, 0.44, 2 },
		}) do
		local dot = Instance.new("Frame")
		dot.Name = "HeaderStar" .. index
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(spot[1], spot[2])
		dot.Size = UDim2.fromOffset(spot[3], spot[3])
		dot.BackgroundColor3 = if index % 3 == 0 then C.EdgeCyan
			elseif index % 5 == 0 then Color3.fromRGB(206, 164, 255)
			else Color3.new(1, 1, 1)
		dot.BackgroundTransparency = 0.3
		dot.BorderSizePixel = 0
		dot.ZIndex = 21
		dot.Parent = header
		GuiStyle.Corner(dot, 1)
	end

	softGlow(header, {
		Name = "BrandingLight", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 40, 0.5, -6), Size = UDim2.fromOffset(760, 210),
		Color = Color3.fromRGB(86, 168, 255), Transparency = 0.82, ZIndex = 21, Radius = 0.45,
	})

	-- The planet that sat between the title and the timer pill is gone, and so
	-- are the violet bloom under it and the glint beside it. The stretch it
	-- occupied is left to the starfield.
end

-- The stopwatch: bigger, lit, and the game's own artwork when it is there.
local headerIcon = Instance.new("Frame")
headerIcon.Name = "HeaderIcon"
headerIcon.AnchorPoint = Vector2.new(0, 0.5)
headerIcon.Position = UDim2.new(0, 26, 0.5, -6)
headerIcon.Size = UDim2.fromOffset(128, 128)
headerIcon.BackgroundTransparency = 1
headerIcon.ZIndex = 23
headerIcon.Parent = header

softGlow(header, {
	Name = "IconGlow", AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.5, -6), Size = UDim2.fromOffset(196, 196),
	Color = C.EdgeCyan, Transparency = 0.54, ZIndex = 20, Radius = 1,
})

do
	local drawn = Instance.new("Frame")
	drawn.Name = "Drawn"
	drawn.Size = UDim2.fromScale(1, 1)
	drawn.BackgroundTransparency = 1
	drawn.ZIndex = 23
	drawn.Parent = headerIcon
	RewardIcons.Draw(drawn, "cooldown", { color = COL.Cyan, zIndex = 23 })

	-- Artwork over the drawn version, hidden only once it has really loaded.
	if UIAssets.Stopwatch then
		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.Size = UDim2.fromScale(1, 1)
		art.BackgroundTransparency = 1
		art.BorderSizePixel = 0
		art.Active = false
		art.Image = UIAssets.Stopwatch
		art.ScaleType = Enum.ScaleType.Fit
		art.ZIndex = 24
		art.Parent = headerIcon

		task.spawn(function()
			local giveUp = os.clock() + 600
			while os.clock() < giveUp do
				if art.IsLoaded then
					drawn.Visible = false
					return
				end
				task.wait(0.5)
			end
		end)
	end
end

makeSparkle(header, { Name = "IconSparkleA", Position = UDim2.new(0, 22, 0.5, -60),
	Size = 28, Color = Color3.fromRGB(255, 224, 120), Transparency = 0.1, ZIndex = 25, Rotation = 10 })
makeSparkle(header, { Name = "IconSparkleB", Position = UDim2.new(0, 150, 0.5, 48),
	Size = 19, Color = C.EdgeCyan, Transparency = 0.22, ZIndex = 25, Rotation = -14 })
makeSparkle(header, { Name = "IconSparkleC", Position = UDim2.new(0, 152, 0.5, -52),
	Size = 16, Color = Color3.fromRGB(255, 236, 160), Transparency = 0.26, ZIndex = 25, Rotation = 22 })
makeSparkle(header, { Name = "TitleSparkleA", Position = UDim2.new(0, 742, 0.5, -44),
	Size = 24, Color = Color3.fromRGB(255, 224, 120), Transparency = 0.12, ZIndex = 25, Rotation = -12 })
makeSparkle(header, { Name = "TitleSparkleB", Position = UDim2.new(0, 156, 0.5, -64),
	Size = 15, Color = C.EdgeCyan, Transparency = 0.3, ZIndex = 25, Rotation = 8 })
makeSparkle(header, { Name = "TitleSparkleC", Position = UDim2.new(0, 762, 0.5, 26),
	Size = 16, Color = Color3.new(1, 1, 1), Transparency = 0.28, ZIndex = 25, Rotation = 18 })

-- Two-colour lettering: gold "Playtime", icy white "Rewards". TextScaled
-- cannot do two colours in one label, so these are two labels sized to their
-- own text and laid out side by side. The popup's UIScale still scales them.
do
	local WORDS = {
		{ Text = "Playtime", Top = Color3.fromRGB(255, 244, 168), Bottom = Color3.fromRGB(255, 154, 22) },
		{ Text = "Rewards", Top = Color3.new(1, 1, 1), Bottom = Color3.fromRGB(150, 216, 255) },
	}

	-- One builder, three passes. Roblox allows a single UIStroke and a single
	-- UIGradient per object, so a cartoon logo's cyan rim, navy extrusion and
	-- graded face cannot live on one label -- they are three rows stacked by
	-- ZIndex. Building them from the same table is what keeps them aligned.
	local function titlePass(name, dropY, zIndex, paint)
		local rowFrame = Instance.new("Frame")
		rowFrame.Name = name
		rowFrame.AnchorPoint = Vector2.new(0, 0)
		rowFrame.Position = UDim2.fromOffset(166, 20 + dropY)
		rowFrame.Size = UDim2.fromOffset(700, 84)
		rowFrame.BackgroundTransparency = 1
		rowFrame.ZIndex = zIndex
		rowFrame.Parent = header

		local row = Instance.new("UIListLayout")
		row.FillDirection = Enum.FillDirection.Horizontal
		row.HorizontalAlignment = Enum.HorizontalAlignment.Left
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.Padding = UDim.new(0, 14)
		row.SortOrder = Enum.SortOrder.LayoutOrder
		row.Parent = rowFrame

		for index, word in ipairs(WORDS) do
			local label = Instance.new("TextLabel")
			label.Name = word.Text
			label.LayoutOrder = index
			label.AutomaticSize = Enum.AutomaticSize.X
			label.Size = UDim2.fromOffset(0, 82)
			label.BackgroundTransparency = 1
			label.Font = FONT
			label.Text = word.Text
			label.TextSize = 72
			label.TextColor3 = Color3.new(1, 1, 1)
			label.ZIndex = zIndex
			label.Parent = rowFrame
			paint(label, word)
		end
		return rowFrame
	end

	-- Pass 1: a wide cyan stroke with the letters themselves invisible, so all
	-- that shows is a halo around the shapes above it.
	titlePass("TitleRim", 2, 21, function(label)
		label.TextTransparency = 1
		local rim = Instance.new("UIStroke")
		rim.Color = Color3.fromRGB(96, 214, 255)
		rim.Thickness = 12
		rim.Transparency = 0.42
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		rim.Parent = label
	end)

	-- Pass 2: solid ink, pushed down. This is the extrusion the letters sit on.
	titlePass("TitleExtrude", 7, 22, function(label)
		label.TextColor3 = C.Ink
		local ink = Instance.new("UIStroke")
		ink.Color = C.Ink
		ink.Thickness = 6.5
		ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		ink.Parent = label
	end)

	-- Pass 3: the face. Gold for Playtime, ice for Rewards, ink outline, and a
	-- specular band across the upper third rather than an even gradient.
	titlePass("TitleRow", 0, 23, function(label, word)
		local ink = Instance.new("UIStroke")
		ink.Color = C.Ink
		ink.Thickness = 6
		ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		ink.Parent = label

		local shade = Instance.new("UIGradient")
		shade.Rotation = 90
		shade.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, word.Top),
			ColorSequenceKeypoint.new(0.34, word.Top:Lerp(Color3.new(1, 1, 1), 0.55)),
			ColorSequenceKeypoint.new(0.46, word.Top),
			ColorSequenceKeypoint.new(1, word.Bottom),
		})
		shade.Parent = label
	end)
end

makeText(header, {
	Name = "Subtitle", Position = UDim2.fromOffset(170, 112),
	Size = UDim2.fromOffset(540, 34), Text = "Play longer, get better rewards!",
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(226, 242, 255),
	ZIndex = 23, StrokeThickness = 3.5, MinTextSize = 14, MaxTextSize = 28,
})

local resetPill = Instance.new("Frame")
resetPill.Name = "Reset"
resetPill.AnchorPoint = Vector2.new(1, 0.5)
resetPill.Position = UDim2.new(1, -104, 0.5, 0)
resetPill.Size = UDim2.fromOffset(320, 64)
resetPill.BackgroundColor3 = Color3.fromRGB(12, 22, 68)
resetPill.BackgroundTransparency = 0.1
resetPill.ZIndex = 22
resetPill.Parent = header
GuiStyle.Corner(resetPill, 0.5)
GuiStyle.Stroke(resetPill, C.EdgeCyan, 3)
local resetPillFit = Instance.new("UIScale")   -- smaller on phones (applyLayout)
resetPillFit.Parent = resetPill

do
	local lift = Instance.new("Frame")
	lift.Name = "Gloss"
	lift.AnchorPoint = Vector2.new(0.5, 0)
	lift.Position = UDim2.new(0.5, 0, 0, 3)
	lift.Size = UDim2.new(1, -16, 0, 20)
	lift.BackgroundColor3 = Color3.new(1, 1, 1)
	lift.BackgroundTransparency = 0.84
	lift.BorderSizePixel = 0
	lift.ZIndex = 23
	lift.Parent = resetPill
	GuiStyle.Corner(lift, 1)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0, 1)
	fade.Parent = lift

	if UIAssets.PlaytimeCalendar then
		local calendar = Instance.new("ImageLabel")
		calendar.Name = "Calendar"
		calendar.AnchorPoint = Vector2.new(0, 0.5)
		calendar.Position = UDim2.new(0, 14, 0.5, 0)
		calendar.Size = UDim2.fromOffset(48, 48)
		calendar.BackgroundTransparency = 1
		calendar.BorderSizePixel = 0
		calendar.Active = false
		calendar.Image = UIAssets.PlaytimeCalendar
		calendar.ScaleType = Enum.ScaleType.Fit
		calendar.ZIndex = 24
		calendar.Parent = resetPill
	end
end

local resetText = makeText(resetPill, {
	Name = "Text", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(240, 34), Text = "New day in --:--", ZIndex = 24,
	TextColor3 = Color3.fromRGB(230, 244, 255),
	MinTextSize = 9, MaxTextSize = 27, StrokeThickness = 3.5,   -- 9: the time must never be cut off
})

local closeButton = GuiStyle.MakePlaytimeX(header, function() end)

do
	-- Chunkier and more lit than the shared default, without touching GuiStyle.
	closeButton.Size = UDim2.fromOffset(62, 62)
	closeButton.Position = UDim2.new(1, -14, 0.5, 0)
	local shadow = header:FindFirstChild("CloseShadow")
	if shadow then
		shadow.Size = UDim2.fromOffset(68, 68)
		shadow.Position = UDim2.new(1, -11, 0.5, 5)
		shadow.BackgroundTransparency = 0.42
	end
	softGlow(header, {
		Name = "CloseGlow", AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(112, 112),
		Color = Color3.fromRGB(255, 104, 104), Transparency = 0.76, ZIndex = 39, Radius = 1,
	})
end

do
	-- The same close artwork the Store and the leaderboard use, laid over the
	-- drawn X. GuiStyle is untouched, so nothing else in the game changes. The
	-- drawn X stays underneath until the picture is confirmed loaded.
	if closeButton and UIAssets.Close then
		local art = Instance.new("ImageLabel")
		art.Name = "CloseArt"
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, 0.5)
		art.Size = UDim2.fromScale(1.42, 1.42)
		art.BackgroundTransparency = 1
		art.BorderSizePixel = 0
		art.Active = false
		art.Image = UIAssets.Close
		art.ScaleType = Enum.ScaleType.Fit
		art.ZIndex = 70
		art.Parent = closeButton

		task.spawn(function()
			local giveUp = os.clock() + 600
			while os.clock() < giveUp do
				if art.IsLoaded then
					closeButton.BackgroundTransparency = 1
					local edge = closeButton:FindFirstChildOfClass("UIStroke")
					if edge then edge.Transparency = 1 end
					for _, child in ipairs(closeButton:GetChildren()) do
						if child ~= art and child:IsA("GuiObject") then
							child.Visible = false
						end
					end
					return
				end
				task.wait(0.4)
			end
		end)
	end
end

-- Progress strip --------------------------------------------------------------------
local strip = Instance.new("Frame")
strip.Name = "Progress"
strip.Position = UDim2.fromOffset(12, HEADER_H + 14)
strip.Size = UDim2.new(1, -24, 0, 78)
strip.BackgroundColor3 = Color3.fromRGB(12, 22, 68)
strip.BackgroundTransparency = 0.08
strip.ZIndex = 12
strip.Parent = interior
-- Short windows (phones): header and strip are drawn smaller so the reward
-- cards get the room (applyLayout).
local headerFit = Instance.new("UIScale")
headerFit.Parent = header
local stripFit = Instance.new("UIScale")
stripFit.Parent = strip
GuiStyle.Corner(strip, 0.35)
GuiStyle.Stroke(strip, C.CardEdge, 3)

do
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.Position = UDim2.fromOffset(3, 3)
	rim.Size = UDim2.new(1, -6, 1, -6)
	rim.BackgroundTransparency = 1
	rim.ZIndex = 13
	rim.Parent = strip
	GuiStyle.Corner(rim, 0.35)
	local edge = GuiStyle.Stroke(rim, C.EdgeCyan, 1.5)
	edge.Transparency = 0.45
end

local stripText = makeText(strip, {
	Name = "Text", AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(22, 10),
	Size = UDim2.new(1, -380, 0, 32), Text = "", TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 14, MinTextSize = 13, MaxTextSize = 29, StrokeThickness = 3.5,
})
local stripTrack = Instance.new("Frame")
stripTrack.Name = "Track"
stripTrack.Position = UDim2.fromOffset(22, 48)
stripTrack.Size = UDim2.new(1, -386, 0, 24)
stripTrack.BackgroundColor3 = Color3.fromRGB(6, 11, 42)
stripTrack.ZIndex = 14
stripTrack.Parent = strip
GuiStyle.Corner(stripTrack, 1)
GuiStyle.Stroke(stripTrack, C.CardEdge, 2)

local stripFill = Instance.new("Frame")
stripFill.Name = "Fill"
stripFill.Size = UDim2.fromScale(0, 1)
stripFill.BackgroundColor3 = Color3.new(1, 1, 1)
stripFill.ZIndex = 15
stripFill.Parent = stripTrack
GuiStyle.Corner(stripFill, 1)
GuiStyle.Gradient(stripFill, Color3.fromRGB(198, 250, 255), Color3.fromRGB(32, 138, 255))

do
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.AnchorPoint = Vector2.new(0.5, 0)
	sheen.Position = UDim2.new(0.5, 0, 0, 2)
	sheen.Size = UDim2.new(1, -8, 0, 7)
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.BackgroundTransparency = 0.3
	sheen.BorderSizePixel = 0
	sheen.ZIndex = 16
	sheen.Parent = stripFill
	GuiStyle.Corner(sheen, 1)
end

local claimAllButton, claimAllLabel, claimAllFill
if BUTTON_ART then
	-- One slot for both states, so switching between them cannot move the
	-- layout. The count is no longer drawn: the asset carries its own wording.
	claimAllButton, claimAllLabel = imageButton(strip, {
		Name = "ClaimAll", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(360, 100), Image = BUTTON_ART.ClaimAll,
		Text = "CLAIM ALL", ZIndex = 17,
	})
else
	claimAllButton, claimAllLabel, claimAllFill = greenButton(strip, {
		Name = "ClaimAll", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(314, 64), Text = "CLAIM ALL", ZIndex = 17, MaxTextSize = 35,
	})
end

do
	-- A soft green bloom under CLAIM ALL. It is the one control in the band
	-- that should read as brighter than everything around it.
	softGlow(strip, {
		Name = "ClaimAllGlow", AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 4), Size = UDim2.fromOffset(330, 92),
		Color = Color3.fromRGB(96, 255, 140), Transparency = 0.82, ZIndex = 13, Radius = 0.5,
	})
end

-- Body: list + featured ----------------------------------------------------------------
local BODY_TOP = HEADER_H + 98

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Rewards"
scroll.Position = UDim2.fromOffset(10, BODY_TOP)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageTransparency = 0.7
scroll.ScrollBarImageColor3 = COL.Cyan
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.ZIndex = 12
scroll.Parent = interior
if UiResponsive and UiResponsive.TouchScroll then UiResponsive.TouchScroll(scroll) end   -- easy thumb scrolling

-- The body lays out in a fixed 672-tall space and is scaled to whatever
-- height the window actually got. See applyLayout.
local scrollScale = Instance.new("UIScale")
scrollScale.Name = "BodyScale"
scrollScale.Parent = scroll

local scrollPad = Instance.new("UIPadding")
scrollPad.PaddingTop = UDim.new(0, 6)
scrollPad.PaddingBottom = UDim.new(0, 16)
scrollPad.PaddingLeft = UDim.new(0, 6)
scrollPad.PaddingRight = UDim.new(0, 10)
scrollPad.Parent = scroll

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(305, 324)   -- applyLayout sets the real one
grid.CellPadding = UDim2.fromOffset(16, 16)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
grid.Parent = scroll

-- Toast (claim results and errors) ----------------------------------------------------
local toast = Instance.new("Frame")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -14)
toast.Size = UDim2.new(0.8, 0, 0, 58)
toast.BackgroundColor3 = Color3.fromRGB(8, 10, 22)
toast.BackgroundTransparency = 0.06
toast.Visible = false
toast.ZIndex = 80
toast.Parent = interior
GuiStyle.Corner(toast, 0.3)
local toastStroke = GuiStyle.Stroke(toast, COL.Green, 3)
local toastIcons = Instance.new("Frame")
toastIcons.Name = "Icons"
toastIcons.AnchorPoint = Vector2.new(0, 0.5)
toastIcons.Position = UDim2.new(0, 12, 0.5, 0)
toastIcons.Size = UDim2.fromOffset(0, 40)
toastIcons.AutomaticSize = Enum.AutomaticSize.X
toastIcons.BackgroundTransparency = 1
toastIcons.ZIndex = 81
toastIcons.Parent = toast
local toastIconLayout = Instance.new("UIListLayout")
toastIconLayout.FillDirection = Enum.FillDirection.Horizontal
toastIconLayout.Padding = UDim.new(0, 4)
toastIconLayout.VerticalAlignment = Enum.VerticalAlignment.Center
toastIconLayout.Parent = toastIcons
local toastText = makeText(toast, {
	Name = "Text", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.new(1, -40, 0.66, 0), ZIndex = 82, MinTextSize = 12, MaxTextSize = 22,
	TextXAlignment = Enum.TextXAlignment.Left,
})
local toastToken = 0

local function showToast(message, color, items)
	toastToken += 1
	local token = toastToken
	for _, child in ipairs(toastIcons:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	local iconCount = 0
	for _, item in ipairs(items or {}) do
		if iconCount >= 5 then break end
		iconCount += 1
		local slot = Instance.new("Frame")
		slot.Size = UDim2.fromOffset(38, 38)
		slot.BackgroundTransparency = 1
		slot.ZIndex = 81
		slot.Parent = toastIcons
		local info = RewardIcons.Describe(item, nil)
		RewardIcons.Draw(slot, info.kind, { color = info.color, zIndex = 81, stroke = 2 })
	end
	toastText.Size = UDim2.new(1, -(iconCount * 42 + 40), 0.66, 0)
	toastText.Text = message
	toastText.TextColor3 = WHITE
	toastStroke.Color = color or COL.Green
	toast.Visible = true
	task.delay(3, function()
		if toastToken == token then toast.Visible = false end
	end)
end

local function describeGranted(granted)
	local parts = {}
	for _, item in ipairs(granted or {}) do
		if item.Type == "Stardust" then
			table.insert(parts, "★" .. RewardIcons.FormatNumber(item.Amount))
		elseif item.Type == "XP" then
			table.insert(parts, "+" .. RewardIcons.FormatNumber(item.Amount) .. " XP")
		elseif item.Type == "Boost" then
			local info = RewardIcons.Describe(item, nil)
			table.insert(parts, info.title .. " +" .. RewardIcons.FormatDuration(item.Seconds))
		elseif item.Type == "Shield" then
			table.insert(parts, "Shield " .. RewardIcons.FormatDuration(item.Seconds))
		elseif item.Type == "Gems" then
			table.insert(parts, "+" .. RewardIcons.FormatNumber(item.Amount) .. " Gems")
		end
	end
	return table.concat(parts, "   ")
end

-- ===================== CARDS =====================
local income = 0
local cards = {}

-- The card gives the artwork a fixed zone and the text a fixed baseline, and
-- both are filled from the middle out: the icon row is centred in its zone, and
-- the reward lines stack UPWARDS from linesBottom. A one-reward card therefore
-- gets the whole zone for one big icon and puts its single line low, while the
-- three-reward card gets smaller icons and three lines, and both end up with
-- the same air between the art and the text. Sizing every card for the worst
-- case instead is what kept the icons small.
local function rewardRows(parent, milestone, props)
	local items = milestone.Rewards
	local iconSize = if #items >= 3 then props.iconSmall else props.iconLarge
	local zoneTop = props.iconsTop
	local zoneHeight = props.iconZone or props.iconLarge
	-- linesLead is extra air under the FIRST line, which on the jackpot is the
	-- Stardust value: it separates the headline number from the boosts below
	-- without giving every gap the same size.
	local lead = if #items > 1 then (props.linesLead or 0) else 0
	local linesTop = props.linesBottom - #items * props.lineHeight - lead

	local iconPad = props.iconPad or 6
	local iconsRow = Instance.new("Frame")
	iconsRow.Name = "Icons"
	iconsRow.AnchorPoint = Vector2.new(0.5, 0.5)
	iconsRow.Position = UDim2.new(0.5, 0, 0, zoneTop + zoneHeight // 2)
	iconsRow.Size = UDim2.new(1, -12, 0, iconSize)
	iconsRow.BackgroundTransparency = 1
	iconsRow.ZIndex = props.zIndex
	iconsRow.Parent = parent

	-- What the row needs across, so applyLayout can shrink it to the cell it
	-- lands in instead of letting it spill out of a narrow card.
	iconsRow:SetAttribute("ContentWidth", #items * iconSize + (#items - 1) * iconPad)
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = iconsRow
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, iconPad)
	layout.Parent = iconsRow

	local lines = {}
	for index, item in ipairs(items) do
		local slot = Instance.new("Frame")
		slot.Size = UDim2.fromOffset(iconSize, iconSize)
		slot.BackgroundTransparency = 1
		slot.LayoutOrder = index
		slot.ZIndex = props.zIndex
		slot.Parent = iconsRow
		local info = RewardIcons.Describe(item, 0)

		-- Colour spill under this icon: faint, wider than the artwork, and in
		-- the reward's own colour, so each one lights its patch of the card.
		softGlow(slot, {
			Name = "Spill", Size = UDim2.fromScale(1.5, 1.5),
			Color = info.color, Transparency = 0.88,
			ZIndex = props.zIndex - 1, Radius = 1,
		})
		-- The 20 MIN reward is a Stardust multiplier rather than a lump of
		-- Stardust, and the reference says so with two overlapping coins.
		-- Read from the reward's own Type, not from the milestone number.
		local stacked = item.Type == "Boost" and info.kind == "stardust"
		RewardIcons.Draw(slot, info.kind, {
			color = info.color, zIndex = props.zIndex, stack = stacked,
		})

		local line = makeText(parent, {
			Name = "Line" .. index, AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, linesTop + (index - 1) * props.lineHeight + (if index > 1 then lead else 0)),
			Size = UDim2.new(1, -16, 0, props.lineHeight - 2), ZIndex = props.zIndex + 1,
			MinTextSize = 11, MaxTextSize = props.lineText, StrokeThickness = 2,
		})
		lines[index] = { label = line, item = item }
	end
	return iconsRow, lines
end

-- #12: the three badge states, as one family. Same pill, same shadow, same
-- gloss; only the paint differs.
local TAG_PAINT = {
	ready = { Fill = Color3.fromRGB(78, 226, 104), Edge = Color3.fromRGB(12, 92, 44), Text = Color3.fromRGB(240, 255, 238) },
	next = { Fill = Color3.fromRGB(20, 40, 104), Edge = Color3.fromRGB(108, 216, 255), Text = Color3.fromRGB(216, 244, 255) },
	claimed = { Fill = Color3.fromRGB(84, 96, 132), Edge = Color3.fromRGB(34, 44, 76), Text = Color3.fromRGB(216, 226, 244) },
}

-- Alternating card identities, so a row of six is not one colour six times.
-- Cyan for the odd milestones, magenta for the even ones; the jackpot has its
-- own gold treatment below.
local CARD_THEMES = {
	{ Rim = C.CardRim, StripTop = Color3.fromRGB(96, 214, 255), StripBottom = Color3.fromRGB(24, 108, 226),
		StripEdge = Color3.fromRGB(8, 34, 96), Aura = Color3.fromRGB(64, 156, 255) },
	{ Rim = Color3.fromRGB(255, 130, 240), StripTop = Color3.fromRGB(252, 126, 236), StripBottom = C.MagentaDeep,
		StripEdge = Color3.fromRGB(72, 8, 70), Aura = Color3.fromRGB(186, 72, 255) },
}

-- Keeps an inner plate's corners following the card's rounded corners, so
-- nothing square pokes past them at any size (the card's radius is a share
-- of its size, so this is measured, not hard-coded).
local function matchInnerCorner(outer, inner, outerScale)
	local corner = inner:FindFirstChildOfClass("UICorner") or GuiStyle.Corner(inner, 0.3)
	local function sync()
		local o, i = outer.AbsoluteSize, inner.AbsoluteSize
		local oMin, iMin = math.min(o.X, o.Y), math.min(i.X, i.Y)
		if oMin < 1 or iMin < 1 then return end
		local inset = math.max((o.X - i.X) / 2, 0)
		local radius = math.max(outerScale * oMin - inset, 4)
		corner.CornerRadius = UDim.new(math.min(radius / iMin, 0.5), 0)
	end
	outer:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)
	inner:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)
	sync()
end

local STRIP_INSET = 4   -- the top strip sits just inside the card's rim

local function makeCard(index, featured)
	local milestone = Config.Milestones[index]
	local theme = if featured
		then { Rim = C.Gold, StripTop = Color3.fromRGB(255, 238, 138), StripBottom = Color3.fromRGB(246, 146, 20),
			StripEdge = Color3.fromRGB(96, 40, 2), Aura = Color3.fromRGB(206, 96, 255) }
		else CARD_THEMES[(index % 2) + 1]

	local card = Instance.new("Frame")
	card.Name = "Reward" .. index
	card.LayoutOrder = if featured then 0 else index
	card.BackgroundColor3 = Color3.new(1, 1, 1)   -- gradient carries the colour
	card.BackgroundTransparency = 0.04
	card.ZIndex = 15
	card.Parent = scroll
	GuiStyle.Corner(card, if featured then 0.05 else 0.09)
	local stroke = GuiStyle.Stroke(card, C.CardEdge, if featured then 4 else 3)
	if featured then
		-- #34: the jackpot's body runs warmer than the blue cards, so the gold
		-- border has something of its own to sit on.
		GuiStyle.Gradient(card, Color3.fromRGB(58, 48, 132), Color3.fromRGB(22, 18, 62))
	else
		GuiStyle.Gradient(card, Color3.fromRGB(34, 54, 136), Color3.fromRGB(13, 21, 68))
	end
	local pop = Instance.new("UIScale")
	pop.Parent = card

	local rimEdge
	-- The jackpot's inner specular line, reached by the hover below.
	local goldLine
	do
		-- Deep navy outline outside, themed rim just inside it, and a soft
		-- shadow under the card. One thick coloured stroke is what makes a
		-- card read as a bordered box instead of a lit panel.
		local shade = Instance.new("Frame")
		shade.Name = "CardShadow"
		shade.AnchorPoint = Vector2.new(0.5, 0.5)
		shade.Position = UDim2.new(0.5, 2, 0.5, 7)
		shade.Size = UDim2.new(1, -8, 1, -6)
		shade.BackgroundColor3 = C.ShadowSoft
		shade.BackgroundTransparency = 0.7
		shade.BorderSizePixel = 0
		shade.ZIndex = 14
		shade.Parent = card
		GuiStyle.Corner(shade, 0.1)

		local rim = Instance.new("Frame")
		rim.Name = "Rim"
		rim.Position = UDim2.fromOffset(3, 3)
		rim.Size = UDim2.new(1, -6, 1, -6)
		rim.BackgroundTransparency = 1
		rim.ZIndex = 58
		rim.Parent = card
		GuiStyle.Corner(rim, if featured then 0.05 else 0.09)
		rimEdge = GuiStyle.Stroke(rim, theme.Rim, if featured then 3 else 2.5)

		if featured then
			-- A thin yellow-white line just inside the gold, which is what
			-- separates a lit metal edge from a coloured border.
			local spec = Instance.new("Frame")
			spec.Name = "GoldSpecular"
			spec.Position = UDim2.fromOffset(6, 6)
			spec.Size = UDim2.new(1, -12, 1, -12)
			spec.BackgroundTransparency = 1
			spec.ZIndex = 58
			spec.Parent = card
			GuiStyle.Corner(spec, 0.05)
			goldLine = GuiStyle.Stroke(spec, Color3.fromRGB(255, 248, 206), 1.5)
			goldLine.Transparency = 0.5
			local grade = Instance.new("UIGradient")
			grade.Rotation = 90
			grade.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.05),
				NumberSequenceKeypoint.new(0.5, 0.6),
				NumberSequenceKeypoint.new(1, 0.9),
			})
			grade.Parent = goldLine
		end
		local rimLight = Instance.new("UIGradient")
		rimLight.Rotation = 90
		rimLight.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.55, 0.28),
			NumberSequenceKeypoint.new(1, 0.55),
		})
		rimLight.Parent = rimEdge

		outerAura(card, theme.Rim, {
			{ Thickness = 3, Transparency = 0.6, ZIndex = 14, Radius = if featured then 0.05 else 0.09 },
			{ Thickness = 9, Transparency = 0.84, ZIndex = 14, Radius = if featured then 0.05 else 0.09 },
			{ Thickness = 16, Transparency = 0.93, ZIndex = 14, Radius = if featured then 0.05 else 0.09 },
		})

		-- Two small star points in the card's own upper corners.
		for index, spot in ipairs({ { 0.11, 0.3, 3 }, { 0.9, 0.24, 2 } }) do
			local dot = Instance.new("Frame")
			dot.Name = "CardStar" .. index
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(spot[1], spot[2])
			dot.Size = UDim2.fromOffset(spot[3], spot[3])
			dot.BackgroundColor3 = Color3.new(1, 1, 1)
			dot.BackgroundTransparency = 0.45
			dot.BorderSizePixel = 0
			dot.ZIndex = 16
			dot.Parent = card
			GuiStyle.Corner(dot, 1)
		end

		-- #8: a wash across the card rather than a rounded rectangle behind
		-- the artwork. Full width, so it has no side edges to read as a shape.
		ambientLight(card, {
			Name = "IconLight",
			Position = UDim2.new(0.5, 0, 0, if featured then 92 else 34),
			Size = UDim2.new(1, 0, 0, if featured then 320 else 200),
			Color = theme.Aura, Transparency = 0.78, ZIndex = 15,
			Radius = if featured then 0.05 else 0.09,
		})

		-- A second, warmer wash low on the card, so the light has a direction
		-- instead of one even pool in the middle.
		ambientLight(card, {
			Name = "LowerLight",
			Position = UDim2.new(0.5, 0, 0, if featured then 400 else 176),
			Size = UDim2.new(1, 0, 0, if featured then 230 else 140),
			Color = theme.Rim, Transparency = 0.9, ZIndex = 15,
			Radius = if featured then 0.05 else 0.09,
		})
	end

	-- The colour strip across the top: time on the left, status on the right.
	local cardStrip = Instance.new("Frame")
	cardStrip.Name = "Strip"
	cardStrip.Position = UDim2.fromOffset(STRIP_INSET, STRIP_INSET)
	cardStrip.Size = UDim2.new(1, -STRIP_INSET * 2, 0, if featured then 96 else 50)
	cardStrip.BackgroundColor3 = Color3.new(1, 1, 1)
	cardStrip.Visible = true
	cardStrip.ZIndex = 17
	cardStrip.Parent = card
	GuiStyle.Corner(cardStrip, 0.3)
	matchInnerCorner(card, cardStrip, if featured then 0.05 else 0.09)
	GuiStyle.Stroke(cardStrip, theme.StripEdge, 3)
	GuiStyle.Gradient(cardStrip, theme.StripTop, theme.StripBottom)

	do
		-- A darker lip along the bottom of the strip, so it reads as a moulded
		-- band rather than a flat rectangle of colour.
		if featured then
			-- #21: gold star accents on the band, and a bright yellow line along
			-- its top edge. A flat rectangle of orange is what made it read as
			-- a Frame rather than a title plate.
			local topEdge = Instance.new("Frame")
			topEdge.Name = "BandEdge"
			topEdge.AnchorPoint = Vector2.new(0.5, 0)
			topEdge.Position = UDim2.new(0.5, 0, 0, 2)
			topEdge.Size = UDim2.new(1, -16, 0, 3)
			topEdge.BackgroundColor3 = Color3.fromRGB(255, 250, 214)
			topEdge.BackgroundTransparency = 0.25
			topEdge.BorderSizePixel = 0
			topEdge.ZIndex = 19
			topEdge.Parent = cardStrip
			GuiStyle.Corner(topEdge, 1)

			makeSparkle(cardStrip, { Name = "BandSparkleA", Position = UDim2.new(0, 22, 0, 24),
				Size = 17, Color = Color3.fromRGB(255, 252, 206), Transparency = 0.16, ZIndex = 21, Rotation = 14 })
			makeSparkle(cardStrip, { Name = "BandSparkleB", Position = UDim2.new(1, -24, 0, 66),
				Size = 14, Color = Color3.fromRGB(255, 240, 168), Transparency = 0.24, ZIndex = 21, Rotation = -18 })
			makeSparkle(cardStrip, { Name = "BandSparkleC", Position = UDim2.new(1, -34, 0, 20),
				Size = 11, Color = Color3.new(1, 1, 1), Transparency = 0.34, ZIndex = 21, Rotation = 28 })
		end

		local lip = Instance.new("Frame")
		lip.Name = "StripLip"
		lip.AnchorPoint = Vector2.new(0.5, 1)
		lip.Position = UDim2.new(0.5, 0, 1, -2)
		lip.Size = UDim2.new(1, -10, 0, if featured then 10 else 7)
		lip.BackgroundColor3 = theme.StripEdge
		lip.BackgroundTransparency = 0.45
		lip.BorderSizePixel = 0
		lip.ZIndex = 18
		lip.Parent = cardStrip
		GuiStyle.Corner(lip, 1)
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(1, 0)
		fade.Parent = lip
	end

	do
		local gloss = Instance.new("Frame")
		gloss.Name = "Gloss"
		gloss.AnchorPoint = Vector2.new(0.5, 0)
		gloss.Position = UDim2.new(0.5, 0, 0, 3)
		gloss.Size = UDim2.new(1, -12, 0, if featured then 26 else 18)
		gloss.BackgroundColor3 = Color3.new(1, 1, 1)
		gloss.BackgroundTransparency = 0.6
		gloss.BorderSizePixel = 0
		gloss.ZIndex = 18
		gloss.Parent = cardStrip
		GuiStyle.Corner(gloss, 1)
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(0, 1)
		fade.Parent = gloss
	end

	local timeLabel = makeText(if featured then card else cardStrip, {
		Name = "Time",
		AnchorPoint = if featured then Vector2.new(0.5, 0) else Vector2.new(0, 0.5),
		Position = if featured then UDim2.new(0.5, 0, 0, 8) else UDim2.new(0, 13, 0.5, 0),
		Size = if featured then UDim2.new(1, -24, 0, 26) else UDim2.fromOffset(136, 34),
		Text = RewardIcons.FormatDuration(milestone.Seconds),
		TextXAlignment = if featured then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
		TextColor3 = C.Cream, ZIndex = 20, MinTextSize = 13,
		MaxTextSize = if featured then 24 else 32, StrokeThickness = 4,
	})

	local tag = Instance.new("Frame")
	tag.Name = "Tag"
	tag.AnchorPoint = Vector2.new(1, 0.5)
	tag.Position = if featured then UDim2.new(1, -10, 0, 22) else UDim2.new(1, -9, 0.5, 0)
	tag.Size = UDim2.fromOffset(98, 36)
	tag.BackgroundColor3 = COL.Cyan
	tag.Visible = false
	tag.ZIndex = 19
	tag.Parent = if featured then card else cardStrip
	GuiStyle.Corner(tag, 0.5)
	local tagEdge = GuiStyle.Stroke(tag, C.CardEdge, 2.5)

	do
		-- Raised, glossy pill rather than a flat swatch of colour.
		local tagGloss = Instance.new("Frame")
		tagGloss.Name = "Gloss"
		tagGloss.AnchorPoint = Vector2.new(0.5, 0)
		tagGloss.Position = UDim2.new(0.5, 0, 0, 3)
		tagGloss.Size = UDim2.new(1, -10, 0, 13)
		tagGloss.BackgroundColor3 = Color3.new(1, 1, 1)
		tagGloss.BackgroundTransparency = 0.58
		tagGloss.BorderSizePixel = 0
		tagGloss.ZIndex = 20
		tagGloss.Parent = tag
		GuiStyle.Corner(tagGloss, 1)
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(0, 1)
		fade.Parent = tagGloss
	end
	do
		-- A shadow under the pill, so the three states read as the same
		-- physical object with different paint on it.
		local drop = Instance.new("Frame")
		drop.Name = "TagShadow"
		drop.AnchorPoint = Vector2.new(0.5, 0.5)
		drop.Position = UDim2.new(0.5, 0, 0.5, 3)
		drop.Size = UDim2.new(1, -4, 1, -2)
		drop.BackgroundColor3 = C.Ink
		drop.BackgroundTransparency = 0.55
		drop.BorderSizePixel = 0
		drop.ZIndex = 18
		drop.Parent = tag
		GuiStyle.Corner(drop, 0.5)
	end

	local tagText = makeText(tag, {
		Name = "Text", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.86, 0, 0.66, 0), Text = "NEXT", ZIndex = 21, MinTextSize = 11, MaxTextSize = 23, StrokeThickness = 2.5,
	})

	local title
	if featured then
		title = makeText(card, {
			-- Sitting on the gold band rather than floating on the body.
			-- #22: COSMIC JACKPOT dominates and 6 HR reads as its kicker, rather
			-- than the two competing at similar weight.
			Name = "Title", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 38),
			Size = UDim2.new(1, -14, 0, 52), Text = string.upper(milestone.Name or "Jackpot"),
			TextWrapped = true, TextColor3 = Color3.fromRGB(255, 246, 196),
			ZIndex = 20, Gloss = true, StrokeThickness = 6, MinTextSize = 18, MaxTextSize = 44,
		})

		softGlow(card, {
			Name = "BandGlow", AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, -16), Size = UDim2.new(1, 44, 0, 150),
			Color = Color3.fromRGB(255, 176, 48), Transparency = 0.74, ZIndex = 16, Radius = 0.4,
		})

		-- Nebula behind the gift, then the gift, then sparkles around it.
		softGlow(card, {
			Name = "Nebula", AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.new(1, 48, 0, 320),
			Color = Color3.fromRGB(226, 96, 255), Transparency = 0.36, ZIndex = 16, Radius = 0.5,
		})

		-- Two objects, so the idle float and the hover scale never share a
		-- property: the wrapper owns Position, the art owns its UIScale.
		local float = Instance.new("Frame")
		float.Name = "GiftFloat"
		float.AnchorPoint = Vector2.new(0.5, 0)
		float.Position = UDim2.new(0.5, 0, 0, 104)
		float.Size = UDim2.fromOffset(268, 268)
		float.BackgroundTransparency = 1
		float.ZIndex = 19
		float.Parent = card

		local art = Instance.new("Frame")
		art.Name = "Art"
		art.Size = UDim2.fromScale(1, 1)
		art.BackgroundTransparency = 1
		art.ZIndex = 19
		art.Parent = float
		RewardIcons.Draw(art, "jackpot", { zIndex = 19, stroke = 3 })

		-- An orbit behind the gift: a wide flattened ring with a bright edge.
		-- Declared outside the block so the idle animation below can drive it.
		local orbit
		do
			orbit = Instance.new("Frame")
			orbit.Name = "Orbit"
			orbit.AnchorPoint = Vector2.new(0.5, 0.5)
			orbit.Position = UDim2.new(0.5, 0, 0, 246)
			orbit.Size = UDim2.fromOffset(392, 142)
			orbit.BackgroundTransparency = 1
			orbit.BorderSizePixel = 0
			orbit.Rotation = -12
			orbit.ZIndex = 17
			orbit.Parent = card
			GuiStyle.Corner(orbit, 1)
			local ring = GuiStyle.Stroke(orbit, Color3.fromRGB(244, 152, 255), 5)
			ring.Transparency = 0.22

			local outer = Instance.new("Frame")
			outer.Name = "OrbitGlow"
			outer.AnchorPoint = Vector2.new(0.5, 0.5)
			outer.Position = UDim2.fromScale(0.5, 0.5)
			outer.Size = UDim2.new(1, 22, 1, 22)
			outer.BackgroundTransparency = 1
			outer.BorderSizePixel = 0
			outer.ZIndex = 17
			outer.Parent = orbit
			GuiStyle.Corner(outer, 1)
			local halo = GuiStyle.Stroke(outer, Color3.fromRGB(206, 128, 255), 14)
			halo.Transparency = 0.82

			-- #24: the two rings were reading as geometry. A violet bloom under
			-- them and three points ON the path turn the same shapes into a
			-- lit orbit rather than a pair of ellipses.
			softGlow(card, {
				Name = "OrbitBloom", AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 246), Size = UDim2.fromOffset(430, 210),
				Color = Color3.fromRGB(186, 96, 255), Transparency = 0.7, ZIndex = 16, Radius = 1,
			})

			for index, point in ipairs({
				{ 0.5, -176, 0, 4 }, { 0.5, 164, 18, 3 }, { 0.5, -42, -58, 3 },
				}) do
				local speck = Instance.new("Frame")
				speck.Name = "OrbitStar" .. index
				speck.AnchorPoint = Vector2.new(0.5, 0.5)
				speck.Position = UDim2.new(point[1], point[2], 0, 246 + point[3])
				speck.Size = UDim2.fromOffset(point[4], point[4])
				speck.BackgroundColor3 = Color3.fromRGB(250, 226, 255)
				speck.BackgroundTransparency = 0.2
				speck.BorderSizePixel = 0
				speck.ZIndex = 18
				speck.Parent = card
				GuiStyle.Corner(speck, 1)
			end
		end

		makeSparkle(card, { Name = "JackpotSparkleA", Position = UDim2.new(0.5, -136, 0, 126),
			Size = 32, Color = Color3.fromRGB(255, 224, 120), Transparency = 0.06, ZIndex = 21, Rotation = 12 })
		makeSparkle(card, { Name = "JackpotSparkleB", Position = UDim2.new(0.5, 134, 0, 272),
			Size = 26, Color = Color3.fromRGB(246, 160, 255), Transparency = 0.12, ZIndex = 21, Rotation = -16 })
		makeSparkle(card, { Name = "JackpotSparkleC", Position = UDim2.new(0.5, 126, 0, 116),
			Size = 19, Color = Color3.new(1, 1, 1), Transparency = 0.2, ZIndex = 21, Rotation = 30 })
		makeSparkle(card, { Name = "JackpotSparkleD", Position = UDim2.new(0.5, -120, 0, 290),
			Size = 17, Color = Color3.fromRGB(255, 236, 170), Transparency = 0.26, ZIndex = 21, Rotation = -8 })
		makeSparkle(card, { Name = "JackpotSparkleE", Position = UDim2.new(0.5, 0, 0, 108),
			Size = 14, Color = C.EdgeCyan, Transparency = 0.34, ZIndex = 21, Rotation = 22 })
		-- Layer 1. Three pixels over four seconds, on Position. The old version
		-- was a 1.2s 6% scale on this same artwork, which is why the whole
		-- jackpot looked like it was pumping.
		float.Position = UDim2.new(0.5, 0, 0, 107)
		TweenService:Create(float,
			TweenInfo.new(2.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.new(0.5, 0, 0, 101) }):Play()

		-- Layer 2. A drift, not a rotation: the ring is a flattened ellipse, so
		-- a full turn would sweep it from lying down to standing up and read as
		-- tumbling. Nine seconds each way between -18 and -6 degrees.
		orbit.Rotation = -18
		TweenService:Create(orbit,
			TweenInfo.new(9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Rotation = -6 }):Play()

		-- Layer 3. Each on its own clock.
		for index, spark in ipairs({
			card:FindFirstChild("JackpotSparkleA"), card:FindFirstChild("JackpotSparkleB"),
			card:FindFirstChild("JackpotSparkleC"), card:FindFirstChild("JackpotSparkleD"),
			card:FindFirstChild("JackpotSparkleE"),
			}) do
			twinkle(spark, (index * 0.37) % 1, 1.7 + index * 0.3)
		end

		-- Hover: the gift grows by 2.5% and the gold line brightens. No card
		-- translation -- in compact this card is a UIGridLayout child and the
		-- layout owns its Position -- and no panel scale, which is the whole
		-- point of this pass.
		local hoverScale = Instance.new("UIScale")
		hoverScale.Name = "GiftHover"
		hoverScale.Parent = art

		local hoverTweens = {}
		local function hover(on)
			for _, tween in ipairs(hoverTweens) do tween:Cancel() end
			table.clear(hoverTweens)
			local info = TweenInfo.new(if on then 0.18 else 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			table.insert(hoverTweens, TweenService:Create(hoverScale, info, { Scale = if on then 1.025 else 1 }))
			if goldLine then
				table.insert(hoverTweens, TweenService:Create(goldLine, info, { Transparency = if on then 0.18 else 0.5 }))
			end
			for _, tween in ipairs(hoverTweens) do tween:Play() end
		end

		card.MouseEnter:Connect(function() hover(true) end)
		card.MouseLeave:Connect(function() hover(false) end)
	end

	local iconsRow, lines = rewardRows(card, milestone, if featured then {
		iconsTop = 380, iconZone = 73, iconLarge = 73, iconSmall = 73, iconPad = 5,
		linesBottom = 610, lineHeight = 28, lineText = 26, linesLead = 10, zIndex = 19,
	} else {
			iconsTop = 56, iconZone = 140, iconLarge = 140, iconSmall = 92, iconPad = 7,
			linesBottom = 258, lineHeight = 24, lineText = 22, zIndex = 19,
		})

	-- Action area: countdown / CLAIM / CLAIMED
	local action = Instance.new("Frame")
	action.Name = "Action"
	action.AnchorPoint = Vector2.new(0.5, 1)
	action.Position = UDim2.new(0.5, 0, 1, if featured then -12 else -10)
	action.Size = UDim2.new(1, -22, 0, if featured then 60 else 54)
	action.BackgroundColor3 = Color3.new(1, 1, 1)   -- gradient carries the colour
	action.BackgroundTransparency = 0.05
	action.ZIndex = 18
	action.Parent = card
	GuiStyle.Corner(action, 0.35)
	GuiStyle.Stroke(action, C.CardEdge, 3)
	if featured then
		-- #27: a deeper navy with a brighter blue midtone, so the jackpot's
		-- countdown looks like part of the gold card rather than a card row.
		GuiStyle.Gradient(action, Color3.fromRGB(62, 100, 208), Color3.fromRGB(10, 20, 70))
	else
		GuiStyle.Gradient(action, Color3.fromRGB(46, 78, 176), Color3.fromRGB(14, 26, 84))
	end

	do
		local rim = Instance.new("Frame")
		rim.Name = "Rim"
		rim.Position = UDim2.fromOffset(3, 3)
		rim.Size = UDim2.new(1, -6, 1, -6)
		rim.BackgroundTransparency = 1
		rim.ZIndex = 19
		rim.Parent = action
		GuiStyle.Corner(rim, 0.35)
		local edge = GuiStyle.Stroke(rim, C.EdgeCyan, 2)
		edge.Transparency = 0.34

		local gloss = Instance.new("Frame")
		gloss.Name = "Gloss"
		gloss.AnchorPoint = Vector2.new(0.5, 0)
		gloss.Position = UDim2.new(0.5, 0, 0, 4)
		gloss.Size = UDim2.new(1, -16, 0, 17)
		gloss.BackgroundColor3 = Color3.new(1, 1, 1)
		gloss.BackgroundTransparency = 0.68
		gloss.BorderSizePixel = 0
		gloss.ZIndex = 19
		gloss.Parent = action
		GuiStyle.Corner(gloss, 1)
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(0, 1)
		fade.Parent = gloss
	end
	local progress = Instance.new("Frame")
	progress.Name = "Progress"
	progress.Size = UDim2.fromScale(0, 1)
	progress.BackgroundColor3 = COL.Blue
	progress.BackgroundTransparency = 0.45
	progress.ZIndex = 18
	progress.Parent = action
	GuiStyle.Corner(progress, 0.3)
	local actionText = makeText(action, {
		Name = "Text", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.62, 0), Text = "", ZIndex = 20, MinTextSize = 13,
		MaxTextSize = if featured then 30 else 27, StrokeThickness = 3,
	})

	-- The artwork slot is CENTRED on the action region rather than sitting on
	-- the card's bottom edge, and it is oversized: roughly 55% of each asset's
	-- height is the pill and the rest is transparent margin, which Fit keeps.
	-- A slot the size of the old drawn button would render a much smaller pill.
	-- The margin hanging over the text above is invisible and costs nothing.
	--
	-- Normal card: action 260..314, centre 287, slot 86 -> pill about 47.
	-- Jackpot:     action 614..674, centre 644, slot 92 -> pill about 51.
	-- If the button ever reads too small or too large, these two heights are
	-- the only numbers to change.
	local claimButton, claimLabel
	if BUTTON_ART then
		claimButton, claimLabel = imageButton(card, {
			Name = "Claim", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 1, if featured then -42 else -37),
			Size = UDim2.new(1, -8, 0, if featured then 92 else 86),
			Image = BUTTON_ART.Claim, Text = "CLAIM", ZIndex = 22,
		})
	else
		claimButton, claimLabel = greenButton(card, {
			Name = "Claim", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, if featured then -12 else -10),
			Size = UDim2.new(1, -22, 0, if featured then 60 else 54), Text = "CLAIM", ZIndex = 22, MaxTextSize = 34,
		})
	end
	claimButton.Visible = false

	local entry = {
		index = index, milestone = milestone, featured = featured, frame = card,
		stroke = stroke, rim = rimEdge, baseRim = theme.Rim, pop = pop,
		timeLabel = timeLabel, tag = tag, tagText = tagText, tagEdge = tagEdge,
		title = title, iconsRow = iconsRow, lines = lines,
		action = action, progress = progress, actionText = actionText, claimButton = claimButton,
		claimLabel = claimLabel, state = nil, busy = false,
	}
	cards[index] = entry
	return entry
end

for index = 1, COUNT do
	makeCard(index, Config.Milestones[index].Featured == true)
end

-- Featured panel on wide screens: the featured card is moved out of the list.
local featuredHolder = Instance.new("Frame")
featuredHolder.Name = "Featured"
featuredHolder.BackgroundTransparency = 1
featuredHolder.ZIndex = 12
featuredHolder.Parent = interior

local featuredScale = Instance.new("UIScale")
featuredScale.Name = "BodyScale"
featuredScale.Parent = featuredHolder

-- ===================== LAYOUT =====================
local compact = false

local function applyLayout()
	-- 1420 x 982, and both numbers are load-bearing:
	--   width  - the interior is 1398, the featured column takes 400 plus a 14
	--            gutter, leaving a 964 scroll. Less its own 16 of padding that
	--            is a 948 grid: exactly three 305 cards with 16 between.
	--   height - the body is 686. Less the scroll's 6 top and 16 bottom
	--            padding that is 664, which is exactly two 324 rows plus the
	--            16 gap. Get the padding wrong and the row below peeks in.
	local scale, width, height = 1, 1420, 982
	if UiResponsive then
		scale, width, height = UiResponsive.FitPanel(1420, 982, { minWidth = 560, minHeight = 380, margin = 16,
			-- Phones: leave game visible around it (~86% x 82% of the usable screen).
			shareW = if UiResponsive.Layout() == "compact" then 0.86 else nil,
			shareH = if UiResponsive.Layout() == "compact" then 0.9 else nil })
	else
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		scale = math.clamp(math.min(viewport.X / 980, viewport.Y / 640), 0.5, 1)
	end
	popupScale.Scale = scale
	-- Text minimums follow the window's scale, so on a phone text shrinks to
	-- fit its box instead of being cut off ("READ" for "READY").
	local textShrink = math.min(1, scale * 0.6)
	for _, constraint in ipairs(popup:GetDescendants()) do
		if constraint:IsA("UITextSizeConstraint") then
			local base = constraint:GetAttribute("BaseMin")
			if type(base) == "number" then
				constraint.MinTextSize = math.max(1, math.floor(base * textShrink))
			end
		end
	end
	popup.Size = UDim2.fromOffset(width, height)
	compact = width < 800

	-- Short windows (landscape phones): the header and progress strip are
	-- drawn at 72%, still full width, and the body starts higher - so the
	-- reward cards get about twice the height instead of a thin strip.
	local k = if height < 640 then 0.55 else 1
	headerFit.Scale = k
	header.Size = UDim2.new(1 / k, 0, 0, HEADER_H)
	stripFit.Scale = k
	strip.Position = UDim2.fromOffset(12, math.floor((HEADER_H + 14) * k + 0.5))
	strip.Size = UDim2.new(1 / k, -24 / k, 0, 78)
	local bodyTop = math.floor(BODY_TOP * k + 0.5)
	scroll.Position = UDim2.fromOffset(10, bodyTop)
	-- The close button keeps a comfortable size inside the smaller header.
	local closeSize = math.floor(62 * (if k < 1 then 0.85 / k else 1) + 0.5)
	closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	local closeShadow = header:FindFirstChild("CloseShadow")
	if closeShadow then closeShadow.Size = UDim2.fromOffset(closeSize + 6, closeSize + 6) end

	-- Header on narrow windows: the "New day in" pill drops to the subtitle's
	-- row and shrinks, and the subtitle narrows, so title / subtitle / timer /
	-- close never touch. The title keeps its full size. (Measured in the
	-- header's own units, which are wider when the header is drawn smaller.)
	local narrowHeader = (width - 22) / k < 1100
	resetPillFit.Scale = if narrowHeader then 0.74 else 1
	resetPill.Position = if narrowHeader then UDim2.new(1, -104, 0, 129) else UDim2.new(1, -104, 0.5, 0)
	local subtitle = header:FindFirstChild("Subtitle")
	if subtitle then
		subtitle.Size = UDim2.fromOffset(if narrowHeader then math.max((width - 22) / k - 170 - 104 - 250, 200) else 540, 34)
	end

	-- Everything below lives inside the interior frame, which is inset 11 a
	-- side, so the usable width is 22 less than the window's.
	local innerWidth = width - 22
	local bodyHeight = height - 22 - bodyTop - 10
	local featuredWidth = if compact then 0 else 400
	local bodyWidth = innerWidth - 20 - (if compact then 0 else featuredWidth + 14)

	-- FitPanel holds the scale at 1 on a desktop and shrinks the panel's HEIGHT
	-- when the screen is short, so a 1600x900 display gets 1360x868 rather than
	-- a smaller 1360x968. The card design needs 672 of body, so the body is
	-- scaled to whatever height it actually got and then laid out in the full
	-- 672 regardless. Two whole rows everywhere, one card design.
	local DESIGN_BODY = 686
	local fit = math.clamp(bodyHeight / DESIGN_BODY, 0.55, 1)
	scrollScale.Scale = fit
	featuredScale.Scale = fit

	-- Sizes are in the scaled space, so these still render at bodyWidth x
	-- bodyHeight pixels. Both frames anchor top-left, which is what a UIScale
	-- scales around, so neither moves.
	local localWidth = math.floor(bodyWidth / fit)
	local localHeight = math.floor(bodyHeight / fit)
	scroll.Size = UDim2.fromOffset(localWidth, localHeight)
	featuredHolder.Position = UDim2.fromOffset(innerWidth - 10 - featuredWidth, bodyTop)
	featuredHolder.Size = UDim2.fromOffset(math.floor(featuredWidth / fit), localHeight)
	featuredHolder.Visible = not compact

	-- Cards: as many 292px columns as fit, never fewer than two. All in the
	-- scaled space, so a column is always a full-size card design.
	local gridWidth = localWidth - 16
	-- Capped at three. Scaling the body to a short screen inflates its local
	-- width, and uncapped that turns 1366x768 into four narrow columns -- a
	-- different composition from the one this panel is designed around. Three
	-- columns simply get wider there instead, and still hold six cards in the
	-- two rows the body has room for.
	local columns = math.clamp(math.floor((gridWidth + 16) / (305 + 16)), 2, 3)
	local cellWidth = math.floor((gridWidth - (columns - 1) * 16) / columns)
	grid.CellSize = UDim2.fromOffset(cellWidth, 324)

	for _, card in pairs(cards) do
		-- Shrink the icon row if the card it is in is narrower than the row
		-- wants to be. 1 on every desktop layout; only phones ever go below.
		-- rowFit, not fit: `fit` above is the body's scale factor, and a second
		-- local of that name here shadowed it for the rest of the loop, so the
		-- featuredWidth / fit below divided a number by a UIScale.
		local row = card.iconsRow
		local rowFit = row and row:FindFirstChild("Fit")
		local content = row and row:GetAttribute("ContentWidth")
		if rowFit and type(content) == "number" and content > 0 then
			local available = (if card.featured and not compact then math.floor(featuredWidth / fit) else cellWidth) - 12
			rowFit.Scale = math.clamp(available / content, 0.55, 1)
		end

		if card.featured then
			if compact then
				-- A normal-size row in the list on small screens.
				card.frame.Parent = scroll
				card.frame.Size = UDim2.fromOffset(cellWidth, 324)
			else
				card.frame.Parent = featuredHolder
				card.frame.Size = UDim2.fromScale(1, 1)
			end
			if card.title then card.title.Visible = not compact end
			local art = card.frame:FindFirstChild("Art")
			if art then art.Visible = not compact end
			-- The jackpot has a gold band of its own, so this only changes its
			-- height. At 92 it carries "6 HR" over the title; on a phone the
			-- card becomes a normal list row and the band matches the rest
			-- at 50.
			-- cardStrip, not strip: `strip` at the top of the file is the
			-- progress band. Nothing below used it, but the same reuse one
			-- block up is what broke this function.
			local cardStrip = card.frame:FindFirstChild("Strip")
			if cardStrip then
				cardStrip.Visible = true
				cardStrip.Size = UDim2.new(1, -STRIP_INSET * 2, 0, if compact then 50 else 96)
			end
			-- Same two rules as rewardRows: the icon row centres in its zone and
			-- the lines stack up from a fixed baseline. Compact shows two of
			-- them, so its block is two lines tall rather than five.
			-- In the list the jackpot is a normal 317-tall card, so its action
			-- strip has to be a normal one too. Left at the featured 56/-12 its
			-- top edge lands at 249 and the two reward lines end at 253.
			local actionHeight = if compact then 54 else 60
			local actionInset = if compact then -10 else -12
			card.action.Size = UDim2.new(1, -22, 0, actionHeight)
			card.action.Position = UDim2.new(0.5, 0, 1, actionInset)
			if BUTTON_ART then
				-- The artwork button anchors on its CENTRE, so it tracks the
				-- middle of the action region rather than its bottom edge.
				-- Sized to the drawn button instead, it would sit half a slot
				-- too low and render a pill the wrong size.
				card.claimButton.Size = UDim2.new(1, -8, 0, if compact then 86 else 92)
				card.claimButton.Position = UDim2.new(0.5, 0, 1, actionInset - actionHeight // 2)
			else
				card.claimButton.Size = UDim2.new(1, -22, 0, actionHeight)
				card.claimButton.Position = UDim2.new(0.5, 0, 1, actionInset)
			end

			card.iconsRow.Position = UDim2.new(0.5, 0, 0, if compact then 56 + 140 // 2 else 380 + 73 // 2)
			local shown = if compact then 2 else #card.lines
			local lineHeight = if compact then 24 else 28
			local lead = if compact then 0 else 10
			local top = (if compact then 258 else 610) - shown * lineHeight - lead
			for i, line in ipairs(card.lines) do
				line.label.Position = UDim2.new(0.5, 0, 0, top + (i - 1) * lineHeight + (if i > 1 then lead else 0))
				-- On the small card, only the first two reward lines fit.
				line.label.Visible = not compact or i <= 2
			end
		end
	end
end

-- Through a pcall, because applyLayout runs at the top level: an error in it
-- used to stop this script before it reached the line that connects the HUD
-- button, so a layout fault meant the popup could not be opened at all. The
-- error is still printed; it is just no longer fatal.
local function safeLayout()
	local ok, err = pcall(applyLayout)
	if not ok then
		warn("[PlaytimeAwards] layout failed, the popup still opens: " .. tostring(err))
	end
end

safeLayout()
if UiResponsive then
	UiResponsive.Changed:Connect(safeLayout)
end

-- ===================== STATE =====================
local lastSync = os.clock()
player:GetAttributeChangedSignal("PlaytimeToday"):Connect(function()
	lastSync = os.clock()
end)

local function played()
	return (tonumber(player:GetAttribute("PlaytimeToday")) or 0) + (os.clock() - lastSync)
end

local function isClaimed(mask, index)
	return bit32.band(mask, bit32.lshift(1, index - 1)) ~= 0
end

local function lineText(item)
	local info = RewardIcons.Describe(item, income, Config.StardustFor)
	if item.Type == "Stardust" or item.Type == "XP" or item.Type == "Gems" then
		return info.value
	end
	return info.title .. " • " .. info.value
end

local firstPass = true

local function setState(card, state, remaining, fraction)
	local changed = card.state ~= state
	card.state = state

	if changed then
		-- READY and CLAIMED are both the artwork button, with different
		-- pictures; only a locked or next reward uses the countdown frame.
		-- Active is set as well as the picture, so a claimed card cannot fire
		-- the claim path however it looks.
		local onButton = state == "ready" or (state == "claimed" and BUTTON_ART ~= nil)
		card.claimButton.Visible = onButton
		card.action.Visible = not onButton
		if BUTTON_ART then
			card.claimButton.Image = if state == "claimed" then BUTTON_ART.Claimed else BUTTON_ART.Claim
			card.claimButton.Active = state == "ready"
			card.claimButton.AutoButtonColor = false
			if card.claimLabel then
				card.claimLabel.Text = if state == "claimed" then "CLAIMED" else "CLAIM"
			end
		end
		-- The state colour goes on the card's bright rim. The outer stroke is
		-- the dark silhouette and stays dark: recolouring that was what turned
		-- a lit card back into an outlined box.
		if card.rim then
			card.rim.Color = STATE_COLORS[state] or card.baseRim
			card.rim.Thickness = if state == "ready" or state == "next" then 3.5 else 2.5
		end
		card.tag.Visible = state == "next" or state == "claimed" or state == "ready"
		card.tagText.Text = if state == "next" then "NEXT" elseif state == "ready" then "READY" else "DONE"
		-- One family: READY is lime, NEXT is navy with a cyan edge, DONE is a
		-- desaturated slate. Only the fill and the rim change.
		local paint = TAG_PAINT[state] or TAG_PAINT.claimed
		card.tag.BackgroundColor3 = paint.Fill
		if card.tagEdge then
			card.tagEdge.Color = paint.Edge
		end
		card.tagText.TextColor3 = paint.Text
		card.frame.BackgroundTransparency = if state == "claimed" then 0.35 else 0.04
		-- The time now sits on a bright colour strip, so it reads cream rather
		-- than cyan; cyan on cyan was the one combination to avoid.
		card.timeLabel.TextColor3 = if state == "claimed" then Color3.fromRGB(198, 210, 236) else C.Cream
		for _, object in ipairs(card.iconsRow:GetDescendants()) do
			if object:IsA("Frame") and object.Name == "Badge" then
				object.BackgroundTransparency = if state == "claimed" then 0.5 else 0
			end
		end
		if state == "ready" and not firstPass then
			card.pop.Scale = 0.94
			TweenService:Create(card.pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end

	if state == "claimed" then
		card.actionText.Text = if BUTTON_ART then "" else "✓ CLAIMED"
		card.actionText.TextColor3 = Color3.fromRGB(150, 235, 160)
		card.progress.Size = UDim2.fromScale(1, 1)
		card.progress.BackgroundColor3 = COL.GreenDark
	elseif state ~= "ready" then
		card.actionText.Text = "IN " .. RewardIcons.FormatClock(remaining)
		card.actionText.TextColor3 = if state == "next" then WHITE else COL.Muted
		card.progress.Size = UDim2.fromScale(math.clamp(fraction or 0, 0, 1), 1)
		card.progress.BackgroundColor3 = COL.Blue
	end

	for _, line in ipairs(card.lines) do
		line.label.Text = lineText(line.item)
		line.label.TextColor3 = if state == "claimed" then COL.Muted else COL.Light
	end
end

-- HUD button + "!" badge -------------------------------------------------------------
local hud = playerGui:WaitForChild("MainHUD")
local playSlot = hud:WaitForChild("PlaytimeSlot")
local openButton = playSlot:FindFirstChild("Playtime Awards") or playSlot:FindFirstChild("PlaytimeAwardsButton")
if not openButton then
	local started = os.clock()
	while os.clock() - started < 15 and not openButton do
		task.wait(0.1)
		openButton = playSlot:FindFirstChild("Playtime Awards") or playSlot:FindFirstChild("PlaytimeAwardsButton")
	end
end

-- The badge is artwork now. It used to be a TextLabel with the letter "!" in
-- it, which is why nothing that went looking for an ImageLabel ever found it.
--
-- ReadyBadge keeps its name, its place and its one job: `hudBang.Visible` is
-- still what the reward logic below toggles. It is now a container holding the
-- picture, with the old drawn badge underneath as the fallback.
local hudBang = Instance.new("Frame")
hudBang.Name = "ReadyBadge"
hudBang.AnchorPoint = Vector2.new(0.5, 0.5)
-- On the button's top-right corner, sitting a little lower than before. The
-- slot is 273x206 and the artwork fills it exactly, so 0.82/0.19 puts the
-- badge's 52px square at 198..250 by 13..65 - inside the button on all sides.
hudBang.Position = UDim2.fromScale(0.82, 0.19)
hudBang.Size = UDim2.fromOffset(52, 52)
hudBang.BackgroundTransparency = 1
hudBang.Visible = false
hudBang.ZIndex = 10
hudBang.Parent = playSlot

local drawnBang = Instance.new("TextLabel")
drawnBang.Name = "DrawnBang"
drawnBang.AnchorPoint = Vector2.new(0.5, 0.5)
drawnBang.Position = UDim2.fromScale(0.5, 0.5)
drawnBang.Size = UDim2.fromScale(0.78, 0.78)
drawnBang.BackgroundColor3 = Color3.fromRGB(255, 80, 150)
drawnBang.Font = FONT
drawnBang.Text = "!"
drawnBang.TextScaled = true
drawnBang.TextColor3 = WHITE
drawnBang.ZIndex = 10
drawnBang.Parent = hudBang
GuiStyle.Corner(drawnBang, 1)
GuiStyle.Stroke(drawnBang, COL.Outline, 2)

do
	local ALERT_ID = "rbxassetid://135785875501572"
	local ok, assets = pcall(function()
		local module = ReplicatedStorage:FindFirstChild("UIAssets")
		return module and require(module)
	end)
	if ok and type(assets) == "table"
		and type(assets.PlaytimeAlert) == "string" and assets.PlaytimeAlert ~= "" then
		ALERT_ID = assets.PlaytimeAlert
	end

	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(1, 1)
	art.BackgroundTransparency = 1
	art.BorderSizePixel = 0
	art.Active = false
	art.Image = ALERT_ID
	art.ScaleType = Enum.ScaleType.Fit
	art.ZIndex = 11
	art.Parent = hudBang

	-- Roblox only fetches an image for a label it is actually drawing, and this
	-- badge spends most of its life hidden, so there is no point asking whether
	-- it loaded at startup - the answer would always be no. The check runs
	-- whenever the badge is actually on screen instead, and stops the moment it
	-- is hidden again so nothing is left spinning.
	local function confirmArtwork()
		if not hudBang.Visible then return end

		task.spawn(function()
			local giveUp = os.clock() + 60
			while hudBang.Visible and os.clock() < giveUp do
				if art.IsLoaded then
					drawnBang.Visible = false
					return
				end
				task.wait(0.4)
			end
		end)
	end

	hudBang:GetPropertyChangedSignal("Visible"):Connect(confirmArtwork)
	confirmArtwork()
end

-- ===== BADGE MOTION =====
-- Squash and stretch, driven through Size and a vertical offset. A UIScale
-- would be uniform, and uniform scaling is exactly what makes a bounce look
-- mechanical: a real one is taller and narrower on the way up, then wider and
-- flatter when it lands.
do
	local BADGE = Vector2.new(52, 52)
	local HOME = UDim2.fromScale(0.82, 0.19)

	local IDLE_HOP = true
	local IDLE_GAP = 2.4

	-- Bumped whenever something new takes over the badge, so a hop that is
	-- half finished stops instead of fighting the pop-in.
	local motionToken = 0

	local function reducedMotion()
		return player:GetAttribute("ReduceMotion") == true
	end

	local function shapeTween(width, height, lift, seconds, style, direction)
		return TweenService:Create(hudBang,
			TweenInfo.new(seconds, style, direction), {
				Size = UDim2.fromOffset(math.floor(width), math.floor(height)),
				Position = HOME + UDim2.fromOffset(0, lift),
			})
	end

	local function rest()
		hudBang.Size = UDim2.fromOffset(BADGE.X, BADGE.Y)
		hudBang.Position = HOME
	end

	-- Arriving: small and low, overshoot, settle. The overshoot is what sells
	-- it as a pop rather than a fade.
	local function popIn()
		motionToken += 1
		local token = motionToken

		if reducedMotion() then
			rest()
			return
		end

		hudBang.Size = UDim2.fromOffset(BADGE.X * 0.4, BADGE.Y * 0.4)
		hudBang.Position = HOME + UDim2.fromOffset(0, 8)

		local grow = shapeTween(BADGE.X * 1.26, BADGE.Y * 1.3, -8, 0.22,
			Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		grow:Play()

		grow.Completed:Connect(function()
			if token ~= motionToken then return end
			shapeTween(BADGE.X, BADGE.Y, 0, 0.13,
				Enum.EasingStyle.Quad, Enum.EasingDirection.Out):Play()
		end)
	end

	-- The hop, in five beats. The extra one is the important one: at the top
	-- it stops stretching and swells to 122% in both directions for a moment,
	-- which is the "it got bigger" read. A hop without it is just movement;
	-- with it the badge grows and shrinks, which is what catches the eye.
	--
	--   crouch  114% x  82%   +5   0.11s  squash down, ready to go
	--   rise     88% x 128%  -22   0.20s  stretch tall, real lift
	--   hang    122% x 122%  -26   0.10s  BIG at the top
	--   land    124% x  80%   +4   0.13s  splat
	--   settle  100%           0   0.34s  overshoot back to rest
	local function hop()
		local token = motionToken

		local function stillOurs()
			return token == motionToken and hudBang.Visible and not reducedMotion()
		end

		local beats = {
			{ 1.14, 0.82, 5, 0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out },
			{ 0.88, 1.28, -22, 0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out },
			{ 1.22, 1.22, -26, 0.10, Enum.EasingStyle.Sine, Enum.EasingDirection.Out },
			{ 1.24, 0.80, 4, 0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In },
		}

		for _, beat in ipairs(beats) do
			if not stillOurs() then return end
			local step = shapeTween(BADGE.X * beat[1], BADGE.Y * beat[2],
				beat[3], beat[4], beat[5], beat[6])
			step:Play()
			step.Completed:Wait()
		end

		if not stillOurs() then return end
		shapeTween(BADGE.X, BADGE.Y, 0, 0.34,
			Enum.EasingStyle.Back, Enum.EasingDirection.Out):Play()
	end

	rest()
	hudBang:GetPropertyChangedSignal("Visible"):Connect(function()
		if hudBang.Visible then
			popIn()
		else
			motionToken += 1
			rest()
		end
	end)

	if IDLE_HOP then
		task.spawn(function()
			while hudBang.Parent do
				task.wait(IDLE_GAP)
				if hudBang.Visible and not reducedMotion() then
					hop()
				end
			end
		end)
	end
end

-- The strip updates twice a second and the value creeps, so setting it
-- directly is a visible stair-step. A tween only for changes worth animating;
-- a claim resets the bar to zero and that should be instant, not a slide.
local stripShown = 0
local stripTween = nil

local function setStripFill(value)
	value = math.clamp(value, 0, 1)
	local delta = value - stripShown
	stripShown = value
	if stripTween then
		stripTween:Cancel()
		stripTween = nil
	end
	if delta <= 0 or delta > 0.25 then
		stripFill.Size = UDim2.fromScale(value, 1)
		return
	end
	stripTween = TweenService:Create(stripFill,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(value, 1) })
	stripTween:Play()
end

local function updateAll()
	local now = played()
	local mask = tonumber(player:GetAttribute("PlaytimeClaimedMask")) or 0
	income = tonumber(player:GetAttribute("PlaytimeIncomeSnapshot")) or 0
	local ready, nextIndex = 0, nil

	for index = 1, COUNT do
		if not isClaimed(mask, index) and now < Config.Milestones[index].Seconds then
			nextIndex = index
			break
		end
	end

	local previousSeconds = 0
	for index = 1, COUNT do
		local card = cards[index]
		local seconds = card.milestone.Seconds
		if isClaimed(mask, index) then
			setState(card, "claimed")
		elseif now >= seconds then
			ready += 1
			setState(card, "ready")
		else
			local fraction = (now - previousSeconds) / math.max(seconds - previousSeconds, 1)
			setState(card, if index == nextIndex then "next" else "locked", seconds - now, if index == nextIndex then fraction else 0)
		end
		previousSeconds = seconds
	end

	-- Strip: time played, next reward and the day reset.
	local endsAt = tonumber(player:GetAttribute("PlaytimeWindowEndsAt")) or 0
	resetText.Text = if endsAt > 0 then "New day in " .. RewardIcons.FormatClock(endsAt - os.time()) else "New day in --:--"
	if nextIndex then
		local target = Config.Milestones[nextIndex].Seconds
		local from = if nextIndex > 1 then Config.Milestones[nextIndex - 1].Seconds else 0
		stripText.Text = ("Played today %s  •  Next reward in %s"):format(RewardIcons.FormatClock(now), RewardIcons.FormatClock(target - now))
		setStripFill((now - from) / math.max(target - from, 1))
	else
		stripText.Text = ("Played today %s  •  Every reward unlocked!"):format(RewardIcons.FormatClock(now))
		setStripFill(1)
	end

	-- The count is still calculated; it is simply no longer rendered, because
	-- the approved artwork says "CLAIM ALL" and nothing else.
	if BUTTON_ART then
		claimAllButton.Image = if ready > 0 then BUTTON_ART.ClaimAll else BUTTON_ART.AllClaimed
		claimAllButton.Active = ready > 0
		claimAllLabel.Text = if ready > 0 then "CLAIM ALL" else "ALL CLAIMED"
	else
		claimAllLabel.Text = if ready > 1 then ("CLAIM ALL (" .. ready .. ")") elseif ready == 1 then "CLAIM" else "NOTHING READY"
		setButtonEnabled(claimAllButton, claimAllFill, ready > 0)
	end
	hudBang.Visible = ready > 0
	firstPass = false
end

-- ===================== CLAIMING =====================
local claiming = false

local function flyStardust(source, granted)
	if not StardustCollectAnimator then return end
	for _, item in ipairs(granted or {}) do
		if item.Type == "Stardust" and (item.Amount or 0) > 0 then
			pcall(StardustCollectAnimator.Play, playerGui, source, item.Amount)
			break
		end
	end
end

local function handleResult(ok, result, source)
	if ok and type(result) == "table" and result.ok then
		sfx("REWARD_CLAIM_ID")
		local granted = result.granted or {}
		showToast("You got  " .. describeGranted(granted), COL.Green, granted)
		flyStardust(source, granted)
		if result.failed and #result.failed > 0 then
			task.delay(3.1, function()
				showToast(tostring(result.failed[1].reason), COL.XBorder)
			end)
		end
		updateAll()
		return true
	end
	local reason = if not ok then "Couldn't reach the server. Try again." elseif type(result) == "table" then tostring(result.reason or "Not ready yet.") else "Not ready yet."
	if reason == "busy" or reason == "Slow down." then return false end
	if reason == "locked" then reason = "Keep playing to unlock this one." end
	if reason == "claimed" then reason = "Already claimed today." end
	showToast(reason, COL.XBorder)
	return false
end

-- Three sparkles over the artwork, fading out and then gone. Short-lived
-- objects of its own, because card.pop is the squash and the rim belongs to
-- setState -- borrowing either would fight the state change a frame later.
local function claimFlourish(card)
	local row = card.iconsRow
	if not row or not card.frame then return end

	-- On the CARD, not in the icon row. The row has a UIListLayout, which lays
	-- out every GuiObject child it has -- so a sparkle parented there is not
	-- decoration over the icons, it is another item in the row and the icons
	-- shift to make space for it. They shifted right because no SortOrder is
	-- set, so LayoutOrder decides, and a sparkle's is 0 against the icons' 1..n.
	--
	-- The row's own Position is the centre of the icon zone, so these offsets
	-- are measured from there and land in the same place on every card.
	local centre = row.Position
	for index, spot in ipairs({
		{ -86, -40, 26, Color3.fromRGB(255, 236, 150) },
		{ 78, -8, 20, Color3.new(1, 1, 1) },
		{ 10, 46, 16, Color3.fromRGB(180, 245, 255) },
		}) do
		local spark = makeSparkle(card.frame, {
			Name = "ClaimSpark" .. index,
			Position = centre + UDim2.fromOffset(spot[1], spot[2]),
			Size = spot[3], Color = spot[4], Transparency = 0.05,
			ZIndex = 40, Rotation = index * 26,
		})
		local scale = Instance.new("UIScale")
		scale.Scale = 0.5
		scale.Parent = spark

		TweenService:Create(scale,
			TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.25 }):Play()
		for _, piece in ipairs(spark:GetDescendants()) do
			if piece:IsA("Frame") then
				TweenService:Create(piece,
					TweenInfo.new(0.46, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ BackgroundTransparency = 1 }):Play()
			end
		end
		task.delay(0.55, function() spark:Destroy() end)
	end
end

for _, card in pairs(cards) do
	card.claimButton.Activated:Connect(function()
		if claiming or card.busy or card.state ~= "ready" then return end
		card.busy = true
		sfx("UI_CLICK_ID")
		local ok, result = pcall(function() return claimRemote:InvokeServer(card.index) end)
		card.busy = false
		if handleResult(ok, result, card.frame) then
			-- Squash out of the press, then the sparkles. Both settle inside
			-- half a second, which is where this stops feeling like a reward
			-- and starts feeling like a cutscene.
			card.pop.Scale = 1.06
			TweenService:Create(card.pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			claimFlourish(card)
		end
	end)
end

claimAllButton.Activated:Connect(function()
	if claiming or not claimAllButton.Active then return end
	claiming = true
	sfx("UI_CLICK_ID")
	if claimAllRemote then
		local ok, result = pcall(function() return claimAllRemote:InvokeServer() end)
		handleResult(ok, result, claimAllButton)
	end
	claiming = false
end)

-- ===================== OPEN / CLOSE =====================
local function openPopup()
	-- Free once the group is warm: EnsureGroup joins the request already in
	-- flight rather than starting another, and returns immediately if it has
	-- already finished. The startup warm normally has this done long before
	-- anyone reaches a five-minute reward.
	if UIAssets.EnsureGroup then
		UIAssets.EnsureGroup("PlaytimeAwards")
	end

	safeLayout()
	updateAll()
	GuiManager:Open("PlaytimeAwards")
	-- Show the first card that needs attention.
	task.defer(function()
		for index = 1, COUNT do
			local card = cards[index]
			if card.frame.Parent == scroll and (card.state == "ready" or card.state == "next") then
				local offset = card.frame.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y * popupScale.Scale
				if offset > scroll.AbsoluteSize.Y - 60 then
					scroll.CanvasPosition = Vector2.new(0, math.max(offset / math.max(popupScale.Scale, 0.01) - 20, 0))
				end
				break
			end
		end
	end)
end

local function closePopup()
	GuiManager:Close("PlaytimeAwards")
end

closeButton.Activated:Connect(closePopup)
GuiManager:SetBackHandler("PlaytimeAwards", closePopup)

if openButton then
	openButton.Activated:Connect(function()
		if GuiManager:GetCurrent() == "PlaytimeAwards" then
			closePopup()
		else
			openPopup()
		end
	end)
else
	warn("[PlaytimeAwardsClient] Could not find the Playtime Awards HUD button.")
end

task.spawn(function()
	while gui.Parent do
		updateAll()
		task.wait(0.5)
	end
end)

-- ===================== STUDIO TESTING =====================
-- "=" adds 10 minutes of playtime, "-" starts a fresh day (Studio only).
if RunService:IsStudio() then
	task.spawn(function()
		local debugRemote = remotes:WaitForChild("DebugPlaytime", 10)
		if not debugRemote then return end
		print("[PlaytimeAwards] Studio: = adds 10 minutes of playtime, - starts a fresh day.")
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then return end
			if input.KeyCode == Enum.KeyCode.Equals then
				debugRemote:FireServer("add")
			elseif input.KeyCode == Enum.KeyCode.Minus then
				debugRemote:FireServer("reset")
			end
		end)
	end)
end
