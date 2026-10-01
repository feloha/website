-- InventoryClient (LocalScript in StarterPlayerScripts)  -- NEW
-- The Inventory window (side menu > Inventory), in the same style as the Store
-- and Playtime Rewards windows.
--
--   STORED     black holes kept safe in your Inventory: DEPLOY puts one back on
--              your base (same black hole, same mutation)
--   ON BASE    black holes on your base: STORE keeps one safe
--   COSMETICS  looks bought with Gems (nameplate border, pickup trail, sparkle)
--
-- Search by name or mutation, sort by tier / rarity / newest, filter mutated /
-- normal / favorites. Tap a card for details, FAVORITE to lock a black hole
-- so it can never be merged by accident.
--
-- Every action is checked and done by the server (BlackHoleSystemServer for
-- black holes, ProgressionService for Gems and cosmetics). This window only
-- shows what the server says. Uses GuiManager, so opening another menu closes
-- this one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SizeVariants = require(ReplicatedStorage:WaitForChild("SizeVariantConfig"))
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GuiManager = require(ReplicatedStorage:WaitForChild("GuiManager"))
local GuiStyle = require(ReplicatedStorage:WaitForChild("GuiStyle"))
local TierConfig = require(ReplicatedStorage:WaitForChild("BlackHoleTierConfig"))
local MutationConfig = require(ReplicatedStorage:WaitForChild("MutationConfig"))

local function optional(name)
	local module = ReplicatedStorage:FindFirstChild(name)
	local ok, result = pcall(function() return module and require(module) end)
	return if ok and type(result) == "table" then result else nil
end

local GemsConfig = optional("GemsConfig")
local InventoryConfig = optional("InventoryConfig") or { Capacity = 30 }
local UiResponsive = optional("UiResponsive")
local Sounds = optional("GameSounds")
local HudStack = optional("HudStack")
local Coordinator = optional("PresentationCoordinator")

local FONT = GuiStyle.FONT
local COL = GuiStyle.COL
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GEM_BLUE = if GemsConfig then GemsConfig.Color else Color3.fromRGB(80, 190, 255)
local STATE_COLORS = {
	Stored = Color3.fromRGB(96, 150, 255),
	Deployed = Color3.fromRGB(70, 210, 110),
	Carried = Color3.fromRGB(255, 180, 60),
}
local FAVORITE_GOLD = Color3.fromRGB(255, 205, 70)

local old = playerGui:FindFirstChild("InventoryUI")
if old then old:Destroy() end

local function sfx(slot, priority)
	if not Sounds then return end
	local volume = if Coordinator and priority then Coordinator.SoundVolume(priority) else 1
	if volume <= 0 then return end
	pcall(Sounds.Play, slot, { volume = volume })
end

-- ===================== REMOTES =====================
local inventoryRemotes = ReplicatedStorage:WaitForChild("InventoryRemotes", 30)
local requestRemote = inventoryRemotes and inventoryRemotes:WaitForChild("Request", 10)
local noticeRemote = inventoryRemotes and inventoryRemotes:WaitForChild("Notice", 10)
local progressionRemotes = ReplicatedStorage:WaitForChild("ProgressionRemotes", 30)
local cosmeticsRemote = progressionRemotes and progressionRemotes:WaitForChild("Cosmetics", 10)
local gemsEarned = progressionRemotes and progressionRemotes:WaitForChild("GemsEarned", 10)

if not requestRemote then
	warn("[InventoryClient] ReplicatedStorage.InventoryRemotes is missing: update BlackHoleSystemServer. The Inventory can't store or deploy.")
end
if not cosmeticsRemote then
	warn("[InventoryClient] ProgressionRemotes.Cosmetics is missing: update ProgressionService. Cosmetics can't be bought.")
end

-- ===================== TEXT / BUTTON HELPERS =====================
local function makeText(parent, props)
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "Text"
	label.BackgroundTransparency = 1
	label.AnchorPoint = props.AnchorPoint or Vector2.zero
	label.Position = props.Position or UDim2.new()
	label.Size = props.Size or UDim2.fromOffset(100, 30)
	label.Text = props.Text or ""
	label.Font = FONT
	label.TextWrapped = props.TextWrapped or false
	label.TextColor3 = props.TextColor3 or COL.Light
	label.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center
	label.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	label.ZIndex = props.ZIndex or 12
	label.TextScaled = true
	label.Parent = parent
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = props.MinTextSize or 11
	constraint.MaxTextSize = props.MaxTextSize or 28
	constraint.Parent = label
	if props.Stroke ~= false then
		GuiStyle.TextStroke(label, props.StrokeThickness or 2)
	end
	if props.Gloss then
		GuiStyle.GlossText(label)
	end
	return label
end

local function paint(button, color)
	local fill = button:FindFirstChild("Fill")
	if fill then
		fill.Color = ColorSequence.new(color:Lerp(WHITE, 0.25), color:Lerp(BLACK, 0.2))
	end
	button:SetAttribute("BaseColor", color)
end

-- A chunky cartoon button. Returns button, label.
local function makeButton(parent, props)
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	button.Position = props.Position or UDim2.new()
	button.Size = props.Size or UDim2.fromOffset(120, 40)
	button.BackgroundColor3 = WHITE
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = props.ZIndex or 14
	button.Parent = parent
	GuiStyle.Corner(button, props.Radius or 0.28)
	GuiStyle.Stroke(button, COL.Outline, 3)
	local fill = Instance.new("UIGradient")
	fill.Name = "Fill"
	fill.Rotation = 90
	fill.Parent = button
	paint(button, props.Color or COL.Green)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	GuiStyle.AddHoverScale(button, scale, 1.05)
	local label = makeText(button, {
		Name = "Label", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.7, 0), Text = props.Text or "", ZIndex = button.ZIndex + 1,
		StrokeThickness = 2.5, MinTextSize = 10, MaxTextSize = props.MaxTextSize or 22,
	})
	button.MouseEnter:Connect(function() sfx("UI_HOVER_ID") end)
	return button, label
end

local function setEnabled(button, enabled)
	button.Active = enabled
	button:SetAttribute("Enabled", enabled)
	local base = button:GetAttribute("BaseColor") or COL.Green
	local fill = button:FindFirstChild("Fill")
	if fill then
		local color = if enabled then base else Color3.fromRGB(96, 104, 138)
		fill.Color = ColorSequence.new(color:Lerp(WHITE, 0.25), color:Lerp(BLACK, 0.2))
	end
end

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.Name = props.Name or "Frame"
	f.AnchorPoint = props.AnchorPoint or Vector2.zero
	f.Position = props.Position or UDim2.new()
	f.Size = props.Size or UDim2.fromScale(1, 1)
	f.BackgroundColor3 = props.Color or COL.Card
	f.BackgroundTransparency = props.Transparency or 0
	f.BorderSizePixel = 0
	f.ZIndex = props.ZIndex or 11
	f.Parent = parent
	if props.Radius then GuiStyle.Corner(f, props.Radius) end
	return f
end

