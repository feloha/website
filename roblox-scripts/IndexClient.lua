-- IndexClient (LocalScript in StarterPlayer > StarterPlayerScripts)
-- Cosmic Index. Entries generated from BlackHoleTierConfig; discovery state
-- comes from the server. Hooks the existing Index HUD button without altering it.
-- The MUTATIONS tab lists every mutation from MutationConfig; which ones you've
-- found comes from the server (player attribute "MutationsDiscovered").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GuiStyle = require(ReplicatedStorage:WaitForChild("GuiStyle"))
local TierConfig = require(ReplicatedStorage:WaitForChild("BlackHoleTierConfig"))
local IndexConfig = require(ReplicatedStorage:WaitForChild("BlackHoleIndexConfig"))

local Format do
	local module = ReplicatedStorage:WaitForChild("NumberFormatter", 10)
	Format = module and require(module) or {
		Abbreviate = function(n) return tostring(math.floor(tonumber(n) or 0)) end,
		Power = function(n) return "★" .. tostring(math.floor(tonumber(n) or 0)) .. "/s" end,
	}
end

-- Same black hole look as in the world (optional).
local Cosmetics do
	local module = ReplicatedStorage:FindFirstChild("BlackHoleCosmetics")
	local ok, result = pcall(function() return module and require(module) end)
	Cosmetics = if ok and type(result) == "table" then result else nil
end

local MutationConfig do
	local module = ReplicatedStorage:FindFirstChild("MutationConfig")
	local ok, result = pcall(function() return module and require(module) end)
	MutationConfig = if ok and type(result) == "table" then result else nil
end

local GuiManager do
	local module = ReplicatedStorage:FindFirstChild("GuiManager")
		or ReplicatedStorage:FindFirstChild("PopupManager")
	GuiManager = module and require(module) or nil
end

local FONT = GuiStyle.FONT
local IS_TOUCH = UserInputService.TouchEnabled

local PANEL = Color3.fromRGB(10, 14, 32)
local BAR = Color3.fromRGB(5, 8, 22)
local CARD = Color3.fromRGB(18, 24, 52)
local CARD_LOCKED = Color3.fromRGB(13, 17, 38)
local RIM = Color3.fromRGB(58, 118, 222)
local RIM_SOFT = Color3.fromRGB(38, 62, 128)
local TEXT = Color3.fromRGB(255, 255, 255)
local TEXT_DIM = Color3.fromRGB(132, 154, 200)
local ACCENT = Color3.fromRGB(96, 186, 255)
local GOLD = Color3.fromRGB(255, 215, 90)
local GREEN = Color3.fromRGB(56, 222, 104)
local WHITE_COLOR = Color3.new(1, 1, 1)
local MUTATION_ACCENT = Color3.fromRGB(196, 130, 255)
local RARITY_COLORS = {
	Common = Color3.fromRGB(120, 200, 255),
	Mid = Color3.fromRGB(196, 130, 255),
	Rare = Color3.fromRGB(255, 200, 80),
}

local MOTION = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Panel = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Close = TweenInfo.new(0.20, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
}

local function makeSound(name, id, volume)
	local existing = SoundService:FindFirstChild(name)
	if existing then return existing end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local openSound = makeSound("IndexOpenSound", "rbxassetid://7218169592", 0.5)
local tickSound = makeSound("IndexTickSound", "rbxassetid://7218169592", 0.26)

local function play(sound)
	if sound and sound.Volume > 0 then
		sound.TimePosition = 0
		sound:Play()
	end
end

local old = playerGui:FindFirstChild("CosmicIndexHUD")
if old then old:Destroy() end

-- ===================== DATA =====================
local entries = {}
local maxTier = (TierConfig.GetMaxTier and TierConfig.GetMaxTier()) or 48
for tier = 1, maxTier do
	local data = TierConfig.GetTier(tier)
	if data then
		table.insert(entries, {
			tier = tier,
			name = tostring(data.DisplayName or ("Tier " .. tier)),
			power = tonumber(data.StellarPower) or tonumber(data.IncomePerSecond) or 0,
			accent = data.GlowColor or data.DiskGlowColor or ACCENT,
			description = IndexConfig.GetDescription(tier),
		})
	end
end
table.sort(entries, function(a, b) return a.tier < b.tier end)

local discovered, newFlags = {}, {}
local pendingSeen = {}

-- Mutations: every one is shown on the MUTATIONS page on the same showcase tier.
local MUTATION_SHOWCASE_TIER = math.min(20, maxTier)
local mutationEntries = {}
if MutationConfig then
	for order, id in ipairs(MutationConfig.Order) do
		local data = MutationConfig.Mutations[id]
		if data then
			table.insert(mutationEntries, {
				id = id,
				order = order,
				tier = MUTATION_SHOWCASE_TIER,
				name = tostring(data.DisplayName or id),
				oneIn = tonumber(data.OneIn) or 0,
				rarity = tostring(data.Rarity or "Common"),
				accent = data.Main or MUTATION_ACCENT,
				spectrum = data.Spectrum,
				description = tostring(data.Description or ""),
			})
		end
	end
end
local mutationsFound, mutationNew = {}, {}

local function rarityName(rarity)
	local names = MutationConfig and MutationConfig.RarityNames
	return (names and names[rarity]) or string.upper(tostring(rarity))
end

local function oddsText(oneIn)
	if MutationConfig and MutationConfig.OddsText then
		return MutationConfig.OddsText(oneIn)
	end
	return "1 IN " .. tostring(oneIn)
end

local viewportModels = {}
local viewportInfo = {}
local detailSpinTarget = nil

-- ===================== SHELL =====================
local gui = Instance.new("ScreenGui")
gui.Name = "CosmicIndexHUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
do
	local ok, responsive = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("UiResponsive", 5)) end)
	if ok and type(responsive) == "table" and responsive.UseModalInsets then responsive.UseModalInsets(gui) end   -- below the top bar
end
gui.DisplayOrder = 7
gui.Parent = playerGui

local dim = Instance.new("Frame")
dim.Position = UDim2.fromOffset(-300, -300)   -- reaches under the top bar too
dim.Size = UDim2.new(1, 600, 1, 600)
dim.BackgroundColor3 = Color3.fromRGB(4, 7, 20)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Visible = false
dim.ZIndex = 50
dim.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "IndexPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = if IS_TOUCH then UDim2.fromScale(0.92, 0.9) else UDim2.fromScale(0.82, 0.82)
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Visible = false
panel.ZIndex = 52
panel.Parent = gui
GuiStyle.Corner(panel, 0.03)
GuiStyle.Stroke(panel, RIM, 3)

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel
do
	-- Never wider/taller than this, so ultrawide and 1440p screens get a
	-- centred panel instead of one spread across the whole display.
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(1600, 960)
	limit.Parent = panel
