-- TutorialClient (LocalScript in StarterPlayerScripts)
-- A friendly first-time tutorial hosted by Nibbles, a baby black hole.
-- Every step completes from something the player really does in the game.
--
--   * The screen dims slightly and a spotlight brightens what to look at: a HUD
--     button, your base or a black hole. World targets also glow and get a
--     golden trail from your character.
--   * Nibbles talks from a speech bubble at the bottom of the screen, moves up
--     while the carry card is showing, and shrinks to a small hint while a
--     popup (like UPGRADE) is open. Everything hides during the attack camera.
--   * Skippable at any time. Replay it from the Nibbles button, bottom-left.
--     Completion is saved by TutorialServer.
--
-- Presentation only: it reads attributes and remotes the game already has and
-- never changes gameplay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")

local GuiStyle = require(ReplicatedStorage:WaitForChild("GuiStyle"))
local NibblesMascot = require(ReplicatedStorage:WaitForChild("NibblesMascot"))
local UIAssets = require(ReplicatedStorage:WaitForChild("UIAssets"))

local function optionalModule(name)
	local module = ReplicatedStorage:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then return nil end
	local ok, result = pcall(require, module)
	return if ok and type(result) == "table" then result else nil
end

local UpgradeConfig = optionalModule("UpgradeConfig")
local GuiManager = optionalModule("GuiManager")
local Settings = optionalModule("ClientSettings")
local UiResponsive = optionalModule("UiResponsive")
local Format = optionalModule("NumberFormatter") or {
	Abbreviate = function(n) return tostring(math.floor(tonumber(n) or 0)) end,
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===================== STYLE =====================
local FONT = GuiStyle.FONT
local WHITE = Color3.new(1, 1, 1)
local NAVY = Color3.fromRGB(8, 12, 28)
local PANEL = Color3.fromRGB(16, 20, 46)
local PANEL_TOP = Color3.fromRGB(38, 44, 96)
local RIM = Color3.fromRGB(128, 100, 255)
local GOLD = Color3.fromRGB(255, 215, 90)
local SOFT = Color3.fromRGB(222, 230, 252)
local DIM = Color3.fromRGB(170, 184, 224)
local GREEN = Color3.fromRGB(86, 222, 110)
local PINK = Color3.fromRGB(255, 128, 196)
local CYAN = Color3.fromRGB(96, 214, 255)
local SHADE = Color3.fromRGB(4, 4, 16)
local FULL = UDim.new(1, 0)

local TAG = "BlackHole"
local MASCOT_NAME = "NIBBLES"
local CHIME_SOUND = "rbxassetid://129349771709668"   -- the HUD click, pitched up

local DIM_HUD = 0.55          -- shade transparency while pointing at the HUD
local DIM_WORLD = 0.68        -- lighter while you have to walk around
local MIN_STEP_SECONDS = 2.5  -- a step never completes faster than you can read it
local TYPE_SPEED = 45         -- characters per second (about 0.022 s each)
local BASE_GAP = 18           -- dialog distance from the bottom of the screen

local TEXT = {
	Regular = { Title = 30, Body = 20, Hint = 18, Button = 22, Small = 16,
		PanelTitle = 50, PanelBody = 27, PanelHint = 21, PanelButton = 30, PanelSmall = 20 },
	Compact = { Title = 34, Body = 24, Hint = 22, Button = 26, Small = 20,
		PanelTitle = 54, PanelBody = 31, PanelHint = 24, PanelButton = 34, PanelSmall = 24 },
}

local PRAISE = { "Nice one!", "Awesome!", "You got it!", "Stellar!", "Nailed it!" }

-- ===================== SCREEN =====================
local old = playerGui:FindFirstChild("TutorialHUD")
if old then old:Destroy() end
local oldPointer = workspace:FindFirstChild("TutorialPointer")
if oldPointer then oldPointer:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "TutorialHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 45
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- Full screen and invisible. Its AbsolutePosition converts any other object's
-- AbsolutePosition into this ScreenGui's coordinates (it absorbs the top bar
-- inset), so the spotlight lines up exactly with MainHUD buttons.
local origin = Instance.new("Frame")
origin.Name = "Origin"
origin.Size = UDim2.fromScale(1, 1)
origin.BackgroundTransparency = 1
origin.Parent = gui

local function toGui(absolute)
	return absolute - origin.AbsolutePosition
end

local function reduceMotion()
	return Settings ~= nil and Settings.Get ~= nil and Settings.Get("ReduceMotion") == true
end

-- ===================== HELPERS =====================
local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, contextual)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

local function padding(parent, top, bottom, left, right)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, top)
	p.PaddingBottom = UDim.new(0, bottom)
	p.PaddingLeft = UDim.new(0, left)
	p.PaddingRight = UDim.new(0, right)
	p.Parent = parent
	return p
end

local function circle(parent, name, color, size, position, zIndex)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = zIndex
	f.Parent = parent
	corner(f, FULL)
	return f
end

-- Text sizes follow the screen: phones get a larger set because the whole
-- dialog is scaled down there.
local compact = false
local texts = {}   -- [TextLabel | TextButton] = size kind

local function sizeFor(kind)
	return (if compact then TEXT.Compact else TEXT.Regular)[kind] or TEXT.Regular.Small
end