-- Small drawn gem (the Gems currency).
local function drawGem(parent, z)
	local holder = frame(parent, { Name = "Gem", Transparency = 1, ZIndex = z })
	local body = frame(holder, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromScale(0.6, 0.6), Color = GEM_BLUE, ZIndex = z, Radius = 0.2 })
	body.Rotation = 45
	GuiStyle.Stroke(body, COL.Outline, 2)
	local top = frame(holder, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.fromScale(0.72, 0.2), Color = Color3.fromRGB(190, 240, 255), ZIndex = z + 1, Radius = 0.3 })
	GuiStyle.Stroke(top, COL.Outline, 2)
	return holder
end

-- A small black hole drawn from shapes: tier colour disk, mutation colour rim.
local function drawHole(parent, tier, mutationId, z)
	local data = TierConfig.GetTier(tier)
	local tierColor = (data and (data.DiskGlowColor or data.GlowColor)) or Color3.fromRGB(170, 120, 255)
	local mutation = MutationConfig.Get(mutationId)
	local band = if mutation then mutation.Band else tierColor
	local rim = if mutation then mutation.Rim else tierColor:Lerp(WHITE, 0.45)
	local holder = frame(parent, { Name = "HoleIcon", Transparency = 1, ZIndex = z })
	local glow = frame(holder, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.96, 0.96), Color = if mutation then mutation.Main else tierColor, Transparency = 0.78, ZIndex = z, Radius = 1 })
	local _ = glow
	local disk = frame(holder, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.98, 0.34), Transparency = 1, ZIndex = z + 1, Radius = 1 })
	disk.Rotation = -14
	local diskStroke = GuiStyle.Stroke(disk, band, 5)
	diskStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local core = frame(holder, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.46, 0.46), Color = BLACK, ZIndex = z + 2, Radius = 1 })
	GuiStyle.Stroke(core, rim, 3)
	local front = frame(holder, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromScale(0.6, 0.05), Color = band:Lerp(WHITE, 0.4), ZIndex = z + 3, Radius = 1 })
	front.Rotation = -14
	return holder
end

local function rarityColor(mutation)
	local colors = MutationConfig.RarityColors or {}
	return if mutation then (colors[mutation.Rarity] or mutation.Main) else nil
end

-- ===================== WINDOW =====================
local gui = Instance.new("ScreenGui")
gui.Name = "InventoryUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
gui.IgnoreGuiInset = true
if UiResponsive and UiResponsive.UseModalInsets then UiResponsive.UseModalInsets(gui) end   -- below the top bar
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local popupGroup = frame(gui, { Name = "InventoryPopupGroup", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Transparency = 1, ZIndex = 10 })
popupGroup.Visible = false

local popup = frame(popupGroup, { Name = "InventoryPopup", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(900, 590), Color = COL.Body, Transparency = 0.22, ZIndex = 10 })
popup.Active = true
GuiStyle.Corner(popup, 0.035)
GuiStyle.Stroke(popup, COL.Outline, 4)
GuiStyle.Gradient(popup, Color3.fromRGB(34, 42, 86), Color3.fromRGB(10, 13, 30))
local popupScale = Instance.new("UIScale")
popupScale.Name = "ResponsiveScale"
popupScale.Parent = popup

GuiManager:Register("Inventory", popupGroup, {
	BlurSize = 12,
	OpenScale = 0.9,
	OpenOvershootScale = 1.02,
	CloseBounceScale = 1.01,
	CloseScale = 0.9,
})

-- Header -----------------------------------------------------------------------
local HEADER_H = 76
local header = frame(popup, { Name = "Header", Size = UDim2.new(1, 0, 0, HEADER_H), Color = Color3.fromRGB(28, 36, 76), ZIndex = 20, Radius = 0.18 })
GuiStyle.Stroke(header, COL.Outline, 4)
GuiStyle.Gradient(header, Color3.fromRGB(150, 90, 55), Color3.fromRGB(60, 34, 30))

do
	local icon = frame(header, { Name = "HeaderIcon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 18, 0.5, 0), Size = UDim2.fromOffset(52, 52), Transparency = 1, ZIndex = 22 })
	local body = frame(icon, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.64), Size = UDim2.fromScale(0.86, 0.5), Color = Color3.fromRGB(150, 82, 40), ZIndex = 22, Radius = 0.18 })
	GuiStyle.Stroke(body, COL.Outline, 2.5)
	local lid = frame(icon, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromScale(0.92, 0.26), Color = Color3.fromRGB(190, 110, 55), ZIndex = 23, Radius = 0.35 })
	GuiStyle.Stroke(lid, COL.Outline, 2.5)
	frame(icon, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.94, 0.08), Color = FAVORITE_GOLD, ZIndex = 24, Radius = 0.3 })
	local lock = frame(icon, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromScale(0.2, 0.24), Color = FAVORITE_GOLD, ZIndex = 25, Radius = 0.3 })
	GuiStyle.Stroke(lock, COL.Outline, 2)
end

makeText(header, {
	Name = "Title", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 82, 0.5, 0),
	Size = UDim2.new(0.34, 0, 0.62, 0), Text = "Inventory", TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 22, StrokeThickness = 3, Gloss = true, MinTextSize = 22, MaxTextSize = 44,
})

local capacityPill = frame(header, { Name = "Capacity", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -86, 0.5, 0), Size = UDim2.fromOffset(210, 40), Color = Color3.fromRGB(10, 14, 32), Transparency = 0.25, ZIndex = 22, Radius = 0.5 })
GuiStyle.Stroke(capacityPill, COL.Outline, 2.5)
local capacityText = makeText(capacityPill, {
	Name = "Text", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0.9, 0, 0.62, 0), Text = "0 / 30 stored", ZIndex = 23, TextColor3 = COL.Muted, MaxTextSize = 20,
})

local closeButton = GuiStyle.MakePlaytimeX(header, function() end)

-- Tabs ---------------------------------------------------------------------------
local TABS_Y = HEADER_H + 10
local tabRow = frame(popup, { Name = "Tabs", Position = UDim2.fromOffset(18, TABS_Y), Size = UDim2.new(1, -36, 0, 44), Transparency = 1, ZIndex = 12 })
local tabButtons = {}
local TAB_DEFS = {
	{ Id = "stored", Text = "STORED", Color = STATE_COLORS.Stored },
	{ Id = "base", Text = "ON BASE", Color = STATE_COLORS.Deployed },
	{ Id = "cosmetics", Text = "COSMETICS", Color = GEM_BLUE },
}
for index, def in ipairs(TAB_DEFS) do
	local button = makeButton(tabRow, {
		Name = "Tab_" .. def.Id, Position = UDim2.fromOffset((index - 1) * 150, 0), Size = UDim2.fromOffset(142, 44),
		Text = def.Text, Color = def.Color, ZIndex = 13, MaxTextSize = 20,
	})
	tabButtons[def.Id] = button
end