end

-- ===================== HEADER =====================
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 86)
header.BackgroundColor3 = BAR
header.BackgroundTransparency = 0.08
header.BorderSizePixel = 0
header.ZIndex = 54
header.Parent = panel

local headerLine = Instance.new("Frame")
headerLine.Position = UDim2.new(0, 0, 1, -3)
headerLine.Size = UDim2.new(1, 0, 0, 3)
headerLine.BackgroundColor3 = RIM
headerLine.BorderSizePixel = 0
headerLine.ZIndex = 55
headerLine.Parent = header

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(26, 10)
title.Size = UDim2.fromOffset(200, 44)
title.Text = "INDEX"
title.Font = FONT
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = TEXT
title.ZIndex = 56
title.Parent = header
GuiStyle.TextStroke(title, 3)
local titleCap = Instance.new("UITextSizeConstraint")
titleCap.MaxTextSize = 42
titleCap.Parent = title

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(28, 54)
subtitle.Size = UDim2.fromOffset(240, 18)
subtitle.Text = IndexConfig.Subtitle
subtitle.Font = FONT
subtitle.TextScaled = true
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.TextColor3 = TEXT_DIM
subtitle.ZIndex = 56
subtitle.Parent = header
local subCap = Instance.new("UITextSizeConstraint")
subCap.MaxTextSize = 15
subCap.Parent = subtitle

local countLabel = Instance.new("TextLabel")
countLabel.AnchorPoint = Vector2.new(1, 0)
countLabel.Position = UDim2.new(1, -78, 0, 12)
countLabel.Size = UDim2.fromOffset(280, 34)
countLabel.BackgroundTransparency = 1
countLabel.Text = "0 / 0 DISCOVERED"
countLabel.Font = FONT
countLabel.TextScaled = true
countLabel.TextXAlignment = Enum.TextXAlignment.Right
countLabel.TextColor3 = TEXT
countLabel.ZIndex = 56
countLabel.Parent = header
GuiStyle.TextStroke(countLabel, 2.5)
local countCap = Instance.new("UITextSizeConstraint")
countCap.MaxTextSize = 26
countCap.Parent = countLabel

local progressTrack = Instance.new("Frame")
progressTrack.AnchorPoint = Vector2.new(1, 0)
progressTrack.Position = UDim2.new(1, -78, 0, 52)
progressTrack.Size = UDim2.fromOffset(280, 12)
progressTrack.BackgroundColor3 = Color3.fromRGB(24, 32, 66)
progressTrack.BorderSizePixel = 0
progressTrack.ZIndex = 56
progressTrack.Parent = header
GuiStyle.Corner(progressTrack, 1)
GuiStyle.Stroke(progressTrack, RIM_SOFT, 1.5)

local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.fromScale(0, 1)
progressFill.BackgroundColor3 = ACCENT
progressFill.BorderSizePixel = 0
progressFill.ZIndex = 57
progressFill.Parent = progressTrack
GuiStyle.Corner(progressFill, 1)

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -16, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(48, 48)
closeBtn.BackgroundColor3 = GuiStyle.COL.X
closeBtn.AutoButtonColor = false
closeBtn.Text = ""
closeBtn.ZIndex = 58
closeBtn.Parent = header
GuiStyle.Corner(closeBtn, 0.3)
GuiStyle.Stroke(closeBtn, GuiStyle.COL.XBorder, 3)

local closeScale = Instance.new("UIScale")
closeScale.Parent = closeBtn
for _, rotation in ipairs({ 45, -45 }) do
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.Size = UDim2.new(0.56, 0, 0.16, 0)
	bar.BackgroundColor3 = TEXT
	bar.BorderSizePixel = 0
	bar.Rotation = rotation
	bar.ZIndex = 59
	bar.Parent = closeBtn
	GuiStyle.Corner(bar, 1)
end

-- ===================== FILTER ROW =====================
local filterRow = Instance.new("Frame")
filterRow.Position = UDim2.new(0, 20, 0, 98)
filterRow.Size = UDim2.new(1, -40, 0, 42)
filterRow.BackgroundTransparency = 1
filterRow.ZIndex = 54
filterRow.Parent = panel

local currentFilter = "ALL"
local filterButtons = {}
local refreshGrid, refreshProgress
local TIER_SUBTITLE = subtitle.Text
local MUTATION_SUBTITLE = "Rolled on every merge. Each one boosts income, damage and health."

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tabLayout.Padding = UDim.new(0, 8)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = filterRow

local function makeTab(text, value, order)
	local button = Instance.new("TextButton")
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(if IS_TOUCH then 112 else 132, if IS_TOUCH then 46 else 38)
	button.BackgroundColor3 = CARD
	button.AutoButtonColor = false
	button.Text = text
	button.Font = FONT
	button.TextScaled = true
	button.TextColor3 = TEXT_DIM
	button.ZIndex = 55
	button.Parent = filterRow
	GuiStyle.Corner(button, 0.3)
	GuiStyle.Stroke(button, RIM_SOFT, 2)
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 17
	cap.Parent = button
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 9)
	pad.PaddingBottom = UDim.new(0, 9)
	pad.Parent = button

	filterButtons[value] = button
	button.Activated:Connect(function()
		play(tickSound)
		currentFilter = value
		for key, other in pairs(filterButtons) do
			local on = key == currentFilter
			local onColor = if key == "MUTATIONS" then Color3.fromRGB(226, 200, 255) else Color3.fromRGB(196, 226, 255)
			TweenService:Create(other, MOTION.Fast, {
				BackgroundColor3 = if on then onColor else CARD,
			}):Play()
			other.TextColor3 = if on then Color3.fromRGB(12, 30, 70)
				elseif key == "MUTATIONS" then MUTATION_ACCENT else TEXT_DIM
		end
		subtitle.Text = if currentFilter == "MUTATIONS" then MUTATION_SUBTITLE else TIER_SUBTITLE
		if refreshGrid then refreshGrid() end
		if refreshProgress then refreshProgress(true) end
	end)
	return button
end

