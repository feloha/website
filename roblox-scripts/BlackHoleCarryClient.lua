-- BlackHoleCarryClient (LocalScript in StarterPlayerScripts)
-- Walk-over pickup, carry card, drop, merge VFX and income popups.
-- The server carries black holes with attachments; the client never moves them.
-- ATTACK hands off to AttackTargetingClient through PlayerGui.ToggleAttackTargeting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SizeVariants = require(ReplicatedStorage:WaitForChild("SizeVariantConfig"))
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local TAG = "BlackHole"

-- Put your merge sound asset here.
-- If this stays as "rbxassetid://0", only the VFX will play.
local MERGE_SOUND_ID = "rbxassetid://121606800780436"
local MERGE_SOUND_PLAYBACK_SPEED = 1.4
local MERGE_SOUND_VOLUME = 0.3
local MERGE_SOUND_START_OFFSET = 0

local UI_SOUND_ID = "rbxassetid://7218169592"

local preloadedMergeSound = nil

local function preloadMergeSound()
	if MERGE_SOUND_ID == "" or MERGE_SOUND_ID == "rbxassetid://0" then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "PreloadedMergeSupernovaSound"
	sound.SoundId = MERGE_SOUND_ID
	sound.Volume = MERGE_SOUND_VOLUME
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 90
	sound.Parent = SoundService

	preloadedMergeSound = sound

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
	end)
end

preloadMergeSound()

local remotes = ReplicatedStorage:WaitForChild("BlackHoleRemotes")
local RequestPickup = remotes:WaitForChild("RequestPickup")
local RequestDrop = remotes:WaitForChild("RequestDrop")
local RequestAttack = remotes:WaitForChild("RequestAttack")

local MergeVFX = remotes:WaitForChild("MergeVFX")
local IncomeTick = remotes:WaitForChild("IncomeTick")
local WorldIncomePopup = remotes:WaitForChild("WorldIncomePopup")
local HeldChanged = remotes:WaitForChild("HeldChanged")


local GuiStyle = nil
pcall(function()
	GuiStyle = require(ReplicatedStorage:WaitForChild("GuiStyle"))
end)

local FONT = GuiStyle and GuiStyle.FONT or Enum.Font.FredokaOne

local COL = GuiStyle and GuiStyle.COL or {
	Light = Color3.fromRGB(255, 255, 255),
	Outline = Color3.fromRGB(24, 46, 90),
	Yellow = Color3.fromRGB(255, 225, 70),
	Cyan = Color3.fromRGB(85, 205, 255),
	Green = Color3.fromRGB(70, 220, 95),
	GreenDark = Color3.fromRGB(24, 165, 62),
	X = Color3.fromRGB(240, 72, 82),
	XBorder = Color3.fromRGB(255, 150, 155),
	Card = Color3.fromRGB(22, 28, 55),
	Card2 = Color3.fromRGB(30, 38, 78),
}

local BLACK_RIM = Color3.fromRGB(5, 5, 10)