local gemsPill = frame(tabRow, { Name = "Gems", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(150, 40), Color = Color3.fromRGB(10, 18, 40), Transparency = 0.15, ZIndex = 13, Radius = 0.5 })
GuiStyle.Stroke(gemsPill, GEM_BLUE, 2.5)
do
	local gemSlot = frame(gemsPill, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(28, 28), Transparency = 1, ZIndex = 14 })
	drawGem(gemSlot, 14)
end
local gemsText = makeText(gemsPill, {
	Name = "Amount", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 42, 0.5, 0), Size = UDim2.new(1, -52, 0.62, 0),
	Text = "0", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(170, 228, 255), ZIndex = 14, MaxTextSize = 22,
})

-- Tools (search / sort / filter) ----------------------------------------------
local TOOLS_Y = TABS_Y + 52
local toolRow = frame(popup, { Name = "Tools", Position = UDim2.fromOffset(18, TOOLS_Y), Size = UDim2.new(1, -36, 0, 38), Transparency = 1, ZIndex = 12 })

local searchBox = Instance.new("TextBox")
searchBox.Name = "Search"
searchBox.Size = UDim2.fromOffset(220, 38)
searchBox.BackgroundColor3 = Color3.fromRGB(10, 14, 32)
searchBox.BackgroundTransparency = 0.1
searchBox.ClearTextOnFocus = false
searchBox.PlaceholderText = "Search name or mutation"
searchBox.PlaceholderColor3 = COL.Muted
searchBox.Text = ""
searchBox.Font = FONT
searchBox.TextSize = 18
searchBox.TextColor3 = COL.Light
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.ZIndex = 13
searchBox.Parent = toolRow
GuiStyle.Corner(searchBox, 0.3)
GuiStyle.Stroke(searchBox, COL.Outline, 2.5)
do
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = searchBox
end

local SORTS = {
	{ Id = "tier", Text = "SORT: TIER" },
	{ Id = "rarity", Text = "SORT: RARITY" },
	{ Id = "newest", Text = "SORT: NEWEST" },
}
local sortButton, sortLabel = makeButton(toolRow, {
	Name = "Sort", Position = UDim2.fromOffset(230, 0), Size = UDim2.fromOffset(150, 38), Text = SORTS[1].Text,
	Color = Color3.fromRGB(96, 104, 170), ZIndex = 13, MaxTextSize = 18,
})

local FILTERS = {
	{ Id = "all", Text = "ALL" },
	{ Id = "mutated", Text = "MUTATED" },
	{ Id = "normal", Text = "NORMAL" },
	{ Id = "favorites", Text = "🔒 FAVORITES" },
}
local filterButtons = {}
do
	local x = 390
	for _, def in ipairs(FILTERS) do
		local width = if def.Id == "favorites" then 136 elseif def.Id == "all" then 58 else 104
		local button = makeButton(toolRow, {
			Name = "Filter_" .. def.Id, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(width, 38),
			Text = def.Text, Color = Color3.fromRGB(70, 78, 120), ZIndex = 13, MaxTextSize = 16,
		})
		filterButtons[def.Id] = button
		x += width + 6
	end
end

-- Body ---------------------------------------------------------------------------
local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Items"
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 8
scroll.ScrollBarImageColor3 = COL.Cyan
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.ZIndex = 12
scroll.Parent = popup
if UiResponsive and UiResponsive.TouchScroll then UiResponsive.TouchScroll(scroll) end   -- easy thumb scrolling
do
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = scroll
end
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(150, 188)
grid.CellPadding = UDim2.fromOffset(12, 12)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = scroll

local emptyText = makeText(popup, {
	Name = "Empty", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(420, 80), Text = "",
	TextWrapped = true, TextColor3 = COL.Muted, ZIndex = 13, MaxTextSize = 22,
})

-- Detail panel ---------------------------------------------------------------------
local detail = frame(popup, { Name = "Detail", Color = Color3.fromRGB(14, 18, 40), Transparency = 0.05, ZIndex = 30, Radius = 0.05 })
GuiStyle.Stroke(detail, COL.Outline, 3)
detail.Active = true

local detailBack, _ = makeButton(detail, {
	Name = "Back", AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(84, 34),
	Text = "BACK", Color = Color3.fromRGB(96, 104, 170), ZIndex = 36, MaxTextSize = 16,
})

local previewHolder = frame(detail, { Name = "Preview", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(170, 170), Transparency = 1, ZIndex = 31 })
local previewHalo = frame(previewHolder, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.95, 0.95), Color = COL.Purple, Transparency = 0.8, ZIndex = 31, Radius = 1 })
local viewport = Instance.new("ViewportFrame")
viewport.Name = "Model"
viewport.Size = UDim2.fromScale(1, 1)
viewport.BackgroundTransparency = 1
viewport.Ambient = Color3.fromRGB(130, 130, 160)
viewport.LightDirection = Vector3.new(-0.3, -0.7, -0.6)
viewport.ZIndex = 32
viewport.Parent = previewHolder
local viewportCamera = Instance.new("Camera")
viewportCamera.FieldOfView = 40
viewportCamera.Parent = viewport
viewport.CurrentCamera = viewportCamera
local fallbackIcon = frame(previewHolder, { Name = "Fallback", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.8), Transparency = 1, ZIndex = 33 })

local detailName = makeText(detail, { Name = "Name", Position = UDim2.fromOffset(12, 190), Size = UDim2.new(1, -24, 0, 32), Text = "", ZIndex = 32, MaxTextSize = 28, Gloss = true, StrokeThickness = 3 })
local detailTier = makeText(detail, { Name = "Tier", Position = UDim2.fromOffset(12, 224), Size = UDim2.new(1, -24, 0, 22), Text = "", ZIndex = 32, TextColor3 = COL.Muted, MaxTextSize = 18 })
local detailMutation = makeText(detail, { Name = "Mutation", Position = UDim2.fromOffset(12, 250), Size = UDim2.new(1, -24, 0, 24), Text = "", ZIndex = 32, MaxTextSize = 20 })
local detailBonus = makeText(detail, { Name = "Bonus", Position = UDim2.fromOffset(12, 276), Size = UDim2.new(1, -24, 0, 18), Text = "", ZIndex = 32, TextColor3 = COL.Yellow, MaxTextSize = 15 })
local detailState = frame(detail, { Name = "State", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 302), Size = UDim2.fromOffset(150, 28), Color = STATE_COLORS.Stored, ZIndex = 32, Radius = 0.5 })
GuiStyle.Stroke(detailState, COL.Outline, 2)
local detailStateText = makeText(detailState, { Name = "Text", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.9, 0, 0.7, 0), Text = "STORED", ZIndex = 33, MaxTextSize = 16 })