makeTab("ALL", "ALL", 1)
makeTab("DISCOVERED", "DISCOVERED", 2)
makeTab("UNDISCOVERED", "UNDISCOVERED", 3)
if #mutationEntries > 0 then
	local mutationTab = makeTab("✦ MUTATIONS", "MUTATIONS", 4)
	mutationTab.TextColor3 = MUTATION_ACCENT
	local tabStroke = mutationTab:FindFirstChildOfClass("UIStroke")
	if tabStroke then tabStroke.Color = MUTATION_ACCENT end
end

filterButtons.ALL.BackgroundColor3 = Color3.fromRGB(196, 226, 255)
filterButtons.ALL.TextColor3 = Color3.fromRGB(12, 30, 70)

local searchBox = Instance.new("TextBox")
searchBox.AnchorPoint = Vector2.new(1, 0.5)
searchBox.Position = UDim2.new(1, 0, 0.5, 0)
searchBox.Size = UDim2.fromOffset(if IS_TOUCH then 160 else 260, if IS_TOUCH then 46 else 38)
searchBox.BackgroundColor3 = CARD
searchBox.Text = ""
searchBox.PlaceholderText = "Search discoveries..."
searchBox.PlaceholderColor3 = Color3.fromRGB(96, 116, 158)
searchBox.Font = FONT
searchBox.TextSize = 16
searchBox.TextColor3 = TEXT
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.ClearTextOnFocus = false
searchBox.ZIndex = 56
searchBox.Parent = filterRow
GuiStyle.Corner(searchBox, 0.3)
GuiStyle.Stroke(searchBox, RIM_SOFT, 2)
local searchPad = Instance.new("UIPadding")
searchPad.PaddingLeft = UDim.new(0, 12)
searchPad.PaddingRight = UDim.new(0, 12)
searchPad.Parent = searchBox

-- Tabs and search share the row: shrink them together on narrow screens.
local function refreshTabs()
	local width = filterRow.AbsoluteSize.X
	if width < 10 then return end
	local count = 0
	for _ in pairs(filterButtons) do count += 1 end
	if count == 0 then return end
	local search = math.clamp(math.floor(width * 0.24), 110, if IS_TOUCH then 160 else 260)
	searchBox.Size = UDim2.fromOffset(search, searchBox.Size.Y.Offset)
	local available = width - search - 12 - (count - 1) * 8
	local tab = math.clamp(math.floor(available / count), 64, if IS_TOUCH then 112 else 132)
	for _, button in pairs(filterButtons) do
		button.Size = UDim2.fromOffset(tab, button.Size.Y.Offset)
	end
end
filterRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshTabs)
task.defer(refreshTabs)

-- ===================== GRID =====================
local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.new(0, 20, 0, 148)
scroll.Size = UDim2.new(1, -40, 1, -166)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = RIM
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ZIndex = 53
scroll.Parent = panel

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(215, 270)
grid.CellPadding = UDim2.fromOffset(12, 12)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = scroll

local emptyState = Instance.new("TextLabel")
emptyState.AnchorPoint = Vector2.new(0.5, 0.5)
emptyState.Position = UDim2.fromScale(0.5, 0.45)
emptyState.Size = UDim2.fromOffset(440, 70)
emptyState.BackgroundTransparency = 1
emptyState.Text = "NO COSMIC OBJECTS FOUND\nTry another tier or name."
emptyState.Font = FONT
emptyState.TextSize = 20
emptyState.TextColor3 = TEXT_DIM
emptyState.Visible = false
emptyState.ZIndex = 54
emptyState.Parent = panel

-- Aim for a readable cell width rather than a fixed column count, then cap the
-- height so a card can never be taller than the visible scroll area.
local function refreshColumns()
	local width = scroll.AbsoluteSize.X
	local height = scroll.AbsoluteSize.Y
	if width < 10 then return end

	local target = math.clamp(math.floor(width / 215), 2, 8)
	local cell = math.floor((width - (target + 1) * 12) / target)
	local cellHeight = math.floor(cell * 1.26)

	if height > 40 then
		cellHeight = math.min(cellHeight, math.floor(height * 0.62))
	end

	grid.CellSize = UDim2.fromOffset(cell, cellHeight)
end
scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshColumns)

-- ===================== VIEWPORTS =====================
local function populateViewport(viewport, tier, locked, cacheKey, mutationId)
	cacheKey = cacheKey or ("grid_" .. tier)

	local cached = viewportModels[cacheKey]
	if cached and cached.Parent then
		cached.Parent = viewport
		return cached
	end

	local folder = ReplicatedStorage:FindFirstChild("BlackHoleCompleteModels")
	local template = folder and folder:FindFirstChild("T" .. tier)
	if not template then return nil end

	local model = template:Clone()

	if Cosmetics and Cosmetics.Enabled then
		local core
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Name:lower():match("^t0*%d+_core$") then
				core = part
				break
			end
		end
		if core then
			local _, extent = model:GetBoundingBox()
			pcall(Cosmetics.Build, model, core, tier, {
				reference = math.max(extent.X, extent.Y, extent.Z, 0.1),
				viewport = true,
				-- The mutation detail view uses more detail so its effect shows.
				quality = if mutationId and cacheKey == "detail" then "MODERATE" else "LOW",
				mutation = mutationId,
			})
		end
	end

	for _, instance in ipairs(model:GetDescendants()) do
		if instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript")
			or instance:IsA("ParticleEmitter") or instance:IsA("Light")
			or instance:IsA("Beam") or instance:IsA("Trail") then
			instance:Destroy()
		elseif instance:IsA("BasePart") then
			instance.Anchored = true
			instance.CanCollide = false
			if locked then
				instance.Color = Color3.fromRGB(16, 20, 40)
				instance.Material = Enum.Material.SmoothPlastic
			end
		end
	end

	local world = Instance.new("WorldModel")
	world.Parent = viewport
	model.Parent = world

	local vpCamera = Instance.new("Camera")
	vpCamera.Parent = viewport
	viewport.CurrentCamera = vpCamera

	local cf, size = model:GetBoundingBox()
	local extent = math.max(size.X, size.Y, size.Z)
	local distance = extent * 1.55 + 2

	viewportInfo[viewport] = { pivot = cf.Position, distance = distance, angle = 0.8 }
	vpCamera.CFrame = CFrame.new(
		cf.Position + Vector3.new(distance * 0.62, distance * 0.42, distance * 0.62),
		cf.Position)

	viewportModels[cacheKey] = world
	return world
end

