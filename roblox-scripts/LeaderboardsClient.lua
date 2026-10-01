-- LeaderboardsClient (LocalScript in StarterPlayerScripts)
-- Elites leaderboard GUI.
-- Fixed crown:
-- - Crown is now custom-made from Frames, not emoji text.
-- - Crown is static/unmoving.
-- - Keeps sparkles, YOU highlight, animated tab switch, top 3 podium, and #4-#30 scroll list.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GuiManager = require(ReplicatedStorage:WaitForChild("GuiManager"))
local GuiStyle = require(ReplicatedStorage:WaitForChild("GuiStyle"))

local UiResponsive do
	local module = ReplicatedStorage:FindFirstChild("UiResponsive")
	local ok, result = pcall(function() return module and require(module) end)
	UiResponsive = if ok and type(result) == "table" then result else nil
end

local UIAssets do
	local module = ReplicatedStorage:WaitForChild("UIAssets", 10)
	if module then
		UIAssets = require(module)
	else
		warn("[Leaderboards] ReplicatedStorage > UIAssets is missing: category icons will be blank.")
		UIAssets = {}
	end
end

local remotes = ReplicatedStorage:WaitForChild("LeaderboardsRemotes")
local getLeaderboard = remotes:WaitForChild("GetLeaderboard")

local FONT = GuiStyle.FONT
local COL = GuiStyle.COL

-- ===== PALETTE =====
-- Copied verbatim from StoreClient's own palette so the two windows are
-- demonstrably the same game rather than two guesses at the same blue. If the
-- Secret Store's colours ever change, change them here as well.
local C = {
	Shadow = Color3.fromRGB(3, 6, 26),            -- navy-black, never pure black
	ShellNavy = Color3.fromRGB(10, 18, 58),       -- outer dark edge
	BorderBlue = Color3.fromRGB(46, 134, 255),    -- bright blue frame
	EdgeCyan = Color3.fromRGB(111, 232, 255),     -- inner highlight

	-- The Store's own interior values, darkened a step. Its window gets much
	-- of its richness from a painted backdrop image that this one does not
	-- have, so the drawn base has to carry it instead.
	BodyTop = Color3.fromRGB(28, 48, 146),
	BodyMid = Color3.fromRGB(15, 26, 94),
	BodyBottom = Color3.fromRGB(24, 38, 124),

	Deep = Color3.fromRGB(9, 15, 52),             -- card interiors
	Deeper = Color3.fromRGB(6, 10, 38),           -- podium floor
	ShadowSoft = Color3.fromRGB(14, 10, 46),      -- navy-purple, never black

	HeaderTop = Color3.fromRGB(48, 88, 228),
	HeaderBottom = Color3.fromRGB(14, 26, 104),

	CardEdge = Color3.fromRGB(10, 22, 70),        -- deep navy outline
	CardRim = Color3.fromRGB(86, 222, 255),       -- bright cyan edge
	CardInnerEdge = Color3.fromRGB(120, 220, 255),

	Cream = Color3.fromRGB(255, 252, 240),
	Ink = Color3.fromRGB(14, 22, 58),             -- outline navy, never black

	Gold = Color3.fromRGB(255, 214, 66),
	Silver = Color3.fromRGB(226, 236, 250),
	Bronze = Color3.fromRGB(255, 152, 74),
}

local old = playerGui:FindFirstChild("LeaderboardsUI")
if old then
	old:Destroy()
end

-- ===== SETTINGS =====

local CAMERA = workspace.CurrentCamera
local DESIGN = Vector2.new(1280, 720)

local POPUP_W = 1160
local POPUP_H = 734

local PLACEHOLDER_ROWS = 4      -- quiet rows kept under the podium when the board is short
local FIRST_SCROLL_RANK = 4
local LAST_SCROLL_RANK = 30
local ROWS_TO_BUILD = LAST_SCROLL_RANK - FIRST_SCROLL_RANK + 1

local HOVER_IN = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HOVER_OUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TAB_BOUNCE = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TAB_RETURN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ===== THEME =====
-- One entry per category: the rim light, the header gradient, the glow behind
-- the podium, and the icon. Top Stardust deliberately uses the game's own
-- Stardust coin rather than a gem.
local THEME = {
	Stardust = {
		Rim = C.CardRim,
		HeaderPeak = Color3.fromRGB(190, 246, 255),
		HeaderTop = Color3.fromRGB(96, 214, 255),
		HeaderMid = Color3.fromRGB(34, 140, 255),
		HeaderBottom = Color3.fromRGB(18, 62, 186),
		HeaderEdge = Color3.fromRGB(8, 34, 96),
		Aura = Color3.fromRGB(64, 156, 255),
		Bubble = Color3.fromRGB(46, 118, 214),
		Icon = "Stardust",
		Halo = "HaloBlue",
		Spark = Color3.fromRGB(150, 235, 255),
	},
	Attacks = {
		Rim = Color3.fromRGB(255, 130, 240),
		HeaderPeak = Color3.fromRGB(255, 196, 252),
		HeaderTop = Color3.fromRGB(252, 108, 232),
		HeaderMid = Color3.fromRGB(232, 36, 198),
		HeaderBottom = Color3.fromRGB(150, 16, 132),
		HeaderEdge = Color3.fromRGB(72, 8, 70),
		Aura = Color3.fromRGB(186, 72, 255),
		Bubble = Color3.fromRGB(146, 58, 196),
		Icon = "Swords",
		Halo = "HaloPink",
		Spark = Color3.fromRGB(236, 152, 255),
	},
	Time = {
		Rim = Color3.fromRGB(255, 190, 86),
		HeaderPeak = Color3.fromRGB(255, 240, 186),
		HeaderTop = Color3.fromRGB(255, 190, 76),
		HeaderMid = Color3.fromRGB(250, 138, 26),
		HeaderBottom = Color3.fromRGB(186, 76, 10),
		HeaderEdge = Color3.fromRGB(86, 32, 6),
		Aura = Color3.fromRGB(255, 150, 52),
		Bubble = Color3.fromRGB(202, 110, 38),
		Icon = "Stopwatch",
		Halo = "HaloGold",
		Spark = Color3.fromRGB(255, 222, 140),
	},
}

-- ===== HELPERS =====

local function corner(parent, r)
	return GuiStyle.Corner(parent, r)
end

-- Default outline is the Store's deep navy, not GuiStyle's darker default and
-- never black. Every stroke in this file that does not name a colour gets it.
local function stroke(parent, color, thickness)
	return GuiStyle.Stroke(parent, color or C.CardEdge, thickness or 2)
end

local function gradient(parent, topColor, bottomColor)
	return GuiStyle.Gradient(parent, topColor, bottomColor)
end

-- A tight aura: one soft rounded shape that fades at top and bottom. Never a
-- second copy of the artwork, which reads as a ghost rather than light.
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

	local color = props.Color or Color3.fromRGB(120, 210, 255)
	local base = props.Transparency or 0.88
	local radius = props.Radius or 1

	-- Widest and faintest first, tightest and strongest last. Each ring fades
	-- out top and bottom, and because they are concentric the horizontal edges
	-- dissolve too. One ring on its own always shows its own outline.
	for index, ring in ipairs({
		{ Scale = 1, Mix = 0.78 },
		{ Scale = 0.84, Mix = 0.56 },
		{ Scale = 0.67, Mix = 0.36 },
		{ Scale = 0.5, Mix = 0.18 },
		{ Scale = 0.33, Mix = 0 },
		}) do
		local layer = Instance.new("Frame")
		layer.Name = "Ring" .. index
		layer.AnchorPoint = Vector2.new(0.5, 0.5)
		layer.Position = UDim2.fromScale(0.5, 0.5)
		layer.Size = UDim2.fromScale(ring.Scale, ring.Scale)
		layer.BackgroundColor3 = color
		layer.BackgroundTransparency = base + (1 - base) * ring.Mix
		layer.BorderSizePixel = 0
		layer.ZIndex = halo.ZIndex
		layer.Parent = halo
		GuiStyle.Corner(layer, radius)

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

-- A thin scattering of stars. Small, few, and never over text. A fourth value
-- in a spot sets its colour, so a header can carry gold and purple points
-- alongside the white ones without a second function.
local function starField(parent, spots, zIndex)
	for index, spot in ipairs(spots) do
		local dot = Instance.new("Frame")
		dot.Name = "Star" .. index
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(spot[1], spot[2])
		dot.Size = UDim2.fromOffset(spot[3], spot[3])
		dot.BackgroundColor3 = spot[4]
			or (if index % 3 == 0 then Color3.fromRGB(150, 235, 255) else Color3.new(1, 1, 1))
		dot.BackgroundTransparency = spot[5] or 0.3
		dot.BorderSizePixel = 0
		dot.ZIndex = zIndex or 11
		dot.Parent = parent
		GuiStyle.Corner(dot, 1)
	end
end

-- Every picture here is a finished asset, so its drawn stand-in is switched
-- off straight away. Waiting for the picture to report "loaded" left the old
-- drawn version showing behind it (sometimes for good, when the signal came
-- late). The picture itself is preloaded with the rest of the UI.
local function whenImageLoaded(_image, onLoaded)
	onLoaded()
end

-- A soft drop shadow. Two stacked shapes with tapered edges rather than one
-- flat slab: a shadow you can see the outline of is a shape, not a shadow.
-- Navy-purple, low opacity, and sitting close to whatever casts it.
local function dropShadow(parent, props)
	local shade = Instance.new("Frame")
	shade.Name = props.Name or "Shadow"
	shade.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
	shade.Position = props.Position or UDim2.new(0.5, props.OffsetX or 0, 0.5, props.OffsetY or 3)
	shade.Size = props.Size or UDim2.new(1, props.Grow or 0, 1, props.Grow or 0)
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.ZIndex = props.ZIndex or 1
	shade.Parent = parent

	local color = props.Color or C.ShadowSoft
	local base = props.Transparency or 0.72
	local radius = props.Radius or 0.5

	for _, layer in ipairs({
		{ Scale = 1.06, Alpha = base + (1 - base) * 0.55 },
		{ Scale = 0.9, Alpha = base },
		}) do
		local slab = Instance.new("Frame")
		slab.Name = "Layer"
		slab.AnchorPoint = Vector2.new(0.5, 0.5)
		slab.Position = UDim2.fromScale(0.5, 0.5)
		slab.Size = UDim2.fromScale(layer.Scale, layer.Scale)
		slab.BackgroundColor3 = color
		slab.BackgroundTransparency = layer.Alpha
		slab.BorderSizePixel = 0
		slab.ZIndex = shade.ZIndex
		slab.Parent = shade
		GuiStyle.Corner(slab, radius)

		local taper = Instance.new("UIGradient")
		taper.Rotation = 90
		taper.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.45, 0),
			NumberSequenceKeypoint.new(1, 0.7),
		})
		taper.Parent = slab
	end

	return shade
end

-- A four-point sparkle drawn from two crossed lenses and a bright centre.
-- Static, cheap, and it cannot fall back to a missing-glyph box the way a
-- typographic star can.
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

	local color = props.Color or Color3.new(1, 1, 1)
	local alpha = props.Transparency or 0.15

	-- A soft round bloom underneath, so the star sits in light rather than
	-- being a hard shape on its own.
	local bloom = Instance.new("Frame")
	bloom.Name = "Bloom"
	bloom.AnchorPoint = Vector2.new(0.5, 0.5)
	bloom.Position = UDim2.fromScale(0.5, 0.5)
	bloom.Size = UDim2.fromScale(0.82, 0.82)
	bloom.BackgroundColor3 = color
	bloom.BackgroundTransparency = math.min(alpha + (1 - alpha) * 0.68, 0.97)
	bloom.BorderSizePixel = 0
	bloom.ZIndex = spark.ZIndex
	bloom.Parent = spark
	GuiStyle.Corner(bloom, 1)

	do
		local bloomFade = Instance.new("UIGradient")
		bloomFade.Rotation = 90
		bloomFade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		bloomFade.Parent = bloom
	end

	-- Each arm fades from its middle out to its tips, which turns two crossed
	-- bars into a four-point star. Rounded ends alone just make a plus sign.
	for _, arm in ipairs({
		{ Name = "Vertical", Size = UDim2.new(0.17, 0, 1, 0), Rotation = 90 },
		{ Name = "Horizontal", Size = UDim2.new(1, 0, 0.17, 0), Rotation = 0 },
		}) do
		local bar = Instance.new("Frame")
		bar.Name = arm.Name
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = arm.Size
		bar.BackgroundColor3 = color
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
	core.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.7)
	core.BackgroundTransparency = math.max(alpha - 0.1, 0)
	core.BorderSizePixel = 0
	core.ZIndex = spark.ZIndex + 2
	core.Parent = spark
	GuiStyle.Corner(core, 1)

	return spark
end

-- An aura that sits OUTSIDE the object it belongs to. A UIStroke is drawn
-- beyond its own border and is not clipped by the parent, so a shell frame the
-- size of the card, carrying a thick faint stroke, gives the reference's
-- "card is lit" look without needing room inside the layout for it.
local function outerAura(parent, color, rings)
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

		local edge = GuiStyle.Stroke(shell, color, ring.Thickness)
		edge.Transparency = ring.Transparency
	end
end

local function makeText(parent, props)
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "TextLabel"
	label.BackgroundTransparency = props.BackgroundTransparency or 1
	label.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(255, 255, 255)
	label.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	label.Position = props.Position or UDim2.fromScale(0, 0)
	label.Size = props.Size or UDim2.fromOffset(100, 40)
	label.Text = props.Text or ""
	label.Font = props.Font or FONT
	label.TextColor3 = props.TextColor3 or COL.Light
	label.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center
	label.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	label.TextWrapped = props.TextWrapped or false
	label.TextScaled = true
	label.TextTruncate = props.TextTruncate or Enum.TextTruncate.None
	label.ZIndex = props.ZIndex or 1
	label.Parent = parent

	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = props.MinTextSize or 10
	limit.MaxTextSize = props.MaxTextSize or 40
	limit.Parent = label

	if props.Stroke ~= false then
		GuiStyle.TextStroke(label, props.StrokeThickness or 2)
		-- Same navy behind every piece of lettering in the window, so the
		-- typography reads as one system rather than several. Found by class
		-- rather than trusting a return value from a module this file does
		-- not own.
		local edge = label:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Color = props.StrokeColor or C.Ink
		end
	end

	if props.Gloss then
		GuiStyle.GlossText(label)
	end

	return label