-- Shared number formatting, with a local fallback.
local abbreviate
do
	local module = ReplicatedStorage:FindFirstChild("NumberFormatter")
	local ok, formatter = pcall(function()
		return module and require(module)
	end)

	if ok and type(formatter) == "table" and formatter.Abbreviate then
		abbreviate = function(n)
			return (formatter.Abbreviate(n))
		end
	else
		abbreviate = function(n)
			n = math.max(tonumber(n) or 0, 0)
			if n < 1000 then
				if math.floor(n) == n then return tostring(math.floor(n)) end
				return (string.format("%.1f", n):gsub("%.?0+$", ""))
			end
			local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
			local index = math.clamp(math.floor(math.log(n) / math.log(1000)), 1, #suffixes - 1)
			local scaled = n / (1000 ^ index)
			return (string.format("%.2f", scaled):gsub("%.?0+$", "")) .. suffixes[index + 1]
		end
	end
end

-- Colour language: blue = my selection, green = valid drop/merge, red = invalid.
local SELECT_COLOR = Color3.fromRGB(120, 150, 255)
local VALID_COLOR = Color3.fromRGB(90, 230, 120)
local INVALID_COLOR = Color3.fromRGB(255, 92, 86)

do
	local module = ReplicatedStorage:FindFirstChild("CosmicCombatConfig")
	if module then
		local ok, combat = pcall(require, module)
		if ok and type(combat) == "table" and combat.Colors and combat.Colors.Attacker then
			SELECT_COLOR = combat.Colors.Attacker
		end
	end
end

-- Reduced pickup radius to stop accidental pickups.
local PICKUP_RADIUS = 5
local PICKUP_CHECK_INTERVAL = 0.10

local selectedHole = nil
local mergeDistance = 4.6
local pickupBusy = false
local lastPickupCheck = 0

local ignoredHole = nil
local ignoreUntil = 0

local selectedHighlight = nil
local targetHighlight = nil

local latestHeldVersion = 0
local targetingActive = false

-- ===== HELPERS =====

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(r, 0)
	c.Parent = parent
	return c
end

local function rawStroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function rawTextStroke(label, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = label
	return s
end

local function tween(instance, info, goal)
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

local function makeUISound(name, volume)
	local existing = SoundService:FindFirstChild(name)
	if existing then return existing end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = UI_SOUND_ID
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local hoverSound = makeUISound("CarryCardHoverSound", 0.22)
local clickSound = makeUISound("CarryCardClickSound", 0.45)

local function play(sound)
	if sound and sound.Volume > 0 then
		sound.TimePosition = 0
		sound:Play()
	end
end

local function getRootPart()
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart")
end

local function isOwnBlackHole(hole)
	return hole
		and hole:IsA("BasePart")
		and CollectionService:HasTag(hole, TAG)
		and hole:GetAttribute("OwnerUserId") == player.UserId
end

local function makeHighlight(name, color)
	local h = Instance.new("Highlight")
	h.Name = name
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = 0.82
	h.OutlineTransparency = 0.05
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = workspace
	return h
end

local function ensureHighlights()
	if not selectedHighlight then
		selectedHighlight = makeHighlight("SelectedBlackHoleHighlight", SELECT_COLOR)
	end
	if not targetHighlight then
		targetHighlight = makeHighlight("MergeTargetHighlight", VALID_COLOR)
	end
end

local function clearHighlights()
	if selectedHighlight then
		selectedHighlight:Destroy()
		selectedHighlight = nil
	end
	if targetHighlight then
		targetHighlight:Destroy()
		targetHighlight = nil
	end
end

local function shouldIgnoreHole(hole)
	if not ignoredHole then
		return false
	end

	if os.clock() >= ignoreUntil then
		ignoredHole = nil
		return false
	end

	return ignoredHole == hole
end

local function findLocalHeldHole()
	for _, hole in ipairs(CollectionService:GetTagged(TAG)) do
		if isOwnBlackHole(hole) and hole:GetAttribute("HeldBy") == player.UserId then
			return hole
		end
	end
	return nil
end

local function findNearestPickupHole()
	local root = getRootPart()
	if not root then return nil end

	local nearest = nil
	local nearestDistance = PICKUP_RADIUS
	local nowServer = workspace:GetServerTimeNow()

	for _, hole in ipairs(CollectionService:GetTagged(TAG)) do
		if isOwnBlackHole(hole) and hole:GetAttribute("HeldBy") == 0 then
			if not shouldIgnoreHole(hole) then
				local lockedUntil = tonumber(hole:GetAttribute("PickupLockedUntil")) or 0

				if nowServer >= lockedUntil then
					local distance = (hole.Position - root.Position).Magnitude

					if distance <= nearestDistance then
						nearestDistance = distance
						nearest = hole
					end
				end
			end
		end
	end

	return nearest
end

local function findNearestMergeTarget()
	if not selectedHole or not selectedHole.Parent then
		return nil
	end

	-- Favorites (locked in the Inventory) never merge, so they're never highlighted.
	if selectedHole:GetAttribute("Favorite") == true then
		return nil
	end

	local selectedTier = tonumber(selectedHole:GetAttribute("Tier")) or 1
	local nearest = nil
	local nearestDistance = mergeDistance

	for _, hole in ipairs(CollectionService:GetTagged(TAG)) do
		if hole ~= selectedHole and isOwnBlackHole(hole) and hole:GetAttribute("HeldBy") == 0
			and hole:GetAttribute("Favorite") ~= true then
			local tier = tonumber(hole:GetAttribute("Tier")) or 1

			if tier == selectedTier then
				local distance = (hole.Position - selectedHole.Position).Magnitude

				if distance <= nearestDistance then
					nearestDistance = distance
					nearest = hole
				end
			end
		end
	end

	return nearest
end

-- ===== CARD CONFIG =====

local CARD = {
	Width = 520,
	Height = 158,
	Pad = 18,
	BottomOffset = 26,
	ButtonTop = 92,
	ButtonHeight = 50,
	ButtonDepth = 5,
	ButtonGap = 12,
}

local THEME = {
	Fill = Color3.fromRGB(22, 28, 62),
	FillShade = Color3.fromRGB(95, 100, 125),
	BorderA = Color3.fromRGB(78, 140, 255),
	BorderB = Color3.fromRGB(168, 104, 255),
	Glow = Color3.fromRGB(110, 90, 255),
	Divider = Color3.fromRGB(64, 76, 140),
	LabelDim = Color3.fromRGB(150, 166, 206),
	Rim = Color3.fromRGB(10, 8, 22),
}

local BUTTON_STYLES = {
	Attack = {
		Text = "ATTACK",
		Icon = "⚔",
		IconTilt = -12,
		Top = Color3.fromRGB(255, 98, 88),
		Bottom = Color3.fromRGB(218, 44, 62),
		Base = Color3.fromRGB(120, 18, 34),
		Hover = Color3.fromRGB(255, 196, 186),
	},
	Drop = {
		Text = "DROP",
		Icon = "↓",
		IconTilt = 0,
		Top = Color3.fromRGB(78, 226, 104),
		Bottom = Color3.fromRGB(28, 168, 64),
		Base = Color3.fromRGB(14, 92, 36),
		Hover = Color3.fromRGB(186, 255, 204),
	},
}

-- Same tier bands as the world labels, so a tier reads identically everywhere.
local TIER_BANDS = {
	{ max = 8,  fill = Color3.fromRGB(62, 110, 198),  edge = Color3.fromRGB(150, 198, 255) },
	{ max = 16, fill = Color3.fromRGB(28, 148, 126),  edge = Color3.fromRGB(118, 240, 206) },
	{ max = 24, fill = Color3.fromRGB(112, 66, 192),  edge = Color3.fromRGB(198, 152, 255) },
	{ max = 32, fill = Color3.fromRGB(198, 130, 24),  edge = Color3.fromRGB(255, 214, 112) },
	{ max = 40, fill = Color3.fromRGB(190, 48, 60),   edge = Color3.fromRGB(255, 140, 140) },
	{ max = math.huge, fill = Color3.fromRGB(206, 190, 142), edge = Color3.fromRGB(255, 252, 234) },
}

local function bandFor(tier)
	for _, band in ipairs(TIER_BANDS) do
		if tier <= band.max then return band end
	end
	return TIER_BANDS[#TIER_BANDS]
end

local MOTION = {
	Hover = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Press = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Release = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Flash = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	CardIn = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	CardSlide = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	CardOut = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Count = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Punch = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
}

-- ===== UI ROOT =====

local old = playerGui:FindFirstChild("BlackHoleActionUI")
if old then
	old:Destroy()
end

local actionGui = Instance.new("ScreenGui")
actionGui.Name = "BlackHoleActionUI"
actionGui.ResetOnSpawn = false
actionGui.IgnoreGuiInset = true
actionGui.DisplayOrder = 80
actionGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
actionGui.Parent = playerGui

local rootGui = Instance.new("Frame")
rootGui.Name = "Root"
rootGui.Size = UDim2.fromScale(1, 1)
rootGui.BackgroundTransparency = 1
rootGui.Parent = actionGui

local rootScale = Instance.new("UIScale")
rootScale.Parent = rootGui

local DESIGN = Vector2.new(1280, 720)
local MIN_SCALE = 0.62
local MAX_SCALE = 1

local function refreshScale()
	local vp = camera.ViewportSize
	if vp.X < 1 then return end
	local scale = math.clamp(math.min(vp.X / DESIGN.X, vp.Y / DESIGN.Y), MIN_SCALE, MAX_SCALE)
		* math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 1, 1.6)   -- grows past 1080p
	rootScale.Scale = scale
	-- A UIScale shrinks the frame it sits on too: size the root up by the same
	-- factor so it still covers the whole screen and edge-anchored parts (the
	-- carry card at bottom-centre) stay on their edges.
	rootGui.Size = UDim2.fromScale(1 / scale, 1 / scale)
end

refreshScale()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)

-- ===== CARD =====

local CARD_POSITION = UDim2.new(0.5, 0, 1, -CARD.BottomOffset)

local cardHolder = Instance.new("Frame")
cardHolder.Name = "CarryCard"
cardHolder.AnchorPoint = Vector2.new(0.5, 1)
cardHolder.Position = CARD_POSITION
cardHolder.Size = UDim2.fromOffset(CARD.Width, CARD.Height)
cardHolder.BackgroundTransparency = 1
cardHolder.Visible = false
cardHolder.ZIndex = 10
cardHolder.Parent = rootGui

local cardScale = Instance.new("UIScale")
cardScale.Parent = cardHolder

local cardGlow = Instance.new("Frame")
cardGlow.Name = "Glow"
cardGlow.AnchorPoint = Vector2.new(0.5, 0.5)
cardGlow.Position = UDim2.fromScale(0.5, 0.5)
cardGlow.Size = UDim2.new(1, 16, 1, 16)
cardGlow.BackgroundColor3 = THEME.Glow
cardGlow.BackgroundTransparency = 0.86
cardGlow.BorderSizePixel = 0
cardGlow.ZIndex = 1
cardGlow.Parent = cardHolder
corner(cardGlow, 0.14)

local cardShadow = Instance.new("Frame")
cardShadow.Name = "Shadow"
cardShadow.Position = UDim2.fromOffset(0, 6)
cardShadow.Size = UDim2.fromScale(1, 1)
cardShadow.BackgroundColor3 = Color3.fromRGB(2, 3, 10)
cardShadow.BackgroundTransparency = 0.45
cardShadow.BorderSizePixel = 0
cardShadow.ZIndex = 2
cardShadow.Parent = cardHolder
corner(cardShadow, 0.12)

local panel = Instance.new("Frame")
panel.Name = "ActionPanel"
panel.Size = UDim2.fromScale(1, 1)
panel.BackgroundColor3 = THEME.Fill
panel.BackgroundTransparency = 0.06
panel.BorderSizePixel = 0
panel.ZIndex = 3
panel.Parent = cardHolder
corner(panel, 0.12)

local fillGrad = Instance.new("UIGradient")
fillGrad.Rotation = 90
fillGrad.Color = ColorSequence.new(Color3.new(1, 1, 1), THEME.FillShade)
fillGrad.Parent = panel

local cardBorder = rawStroke(panel, Color3.new(1, 1, 1), 2.5)
local borderGrad = Instance.new("UIGradient")
borderGrad.Color = ColorSequence.new(THEME.BorderA, THEME.BorderB)
borderGrad.Parent = cardBorder

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(CARD.Pad, 12)
title.Size = UDim2.new(1, -(CARD.Pad * 2 + 84), 0, 32)
title.Font = FONT
title.Text = "Black Hole"
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = COL.Light
title.ZIndex = 4
title.Parent = panel
rawTextStroke(title, THEME.Rim, 3)
do
	local cap = Instance.new("UITextSizeConstraint")
	cap.MinTextSize = 14
	cap.MaxTextSize = 26
	cap.Parent = title
end

local tierPill = Instance.new("Frame")
tierPill.Name = "TierBadge"
tierPill.AnchorPoint = Vector2.new(1, 0)
tierPill.Position = UDim2.new(1, -CARD.Pad, 0, 14)
tierPill.Size = UDim2.fromOffset(72, 30)
tierPill.BorderSizePixel = 0
tierPill.ZIndex = 4
tierPill.Parent = panel
corner(tierPill, 1)
local tierStroke = rawStroke(tierPill, Color3.new(1, 1, 1), 2)
do
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))
	g.Parent = tierPill