-- Orbits the camera around the model rather than touching the model itself.
local function spinViewport(viewport, dt)
	local info = viewportInfo[viewport]
	local vpCamera = viewport.CurrentCamera
	if not info or not vpCamera then return end
	info.angle += dt * 0.35
	local d = info.distance
	vpCamera.CFrame = CFrame.new(
		info.pivot + Vector3.new(
			math.cos(info.angle) * d * 0.72,
			d * 0.42,
			math.sin(info.angle) * d * 0.72),
		info.pivot)
end

-- ===================== CARDS =====================
local cards = {}
local activeViewports = {}
local showDetail, showMutationDetail

local function buildViewport(parent)
	local viewport = Instance.new("ViewportFrame")
	-- Scale-based height. An aspect constraint here collapses the frame,
	-- because FitWithinMaxSize fits inside the size it already has.
	viewport.Position = UDim2.new(0, 8, 0, 8)
	viewport.Size = UDim2.new(1, -16, 0.64, -8)
	viewport.BackgroundColor3 = Color3.fromRGB(9, 13, 32)
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(190, 200, 235)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-0.4, -0.8, -0.5)
	viewport.ZIndex = 55
	viewport.Parent = parent
	GuiStyle.Corner(viewport, 0.1)

	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(0.82, 0.82)
	glow.BackgroundColor3 = Color3.fromRGB(38, 80, 180)
	glow.BackgroundTransparency = 0.86
	glow.BorderSizePixel = 0
	glow.ZIndex = 54
	glow.Parent = viewport
	GuiStyle.Corner(glow, 1)

	local fallback = Instance.new("TextLabel")
	fallback.Name = "Fallback"
	fallback.AnchorPoint = Vector2.new(0.5, 0.5)
	fallback.Position = UDim2.fromScale(0.5, 0.5)
	fallback.Size = UDim2.fromScale(0.5, 0.5)
	fallback.BackgroundTransparency = 1
	fallback.Text = "?"
	fallback.Font = FONT
	fallback.TextScaled = true
	fallback.TextColor3 = Color3.fromRGB(70, 92, 148)
	fallback.Visible = false
	fallback.ZIndex = 56
	fallback.Parent = viewport

	return viewport
end