local favoriteButton, favoriteLabel = makeButton(detail, {
	Name = "Favorite", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 340), Size = UDim2.new(1, -36, 0, 40),
	Text = "LOCK AS FAVORITE", Color = Color3.fromRGB(96, 104, 170), ZIndex = 33, MaxTextSize = 18,
})
local actionButton, actionLabel = makeButton(detail, {
	Name = "Action", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 388), Size = UDim2.new(1, -36, 0, 48),
	Text = "STORE", Color = COL.Green, ZIndex = 33, MaxTextSize = 24,
})
local detailReason = makeText(detail, {
	Name = "Reason", Position = UDim2.fromOffset(14, 442), Size = UDim2.new(1, -28, 0, 56), Text = "",
	TextWrapped = true, TextColor3 = COL.Muted, ZIndex = 32, MaxTextSize = 16, TextYAlignment = Enum.TextYAlignment.Top,
})

-- Cosmetics page -------------------------------------------------------------------
local cosmeticsInfo = makeText(popup, {
	Name = "CosmeticsInfo", Text = "Earn Gems by reaching new levels, from playtime rewards and by destroying the island during events. Gems only buy looks.",
	TextWrapped = true, TextColor3 = COL.Muted, ZIndex = 13, MaxTextSize = 17, TextXAlignment = Enum.TextXAlignment.Left,
})

-- Toast ---------------------------------------------------------------------------------
local toast = frame(popup, { Name = "Toast", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(0.7, 0, 0, 50), Color = Color3.fromRGB(8, 10, 22), Transparency = 0.06, ZIndex = 80, Radius = 0.3 })
toast.Visible = false
local toastStroke = GuiStyle.Stroke(toast, COL.Green, 3)
local toastText = makeText(toast, { Name = "Text", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.92, 0, 0.64, 0), ZIndex = 81, MaxTextSize = 20 })
local toastToken = 0

local function showToast(message, color)
	toastToken += 1
	local token = toastToken
	toastText.Text = message
	toastStroke.Color = color or COL.Green
	toast.Visible = true
	task.delay(3, function()
		if toastToken == token then toast.Visible = false end
	end)
end

-- ===================== STATE =====================
local tab = "stored"
local sortIndex = 1
local filter = "all"
local selectedKey = nil
local compact = false
local dirty = true
local busy = false
local confirmBuy = nil   -- { id, expires }

local function inventoryEnabled()
	return player:GetAttribute("InventoryEnabled") == true
end

local function storedItems()
	local list = {}
	local raw = player:GetAttribute("InventoryData")
	if type(raw) ~= "string" or raw == "" then return list end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(decoded) ~= "table" then return list end
	for _, record in ipairs(decoded) do
		if type(record) == "table" and type(record.id) == "string" then
			table.insert(list, {
				key = "s:" .. record.id, kind = "stored", id = record.id,
				tier = tonumber(record.tier) or 1, mutation = record.mutation or "", oneIn = tonumber(record.oneIn) or 0,
				favorite = record.favorite == true, createdAt = tonumber(record.createdAt) or 0,
				state = "Stored", sizeMultiplier = SizeVariants.Read(record.sizeMultiplier),
			})
		end
	end
	return list
end

local function baseItems()
	local list = {}
	for _, hole in ipairs(CollectionService:GetTagged("BlackHole")) do
		if hole:IsDescendantOf(workspace) and hole:GetAttribute("OwnerUserId") == player.UserId
			and hole:GetAttribute("MergeLocked") ~= true then
			local id = hole:GetAttribute("BlackHoleId")
			table.insert(list, {
				key = "b:" .. tostring(id), kind = "base", hole = hole, id = id,
				tier = tonumber(hole:GetAttribute("Tier")) or 1, mutation = hole:GetAttribute("Mutation") or "",
				oneIn = tonumber(hole:GetAttribute("MutationOneIn")) or 0,
				sizeMultiplier = SizeVariants.Read(hole:GetAttribute("SizeMultiplier")),
				favorite = hole:GetAttribute("Favorite") == true, createdAt = tonumber(hole:GetAttribute("CreatedAt")) or 0,
				state = if hole:GetAttribute("HeldBy") == player.UserId then "Carried" else "Deployed",
			})
		end
	end
	return list
end

local function displayName(item)
	local data = TierConfig.GetTier(item.tier)
	return tostring(data and data.DisplayName or ("Tier " .. item.tier))
end

local function visibleItems()
	local list = if tab == "stored" then storedItems() else baseItems()
	local query = string.lower(searchBox.Text or "")
	local filtered = {}
	for _, item in ipairs(list) do
		local mutation = MutationConfig.Get(item.mutation)
		local matchesFilter = filter == "all"
			or (filter == "mutated" and mutation ~= nil)
			or (filter == "normal" and mutation == nil)
			or (filter == "favorites" and item.favorite)
		local haystack = string.lower(displayName(item) .. " " .. (if mutation then mutation.DisplayName else "normal"))
		if matchesFilter and (query == "" or string.find(haystack, query, 1, true)) then
			item.rarity = if mutation then (tonumber(mutation.OneIn) or 1) else 0
			table.insert(filtered, item)
		end
	end
	local sort = SORTS[sortIndex].Id
	table.sort(filtered, function(a, b)
		if sort == "rarity" then
			if a.rarity ~= b.rarity then return a.rarity > b.rarity end
			if a.tier ~= b.tier then return a.tier > b.tier end
		elseif sort == "newest" then
			if a.createdAt ~= b.createdAt then return a.createdAt > b.createdAt end
		else
			if a.tier ~= b.tier then return a.tier > b.tier end
			if a.rarity ~= b.rarity then return a.rarity > b.rarity end
		end
		return tostring(a.id) < tostring(b.id)
	end)
	return filtered, #list
end

-- Why a black hole on the base can't be stored right now (nil = try it).
-- The server checks again; this only explains a greyed-out button.
local function storeBlocker(item)
	local hole = item.hole
	if not hole or not hole.Parent then return "That black hole is gone." end
	if not inventoryEnabled() then return "The Inventory is off this session (your base didn't load correctly)." end
	if (tonumber(player:GetAttribute("InventoryCount")) or 0) >= (tonumber(player:GetAttribute("InventoryCapacity")) or InventoryConfig.Capacity) then
		return "Your Inventory is full."
	end
	if hole:GetAttribute("BeingConsumed") or hole:GetAttribute("Defeated") then return "It's under attack right now." end
	if hole:GetAttribute("AttackingId") then return "It's attacking. Wait until the attack finishes." end
	if player:GetAttribute("UnderAttackBy") ~= nil then return "Your base is under attack. Try again when it's over." end
	local maxHealth, health = tonumber(hole:GetAttribute("MaxHealth")), tonumber(hole:GetAttribute("Health"))
	if maxHealth and health and health < maxHealth then return "It's damaged. It can be stored once it recovers." end
	return nil
end

-- ===================== REQUESTS =====================
local function request(action, payload)
	if not requestRemote then return { ok = false, reason = "The Inventory isn't installed on the server." } end
	payload.requestId = HttpService:GenerateGUID(false)
	for attempt = 1, 2 do
		local ok, result = pcall(function() return requestRemote:InvokeServer(action, payload) end)
		if ok and type(result) == "table" then return result end
		if attempt == 2 then
			return { ok = false, reason = "Couldn't reach the server. Try again." }
		end
		task.wait(0.4)   -- same requestId: a retry never does it twice
	end
	return { ok = false, reason = "Couldn't reach the server." }