end

local tierText = Instance.new("TextLabel")
tierText.BackgroundTransparency = 1
tierText.Position = UDim2.fromOffset(6, 3)
tierText.Size = UDim2.new(1, -12, 1, -6)
tierText.Font = FONT
tierText.Text = "T1"
tierText.TextScaled = true
tierText.TextColor3 = COL.Light
tierText.ZIndex = 5
tierText.Parent = tierPill
rawTextStroke(tierText, THEME.Rim, 2)

local power = Instance.new("TextLabel")
power.Name = "Power"
power.BackgroundTransparency = 1
power.Position = UDim2.fromOffset(CARD.Pad, 48)
power.Size = UDim2.new(1, -CARD.Pad * 2, 0, 22)
power.Font = FONT
power.RichText = true
power.TextScaled = true
power.TextXAlignment = Enum.TextXAlignment.Left
power.TextColor3 = THEME.LabelDim
power.ZIndex = 4
power.Parent = panel
rawTextStroke(power, THEME.Rim, 2)
do
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 18
	cap.Parent = power
end

local powerScale = Instance.new("UIScale")
powerScale.Parent = power

local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.Position = UDim2.fromOffset(CARD.Pad, 80)
divider.Size = UDim2.new(1, -CARD.Pad * 2, 0, 1)
divider.BackgroundColor3 = THEME.Divider
divider.BackgroundTransparency = 0.45
divider.BorderSizePixel = 0
divider.ZIndex = 4
divider.Parent = panel