local function makeCard(entry, order)
	local isMutation = entry.id ~= nil
	local card = Instance.new("TextButton")
	card.Name = if isMutation then "M_" .. entry.id else "T" .. entry.tier
	card.LayoutOrder = order
	card.BackgroundColor3 = CARD
	card.BackgroundTransparency = 0.1
	card.AutoButtonColor = false
	card.Text = ""
	card.ClipsDescendants = true
	card.ZIndex = 54
	card.Parent = scroll
	GuiStyle.Corner(card, 0.09)
	local stroke = GuiStyle.Stroke(card, RIM_SOFT, 2)

	local accentBar = Instance.new("Frame")
	accentBar.Name = "Accent"
	accentBar.AnchorPoint = Vector2.new(0.5, 1)
	accentBar.Position = UDim2.new(0.5, 0, 1, 0)
	accentBar.Size = UDim2.new(1, 0, 0, 4)
	accentBar.BackgroundColor3 = entry.accent
	accentBar.BorderSizePixel = 0
	accentBar.ZIndex = 57
	accentBar.Parent = card
	if entry.spectrum then
		accentBar.BackgroundColor3 = WHITE_COLOR
		local keypoints = {}
		for i, color in ipairs(entry.spectrum) do
			table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(#entry.spectrum - 1, 1), color))
		end
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(keypoints)
		gradient.Parent = accentBar
	end
	local scale = Instance.new("UIScale")
	scale.Parent = card

	local viewport = buildViewport(card)

	local badge = Instance.new("TextLabel")
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -12, 0, 12)
	badge.Size = UDim2.fromOffset(if isMutation then 96 elseif entry.tier >= 10 then 50 else 40, 24)
	badge.BackgroundColor3 = Color3.fromRGB(30, 44, 92)
	badge.Text = if isMutation then rarityName(entry.rarity) else "T" .. entry.tier
	badge.Font = FONT
	badge.TextScaled = true
	badge.TextColor3 = TEXT
	badge.ZIndex = 58
	badge.Parent = card
	GuiStyle.Corner(badge, 1)
	local badgeStroke = GuiStyle.Stroke(badge, entry.accent, 2)
	local badgeCap = Instance.new("UITextSizeConstraint")
	badgeCap.MinTextSize = 9
	badgeCap.MaxTextSize = 16
	badgeCap.Parent = badge

	local newBadge = Instance.new("TextLabel")
	newBadge.Position = UDim2.fromOffset(12, 12)
	newBadge.Size = UDim2.fromOffset(46, 22)
	newBadge.BackgroundColor3 = GREEN
	newBadge.Text = "NEW!"
	newBadge.Font = FONT
	newBadge.TextScaled = true
	newBadge.TextColor3 = Color3.fromRGB(8, 40, 18)
	newBadge.Visible = false
	newBadge.ZIndex = 58
	newBadge.Parent = card
	GuiStyle.Corner(newBadge, 1)
	local newCap = Instance.new("UITextSizeConstraint")
	newCap.MaxTextSize = 14
	newCap.Parent = newBadge

	local nameLabel = Instance.new("TextLabel")
	nameLabel.AnchorPoint = Vector2.new(0.5, 1)
	nameLabel.Position = UDim2.new(0.5, 0, 1, -46)
	nameLabel.Size = UDim2.new(1, -16, 0, 22)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = entry.name
	nameLabel.Font = FONT
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = TEXT
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 56
	nameLabel.Parent = card
	GuiStyle.TextStroke(nameLabel, 2)
	local nameCap = Instance.new("UITextSizeConstraint")
	nameCap.MinTextSize = 10
	nameCap.MaxTextSize = 21
	nameCap.Parent = nameLabel

	local statLabel = Instance.new("TextLabel")
	statLabel.AnchorPoint = Vector2.new(0.5, 1)
	statLabel.Position = UDim2.new(0.5, 0, 1, -26)
	statLabel.Size = UDim2.new(1, -16, 0, 18)
	statLabel.BackgroundTransparency = 1
	statLabel.Text = if isMutation then oddsText(entry.oneIn) else Format.Power(entry.power)
	statLabel.Font = FONT
	statLabel.TextScaled = true
	statLabel.TextColor3 = GOLD
	statLabel.ZIndex = 56
	statLabel.Parent = card
	local statCap = Instance.new("UITextSizeConstraint")
	statCap.MaxTextSize = 17
	statCap.Parent = statLabel

	local statusLabel = Instance.new("TextLabel")
	statusLabel.AnchorPoint = Vector2.new(0.5, 1)
	statusLabel.Position = UDim2.new(0.5, 0, 1, -6)
	statusLabel.Size = UDim2.new(1, -16, 0, 16)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "DISCOVERED"
	statusLabel.Font = FONT
	statusLabel.TextScaled = true
	statusLabel.TextColor3 = GREEN
	statusLabel.ZIndex = 56
	statusLabel.Parent = card
	local statusCap = Instance.new("UITextSizeConstraint")
	statusCap.MaxTextSize = 14
	statusCap.Parent = statusLabel

	card.MouseEnter:Connect(function()
		TweenService:Create(scale, MOTION.Fast, { Scale = 1.025 }):Play()
		TweenService:Create(stroke, MOTION.Fast, { Color = entry.accent }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(scale, MOTION.Fast, { Scale = 1 }):Play()
		TweenService:Create(stroke, MOTION.Fast, { Color = RIM_SOFT }):Play()
	end)
	card.Activated:Connect(function()
		play(tickSound)
		if isMutation then showMutationDetail(entry) else showDetail(entry) end
	end)

	return {
		entry = entry, root = card, viewport = viewport, stroke = stroke,
		badge = badge, badgeStroke = badgeStroke, newBadge = newBadge,
		name = nameLabel, stat = statLabel, status = statusLabel,
		populated = false, populatedLocked = true,
		kind = if isMutation then "mutation" else "tier",
		cacheKey = if isMutation then "mut_" .. entry.id else "grid_" .. entry.tier,
		mutationId = entry.id,
	}
end

local function isCardDiscovered(card)
	if card.kind == "mutation" then
		return mutationsFound[card.entry.id] == true
	end
	return discovered[tostring(card.entry.tier)] == true
end

local function applyCardState(card)
	local entry = card.entry
	local isDiscovered = isCardDiscovered(card)

	card.root.BackgroundColor3 = if isDiscovered then CARD else CARD_LOCKED
	card.status.TextColor3 = if isDiscovered then GREEN else Color3.fromRGB(96, 112, 150)
	card.badgeStroke.Color = if isDiscovered then entry.accent else RIM_SOFT
	if card.kind == "mutation" then
		-- Names and odds stay visible so players know what to hunt for.
		card.name.Text = entry.name
		card.name.TextColor3 = if isDiscovered then entry.accent else TEXT_DIM
		card.stat.Text = oddsText(entry.oneIn)
		card.stat.TextColor3 = if isDiscovered then GOLD else Color3.fromRGB(110, 124, 160)
		card.status.Text = if isDiscovered then "✓ DISCOVERED" else "NOT FOUND YET"
		card.badge.TextColor3 = RARITY_COLORS[entry.rarity] or TEXT
		card.newBadge.Visible = isDiscovered and mutationNew[entry.id] == true
	else
		card.name.Text = if isDiscovered then entry.name else "???"
		card.name.TextColor3 = if isDiscovered then TEXT else TEXT_DIM
		card.stat.Text = if isDiscovered then Format.Power(entry.power) else "- - -"
		card.stat.TextColor3 = if isDiscovered then GOLD else Color3.fromRGB(78, 94, 132)
		card.status.Text = if isDiscovered then "✓ DISCOVERED" else "NOT DISCOVERED"
		card.newBadge.Visible = isDiscovered and newFlags[tostring(entry.tier)] == true
	end

	-- A silhouette that has just been discovered must be rebuilt in colour.
	if card.populated and card.populatedLocked and isDiscovered then
		local key = card.cacheKey
		local world = viewportModels[key]
		if world then world:Destroy() end
		viewportModels[key] = nil
		viewportInfo[card.viewport] = nil
		for _, child in ipairs(card.viewport:GetChildren()) do
			if child:IsA("WorldModel") or child:IsA("Camera") then child:Destroy() end
		end
		card.populated = false
	end
end

for order, entry in ipairs(entries) do
	local card = makeCard(entry, order)
	cards[entry.tier] = card
	applyCardState(card)
end

for order, entry in ipairs(mutationEntries) do
	local card = makeCard(entry, 1000 + order)
	card.root.Visible = false
	cards["M_" .. entry.id] = card
	applyCardState(card)
end

-- ===================== VISIBILITY =====================
local visibilityClock = 0

local function refreshVisibility()
	if not panel.Visible then return end
	local top = scroll.AbsolutePosition.Y
	local bottom = top + scroll.AbsoluteSize.Y
	table.clear(activeViewports)

	for _, card in pairs(cards) do
		if card.root.Visible then
			local cardTop = card.root.AbsolutePosition.Y
			local cardBottom = cardTop + card.root.AbsoluteSize.Y
			local inView = cardBottom > top - 120 and cardTop < bottom + 120

			if inView and not card.populated then
				local isDiscovered = isCardDiscovered(card)
				local world = populateViewport(card.viewport, card.entry.tier, not isDiscovered, card.cacheKey, card.mutationId)
				card.populated = true
				card.populatedLocked = not isDiscovered

				local fallback = card.viewport:FindFirstChild("Fallback")
				if fallback then
					fallback.Visible = world == nil
					if world == nil then
						warn("[CosmicIndex] No model for T" .. card.entry.tier
							.. " in ReplicatedStorage.BlackHoleCompleteModels")
					end
				end
			end

			card.viewport.Visible = inView
			if inView then table.insert(activeViewports, card.viewport) end
		else
			card.viewport.Visible = false
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	if not panel.Visible then return end
	visibilityClock -= dt
	if visibilityClock <= 0 then
		visibilityClock = 0.1
		refreshVisibility()
	end
	for _, viewport in ipairs(activeViewports) do
		spinViewport(viewport, dt)
	end
	if detailSpinTarget then
		spinViewport(detailSpinTarget, dt)
	end
end)