end

local SUFFIX = {"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"}

local function abbreviate(n)
	n = tonumber(n) or 0
	n = math.max(n, 0)

	if n < 1000 then
		return tostring(math.floor(n))
	end

	local index = math.clamp(math.floor(math.log(n) / math.log(1000)), 1, #SUFFIX - 1)
	local scaled = n / (1000 ^ index)

	return (string.format("%.2f", scaled):gsub("%.?0+$", "")) .. SUFFIX[index + 1]
end

local function formatStardust(n)
	return abbreviate(n)
end

local function formatAttacks(n)
	return abbreviate(n)
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))

	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60

	return string.format("%02d:%02d:%02d", h, m, s)
end

local function formatterFor(columnKey)
	if columnKey == "Stardust" then
		return formatStardust
	elseif columnKey == "Attacks" then
		return formatAttacks
	else
		return formatTime
	end
end

-- ===== PROFILE IMAGE CACHE =====

local avatarCache = {}

local function initials(name)
	name = tostring(name or "?")
	name = string.gsub(name, "%s+", "")

	if name == "" then
		return "?"
	end

	return string.upper(string.sub(name, 1, 1))
end

local function setProfileImage(imageLabel, letterLabel, userId, fallbackName)
	userId = tonumber(userId)

	imageLabel.Image = ""
	letterLabel.Text = initials(fallbackName)
	letterLabel.Visible = true

	if not userId then
		return
	end

	if avatarCache[userId] then
		imageLabel.Image = avatarCache[userId]
		letterLabel.Visible = false
		return
	end

	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)

		if ok and image then
			avatarCache[userId] = image

			if imageLabel and imageLabel.Parent then
				imageLabel.Image = image
				letterLabel.Visible = false
			end
		end
	end)
end

-- ===== GUI ROOT =====

local gui = Instance.new("ScreenGui")
gui.Name = "LeaderboardsUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
if UiResponsive and UiResponsive.UseModalInsets then UiResponsive.UseModalInsets(gui) end   -- below the top bar
gui.DisplayOrder = 40
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = gui

local rootScale = Instance.new("UIScale")
rootScale.Parent = root

local function refreshScale()
	local vp = CAMERA.ViewportSize
	if vp.X < 1 or vp.Y < 1 then return end

	local scale = math.min(vp.X / DESIGN.X, vp.Y / DESIGN.Y)
	scale = math.clamp(scale, 0.46, 1)

	rootScale.Scale = scale
end

refreshScale()
if not UiResponsive then
	CAMERA:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
end

-- ===== POPUP =====

local popup = Instance.new("Frame")
popup.Name = "LeaderboardsPopup"
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.Position = UDim2.fromScale(0.5, 0.5)
popup.Size = UDim2.fromOffset(POPUP_W, POPUP_H)
-- Dark navy structure. The lit interior is a separate inset frame, so a band
-- of this shows between the bright frame and the bright interior - which is
-- how the Store's window is built and why its cards stand off the background.
popup.BackgroundColor3 = C.ShellNavy
popup.BackgroundTransparency = 0.06
popup.Visible = false
popup.ClipsDescendants = true
popup.ZIndex = 10
popup.Parent = root
corner(popup, 0.05)
-- Same construction as the Store: dark navy silhouette, bright blue frame,
-- cyan highlight just inside it. The Store uses a 9px frame on a 1190-tall
-- window; 7px on a 690-tall one is the same weight for the size.
stroke(popup, C.BorderBlue, 7)

-- Behind the window: a soft shadow, a tight electric-blue aura, and the
-- luminous platform the whole thing appears to float on. All three are
-- siblings so the window's own ClipsDescendants cannot cut them off, and all
-- three follow the window's size and visibility.
local frameDecor = {}

do
	-- The floor halo is gone: it read as low-resolution and pulled attention
	-- off the window. What is left behind the window is a soft shadow and a
	-- tight electric-blue aura, both of which hug the frame.
	local shadow = Instance.new("Frame")
	shadow.Name = "PopupShadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.BackgroundColor3 = C.ShadowSoft
	shadow.BackgroundTransparency = 0.6
	shadow.BorderSizePixel = 0
	shadow.Visible = false
	shadow.ZIndex = 8
	shadow.Parent = root
	corner(shadow, 0.055)

	do
		local shadowFade = Instance.new("UIGradient")
		shadowFade.Rotation = 90
		shadowFade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.4),
		})
		shadowFade.Parent = shadow
	end

	local glow = Instance.new("Frame")
	glow.Name = "PopupGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.Visible = false
	glow.ZIndex = 9
	glow.Parent = root
	outerAura(glow, C.BorderBlue, {
		{ Thickness = 4, Transparency = 0.55, ZIndex = 9, Radius = 0.05 },
		{ Thickness = 11, Transparency = 0.82, ZIndex = 9, Radius = 0.05 },
		{ Thickness = 22, Transparency = 0.93, ZIndex = 9, Radius = 0.05 },
	})

	function frameDecor.sync()
		local w = popup.Size.X.Offset
		local h = popup.Size.Y.Offset
		glow.Size = UDim2.fromOffset(w - 2, h - 2)
		shadow.Position = UDim2.new(0.5, 0, 0.5, 14)
		shadow.Size = UDim2.fromOffset(w - 20, h - 8)
	end

	function frameDecor.setVisible(on)
		shadow.Visible = on
		glow.Visible = on
	end

	frameDecor.sync()
	popup:GetPropertyChangedSignal("Visible"):Connect(function()
		frameDecor.setVisible(popup.Visible)
	end)
end

local interior = Instance.new("Frame")
interior.Name = "Interior"
interior.Position = UDim2.fromOffset(13, 13)
interior.Size = UDim2.new(1, -26, 1, -26)
interior.BackgroundColor3 = Color3.new(1, 1, 1)   -- gradient carries the colour
interior.BackgroundTransparency = 0
interior.BorderSizePixel = 0
interior.ClipsDescendants = true
interior.ZIndex = 11
interior.Parent = popup
-- Concentric with the frame: 0.032 of 664 is 21px, which is the window's own
-- 34px corner less the 13px inset.
corner(interior, 0.032)

do
	-- Deep navy at the top, indigo through the middle, blue-violet at the
	-- bottom, with a cyan highlight just inside the frame.
	local sky = Instance.new("UIGradient")
	sky.Rotation = 90
	sky.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.BodyTop),
		ColorSequenceKeypoint.new(0.55, C.BodyMid),
		ColorSequenceKeypoint.new(1, C.BodyBottom),
	})
	sky.Parent = interior

	-- The Store's cosmic wash: five wide, very faint colour fields that give
	-- the interior depth without any of it reading as fog.
	local function field(x, y, size, tint, alpha)
		local blob = Instance.new("Frame")
		blob.Name = "ColourField"
		blob.AnchorPoint = Vector2.new(0.5, 0.5)
		blob.Position = UDim2.fromScale(x, y)
		blob.Size = UDim2.fromScale(size, size * 0.72)
		blob.BackgroundColor3 = tint
		blob.BackgroundTransparency = alpha
		blob.BorderSizePixel = 0
		blob.ZIndex = 11
		blob.Parent = interior
		corner(blob, 1)

		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = blob
	end
	field(0.2, 0.16, 0.7, Color3.fromRGB(96, 158, 255), 0.82)      -- upper left cobalt
	field(0.78, 0.2, 0.55, Color3.fromRGB(120, 130, 255), 0.88)    -- upper right lilac
	field(0.5, 0.62, 1.05, Color3.fromRGB(14, 24, 92), 0.8)        -- depth, not a hole
	field(0.12, 0.9, 0.62, Color3.fromRGB(150, 128, 255), 0.84)    -- lower left violet
	field(0.9, 0.86, 0.64, Color3.fromRGB(96, 206, 255), 0.84)     -- lower right cyan

	local inner = Instance.new("Frame")
	inner.Name = "InnerEdge"
	inner.Position = UDim2.fromOffset(8, 8)
	inner.Size = UDim2.new(1, -16, 1, -16)
	inner.BackgroundTransparency = 1
	inner.ZIndex = 60
	inner.Parent = popup
	corner(inner, 0.045)
	local edge = stroke(inner, C.EdgeCyan, 3)
	edge.Transparency = 0.1

	-- A brighter kiss of light along the very top and bottom edges, which is
	-- what makes the reference frame read as glass rather than as a border.
	-- Short segments of reflected light, not one continuous white line: two
	-- short ones near the upper corners, a long soft one along the bottom.
	for _, side in ipairs({
		{ Name = "TopShineLeft", X = 0.22, Y = 0, Width = 0.26, Alpha = 0.34, Height = 3 },
		{ Name = "TopShineRight", X = 0.78, Y = 0, Width = 0.26, Alpha = 0.34, Height = 3 },
		{ Name = "BottomShine", X = 0.5, Y = 1, Width = 0.66, Alpha = 0.6, Height = 4 },
		}) do
		local shine = Instance.new("Frame")
		shine.Name = side.Name
		shine.AnchorPoint = Vector2.new(0.5, side.Y)
		shine.Position = UDim2.new(side.X, 0, side.Y, 0)
		shine.Size = UDim2.new(side.Width, 0, 0, side.Height)
		shine.BackgroundColor3 = Color3.fromRGB(198, 244, 255)
		shine.BackgroundTransparency = side.Alpha
		shine.BorderSizePixel = 0
		shine.ZIndex = 61
		shine.Parent = inner
		corner(shine, 1)

		local taper = Instance.new("UIGradient")
		taper.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		taper.Parent = shine
	end

	-- STEP 48: cyan light reflecting up off the floor halo onto the lower
	-- interior. Wide, weak, and cut off well before it reaches the cards.
	local floorBounce = Instance.new("Frame")
	floorBounce.Name = "FloorBounce"
	floorBounce.AnchorPoint = Vector2.new(0.5, 1)
	floorBounce.Position = UDim2.new(0.5, 0, 1, 0)
	floorBounce.Size = UDim2.new(0.8, 0, 0, 74)
	floorBounce.BackgroundColor3 = C.EdgeCyan
	floorBounce.BackgroundTransparency = 0.88
	floorBounce.BorderSizePixel = 0
	floorBounce.ZIndex = 59
	floorBounce.Parent = interior
	corner(floorBounce, 1)

	local bounceFade = Instance.new("UIGradient")
	bounceFade.Rotation = 90
	bounceFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	bounceFade.Parent = floorBounce

	-- Atmosphere: white, cyan and a couple of warm points, kept to the edges
	-- and the gaps between cards so nothing ever lands on a name or a number.
	starField(interior, {
		{ 0.021, 0.30, 4 }, { 0.013, 0.62, 3 }, { 0.030, 0.86, 3 },
		{ 0.978, 0.28, 4 }, { 0.988, 0.58, 3 }, { 0.970, 0.84, 3 },
		{ 0.5, 0.975, 4 }, { 0.30, 0.982, 3 }, { 0.70, 0.982, 3 },
		{ 0.335, 0.30, 3, Color3.fromRGB(255, 226, 140), 0.45 },
		{ 0.665, 0.52, 3, Color3.fromRGB(198, 150, 255), 0.45 },
		{ 0.335, 0.74, 2, Color3.fromRGB(150, 235, 255), 0.4 },
	}, 11)

	makeSparkle(interior, { Name = "EdgeSparkleA", Position = UDim2.fromScale(0.026, 0.19), Size = 15,
		Color = C.EdgeCyan, Transparency = 0.38, ZIndex = 11, Rotation = 12 })
	makeSparkle(interior, { Name = "EdgeSparkleB", Position = UDim2.fromScale(0.974, 0.72), Size = 13,
		Color = Color3.fromRGB(255, 232, 160), Transparency = 0.4, ZIndex = 11, Rotation = -8 })
	makeSparkle(interior, { Name = "EdgeSparkleC", Position = UDim2.fromScale(0.974, 0.22), Size = 11,
		Color = Color3.fromRGB(198, 150, 255), Transparency = 0.45, ZIndex = 11, Rotation = 20 })
	makeSparkle(interior, { Name = "GapSparkleA", Position = UDim2.fromScale(0.344, 0.88), Size = 12,
		Color = C.EdgeCyan, Transparency = 0.45, ZIndex = 11, Rotation = -16 })
	makeSparkle(interior, { Name = "GapSparkleB", Position = UDim2.fromScale(0.656, 0.22), Size = 10,
		Color = Color3.fromRGB(255, 232, 160), Transparency = 0.5, ZIndex = 11, Rotation = 8 })
	makeSparkle(interior, { Name = "EdgeSparkleD", Position = UDim2.fromScale(0.026, 0.86), Size = 10,
		Color = Color3.new(1, 1, 1), Transparency = 0.5, ZIndex = 11, Rotation = -6 })
end

GuiManager:Register("Leaderboards", popup, {
	BlurSize = 18,
	OpenScale = 0.82,
	OpenOvershootScale = 1.04,
	CloseBounceScale = 1.02,
	CloseScale = 0.82,
})

-- ===== HEADER =====

local header = Instance.new("Frame")
header.Name = "Header"
header.Position = UDim2.fromOffset(0, 0)
header.Size = UDim2.new(1, 0, 0, 112)
header.BackgroundColor3 = Color3.new(1, 1, 1)   -- gradient carries the colour
header.BackgroundTransparency = 0.04
header.ZIndex = 12
header.Parent = interior
corner(header, 0.05)
stroke(header, C.CardEdge, 2.5)
gradient(header, C.HeaderTop, C.HeaderBottom)

do
	-- A thin bright line along the top of the header, as the Store's banner has.
	local headerShine = Instance.new("Frame")
	headerShine.Name = "HeaderShine"
	headerShine.AnchorPoint = Vector2.new(0.5, 0)
	headerShine.Position = UDim2.new(0.5, 0, 0, 5)
	headerShine.Size = UDim2.new(0.94, 0, 0, 16)
	headerShine.BackgroundColor3 = Color3.new(1, 1, 1)
	headerShine.BackgroundTransparency = 0.82
	headerShine.BorderSizePixel = 0
	headerShine.ZIndex = 13
	headerShine.Parent = header
	corner(headerShine, 1)

	local shineFade = Instance.new("UIGradient")
	shineFade.Rotation = 90
	shineFade.Transparency = NumberSequence.new(0, 1)
	shineFade.Parent = headerShine