end

-- ===================== RENDER: BLACK HOLES =====================
local cardPool = {}
local refreshDetail

local function clearCards()
	for _, card in ipairs(cardPool) do card:Destroy() end
	table.clear(cardPool)
end

local function buildCard(item, order)
	local mutation = MutationConfig.Get(item.mutation)
	local border = rarityColor(mutation) or COL.Outline
	local card = Instance.new("TextButton")
	card.Name = "Card"
	card.LayoutOrder = order
	card.BackgroundColor3 = WHITE
	card.AutoButtonColor = false
	card.Text = ""
	card.ZIndex = 13
	card.Parent = scroll
	GuiStyle.Corner(card, 0.1)
	local stroke = GuiStyle.Stroke(card, if item.key == selectedKey then WHITE else border, if item.key == selectedKey then 4 else 3)
	local _ = stroke
	GuiStyle.Gradient(card, (if mutation then mutation.Main else COL.Card2):Lerp(BLACK, 0.45), Color3.fromRGB(14, 18, 40))

	local icon = frame(card, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(88, 88), Transparency = 1, ZIndex = 14 })
	drawHole(icon, item.tier, item.mutation, 14)

	local badge = frame(card, { AnchorPoint = Vector2.zero, Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(46, 24), Color = Color3.fromRGB(10, 14, 32), Transparency = 0.1, ZIndex = 19, Radius = 0.4 })
	GuiStyle.Stroke(badge, COL.Outline, 2)
	makeText(badge, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.9, 0, 0.72, 0), Text = "T" .. item.tier, ZIndex = 20, MaxTextSize = 16 })

	if SizeVariants.Read(item.sizeMultiplier) > 1 then
		makeText(card, {Name="Size", Position=UDim2.fromOffset(6,76), Size=UDim2.new(1,-12,0,24), Text=SizeVariants.Text(item.sizeMultiplier), TextColor3=Color3.fromRGB(175,239,255), ZIndex=20, MaxTextSize=17})
	end
	if item.favorite then
		makeText(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 4), Size = UDim2.fromOffset(28, 28), Text = "🔒", ZIndex = 20, MaxTextSize = 22, Stroke = false })
	end

	makeText(card, { Name = "Name", Position = UDim2.fromOffset(6, 104), Size = UDim2.new(1, -12, 0, 24), Text = displayName(item), ZIndex = 15, MaxTextSize = 18 })
	makeText(card, {
		Name = "Mutation", Position = UDim2.fromOffset(6, 128), Size = UDim2.new(1, -12, 0, 20),
		Text = if mutation then ("✦ " .. string.upper(mutation.DisplayName)) else "Normal",
		TextColor3 = if mutation then mutation.Main:Lerp(WHITE, 0.3) else COL.Muted, ZIndex = 15, MaxTextSize = 16,
	})
	local stateTag = frame(card, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -24, 0, 24), Color = STATE_COLORS[item.state], ZIndex = 15, Radius = 0.5 })
	GuiStyle.Stroke(stateTag, COL.Outline, 2)
	makeText(stateTag, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.9, 0, 0.72, 0),
		Text = if item.state == "Stored" then "STORED" elseif item.state == "Carried" then "CARRIED" else "ON BASE", ZIndex = 16, MaxTextSize = 14,
	})

	local pop = Instance.new("UIScale")
	pop.Parent = card
	GuiStyle.AddHoverScale(card, pop, 1.04)
	card.Activated:Connect(function()
		sfx("UI_CLICK_ID")
		selectedKey = item.key
		dirty = true
	end)
	table.insert(cardPool, card)
	return card
end

-- ===================== RENDER: COSMETICS =====================
local function ownedSet()
	local set = {}
	local raw = player:GetAttribute("CosmeticsOwned")
	if type(raw) == "string" then
		for id in string.gmatch(raw, "[^,]+") do set[id] = true end
	end
	return set
end

local function slotName(slotId)
	if GemsConfig then
		for _, slot in ipairs(GemsConfig.Slots) do
			if slot.Id == slotId then return slot.Name end
		end
	end
	return slotId
end

local function cosmeticSwatch(parent, item, slotId, z)
	local swatch = frame(parent, { Name = "Swatch", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.new(1, -28, 0, 70), Color = Color3.fromRGB(10, 14, 32), ZIndex = z, Radius = 0.2 })
	GuiStyle.Stroke(swatch, COL.Outline, 2)
	local color = if item and item.Color then item.Color else nil
	if slotId == "Nameplate" then
		local plate = frame(swatch, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.7), Color = Color3.fromRGB(58, 32, 120), ZIndex = z + 1, Radius = 0.18 })
		local border = GuiStyle.Stroke(plate, color or Color3.fromRGB(120, 220, 255), 5)
		if item and item.Rainbow and GemsConfig then
			border.Color = WHITE
			local g = Instance.new("UIGradient")
			g.Color = GemsConfig.Rainbow
			g.Parent = border
		end
		makeText(plate, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.5), Text = player.DisplayName, ZIndex = z + 2, MaxTextSize = 16 })
	elseif slotId == "Trail" then
		local streak = frame(swatch, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.1, 0.5), Size = UDim2.fromScale(0.62, 0.22), Color = color or Color3.fromRGB(255, 214, 80), ZIndex = z + 1, Radius = 1 })
		local g = Instance.new("UIGradient")
		if item and item.Rainbow and GemsConfig then
			g.Color = GemsConfig.Rainbow
		end
		g.Transparency = NumberSequence.new(if item then 0.9 else 1, if item then 0 else 1)
		g.Parent = streak
		local coin = frame(swatch, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.78, 0.5), Size = UDim2.fromOffset(34, 34), Color = Color3.fromRGB(255, 206, 52), ZIndex = z + 2, Radius = 1 })
		GuiStyle.Stroke(coin, Color3.fromRGB(214, 138, 18), 3)
		makeText(coin, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.7), Text = "★", ZIndex = z + 3, TextColor3 = Color3.fromRGB(214, 138, 18), Stroke = false })
	else
		local sparkleColor = color or Color3.fromRGB(255, 232, 120)
		local count = if item then math.min(item.Count or 6, 10) else 5
		for i = 1, count do
			local angle = (i / count) * math.pi * 2
			makeText(swatch, {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(angle) * 36, 0.5, math.sin(angle) * 22),
				Size = UDim2.fromOffset(18, 18), Text = "✦", TextColor3 = sparkleColor:Lerp(WHITE, (i % 3) * 0.2), ZIndex = z + 1, MaxTextSize = 18, Stroke = false,
			})
		end
	end
	return swatch
end