-- ===================== FILTER / SEARCH =====================
function refreshGrid()
	local query = searchBox.Text:lower():gsub("^%s+", ""):gsub("%s+$", "")
	local shown = 0
	local page = if currentFilter == "MUTATIONS" then "mutation" else "tier"

	for _, card in pairs(cards) do
		local entry = card.entry
		local isDiscovered = isCardDiscovered(card)

		local passesFilter = card.kind == page and (
			page == "mutation"
				or currentFilter == "ALL"
				or (currentFilter == "DISCOVERED" and isDiscovered)
				or (currentFilter == "UNDISCOVERED" and not isDiscovered))

		local passesSearch = true
		if query ~= "" then
			local haystack
			if card.kind == "mutation" then
				haystack = entry.name:lower() .. " " .. entry.rarity:lower()
			else
				haystack = ("t%d %d"):format(entry.tier, entry.tier)
				if isDiscovered then haystack = haystack .. " " .. entry.name:lower() end
			end
			passesSearch = haystack:find(query, 1, true) ~= nil
		end

		local visible = passesFilter and passesSearch
		card.root.Visible = visible
		if visible then shown += 1 end
	end

	emptyState.Visible = shown == 0
	visibilityClock = 0
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	refreshGrid()
end)

-- ===================== DETAIL =====================
local detail = Instance.new("Frame")
detail.AnchorPoint = Vector2.new(0.5, 0.5)
detail.Position = UDim2.fromScale(0.5, 0.5)
detail.Size = if IS_TOUCH then UDim2.fromScale(0.92, 0.8) else UDim2.fromScale(0.64, 0.74)
detail.BackgroundColor3 = PANEL
detail.BackgroundTransparency = 0.04
detail.BorderSizePixel = 0
detail.Visible = false
detail.ZIndex = 62
detail.Parent = panel
GuiStyle.Corner(detail, 0.04)
GuiStyle.Stroke(detail, RIM, 3)

local detailScale = Instance.new("UIScale")
detailScale.Parent = detail

local detailViewport = Instance.new("ViewportFrame")
detailViewport.Position = UDim2.new(0, 18, 0, 18)
detailViewport.Size = UDim2.new(0.44, -18, 1, -36)
detailViewport.BackgroundColor3 = Color3.fromRGB(9, 13, 32)
detailViewport.BorderSizePixel = 0
detailViewport.Ambient = Color3.fromRGB(200, 210, 240)
detailViewport.LightColor = Color3.fromRGB(255, 255, 255)
detailViewport.LightDirection = Vector3.new(-0.4, -0.8, -0.5)
detailViewport.ZIndex = 63
detailViewport.Parent = detail
GuiStyle.Corner(detailViewport, 0.06)

local detailName = Instance.new("TextLabel")
detailName.Position = UDim2.new(0.46, 8, 0, 28)
detailName.Size = UDim2.new(0.52, -20, 0, 42)
detailName.BackgroundTransparency = 1
detailName.Font = FONT
detailName.TextScaled = true
detailName.TextXAlignment = Enum.TextXAlignment.Left
detailName.TextColor3 = TEXT
detailName.ZIndex = 64
detailName.Parent = detail
GuiStyle.TextStroke(detailName, 3)
local detailNameCap = Instance.new("UITextSizeConstraint")
detailNameCap.MaxTextSize = 32
detailNameCap.Parent = detailName

local detailBadge = Instance.new("TextLabel")
detailBadge.Position = UDim2.new(0.46, 8, 0, 74)
detailBadge.Size = UDim2.fromOffset(62, 28)
detailBadge.BackgroundColor3 = Color3.fromRGB(30, 44, 92)
detailBadge.Font = FONT
detailBadge.TextScaled = true
detailBadge.TextColor3 = TEXT
detailBadge.ZIndex = 64
detailBadge.Parent = detail
GuiStyle.Corner(detailBadge, 1)
local detailBadgeStroke = GuiStyle.Stroke(detailBadge, RIM, 2)
local detailBadgeCap = Instance.new("UITextSizeConstraint")
detailBadgeCap.MaxTextSize = 18
detailBadgeCap.Parent = detailBadge

local detailDesc = Instance.new("TextLabel")
detailDesc.Position = UDim2.new(0.46, 8, 0, 118)
detailDesc.Size = UDim2.new(0.52, -20, 0, 132)
detailDesc.BackgroundTransparency = 1
detailDesc.Font = FONT
detailDesc.TextSize = 17
detailDesc.TextWrapped = true
detailDesc.TextXAlignment = Enum.TextXAlignment.Left
detailDesc.TextYAlignment = Enum.TextYAlignment.Top
detailDesc.TextColor3 = TEXT_DIM
detailDesc.ZIndex = 64
detailDesc.Parent = detail

local detailStatCard = Instance.new("Frame")
detailStatCard.Position = UDim2.new(0.46, 8, 0, 260)
detailStatCard.Size = UDim2.new(0.52, -20, 0, 62)
detailStatCard.BackgroundColor3 = CARD
detailStatCard.BorderSizePixel = 0
detailStatCard.ZIndex = 64
detailStatCard.Parent = detail
GuiStyle.Corner(detailStatCard, 0.18)
GuiStyle.Stroke(detailStatCard, RIM_SOFT, 2)

local detailStatLabel = Instance.new("TextLabel")
detailStatLabel.Position = UDim2.fromOffset(14, 8)
detailStatLabel.Size = UDim2.new(1, -28, 0, 16)
detailStatLabel.BackgroundTransparency = 1
detailStatLabel.Text = "STELLAR POWER"
detailStatLabel.Font = FONT
detailStatLabel.TextScaled = true
detailStatLabel.TextXAlignment = Enum.TextXAlignment.Left
detailStatLabel.TextColor3 = TEXT_DIM
detailStatLabel.ZIndex = 65
detailStatLabel.Parent = detailStatCard
local dsCap = Instance.new("UITextSizeConstraint")
dsCap.MaxTextSize = 13
dsCap.Parent = detailStatLabel

local detailStatValue = Instance.new("TextLabel")
detailStatValue.Position = UDim2.fromOffset(14, 26)
detailStatValue.Size = UDim2.new(1, -28, 0, 28)
detailStatValue.BackgroundTransparency = 1
detailStatValue.Font = FONT
detailStatValue.TextScaled = true
detailStatValue.TextXAlignment = Enum.TextXAlignment.Left
detailStatValue.TextColor3 = GOLD
detailStatValue.ZIndex = 65
detailStatValue.Parent = detailStatCard
GuiStyle.TextStroke(detailStatValue, 2)
local dsvCap = Instance.new("UITextSizeConstraint")
dsvCap.MaxTextSize = 26
dsvCap.Parent = detailStatValue