end

do
	-- The globe sits behind the title as an accent, never over the letters.
	local globe = Instance.new("ImageLabel")
	globe.Name = "GlobeAccent"
	globe.BackgroundTransparency = 1
	globe.BorderSizePixel = 0
	globe.Active = false
	globe.AnchorPoint = Vector2.new(0.5, 0.5)
	globe.Position = UDim2.new(0, 64, 0.5, -12)
	globe.Size = UDim2.fromOffset(78, 78)
	globe.Image = UIAssets.Globe or ""
	globe.ImageTransparency = 0
	globe.ScaleType = Enum.ScaleType.Fit
	globe.ZIndex = 12
	globe.Parent = header

	-- Smaller than the word and tucked under its first letter, with its own
	-- halo, so it reads as part of the logo rather than an icon parked beside
	-- it. The title is ZIndex 14, so the globe can never cover a letter.
	dropShadow(header, {
		Name = "GlobeShadow", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 67, 0.5, -7), Size = UDim2.fromOffset(78, 78),
		Transparency = 0.55, ZIndex = 11, Radius = 1,
	})

	softGlow(header, {
		Name = "GlobeAura", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 64, 0.5, -12), Size = UDim2.fromOffset(100, 100),
		Color = C.EdgeCyan, Transparency = 0.78, ZIndex = 11, Radius = 1,
	})

	softGlow(header, {
		Name = "TitleGlow", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 70, 0.5, 0), Size = UDim2.fromOffset(300, 98),
		Color = Color3.fromRGB(110, 200, 255), Transparency = 0.86, ZIndex = 12, Radius = 0.5,
	})

	-- One deliberate arrangement around the branding: a large gold sparkle over
	-- the globe's shoulder, a cyan one past the end of the word, a small purple
	-- one between them, and a few white points. Nothing is scattered at random
	-- and nothing sits on a letter - "Elites" ends near x=300 in its 268-wide
	-- box and the tab row starts at x=348.
	starField(header, {
		{ 0.026, 0.26, 4 },
		{ 0.098, 0.78, 3 },
		{ 0.246, 0.14, 3 },
		{ 0.285, 0.86, 3, C.EdgeCyan, 0.3 },
	}, 13)

	makeSparkle(header, { Name = "TitleSparkleGold", Position = UDim2.new(0, 36, 0.5, -34),
		Size = 20, Color = Color3.fromRGB(255, 220, 112), Transparency = 0.12, ZIndex = 15, Rotation = 10 })
	makeSparkle(header, { Name = "TitleSparklePurple", Position = UDim2.new(0, 314, 0.5, -34),
		Size = 12, Color = Color3.fromRGB(198, 150, 255), Transparency = 0.25, ZIndex = 15, Rotation = 18 })
	makeSparkle(header, { Name = "TitleSparkleCyan", Position = UDim2.new(0, 330, 0.5, 26),
		Size = 16, Color = C.EdgeCyan, Transparency = 0.15, ZIndex = 15, Rotation = -14 })
end

do
	-- A navy copy sitting down and to the right, which is what gives the word
	-- its weight. The Store's lettering is built the same way.
	local titleShadow = makeText(header, {
		Name = "TitleShadow",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 89, 0.5, 6),
		Size = UDim2.fromOffset(268, 92),
		Text = "Elites",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Ink,
		ZIndex = 13,
		Stroke = false,
		MinTextSize = 46,
		MaxTextSize = 86,
	})
	titleShadow.TextTransparency = 0.25
end

do
	-- A cyan rim just behind the face, which is what gives the reference's
	-- lettering its lit edge rather than a flat white fill.
	local titleRim = makeText(header, {
		Name = "TitleRim",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 84, 0.5, 0),
		Size = UDim2.fromOffset(268, 92),
		Text = "Elites",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.EdgeCyan,
		ZIndex = 13,
		StrokeColor = C.EdgeCyan,
		StrokeThickness = 7,
		MinTextSize = 46,
		MaxTextSize = 86,
	})
	titleRim.TextTransparency = 1
	local rimEdge = titleRim:FindFirstChildOfClass("UIStroke")
	if rimEdge then
		rimEdge.Transparency = 0.72
	end
end

makeText(header, {
	Name = "Title",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 84, 0.5, 0),
	Size = UDim2.fromOffset(268, 92),
	Text = "Elites",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(246, 253, 255),
	ZIndex = 14,
	StrokeThickness = 4.5,
	Gloss = true,
	MinTextSize = 46,
	MaxTextSize = 86,
})

do
	-- A bright line where the header meets the cards.
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.AnchorPoint = Vector2.new(0, 1)
	divider.Position = UDim2.new(0, 0, 1, 0)
	divider.Size = UDim2.new(1, 0, 0, 3)
	divider.BackgroundColor3 = C.EdgeCyan
	divider.BackgroundTransparency = 0.18
	divider.BorderSizePixel = 0
	divider.ZIndex = 15
	divider.Parent = header
end

do
	local closeButton = GuiStyle.MakePlaytimeX(header, function()
		GuiManager:Close("Leaderboards")
	end)

	-- The Secret Store's close button is artwork, not a drawn X. The same
	-- picture goes on this one so the two windows close the same way. Only
	-- this leaderboard is affected: GuiStyle itself is untouched, so Settings,
	-- Welcome Back and the HUD keep exactly what they have now. The drawn X
	-- stays underneath and is hidden only once the picture has really loaded.
	if closeButton and UIAssets.Close then
		local art = Instance.new("ImageLabel")
		art.Name = "CloseArt"
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, 0.5)
		art.Size = UDim2.fromScale(1.36, 1.36)
		art.BackgroundTransparency = 1
		art.BorderSizePixel = 0
		art.Active = false
		art.Image = UIAssets.Close
		art.ScaleType = Enum.ScaleType.Fit
		art.ZIndex = 70
		art.Parent = closeButton

		whenImageLoaded(art, function()
			closeButton.BackgroundTransparency = 1
			local edge = closeButton:FindFirstChildOfClass("UIStroke")
			if edge then
				edge.Transparency = 1
			end
			for _, child in ipairs(closeButton:GetChildren()) do
				if child ~= art and child:IsA("GuiObject") then
					child.Visible = false
				end
			end
		end)
	end
end

-- ===== TABS =====

local activeTab = "Daily"
local tabButtons = {}
local requestToken = 0
local columnObjects = {}

local tabsFrame = Instance.new("Frame")
tabsFrame.Name = "Tabs"
tabsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
tabsFrame.Position = UDim2.new(0.61, 0, 0.5, 0)
tabsFrame.Size = UDim2.fromOffset(720, 78)
tabsFrame.BackgroundTransparency = 1
tabsFrame.ZIndex = 14
tabsFrame.Parent = header

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tabLayout.Padding = UDim.new(0, 18)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabsFrame

local refreshLeaderboard

local tabIconArtReady = {}

local tabClickSound = Instance.new("Sound")
tabClickSound.Name = "LeaderboardTabClick"
tabClickSound.SoundId = "rbxassetid://129349771709668"   -- the HUD's click
tabClickSound.Volume = 0.45
tabClickSound.Parent = SoundService

local lastTabClick = 0

local function playTabClick()
	local now = os.clock()
	if now - lastTabClick < 0.06 then return end
	lastTabClick = now
	tabClickSound.TimePosition = 0
	tabClickSound:Play()
end

local CALENDAR_TONES = {
	active = {
		Body = Color3.fromRGB(32, 78, 158),
		Band = Color3.fromRGB(86, 176, 246),
		Dot = Color3.fromRGB(255, 255, 255),
	},
	inactive = {
		Body = Color3.fromRGB(74, 112, 178),
		Band = Color3.fromRGB(110, 156, 220),
		Dot = Color3.fromRGB(214, 232, 255),
	},
}

local function makeCalendarIcon(parent)
	local icon = Instance.new("Frame")
	icon.Name = "TabIcon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 14, 0.5, 0)
	icon.Size = UDim2.fromOffset(30, 30)
	icon.BackgroundTransparency = 1
	icon.ZIndex = 17
	icon.Parent = parent

	local rings = {}
	for index, x in ipairs({ 7, 19 }) do
		local ring = Instance.new("Frame")
		ring.Name = "Ring" .. index
		ring.AnchorPoint = Vector2.new(0.5, 0)
		ring.Position = UDim2.fromOffset(x, 0)
		ring.Size = UDim2.fromOffset(4, 9)
		ring.BorderSizePixel = 0
		ring.ZIndex = 17
		ring.Parent = icon
		GuiStyle.Corner(ring, 1)
		table.insert(rings, ring)
	end

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, 6)
	body.Size = UDim2.fromOffset(30, 24)
	body.BorderSizePixel = 0
	body.ZIndex = 18
	body.Parent = icon
	GuiStyle.Corner(body, 0.22)

	local band = Instance.new("Frame")
	band.Name = "Band"
	band.Position = UDim2.fromOffset(0, 0)
	band.Size = UDim2.fromOffset(30, 8)
	band.BorderSizePixel = 0
	band.ZIndex = 19
	band.Parent = body
	GuiStyle.Corner(band, 0.3)

	local dots = {}
	for row = 0, 1 do
		for col = 0, 2 do
			local dot = Instance.new("Frame")
			dot.Name = ("Dot%d%d"):format(row, col)
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromOffset(8 + col * 7, 12 + row * 6)
			dot.Size = UDim2.fromOffset(4, 4)
			dot.BorderSizePixel = 0
			dot.ZIndex = 20
			dot.Parent = body
			GuiStyle.Corner(dot, 1)
			table.insert(dots, dot)
		end
	end

	local function setActive(active)
		local tone = if active then CALENDAR_TONES.active else CALENDAR_TONES.inactive
		body.BackgroundColor3 = tone.Body
		band.BackgroundColor3 = tone.Band
		for _, ring in ipairs(rings) do
			ring.BackgroundColor3 = tone.Body
		end
		for _, dot in ipairs(dots) do
			dot.BackgroundColor3 = tone.Dot
		end
	end

	setActive(false)

	return { Frame = icon, SetActive = setActive }
end

local function setTabVisual(tabName, instant)
	for name, data in pairs(tabButtons) do
		local active = name == tabName

		-- Icy cyan when selected, deep navy with a royal-blue centre when not.
		-- Both read as premium; only one of them glows.
		local bg = active and Color3.fromRGB(206, 242, 255) or Color3.fromRGB(20, 34, 92)
		local outline = active and C.EdgeCyan or C.BorderBlue
		-- Selected: white letters with a deep navy outline, which is legible on
		-- the pale pill and matches the rest of the game's lettering. Ink-navy
		-- text on light cyan was too dark to read at a glance.
		local textColor = active and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(176, 202, 240)

		data.Text.TextColor3 = textColor
		if data.Rim then
			data.Rim.Color = outline
			data.Rim.Transparency = if active then 0 else 0.55
			data.Rim.Thickness = if active then 2.5 else 1.5
		end

		if data.TextStroke then
			data.TextStroke.Color = if active then Color3.fromRGB(18, 52, 122) else Color3.fromRGB(8, 14, 42)
			data.TextStroke.Thickness = if active then 3 else 2.5
			data.TextStroke.Transparency = 0
		end

		-- The rest of the selected look: a gloss across the top, an aura
		-- outside the pill, and a shadow that lifts it off the header. The
		-- unselected look keeps a faint inner light so it is not a flat box.
		if data.Gloss then
			data.Gloss.BackgroundTransparency = if active then 0.3 else 0.84
		end
		if data.Aura then
			data.Aura.Visible = active
		end
		if data.Lift then
			data.Lift.Visible = active
		end
		if data.InnerLight then
			-- An unselected tab still has light in it, so it reads as a
			-- premium control that happens not to be chosen.
			data.InnerLight.BackgroundTransparency = if active then 0.9 else 0.7
		end
		if data.SetIconActive then
			data.SetIconActive(active)
		end
		if data.IconImage then
			data.IconImage.ImageTransparency = if active then 0 else 0.22
		end

		-- A shading ramp, not a colour: it is multiplied against the pill's own
		-- colour, which is what the tween animates.
		if active then
			data.Gradient.Color = ColorSequence.new(
				Color3.fromRGB(255, 255, 255),
				Color3.fromRGB(198, 216, 232)
			)
		else
			data.Gradient.Color = ColorSequence.new(
				Color3.fromRGB(255, 255, 255),
				Color3.fromRGB(150, 162, 196)
			)
		end

		if instant then
			data.Button.BackgroundColor3 = bg
			data.Scale.Scale = active and 1.03 or 1
		else
			TweenService:Create(data.Button, TweenInfo.new(0.16), {
				BackgroundColor3 = bg,
			}):Play()

			TweenService:Create(data.Scale, TweenInfo.new(0.16), {
				Scale = active and 1.03 or 1,
			}):Play()
		end
	end
end

local function bounceTab(data)
	TweenService:Create(data.Button, TAB_BOUNCE, {
		Position = UDim2.fromOffset(0, -8),
	}):Play()

	TweenService:Create(data.Scale, TAB_BOUNCE, {
		Scale = 1.10,
	}):Play()

	task.delay(0.14, function()
		if data.Button and data.Button.Parent then
			TweenService:Create(data.Button, TAB_RETURN, {
				Position = UDim2.fromOffset(0, 0),
			}):Play()

			TweenService:Create(data.Scale, TAB_RETURN, {
				Scale = 1.03,
			}):Play()
		end
	end)
end