local function buildCosmeticCard(item, slotId, order)
	local owned = ownedSet()
	local equippedId = player:GetAttribute("Equipped_" .. slotId)
	local isDefault = item == nil
	local isOwned = isDefault or owned[item.Id] == true
	local isEquipped = if isDefault then (equippedId == nil or equippedId == "") else equippedId == item.Id

	local card = frame(scroll, { Name = "Cosmetic", Color = WHITE, ZIndex = 13, Radius = 0.1 })
	card.LayoutOrder = order
	GuiStyle.Stroke(card, if isEquipped then COL.Green else COL.Outline, if isEquipped then 4 else 3)
	GuiStyle.Gradient(card, Color3.fromRGB(34, 42, 86), Color3.fromRGB(14, 18, 40))
	cosmeticSwatch(card, item, slotId, 14)
	makeText(card, { Name = "Name", Position = UDim2.fromOffset(8, 90), Size = UDim2.new(1, -16, 0, 24), Text = if isDefault then "Default" else item.Name, ZIndex = 15, MaxTextSize = 18 })
	makeText(card, { Name = "Slot", Position = UDim2.fromOffset(8, 114), Size = UDim2.new(1, -16, 0, 18), Text = slotName(slotId), TextColor3 = COL.Muted, ZIndex = 15, MaxTextSize = 14 })

	local text, color, enabled
	if isEquipped then
		text, color, enabled = "✓ IN USE", COL.GreenDark, false
	elseif isOwned then
		text, color, enabled = if isDefault then "USE DEFAULT" else "EQUIP", COL.Green, true
	else
		local confirming = confirmBuy and confirmBuy.id == item.Id and os.clock() < confirmBuy.expires
		text = if confirming then ("CONFIRM %s"):format(GemsConfig.Format(item.Price)) else ("BUY  %s"):format(GemsConfig.Format(item.Price))
		color = if confirming then COL.Pink else GEM_BLUE
		enabled = (tonumber(player:GetAttribute("Gems")) or 0) >= item.Price
	end
	local button = makeButton(card, {
		Name = "Action", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -24, 0, 38),
		Text = text, Color = color, ZIndex = 16, MaxTextSize = 17,
	})
	setEnabled(button, enabled)
	if not isOwned and not enabled then
		local label = button:FindFirstChild("Label")
		if label then label.Text = ("NEED %s"):format(GemsConfig.Format(item.Price)) end
	end

	button.Activated:Connect(function()
		if busy or not button.Active then return end
		if not cosmeticsRemote then
			showToast("Cosmetics aren't installed on the server.", COL.X)
			return
		end
		sfx("UI_CLICK_ID")
		if isDefault then
			busy = true
			local ok, result = pcall(function() return cosmeticsRemote:InvokeServer("unequip", slotId) end)
			busy = false
			if not (ok and type(result) == "table" and result.ok) then
				showToast((ok and type(result) == "table" and result.reason) or "Couldn't change that.", COL.X)
			end
		elseif isOwned then
			busy = true
			local ok, result = pcall(function() return cosmeticsRemote:InvokeServer("equip", item.Id) end)
			busy = false
			if not (ok and type(result) == "table" and result.ok) then
				showToast((ok and type(result) == "table" and result.reason) or "Couldn't equip that.", COL.X)
			end
		elseif confirmBuy and confirmBuy.id == item.Id and os.clock() < confirmBuy.expires then
			confirmBuy = nil
			busy = true
			local ok, result = pcall(function() return cosmeticsRemote:InvokeServer("buy", item.Id) end)
			busy = false
			if ok and type(result) == "table" and result.ok then
				sfx("COSMETIC_BUY_ID")
				showToast(("Bought %s! It's equipped."):format(item.Name), COL.Green)
			else
				showToast((ok and type(result) == "table" and result.reason) or "Couldn't buy that.", COL.X)
			end
		else
			-- First tap asks to confirm, so Gems are never spent by accident.
			confirmBuy = { id = item.Id, expires = os.clock() + 3 }
			task.delay(3.05, function() dirty = true end)
		end
		dirty = true
	end)
	table.insert(cardPool, card)
end

-- ===================== DETAIL =====================
local previewModel = nil
local previewTier = nil
local previewRadius = 1
local function framePreview()
	if not previewModel then return end
	local size=viewport.AbsoluteSize
	local vertical=math.rad(viewportCamera.FieldOfView/2)
	local half=math.min(vertical,math.atan(math.tan(vertical)*math.max(size.X,1)/math.max(size.Y,1)))
	local distance=previewRadius/math.sin(half)*1.08
	viewportCamera.CFrame=CFrame.lookAt(Vector3.new(0,0.25,1).Unit*distance,Vector3.zero)
end
viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(framePreview)

local function setPreview(item)
	local key = tostring(item.tier) .. ":" .. tostring(item.mutation) .. ":" .. tostring(item.sizeMultiplier)
	if previewTier == key and previewModel then return end
	previewTier = key
	if previewModel then previewModel:Destroy() end
	previewModel = nil
	fallbackIcon:ClearAllChildren()
	local templates = ReplicatedStorage:FindFirstChild("BlackHoleCompleteModels")
	local template = templates and templates:FindFirstChild("T" .. item.tier)
	if template then
		local ok, clone = pcall(function() return template:Clone() end)
		if ok and clone then
			clone:PivotTo(CFrame.new())
			local core
			for _, object in ipairs(clone:GetDescendants()) do
				if object:IsA("BasePart") and object.Name:lower():match("_core$") then core=object break end
			end
			local cosmeticModule = ReplicatedStorage:FindFirstChild("BlackHoleCosmetics")
			if core and cosmeticModule then
				local okCosmetic, err = pcall(function()
					local _, extent = clone:GetBoundingBox()
					require(cosmeticModule).Build(clone,core,item.tier,{viewport=true,quality="LOW",reference=math.max(extent.X,extent.Y,extent.Z),mutation=item.mutation})
				end)
				if not okCosmetic then warn("[Inventory] Preview cosmetics:",err) end
			end
			clone:ScaleTo(clone:GetScale()*SizeVariants.Read(item.sizeMultiplier))
			clone.Parent = viewport
			local bounds, size = clone:GetBoundingBox()
			-- A sphere enclosing the off-centre bounds also fits while spinning.
			previewRadius = size.Magnitude * 0.5 + (bounds.Position-clone:GetPivot().Position).Magnitude
			previewModel = clone
			framePreview()
		end
	end
	if not previewModel then
		drawHole(fallbackIcon, item.tier, item.mutation, 33)
	end
end