-- kind: "Title" | "Body" | "Hint" | "Button" | "Small"
-- Without props.Size the text wraps and grows downwards.
local function text(parent, kind, props)
	local label = Instance.new(if props.Button then "TextButton" else "TextLabel")
	label.Name = props.Name or kind
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = FONT
	label.Text = props.Text or ""
	label.TextColor3 = props.Color or WHITE
	label.TextWrapped = true
	label.TextXAlignment = props.AlignX or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.LayoutOrder = props.Order or 0
	label.ZIndex = props.ZIndex or 1
	if props.Button then
		label.AutoButtonColor = false
	end
	if props.Size then
		label.Size = props.Size
	else
		label.Size = UDim2.new(1, 0, 0, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
	end
	if props.Position then label.Position = props.Position end
	if props.AnchorPoint then label.AnchorPoint = props.AnchorPoint end
	texts[label] = kind
	label.TextSize = sizeFor(kind)
	if props.Stroke then
		stroke(label, NAVY, props.Stroke, true)
	end
	label.Parent = parent
	return label
end

-- ===================== NIBBLES =====================
-- Nibbles is image-driven now (ReplicatedStorage.NibblesMascot): emotions,
-- talking mouths, blinking and idle motion from the uploaded pictures.
local function buildMascot(parent, size, z)
	return NibblesMascot.new(parent, size, z)
end

local function animateMascot(m, now, talking, calm)
	m:Update(now, talking, calm)
end

-- ===================== DIM + SPOTLIGHT =====================
-- Four shades around a rectangular hole. The hole sits over the highlighted
-- thing, so it stays at full brightness while everything else dims.
-- The shades are not Active, so every click still reaches the game.
local dim = Instance.new("Frame")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundTransparency = 1
dim.Visible = false
dim.ZIndex = 1
dim.Parent = gui

local shades = {}
for _, name in ipairs({ "Top", "Bottom", "Left", "Right" }) do
	local shade = Instance.new("Frame")
	shade.Name = name
	shade.BackgroundColor3 = SHADE
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.Parent = dim
	shades[name] = shade
end

-- The ring and arrow sit in their own ScreenGui above the carry card (80), so
-- they still show when the highlighted button is on that card.
local oldPointerGui = playerGui:FindFirstChild("TutorialPointerHUD")
if oldPointerGui then oldPointerGui:Destroy() end

local pointerGui = Instance.new("ScreenGui")
pointerGui.Name = "TutorialPointerHUD"
pointerGui.ResetOnSpawn = false
pointerGui.IgnoreGuiInset = true
pointerGui.DisplayOrder = 90
pointerGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pointerGui.Parent = playerGui

local ring = Instance.new("Frame")
ring.Name = "Spotlight"
ring.BackgroundTransparency = 1
ring.Visible = false
ring.ZIndex = 2
ring.Parent = pointerGui
corner(ring, UDim.new(0, 18))
local ringStroke = stroke(ring, GOLD, 3)

local halo = Instance.new("Frame")
halo.Name = "Halo"
halo.AnchorPoint = Vector2.new(0.5, 0.5)
halo.Position = UDim2.fromScale(0.5, 0.5)
halo.Size = UDim2.new(1, 14, 1, 14)
halo.BackgroundTransparency = 1
halo.ZIndex = 2
halo.Parent = ring
corner(halo, UDim.new(0, 24))
local haloStroke = stroke(halo, GOLD, 6)

local arrow = text(pointerGui, "Title", {
	Name = "Pointer", Text = "▼", Color = GOLD, AlignX = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(44, 44), Stroke = 3, ZIndex = 5,
})
arrow.TextScaled = true
arrow.Visible = false

-- ===================== DIALOG =====================
-- The dialog is the illustrated galaxy panel with Nibbles overlapping its
-- left edge. The panel picture carries its own border, glow and corners, so
-- nothing here redraws them. Layout is in design pixels at 1600x900 and the
-- whole dialog is scaled to the screen (refreshLayout), so proportions never
-- change.
local P = {}   -- the panel's measurements (design px at 1600x900) and assets
-- Asset ids and art geometry live in UIAssets.TutorialArt.
P.Assets = UIAssets.TutorialArt
P.Art = UIAssets.TutorialArt.Geometry
if UIAssets.EnsureGroup then task.spawn(UIAssets.EnsureGroup, "Tutorial") end

-- P.W / P.H are the VISIBLE panel (its border), not the whole picture: the
-- picture's transparent margin hangs outside (UIAssets geometry).
P.W = 960
P.H = math.floor(P.W / P.Art.Panel.Aspect + 0.5)
P.MascotSize = 320                          -- big, but clear of the writing
P.MascotX = math.floor(P.W * 0.03)          -- Nibbles' centre, just inside the left edge
P.Overhang = P.MascotSize / 2 - P.MascotX   -- how far Nibbles reaches past the panel
P.ContentLeft = math.floor(P.W * 0.28)      -- the text column starts clear of Nibbles
P.ContentRight = math.floor(P.W * 0.065)
P.ContentW = P.W - P.ContentLeft - P.ContentRight
P.PadTop = math.floor(P.H * 0.085)
P.PadBottom = math.floor(P.H * 0.085)
P.BadgeH = math.floor(P.H * 0.14)
P.ButtonH = math.floor(P.H * 0.24)
P.SkipH = math.floor(P.H * 0.16)           -- Skip tutorial button height
P.SkipStepH = math.floor(P.H * 0.19)       -- Skip step button height (smaller than LET'S GO)
P.SuccessH = math.floor(P.H * 0.3)         -- success badge picture height
P.BannerH = math.floor(P.H * 0.36)         -- objective banner height (width follows its shape)
P.BodyLineHeight = 1.15
P.BodyMin = 16
P.Dot, P.DotActive, P.DotGap = 14, 34, 10
P.TotalW = P.W + P.Overhang
P.Scale = 0.7                               -- overall size on computers and tablets (1 = full)
local dialogWidth = P.TotalW

-- Places an ImageLabel so the art rectangle inside its picture fills the parent.
function P.FitArt(label, rect)
	local w, h = rect[3] - rect[1], rect[4] - rect[2]
	label.AnchorPoint = Vector2.zero
	label.Size = UDim2.fromScale(1 / w, 1 / h)
	label.Position = UDim2.fromScale(-rect[1] / w, -rect[2] / h)
	label.ScaleType = Enum.ScaleType.Fit
	label.BackgroundTransparency = 1
end

function P.ArtImage(parent, name, image, rect, z)
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.Image = image
	label.ZIndex = z or 1
	P.FitArt(label, rect)
	label.Parent = parent
	return label
end

local dialog = Instance.new("Frame")
dialog.Name = "Dialog"
dialog.AnchorPoint = Vector2.new(0.5, 1)
dialog.Position = UDim2.new(0.5, 0, 1, 600)
dialog.Size = UDim2.fromOffset(dialogWidth, P.H)
dialog.BackgroundTransparency = 1
dialog.Visible = false
dialog.ZIndex = 10
dialog.Parent = gui

local dialogScale = Instance.new("UIScale")
dialogScale.Parent = dialog

-- The panel itself.
local bubble = Instance.new("Frame")
bubble.Name = "Bubble"
bubble.Position = UDim2.fromOffset(P.Overhang, 0)
bubble.Size = UDim2.fromOffset(P.W, P.H)
bubble.BackgroundTransparency = 1
bubble.Active = true   -- clicks on the panel never reach the world
bubble.ZIndex = 11
bubble.Parent = dialog
local bubblePop = Instance.new("UIScale")
bubblePop.Parent = bubble
P.PanelArt = P.ArtImage(bubble, "Galaxy", P.Assets.GalaxyBackground, P.Art.Panel.Rect, 1)
-- A very light tint on the whole picture calms the galaxy a touch without
-- adding any edges of its own.
P.PanelArt.ImageColor3 = Color3.fromRGB(226, 229, 246)

-- Nibbles, overlapping the left edge (drawn above the panel).
local mascot = buildMascot(dialog, P.MascotSize, 12)
mascot.holder.AnchorPoint = Vector2.new(0.5, 0.5)
mascot.holder.Position = UDim2.fromOffset(P.Overhang + P.MascotX, math.floor(P.H * 0.5))

-- NIBBLES badge, top-left of the text column.
do
	local nameTag = Instance.new("Frame")
	nameTag.Name = "NameTag"
	nameTag.BackgroundTransparency = 1
	nameTag.Position = UDim2.fromOffset(P.ContentLeft, P.PadTop)
	nameTag.Size = UDim2.fromOffset(math.floor(P.BadgeH * P.Art.Badge.Aspect + 0.5), P.BadgeH)
	nameTag.ZIndex = 3
	nameTag.Parent = bubble
	P.ArtImage(nameTag, "Art", P.Assets.NibblesBadge, P.Art.Badge.Rect, 3)
end

-- Progress, top-right: gold pill for this step, soft lavender for the rest.
local dotsHolder = Instance.new("Frame")
dotsHolder.Name = "Progress"
dotsHolder.AnchorPoint = Vector2.new(1, 0.5)
dotsHolder.Position = UDim2.fromOffset(P.W - P.ContentRight, P.PadTop + P.BadgeH / 2)
dotsHolder.Size = UDim2.fromOffset(100, P.Dot)
dotsHolder.BackgroundTransparency = 1
dotsHolder.ZIndex = 3
dotsHolder.Parent = bubble

do
	local dotsList = Instance.new("UIListLayout")
	dotsList.FillDirection = Enum.FillDirection.Horizontal
	dotsList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	dotsList.VerticalAlignment = Enum.VerticalAlignment.Center
	dotsList.SortOrder = Enum.SortOrder.LayoutOrder
	dotsList.Padding = UDim.new(0, P.DotGap)
	dotsList.Parent = dotsHolder
end

-- Heading and dialogue. `copy` slides them in on every new line.
P.Copy = Instance.new("Frame")
P.Copy.Name = "Copy"
P.Copy.BackgroundTransparency = 1
P.Copy.Size = UDim2.fromOffset(P.W, P.H)
P.Copy.ZIndex = 3
P.Copy.Parent = bubble

-- A navy copy 3 px below the heading gives it the reference's depth.
P.TitleShadow = text(P.Copy, "PanelTitle", { Name = "TitleShadow", Color = NAVY, Size = UDim2.fromOffset(P.ContentW, 50), Stroke = 4, ZIndex = 2 })
P.TitleShadow.TextYAlignment = Enum.TextYAlignment.Top
P.TitleShadow.TextWrapped = false
P.TitleShadow.TextTransparency = 0.3
local title = text(P.Copy, "PanelTitle", { Size = UDim2.fromOffset(P.ContentW, 50), Stroke = 4, ZIndex = 3 })
title:GetPropertyChangedSignal("Text"):Connect(function() P.TitleShadow.Text = title.Text end)
title.TextYAlignment = Enum.TextYAlignment.Top
title.TextWrapped = false
title.TextTruncate = Enum.TextTruncate.AtEnd
do
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(WHITE, Color3.fromRGB(214, 222, 255))
	g.Parent = title
end
P.TitleStroke = title:FindFirstChildOfClass("UIStroke")
local body = text(P.Copy, "PanelBody", { Color = Color3.fromRGB(238, 241, 255), Size = UDim2.fromOffset(P.ContentW, 24), Stroke = 2, ZIndex = 3 })
body.TextYAlignment = Enum.TextYAlignment.Top
body.LineHeight = P.BodyLineHeight

-- Goal row: what to do right now, or the "Nice one!" when a step is done.
local goal = Instance.new("Frame")
goal.Name = "Goal"
goal.BackgroundColor3 = GOLD
goal.BackgroundTransparency = 0.86
goal.BorderSizePixel = 0
goal.Visible = false
goal.ZIndex = 3
goal.AnchorPoint = Vector2.new(0, 0.5)
corner(goal, UDim.new(0, 10))
local goalStroke = stroke(goal, GOLD, 1.5)
goalStroke.Transparency = 0.5
local goalLabel = text(goal, "PanelHint", { Color = GOLD, Stroke = 1.5, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 1, -8), ZIndex = 4 })
goalLabel.TextScaled = true   -- always fits between Skip tutorial and the button
do
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = sizeFor("PanelHint")
	limit.MinTextSize = 12
	limit.Parent = goalLabel
end

-- Buttons: Skip tutorial bottom-left of the text column, the big button
-- bottom-right.
local actions = Instance.new("Frame")
actions.Name = "Actions"
actions.BackgroundTransparency = 1
actions.Position = UDim2.fromOffset(P.ContentLeft, P.H - P.PadBottom - P.ButtonH)
actions.Size = UDim2.fromOffset(P.ContentW, P.ButtonH)
actions.ZIndex = 3
actions.Parent = bubble
goal.Parent = actions

function P.Tween(object, seconds, props, style, direction)
	local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- Hover 1 -> 1.04, press 1 -> 0.94 -> 1.03 -> 1 (about 0.2 s).
function P.Pressable(button, scale, onHover)
	local pressToken = 0
	button.MouseEnter:Connect(function()
		P.Tween(scale, 0.12, { Scale = 1.04 })
		if onHover then onHover(true) end
	end)
	button.MouseLeave:Connect(function()
		P.Tween(scale, 0.12, { Scale = 1 })
		if onHover then onHover(false) end
	end)
	button.Activated:Connect(function()
		if reduceMotion() then return end
		pressToken += 1
		local token = pressToken
		P.Tween(scale, 0.05, { Scale = 0.94 })
		task.delay(0.05, function()
			if token ~= pressToken then return end
			P.Tween(scale, 0.08, { Scale = 1.03 })
			task.delay(0.08, function()
				if token ~= pressToken then return end
				P.Tween(scale, 0.07, { Scale = 1 })
			end)
		end)
	end)
end

-- Skip tutorial: the lettering picture, with a hit area a bit larger than it.
local skipAllButton = Instance.new("TextButton")
skipAllButton.Name = "SkipTutorial"
skipAllButton.Text = ""
skipAllButton.AutoButtonColor = false
skipAllButton.BackgroundTransparency = 1
skipAllButton.AnchorPoint = Vector2.new(0, 0.5)
skipAllButton.Position = UDim2.new(0, 0, 0.5, math.floor(P.ButtonH * 0.06))
skipAllButton.Size = UDim2.fromOffset(math.floor(P.SkipH * P.Art.Skip.Aspect + 0.5), P.SkipH)
skipAllButton.ZIndex = 4
skipAllButton.Parent = actions
do
	local skipArtHolder = Instance.new("Frame")
	skipArtHolder.Name = "ArtHolder"
	skipArtHolder.BackgroundTransparency = 1
	skipArtHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	skipArtHolder.Position = UDim2.fromScale(0.5, 0.5)
	skipArtHolder.Size = UDim2.fromOffset(math.floor(P.SkipH * P.Art.Skip.Aspect + 0.5), P.SkipH)
	skipArtHolder.ZIndex = 4
	skipArtHolder.Parent = skipAllButton
	local skipArt = P.ArtImage(skipArtHolder, "Art", P.Assets.SkipTutorial, P.Art.Skip.Rect, 4)
	local SKIP_REST = Color3.fromRGB(232, 236, 255)   -- a touch quieter than LET'S GO
	skipArt.ImageColor3 = SKIP_REST
	local skipScale = Instance.new("UIScale")
	skipScale.Parent = skipArtHolder
	P.Pressable(skipAllButton, skipScale, function(on)
		P.Tween(skipArt, 0.12, { ImageColor3 = if on then WHITE else SKIP_REST })
	end)
end

-- The main button. It stays a TextButton so the tutorial can keep setting
-- its Text; the label is drawn by the art ("LET'S GO!") or by a matching
-- glossy green pill for the other labels (GOT IT!, AWESOME!, ...), since the
-- LET'S GO picture has its words baked in.
local primaryButton = Instance.new("TextButton")
primaryButton.Name = "Continue"
primaryButton.Text = "LET'S GO!"
primaryButton.TextTransparency = 1
primaryButton.AutoButtonColor = false
primaryButton.BackgroundTransparency = 1
primaryButton.AnchorPoint = Vector2.new(1, 0.5)
primaryButton.Position = UDim2.fromScale(1, 0.5)
primaryButton.Size = UDim2.fromOffset(math.floor(P.ButtonH * P.Art.LetsGo.Aspect + 0.5), P.ButtonH)
primaryButton.ZIndex = 4
primaryButton.Parent = actions
do
	local primaryVisual = Instance.new("Frame")
	primaryVisual.Name = "Visual"
	primaryVisual.BackgroundTransparency = 1
	primaryVisual.Size = UDim2.fromScale(1, 1)
	primaryVisual.ZIndex = 4
	primaryVisual.Parent = primaryButton
	local primaryScale = Instance.new("UIScale")
	primaryScale.Parent = primaryVisual
	local letsGoArt = P.ArtImage(primaryVisual, "Art", P.Assets.LetsGoButton, P.Art.LetsGo.Rect, 5)
	local ART_REST = Color3.fromRGB(242, 242, 242)
	letsGoArt.ImageColor3 = ART_REST

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = WHITE
	pill.ZIndex = 5
	pill.Visible = false
	pill.Parent = primaryVisual
	corner(pill, FULL)
	stroke(pill, Color3.fromRGB(14, 96, 30), 4)
	do
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(104, 240, 96), Color3.fromRGB(40, 196, 64))
		g.Parent = pill
		local gloss = Instance.new("Frame")
		gloss.Name = "Gloss"
		gloss.AnchorPoint = Vector2.new(0.5, 0)
		gloss.Position = UDim2.fromScale(0.5, 0.1)
		gloss.Size = UDim2.fromScale(0.8, 0.22)
		gloss.BackgroundColor3 = WHITE
		gloss.BackgroundTransparency = 0.7
		gloss.ZIndex = 6
		gloss.Parent = pill
		corner(gloss, FULL)
	end
	local pillLabel = text(pill, "PanelButton", {
		Name = "Label", AlignX = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Stroke = 3, ZIndex = 7,
	})
	pillLabel.TextWrapped = false

	function P.RefreshPrimaryVisual()
		local usesArt = primaryButton.Text == "LET'S GO!"
		letsGoArt.Visible = usesArt
		pill.Visible = not usesArt
		pillLabel.Text = primaryButton.Text
	end
	P.Pill = pill
	primaryButton:GetPropertyChangedSignal("Text"):Connect(P.RefreshPrimaryVisual)
	P.Pressable(primaryButton, primaryScale, function(on)
		P.Tween(letsGoArt, 0.12, { ImageColor3 = if on then WHITE else ART_REST })
	end)