local function makeTab(name, order)
	local holder = Instance.new("Frame")
	holder.Name = name .. "Holder"
	holder.LayoutOrder = order
	holder.Size = UDim2.fromOffset(name == "All Time" and 244 or 214, 70)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 14
	holder.Parent = tabsFrame

	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.fromOffset(0, 0)
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(20, 34, 92)
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = 15
	button.Parent = holder
	corner(button, 0.26)

	-- Dark navy silhouette, constant. The bright edge is a separate shell
	-- inside it, exactly as the Store's cards are built.
	local tabStroke = stroke(button, C.CardEdge, 3)

	local rimShell = Instance.new("Frame")
	rimShell.Name = "Rim"
	rimShell.Position = UDim2.fromOffset(3, 3)
	rimShell.Size = UDim2.new(1, -6, 1, -6)
	rimShell.BackgroundTransparency = 1
	rimShell.BorderSizePixel = 0
	rimShell.ZIndex = 17
	rimShell.Parent = button
	corner(rimShell, 0.26)
	local tabRim = stroke(rimShell, C.EdgeCyan, 2)

	-- Lifted off the header when selected.
	local lift = Instance.new("Frame")
	lift.Name = "Lift"
	lift.AnchorPoint = Vector2.new(0.5, 0.5)
	lift.Position = UDim2.new(0.5, 0, 0.5, 5)
	lift.Size = UDim2.new(1, -8, 1, -4)
	lift.BackgroundColor3 = C.Shadow
	lift.BackgroundTransparency = 0.5
	lift.BorderSizePixel = 0
	lift.Visible = false
	lift.ZIndex = 14
	lift.Parent = holder
	corner(lift, 0.28)

	local aura = Instance.new("Frame")
	aura.Name = "Aura"
	aura.AnchorPoint = Vector2.new(0.5, 0.5)
	aura.Position = UDim2.fromScale(0.5, 0.5)
	aura.Size = UDim2.new(1, -2, 1, -2)
	aura.BackgroundTransparency = 1
	aura.BorderSizePixel = 0
	aura.Visible = false
	aura.ZIndex = 14
	aura.Parent = holder
	outerAura(aura, C.EdgeCyan, {
		{ Thickness = 3, Transparency = 0.32, ZIndex = 14, Radius = 0.26 },
		{ Thickness = 9, Transparency = 0.7, ZIndex = 14, Radius = 0.26 },
		{ Thickness = 18, Transparency = 0.87, ZIndex = 14, Radius = 0.26 },
	})

	local tabGradient = Instance.new("UIGradient")
	tabGradient.Rotation = 90
	tabGradient.Color = ColorSequence.new(
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(168, 180, 208)
	)
	tabGradient.Parent = button

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = button

	-- Gloss across the upper half, fading downwards.
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.AnchorPoint = Vector2.new(0.5, 0)
	gloss.Position = UDim2.new(0.5, 0, 0, 4)
	gloss.Size = UDim2.new(1, -14, 0, 26)
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.86
	gloss.BorderSizePixel = 0
	gloss.ZIndex = 16
	gloss.Parent = button
	corner(gloss, 1)

	do
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(0, 1)
		fade.Parent = gloss
	end

	-- Inner illumination, so an unselected tab is not a flat rectangle.
	local innerLight = Instance.new("Frame")
	innerLight.Name = "InnerLight"
	innerLight.AnchorPoint = Vector2.new(0.5, 1)
	innerLight.Position = UDim2.new(0.5, 0, 1, -3)
	innerLight.Size = UDim2.new(1, -18, 0, 22)
	innerLight.BackgroundColor3 = C.BorderBlue
	innerLight.BackgroundTransparency = 0.82
	innerLight.BorderSizePixel = 0
	innerLight.ZIndex = 16
	innerLight.Parent = button
	corner(innerLight, 1)

	do
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(1, 0.1)
		fade.Parent = innerLight
	end

	-- 44 is the largest size at which all three labels fit their boxes, so
	-- every tab renders at exactly the same size instead of one of them
	-- quietly scaling itself down.
	local text = makeText(button, {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		Text = name,
		TextColor3 = COL.Muted,
		ZIndex = 18,
		StrokeThickness = 2.5,
		MinTextSize = 26,
		MaxTextSize = 44,
	})
	local textStroke = text:FindFirstChildOfClass("UIStroke")

	local iconFrame, setIconActive, iconImage = nil, nil, nil

	if name == "All Time" then
		local crownIcon = Instance.new("ImageLabel")
		crownIcon.Name = "TabIcon"
		crownIcon.AnchorPoint = Vector2.new(0, 0.5)
		crownIcon.Position = UDim2.new(0, 12, 0.5, 0)
		crownIcon.Size = UDim2.fromOffset(38, 38)
		crownIcon.BackgroundTransparency = 1
		crownIcon.BorderSizePixel = 0
		crownIcon.Active = false
		crownIcon.Image = UIAssets.Crown or ""
		crownIcon.ScaleType = Enum.ScaleType.Fit
		crownIcon.ZIndex = 17
		crownIcon.Parent = button
		iconFrame = crownIcon
		iconImage = crownIcon
	else
		local calendar = makeCalendarIcon(button)
		iconFrame = calendar.Frame
		setIconActive = calendar.SetActive

		local artId = if name == "Daily" then UIAssets.TabDaily else UIAssets.TabWeekly
		if type(artId) == "string" and artId ~= "" then
			local art = Instance.new("ImageLabel")
			art.Name = "TabIconArt"
			art.AnchorPoint = Vector2.new(0, 0.5)
			art.Position = UDim2.new(0, 10, 0.5, 0)
			art.Size = UDim2.fromOffset(38, 38)
			art.BackgroundTransparency = 1
			art.BorderSizePixel = 0
			art.Active = false
			art.Image = artId
			art.ScaleType = Enum.ScaleType.Fit
			art.ZIndex = 17
			art.Parent = button
			iconImage = art

			whenImageLoaded(art, function()
				tabIconArtReady[name] = true
				calendar.Frame.Visible = false
			end)
		end
	end

	if iconFrame then
		text.Position = UDim2.fromOffset(54, 0)
		text.Size = UDim2.new(1, -66, 1, 0)
	end

	tabButtons[name] = {
		Holder = holder,
		Button = button,
		Text = text,
		TextStroke = textStroke,
		Stroke = tabStroke,
		Gradient = tabGradient,
		Scale = scale,
		Gloss = gloss,
		Rim = tabRim,
		Aura = aura,
		Lift = lift,
		InnerLight = innerLight,
		Icon = iconFrame,
		IconImage = iconImage,
		SetIconActive = setIconActive,
	}

	button.MouseEnter:Connect(function()
		TweenService:Create(scale, HOVER_IN, {
			Scale = name == activeTab and 1.05 or 1.02,
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(scale, HOVER_OUT, {
			Scale = name == activeTab and 1.03 or 1,
		}):Play()
	end)

	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, HOVER_OUT, { Scale = 0.98 }):Play()
	end)

	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, HOVER_IN, {
			Scale = name == activeTab and 1.05 or 1.02,
		}):Play()
	end)

	button.Activated:Connect(function()
		playTabClick()

		activeTab = name
		setTabVisual(activeTab, false)
		bounceTab(tabButtons[name])

		if refreshLeaderboard then
			refreshLeaderboard()
		end
	end)
end

makeTab("Daily", 1)
makeTab("Weekly", 2)
makeTab("All Time", 3)

-- ===== CONTENT =====

local content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.fromOffset(15, 127)
content.Size = UDim2.new(1, -30, 1, -138)
content.BackgroundTransparency = 1
content.ZIndex = 12
content.Parent = interior

local columnsFrame = Instance.new("Frame")
columnsFrame.Name = "Columns"
columnsFrame.Size = UDim2.fromScale(1, 1)
columnsFrame.BackgroundTransparency = 1
columnsFrame.ZIndex = 12
columnsFrame.Parent = content

local columnsLayout = Instance.new("UIListLayout")
columnsLayout.FillDirection = Enum.FillDirection.Horizontal
columnsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
columnsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
columnsLayout.Padding = UDim.new(0, 26)
columnsLayout.SortOrder = Enum.SortOrder.LayoutOrder
columnsLayout.Parent = columnsFrame

-- Gold, icy silver and warm bronze, each with its own four-stop face and a
-- brighter cap. The three pedestals should not look like the same object in
-- three colours.
local PODIUM_FACE = {
	[1] = {
		Top = Color3.fromRGB(255, 246, 198), Light = Color3.fromRGB(255, 226, 108),
		Mid = Color3.fromRGB(252, 196, 34), Deep = Color3.fromRGB(158, 100, 14),
		Cap = Color3.fromRGB(255, 250, 216), CapEdge = Color3.fromRGB(255, 220, 96),
	},
	[2] = {
		Top = Color3.fromRGB(250, 252, 255), Light = Color3.fromRGB(224, 233, 248),
		Mid = Color3.fromRGB(174, 190, 222), Deep = Color3.fromRGB(94, 110, 154),
		Cap = Color3.fromRGB(252, 254, 255), CapEdge = Color3.fromRGB(214, 228, 248),
	},
	[3] = {
		Top = Color3.fromRGB(255, 220, 182), Light = Color3.fromRGB(255, 174, 106),
		Mid = Color3.fromRGB(240, 126, 44), Deep = Color3.fromRGB(138, 62, 20),
		Cap = Color3.fromRGB(255, 230, 198), CapEdge = Color3.fromRGB(255, 180, 116),
	},
}

local function makeRankColor(index)
	if index == 1 then
		return C.Gold
	elseif index == 2 then
		return C.Silver
	elseif index == 3 then
		return C.Bronze
	end

	return COL.Cyan
end

-- The twinkling sparkles. Drawn rather than typed: a glyph can fall back to a
-- missing-character box on a device without it, and a drawn one cannot.
local function makeSoftSparkle(parent, x, y, delayTime, color)
	local sparkle = makeSparkle(parent, {
		Position = UDim2.fromOffset(x, y),
		Size = 18,
		Color = color or Color3.fromRGB(255, 235, 110),
		Transparency = 0,
		ZIndex = 38,
	})

	local parts = {}
	for _, child in ipairs(sparkle:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(parts, { Frame = child, Base = child.BackgroundTransparency })
		end
	end

	-- Fades everything towards invisible while keeping the bloom softer than
	-- the arms, so it twinkles as one object instead of flashing as parts.
	local function setAlpha(value)
		for _, part in ipairs(parts) do
			part.Frame.BackgroundTransparency = part.Base + (1 - part.Base) * value
		end
	end

	setAlpha(1)
	sparkle.Rotation = math.random(-25, 25)

	task.spawn(function()
		task.wait(delayTime)

		while sparkle.Parent do
			-- Nothing twinkles while the window is shut.
			while sparkle.Parent and not popup.Visible do
				task.wait(0.5)
			end
			if not sparkle.Parent then break end

			local target = sparkle.Rotation + 25
			local inTween = TweenService:Create(sparkle, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				Rotation = target,
			})
			inTween:Play()
			for step = 1, 6 do
				setAlpha(1 - step / 6 * 0.85)
				task.wait(0.075)
			end

			local outTween = TweenService:Create(sparkle, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Rotation = target + 30,
			})
			outTween:Play()
			for step = 1, 6 do
				setAlpha(0.15 + step / 6 * 0.85)
				task.wait(0.09)
			end

			task.wait(0.55 + math.random() * 0.9)
		end
	end)

	return sparkle
end

local function makeStaticCrown(parent)
	local crown = Instance.new("Frame")
	crown.Name = "Crown"
	crown.AnchorPoint = Vector2.new(0.5, 0.5)
	crown.Position = UDim2.new(0.5, 0, 0, -7)
	crown.Size = UDim2.fromOffset(46, 30)
	crown.BackgroundTransparency = 1
	crown.ZIndex = 44
	crown.Parent = parent

	local gold = Color3.fromRGB(255, 216, 55)
	local darkGold = Color3.fromRGB(190, 120, 0)

	local base = Instance.new("Frame")
	base.Name = "Base"
	base.AnchorPoint = Vector2.new(0.5, 1)
	base.Position = UDim2.new(0.5, 0, 1, 0)
	base.Size = UDim2.fromOffset(34, 9)
	base.BackgroundColor3 = gold
	base.BorderSizePixel = 0
	base.ZIndex = 45
	base.Parent = crown
	corner(base, 0.35)
	stroke(base, darkGold, 1)

	local left = Instance.new("Frame")
	left.Name = "LeftSpike"
	left.AnchorPoint = Vector2.new(0.5, 1)
	left.Position = UDim2.new(0.23, 0, 1, -5)
	left.Size = UDim2.fromOffset(9, 17)
	left.BackgroundColor3 = gold
	left.BorderSizePixel = 0
	left.Rotation = -15
	left.ZIndex = 45
	left.Parent = crown
	corner(left, 0.4)
	stroke(left, darkGold, 1)

	local middle = Instance.new("Frame")
	middle.Name = "MiddleSpike"
	middle.AnchorPoint = Vector2.new(0.5, 1)
	middle.Position = UDim2.new(0.5, 0, 1, -5)
	middle.Size = UDim2.fromOffset(11, 23)
	middle.BackgroundColor3 = gold
	middle.BorderSizePixel = 0
	middle.ZIndex = 46
	middle.Parent = crown
	corner(middle, 0.4)
	stroke(middle, darkGold, 1)

	local right = Instance.new("Frame")
	right.Name = "RightSpike"
	right.AnchorPoint = Vector2.new(0.5, 1)
	right.Position = UDim2.new(0.77, 0, 1, -5)
	right.Size = UDim2.fromOffset(9, 17)
	right.BackgroundColor3 = gold
	right.BorderSizePixel = 0
	right.Rotation = 15
	right.ZIndex = 45
	right.Parent = crown
	corner(right, 0.4)
	stroke(right, darkGold, 1)

	local gem = Instance.new("Frame")
	gem.Name = "Gem"
	gem.AnchorPoint = Vector2.new(0.5, 0.5)
	gem.Position = UDim2.new(0.5, 0, 1, -5)
	gem.Size = UDim2.fromOffset(7, 7)
	gem.BackgroundColor3 = COL.Cyan
	gem.BorderSizePixel = 0
	gem.ZIndex = 47
	gem.Parent = crown
	corner(gem, 0.5)

	-- The supplied crown sits over the drawn one, a little larger than the
	-- frame so it reads at podium size. Fit keeps its proportions and it is
	-- never tinted.
	local artId = UIAssets and UIAssets.Crown
	if type(artId) == "string" and artId ~= "" then
		local art = Instance.new("ImageLabel")
		art.Name = "CrownArt"
		art.BackgroundTransparency = 1
		art.BorderSizePixel = 0
		art.Active = false
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, 0.5)
		art.Size = UDim2.fromScale(1.45, 1.45)
		art.Image = artId
		art.ScaleType = Enum.ScaleType.Fit
		art.ZIndex = 48
		art.Parent = crown

		dropShadow(crown, {
			Name = "CrownShadow", Position = UDim2.new(0.5, 2, 0.5, 5),
			Size = UDim2.fromScale(1.2, 1.1), Transparency = 0.62,
			ZIndex = 42, Radius = 0.4,
		})

		local glow = softGlow(crown, {
			Name = "CrownGlow", Size = UDim2.fromScale(1.75, 1.6),
			Color = Color3.fromRGB(255, 228, 130), Transparency = 0.66,
			ZIndex = 43, Radius = 0.5,
		})
		glow.Visible = false

		local drawn = { base, left, middle, right, gem }
		whenImageLoaded(art, function()
			for _, piece in ipairs(drawn) do
				piece.Visible = false
			end
			glow.Visible = true
		end)
	end

	return crown