local detailStatus = Instance.new("TextLabel")
detailStatus.Position = UDim2.new(0.46, 8, 0, 332)
detailStatus.Size = UDim2.new(0.52, -20, 0, 24)
detailStatus.BackgroundTransparency = 1
detailStatus.Font = FONT
detailStatus.TextScaled = true
detailStatus.TextXAlignment = Enum.TextXAlignment.Left
detailStatus.ZIndex = 64
detailStatus.Parent = detail
local dstCap = Instance.new("UITextSizeConstraint")
dstCap.MaxTextSize = 18
dstCap.Parent = detailStatus

local detailBack = Instance.new("TextButton")
detailBack.AnchorPoint = Vector2.new(1, 1)
detailBack.Position = UDim2.new(1, -18, 1, -18)
detailBack.Size = UDim2.fromOffset(140, 44)
detailBack.BackgroundColor3 = RIM
detailBack.AutoButtonColor = false
detailBack.Text = "BACK"
detailBack.Font = FONT
detailBack.TextScaled = true
detailBack.TextColor3 = TEXT
detailBack.ZIndex = 65
detailBack.Parent = detail
GuiStyle.Corner(detailBack, 0.3)
GuiStyle.Stroke(detailBack, Color3.fromRGB(18, 40, 96), 3)
GuiStyle.TextStroke(detailBack, 2.5)
local backPad = Instance.new("UIPadding")
backPad.PaddingTop = UDim.new(0, 10)
backPad.PaddingBottom = UDim.new(0, 10)
backPad.Parent = detailBack

local detailWorld

local function showDetailViewport(tier, locked, mutationId)
	-- Detail uses its own cache slot so grid cards keep their models.
	if detailWorld then detailWorld:Destroy() end
	viewportModels["detail"] = nil
	viewportInfo[detailViewport] = nil
	for _, child in ipairs(detailViewport:GetChildren()) do
		if child:IsA("WorldModel") or child:IsA("Camera") then child:Destroy() end
	end
	detailWorld = populateViewport(detailViewport, tier, locked, "detail", mutationId)
	detailSpinTarget = detailViewport

	detail.Visible = true
	detailScale.Scale = 0.97
	TweenService:Create(detailScale, MOTION.Normal, { Scale = 1 }):Play()
end

local function ownedWithMutation(id)
	local count = 0
	for _, hole in ipairs(CollectionService:GetTagged("BlackHole")) do
		if hole:GetAttribute("OwnerUserId") == player.UserId and hole:GetAttribute("Mutation") == id then
			count += 1
		end
	end
	return count
end

function showMutationDetail(entry)
	local found = mutationsFound[entry.id] == true
	if mutationNew[entry.id] then
		mutationNew[entry.id] = nil
		local card = cards["M_" .. entry.id]
		if card then card.newBadge.Visible = false end
	end

	detailName.Text = entry.name
	detailName.TextColor3 = if found then entry.accent else TEXT
	detailBadge.Text = rarityName(entry.rarity)
	detailBadge.Size = UDim2.fromOffset(124, 28)
	detailBadge.TextColor3 = RARITY_COLORS[entry.rarity] or TEXT
	detailBadgeStroke.Color = if found then entry.accent else RIM_SOFT
	detailDesc.Text = (if found then entry.description
		else "Not found yet. Every merge has a chance to roll it. " .. entry.description)
		.. "\n\nBonus: " .. (if MutationConfig and MutationConfig.BonusText then MutationConfig.BonusText(entry.id, ", ") else "")
	detailStatLabel.Text = "CHANCE PER MERGE"
	detailStatValue.Text = oddsText(entry.oneIn)

	local owned = if found then ownedWithMutation(entry.id) else 0
	detailStatus.Text = if not found then "NOT FOUND YET"
		elseif owned > 0 then ("✓ DISCOVERED  ·  YOU OWN %d"):format(owned)
		else "✓ DISCOVERED"
	detailStatus.TextColor3 = if found then GREEN else Color3.fromRGB(96, 112, 150)

	showDetailViewport(entry.tier, not found, entry.id)
end

function showDetail(entry)
	local isDiscovered = discovered[tostring(entry.tier)] == true
	detailName.TextColor3 = TEXT
	detailBadge.Size = UDim2.fromOffset(62, 28)
	detailBadge.TextColor3 = TEXT
	detailStatLabel.Text = "STELLAR POWER"

	if newFlags[tostring(entry.tier)] then
		newFlags[tostring(entry.tier)] = nil
		table.insert(pendingSeen, entry.tier)
		local card = cards[entry.tier]
		if card then card.newBadge.Visible = false end
	end

	detailName.Text = if isDiscovered then entry.name else "UNKNOWN OBJECT"
	detailBadge.Text = "T" .. entry.tier
	detailBadgeStroke.Color = if isDiscovered then entry.accent else RIM_SOFT
	detailDesc.Text = if isDiscovered then entry.description
		else "Continue progressing to uncover this cosmic object."
	detailStatValue.Text = if isDiscovered then Format.Power(entry.power) else "- - -"
	detailStatus.Text = if isDiscovered then "✓ DISCOVERED" else "NOT DISCOVERED"
	detailStatus.TextColor3 = if isDiscovered then GREEN else Color3.fromRGB(96, 112, 150)

	showDetailViewport(entry.tier, not isDiscovered)
end

local function hideDetail()
	detail.Visible = false
	detailSpinTarget = nil
end

detailBack.Activated:Connect(function()
	play(tickSound)
	hideDetail()
end)

-- ===================== PROGRESS =====================
function refreshProgress(animate)
	local mutationPage = currentFilter == "MUTATIONS"
	local total, count = 0, 0
	if mutationPage then
		total = #mutationEntries
		for _, entry in ipairs(mutationEntries) do
			if mutationsFound[entry.id] then count += 1 end
		end
		countLabel.Text = string.format("%d / %d MUTATIONS", count, total)
	else
		total = #entries
		for _, entry in ipairs(entries) do
			if discovered[tostring(entry.tier)] then count += 1 end
		end
		countLabel.Text = string.format("%d / %d DISCOVERED", count, total)
	end
	local ratio = if total > 0 then count / total else 0
	if animate then
		TweenService:Create(progressFill, TweenInfo.new(0.5, Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out), { Size = UDim2.fromScale(ratio, 1) }):Play()
	else
		progressFill.Size = UDim2.fromScale(ratio, 1)
	end
	progressFill.BackgroundColor3 = if ratio >= 1 then GOLD elseif mutationPage then MUTATION_ACCENT else ACCENT
end