-- ===== BUTTONS =====

local function makeActionButton(key, order)
	local style = BUTTON_STYLES[key]
	local width = math.floor((CARD.Width - CARD.Pad * 2 - CARD.ButtonGap) / 2)
	local x = CARD.Pad + (order - 1) * (width + CARD.ButtonGap)

	local slot = Instance.new("Frame")
	slot.Name = key .. "Slot"
	slot.BackgroundTransparency = 1
	slot.Position = UDim2.fromOffset(x, CARD.ButtonTop)
	slot.Size = UDim2.fromOffset(width, CARD.ButtonHeight + CARD.ButtonDepth)
	slot.ZIndex = 5
	slot.Parent = panel

	local slotScale = Instance.new("UIScale")
	slotScale.Parent = slot

	-- Targeting pulse sits furthest back; only the Attack button uses it.
	local pulse = Instance.new("Frame")
	pulse.Name = "Pulse"
	pulse.AnchorPoint = Vector2.new(0.5, 0.5)
	pulse.Position = UDim2.fromScale(0.5, 0.5)
	pulse.Size = UDim2.new(1, 18, 1, 18)
	pulse.BackgroundColor3 = style.Top
	pulse.BackgroundTransparency = 1
	pulse.BorderSizePixel = 0
	pulse.ZIndex = 1
	pulse.Parent = slot
	corner(pulse, 0.32)

	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, 10, 1, 10)
	glow.BackgroundColor3 = style.Top
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.ZIndex = 2
	glow.Parent = slot
	corner(glow, 0.3)

	local base = Instance.new("Frame")
	base.Name = "Base"
	base.Position = UDim2.fromOffset(0, CARD.ButtonDepth)
	base.Size = UDim2.new(1, 0, 0, CARD.ButtonHeight)
	base.BackgroundColor3 = style.Base
	base.BorderSizePixel = 0
	base.ZIndex = 3
	base.Parent = slot
	corner(base, 0.28)
	rawStroke(base, THEME.Rim, 2.5)

	local face = Instance.new("TextButton")
	face.Name = key
	face.Position = UDim2.fromOffset(0, 0)
	face.Size = UDim2.new(1, 0, 0, CARD.ButtonHeight)
	face.BackgroundColor3 = Color3.new(1, 1, 1)
	face.AutoButtonColor = false
	face.Text = ""
	face.ZIndex = 4
	face.Parent = slot
	corner(face, 0.28)
	local faceStroke = rawStroke(face, THEME.Rim, 2.5)

	local faceGrad = Instance.new("UIGradient")
	faceGrad.Rotation = 90
	faceGrad.Color = ColorSequence.new(style.Top, style.Bottom)
	faceGrad.Parent = face

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.Position = UDim2.fromOffset(6, 4)
	shine.Size = UDim2.new(1, -12, 0.36, 0)
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.84
	shine.BorderSizePixel = 0
	shine.ZIndex = 5
	shine.Parent = face
	corner(shine, 0.5)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 6
	content.Parent = face

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.LayoutOrder = 1
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(30, 30)
	icon.Font = FONT
	icon.Text = style.Icon
	icon.TextScaled = true
	icon.TextColor3 = COL.Light
	icon.ZIndex = 7
	icon.Parent = content
	rawTextStroke(icon, THEME.Rim, 2)

	local iconScale = Instance.new("UIScale")
	iconScale.Parent = icon

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.LayoutOrder = 2
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 30)
	label.Font = FONT
	label.Text = style.Text
	label.TextSize = 26
	label.TextColor3 = COL.Light
	label.ZIndex = 7
	label.Parent = content
	rawTextStroke(label, THEME.Rim, 3)

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 8
	flash.Parent = face
	corner(flash, 0.28)

	return {
		style = style, slot = slot, slotScale = slotScale,
		pulse = pulse, glow = glow, face = face, faceStroke = faceStroke,
		icon = icon, iconScale = iconScale, label = label, flash = flash,
		hovering = false, pressed = false,
	}
end

local function restPose(button)
	tween(button.slotScale, MOTION.Release, { Scale = if button.hovering then 1.03 else 1 })
	tween(button.face, MOTION.Release, { Position = UDim2.fromOffset(0, 0) })
end

local function bindButton(button, onActivate)
	local face = button.face

	face.MouseEnter:Connect(function()
		button.hovering = true
		play(hoverSound)
		tween(button.slotScale, MOTION.Hover, { Scale = 1.03 })
		tween(button.faceStroke, MOTION.Hover, { Color = button.style.Hover, Thickness = 3 })
		tween(button.glow, MOTION.Hover, { BackgroundTransparency = 0.72 })
		tween(button.icon, MOTION.Hover, { Rotation = button.style.IconTilt })
		tween(button.iconScale, MOTION.Hover, { Scale = 1.15 })
	end)

	face.MouseLeave:Connect(function()
		button.hovering = false
		button.pressed = false
		tween(button.slotScale, MOTION.Hover, { Scale = 1 })
		tween(button.face, MOTION.Hover, { Position = UDim2.fromOffset(0, 0) })
		tween(button.faceStroke, MOTION.Hover, { Color = THEME.Rim, Thickness = 2.5 })
		tween(button.glow, MOTION.Hover, { BackgroundTransparency = 1 })
		tween(button.icon, MOTION.Hover, { Rotation = 0 })
		tween(button.iconScale, MOTION.Hover, { Scale = 1 })
	end)

	face.MouseButton1Down:Connect(function()
		button.pressed = true
		tween(button.slotScale, MOTION.Press, { Scale = 0.94 })
		tween(button.face, MOTION.Press, { Position = UDim2.fromOffset(0, CARD.ButtonDepth - 1) })
	end)

	-- Touch can lift off the button without a MouseLeave; never leave it pressed.
	face.InputEnded:Connect(function(input)
		if not button.pressed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			button.pressed = false
			restPose(button)
		end
	end)

	face.Activated:Connect(function()
		button.pressed = false
		play(clickSound)
		button.flash.BackgroundTransparency = 0.45
		tween(button.flash, MOTION.Flash, { BackgroundTransparency = 1 })
		restPose(button)
		onActivate()
	end)