refreshDetail = function(item)
	if not item then
		detail.Visible = not compact and false
		return
	end
	detail.Visible = true
	detailBack.Visible = compact
	local mutation = MutationConfig.Get(item.mutation)
	setPreview(item)
	previewHalo.BackgroundColor3 = if mutation then mutation.Main else ((TierConfig.GetTier(item.tier) or {}).DiskGlowColor or COL.Purple)
	detailName.Text = displayName(item)
	detailTier.Text = "Tier " .. item.tier .. "  •  Size " .. SizeVariants.Text(item.sizeMultiplier)
	if mutation then
		detailMutation.Text = ("✦ %s  (%s)"):format(string.upper(mutation.DisplayName), MutationConfig.OddsText(if item.oneIn > 0 then item.oneIn else mutation.OneIn))
		detailMutation.TextColor3 = mutation.Main:Lerp(WHITE, 0.3)
		detailBonus.Text = if MutationConfig.BonusText then MutationConfig.BonusText(item.mutation, "  •  ") else ""
	else
		detailMutation.Text = "Normal (no mutation)"
		detailMutation.TextColor3 = COL.Muted
		detailBonus.Text = ""
	end
	detailState.BackgroundColor3 = STATE_COLORS[item.state]
	detailStateText.Text = if item.state == "Stored" then "STORED" elseif item.state == "Carried" then "CARRIED" else "ON YOUR BASE"

	paint(favoriteButton, if item.favorite then FAVORITE_GOLD else Color3.fromRGB(96, 104, 170))
	favoriteLabel.Text = if item.favorite then "🔒 FAVORITE (TAP TO UNLOCK)" else "LOCK AS FAVORITE"
	setEnabled(favoriteButton, inventoryEnabled())

	local reason
	if item.kind == "stored" then
		actionLabel.Text = "DEPLOY TO BASE"
		paint(actionButton, COL.Green)
		reason = if inventoryEnabled() then "Deploying puts it back on your base, if there's a free slot." else "The Inventory is off this session."
		setEnabled(actionButton, inventoryEnabled())
	else
		actionLabel.Text = "STORE IN INVENTORY"
		paint(actionButton, STATE_COLORS.Stored)
		local blocker = storeBlocker(item)
		setEnabled(actionButton, blocker == nil)
		reason = blocker or "Stored black holes are safe: they don't earn, attack or get attacked."
	end
	if item.favorite then
		reason = reason .. "\nFavorites never merge."
	end
	if SizeVariants.IsProtected(item.sizeMultiplier) then reason ..= "\nGiant: merging needs confirmation and rolls a fresh size." end
	detailReason.Text = reason
end

-- ===================== LAYOUT =====================
local BODY_TOP_ITEMS = TOOLS_Y + 48
local BODY_TOP_COSMETICS = TABS_Y + 104

local function applyLayout()
	local scale, width, height = 1, 900, 590
	if UiResponsive then
		scale, width, height = UiResponsive.FitPanel(900, 590, { minWidth = 560, minHeight = 400, margin = 16 })
	end
	popupScale.Scale = scale
	popup.Size = UDim2.fromOffset(width, height)
	compact = width < 760

	local cosmetics = tab == "cosmetics"
	toolRow.Visible = not cosmetics
	cosmeticsInfo.Visible = cosmetics
	local bodyTop = if cosmetics then BODY_TOP_COSMETICS else BODY_TOP_ITEMS
	if cosmetics then
		cosmeticsInfo.Position = UDim2.fromOffset(24, TABS_Y + 52)
		cosmeticsInfo.Size = UDim2.new(1, -48, 0, 44)
	end

	local detailWidth = if cosmetics or compact then 0 else 290
	local bodyHeight = height - bodyTop - 14
	scroll.Position = UDim2.fromOffset(16, bodyTop)
	scroll.Size = UDim2.fromOffset(width - 32 - (if detailWidth > 0 then detailWidth + 12 else 0), bodyHeight)
	emptyText.Position = UDim2.fromOffset(16 + scroll.Size.X.Offset / 2, bodyTop + bodyHeight / 2)

	if compact then
		detail.Position = UDim2.fromOffset(16, bodyTop)
		detail.Size = UDim2.fromOffset(width - 32, bodyHeight)
	else
		detail.Position = UDim2.fromOffset(width - 16 - 290, bodyTop)
		detail.Size = UDim2.fromOffset(290, bodyHeight)
	end

	-- Tools: narrower search and filters on small windows.
	local toolWidth = width - 36
	searchBox.Size = UDim2.fromOffset(if toolWidth < 760 then 150 else 220, 38)
	sortButton.Position = UDim2.fromOffset(searchBox.Size.X.Offset + 10, 0)
	local x = sortButton.Position.X.Offset + 160
	for _, def in ipairs(FILTERS) do
		local button = filterButtons[def.Id]
		local w = button.Size.X.Offset
		button.Position = UDim2.fromOffset(x, 0)
		button.Visible = x + w <= toolWidth
		x += w + 6
	end
	for index, def in ipairs(TAB_DEFS) do
		local w = if width < 700 then 118 else 142
		tabButtons[def.Id].Size = UDim2.fromOffset(w, 44)
		tabButtons[def.Id].Position = UDim2.fromOffset((index - 1) * (w + 8), 0)
	end

	local cell = if cosmetics then 170 else 150
	local cellHeight = if cosmetics then 190 else 188
	local gridWidth = scroll.Size.X.Offset - 16
	local columns = math.max(math.floor((gridWidth + 12) / (cell + 12)), 2)
	local cellWidth = math.floor((gridWidth - (columns - 1) * 12) / columns)
	grid.CellSize = UDim2.fromOffset(cellWidth, cellHeight)
end

-- ===================== REFRESH =====================
local function render()
	applyLayout()
	clearCards()
	local count = tonumber(player:GetAttribute("InventoryCount")) or #storedItems()
	local capacity = tonumber(player:GetAttribute("InventoryCapacity")) or InventoryConfig.Capacity
	capacityText.Text = ("%d / %d stored"):format(count, capacity)
	capacityText.TextColor3 = if count >= capacity then COL.X else COL.Muted
	gemsText.Text = if GemsConfig then GemsConfig.Format(player:GetAttribute("Gems") or 0) else tostring(player:GetAttribute("Gems") or 0)

	for id, button in pairs(tabButtons) do
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if id == tab then WHITE else COL.Outline
			stroke.Thickness = if id == tab then 4 else 3
		end
	end
	for id, button in pairs(filterButtons) do
		paint(button, if id == filter then COL.Cyan:Lerp(BLACK, 0.2) else Color3.fromRGB(70, 78, 120))
	end
	sortLabel.Text = SORTS[sortIndex].Text

	if tab == "cosmetics" then
		detail.Visible = false
		emptyText.Text = ""
		if not GemsConfig then
			emptyText.Text = "Cosmetics need GemsConfig in ReplicatedStorage."
			return
		end
		local order = 0
		for _, slot in ipairs(GemsConfig.Slots) do
			order += 1
			buildCosmeticCard(nil, slot.Id, order)
			for _, item in ipairs(GemsConfig.Catalog) do
				if item.Slot == slot.Id then
					order += 1
					buildCosmeticCard(item, slot.Id, order)
				end
			end
		end
		return
	end

	local items, total = visibleItems()
	local selected = nil
	for index, item in ipairs(items) do
		buildCard(item, index)
		if item.key == selectedKey then selected = item end
	end
	if not selected and not compact and #items > 0 then
		selected = items[1]
		selectedKey = selected.key
		for _, card in ipairs(cardPool) do
			if card.LayoutOrder == 1 then
				local stroke = card:FindFirstChildOfClass("UIStroke")
				if stroke then stroke.Color = WHITE stroke.Thickness = 4 end
			end
		end
	end

	if #items == 0 then
		if total == 0 then
			emptyText.Text = if tab == "stored"
				then "Nothing stored yet. Open ON BASE and store a black hole to keep it safe."
				else "No black holes on your base right now."
		else
			emptyText.Text = "Nothing matches your search or filter."
		end
	else
		emptyText.Text = ""
	end

	if compact then
		scroll.Visible = selected == nil
		detail.Visible = selected ~= nil
		if selected then refreshDetail(selected) end
	else
		scroll.Visible = true
		if selected then
			refreshDetail(selected)
		else
			detail.Visible = false
		end
	end
	emptyText.Visible = scroll.Visible