end

-- ===== PAINTED PEDESTALS =====
-- Size is the square box the picture is fitted into; Drop is how far below the
-- floor line that box sits, which is how the three are levelled with each
-- other. If a pedestal looks too big, too small or is floating, these six
-- numbers are the only ones to touch.
-- Clearance between a stat line and the top of its own painted pedestal.
-- First place's carries a crown, so its plate hangs a lot further up.
-- -36 rather than -38 on first place: at -38 the glow behind its avatar
-- started 1px above the top of the podium region, which clips.
local PLATE_DROP = { [1] = -36, [2] = -12, [3] = -18 }

local PODIUM_ART = {
	[1] = { Key = "Podium1", Size = 152, Drop = 6 },
	[2] = { Key = "Podium2", Size = 120, Drop = 2 },
	[3] = { Key = "Podium3", Size = 120, Drop = 8 },
}

local function makePodiumSlot(parent, rank, xOffset, yOffset, standHeight, standWidth, accent)
	local holder = Instance.new("Frame")
	holder.Name = "Podium" .. rank
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, xOffset, 1, yOffset)
	holder.Size = UDim2.fromOffset(standWidth, 150)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 24
	holder.Parent = parent

	-- Everything the painted pedestal would draw over. Collected as it is
	-- built, hidden in one go if the picture loads.
	local drawnPodium = {}

	local holderScale = Instance.new("UIScale")
	holderScale.Scale = 1
	holderScale.Parent = holder

	local standTopY = 150 - standHeight
	local profileSize = rank == 1 and 52 or 44
	local rankColor = makeRankColor(rank)

	-- The halo the pedestal stands in: its own clean ellipse, centred, and
	-- narrow enough that it never runs into the one beside it. The podium area
	-- clips at 248 and this bottoms out at 245.
	do
		local ring = Instance.new("Frame")
		ring.Name = "GroundRing"
		ring.AnchorPoint = Vector2.new(0.5, 1)
		ring.Position = UDim2.new(0.5, 0, 1, 7)
		ring.Size = UDim2.fromOffset(standWidth + 14, 26)
		ring.BackgroundColor3 = rankColor
		ring.BackgroundTransparency = if rank == 1 then 0.3 else 0.52
		ring.BorderSizePixel = 0
		ring.ZIndex = 23
		ring.Parent = holder
		corner(ring, 1)

		local ringEdge = stroke(ring, rankColor:Lerp(Color3.new(1, 1, 1), 0.45), 2.5)
		ringEdge.Transparency = if rank == 1 then 0.1 else 0.35

		local ringFade = Instance.new("UIGradient")
		ringFade.Rotation = 90
		ringFade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.6, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		ringFade.Parent = ring
		table.insert(drawnPodium, ring)

		softGlow(holder, {
			Name = "BaseGlow", AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 9), Size = UDim2.fromOffset(standWidth + 30, 34),
			Color = rankColor, Transparency = if rank == 1 then 0.5 else 0.68,
			ZIndex = 22, Radius = 1,
		})
	end

	local face = PODIUM_FACE[rank] or PODIUM_FACE[1]

	-- The base the cylinder sits on: a darker ellipse, slightly wider than the
	-- body, which both grounds it and gives the bottom its curve.
	do
		local base = Instance.new("Frame")
		base.Name = "BasePlate"
		base.AnchorPoint = Vector2.new(0.5, 1)
		base.Position = UDim2.new(0.5, 0, 1, 0)
		base.Size = UDim2.fromOffset(standWidth + 8, 20)
		base.BackgroundColor3 = face.Deep
		base.BackgroundTransparency = 0
		base.BorderSizePixel = 0
		base.ZIndex = 24
		base.Parent = holder
		corner(base, 1)
		local baseEdge = stroke(base, C.CardEdge, 2)
		baseEdge.Transparency = 0.2
		table.insert(drawnPodium, base)
	end

	local stand = Instance.new("Frame")
	stand.Name = "Stand"
	stand.AnchorPoint = Vector2.new(0.5, 1)
	stand.Position = UDim2.new(0.5, 0, 1, 0)
	stand.Size = UDim2.fromOffset(standWidth, standHeight)
	stand.BackgroundColor3 = Color3.new(1, 1, 1)   -- sheen gradient carries gold/silver/bronze
	stand.BackgroundTransparency = 0
	stand.ZIndex = 25
	stand.Parent = holder
	corner(stand, 0.14)

	local standStroke = stroke(stand, C.CardEdge, 2.5)

	do
		local sheen = Instance.new("UIGradient")
		sheen.Rotation = 90
		-- Toy-like: a bright upper face, full colour through the middle, and a
		-- distinctly darker lower edge. Each place has its own four stops.
		sheen.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, face.Top),
			ColorSequenceKeypoint.new(0.26, face.Light),
			ColorSequenceKeypoint.new(0.66, face.Mid),
			ColorSequenceKeypoint.new(1, face.Deep),
		})
		sheen.Parent = stand
	end

	do
		local sideLight = Instance.new("Frame")
		sideLight.Name = "SideLight"
		sideLight.AnchorPoint = Vector2.new(0, 0.5)
		sideLight.Position = UDim2.new(0, 7, 0.5, 4)
		sideLight.Size = UDim2.new(0, 5, 1, -22)
		sideLight.BackgroundColor3 = Color3.new(1, 1, 1)
		sideLight.BackgroundTransparency = 0.72
		sideLight.BorderSizePixel = 0
		sideLight.ZIndex = 26
		sideLight.Parent = stand
		corner(sideLight, 1)

		local sideFade = Instance.new("UIGradient")
		sideFade.Rotation = 90
		sideFade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		sideFade.Parent = sideLight
	end

	-- The top surface. Centred on the stand's top edge so half of it stands
	-- proud: that overhang is what reads as a curved top rather than a corner.
	local cap = Instance.new("Frame")
	cap.Name = "TopCap"
	cap.AnchorPoint = Vector2.new(0.5, 0.5)
	cap.Position = UDim2.new(0.5, 0, 0, 0)
	cap.Size = UDim2.fromOffset(standWidth, 18)
	cap.BackgroundColor3 = face.Cap
	cap.BackgroundTransparency = 0
	cap.BorderSizePixel = 0
	cap.ZIndex = 26
	cap.Parent = stand
	corner(cap, 1)

	do
		local capEdge = stroke(cap, C.CardEdge, 2)
		capEdge.Transparency = 0.25

		local capSheen = Instance.new("UIGradient")
		capSheen.Rotation = 90
		capSheen.Color = ColorSequence.new(Color3.new(1, 1, 1), face.CapEdge)
		capSheen.Parent = cap
	end

	table.insert(drawnPodium, stand)

	local crown = nil
	if rank == 1 then
		crown = makeStaticCrown(stand)
		if crown then
			crown.Parent = stand
			crown.AnchorPoint = Vector2.new(0.5, 0)
			crown.Position = UDim2.new(0.5, 0, 0, -2)
			crown.ZIndex = 28
		end
	end

	makeText(stand, {
		Name = "RankText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if rank == 1 then 0.71 else 0.6),
		Size = UDim2.fromScale(1, if rank == 1 then 0.54 else 0.72),
		Text = tostring(rank),
		TextColor3 = COL.Light,
		ZIndex = 27,
		StrokeThickness = 3.5,
		MinTextSize = 26,
		MaxTextSize = rank == 1 and 54 or 42,
	})

	-- The painted pedestal. It supplies the stand, the number and the crown,
	-- so the drawn ones are only used when there is no picture id.
	local art = nil
	do
		local spec = PODIUM_ART[rank]
		local artId = spec and UIAssets[spec.Key]

		if type(artId) == "string" and artId ~= "" then
			art = Instance.new("ImageLabel")
			art.Name = "PodiumArt"
			art.AnchorPoint = Vector2.new(0.5, 1)
			art.Position = UDim2.new(0.5, 0, 1, spec.Drop)
			art.Size = UDim2.fromOffset(spec.Size, spec.Size)
			art.BackgroundTransparency = 1
			art.BorderSizePixel = 0
			art.Active = false
			art.Image = artId
			art.ScaleType = Enum.ScaleType.Fit
			art.ZIndex = 29
			art.Parent = holder

			-- The picture is the podium: the drawn stand, number and crown
			-- are hidden straight away, so they never show behind it while
			-- it loads (or if the load signal comes late).
			for _, piece in ipairs(drawnPodium) do
				piece.Visible = false
			end
		end
	end

	local infoPlate = Instance.new("Frame")
	infoPlate.Name = "InfoPlate"
	infoPlate.AnchorPoint = Vector2.new(0.5, 1)
	-- Hangs clear above the pedestal: far enough that the stat line never
	-- touches the pedestal's top edge, and on first place never touches the
	-- crown either.
	infoPlate.Position = UDim2.new(0.5, 0, 0, standTopY + PLATE_DROP[rank])
	infoPlate.Size = UDim2.fromOffset(standWidth + 22, 82)
	infoPlate.BackgroundTransparency = 1
	infoPlate.ZIndex = 30
	infoPlate.Parent = holder

	-- Depth first: the shadow it sits above, then the aura it gives off.
	-- Both, deliberately - a glow on its own reads as decoration, a shadow on
	-- its own reads as flat. Together they lift the badge off the card.
	dropShadow(infoPlate, {
		Name = "AvatarShadow", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 2, 0, -profileSize / 2 + 5),
		Size = UDim2.fromOffset(profileSize, profileSize),
		Transparency = 0.5, ZIndex = 31, Radius = 1,
	})

	softGlow(infoPlate, {
		Name = "AvatarGlow", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -profileSize / 2 - 9),
		Size = UDim2.fromOffset(profileSize + 22, profileSize + 18),
		Color = rankColor, Transparency = if rank == 1 then 0.42 else 0.56,
		ZIndex = 32, Radius = 1,
	})

	local profileHolder = Instance.new("Frame")
	profileHolder.Name = "ProfileHolder"
	profileHolder.AnchorPoint = Vector2.new(0.5, 0)
	profileHolder.Position = UDim2.new(0.5, 0, 0, -profileSize / 2)
	profileHolder.Size = UDim2.fromOffset(profileSize, profileSize)
	profileHolder.BackgroundColor3 = Color3.new(1, 1, 1)   -- gradient below
	profileHolder.BackgroundTransparency = 0
	profileHolder.ZIndex = 34
	profileHolder.Parent = infoPlate
	corner(profileHolder, 0.5)
	gradient(profileHolder, Color3.fromRGB(38, 62, 148), Color3.fromRGB(14, 24, 74))

	-- The ring carries the rank metal: gold, silver, bronze.
	local profileStroke = stroke(profileHolder, rankColor, if rank == 1 then 4 else 3)

	do
		-- A highlight across the top of the disc, as on a moulded button.
		local capLight = Instance.new("Frame")
		capLight.Name = "CapLight"
		capLight.AnchorPoint = Vector2.new(0.5, 0)
		capLight.Position = UDim2.new(0.5, 0, 0, 4)
		capLight.Size = UDim2.new(0.66, 0, 0, math.floor(profileSize * 0.3))
		capLight.BackgroundColor3 = Color3.new(1, 1, 1)
		capLight.BackgroundTransparency = 0.7
		capLight.BorderSizePixel = 0
		capLight.ZIndex = 35        -- above the disc (34), under the avatar (36)
		capLight.Parent = profileHolder
		corner(capLight, 1)

		local capFade = Instance.new("UIGradient")
		capFade.Rotation = 90
		capFade.Transparency = NumberSequence.new(0.25, 1)
		capFade.Parent = capLight
	end

	local profileImage = Instance.new("ImageLabel")
	profileImage.Name = "ProfileImage"
	profileImage.BackgroundTransparency = 1
	profileImage.Size = UDim2.fromScale(1, 1)
	profileImage.Image = ""
	profileImage.ScaleType = Enum.ScaleType.Crop
	profileImage.ZIndex = 36
	profileImage.Parent = profileHolder
	corner(profileImage, 0.5)

	local profileLetter = makeText(profileHolder, {
		Name = "ProfileLetter",
		Size = UDim2.fromScale(1, 1),
		Text = "?",
		TextColor3 = if rank == 1 then Color3.fromRGB(255, 248, 214) else C.Cream,
		ZIndex = 38,
		StrokeThickness = 2.5,
		MinTextSize = 12,
		MaxTextSize = 24,
	})
	do
		local letterEdge = profileLetter:FindFirstChildOfClass("UIStroke")
		if letterEdge then
			letterEdge.Color = C.Ink
		end
	end

	local nameLabel = makeText(infoPlate, {
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, profileSize / 2 + 8),
		Size = UDim2.fromOffset(standWidth + 12, 21),
		Text = "",
		TextColor3 = COL.Light,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 33,
		StrokeThickness = 2.5,
		MinTextSize = 9,
		MaxTextSize = rank == 1 and 17 or 14,
	})

	local valueLabel = makeText(infoPlate, {
		Name = "Value",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, profileSize / 2 + 32),
		Size = UDim2.fromOffset(standWidth + 12, 19),
		Text = "",
		TextColor3 = if rank == 1 then Color3.fromRGB(255, 238, 160) else Color3.fromRGB(214, 234, 255),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 33,
		StrokeThickness = 2.5,
		MinTextSize = 9,
		MaxTextSize = rank == 1 and 16 or 13,
	})

	return {
		Holder = holder,
		Scale = holderScale,
		ProfileImage = profileImage,
		ProfileLetter = profileLetter,
		ProfileStroke = profileStroke,
		Name = nameLabel,
		Value = valueLabel,
		Stand = stand,
		StandStroke = standStroke,
		InfoPlate = infoPlate,
		Crown = crown,
		Art = art,
		-- Remembered so the "you" highlight can put them back instead of
		-- flattening every podium to the default outline colour.
		BaseStandColor = C.CardEdge,
		BaseProfileColor = rankColor,
		BaseProfileThickness = if rank == 1 then 4 else 3,
		Accent = accent,
	}
end

local ROW_HEIGHT = 52