end

local attackButton = makeActionButton("Attack", 1)
local dropButton = makeActionButton("Drop", 2)

-- ===== TOAST =====

local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 145)
toast.Size = UDim2.fromOffset(440, 50)
toast.BackgroundTransparency = 1
toast.Font = FONT
toast.Text = ""
toast.TextScaled = true
toast.TextColor3 = COL.Light
toast.ZIndex = 50
toast.Visible = false
toast.Parent = rootGui
local toastStroke = rawTextStroke(toast, BLACK_RIM, 3)
do
	local cap = Instance.new("UITextSizeConstraint")
	cap.MinTextSize = 18
	cap.MaxTextSize = 30
	cap.Parent = toast
end

local toastToken = 0

local function showToast(message)
	toastToken += 1
	local token = toastToken

	toast.Text = tostring(message or "")
	toast.Visible = true
	toast.TextTransparency = 0
	toastStroke.Transparency = 0

	task.delay(1.15, function()
		if toastToken ~= token or not toast.Parent then return end
		tween(toast, TweenInfo.new(0.25), { TextTransparency = 1 })
		tween(toastStroke, TweenInfo.new(0.25), { Transparency = 1 })
		task.delay(0.27, function()
			if toastToken == token then toast.Visible = false end
		end)
	end)
end

-- ===== CARD STATE =====

local cardShown = false
local cardToken = 0
local shownName, shownTier = nil, nil
local displayedPower = nil

local powerValue = Instance.new("NumberValue")
local powerTween = nil

local function renderPower(value)
	power.Text = string.format('Stellar Power: <font color="#FFD75A">★%s/s</font>', abbreviate(value))
end

powerValue.Changed:Connect(renderPower)
renderPower(0)

local function setPower(target, instant)
	target = tonumber(target) or 0
	if displayedPower == target then return end

	local previous = displayedPower
	displayedPower = target

	if powerTween then
		powerTween:Cancel()
		powerTween = nil
	end

	if instant or previous == nil then
		powerValue.Value = target
		renderPower(target)
		return
	end

	powerTween = tween(powerValue, MOTION.Count, { Value = target })
	powerScale.Scale = 1
	tween(powerScale, MOTION.Punch, { Scale = 1.06 })
end

local function renderTier(tier)
	local band = bandFor(tier)
	tierPill.BackgroundColor3 = band.fill
	tierStroke.Color = band.edge
	tierText.Text = "T" .. tostring(tier)
end

local function refreshCard(hole, instant, overrides)
	overrides = overrides or {}

	local name = tostring(overrides.displayName or hole:GetAttribute("DisplayName") or "Black Hole")
	if name ~= shownName then
		shownName = name
		title.Text = name
	end

	local tier = tonumber(overrides.tier or hole:GetAttribute("Tier")) or 1
	if tier ~= shownTier then
		shownTier = tier
		renderTier(tier)
	end

	setPower(overrides.stellarPower or hole:GetAttribute("StellarPower") or 0, instant)
end

local function openCard()
	if cardShown then return end
	cardShown = true
	cardToken += 1

	cardHolder.Visible = true
	cardScale.Scale = 0.9
	cardHolder.Position = CARD_POSITION + UDim2.fromOffset(0, 18)
	tween(cardScale, MOTION.CardIn, { Scale = 1 })
	tween(cardHolder, MOTION.CardSlide, { Position = CARD_POSITION })
end

local function closeCard()
	if not cardShown then return end
	cardShown = false
	cardToken += 1
	local token = cardToken

	tween(cardScale, MOTION.CardOut, { Scale = 0.92 })
	tween(cardHolder, MOTION.CardOut, { Position = CARD_POSITION + UDim2.fromOffset(0, 14) })

	task.delay(0.15, function()
		if cardToken == token then
			cardHolder.Visible = false
		end
	end)
end

-- ===== DROP INDICATOR =====
-- A ground ring under the held hole. Green over your base or on a merge target;
-- red outside your base, where the server will snap the drop back onto the plate.

local dropRing = Instance.new("CylinderHandleAdornment")
dropRing.Name = "DropIndicator"
dropRing.Adornee = workspace.Terrain
dropRing.Height = 0.15
dropRing.Radius = 3
dropRing.InnerRadius = 2.35
dropRing.Transparency = 0.2
dropRing.AlwaysOnTop = false
dropRing.Visible = false
dropRing.Parent = workspace.Terrain

local myPlate = nil
local plateScanAt = 0

local function getMyPlate()
	if myPlate and myPlate.Parent and myPlate:GetAttribute("OwnerUserId") == player.UserId then
		return myPlate
	end

	local now = os.clock()
	if now - plateScanAt < 4 then return nil end
	plateScanAt = now
	myPlate = nil

	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("BasePart")
			and instance:GetAttribute("OwnerUserId") == player.UserId
			and not CollectionService:HasTag(instance, TAG)
			and instance.Name:lower():find("plate", 1, true) then
			myPlate = instance
			break
		end
	end

	return myPlate