-- ===================== OPEN / CLOSE =====================
local isOpen, busy = false, false

if GuiManager then
	GuiManager:Register("CosmicIndex", panel, {
		BlurSize = 12,
		OpenScale = 1, OpenOvershootScale = 1,
		CloseBounceScale = 1, CloseScale = 1,
		CloseBounceTween = TweenInfo.new(0),
		CloseShrinkTween = TweenInfo.new(0),
	})
end

local function openIndex()
	if isOpen or busy then return end
	isOpen, busy = true, true


	if GuiManager then GuiManager:Open("CosmicIndex") end
	panel.Visible = true
	dim.Visible = true
	hideDetail()

	dim.BackgroundTransparency = 1
	panel.BackgroundTransparency = 1
	panelScale.Scale = 0.97
	progressFill.Size = UDim2.fromScale(0, 1)

	TweenService:Create(dim, MOTION.Normal, { BackgroundTransparency = 0.66 }):Play()
	TweenService:Create(panel, MOTION.Panel, { BackgroundTransparency = 0.12 }):Play()
	TweenService:Create(panelScale, MOTION.Panel, { Scale = 1 }):Play()

	refreshColumns()
	refreshGrid()
	task.delay(0.15, function()
		if isOpen then refreshProgress(true) end
	end)
	task.delay(0.3, function() busy = false end)
end

local function closeIndex()
	if not isOpen or busy then return end
	if GuiManager then GuiManager:BeginClose("CosmicIndex") end
	isOpen, busy = false, true

	if #pendingSeen > 0 then
		local remotes = ReplicatedStorage:FindFirstChild("IndexRemotes")
		if remotes and remotes:FindFirstChild("MarkSeen") then
			remotes.MarkSeen:FireServer(pendingSeen)
		end
		pendingSeen = {}
	end

	TweenService:Create(dim, MOTION.Close, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(panel, MOTION.Close, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(panelScale, MOTION.Close, { Scale = 0.97 }):Play()

	task.delay(0.21, function()
		busy = false
		if isOpen then return end
		panel.Visible = false
		dim.Visible = false
		hideDetail()
		if GuiManager then GuiManager:Close("CosmicIndex") end
	end)
end

closeBtn.MouseEnter:Connect(function()
	TweenService:Create(closeScale, MOTION.Fast, { Scale = 1.08 }):Play()
end)
closeBtn.MouseLeave:Connect(function()
	TweenService:Create(closeScale, MOTION.Fast, { Scale = 1 }):Play()
end)
if GuiManager and GuiManager.SetBackHandler then
	GuiManager:SetBackHandler("CosmicIndex", function() closeIndex() end)
end

closeBtn.Activated:Connect(function()
	play(tickSound)
	closeIndex()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.Escape or not isOpen then return end
	if detail.Visible then hideDetail() else closeIndex() end
end)

panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if not panel.Visible and isOpen then
		isOpen = false
		dim.Visible = false
		hideDetail()
	end
end)

-- ===================== HOOK THE EXISTING HUD BUTTON =====================
-- MainHUD destroys and recreates its own ScreenGui on startup, so a one-shot
-- lookup can end up holding a dead instance. Scan all of PlayerGui, and re-hook
-- whenever a new Index button appears.
-- Strong keys: a weak table can drop a live button and hook it twice, which
-- opens and instantly closes the Index on one click.
local hooked = {}
local liveButtons = 0

local function toggleIndex()
	if isOpen then closeIndex() else openIndex() end
end

local function tryHook(instance)
	if hooked[instance] then return false end
	if not (instance:IsA("TextButton") or instance:IsA("ImageButton")) then return false end
	if instance.Name:lower() ~= "index" then return false end
	if instance:IsDescendantOf(gui) then return false end

	hooked[instance] = true
	liveButtons += 1
	instance.Activated:Connect(toggleIndex)

	instance.Destroying:Connect(function()
		if hooked[instance] then
			hooked[instance] = nil
			liveButtons -= 1
		end
	end)

	print("[CosmicIndex] Hooked Index button:", instance:GetFullName())
	return true
end

local function scanAll()
	for _, instance in ipairs(playerGui:GetDescendants()) do
		tryHook(instance)
	end
end

playerGui.DescendantAdded:Connect(tryHook)

task.spawn(function()
	local deadline = os.clock() + 25

	-- The button may be hooked by DescendantAdded instead of by a scan, so the
	-- test is "is a button hooked", not "did this scan find one".
	while os.clock() < deadline do
		scanAll()
		if liveButtons > 0 then return end
		task.wait(0.5)
	end

	warn("[CosmicIndex] No button named 'Index' found. Buttons present in PlayerGui:")
	for _, instance in ipairs(playerGui:GetDescendants()) do
		if (instance:IsA("TextButton") or instance:IsA("ImageButton"))
			and not instance:IsDescendantOf(gui) then
			warn("   ", instance.Name, "  <-", instance:GetFullName())
		end
	end
end)

-- ===================== SERVER DATA =====================
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("IndexRemotes", 25)
	if not remotes then
		warn("[CosmicIndex] IndexRemotes missing. Add IndexDiscoveryServer to ServerScriptService.")
		return
	end

	remotes:WaitForChild("IndexUpdated").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		discovered = type(payload.discovered) == "table" and payload.discovered or {}
		newFlags = type(payload.new) == "table" and payload.new or {}

		for _, card in pairs(cards) do
			applyCardState(card)
		end

		refreshGrid()
		refreshProgress(panel.Visible)
	end)
end)

-- ===================== MUTATION DISCOVERIES =====================
-- Set by BlackHoleSystemServer on join and after each new discovery.
local mutationsLoaded = false

local function readMutations()
	local raw = player:GetAttribute("MutationsDiscovered")
	local found = {}
	if type(raw) == "string" then
		for id in string.gmatch(raw, "[^,]+") do
			found[id] = true
		end
	end
	-- Anything that appears after the first load is new this session.
	if mutationsLoaded then
		for id in pairs(found) do
			if not mutationsFound[id] then mutationNew[id] = true end
		end
	end
	mutationsLoaded = raw ~= nil
	mutationsFound = found

	for _, card in pairs(cards) do
		if card.kind == "mutation" then applyCardState(card) end
	end
	if panel.Visible then refreshGrid() end
	refreshProgress(panel.Visible)
end

player:GetAttributeChangedSignal("MutationsDiscovered"):Connect(readMutations)
readMutations()

refreshProgress(false)