local function makeRow(parent, index, accent, tint)
	local row = Instance.new("Frame")
	row.Name = "Row" .. index
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -28, 0, ROW_HEIGHT)
	row.BackgroundColor3 = Color3.new(1, 1, 1)   -- gradient carries the colour
	row.BackgroundTransparency = index % 2 == 0 and 0.16 or 0.08
	row.BorderSizePixel = 0
	row.ZIndex = 20
	row.Parent = parent
	corner(row, 0.32)

	local rowStroke = stroke(row, C.CardEdge, 1.5)
	rowStroke.Transparency = 0.35

	-- A tenth of the card's own light mixed into the row, so the three lists
	-- are recognisably cyan, violet and warm rather than one shared blue.
	local warm = tint or Color3.fromRGB(64, 156, 255)
	local rowTop = Color3.fromRGB(42, 66, 158):Lerp(warm, 0.12)
	local rowBottom = Color3.fromRGB(20, 32, 96):Lerp(warm, 0.08)
	local rowGradient = gradient(row, rowTop, rowBottom)

	-- A hairline of light along the top edge gives the strip some depth.
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.AnchorPoint = Vector2.new(0.5, 0)
	sheen.Position = UDim2.new(0.5, 0, 0, 3)
	sheen.Size = UDim2.new(1, -22, 0, 2)
	sheen.BackgroundColor3 = Color3.fromRGB(180, 222, 255)
	sheen.BackgroundTransparency = 0.66
	sheen.BorderSizePixel = 0
	sheen.ZIndex = 21
	sheen.Parent = row
	corner(sheen, 1)

	dropShadow(row, {
		Name = "RankShadow", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 4), Size = UDim2.fromOffset(34, 34),
		Transparency = 0.55, ZIndex = 20, Radius = 1,
	})

	local rankBubble = Instance.new("Frame")
	rankBubble.Name = "RankBubble"
	rankBubble.AnchorPoint = Vector2.new(0, 0.5)
	rankBubble.Position = UDim2.new(0, 8, 0.5, 0)
	rankBubble.Size = UDim2.fromOffset(34, 34)
	rankBubble.BackgroundColor3 = accent or COL.Cyan
	rankBubble.BackgroundTransparency = 0
	rankBubble.ZIndex = 21
	rankBubble.Parent = row
	corner(rankBubble, 0.5)
	stroke(rankBubble, C.CardEdge, 2)

	do
		-- Glossy, like the podium rank markers.
		local bubbleSheen = Instance.new("UIGradient")
		bubbleSheen.Rotation = 90
		bubbleSheen.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(228, 228, 228)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(158, 158, 158)),
		})
		bubbleSheen.Parent = rankBubble
	end

	local rankLabel = makeText(rankBubble, {
		Name = "RankText",
		Size = UDim2.fromScale(1, 1),
		Text = tostring(index),
		TextColor3 = COL.Light,
		ZIndex = 22,
		StrokeThickness = 2,
		MinTextSize = 13,
		MaxTextSize = 22,
	})

	dropShadow(row, {
		Name = "AvatarShadow", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 50, 0.5, 4), Size = UDim2.fromOffset(42, 42),
		Transparency = 0.55, ZIndex = 20, Radius = 1,
	})

	local profileHolder = Instance.new("Frame")
	profileHolder.Name = "ProfileHolder"
	profileHolder.AnchorPoint = Vector2.new(0, 0.5)
	profileHolder.Position = UDim2.new(0, 48, 0.5, 0)
	profileHolder.Size = UDim2.fromOffset(42, 42)
	profileHolder.BackgroundColor3 = Color3.fromRGB(19, 32, 84)
	profileHolder.BackgroundTransparency = 0
	profileHolder.ZIndex = 21
	profileHolder.Parent = row
	corner(profileHolder, 0.5)

	local profileStroke = stroke(profileHolder, Color3.fromRGB(96, 142, 224), 2)

	local profileImage = Instance.new("ImageLabel")
	profileImage.Name = "ProfileImage"
	profileImage.BackgroundTransparency = 1
	profileImage.Size = UDim2.fromScale(1, 1)
	profileImage.Image = ""
	profileImage.ScaleType = Enum.ScaleType.Crop
	profileImage.ZIndex = 22
	profileImage.Parent = profileHolder
	corner(profileImage, 0.5)

	local profileLetter = makeText(profileHolder, {
		Name = "ProfileLetter",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextColor3 = COL.Light,
		ZIndex = 23,
		StrokeThickness = 2,
		MinTextSize = 13,
		MaxTextSize = 22,
	})

	-- The name and the value live together on one rounded bar, which is what
	-- gives the reference rows their shape. It stays put when a row is empty,
	-- so an unfilled place reads as a waiting slot instead of a broken line.
	local infoBar = Instance.new("Frame")
	infoBar.Name = "InfoBar"
	infoBar.AnchorPoint = Vector2.new(0, 0.5)
	infoBar.Position = UDim2.new(0, 96, 0.5, 0)
	infoBar.Size = UDim2.new(1, -104, 0, 34)
	infoBar.BackgroundColor3 = Color3.new(1, 1, 1)   -- gradient carries the colour
	infoBar.BackgroundTransparency = 0.25
	infoBar.BorderSizePixel = 0
	infoBar.ZIndex = 21
	infoBar.Parent = row
	corner(infoBar, 0.5)

	local barEdge, barShine
	do
		barEdge = stroke(infoBar, C.CardEdge, 1.5)
		barEdge.Transparency = 0.45

		local barLight = Instance.new("UIGradient")
		barLight.Rotation = 90
		barLight.Color = ColorSequence.new(
			Color3.fromRGB(26, 44, 116),
			Color3.fromRGB(13, 22, 70)
		)
		barLight.Parent = infoBar

		barShine = Instance.new("Frame")
		barShine.Name = "BarShine"
		barShine.AnchorPoint = Vector2.new(0.5, 0)
		barShine.Position = UDim2.new(0.5, 0, 0, 3)
		barShine.Size = UDim2.new(1, -16, 0, 3)
		barShine.BackgroundColor3 = Color3.fromRGB(150, 200, 255)
		barShine.BackgroundTransparency = 0.72
		barShine.BorderSizePixel = 0
		barShine.ZIndex = 22
		barShine.Parent = infoBar
		corner(barShine, 1)
	end

	local nameLabel = makeText(infoBar, {
		Name = "Name",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(86, 24),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.Light,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 22,
		StrokeThickness = 2,
		MinTextSize = 11,
		MaxTextSize = 19,
	})

	local youTag = makeText(infoBar, {
		Name = "YouTag",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 58, 0.5, 0),
		Size = UDim2.fromOffset(38, 20),
		Text = "YOU",
		TextColor3 = COL.Yellow,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 24,
		StrokeThickness = 2,
		MinTextSize = 10,
		MaxTextSize = 16,
	})
	youTag.Visible = false

	local valueLabel = makeText(infoBar, {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(92, 26),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(232, 244, 255),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 22,
		StrokeThickness = 2.5,
		MinTextSize = 12,
		MaxTextSize = 22,
	})

	local emptyMark = Instance.new("ImageLabel")
	emptyMark.Name = "EmptyMark"
	emptyMark.AnchorPoint = Vector2.new(1, 0.5)
	emptyMark.Position = UDim2.new(1, -16, 0.5, 0)
	emptyMark.Size = UDim2.fromOffset(22, 22)
	emptyMark.BackgroundTransparency = 1
	emptyMark.BorderSizePixel = 0
	emptyMark.Active = false
	emptyMark.Image = UIAssets.Crown or ""
	emptyMark.ImageTransparency = 0.55
	emptyMark.ScaleType = Enum.ScaleType.Fit
	emptyMark.ZIndex = 23
	emptyMark.Parent = infoBar
	emptyMark.Visible = false

	-- Shown instead of the row's contents when a board genuinely has nobody
	-- past the podium, so the list never fills up with rows of dashes.
	local caption = makeText(row, {
		Name = "Caption",
		Size = UDim2.fromScale(1, 1),
		Text = "No other players yet",
		TextColor3 = Color3.fromRGB(150, 178, 224),
		ZIndex = 23,
		StrokeThickness = 2,
		MinTextSize = 11,
		MaxTextSize = 18,
	})
	caption.Visible = false

	return {
		Frame = row,
		RowStroke = rowStroke,
		Gradient = rowGradient,
		RankBubble = rankBubble,
		Rank = rankLabel,
		ProfileHolder = profileHolder,
		ProfileImage = profileImage,
		ProfileLetter = profileLetter,
		ProfileStroke = profileStroke,
		InfoBar = infoBar,
		BarEdge = barEdge,
		BarShine = barShine,
		EmptyMark = emptyMark,
		Sheen = sheen,
		Name = nameLabel,
		Value = valueLabel,
		YouTag = youTag,
		Caption = caption,
		BaseColor = row.BackgroundColor3,
		BaseTop = rowTop,
		BaseBottom = rowBottom,
		BaseTransparency = row.BackgroundTransparency,
		BaseStrokeColor = rowStroke.Color,
		BaseProfileColor = profileStroke.Color,
		BubbleColor = accent or COL.Cyan,
		NameWide = 86,
		NameNarrow = 44,
	}
end

-- One place decides what a row is showing.
--   filled  - real player
--   empty   - a waiting slot: shape, no text
--   caption - the "nobody here yet" line
local function setRowMode(row, mode)
	local filled = mode == "filled"
	local caption = mode == "caption"

	row.Frame.Visible = true
	row.Caption.Visible = caption
	row.RankBubble.Visible = not caption
	row.ProfileHolder.Visible = not caption
	row.InfoBar.Visible = not caption

	if caption then
		row.Frame.BackgroundTransparency = math.min(row.BaseTransparency + 0.45, 0.94)
		return
	end

	row.Frame.BackgroundTransparency = if filled
		then row.BaseTransparency
		else math.min(row.BaseTransparency + 0.26, 0.86)
	row.InfoBar.BackgroundTransparency = if filled then 0.25 else 0.52
	row.ProfileHolder.BackgroundTransparency = if filled then 0 else 0.4
	row.RankBubble.BackgroundTransparency = if filled then 0 else 0.45

	-- The outlines and highlights step back too. Leaving them at full
	-- strength on an empty row is what made it look like a broken control.
	if row.RowStroke then
		row.RowStroke.Transparency = if filled then 0.35 else 0.66
	end
	if row.BarEdge then
		row.BarEdge.Transparency = if filled then 0.45 else 0.78
	end
	if row.BarShine then
		row.BarShine.Visible = filled
	end
	if row.Sheen then
		row.Sheen.BackgroundTransparency = if filled then 0.66 else 0.88
	end
	if row.ProfileStroke then
		row.ProfileStroke.Transparency = if filled then 0 else 0.55
	end
	if row.EmptyMark then
		row.EmptyMark.Visible = not filled
	end

	if not filled then
		row.Name.Text = ""
		row.Value.Text = ""
		row.ProfileImage.Image = ""
		row.ProfileLetter.Text = ""
	end
end