end

-- "Skip step": shown instead of the main button on steps you finish by
-- playing. Quieter than the main button.
local skipStepButton = Instance.new("TextButton")
skipStepButton.Name = "SkipStep"
skipStepButton.Text = ""
skipStepButton.AutoButtonColor = false
skipStepButton.BackgroundTransparency = 1
skipStepButton.AnchorPoint = Vector2.new(1, 0.5)
skipStepButton.Position = UDim2.new(1, 0, 0.5, 0)
skipStepButton.Size = UDim2.fromOffset(math.floor(P.SkipStepH * P.Art.SkipStep.Aspect + 0.5), P.SkipStepH)
skipStepButton.ZIndex = 4
skipStepButton.Parent = actions
do
	local holder = Instance.new("Frame")
	holder.Name = "ArtHolder"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 4
	holder.Parent = skipStepButton
	local art = P.ArtImage(holder, "Art", P.Assets.SkipStep, P.Art.SkipStep.Rect, 4)
	local REST = Color3.fromRGB(236, 238, 252)
	art.ImageColor3 = REST
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	P.Pressable(skipStepButton, scale, function(on)
		P.Tween(art, 0.12, { ImageColor3 = if on then WHITE else REST })
	end)
end

-- Success badge, bottom centre: one of the four pictures (never the same
-- twice in a row), popped in when a step is completed, then gone.
P.Success = Instance.new("Frame")
P.Success.Name = "SuccessFeedback"
P.Success.AnchorPoint = Vector2.new(0.5, 0.5)
P.Success.BackgroundTransparency = 1
P.Success.Size = UDim2.fromOffset(math.floor(P.SuccessH * P.Art.Success.Aspect + 0.5), P.SuccessH)
P.Success.ZIndex = 6
P.Success.Visible = false
P.Success.Parent = actions
P.SuccessScale = Instance.new("UIScale")
P.SuccessScale.Parent = P.Success
P.SuccessArt = P.ArtImage(P.Success, "Art", P.Assets.Success[1], P.Art.Success.Rect, 6)
P.SuccessToken, P.LastSuccess = 0, 0