end

local function updateDropIndicator(_mergeTarget)
	-- The flowing merge guide replaces this old floor ring.
	dropRing.Visible = false
end

-- ===== PANEL =====

local function showPanel(hole, result)
	if not hole or not hole.Parent then
		return
	end

	local isNewHole = hole ~= selectedHole
	selectedHole = hole

	if isNewHole then
		shownName, shownTier, displayedPower = nil, nil, nil
	end

	refreshCard(hole, isNewHole or not cardShown, type(result) == "table" and result or nil)
	openCard()

	ensureHighlights()
	selectedHighlight.Adornee = hole
	selectedHighlight.Enabled = not targetingActive
end

local function hidePanel(ignoreCurrentHole)
	if ignoreCurrentHole and selectedHole and selectedHole.Parent then
		ignoredHole = selectedHole
		ignoreUntil = os.clock() + 0.85
	end

	closeCard()
	selectedHole = nil
	shownName, shownTier, displayedPower = nil, nil, nil
	dropRing.Visible = false
	clearHighlights()
end

-- ===== ATTACK TARGETING STATE =====

local pulseTween = nil

local function setTargetingVisual(active)
	targetingActive = active

	attackButton.label.Text = if active then "CANCEL" else BUTTON_STYLES.Attack.Text
	attackButton.icon.Text = if active then "✕" else BUTTON_STYLES.Attack.Icon

	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end

	if active then
		attackButton.pulse.BackgroundTransparency = 0.82
		pulseTween = TweenService:Create(attackButton.pulse,
			TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = 0.5 })
		pulseTween:Play()
	else
		attackButton.pulse.BackgroundTransparency = 1
	end

	-- Step the card's own highlights aside so the orange target reads clearly.
	if selectedHighlight then
		selectedHighlight.Enabled = not active and selectedHole ~= nil
	end
	if targetHighlight and active then
		targetHighlight.Enabled = false
	end
	if active then
		dropRing.Visible = false
	end
end

-- AttackTargetingClient enables workspace.AttackerHighlight only while targeting,
-- so its Enabled property is the targeting state. No extra remote or edit needed.
local function watchAttackerHighlight(highlight)
	if not highlight:IsA("Highlight") then return end
	highlight:GetPropertyChangedSignal("Enabled"):Connect(function()
		setTargetingVisual(highlight.Enabled)
	end)
	setTargetingVisual(highlight.Enabled)
end

do
	local existing = workspace:FindFirstChild("AttackerHighlight")
	if existing then watchAttackerHighlight(existing) end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "AttackerHighlight" then
			watchAttackerHighlight(child)
		end
	end)
end

-- ===== PICKUP / DROP / ATTACK =====

local function pickup(hole)
	if pickupBusy then return end
	if selectedHole then return end
	if not isOwnBlackHole(hole) then return end

	pickupBusy = true

	local ok, result = pcall(function()
		return RequestPickup:InvokeServer(hole)
	end)

	pickupBusy = false

	if not ok then
		warn("[BlackHoleCarryClient] Pickup failed:", result)
		return
	end

	if type(result) == "table" and result.ok then
		mergeDistance = tonumber(result.mergeDistance) or 4.6
		latestHeldVersion = math.max(latestHeldVersion, tonumber(result.heldVersion) or latestHeldVersion)
		showPanel(hole, result)
	elseif type(result) == "table" and result.heldHole and result.heldHole.Parent then
		latestHeldVersion = math.max(latestHeldVersion, tonumber(result.heldVersion) or latestHeldVersion)
		showPanel(result.heldHole, result.payload)
	elseif type(result) == "table" and result.message
		and result.message ~= "Move closer." and result.message ~= "Wait a moment." then
		showToast(result.message)
	end
end

bindButton(attackButton, function()
	local toggle = playerGui:FindFirstChild("ToggleAttackTargeting")

	if toggle and toggle:IsA("BindableFunction") then
		local ok, result = pcall(function()
			return toggle:Invoke()
		end)

		if not ok then
			showToast("Attack unavailable.")
			return
		end

		if type(result) == "table" then
			if result.ok == false then
				showToast(result.reason or "Cannot attack right now.")
			elseif result.targeting then
				showToast("Pick a target to absorb.")
			end
		end
		return
	end

	-- Fallback: AttackTargetingClient is not installed, use the server stub.
	local ok, result = pcall(function()
		return RequestAttack:InvokeServer()
	end)

	if ok and type(result) == "table" and result.message then
		showToast(result.message)
	else
		showToast("Attack coming soon.")
	end
end)

bindButton(dropButton, function()
	local ok, result = pcall(function()
		return RequestDrop:InvokeServer()
	end)

	if not ok then
		warn("[BlackHoleCarryClient] Drop failed:", result)
		showToast("Drop failed.")
		hidePanel(true)
		return
	end

	if type(result) == "table" then
		showToast(result.message or "Dropped.")

		if result.merged == true then
			hidePanel(false)
		else
			hidePanel(true)
		end
	else
		showToast("Dropped.")
		hidePanel(true)
	end
end)

HeldChanged.OnClientEvent:Connect(function(hole, version, payload)
	version = tonumber(version) or 0

	if version < latestHeldVersion then
		return
	end

	latestHeldVersion = version

	if hole and hole.Parent then
		showPanel(hole, payload)
	else
		hidePanel(false)
	end
end)

-- ===== MAIN LOOP =====

local MERGE_CHECK_INTERVAL = 1 / 12
local DROP_CHECK_INTERVAL = 1 / 20

local mergeCheckAt = 0
local dropCheckAt = 0
local cachedMergeTarget = nil