local function makeColumn(key, titleText, order)
	local theme = THEME[key] or THEME.Stardust
	local iconId = UIAssets[theme.Icon]

	local column = Instance.new("Frame")
	column.Name = key .. "Column"
	column.LayoutOrder = order
	column.Size = UDim2.new(0, 336, 1, 0)
	column.BackgroundColor3 = Color3.new(1, 1, 1)   -- gradient carries the colour
	column.BackgroundTransparency = 0.04
	column.ZIndex = 13
	column.Parent = columnsFrame
	corner(column, 0.055)

	-- Behind the card: a shadow that lifts it off the window. ZIndex 12 puts it
	-- strictly under the card body (13), and nothing here clips, so it can sit
	-- outside the card's own bounds.
	dropShadow(column, {
		Name = "CardShadow", Position = UDim2.new(0.5, 2, 0.5, 8),
		Size = UDim2.new(1, -6, 1, -4), Transparency = 0.74,
		ZIndex = 12, Radius = 0.06,
	})

	-- Dark silhouette, one coloured rim, then the aura outside it. Each card
	-- keeps 22px of clear space either side, so the aura is never cut off.
	-- Two layers, like the Store's cards: a deep navy outline, then the
	-- luminous themed rim just inside it. A single thick coloured stroke is
	-- what made these read as bordered frames instead of lit panels.
	stroke(column, C.CardEdge, 3)

	do
		local rimShell = Instance.new("Frame")
		rimShell.Name = "Rim"
		rimShell.Position = UDim2.fromOffset(3, 3)
		rimShell.Size = UDim2.new(1, -6, 1, -6)
		rimShell.BackgroundTransparency = 1
		rimShell.BorderSizePixel = 0
		rimShell.ZIndex = 58
		rimShell.Parent = column
		corner(rimShell, 0.055)
		local rimEdge = stroke(rimShell, theme.Rim, 2.5)

		local rimLight = Instance.new("UIGradient")
		rimLight.Rotation = 90
		rimLight.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.55, 0.35),
			NumberSequenceKeypoint.new(1, 0.62),
		})
		rimLight.Parent = rimEdge

		-- STEP 44: the lower corners catch a little of the card's own light.
		for _, spot in ipairs({ { 0.16, 1 }, { 0.84, 1 } }) do
			softGlow(column, {
				Name = "CornerLight", AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(spot[1], 0, spot[2], 4),
				Size = UDim2.fromOffset(96, 40), Color = theme.Rim,
				Transparency = 0.86, ZIndex = 14, Radius = 1,
			})
		end
	end

	outerAura(column, theme.Rim, {
		{ Thickness = 3, Transparency = 0.6, ZIndex = 12, Radius = 0.055 },
		{ Thickness = 8, Transparency = 0.82, ZIndex = 12, Radius = 0.055 },
		{ Thickness = 17, Transparency = 0.93, ZIndex = 12, Radius = 0.055 },
	})

	-- Royal blue at the top into deep navy: the Store's interior language, not
	-- a black panel with colour sprayed on it.
	gradient(column, Color3.fromRGB(36, 58, 146), Color3.fromRGB(16, 26, 84))

	-- Themed light inside the card: brightest behind the podium, fading out
	-- towards the edges, so the interior is not a uniform black panel.
	softGlow(column, {
		Name = "PodiumLight", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08), Size = UDim2.new(1, 40, 0, 360),
		Color = theme.Aura, Transparency = 0.72, ZIndex = 13, Radius = 0.2,
	})
	softGlow(column, {
		Name = "BodyLight", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.99), Size = UDim2.new(1, -44, 0, 240),
		Color = theme.Aura, Transparency = 0.84, ZIndex = 13, Radius = 0.15,
	})
	starField(column, {
		{ 0.08, 0.50, 3, theme.Spark, 0.2 }, { 0.92, 0.44, 3 },
		{ 0.5, 0.975, 3 }, { 0.17, 0.85, 2 },
		{ 0.83, 0.90, 2, theme.Spark, 0.25 }, { 0.30, 0.66, 2 },
		{ 0.06, 0.63, 2, theme.Spark, 0.35 }, { 0.95, 0.68, 2 },
	}, 14)

	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Position = UDim2.fromOffset(0, 0)
	titleBar.Size = UDim2.new(1, 0, 0, 86)
	titleBar.BackgroundColor3 = Color3.new(1, 1, 1)   -- gradient carries the colour
	titleBar.BackgroundTransparency = 0
	titleBar.ZIndex = 14
	titleBar.Parent = column
	corner(titleBar, 0.2)        -- 15px, to sit inside the card's 18px corner
	stroke(titleBar, theme.HeaderEdge, 3)

	do
		-- Four stops: a bright upper face, the light colour, the saturated
		-- middle, then a distinctly darker lower edge. This is the same
		-- material as the Store's pink game-pass strips.
		local headerSky = Instance.new("UIGradient")
		headerSky.Rotation = 90
		headerSky.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.HeaderPeak),
			ColorSequenceKeypoint.new(0.24, theme.HeaderTop),
			ColorSequenceKeypoint.new(0.68, theme.HeaderMid),
			ColorSequenceKeypoint.new(1, theme.HeaderBottom),
		})
		headerSky.Parent = titleBar

		-- The header sits on the card, so it casts a little shade onto it.
		dropShadow(column, {
			Name = "HeaderShadow", AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.new(1, -10, 0, 86),
			Transparency = 0.55, ZIndex = 13, Radius = 0.06,
		})
	end

	do
		local shine = Instance.new("Frame")
		shine.Name = "Shine"
		shine.AnchorPoint = Vector2.new(0.5, 0)
		shine.Position = UDim2.new(0.5, 0, 0, 5)
		shine.Size = UDim2.new(1, -18, 0, 24)
		shine.BackgroundColor3 = Color3.new(1, 1, 1)
		shine.BackgroundTransparency = 0.64
		shine.BorderSizePixel = 0
		shine.ZIndex = 15
		shine.Parent = titleBar
		corner(shine, 1)

		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(0, 1)
		fade.Parent = shine

		-- A short reflective streak across the upper right, the way a glossy
		-- moulded surface catches light in one place rather than evenly.
		local streak = Instance.new("Frame")
		streak.Name = "Streak"
		streak.AnchorPoint = Vector2.new(1, 0)
		streak.Position = UDim2.new(1, -22, 0, 9)
		streak.Size = UDim2.fromOffset(66, 7)
		streak.BackgroundColor3 = Color3.new(1, 1, 1)
		streak.BackgroundTransparency = 0.55
		streak.BorderSizePixel = 0
		streak.Rotation = -4
		streak.ZIndex = 16
		streak.Parent = titleBar
		corner(streak, 1)

		local streakFade = Instance.new("UIGradient")
		streakFade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		streakFade.Parent = streak
	end

	-- Category emblem, drawn as supplied: no tint, no stretch, room for its
	-- glow. 72px makes it a hero element in the header rather than a bullet.
	local icon = Instance.new("ImageLabel")
	icon.Name = "CategoryIcon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 12, 0.5, 0)
	icon.Size = UDim2.fromOffset(78, 78)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.Active = false
	icon.Image = iconId or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 17
	icon.Parent = titleBar

	softGlow(titleBar, {
		Name = "IconGlow", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 9, 0.5, 0), Size = UDim2.fromOffset(88, 88),
		Color = if key == "Stardust" then Color3.fromRGB(255, 236, 150) else Color3.new(1, 1, 1),
		Transparency = 0.62, ZIndex = 16, Radius = 1,
	})

	dropShadow(titleBar, {
		Name = "IconShadow", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 15, 0.5, 4), Size = UDim2.fromOffset(76, 76),
		Transparency = 0.7, ZIndex = 15, Radius = 1,
	})

	-- Title box stops at x=302 on every card, which leaves the right-hand
	-- corner free for decoration and keeps all three headers padded alike.
	makeText(titleBar, {
		Name = "Title",
		Position = UDim2.fromOffset(92, 0),
		Size = UDim2.new(1, -126, 1, 0),
		Text = titleText,
		TextColor3 = C.Cream,
		ZIndex = 17,
		StrokeThickness = 3.8,
		Gloss = true,
		MinTextSize = 20,
		MaxTextSize = 38,
	})

	-- Two small themed sparkles per header.
	makeSparkle(titleBar, { Name = "HeaderSparkleA", Position = UDim2.new(0, 84, 0, 14),
		Size = 14, Color = Color3.new(1, 1, 1), Transparency = 0.22, ZIndex = 18, Rotation = 12 })
	makeSparkle(titleBar, { Name = "HeaderSparkleB", Position = UDim2.new(1, -26, 0, 62),
		Size = 12, Color = theme.Spark, Transparency = 0.18, ZIndex = 18, Rotation = -10 })
	makeSparkle(titleBar, { Name = "HeaderSparkleC", Position = UDim2.new(0, 96, 0, 64),
		Size = 9, Color = theme.Spark, Transparency = 0.4, ZIndex = 18, Rotation = -22 })

	local podiumArea = Instance.new("Frame")
	podiumArea.Name = "PodiumArea"
	podiumArea.Position = UDim2.fromOffset(0, 90)
	podiumArea.Size = UDim2.new(1, 0, 0, 268)
	podiumArea.BackgroundColor3 = Color3.fromRGB(11, 19, 62)
	podiumArea.BackgroundTransparency = 0.24
	podiumArea.ZIndex = 16
	podiumArea.ClipsDescendants = true
	podiumArea.Parent = column
	corner(podiumArea, 0.05)
	local podiumEdge = stroke(podiumArea, theme.Rim, 1.5)
	podiumEdge.Transparency = 0.7

	-- Themed light pooling on the podium floor.
	-- The supplied halo ring, laid on the floor under all three pedestals: blue
	-- for Stardust, pink for Attacks, gold for Time Played. It is decoration
	-- only, so if the id never loads nothing is missing but the ring.
	if theme.Halo and UIAssets[theme.Halo] then
		local floorRing = Instance.new("ImageLabel")
		floorRing.Name = "FloorRing"
		floorRing.AnchorPoint = Vector2.new(0.5, 1)
		floorRing.Position = UDim2.new(0.5, 0, 1, 4)
		floorRing.Size = UDim2.fromOffset(330, 84)
		floorRing.BackgroundTransparency = 1
		floorRing.BorderSizePixel = 0
		floorRing.Active = false
		floorRing.Image = UIAssets[theme.Halo]
		floorRing.ImageTransparency = 0.25
		floorRing.ScaleType = Enum.ScaleType.Stretch
		floorRing.ZIndex = 21
		floorRing.Parent = podiumArea
	end

	-- A gentle spotlight from above and a pool of light on the floor. This is
	-- what pulls the eye up to the podium and away from the list.
	softGlow(podiumArea, {
		Name = "SpotLight", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, -0.06), Size = UDim2.new(1, -60, 0, 190),
		Color = theme.Aura, Transparency = 0.72, ZIndex = 17, Radius = 0.4,
	})
	softGlow(podiumArea, {
		Name = "StageLight", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1.02), Size = UDim2.new(1, -40, 0, 150),
		Color = theme.Aura, Transparency = 0.72, ZIndex = 17, Radius = 0.3,
	})

	-- Decoration only where nothing else lives. First place's avatar occupies
	-- x 142..194 / y 12..64 and the two lower plates fill the sides from y 48
	-- down, so the free space is the top strip and the outer edges at avatar
	-- height. Nothing here can land on a name, a number or a face.
	starField(podiumArea, {
		{ 0.06, 0.09, 3, theme.Spark, 0.3 }, { 0.94, 0.09, 3 },
		{ 0.30, 0.04, 2 }, { 0.70, 0.04, 2, theme.Spark, 0.35 },
		{ 0.15, 0.20, 2 }, { 0.86, 0.22, 2, theme.Spark, 0.4 },
		{ 0.50, 0.015, 2, theme.Spark, 0.45 },
	}, 18)

	makeSoftSparkle(podiumArea, 26, 60, 0.1, theme.Spark)
	makeSoftSparkle(podiumArea, 310, 60, 0.7, Color3.new(1, 1, 1))

	local podium = {
		[2] = makePodiumSlot(podiumArea, 2, -109, -10, 80, 86, theme.Rim),
		[1] = makePodiumSlot(podiumArea, 1, 0, -10, 104, 104, theme.Rim),
		[3] = makePodiumSlot(podiumArea, 3, 109, -10, 72, 86, theme.Rim),
	}

	-- The transition to the list: a light that fades out downwards instead of
	-- a hard black rule between two panels.
	do
		local seam = Instance.new("Frame")
		seam.Name = "Seam"
		seam.AnchorPoint = Vector2.new(0.5, 0)
		seam.Position = UDim2.new(0.5, 0, 0, 360)
		seam.Size = UDim2.new(1, -40, 0, 10)
		seam.BackgroundColor3 = theme.Rim
		seam.BackgroundTransparency = 0.45
		seam.BorderSizePixel = 0
		seam.ZIndex = 15
		seam.Parent = column
		corner(seam, 1)

		local seamFade = Instance.new("UIGradient")
		seamFade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		seamFade.Parent = seam
	end

	local listPanel = Instance.new("Frame")
	listPanel.Name = "ListPanel"
	listPanel.AnchorPoint = Vector2.new(0.5, 0)
	listPanel.Position = UDim2.new(0.5, 0, 0, 366)
	listPanel.Size = UDim2.new(1, -16, 1, -374)
	listPanel.BackgroundColor3 = Color3.new(1, 1, 1)
	listPanel.BackgroundTransparency = 0.12
	listPanel.BorderSizePixel = 0
	listPanel.ZIndex = 14
	listPanel.Parent = column
	corner(listPanel, 0.1)
	gradient(listPanel, Color3.fromRGB(20, 34, 96), Color3.fromRGB(11, 19, 62))

	do
		local panelEdge = stroke(listPanel, C.CardEdge, 2)
		panelEdge.Transparency = 0.15

		-- Inset shadow along the top edge: the list looks recessed into the
		-- card rather than laid on top of it.
		local inset = Instance.new("Frame")
		inset.Name = "InsetShade"
		inset.AnchorPoint = Vector2.new(0.5, 0)
		inset.Position = UDim2.new(0.5, 0, 0, 0)
		inset.Size = UDim2.new(1, -6, 0, 16)
		inset.BackgroundColor3 = C.Shadow
		inset.BackgroundTransparency = 0.6
		inset.BorderSizePixel = 0
		inset.ZIndex = 14
		inset.Parent = listPanel
		corner(inset, 0.5)

		local insetFade = Instance.new("UIGradient")
		insetFade.Rotation = 90
		insetFade.Transparency = NumberSequence.new(0.35, 1)
		insetFade.Parent = inset
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "RowsScroll"
	scroll.Position = UDim2.fromOffset(0, 370)
	scroll.Size = UDim2.new(1, 0, 1, -378)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = theme.Rim
	scroll.ScrollBarImageTransparency = 0.75
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ZIndex = 15
	scroll.Parent = column

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 7)
	-- 3 rows of 52 with 7 between them is 172 in a 192-tall area, so a fourth
	-- shows as a peek and the list reads as scrollable.
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 2)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = scroll

	local rows = {}

	for i = 1, ROWS_TO_BUILD do
		rows[i] = makeRow(scroll, i, theme.Bubble, theme.Aura)
	end

	columnObjects[key] = {
		Column = column,
		PodiumArea = podiumArea,
		Scroll = scroll,
		Rows = rows,
		Podium = podium,
	}
end

makeColumn("Stardust", "Top Stardust", 1)
makeColumn("Attacks", "Most Attacks", 2)
makeColumn("Time", "Time Played", 3)

-- ===== ANIMATION / HIGHLIGHT =====