end

local currentItem = nil

local function selectedItem()
	if not selectedKey then return nil end
	local list = if string.sub(selectedKey, 1, 2) == "s:" then storedItems() else baseItems()
	for _, item in ipairs(list) do
		if item.key == selectedKey then return item end
	end
	return nil
end

-- ===================== ACTIONS =====================
actionButton.Activated:Connect(function()
	if busy or not actionButton.Active then return end
	local item = selectedItem()
	if not item then return end
	busy = true
	sfx("UI_CLICK_ID")
	local result
	if item.kind == "stored" then
		result = request("deploy", { id = item.id })
		if result.ok then
			sfx("INVENTORY_DEPLOY_ID")
			showToast(("%s is back on your base!"):format(displayName(item)), COL.Green)
			selectedKey = nil
		end
	else
		result = request("store", { hole = item.hole })
		if result.ok then
			sfx("INVENTORY_STORE_ID")
			showToast(("%s is stored safely."):format(displayName(item)), STATE_COLORS.Stored)
			selectedKey = "s:" .. tostring(result.id or item.id)
		end
	end
	if not result.ok then
		showToast(result.reason or "That didn't work.", COL.X)
	end
	busy = false
	dirty = true
end)

favoriteButton.Activated:Connect(function()
	if busy or not favoriteButton.Active then return end
	local item = selectedItem()
	if not item then return end
	busy = true
	sfx("UI_CLICK_ID")
	local payload = { value = not item.favorite }
	if item.kind == "stored" then payload.id = item.id else payload.hole = item.hole end
	local result = request("favorite", payload)
	if result.ok then
		showToast(if result.favorite then "Locked as a favorite: it will never be merged." else "Unlocked: it can be merged again.", FAVORITE_GOLD)
	else
		showToast(result.reason or "That didn't work.", COL.X)
	end
	busy = false
	dirty = true
end)

detailBack.Activated:Connect(function()
	selectedKey = nil
	dirty = true
end)

for id, button in pairs(tabButtons) do
	button.Activated:Connect(function()
		if tab == id then return end
		sfx("UI_CLICK_ID")
		tab = id
		selectedKey = nil
		dirty = true
	end)
end
for id, button in pairs(filterButtons) do
	button.Activated:Connect(function()
		sfx("UI_CLICK_ID")
		filter = id
		dirty = true
	end)
end
sortButton.Activated:Connect(function()
	sfx("UI_CLICK_ID")
	sortIndex = sortIndex % #SORTS + 1
	dirty = true
end)
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	dirty = true
end)

-- Anything that changes what the window shows marks it dirty; it redraws at
-- most a few times a second, and only while open.
for _, attribute in ipairs({ "InventoryData", "InventoryCount", "InventoryEnabled", "Gems", "CosmeticsOwned",
	"Equipped_Nameplate", "Equipped_Trail", "Equipped_Sparkle", "UnderAttackBy" }) do
	player:GetAttributeChangedSignal(attribute):Connect(function() dirty = true end)
end
local function watchHole(hole)
	if hole:GetAttribute("OwnerUserId") ~= player.UserId then return end
	for _, attribute in ipairs({ "Favorite", "HeldBy", "Health", "Tier", "Mutation", "MergeLocked", "BeingConsumed", "AttackingId", "SizeMultiplier" }) do
		hole:GetAttributeChangedSignal(attribute):Connect(function() dirty = true end)
	end
	dirty = true
end
CollectionService:GetInstanceAddedSignal("BlackHole"):Connect(function(hole)
	task.defer(watchHole, hole)
end)
CollectionService:GetInstanceRemovedSignal("BlackHole"):Connect(function() dirty = true end)
for _, hole in ipairs(CollectionService:GetTagged("BlackHole")) do
	watchHole(hole)
end

local spin = 0
RunService.RenderStepped:Connect(function(dt)
	if not popupGroup.Visible then return end
	if previewModel and detail.Visible then
		spin += dt * 0.6
		previewModel:PivotTo(CFrame.Angles(math.rad(16), spin, 0))
	end
end)

task.spawn(function()
	while gui.Parent do
		task.wait(0.2)
		if dirty and popupGroup.Visible and not busy then
			dirty = false
			local ok, err = pcall(render)
			if not ok then warn("[InventoryClient] Render failed:", err) end
			currentItem = selectedItem()
		end
	end
end)

-- ===================== OPEN / CLOSE =====================
local function openPopup()
	dirty = true
	pcall(render)
	dirty = false
	GuiManager:Open("Inventory")
end

local function closePopup()
	GuiManager:Close("Inventory")
end

closeButton.Activated:Connect(closePopup)
GuiManager:SetBackHandler("Inventory", function()
	if compact and selectedKey then
		selectedKey = nil
		dirty = true
	else
		closePopup()
	end
end)
if UiResponsive and UiResponsive.Changed then
	UiResponsive.Changed:Connect(function() dirty = true end)
end

task.spawn(function()
	local hud = playerGui:WaitForChild("MainHUD", 30)
	local slot = hud and hud:FindFirstChild("InventorySlot", true)
	local started = os.clock()
	while hud and not slot and os.clock() - started < 15 do
		task.wait(0.2)
		slot = hud:FindFirstChild("InventorySlot", true)
	end
	local button = slot and slot:FindFirstChild("Inventory")
	if not button then
		warn("[InventoryClient] Couldn't find the Inventory button in MainHUD. Update MainHUD.")
		return
	end
	button.Activated:Connect(function()
		if GuiManager:GetCurrent() == "Inventory" then
			closePopup()
		else
			openPopup()
		end
	end)
end)

-- ===================== NOTICES =====================
if noticeRemote then
	local lastNotice = 0
	noticeRemote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or os.clock() - lastNotice < 4 then return end
		lastNotice = os.clock()
		if HudStack and HudStack.Announce then
			HudStack.Announce({
				key = "InventoryNotice", priority = 2, title = "🔒 FAVORITE",
				subtitle = tostring(payload.text or ""), accent = FAVORITE_GOLD, seconds = 2.6,
			})
		end
	end)
end

-- Gems from the island or other sources get a sound (playtime claims already
-- play their own claim sound; level-up Gems are part of the level-up banner).
if gemsEarned then
	gemsEarned.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		if payload.source == "Playtime reward" then return end
		sfx("GEMS_EARNED_ID", "minor")
	end)
end

local _ = currentItem