RunService.RenderStepped:Connect(function()
	if selectedHole and not selectedHole.Parent then
		hidePanel(false)
		return
	end

	if selectedHole then
		-- Picks up in-place tier upgrades without replaying the card animation.
		refreshCard(selectedHole, false)

		ensureHighlights()
		selectedHighlight.Adornee = selectedHole
		selectedHighlight.Enabled = not targetingActive

		local now = os.clock()

		if now >= mergeCheckAt then
			mergeCheckAt = now + MERGE_CHECK_INTERVAL
			cachedMergeTarget = if targetingActive then nil else findNearestMergeTarget()
		end

		targetHighlight.Adornee = cachedMergeTarget
		targetHighlight.Enabled = cachedMergeTarget ~= nil

		if now >= dropCheckAt then
			dropCheckAt = now + DROP_CHECK_INTERVAL
			updateDropIndicator(cachedMergeTarget)
		end

		return
	end

	if pickupBusy then return end

	local now = os.clock()
	if now - lastPickupCheck < PICKUP_CHECK_INTERVAL then
		return
	end
	lastPickupCheck = now

	local localHeld = findLocalHeldHole()
	if localHeld then
		showPanel(localHeld)
		return
	end

	local nearest = findNearestPickupHole()
	if nearest then
		pickup(nearest)
	end
end)

-- ===== WORLD INCOME POPUPS =====
-- The server reports income for every black hole every second. Showing each
-- one covered the screen, so amounts are now added up per black hole and shown
-- every FlushSeconds: only your black holes near the camera, at most MaxShown
-- at a time, small and short-lived, beside the black hole (never over its
-- label). The number is the real total earned since the last popup.
-- Presentation only: income timing and amounts are unchanged.
-- Settings > Income Popups turns them off.
local INCOME_POPUPS = {
	FlushSeconds = 3,
	MaxShown = 4,
	MaxDistance = 70,
	Lifetime = 1.1,
}

local popupSettings do
	local module = ReplicatedStorage:FindFirstChild("ClientSettings")
	local ok, result = pcall(function() return module and require(module) end)
	popupSettings = if ok and type(result) == "table" then result else nil
end

local pendingIncome = {}   -- [hole] = amount since the last popup
local shownPopups = 0