-- image / geometry / hold are optional: by default one of the four praise
-- pictures (never the same twice in a row).
function P.ShowSuccess(image, geometry, hold)
	geometry = geometry or P.Art.Success
	if not image then
		local count = #P.Assets.Success
		local pick = math.random(count)
		if count > 1 and pick == P.LastSuccess then pick = pick % count + 1 end
		P.LastSuccess = pick
		image = P.Assets.Success[pick]
	end
	P.SuccessArt.Image = image
	P.FitArt(P.SuccessArt, geometry.Rect)

	-- Centred in the free space between the bottom-left and bottom-right
	-- buttons, and never wider than that space.
	local left = if skipAllButton.Visible then skipAllButton.Size.X.Offset + 10 else 0
	local right = if primaryButton.Visible then primaryButton.Size.X.Offset + 10
		elseif skipStepButton.Visible then skipStepButton.Size.X.Offset + 10 else 0
	local room = P.ContentW - left - right
	local height = math.min(P.SuccessH, room / geometry.Aspect)
	P.Success.Size = UDim2.fromOffset(math.floor(height * geometry.Aspect + 0.5), math.floor(height + 0.5))
	P.Success.Position = UDim2.new(0, left + room / 2, 0.5, 0)
	P.Success.Visible = true
	P.SuccessToken += 1
	local token = P.SuccessToken
	if reduceMotion() then
		P.SuccessScale.Scale, P.Success.Rotation, P.SuccessArt.ImageTransparency = 1, 0, 0
	else
		P.SuccessScale.Scale, P.Success.Rotation, P.SuccessArt.ImageTransparency = 0.55, -4, 1
		P.Tween(P.SuccessScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		P.Tween(P.SuccessArt, 0.16, { ImageTransparency = 0 })
		P.Tween(P.Success, 0.14, { Rotation = 2 })
		task.delay(0.14, function()
			if token == P.SuccessToken then P.Tween(P.Success, 0.14, { Rotation = 0 }) end
		end)
		-- A few quick sparkles flying out, then gone.
		for i = 1, 4 do
			local spark = Instance.new("TextLabel")
			spark.Name = "Sparkle"
			spark.AnchorPoint = Vector2.new(0.5, 0.5)
			spark.BackgroundTransparency = 1
			spark.Text = "✦"
			spark.Font = FONT
			spark.TextScaled = true
			spark.TextColor3 = if i % 2 == 0 then GOLD else WHITE
			spark.Size = UDim2.fromOffset(16, 16)
			spark.Position = UDim2.fromScale(0.5, 0.5)
			spark.ZIndex = 7
			spark.Parent = P.Success
			local angle = (i - 1) * math.pi / 2 + math.pi / 4 + (math.random() - 0.5) * 0.6
			P.Tween(spark, 0.35, {
				Position = UDim2.new(0.5, math.cos(angle) * P.Success.Size.X.Offset * 0.55, 0.5, math.sin(angle) * P.SuccessH * 0.7),
				TextTransparency = 1, Rotation = 90,
			})
			task.delay(0.4, function() spark:Destroy() end)
		end
	end
	task.delay(0.3 + (hold or 0.75), function()
		if token ~= P.SuccessToken then return end
		if reduceMotion() then P.Success.Visible = false return end
		P.Tween(P.SuccessScale, 0.18, { Scale = 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		P.Tween(P.SuccessArt, 0.18, { ImageTransparency = 1 })
		task.delay(0.18, function()
			if token == P.SuccessToken then P.Success.Visible = false end
		end)
	end)
end

-- ===== OBJECTIVE BANNERS =====
-- The illustrated banner for a hint, if there is one. Matched on the start of
-- the hint, so "Carry it into the glowing tier 7" uses the (tier-free) Merge
-- banner for every tier.
P.BannerHints = {
	{ "Watch your Stardust climb", "WatchStardust" },
	{ "Walk into the glowing black hole", "WalkIntoBlackHole" },
	{ "Pick up a black hole first", "PickUpBlackHole" },
	{ "Carry it into the glowing tier", "MergeBlackHoles" },
	{ "Press ATTACK, then click a target", "AttackTarget" },
	{ "You can afford one now", "CanAffordUpgrade" },
	{ "Press LOCK BASE", "LockBase" },
}
function P.BannerFor(hint)
	if type(hint) ~= "string" then return nil end
	for _, pair in ipairs(P.BannerHints) do
		if string.sub(hint, 1, #pair[1]) == pair[1] and (pair[2] ~= "LockBase" or hint == pair[1]) then
			return P.Assets.Objectives[pair[2]] and pair[2] or nil
		end
	end
	return nil
end

-- The banner takes the place of the heading and dialogue once Nibbles has
-- finished saying the line, in the middle of the text column.
P.Banner = Instance.new("Frame")
P.Banner.Name = "ObjectiveBanner"
P.Banner.AnchorPoint = Vector2.new(0.5, 0.5)
P.Banner.BackgroundTransparency = 1
P.Banner.ZIndex = 4
P.Banner.Visible = false
P.Banner.Parent = bubble
do
	local top = P.PadTop + P.BadgeH + math.floor(P.H * 0.03)
	local bottom = P.H - P.PadBottom - P.ButtonH - 6
	local height = math.min(P.BannerH, bottom - top)
	local width = math.min(height * P.Art.Objective.Aspect, P.ContentW)
	height = width / P.Art.Objective.Aspect
	P.Banner.Size = UDim2.fromOffset(math.floor(width + 0.5), math.floor(height + 0.5))
	P.BannerHome = UDim2.fromOffset(P.ContentLeft + P.ContentW / 2, (top + bottom) / 2)
	P.Banner.Position = P.BannerHome
end
P.BannerScale = Instance.new("UIScale")
P.BannerScale.Parent = P.Banner
P.BannerArt = P.ArtImage(P.Banner, "Art", "", P.Art.Objective.Rect, 4)
P.BannerKey, P.BannerShown, P.BannerToken, P.TypedAt = nil, nil, 0, 0

local function copyParts()
	return { title, P.TitleShadow, body }
end
-- Heading + dialogue fade out (banner mode) or back in.
function P.SetCopyShown(shown, instant)
	for _, label in ipairs(copyParts()) do
		local rest = if label == P.TitleShadow then 0.3 else 0
		local goal = if shown then rest else 1
		local edge = label:FindFirstChildOfClass("UIStroke")
		if instant or reduceMotion() then
			label.TextTransparency = goal
			if edge then edge.Transparency = if shown then 0 else 1 end
		else
			P.Tween(label, 0.15, { TextTransparency = goal })
			if edge then P.Tween(edge, 0.15, { Transparency = if shown then 0 else 1 }) end
		end
	end
end

-- Shows `key`'s banner (nil hides it). A change slides the old one out to
-- the left and the new one in from the right.
function P.ShowBanner(key)
	if key == P.BannerShown then return end
	local previous = P.BannerShown
	P.BannerShown = key
	P.BannerToken += 1
	local token = P.BannerToken
	local calm = reduceMotion()
	local function bringIn()
		if token ~= P.BannerToken then return end
		if not key then
			P.Banner.Visible = false
			return
		end
		P.BannerArt.Image = P.Assets.Objectives[key]
		P.Banner.Visible = true
		if calm then
			P.Banner.Position, P.BannerScale.Scale, P.BannerArt.ImageTransparency = P.BannerHome, 1, 0
			return
		end
		P.Banner.Position = P.BannerHome + UDim2.fromOffset(12, 0)
		P.BannerScale.Scale = 0.94
		P.BannerArt.ImageTransparency = 1
		P.Tween(P.Banner, 0.16, { Position = P.BannerHome })
		P.Tween(P.BannerArt, 0.14, { ImageTransparency = 0 })
		P.Tween(P.BannerScale, 0.14, { Scale = 1.02 })
		task.delay(0.14, function()
			if token == P.BannerToken then P.Tween(P.BannerScale, 0.1, { Scale = 1 }) end
		end)
	end
	if previous and P.Banner.Visible and not calm then
		P.Tween(P.Banner, 0.1, { Position = P.BannerHome - UDim2.fromOffset(12, 0) })
		P.Tween(P.BannerScale, 0.1, { Scale = 0.96 })
		P.Tween(P.BannerArt, 0.1, { ImageTransparency = 1 })
		task.delay(0.1, bringIn)
	else
		bringIn()
	end
end

-- Every frame while the tutorial runs: the banner appears once the line has
-- been read (typing done + a moment), and the heading/dialogue step aside.
function P.UpdateBanner(now, isTyping, isCompleting)
	local want = P.BannerKey
	if want and (isTyping or now - P.TypedAt < 1.2) then want = nil end
	if want == nil and P.BannerShown and isCompleting then return end   -- keep it while the success pops
	if want ~= P.BannerShown then
		P.SetCopyShown(want == nil)
		P.ShowBanner(want)
	end
end

-- New step: no banner, heading and dialogue back.
function P.ResetBanner()
	P.BannerKey = nil
	P.ShowBanner(nil)
	P.SetCopyShown(true, true)
end

function P.HideSuccess()
	P.SuccessToken += 1
	P.Success.Visible = false
end

local function measure(value, kind, width)
	return TextService:GetTextSize(value, sizeFor(kind), FONT, Vector2.new(width, 10000))
end

-- Positions the text from measured heights. The panel keeps its size, so a
-- long line gets a slightly smaller body size instead of spilling out.
-- Called when text, the goal row or the screen changes; never every frame.
local function layoutBubble()
	P.RefreshPrimaryVisual()
	if P.Pill.Visible then
		local wanted = math.ceil(measure(primaryButton.Text, "PanelButton", 1000).X) + 70
		primaryButton.Size = UDim2.fromOffset(math.max(wanted, math.floor(P.ButtonH * 2.4)), P.ButtonH)
	else
		primaryButton.Size = UDim2.fromOffset(math.floor(P.ButtonH * P.Art.LetsGo.Aspect + 0.5), P.ButtonH)
	end

	local y = P.PadTop + P.BadgeH + math.floor(P.H * 0.03)
	local titleHeight = sizeFor("PanelTitle") + 8
	title.Position = UDim2.fromOffset(P.ContentLeft, y)
	title.Size = UDim2.fromOffset(P.ContentW, titleHeight)
	P.TitleShadow.Position = UDim2.fromOffset(P.ContentLeft, y + 3)
	P.TitleShadow.Size = title.Size
	y += titleHeight + math.floor(P.H * 0.025)

	-- The dialogue fills the space down to the buttons; a long line gets a
	-- slightly smaller size instead of spilling out.
	local limit = P.H - P.PadBottom - P.ButtonH - 8
	local bodySize = sizeFor("PanelBody")
	local bodyHeight
	repeat
		local lines = TextService:GetTextSize(body.Text, bodySize, FONT, Vector2.new(P.ContentW, 10000)).Y
		bodyHeight = math.ceil(lines * P.BodyLineHeight) + 4
		if y + bodyHeight <= limit or bodySize <= P.BodyMin then break end
		bodySize -= 1
	until false
	body.TextSize = bodySize
	body.Position = UDim2.fromOffset(P.ContentLeft, y)
	body.Size = UDim2.fromOffset(P.ContentW, bodyHeight)

	-- The goal hint sits in the bottom row, between Skip tutorial and the
	-- button on the right.
	if goal.Visible then
		local left = if skipAllButton.Visible then skipAllButton.Size.X.Offset + 4 else 0
		local right = if primaryButton.Visible then primaryButton.Size.X.Offset
			elseif skipStepButton.Visible then skipStepButton.Size.X.Offset else 0
		goal.Position = UDim2.new(0, left, 0.5, 0)
		goal.Size = UDim2.fromOffset(math.max(P.ContentW - left - right - 16, 60), math.floor(P.ButtonH * 0.62))
	end

	local dotsWidth = math.max(#dotsHolder:GetChildren() - 2, 0) * (P.Dot + P.DotGap) + P.DotActive
	dotsHolder.Size = UDim2.fromOffset(dotsWidth, P.Dot)
end

-- A new line slides in: heading and dialogue come in from 8 px to the right
-- and fade up, without reopening the panel.
function P.SlideInCopy()
	if reduceMotion() then
		P.Copy.Position = UDim2.fromOffset(0, 0)
		title.TextTransparency = 0
		if P.TitleStroke then P.TitleStroke.Transparency = 0 end
		return
	end
	P.Copy.Position = UDim2.fromOffset(8, 0)
	title.TextTransparency = 1
	P.TitleShadow.TextTransparency = 1
	P.Tween(P.TitleShadow, 0.2, { TextTransparency = 0.3 })
	if P.TitleStroke then P.TitleStroke.Transparency = 1 end
	P.Tween(P.Copy, 0.2, { Position = UDim2.fromOffset(0, 0) })
	P.Tween(title, 0.2, { TextTransparency = 0 })
	if P.TitleStroke then P.Tween(P.TitleStroke, 0.2, { Transparency = 0 }) end
end

-- Opening: the panel pops 0.88 -> 1 (Back overshoot) and fades up; Nibbles
-- follows a beat later, 0.75 -> 1.
function P.OpenDialog()
	if reduceMotion() then
		bubblePop.Scale, mascot.pop.Scale, P.PanelArt.ImageTransparency = 1, 1, 0
		return
	end
	bubblePop.Scale = 0.88
	P.PanelArt.ImageTransparency = 0.35
	P.Tween(bubblePop, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	P.Tween(P.PanelArt, 0.25, { ImageTransparency = 0 })
	mascot.pop.Scale = 0.75
	task.delay(0.04, function()
		P.Tween(mascot.pop, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
end

-- ===================== MINI HINT =====================
-- While a popup is open the dialog steps aside and this small pill remains.
local MINI_HEIGHT = 60

local mini = Instance.new("Frame")
mini.Name = "MiniHint"
mini.AnchorPoint = Vector2.new(0.5, 1)
mini.Position = UDim2.new(0.5, 0, 1, -12)
mini.Size = UDim2.fromOffset(300, MINI_HEIGHT)
mini.BackgroundColor3 = PANEL
mini.BorderSizePixel = 0
mini.Visible = false
mini.ZIndex = 10
mini.Parent = gui
corner(mini, FULL)
stroke(mini, RIM, 3)
local miniScale = Instance.new("UIScale")
miniScale.Parent = mini

local miniMascot = buildMascot(mini, 56, 11)
miniMascot.holder.AnchorPoint = Vector2.new(0, 0.5)
miniMascot.holder.Position = UDim2.new(0, 4, 0.5, 0)
local miniLabel = text(mini, "Hint", {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 68, 0.5, 0),
	Size = UDim2.fromOffset(200, MINI_HEIGHT), Stroke = 1.5,
})
miniLabel.TextWrapped = false

local function setMiniText(value)
	if miniLabel.Text == value then return end
	miniLabel.Text = value
	local width = math.ceil(measure(value, "Hint", 2000).X) + 4
	miniLabel.Size = UDim2.fromOffset(width, MINI_HEIGHT)
	mini.Size = UDim2.fromOffset(68 + width + 24, MINI_HEIGHT)
end

-- ===================== REPLAY BUTTON =====================
local replayButton = Instance.new("TextButton")
replayButton.Name = "TutorialButton"
replayButton.AnchorPoint = Vector2.new(0, 1)
replayButton.Position = UDim2.new(0, 12, 1, -12)
replayButton.Size = UDim2.fromOffset(72, 72)
replayButton.BackgroundTransparency = 1
replayButton.AutoButtonColor = false
replayButton.Text = ""
replayButton.Visible = false
replayButton.ZIndex = 20
replayButton.Parent = gui
local replayScale = Instance.new("UIScale")
replayScale.Parent = replayButton

local replayMascot = buildMascot(replayButton, 72, 21)

local badge = text(replayButton, "Small", {
	Name = "Badge", Text = "?", Color = NAVY, AlignX = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 2, 0, 0), Size = UDim2.fromOffset(26, 26), ZIndex = 30,
})
badge.TextScaled = true
badge.BackgroundColor3 = GOLD
badge.BackgroundTransparency = 0
corner(badge, FULL)
stroke(badge, NAVY, 2)

replayButton.MouseEnter:Connect(function()
	TweenService:Create(replayMascot.pop, GuiStyle.HOVER_IN, { Scale = 1.12 }):Play()
end)
replayButton.MouseLeave:Connect(function()
	TweenService:Create(replayMascot.pop, GuiStyle.HOVER_OUT, { Scale = 1 }):Play()
end)

-- ===================== RESPONSIVE =====================
local function refreshLayout()
	local screen = origin.AbsoluteSize
	if screen.X < 2 or screen.Y < 2 then return end

	local isCompact = screen.Y < 520
	if isCompact ~= compact then
		compact = isCompact
		for label, kind in pairs(texts) do
			label.TextSize = sizeFor(kind)
		end
		local current = miniLabel.Text
		miniLabel.Text = ""
		setMiniText(current)
	end

	dialogWidth = P.TotalW
	dialog.Size = UDim2.fromOffset(dialogWidth, P.H)
	layoutBubble()

	local boost = math.clamp(math.min(screen.X / 1920, screen.Y / 1080), 1, 1.6)
	local scale = math.clamp(math.min(screen.X / 1280, screen.Y / 720), 0.6, 1) * boost
	-- The dialog is designed at 1600x900: about half the screen wide anywhere.
	-- (P.Scale shrinks it on computers and tablets; phones keep the full
	-- size so the words stay readable.)
	local size = if compact then 1 else P.Scale
	local panelScale = math.clamp(math.min(screen.X / 1600, screen.Y / 900) * size, 0.45, 1.35)
	dialogScale.Scale = math.min(panelScale, (screen.X - 24) / dialogWidth, (screen.Y * (if compact then 0.36 else 0.3)) / P.H)
	miniScale.Scale = math.min(scale, (screen.X - 24) / math.max(mini.Size.X.Offset, 1))
	replayScale.Scale = scale

	local placed = false
	if UiResponsive and UiResponsive.Layout() == "compact" then
		local hud = playerGui:FindFirstChild("MainHUD")
		local menu = hud and hud:FindFirstChild("SideMenu")
		if menu and menu.AbsoluteSize.Y > 0 then
			local topLeft = toGui(menu.AbsolutePosition)
			replayButton.AnchorPoint = Vector2.new(0, 0)
			replayButton.Position = UDim2.fromOffset(topLeft.X, topLeft.Y + menu.AbsoluteSize.Y + 10)
			placed = true
		end
	end
	if not placed then
		local safeOffset = if UiResponsive then UiResponsive.SafeRect() else Vector2.zero
		replayButton.AnchorPoint = Vector2.new(0, 1)
		replayButton.Position = UDim2.new(0, safeOffset.X + 12, 1, -12)
	end
end
origin:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshLayout)
if UiResponsive then
	UiResponsive.Changed:Connect(refreshLayout)
end
task.delay(3, refreshLayout)   -- MainHUD's side menu may finish laying out after us
refreshLayout()

-- ===================== WORLD POINTER =====================
local pointerFolder = Instance.new("Folder")
pointerFolder.Name = "TutorialPointer"
pointerFolder.Parent = workspace

local targetPart = Instance.new("Part")
targetPart.Name = "TutorialTarget"
targetPart.Anchored = true
targetPart.CanCollide = false
targetPart.CanQuery = false
targetPart.CanTouch = false
targetPart.Transparency = 1
targetPart.Size = Vector3.one * 0.2
targetPart.Parent = pointerFolder

local targetAttachment = Instance.new("Attachment")
targetAttachment.Parent = targetPart

local beam = Instance.new("Beam")
beam.Attachment1 = targetAttachment
beam.Color = ColorSequence.new(GOLD)
beam.LightEmission = 0.6
beam.LightInfluence = 0
beam.FaceCamera = true
beam.Width0 = 0.5
beam.Width1 = 0.5
beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
beam.TextureMode = Enum.TextureMode.Static
beam.TextureLength = 2
beam.TextureSpeed = 1.5
beam.Transparency = NumberSequence.new(0.25)
beam.Enabled = false
beam.Parent = pointerFolder

-- Makes the black hole or base glow through everything while it's the focus.
local highlight = Instance.new("Highlight")
highlight.Name = "TutorialHighlight"
highlight.FillColor = GOLD
highlight.FillTransparency = 0.75
highlight.OutlineColor = Color3.fromRGB(255, 244, 200)
highlight.OutlineTransparency = 0
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Enabled = false
highlight.Parent = pointerFolder

local characterAttachment = nil
local beamWanted = false
local highlightWanted = false

local function pointAt(position)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not position or not root then
		beamWanted = false
		return
	end
	if not characterAttachment or characterAttachment.Parent ~= root then
		if characterAttachment then characterAttachment:Destroy() end
		characterAttachment = Instance.new("Attachment")
		characterAttachment.Name = "TutorialBeamStart"
		characterAttachment.Parent = root
	end
	beam.Attachment0 = characterAttachment
	targetPart.CFrame = CFrame.new(position)
	beamWanted = true
end

player.CharacterAdded:Connect(function()
	characterAttachment = nil
end)

-- ===================== GAME LOOKUPS =====================
local cachedPlate, plateCheckedAt = nil, -math.huge

local function ownsPlate(plate)
	return plate ~= nil and plate.Parent ~= nil
		and tonumber(plate:GetAttribute("OwnerUserId")) == player.UserId
end

-- Plates are named plate1..plate8 (PlateAssignment). Looked up at most every
-- two seconds and reused while it is still ours.
local function myPlate()
	if ownsPlate(cachedPlate) then return cachedPlate end
	if os.clock() - plateCheckedAt < 2 then return nil end
	plateCheckedAt = os.clock()
	cachedPlate = nil
	for i = 1, 8 do
		local plate = workspace:FindFirstChild("plate" .. i, true)
		if plate and (plate:IsA("BasePart") or plate:IsA("Model")) and ownsPlate(plate) then
			cachedPlate = plate
			break
		end
	end
	return cachedPlate
end

local function boundsOf(instance)
	if instance:IsA("BasePart") then
		return instance.Position, instance.Size
	end
	local cframe, size = instance:GetBoundingBox()
	return cframe.Position, size
end

local function myHoles()
	local holes = {}
	for _, hole in ipairs(CollectionService:GetTagged(TAG)) do
		if hole:IsA("BasePart") and hole:IsDescendantOf(workspace)
			and tonumber(hole:GetAttribute("OwnerUserId")) == player.UserId then
			table.insert(holes, hole)
		end
	end
	return holes
end

local function rootPosition()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

local function nearest(holes, predicate)
	local from = rootPosition()
	if not from then return nil end
	local best, bestDistance = nil, math.huge
	for _, hole in ipairs(holes) do
		if not predicate or predicate(hole) then
			local distance = (hole.Position - from).Magnitude
			if distance < bestDistance then
				best, bestDistance = hole, distance
			end
		end
	end
	return best
end

local function heldHole()
	for _, hole in ipairs(myHoles()) do
		if hole:GetAttribute("HeldBy") == player.UserId then return hole end
	end
	return nil
end

-- BlackHoleVisualClient hides the real part and draws a model on top of it,
-- so the glow goes on that model.
local visualCache = setmetatable({}, { __mode = "k" })

local function visualFor(hole)
	local cached = visualCache[hole]
	if cached and os.clock() - cached.at < 1 and (cached.model == nil or cached.model.Parent ~= nil) then
		return cached.model, cached.extents
	end
	local best, bestDistance = nil, 3 + math.max(hole.Size.X, hole.Size.Y, hole.Size.Z)
	local folder = workspace:FindFirstChild("CompleteBlackHoleVisuals")
	if folder then
		for _, model in ipairs(folder:GetChildren()) do
			if model:IsA("Model") then
				local distance = (model:GetPivot().Position - hole.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = model, distance
				end
			end
		end
	end
	local extents = if best then best:GetExtentsSize() else hole.Size
	visualCache[hole] = { model = best, extents = extents, at = os.clock() }
	return best, extents
end

local function holeFocus(hole)
	local visual, extents = visualFor(hole)
	return {
		world = if visual then visual:GetPivot().Position else hole.Position,
		radius = math.max(extents.X, extents.Y, extents.Z) * 0.5,
		adornee = visual or hole,
	}
end

local function hudObject(...)
	local node = playerGui:FindFirstChild("MainHUD")
	for _, name in ipairs({ ... }) do
		if not node then return nil end
		node = node:FindFirstChild(name)
	end
	return node
end

local function upgradeLevels()
	local total = 0
	if UpgradeConfig and UpgradeConfig.Items then
		for _, item in ipairs(UpgradeConfig.Items) do
			total += tonumber(player:GetAttribute(item.LevelAttribute)) or 0
		end
	end
	return total
end

local function cheapestUpgrade()
	if not (UpgradeConfig and UpgradeConfig.Items and UpgradeConfig.GetPrice) then return nil end
	local best
	for _, item in ipairs(UpgradeConfig.Items) do
		local price = UpgradeConfig.GetPrice(item.Id, player:GetAttribute(item.LevelAttribute) or 0)
		if price and (not best or price < best.price) then
			best = { price = price, title = item.Title }
		end
	end
	return best
end

local mergeCount = 0
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("BlackHoleRemotes", 60)
	local merge = folder and folder:WaitForChild("MergeVFX", 30)
	if merge and merge:IsA("RemoteEvent") then
		merge.OnClientEvent:Connect(function()
			mergeCount += 1
		end)
	end
end)

-- Attacks you launch (BaseAttackServer tells every client, with the attacker).
local attackCount = 0
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("BaseAttackRemotes", 60)
	local started = folder and folder:WaitForChild("BaseAttackStarted", 30)
	if started and started:IsA("RemoteEvent") then
		started.OnClientEvent:Connect(function(plan)
			if type(plan) == "table" and plan.attackerUserId == player.UserId then
				attackCount += 1
			end
		end)
	end
end)

local function inAttackView()
	local camera = workspace.CurrentCamera
	return camera ~= nil and camera.CameraType == Enum.CameraType.Scriptable
end

local function readyToAttack(hole)
	return (tonumber(hole:GetAttribute("AttackCooldownUntil")) or 0) <= os.time()
end

local function clockText(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Is there anything to attack right now? Otherwise, when the island opens.
local function attackTargets()
	local islandOpensIn = nil
	for _, model in ipairs(CollectionService:GetTagged("WorldAttackTarget")) do
		if model:IsA("Model") and model:GetAttribute("WT_Id") then
			local open = (model:GetAttribute("WT_EventState") or "Open") == "Open"
			local alive = (model:GetAttribute("WT_State") or "Alive") == "Alive"
			if open and alive then
				return true, nil
			end
			local nextAt = tonumber(model:GetAttribute("WT_NextEventAt")) or 0
			if nextAt > os.time() then
				islandOpensIn = nextAt - os.time()
			end
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			return true, nil
		end
	end
	return false, islandOpensIn
end

local function carryObject(...)
	local node = playerGui:FindFirstChild("BlackHoleActionUI")
	node = node and node:FindFirstChild("CarryCard", true)
	for _, name in ipairs({ ... }) do
		if not node then return nil end
		node = node:FindFirstChild(name)
	end
	return node
end

-- ===================== STEPS =====================
-- title / body: what Nibbles says.
-- emotion: Nibbles' face for the line (Neutral, Playful, Blushing, Amazed,
--   Shocked, Upset, Angry, EyesClosed). Leave it out for Neutral.
-- button: a step you finish by pressing it (otherwise it finishes by itself).
-- update(state) -> done, goal text, focus. focus is { gui = GuiObject } or
--   { world = Vector3, radius = studs, adornee = Instance }.
-- popupHint: the small hint shown while a popup is open.
local steps = {
	{
		title = "Hi, I'm Nibbles!",
		emotion = "Playful",
		body = "I'm a baby black hole, and I'm going to help you build a cosmic empire. Ready?",
		button = "LET'S GO!",
	},
	{
		title = "This is your base",
		body = "Follow the golden trail to your plate. Everything you build lives right here!",
		update = function()
			local plate = myPlate()
			local from = rootPosition()
			if not plate or not from then
				return false, "Looking for your base…"
			end
			local center, size = boundsOf(plate)
			local flat = Vector3.new(from.X - center.X, 0, from.Z - center.Z).Magnitude
			local reach = math.max(size.X, size.Z) * 0.5 + 6
			local arrived = flat <= reach
			return arrived, if arrived then "You made it!" else "Walk onto your base", {
				world = center + Vector3.new(0, size.Y * 0.5 + 2, 0),
				radius = math.max(size.X, size.Z) * 0.5,
				adornee = plate,
			}
		end,
	},
	{
		title = "Black holes make Stardust",
		emotion = "Amazed",
		body = "Black holes pop up on your base all by themselves and earn Stardust every single second!",
		start = function(state)
			state.stardust = tonumber(player:GetAttribute("Stardust")) or 0
		end,
		update = function(state)
			local now = tonumber(player:GetAttribute("Stardust")) or 0
			local display = hudObject("StardustDisplay")
			-- The number can grow wider than its frame, so light up both.
			return now > state.stardust, "Watch your Stardust climb…", {
				gui = display,
				also = display and display:FindFirstChild("StardustRow"),
			}
		end,
	},
	{
		title = "Grab one!",
		body = "Walk right into one of your black holes to pick it up.",
		update = function()
			if heldHole() then
				return true, "Got it!"
			end
			local target = nearest(myHoles())
			if not target then
				return false, "Waiting for one to spawn…"
			end
			return false, "Walk into the glowing black hole", holeFocus(target)
		end,
	},
	{
		title = "Merge time!",
		emotion = "Playful",
		body = "Carry it into another black hole of the SAME tier. Two become one bigger hole that earns way more!",
		start = function(state)
			state.merges = mergeCount
		end,
		update = function(state)
			if mergeCount > state.merges then
				return true, "Merged!"
			end
			local held = heldHole()
			if not held then
				local target = nearest(myHoles())
				return false, "Pick up a black hole first", target and holeFocus(target)
			end
			local tier = held:GetAttribute("Tier")
			local match = nearest(myHoles(), function(hole)
				return hole ~= held and hole:GetAttribute("Tier") == tier
			end)
			if not match then
				return false, "Wait for another tier " .. tostring(tier) .. " to spawn"
			end
			return false, "Carry it into the glowing tier " .. tostring(tier), holeFocus(match)
		end,
	},
	{
		title = "Attack!",
		emotion = "Angry",
		body = "Pick up a black hole, press ATTACK, then click an enemy base or the central island. Launch it for a big Stardust reward!",
		start = function(state)
			state.attacks = attackCount
		end,
		update = function(state)
			if attackCount > state.attacks then
				-- Celebrate once the attack camera has handed control back.
				return not inAttackView(), "Boom! Direct hit!"
			end

			local canAttack, islandOpensIn = attackTargets()
			if not canAttack then
				-- Nobody to attack (e.g. alone in the server): let them move on.
				state.allowContinue = true
				if islandOpensIn then
					return false, "No targets yet. The island event opens in " .. clockText(islandOpensIn)
				end
				return false, "No targets right now. Come back when the island event opens!"
			end
			state.allowContinue = false

			local held = heldHole()
			if not held then
				local target = nearest(myHoles(), readyToAttack) or nearest(myHoles())
				return false, "Pick up a black hole first", target and holeFocus(target)
			end
			if not readyToAttack(held) then
				return false, "This one is still charging. Try another black hole!"
			end
			return false, "Press ATTACK, then click a target", { gui = carryObject("ActionPanel", "AttackSlot") }
		end,
	},
	{
		title = "Power up!",
		emotion = "Amazed",
		body = "Press UPGRADE and buy anything you can afford. Upgrades spawn stronger black holes, and more of them.",
		popupHint = "Buy any upgrade you can afford!",
		start = function(state)
			state.levels = upgradeLevels()
		end,
		update = function(state)
			if upgradeLevels() > state.levels then
				return true, "Upgraded!"
			end
			local cheapest = cheapestUpgrade()
			local stardust = tonumber(player:GetAttribute("Stardust")) or 0
			local hint = "You can afford one now!"
			if cheapest and stardust < cheapest.price then
				hint = ("%s costs ★%s. You have ★%s"):format(cheapest.title,
					Format.Abbreviate(cheapest.price), Format.Abbreviate(stardust))
			end
			return false, hint, { gui = hudObject("TopActionButtons", "UpgradeSlot", "UPGRADE") }
		end,
	},
	{
		title = "Protect your base",
		emotion = "Playful",
		body = "Other players can attack you too! Press LOCK BASE to keep your black holes safe for a while.",
		button = "GOT IT!",
		update = function()
			local lockButton = { gui = hudObject("TopActionButtons", "LockBaseSlot", "LOCK BASE") }
			local now = os.time()
			if (tonumber(player:GetAttribute("BaseLockedUntil")) or 0) > now then
				return true, "Your base is protected!", lockButton
			end
			if (tonumber(player:GetAttribute("LockBaseCooldownUntil")) or 0) > now then
				return false, "LOCK BASE is recharging. Use it whenever it's ready!", lockButton
			end
			return false, "Press LOCK BASE", lockButton
		end,
	},
	{
		title = "You're a natural!",
		emotion = "Blushing",
		body = "That's all you need. Tap me down in the corner any time to see this again. Now go grow HUGE!",
		button = "LET'S PLAY!",
		final = true,
		update = function()
			return false, nil, { gui = replayButton }
		end,
	},
}

-- ===================== ONE-OFF GUIDES =====================
-- Short guides that reuse everything above (dim, spotlight, arrow, bubble)
-- with their own steps. Each plays once; TutorialServer remembers it.
local mainSteps = steps
local activeGuide = nil          -- nil while the main tutorial (or nothing) runs
local guidesSeen = {}            -- [name] = true, from TutorialServer
local guideSeenRemote = nil

local function rebirthGui(name)
	local rebirthUi = playerGui:FindFirstChild("RebirthUI")
	return rebirthUi and rebirthUi:FindFirstChild(name, true)
end

local function setRebirthHighlight(target)
	local window = rebirthGui("RebirthWindow")
	if window then window:SetAttribute("GuideHighlight", target or "") end
end

local function rebirthWindowOpen()
	return GuiManager ~= nil and GuiManager:GetCurrent() == "Rebirth"
end

local function rebirthCount()
	return tonumber(player:GetAttribute(UpgradeConfig and UpgradeConfig.RebirthAttribute or "Rebirths")) or 0
end

-- The first time an upgrade is bought up to its rebirth cap.
-- context = { title, cap, nextCap } from MainHUD.
local function rebirthCapGuide(context)
	local sideButton = function() return hudObject("SideMenu", "RebirthSlot", "Rebirth") end
	-- Steps whose wording depends on live values rewrite their own body when
	-- they start (showStep runs start before it shows the body).
	local requirementStep, doneStep
	requirementStep = {
		title = "What it takes",
		body = "",
		allowPopup = "Rebirth",
		start = function()
			-- The requirements come from RebirthConfig and can change, so the
			-- wording points at the glowing list instead of naming them.
			if player:GetAttribute("CanRebirth") == true then
				requirementStep.body = "These are the rebirth requirements, and every one has a green check. You're ready!"
			else
				requirementStep.body = "These are the rebirth requirements. Anything without a green check still needs work. Keep growing!"
			end
			setRebirthHighlight("Requirements")
		end,
		leave = function()
			setRebirthHighlight("")
		end,
		update = function(state)
			if not rebirthWindowOpen() then
				state.allowContinue = false
				return false, "Open REBIRTH again", { gui = sideButton() }
			end
			local requirements = { gui = rebirthGui("Requirements") }
			if player:GetAttribute("CanRebirth") == true then
				return true, "You're ready!", requirements
			end
			-- Not there yet: nothing more to show today.
			state.allowContinue = true
			state.finishOnContinue = true
			return false, "Come back when every box is checked!", requirements
		end,
	}
	doneStep = {
		title = "Rebirth complete!",
		emotion = "Amazed",
		body = "",
		button = "AWESOME!",
		final = true,
		start = function()
			local count = rebirthCount()
			local cap = if UpgradeConfig and UpgradeConfig.GetLevelCap then UpgradeConfig.GetLevelCap("SpawnTier", count) else nil
			doneStep.body = if cap then ("Welcome to Rebirth %d! Upgrades start again from 0, but you earn more Stardust forever and Spawn Tier can now reach level %d!"):format(count + 1, cap)
				else ("Welcome to Rebirth %d! Keep growing!"):format(count + 1)
		end,
	}
	return {
		{
			title = "Level cap reached!",
			emotion = "Shocked",
			body = ("%s is maxed for this run (level %d). Rebirthing raises its cap to %d and makes you earn more Stardust forever! Let's take a look.")
				:format(context.title or "This upgrade", context.cap or 10, context.nextCap or 20),
			popupHint = "Close this menu, then press REBIRTH!",
			update = function()
				if rebirthWindowOpen() then
					return true, "That's the Rebirth window!"
				end
				return false, "Press REBIRTH", { gui = sideButton() }
			end,
		},
		requirementStep,
		{
			title = "Time to rebirth!",
			emotion = "Playful",
			body = "Hey! Click that glowing REBIRTH button! Press it twice to confirm. Upgrades restart at 0, but you keep Gems and the Index, and earn more Stardust forever!",
			allowPopup = "Rebirth",
			start = function(state)
				state.rebirths = rebirthCount()
				setRebirthHighlight("Button")
			end,
			leave = function()
				setRebirthHighlight("")
			end,
			update = function(state)
				if rebirthCount() > (state.rebirths or 0) then
					return true, "You rebirthed!"
				end
				if not rebirthWindowOpen() then
					return false, "Open REBIRTH again", { gui = sideButton() }
				end
				return false, "Click REBIRTH (twice to confirm)", { gui = rebirthGui("RebirthButton") }
			end,
		},
		doneStep,
	}
end

local dots = {}
for i = 1, #steps do
	local dot = Instance.new("Frame")
	dot.Name = "Dot" .. i
	dot.LayoutOrder = i
	dot.Size = UDim2.fromOffset(P.Dot, P.Dot)
	dot.BackgroundColor3 = DIM
	dot.BorderSizePixel = 0
	dot.Parent = dotsHolder
	corner(dot, FULL)
	dots[i] = dot
end

-- ===================== FEEDBACK =====================
local function chime(speeds)
	local volume = Settings and Settings.Get and tonumber(Settings.Get("SfxVolume"))
	if volume ~= nil and volume <= 0 then return end
	local group = SoundService:FindFirstChild("BH_SFX")
	for i, speed in ipairs(speeds) do
		task.delay((i - 1) * 0.09, function()
			local sound = Instance.new("Sound")
			sound.SoundId = CHIME_SOUND
			sound.Volume = 0.45
			sound.PlaybackSpeed = speed
			if group and group:IsA("SoundGroup") then
				sound.SoundGroup = group   -- follows the SFX volume slider
			end
			sound.Parent = SoundService
			sound:Play()
			Debris:AddItem(sound, 3)
		end)
	end
end

local function hop()
	if reduceMotion() then return end
	mascot.pop.Scale = 1.25
	TweenService:Create(mascot.pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local CONFETTI_COLORS = { GOLD, PINK, CYAN, GREEN, RIM }

local function confetti(object, count)
	if reduceMotion() or not object or object.AbsoluteSize.X < 1 then return end
	local from = toGui(object.AbsolutePosition) + Vector2.new(object.AbsoluteSize.X * 0.5, 10)
	for _ = 1, count do
		local piece = Instance.new("Frame")
		piece.Name = "Confetti"
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Size = UDim2.fromOffset(math.random(6, 10), math.random(10, 16))
		piece.Position = UDim2.fromOffset(from.X + math.random(-40, 40), from.Y)
		piece.Rotation = math.random(0, 360)
		piece.BackgroundColor3 = CONFETTI_COLORS[math.random(#CONFETTI_COLORS)]
		piece.BorderSizePixel = 0
		piece.ZIndex = 40
		piece.Parent = gui

		local peak = UDim2.fromOffset(from.X + math.random(-260, 260), from.Y - math.random(80, 220))
		TweenService:Create(piece, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = peak,
			Rotation = piece.Rotation + math.random(-180, 180),
		}):Play()
		task.delay(0.45, function()
			if not piece.Parent then return end
			TweenService:Create(piece, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = peak + UDim2.fromOffset(math.random(-30, 30), math.random(90, 160)),
				Rotation = piece.Rotation + math.random(-240, 240),
				BackgroundTransparency = 1,
			}):Play()
		end)
		Debris:AddItem(piece, 1.3)
	end
end

-- ===================== DIALOG CONTENT =====================
local typing, typed, totalGraphemes = false, 0, 0

local function finishTyping()
	if typing then P.TypedAt = os.clock() end
	typing = false
	body.MaxVisibleGraphemes = -1
end

local function setBody(value)
	body.Text = value
	totalGraphemes = utf8.len(value) or #value
	typed = 0
	typing = true
	body.MaxVisibleGraphemes = 0
	layoutBubble()
end

local function setHint(value, color)
	-- Hints with an illustrated banner show the banner instead of text.
	local bannerKey = if color == nil then P.BannerFor(value) else nil
	P.BannerKey = bannerKey
	if bannerKey then value = nil end
	local shown = type(value) == "string" and value ~= ""
	if goal.Visible ~= shown then
		goal.Visible = shown
		layoutBubble()
	end
	if not shown then return end

	local display = if color then value else "➜  " .. value
	color = color or GOLD
	if goalLabel.Text ~= display then
		goalLabel.Text = display
		layoutBubble()
	end
	if goalLabel.TextColor3 ~= color then
		goalLabel.TextColor3 = color
		goal.BackgroundColor3 = color
		goalStroke.Color = color
	end
end

-- ===================== RUNNER =====================
local running = false
local runToken = 0
local stepIndex = 0
local stepToken = 0
local stepState = {}
local stepStartedAt = 0
local completing = false
local focus = nil
local complete = nil   -- RemoteEvent, found once TutorialServer is up

local showStep, finish

local function refreshDots()
	for i, dot in ipairs(dots) do
		if i < stepIndex then
			dot.BackgroundColor3 = Color3.fromRGB(150, 140, 240)
			dot.BackgroundTransparency = 0.1
			dot.Size = UDim2.fromOffset(P.Dot, P.Dot)
		elseif i == stepIndex then
			dot.BackgroundColor3 = Color3.fromRGB(255, 206, 64)
			dot.BackgroundTransparency = 0
			dot.Size = UDim2.fromOffset(P.DotActive, P.Dot)
		else
			dot.BackgroundColor3 = Color3.fromRGB(96, 100, 190)
			dot.BackgroundTransparency = 0.35
			dot.Size = UDim2.fromOffset(P.Dot, P.Dot)
		end
	end
	dotsHolder.Size = UDim2.fromOffset((#dots - 1) * (P.Dot + P.DotGap) + P.DotActive, P.Dot)
end

local function refreshWorldPointers()
	if focus and focus.world then
		pointAt(focus.world)
		local adornee = focus.adornee
		highlightWanted = adornee ~= nil and adornee.Parent ~= nil
		if highlightWanted and highlight.Adornee ~= adornee then
			highlight.Adornee = adornee
		end
	else
		pointAt(nil)
		highlightWanted = false
	end
end

local function completeStep()
	completing = true
	local token = stepToken
	setHint(nil)
	skipStepButton.Visible = false   -- the step is done: nothing left to skip
	P.ShowSuccess()
	chime({ 1.3, 1.7 })
	mascot:React(if math.random() < 0.5 then "Amazed" else "Playful", 1.1)
	hop()
	confetti(bubble, 14)
	task.delay(1.1, function()
		if running and stepToken == token then
			showStep(stepIndex + 1)
		end
	end)
end

local function evaluate()
	local step = steps[stepIndex]
	if not step or completing then return end

	local done, newHint, newFocus = false, nil, nil
	if step.update then
		-- A respawn or a missing object just means "not done yet".
		local ok, a, b, c = pcall(step.update, stepState)
		if ok then
			done, newHint, newFocus = a, b, c
		end
	end
	focus = newFocus
	setHint(newHint)

	-- The main button shows for press-to-continue steps, and for steps that
	-- can't be done right now (like attacking with nobody around).
	local canContinue = step.button ~= nil or stepState.allowContinue == true
	if primaryButton.Visible ~= canContinue then
		primaryButton.Text = step.button or "GOT IT!"
		primaryButton.Visible = canContinue
		skipStepButton.Visible = not canContinue
		layoutBubble()
	end

	if done and os.clock() - stepStartedAt >= MIN_STEP_SECONDS then
		completeStep()
	end
end

showStep = function(index)
	local previous = steps[stepIndex]
	if previous and previous.leave then pcall(previous.leave, stepState) end

	stepToken += 1
	stepIndex = index
	local step = steps[index]
	if not step then
		finish(false)
		return
	end

	stepState = {}
	stepStartedAt = os.clock()
	completing = false
	focus = nil
	if step.start then pcall(step.start, stepState) end

	title.Text = step.title
	mascot:SetEmotion(step.emotion or "Neutral")
	setBody(step.body)
	setHint(nil)
	primaryButton.Text = step.button or "GOT IT!"
	primaryButton.Visible = step.button ~= nil
	skipStepButton.Visible = step.button == nil
	skipAllButton.Visible = not step.final
	replayButton.Visible = step.final == true
	refreshDots()
	layoutBubble()

	-- Gamepad: put selection on the button that moves the tutorial on.
	if UiResponsive and UiResponsive.IsGamepad() then
		GuiService.SelectedObject = if primaryButton.Visible then primaryButton else skipStepButton
	end

	P.ResetBanner()
	P.SlideInCopy()
	-- The last page celebrates: "You made it!" pops in the bottom row.
	if step.final and not activeGuide then
		local token = stepToken
		task.delay(0.35, function()
			if running and stepToken == token then
				P.ShowSuccess(P.Assets.YouMadeIt, P.Art.YouMadeIt, 1.1)
			end
		end)
	end

	evaluate()
	refreshWorldPointers()
end

-- ===================== RENDERING =====================
local holeRect = { x = 0, y = 0, w = 0, h = 0 }
local shadeAlpha = 1
local ringAlpha = 1
local dialogBottom = -600
local bottomGap = BASE_GAP
local renderConnection = nil
local carryCard = nil

local function lerp(a, b, k)
	return a + (b - a) * k
end

local function guiShown(object)
	if not object or not object.Parent then return false end
	if object.AbsoluteSize.X < 2 or object.AbsoluteSize.Y < 2 then return false end
	local node = object
	while node and not node:IsA("LayerCollector") do
		if node:IsA("GuiObject") and not node.Visible then return false end
		node = node.Parent
	end
	return node ~= nil and node.Enabled
end

local function worldRect(position, radius)
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local center = camera:WorldToViewportPoint(position)
	if center.Z <= 0 then return nil end
	local edge = camera:WorldToViewportPoint(position + camera.CFrame.RightVector * radius)
	local r = math.clamp(Vector2.new(edge.X - center.X, edge.Y - center.Y).Magnitude + 18, 48, 280)
	local screen = origin.AbsoluteSize
	if center.X < -r or center.X > screen.X + r or center.Y < -r or center.Y > screen.Y + r then
		return nil
	end
	return center.X - r, center.Y - r, r * 2, r * 2
end

local function setRect(frame, x, y, w, h)
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(math.max(w, 0), math.max(h, 0))
end

-- Keeps the dialog above the carry card while you're holding a black hole.
local function refreshBottomGap()
	local gap = BASE_GAP
	-- Phones: sit clearly above the bottom edge (home bar, thumbs), not on it.
	if compact then
		local safeBottom = 0
		if UiResponsive and UiResponsive.SafeRect then
			local position, size = UiResponsive.SafeRect()
			safeBottom = math.max(origin.AbsoluteSize.Y - (position.Y + size.Y), 0)
		end
		gap = math.max(gap, safeBottom + math.floor(origin.AbsoluteSize.Y * 0.06))
	end
	if not carryCard or not carryCard.Parent then
		local actionGui = playerGui:FindFirstChild("BlackHoleActionUI")
		carryCard = actionGui and actionGui:FindFirstChild("CarryCard", true)
	end
	if carryCard and guiShown(carryCard) then
		local top = toGui(carryCard.AbsolutePosition).Y
		gap = math.max(gap, origin.AbsoluteSize.Y - top + 12)
	end
	bottomGap = gap
end

local function render(dt)
	local now = os.clock()
	local calm = reduceMotion()
	local screen = origin.AbsoluteSize
	local camera = workspace.CurrentCamera
	local k = 1 - math.exp(-dt * 12)

	local attackView = camera ~= nil and camera.CameraType == Enum.CameraType.Scriptable
	local current = GuiManager ~= nil and GuiManager.GetCurrent ~= nil and GuiManager:GetCurrent() or nil
	local currentStep = steps[stepIndex]
	-- A guide step can keep talking over one popup (the Rebirth window).
	local popupOpen = current ~= nil and not (currentStep and currentStep.allowPopup == current)
	local showDialog = running and not attackView and not popupOpen
	local showMini = running and not attackView and popupOpen

	-- Spotlight target
	local tx, ty, tw, th
	local worldFocus = false
	if showDialog and focus then
		if focus.gui and guiShown(focus.gui) then
			local low = toGui(focus.gui.AbsolutePosition)
			local high = low + focus.gui.AbsoluteSize
			if focus.also and guiShown(focus.also) then
				local alsoLow = toGui(focus.also.AbsolutePosition)
				local alsoHigh = alsoLow + focus.also.AbsoluteSize
				low = Vector2.new(math.min(low.X, alsoLow.X), math.min(low.Y, alsoLow.Y))
				high = Vector2.new(math.max(high.X, alsoHigh.X), math.max(high.Y, alsoHigh.Y))
			end
			tx, ty, tw, th = low.X - 10, low.Y - 10, high.X - low.X + 20, high.Y - low.Y + 20
		elseif focus.world then
			worldFocus = true
			tx, ty, tw, th = worldRect(focus.world, focus.radius or 4)
		end
	end

	local hasHole = tx ~= nil
	if hasHole then
		if holeRect.w < 2 then
			-- Grow from the new target instead of sliding in from the old one.
			holeRect.x, holeRect.y = tx + tw * 0.5, ty + th * 0.5
		end
	else
		tx, ty, tw, th = holeRect.x + holeRect.w * 0.5, holeRect.y + holeRect.h * 0.5, 0, 0
	end
	holeRect.x = lerp(holeRect.x, tx, k)
	holeRect.y = lerp(holeRect.y, ty, k)
	holeRect.w = lerp(holeRect.w, tw, k)
	holeRect.h = lerp(holeRect.h, th, k)

	-- Shades
	local targetAlpha = 1
	if showDialog then
		targetAlpha = if worldFocus then DIM_WORLD else DIM_HUD
	end
	shadeAlpha = lerp(shadeAlpha, targetAlpha, 1 - math.exp(-dt * 6))
	dim.Visible = shadeAlpha < 0.99
	if dim.Visible then
		local x, y = math.floor(holeRect.x), math.floor(holeRect.y)
		local w, h = math.floor(holeRect.w), math.floor(holeRect.h)
		setRect(shades.Top, 0, 0, screen.X, y)
		setRect(shades.Bottom, 0, y + h, screen.X, screen.Y - y - h)
		setRect(shades.Left, 0, y, x, h)
		setRect(shades.Right, x + w, y, screen.X - x - w, h)
		for _, shade in pairs(shades) do
			shade.BackgroundTransparency = shadeAlpha
		end
	end

	-- Ring around the hole: a gentle breathing glow, never a flash.
	ringAlpha = lerp(ringAlpha, if showDialog and hasHole then 0.05 else 1, k)
	ring.Visible = ringAlpha < 0.98 and holeRect.w > 12
	if ring.Visible then
		local pulse = if calm then 0 else math.sin(now * 3.5) * 3
		ring.Position = UDim2.fromOffset(holeRect.x - 4 - pulse, holeRect.y - 4 - pulse)
		ring.Size = UDim2.fromOffset(holeRect.w + 8 + pulse * 2, holeRect.h + 8 + pulse * 2)
		ringStroke.Transparency = ringAlpha
		haloStroke.Transparency = 0.65 + ringAlpha * 0.35
	end

	-- Bouncing arrow
	arrow.Visible = ring.Visible and showDialog and hasHole
	if arrow.Visible then
		local bounce = if calm then 0 else math.abs(math.sin(now * 5)) * 10
		local centerX = holeRect.x + holeRect.w * 0.5
		local above = worldFocus or holeRect.y + holeRect.h + 60 > screen.Y
		if above and holeRect.y < 56 then above = false end
		if above then
			arrow.Text = "▼"
			arrow.AnchorPoint = Vector2.new(0.5, 1)
			arrow.Position = UDim2.fromOffset(centerX, holeRect.y - 6 - bounce)
		else
			arrow.Text = "▲"
			arrow.AnchorPoint = Vector2.new(0.5, 0)
			arrow.Position = UDim2.fromOffset(centerX, holeRect.y + holeRect.h + 6 + bounce)
		end
	end

	-- World glow and trail
	highlight.Enabled = showDialog and highlightWanted
	if highlight.Enabled and not calm then
		highlight.FillTransparency = 0.72 + 0.08 * math.sin(now * 3)
	end
	beam.Enabled = showDialog and beamWanted

	-- Dialog slides up into place, and away while hidden.
	dialogBottom = lerp(dialogBottom, if showDialog then bottomGap else -600, 1 - math.exp(-dt * 10))
	dialog.Position = UDim2.new(0.5, 0, 1, -math.floor(dialogBottom))
	dialog.Visible = dialogBottom > -560
	mini.Visible = showMini

	P.UpdateBanner(now, typing, completing)
	if typing then
		typed += dt * TYPE_SPEED
		if typed >= totalGraphemes then
			finishTyping()
		else
			body.MaxVisibleGraphemes = math.floor(typed)
		end
	end

	if dialog.Visible then
		-- Nibbles looks at whatever is highlighted.
		local look = Vector2.new(math.sin(now * 0.6) * 0.35, 0.1)
		if hasHole then
			local center = toGui(mascot.holder.AbsolutePosition) + mascot.holder.AbsoluteSize * 0.5
			local delta = Vector2.new(holeRect.x + holeRect.w * 0.5, holeRect.y + holeRect.h * 0.5) - center
			if delta.Magnitude > 1 then look = delta.Unit end
		end
		mascot.look = mascot.look:Lerp(look, k)
		animateMascot(mascot, now, typing, calm)
	end
	if mini.Visible then
		animateMascot(miniMascot, now, false, calm)
	end
end

local function stopRender()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

-- ===================== START / FINISH =====================
local function start()
	if running then return end
	running = true
	runToken += 1
	replayButton.Visible = false
	refreshLayout()
	refreshBottomGap()

	if not renderConnection then
		dialogBottom = -600
		shadeAlpha = 1
		ringAlpha = 1
		holeRect.x, holeRect.y = origin.AbsoluteSize.X * 0.5, origin.AbsoluteSize.Y * 0.5
		holeRect.w, holeRect.h = 0, 0
		renderConnection = RunService.RenderStepped:Connect(render)
	end
	dialog.Visible = true
	P.OpenDialog()
	showStep(1)
end

finish = function(skipped)
	if not running then return end
	running = false
	stepToken += 1

	local step = steps[stepIndex]
	if step and step.leave then pcall(step.leave, stepState) end
	focus = nil
	finishTyping()
	pointAt(nil)
	highlightWanted = false
	P.HideSuccess()
	P.ResetBanner()

	if not skipped then
		chime({ 1.2, 1.5, 1.9 })
		confetti(bubble, 30)
		hop()
	end
	if complete and not activeGuide then
		complete:FireServer(skipped == true)
	end
	if activeGuide then
		setRebirthHighlight("")
		activeGuide = nil
		steps = mainSteps
		dotsHolder.Visible = true
	end

	replayButton.Visible = true
	runToken += 1
	local token = runToken
	task.delay(0.8, function()
		if runToken ~= token then return end
		stopRender()
		dialog.Visible = false
		dim.Visible = false
		ring.Visible = false
		arrow.Visible = false
		mini.Visible = false
		highlight.Enabled = false
		highlight.Adornee = nil
		beam.Enabled = false
	end)
end

-- ===================== INPUT =====================
primaryButton.Activated:Connect(function()
	if not running then return end
	local step = steps[stepIndex]
	if step and (step.final or stepState.finishOnContinue) then
		finish(false)
	else
		chime({ 1.45 })
		showStep(stepIndex + 1)
	end
end)

skipStepButton.Activated:Connect(function()
	if running and not completing then
		showStep(stepIndex + 1)
	end
end)

skipAllButton.Activated:Connect(function()
	finish(true)
end)

replayButton.Activated:Connect(function()
	if not running then
		start()
	end
end)

-- Tap the bubble to show the whole line at once.
bubble.InputBegan:Connect(function(input)
	if typing and (input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch) then
		finishTyping()
	end
end)

-- ===================== LOOPS =====================
-- Step checks, the world trail and the carry card position: 10 times a second.
local tickClock = 0
RunService.Heartbeat:Connect(function(dt)
	if not running then return end
	tickClock += dt
	if tickClock < 0.1 then return end
	tickClock = 0

	evaluate()
	refreshWorldPointers()
	refreshBottomGap()

	local step = steps[stepIndex]
	local miniText = (step and step.popupHint) or "Close this menu to keep going!"
	setMiniText(miniText)
end)

-- The corner button idles gently (30 times a second, only while it's shown).
local idleClock = 0
RunService.Heartbeat:Connect(function(dt)
	if not replayButton.Visible then return end
	idleClock += dt
	if idleClock < 1 / 30 then return end
	idleClock = 0
	animateMascot(replayMascot, os.clock(), false, reduceMotion())
end)

-- ===================== START =====================
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("TutorialRemotes", 30)
	if not remotes then
		warn("[Tutorial] ReplicatedStorage.TutorialRemotes never appeared, so progress won't be saved."
			.. " TutorialServer must be a Script (not a LocalScript or ModuleScript) directly in ServerScriptService.")
		if not running then replayButton.Visible = true end
		return
	end

	local getState = remotes:WaitForChild("GetState", 10)
	complete = remotes:WaitForChild("Complete", 10)
	guideSeenRemote = remotes:WaitForChild("GuideSeen", 10)

	local ok, state = pcall(function()
		return getState and getState:InvokeServer()
	end)
	if ok and type(state) == "table" and type(state.guides) == "table" then
		for name, seen in pairs(state.guides) do
			if seen == true then guidesSeen[name] = true end
		end
	elseif not ok or type(state) ~= "table" then
		-- Can't tell what was seen: stay quiet rather than repeat a guide.
		guidesSeen.RebirthCap = true
	end
	if ok and type(state) == "table" and state.show then
		task.wait(2) -- let the HUD and base settle first
		if not running then start() end
	elseif not running then
		replayButton.Visible = true
	end
end)

-- ===================== REBIRTH CAP GUIDE =====================
-- MainHUD fires this when an upgrade can't go higher until the next rebirth.
-- The first time only (and never over the main tutorial), Nibbles walks the
-- player to the Rebirth window.
local function startGuide(name, guideSteps)
	if running or guidesSeen[name] or not guideSeenRemote then return end
	guidesSeen[name] = true
	guideSeenRemote:FireServer(name)
	-- The dialog only shows with no menu open, so close the Upgrade window.
	if GuiManager and GuiManager:GetCurrent() == "Upgrade" then
		GuiManager:Close("Upgrade")
	end
	activeGuide = name
	steps = guideSteps
	dotsHolder.Visible = false
	start()
end

task.spawn(function()
	local folder = ReplicatedStorage:FindFirstChild("ClientSignals")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ClientSignals"
		folder.Parent = ReplicatedStorage
	end
	local event = folder:FindFirstChild("RebirthCapGuide")
	if not event then
		event = Instance.new("BindableEvent")
		event.Name = "RebirthCapGuide"
		event.Parent = folder
	end
	event.Event:Connect(function(context)
		startGuide("RebirthCap", rebirthCapGuide(if type(context) == "table" then context else {}))
	end)
end)

-- ===================== STUDIO DEBUG =====================
-- Studio only: press Y to force the tutorial to start.
if RunService:IsStudio() then
	print("[Tutorial] Studio: press Y to start the tutorial.")
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Y and not running then
			start()
		end
	end)
end