local function applyYouHighlightToPodium(slot, isYou)
	if not slot then return end

	if isYou then
		slot.StandStroke.Color = COL.Yellow
		slot.StandStroke.Thickness = 4
		slot.ProfileStroke.Color = COL.Yellow
		slot.ProfileStroke.Thickness = 3

		TweenService:Create(slot.Scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1.05,
		}):Play()
	else
		slot.StandStroke.Color = slot.BaseStandColor or C.CardEdge
		slot.StandStroke.Thickness = 2
		slot.ProfileStroke.Color = slot.BaseProfileColor or C.CardEdge
		slot.ProfileStroke.Thickness = slot.BaseProfileThickness or 2

		TweenService:Create(slot.Scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end
end

local function applyYouHighlightToRow(row, isYou)
	if not row then return end

	if isYou then
		if row.Gradient then
			row.Gradient.Color = ColorSequence.new(
				Color3.fromRGB(62, 84, 162),
				Color3.fromRGB(32, 44, 104)
			)
		end
		row.Frame.BackgroundTransparency = 0.05
		row.RowStroke.Color = COL.Yellow
		row.RowStroke.Thickness = 3
		row.RowStroke.Transparency = 0
		row.ProfileStroke.Color = COL.Yellow
		row.ProfileStroke.Thickness = 3
		row.YouTag.Visible = true
		row.Name.Size = UDim2.fromOffset(row.NameNarrow, 24)
	else
		if row.Gradient then
			row.Gradient.Color = ColorSequence.new(row.BaseTop, row.BaseBottom)
		end
		row.RowStroke.Color = row.BaseStrokeColor
		row.RowStroke.Thickness = 1.5
		row.RowStroke.Transparency = 0.35
		row.ProfileStroke.Color = row.BaseProfileColor
		row.ProfileStroke.Thickness = 2
		row.YouTag.Visible = false
		row.Name.Size = UDim2.fromOffset(row.NameWide, 24)
	end
end

local PODIUM_Y, SCROLL_Y = 82, 252   -- changed by the phone layout below

local function playTabSwitchAnimation()
	for _, column in pairs(columnObjects) do
		column.PodiumArea.Position = UDim2.fromOffset(0, PODIUM_Y + 8)
		column.Scroll.Position = UDim2.fromOffset(0, SCROLL_Y + 8)

		TweenService:Create(column.PodiumArea, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, PODIUM_Y),
		}):Play()

		TweenService:Create(column.Scroll, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, SCROLL_Y),
		}):Play()

		for _, slot in pairs(column.Podium) do
			slot.Scale.Scale = 0.92

			TweenService:Create(slot.Scale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end

		for i, row in ipairs(column.Rows) do
			if row.Frame.Visible then
				row.Frame.Position = UDim2.fromOffset(0, 8)
				TweenService:Create(row.Frame, TweenInfo.new(0.16 + (i * 0.01), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.fromOffset(0, 0),
				}):Play()
			end
		end
	end
end

-- ===== DATA DISPLAY =====

local function setPodiumSlot(slot, info, formatter, rank)
	if info then
		slot.Holder.Visible = true

		local displayName = tostring(info.DisplayName or info.Name or "Player")
		slot.Name.Text = displayName
		slot.Value.Text = formatter(info.Value or 0)

		setProfileImage(slot.ProfileImage, slot.ProfileLetter, info.UserId, displayName)
		applyYouHighlightToPodium(slot, tonumber(info.UserId) == player.UserId)
	else
		slot.Holder.Visible = true
		slot.Name.Text = ""
		slot.Value.Text = "0"
		slot.ProfileImage.Image = ""
		slot.ProfileLetter.Text = tostring(rank)
		slot.ProfileLetter.Visible = true
		applyYouHighlightToPodium(slot, false)
	end
end

local function showLoading()
	for _, column in pairs(columnObjects) do
		for rank, slot in pairs(column.Podium) do
			slot.Name.Text = "Loading"
			slot.Value.Text = ""
			slot.ProfileImage.Image = ""
			slot.ProfileLetter.Text = tostring(rank)
			slot.ProfileLetter.Visible = true
			applyYouHighlightToPodium(slot, false)
		end

		for i, row in ipairs(column.Rows) do
			if i == 1 then
				row.Caption.Text = "Loading..."
				setRowMode(row, "caption")
			elseif i <= PLACEHOLDER_ROWS then
				row.Rank.Text = tostring(FIRST_SCROLL_RANK + i - 1)
				setRowMode(row, "empty")
			else
				row.Frame.Visible = false
			end
			applyYouHighlightToRow(row, false)
		end
	end
end

local function showError(message)
	for _, column in pairs(columnObjects) do
		for _, slot in pairs(column.Podium) do
			slot.Name.Text = "Error"
			slot.Value.Text = ""
			slot.ProfileImage.Image = ""
			slot.ProfileLetter.Text = "!"
			slot.ProfileLetter.Visible = true
			applyYouHighlightToPodium(slot, false)
		end

		for i, row in ipairs(column.Rows) do
			if i == 1 then
				row.Caption.Text = message or "Failed to load"
				setRowMode(row, "caption")
			else
				row.Frame.Visible = false
			end
			applyYouHighlightToRow(row, false)
		end
	end
end

local function setRows(columnKey, rowsData)
	local column = columnObjects[columnKey]
	if not column then return end

	local formatter = formatterFor(columnKey)

	setPodiumSlot(column.Podium[1], rowsData and rowsData[1], formatter, 1)
	setPodiumSlot(column.Podium[2], rowsData and rowsData[2], formatter, 2)
	setPodiumSlot(column.Podium[3], rowsData and rowsData[3], formatter, 3)

	-- An unfilled place shows the row's shape and nothing else. No banner and
	-- no dashes: showing both a "nobody here" line AND a column of empty rows
	-- said the same thing twice.
	for i, row in ipairs(column.Rows) do
		local actualRank = FIRST_SCROLL_RANK + i - 1
		local info = rowsData and rowsData[actualRank]

		if info then
			local rank = tonumber(info.Rank) or actualRank
			row.Rank.Text = tostring(rank)

			local displayName = tostring(info.DisplayName or info.Name or "Player")
			row.Name.Text = displayName
			row.Value.Text = formatter(info.Value or 0)

			row.RankBubble.BackgroundColor3 = if rank <= 3 then makeRankColor(rank) else (row.BubbleColor or COL.Cyan)

			setProfileImage(row.ProfileImage, row.ProfileLetter, info.UserId, displayName)
			setRowMode(row, "filled")
			applyYouHighlightToRow(row, tonumber(info.UserId) == player.UserId)
		elseif i <= PLACEHOLDER_ROWS then
			row.Rank.Text = tostring(actualRank)
			row.RankBubble.BackgroundColor3 = row.BubbleColor or COL.Cyan
			row.ProfileLetter.Visible = true
			setRowMode(row, "empty")
			applyYouHighlightToRow(row, false)
		else
			row.Frame.Visible = false
			applyYouHighlightToRow(row, false)
		end
	end

	column.Scroll.CanvasPosition = Vector2.new(0, 0)
end

refreshLeaderboard = function()
	requestToken += 1
	local token = requestToken

	showLoading()

	task.spawn(function()
		local ok, result = pcall(function()
			return getLeaderboard:InvokeServer(activeTab)
		end)

		if token ~= requestToken then
			return
		end

		if not ok or type(result) ~= "table" or result.ok ~= true then
			warn("[LeaderboardsClient] Failed to get leaderboard:", result)
			showError("Failed to load")
			return
		end

		local data = result.Data or {}

		setRows("Stardust", data.Stardust or {})
		setRows("Attacks", data.Attacks or {})
		setRows("Time", data.Time or {})

		playTabSwitchAnimation()
	end)
end

setTabVisual(activeTab, true)
showLoading()

-- ===== RESPONSIVE LAYOUT =====
-- Desktop/tablet: the three columns side by side, scaled to fit.
-- Phones: one column at a time with a switcher, so names and numbers stay readable.
local COLUMN_KEYS = { "Stardust", "Attacks", "Time" }
local COLUMN_LABELS = { Stardust = "Stardust", Attacks = "Attacks", Time = "Time" }
local selectedColumn = "Stardust"
local layoutCompact = nil

local switcher = Instance.new("Frame")
switcher.Name = "ColumnSwitcher"
-- Inside the interior with everything else, now that the window carries a
-- navy band. On a phone the header is 84 tall and the cards start at 133,
-- so this sits at 86 and clears both.
switcher.Position = UDim2.fromOffset(3, 86)
switcher.Size = UDim2.new(1, -6, 0, 46)
switcher.BackgroundTransparency = 1
switcher.Visible = false
switcher.ZIndex = 14
switcher.Parent = interior

local switcherLayout = Instance.new("UIListLayout")
switcherLayout.FillDirection = Enum.FillDirection.Horizontal
switcherLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
switcherLayout.VerticalAlignment = Enum.VerticalAlignment.Center
switcherLayout.Padding = UDim.new(0, 10)
switcherLayout.SortOrder = Enum.SortOrder.LayoutOrder
switcherLayout.Parent = switcher

local switchButtons = {}

local function refreshColumnVisibility()
	for key, object in pairs(columnObjects) do
		object.Column.Visible = not layoutCompact or key == selectedColumn
	end
	for key, button in pairs(switchButtons) do
		local active = key == selectedColumn
		button.BackgroundColor3 = if active then Color3.fromRGB(206, 242, 255) else Color3.fromRGB(20, 34, 92)
		button.TextColor3 = if active then C.Cream else Color3.fromRGB(176, 202, 240)
	end
end

for order, key in ipairs(COLUMN_KEYS) do
	local button = Instance.new("TextButton")
	button.Name = key .. "Switch"
	button.LayoutOrder = order
	button.Size = UDim2.new(1 / 3, -8, 1, 0)
	button.BackgroundColor3 = Color3.fromRGB(20, 34, 92)
	button.AutoButtonColor = false
	button.Font = FONT
	button.Text = COLUMN_LABELS[key]
	button.TextScaled = true
	button.TextColor3 = Color3.fromRGB(176, 202, 240)
	button.ZIndex = 15
	button.Parent = switcher
	corner(button, 0.25)
	stroke(button, C.CardEdge, 3)
	GuiStyle.TextStroke(button, 2)
	local cap = Instance.new("UITextSizeConstraint")
	cap.MinTextSize = 16
	cap.MaxTextSize = 26
	cap.Parent = button
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = button
	switchButtons[key] = button

	button.Activated:Connect(function()
		selectedColumn = key
		refreshColumnVisibility()
		playTabSwitchAnimation()
	end)
end

local titleLabel = header:FindFirstChild("Title")

local function applyLayout()
	local compact = UiResponsive ~= nil and UiResponsive.Layout() == "compact"
	local scale, width, height = nil, POPUP_W, POPUP_H

	if UiResponsive then
		if compact then
			scale, width, height = UiResponsive.FitPanel(640, POPUP_H, { minWidth = 520, minHeight = 400, margin = 12 })
		else
			scale = UiResponsive.FitScale(POPUP_W, POPUP_H, { margin = 16 })
		end
	else
		local vp = CAMERA.ViewportSize
		if vp.X < 1 or vp.Y < 1 then return end
		scale = math.clamp(math.min(vp.X / DESIGN.X, vp.Y / DESIGN.Y), 0.46, 1)
	end

	rootScale.Scale = scale
	popup.Size = UDim2.fromOffset(width, height)
	frameDecor.sync()

	if compact == layoutCompact then return end
	layoutCompact = compact

	header.Size = UDim2.new(1, 0, 0, if compact then 84 else 112)
	if titleLabel then
		titleLabel.Size = if compact then UDim2.fromOffset(150, 60) else UDim2.fromOffset(245, 82)
	end
	tabsFrame.AnchorPoint = if compact then Vector2.new(0, 0.5) else Vector2.new(0.5, 0.5)
	tabsFrame.Position = if compact then UDim2.new(0, 170, 0.5, 0) else UDim2.new(0.61, 0, 0.5, 0)
	tabsFrame.Size = if compact then UDim2.fromOffset(400, 64) else UDim2.fromOffset(720, 78)
	tabLayout.Padding = UDim.new(0, if compact then 8 else 18)
	for name, data in pairs(tabButtons) do
		data.Holder.Size = if compact
			then UDim2.fromOffset(128, 54)
			else UDim2.fromOffset(if name == "All Time" then 244 else 214, 70)
		if data.Icon then
			-- The drawn calendar does not come back once the artwork has
			-- replaced it, so a compact/desktop switch cannot resurrect it.
			data.Icon.Visible = (not compact) and not tabIconArtReady[name]
			if data.IconImage then
				data.IconImage.Visible = not compact
			end
			data.Text.Position = if compact then UDim2.fromOffset(0, 0) else UDim2.fromOffset(54, 0)
			data.Text.Size = if compact then UDim2.fromScale(1, 1) else UDim2.new(1, -66, 1, 0)
		end
		local cap = data.Text:FindFirstChildOfClass("UITextSizeConstraint")
		if cap then
			cap.MinTextSize = if compact then 16 else 26
			cap.MaxTextSize = if compact then 30 else 44
		end
	end

	switcher.Visible = compact
	content.Position = UDim2.fromOffset(if compact then 4 else 15, if compact then 133 else 127)
	content.Size = if compact then UDim2.new(1, -8, 1, -132) else UDim2.new(1, -30, 1, -138)

	PODIUM_Y = if compact then 0 else 90
	SCROLL_Y = if compact then 280 else 370
	for _, object in pairs(columnObjects) do
		object.Column.Size = if compact then UDim2.fromScale(1, 1) else UDim2.new(0, 336, 1, 0)
		local titleBar = object.Column:FindFirstChild("TitleBar")
		if titleBar then titleBar.Visible = not compact end
		local seam = object.Column:FindFirstChild("Seam")
		if seam then seam.Position = UDim2.new(0.5, 0, 0, PODIUM_Y + 270) end
		local listPanel = object.Column:FindFirstChild("ListPanel")
		if listPanel then
			listPanel.Position = UDim2.new(0.5, 0, 0, SCROLL_Y - 4)
			listPanel.Size = UDim2.new(1, -16, 1, -(SCROLL_Y + 4))
		end
		object.PodiumArea.Position = UDim2.fromOffset(0, PODIUM_Y)
		object.Scroll.Position = UDim2.fromOffset(0, SCROLL_Y)
		object.Scroll.Size = UDim2.new(1, 0, 1, -(SCROLL_Y + 8))
	end

	refreshColumnVisibility()
end

applyLayout()
if UiResponsive then
	UiResponsive.Changed:Connect(applyLayout)
end

task.spawn(function()
	while true do
		task.wait(60)

		if GuiManager:GetCurrent() == "Leaderboards" then
			refreshLeaderboard()
		end
	end
end)

-- ===== OPEN BUTTON HOOK =====

local function buttonLooksLikeLeaderboards(button)
	if button.Name == "Leaderboards" or button.Name == "LeaderboardsButton" then
		return true
	end

	for _, child in ipairs(button:GetDescendants()) do
		if child:IsA("TextLabel") and string.lower(child.Text) == "leaderboards" then
			return true
		end
	end

	return false
end

local function findLeaderboardsButton(timeout)
	local start = os.clock()

	while os.clock() - start < timeout do
		local mainHud = playerGui:FindFirstChild("MainHUD")

		if mainHud then
			local sideMenu = mainHud:FindFirstChild("SideMenu", true)
			local slot = sideMenu and sideMenu:FindFirstChild("LeaderboardsSlot")
			local direct = slot and slot:FindFirstChild("Leaderboards")

			if direct and direct:IsA("GuiButton") then
				return direct
			end

			for _, item in ipairs(mainHud:GetDescendants()) do
				if item:IsA("GuiButton") and buttonLooksLikeLeaderboards(item) then
					return item
				end
			end
		end

		task.wait(0.1)
	end

	return nil
end

local leaderboardsButton = findLeaderboardsButton(15)

if not leaderboardsButton then
	warn("[LeaderboardsClient] Could not find MainHUD Leaderboards button.")
	return
end

leaderboardsButton.Activated:Connect(function()
	if GuiManager:GetCurrent() == "Leaderboards" then
		GuiManager:Close("Leaderboards")
	else
		GuiManager:Open("Leaderboards")
		refreshLeaderboard()
	end
end)

print("[LeaderboardsClient] Connected Leaderboards button:", leaderboardsButton:GetFullName())