local function makeWorldIncomePopup(hole, amount)
	local size = SizeVariants.Diameter(hole)
	local side = if math.random() < 0.5 then -1 else 1

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "WorldIncomePopup"
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(120, 34)
	billboard.StudsOffsetWorldSpace = SizeVariants.WorldCenter(hole) - hole.Position + Vector3.new(side * (size * 0.5 + 1.2), size * 0.1, 0)
	billboard.MaxDistance = INCOME_POPUPS.MaxDistance + 10
	billboard.Parent = hole

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "+★" .. abbreviate(amount)
	label.Font = FONT
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(90, 255, 120)
	label.TextStrokeColor3 = Color3.fromRGB(16, 60, 30)
	label.TextStrokeTransparency = 0.1
	label.Parent = billboard

	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = label

	shownPopups += 1
	tween(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	tween(billboard, TweenInfo.new(INCOME_POPUPS.Lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = billboard.StudsOffsetWorldSpace + Vector3.new(0, 1.2, 0),
	})
	task.delay(INCOME_POPUPS.Lifetime * 0.65, function()
		if label.Parent then
			tween(label, TweenInfo.new(INCOME_POPUPS.Lifetime * 0.35), { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end)
	task.delay(INCOME_POPUPS.Lifetime, function()
		shownPopups -= 1
		billboard:Destroy()
	end)
end

WorldIncomePopup.OnClientEvent:Connect(function(hole, amount)
	if typeof(hole) ~= "Instance" then return end
	amount = tonumber(amount) or 0
	if amount <= 0 then return end
	pendingIncome[hole] = (pendingIncome[hole] or 0) + amount
end)

task.spawn(function()
	while true do
		task.wait(INCOME_POPUPS.FlushSeconds)
		if popupSettings and popupSettings.Get and popupSettings.Get("IncomePopups") == false then
			table.clear(pendingIncome)
			continue
		end
		local cam = workspace.CurrentCamera
		local list = {}
		for hole, total in pairs(pendingIncome) do
			if hole.Parent and cam then
				local distance = (hole.Position - cam.CFrame.Position).Magnitude
				if distance <= INCOME_POPUPS.MaxDistance then
					table.insert(list, { hole = hole, total = total, distance = distance })
				end
			end
		end
		table.clear(pendingIncome)
		table.sort(list, function(a, b) return a.distance < b.distance end)
		for index = 1, math.min(#list, INCOME_POPUPS.MaxShown - shownPopups) do
			makeWorldIncomePopup(list[index].hole, list[index].total)
		end
	end
end)

-- ===== STARDUST COUNTER GAIN =====
-- Passive income used to throw 18 stars and a big "+X Stardust" from the top
-- of the screen every 5 seconds. Now a small "+★X" rises beside the Stardust
-- counter (bottom-left) instead, and MainHUD pops the number. Playtime rewards
-- and codes still use the big star burst. Presentation only: the server still
-- sends the same totals on the same timer.
local gainGui = Instance.new("ScreenGui")
gainGui.Name = "StardustGainUI"
gainGui.ResetOnSpawn = false
gainGui.IgnoreGuiInset = true
gainGui.DisplayOrder = 6
gainGui.Parent = playerGui

local gainLabel = nil

local function stardustCounter()
	-- MainHUD is switched off during attack views; show nothing then.
	local hud = playerGui:FindFirstChild("MainHUD")
	if not hud or (hud:IsA("ScreenGui") and not hud.Enabled) then return nil end
	local display = hud:FindFirstChild("StardustDisplay", true)
	if display and display:IsA("GuiObject") and display.Visible and display.AbsoluteSize.X > 1 then
		return display
	end
	return nil
end

IncomeTick.OnClientEvent:Connect(function(amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then return end
	local display = stardustCounter()
	if not display then return end

	if gainLabel then gainLabel:Destroy() end
	-- AbsolutePosition is measured from below the top bar; this ScreenGui
	-- ignores the top bar, so the inset is added back.
	local inset = GuiService:GetGuiInset()
	local x = display.AbsolutePosition.X + display.AbsoluteSize.X + 10
	local y = inset.Y + display.AbsolutePosition.Y + display.AbsoluteSize.Y * 0.5

	local label = Instance.new("TextLabel")
	label.Name = "StardustGain"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.fromOffset(150, 28)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.Text = "+★" .. abbreviate(amount)
	label.TextSize = 24
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(120, 255, 140)
	label.Parent = gainGui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(16, 50, 28)
	stroke.Thickness = 2.5
	stroke.Parent = label
	gainLabel = label

	local rise = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tween(label, rise, { Position = UDim2.fromOffset(x, y - 22) })
	task.delay(0.7, function()
		if label.Parent then
			tween(label, TweenInfo.new(0.4), { TextTransparency = 1 })
			tween(stroke, TweenInfo.new(0.4), { Transparency = 1 })
		end
	end)
	task.delay(1.15, function()
		if gainLabel == label then gainLabel = nil end
		label:Destroy()
	end)
end)

-- ===== MERGE VFX =====

local function playMergeVFX(position, tier, displayName)
	-- MutationClient plays the full merge animation (pull-in, burst, popup).
	-- This older flash only runs if that script is missing.
	if player:GetAttribute("MergeFusionClient") == true then
		return
	end

	-- Mini supernova merge effect. Local-only, so it does not lag the server.

	local anchor = Instance.new("Part")
	anchor.Name = "LocalMergeSupernovaAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace

	if MERGE_SOUND_ID ~= "" and MERGE_SOUND_ID ~= "rbxassetid://0" then
		local sound = Instance.new("Sound")
		sound.Name = "MergeSupernovaSound"
		sound.SoundId = MERGE_SOUND_ID
		sound.Volume = MERGE_SOUND_VOLUME
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 8
		sound.RollOffMaxDistance = 90
		sound.PlayOnRemove = false
		sound.Parent = anchor
		sound:Play()
	end

	local flash = Instance.new("Part")
	flash.Name = "SupernovaFlash"
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 235, 90)
	flash.Transparency = 0.05
	flash.Size = Vector3.new(1.2, 1.2, 1.2)
	flash.CFrame = CFrame.new(position + Vector3.new(0, 1.2, 0))
	flash.Parent = workspace

	tween(flash, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(8, 8, 8),
		Transparency = 1,
	})

	Debris:AddItem(flash, 0.3)

	local function makeRing(yOffset, color, finalSize, duration)
		local ring = Instance.new("Part")
		ring.Name = "SupernovaRing"
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanTouch = false
		ring.CanQuery = false
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Color = color
		ring.Transparency = 0.15
		ring.Size = Vector3.new(0.18, 1.4, 1.4)
		ring.CFrame = CFrame.new(position + Vector3.new(0, yOffset, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = workspace

		tween(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.18, finalSize, finalSize),
			Transparency = 1,
		})

		Debris:AddItem(ring, duration + 0.1)
	end

	makeRing(1.05, Color3.fromRGB(255, 230, 80), 18, 0.45)
	makeRing(1.12, Color3.fromRGB(100, 220, 255), 24, 0.6)
	makeRing(1.18, Color3.fromRGB(170, 95, 255), 30, 0.72)

	for i = 1, 28 do
		local star = Instance.new("Part")
		star.Name = "SupernovaStar"
		star.Anchored = true
		star.CanCollide = false
		star.CanTouch = false
		star.CanQuery = false
		star.Shape = Enum.PartType.Ball
		star.Material = Enum.Material.Neon

		if i % 3 == 0 then
			star.Color = Color3.fromRGB(100, 220, 255)
		elseif i % 3 == 1 then
			star.Color = Color3.fromRGB(255, 230, 80)
		else
			star.Color = Color3.fromRGB(170, 95, 255)
		end

		local size = math.random(18, 38) / 100
		star.Size = Vector3.new(size, size, size)
		star.CFrame = CFrame.new(position + Vector3.new(0, 1.3, 0))
		star.Parent = workspace

		local angle = math.random() * math.pi * 2
		local distance = math.random(45, 120) / 10
		local height = math.random(8, 55) / 10

		local offset = Vector3.new(
			math.cos(angle) * distance,
			height,
			math.sin(angle) * distance
		)

		tween(star, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = star.Position + offset,
			Transparency = 1,
			Size = Vector3.new(0.05, 0.05, 0.05),
		})

		Debris:AddItem(star, 0.7)
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MergeVFX"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(285, 95)
	billboard.StudsOffset = Vector3.new(0, 5.4, 0)
	billboard.MaxDistance = 180
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)

	local mergeWord = "SUPERNOVA!"
	if math.random(1, 2) == 1 then
		mergeWord = "MERGED!"
	end

	label.Text = mergeWord .. "\n" .. tostring(displayName or ("Tier " .. tostring(tier)))
	label.Font = FONT
	label.TextScaled = true
	label.TextColor3 = COL.Yellow
	label.TextStrokeColor3 = Color3.fromRGB(5, 5, 10)
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MinTextSize = 18
	textLimit.MaxTextSize = 42
	textLimit.Parent = label

	local scale = Instance.new("UIScale")
	scale.Scale = 0.35
	scale.Parent = label

	tween(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })

	tween(billboard, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 7.8, 0),
	})

	task.delay(0.55, function()
		if label and label.Parent then
			tween(label, TweenInfo.new(0.25), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			})
		end
	end)

	Debris:AddItem(anchor, 1.35)
end

MergeVFX.OnClientEvent:Connect(playMergeVFX)

print("[BlackHoleCarryClient] Running.")