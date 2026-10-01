-- HudStack (ModuleScript in ReplicatedStorage)  -- NEW
-- One shared top-centre column for event cards and short announcements.
-- Presentation only: it reads no server state and changes nothing.
-- Client only: require it from LocalScripts or client modules.
--
--        [ UPGRADE ]  [ LOCK BASE ]        MainHUD
--        [      announcement      ]        HudStack (only while one shows)
--        [ LV 12 ] [ 2x 18:30 ]            HudStack status row (level, boosts)
--        [ THIEVING TIME ] [ ISLAND ]      HudStack cards
--
-- The column measures MainHUD (TopActionButtons, SideMenu, PlaytimeSlot)
-- instead of guessing pixel offsets, so it always starts under the Upgrade /
-- Lock Base buttons and stays between the side buttons. Cards sit side by side when
-- they fit and stack when they don't. Hidden cards take no space.
--
-- Layout is only recalculated when the screen size, MainHUD or a card's
-- visibility changes. Nothing here runs every frame.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HudStack = {}

-- ===================== STYLE =====================
local COLORS = {
	Panel = Color3.fromRGB(16, 20, 44),
	Track = Color3.fromRGB(8, 11, 26),
	Outline = Color3.fromRGB(8, 12, 28),
	Text = Color3.fromRGB(255, 255, 255),
	Dim = Color3.fromRGB(178, 192, 228),
	Red = Color3.fromRGB(255, 88, 88),
	Amber = Color3.fromRGB(255, 196, 72),
	Green = Color3.fromRGB(86, 222, 110),
	Blue = Color3.fromRGB(96, 176, 255),
	Calm = Color3.fromRGB(88, 104, 160),
}
HudStack.COLORS = COLORS
HudStack.FONT = Enum.Font.FredokaOne

-- Text sizes in design pixels (a 1280x720 screen). The column's UIScale
-- shrinks everything on small screens, so phones get a larger set.
local TEXT = {
	Regular = { Title = 30, Timer = 25, Status = 19, Support = 17 },
	Compact = { Title = 32, Timer = 27, Status = 22, Support = 20 },
}
local TEXT_STROKE = { Title = 3, Timer = 2.5, Status = 2, Support = 1.5 }

-- MainHUD's design size and scale rule, used when MainHUD can't be measured.
local DESIGN = Vector2.new(1280, 720)
local HUD_MIN_SCALE = 0.45

local CARD_WIDTH = 420
local CARD_BACKGROUND = 0.04
local ANNOUNCE_WIDTH = 560
local ANNOUNCE_HEIGHT = 124          -- title + subtitle
local ANNOUNCE_SHORT_HEIGHT = 82     -- title only
local GAP = 10                       -- between cards, and under the Stardust counter
local SIDE_CLEARANCE = 14            -- from the side menu and the playtime button
local COMPACT_BELOW_HEIGHT = 520     -- landscape phones
local CONDENSED_SHARE = 0.78         -- COMPACT density: the whole column, uniformly

-- ===================== STATE =====================
local strokes = {}   -- [UIStroke] = design thickness
local texts = {}     -- [TextLabel] = text kind
local cards = {}
local compact = false
local scale = 1
local announceWidth = ANNOUNCE_WIDTH
local density = "FULL"   -- "COMPACT" while the tutorial or a higher-priority piece needs the room

local function textSize(kind)
	local set = if compact then TEXT.Compact else TEXT.Regular
	return set[kind] or set.Support
end

-- ===================== HELPERS =====================
function HudStack.Stroke(parent, color, thickness, contextual)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or COLORS.Outline
	stroke.ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	strokes[stroke] = thickness or 2
	stroke.Destroying:Connect(function() strokes[stroke] = nil end)
	-- UIScale doesn't thin strokes, so they're scaled here to stay in proportion.
	stroke.Thickness = strokes[stroke] * scale
	stroke.Parent = parent
	return stroke
end

function HudStack.Corner(parent, pixels)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, pixels)
	corner.Parent = parent
	return corner
end

-- Wrapped text gets an exact height from TextService. Roblox's AutomaticSize
-- doesn't wrap reliably inside list layouts and cut second lines off.
local CARD_INNER_WIDTH = 420 - 32
local measured = {}   -- [TextLabel] = width used for wrapping

local function fitLabel(label)
	local width = measured[label]
	if not width then return end
	local bounds = TextService:GetTextSize(label.Text, label.TextSize, label.Font, Vector2.new(width, 100000))
	local height = math.ceil(bounds.Y) + 2
	if label.Text == "" then height = 0 end
	if label.Size.Y.Offset ~= height then
		label.Size = UDim2.new(1, 0, 0, height)
	end
end

-- kind: "Title" | "Timer" | "Status" | "Support"
-- Labels wrap and grow downwards, and their card grows with them.
-- props.Fill = true fills the parent instead (for text inside a bar).
-- props.Width = wrap width if the label is narrower than a card's content.
function HudStack.Label(parent, kind, props)
	props = props or {}
	local label = Instance.new("TextLabel")
	label.Name = props.Name or kind
	label.BackgroundTransparency = 1
	label.Font = HudStack.FONT
	label.Text = props.Text or ""
	label.TextColor3 = props.Color or COLORS.Text
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = true
	label.LayoutOrder = props.Order or 0
	label.ZIndex = props.ZIndex or 3
	texts[label] = kind
	label.Destroying:Connect(function()
		texts[label] = nil
		measured[label] = nil
	end)
	label.TextSize = textSize(kind)
	if props.Fill then
		label.Size = UDim2.fromScale(1, 1)
	else
		measured[label] = props.Width or CARD_INNER_WIDTH
		fitLabel(label)
		label:GetPropertyChangedSignal("Text"):Connect(function() fitLabel(label) end)
		label:GetPropertyChangedSignal("TextSize"):Connect(function() fitLabel(label) end)
	end
	HudStack.Stroke(label, COLORS.Outline, TEXT_STROKE[kind] or 1.5, true)
	label.Parent = parent
	return label
end

-- ===================== SCREEN =====================
local old = playerGui:FindFirstChild("HudStack")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "HudStack"
gui.ResetOnSpawn = false          -- built once per session, survives respawns
gui.IgnoreGuiInset = true         -- same coordinates as MainHUD
gui.DisplayOrder = 4              -- just under MainHUD (5), so every popup covers it
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui
HudStack.Gui = gui

local column = Instance.new("Frame")
column.Name = "Column"
column.AnchorPoint = Vector2.new(0.5, 0)
column.Position = UDim2.new(0.5, 0, 0, 192)
column.Size = UDim2.fromOffset(0, 0)
column.AutomaticSize = Enum.AutomaticSize.XY
column.BackgroundTransparency = 1
column.Parent = gui

local columnScale = Instance.new("UIScale")
columnScale.Parent = column

local columnLayout = Instance.new("UIListLayout")
columnLayout.FillDirection = Enum.FillDirection.Vertical
columnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
columnLayout.Padding = UDim.new(0, GAP)
columnLayout.Parent = column

-- A slim row at the top of the column for small status chips (Cosmic Level
-- and active boosts, drawn by BoostHUDClient). Hidden when it has nothing.
local statusRow = Instance.new("Frame")
statusRow.Name = "StatusRow"
statusRow.LayoutOrder = 0
statusRow.Size = UDim2.fromOffset(0, 0)
statusRow.AutomaticSize = Enum.AutomaticSize.XY
statusRow.BackgroundTransparency = 1
statusRow.Visible = false
statusRow.Parent = column

local statusLayout = Instance.new("UIListLayout")
statusLayout.FillDirection = Enum.FillDirection.Horizontal
statusLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
statusLayout.VerticalAlignment = Enum.VerticalAlignment.Center
statusLayout.SortOrder = Enum.SortOrder.LayoutOrder
statusLayout.Padding = UDim.new(0, 8)
statusLayout.Parent = statusRow

-- Returns the status row frame (parent small chips to it; set its Visible).
function HudStack.StatusRow()
	return statusRow
end

local slot = Instance.new("Frame")
slot.Name = "AnnouncementSlot"
slot.LayoutOrder = 1
slot.Size = UDim2.fromOffset(ANNOUNCE_WIDTH, 0)
slot.BackgroundTransparency = 1
slot.Visible = false
slot.Parent = column

local row = Instance.new("Frame")
row.Name = "Cards"
row.LayoutOrder = 2
row.Size = UDim2.fromOffset(0, 0)
row.AutomaticSize = Enum.AutomaticSize.XY
row.BackgroundTransparency = 1
row.Visible = false
row.Parent = column

local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Vertical
rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Padding = UDim.new(0, GAP)
rowLayout.Parent = row

-- The announcement slot's height is animated through this value, so the
-- width can still follow the screen while it opens or closes.
local slotHeight = Instance.new("NumberValue")
slotHeight.Value = 0

local function applySlotSize()
	slot.Size = UDim2.fromOffset(announceWidth, math.floor(slotHeight.Value + 0.5))
end
slotHeight.Changed:Connect(applySlotSize)

-- ===================== LAYOUT =====================
local anchors = {}   -- stardust / menu / playtime, measured from MainHUD

local function usable(object)
	return object ~= nil and object.Parent ~= nil
		and object.AbsoluteSize.X > 0 and object.AbsoluteSize.Y > 0
end

local function relayout()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local viewport = camera.ViewportSize
	if viewport.X < 2 or viewport.Y < 2 then return end

	local hudScale = math.clamp(math.min(viewport.X / DESIGN.X, viewport.Y / DESIGN.Y), HUD_MIN_SCALE, 1)
	local isCompact = viewport.Y < COMPACT_BELOW_HEIGHT

	-- Top: just under the Upgrade / Lock Base buttons (the Stardust counter
	-- lives bottom-left now). AbsolutePosition is measured from below Roblox's
	-- top bar, but these ScreenGuis ignore the top bar, so the inset is added
	-- back. MainHUD's own layout is the floor.
	local top = 14 + 78 * hudScale
	if usable(anchors.actions) then
		local inset = GuiService:GetGuiInset()
		top = math.max(top, inset.Y + anchors.actions.AbsolutePosition.Y + anchors.actions.AbsoluteSize.Y)
	end
	top += GAP * hudScale

	-- Width: the space between the side menu and the playtime button,
	-- kept symmetric so the column stays centred under the top buttons.
	local leftEdge = 20 + 184 * hudScale
	if usable(anchors.menu) then
		leftEdge = anchors.menu.AbsolutePosition.X + anchors.menu.AbsoluteSize.X
	end
	local rightEdge = 18 + 108 * hudScale
	if usable(anchors.playtime) then
		rightEdge = viewport.X - anchors.playtime.AbsolutePosition.X
	end
	local room = math.max(viewport.X - 2 * (math.max(leftEdge, rightEdge) + SIDE_CLEARANCE), 180)

	local shown = 0
	for _, card in ipairs(cards) do
		if card.Frame.Visible then shown += 1 end
	end
	row.Visible = shown > 0

	local base = math.clamp(hudScale, if isCompact then 0.6 else 0.5, 1)
	local newScale = math.min(base, room / CARD_WIDTH)
	local sideBySide = false
	if shown >= 2 then
		local fit = math.min(base, room / (shown * CARD_WIDTH + (shown - 1) * GAP))
		-- Side by side, unless that would shrink the text noticeably.
		if fit >= newScale * 0.85 then
			sideBySide = true
			newScale = fit
		end
	end
	if density == "COMPACT" then newScale *= CONDENSED_SHARE end
	newScale = math.max(newScale, 0.3)

	rowLayout.FillDirection = if sideBySide then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	column.Position = UDim2.new(0.5, 0, 0, math.floor(top + 0.5))
	announceWidth = math.floor(math.min(ANNOUNCE_WIDTH, room / newScale))
	applySlotSize()

	if isCompact ~= compact then
		compact = isCompact
		for label, kind in pairs(texts) do
			label.TextSize = textSize(kind)
		end
	end

	if math.abs(newScale - scale) > 0.001 then
		scale = newScale
		columnScale.Scale = scale
		for stroke, thickness in pairs(strokes) do
			stroke.Thickness = thickness * scale
		end
	end
end

local scheduled = false
local function schedule()
	if scheduled then return end
	scheduled = true
	task.defer(function()
		scheduled = false
		relayout()
	end)
end

-- Screen size
local cameraConnection
local function bindCamera()
	if cameraConnection then cameraConnection:Disconnect() end
	cameraConnection = nil
	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(schedule)
	end
	schedule()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()

-- FULL / COMPACT. Set by UILayoutManager; anyone may call it.
function HudStack.SetDensity(mode)
	mode = if mode == "COMPACT" then "COMPACT" else "FULL"
	if mode == density then return end
	density = mode
	schedule()
end

function HudStack.GetDensity()
	return density
end

-- The event / announcement column is optional HUD: the layout manager
-- condenses it during the tutorial and whenever something with a higher
-- priority (Nibbles) overlaps it.
task.defer(function()
	local module = game:GetService("ReplicatedStorage"):FindFirstChild("UILayoutManager")
	local ok, Layout = pcall(function() return module and require(module) end)
	if ok and type(Layout) == "table" and Layout.Register then
		Layout.Register("EventColumn", column, {
			Priority = 40,
			Optional = true,
			State = "EVENT",
			SetVariant = HudStack.SetDensity,
		})
	end
end)

-- MainHUD pieces (it can be rebuilt, so it is re-bound when it reappears)
local hudConnections = {}
local hudToken = 0
local ANCHOR_NAMES = { actions = "TopActionButtons", menu = "SideMenu", playtime = "PlaytimeSlot" }

local function bindMainHud(hud)
	hudToken += 1
	local token = hudToken
	for _, connection in ipairs(hudConnections) do connection:Disconnect() end
	table.clear(hudConnections)
	table.clear(anchors)
	schedule()

	for key, name in pairs(ANCHOR_NAMES) do
		task.spawn(function()
			local object = hud:FindFirstChild(name, true) or hud:WaitForChild(name, 30)
			if hudToken ~= token or not object or not object:IsA("GuiObject") then return end
			anchors[key] = object
			table.insert(hudConnections, object:GetPropertyChangedSignal("AbsolutePosition"):Connect(schedule))
			table.insert(hudConnections, object:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule))
			schedule()
		end)
	end
end

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "MainHUD" and child:IsA("ScreenGui") then
		bindMainHud(child)
	end
end)
do
	local hud = playerGui:FindFirstChild("MainHUD")
	if hud and hud:IsA("ScreenGui") then bindMainHud(hud) end
end

-- ===================== CARDS =====================
local Card = {}
Card.__index = Card

local FADE_IN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- A card is a Frame in the shared row. Add HudStack.Label children with
-- props.Order to stack them; the card's height follows its content.
function HudStack.Card(name, order, accent)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.LayoutOrder = order or 10
	frame.Size = UDim2.fromOffset(CARD_WIDTH, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = COLORS.Panel
	frame.BackgroundTransparency = CARD_BACKGROUND
	frame.BorderSizePixel = 0
	frame.Active = true   -- a click on a card never falls through to the world
	frame.Visible = false
	frame.Parent = row
	HudStack.Corner(frame, 14)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = frame

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = frame

	local card = setmetatable({
		Frame = frame,
		Stroke = HudStack.Stroke(frame, accent or COLORS.Calm, 3),
	}, Card)
	table.insert(cards, card)
	return card
end

function Card:SetVisible(visible)
	visible = visible == true
	if self.Frame.Visible == visible then return end
	self.Frame.Visible = visible
	schedule()
end

function Card:SetAccent(color)
	if self.Stroke.Color ~= color then
		self.Stroke.Color = color
	end
end

-- Transparency only, so nothing around the card moves while it plays.
function Card:FadeIn()
	local frame = self.Frame
	frame.BackgroundTransparency = 1
	TweenService:Create(frame, FADE_IN, { BackgroundTransparency = CARD_BACKGROUND }):Play()
	for _, object in ipairs(frame:GetDescendants()) do
		if object:IsA("TextLabel") then
			object.TextTransparency = 1
			TweenService:Create(object, FADE_IN, { TextTransparency = 0 }):Play()
		elseif object:IsA("UIStroke") then
			object.Transparency = 1
			TweenService:Create(object, FADE_IN, { Transparency = 0 }):Play()
		end
	end
end

-- ===================== ANNOUNCEMENTS =====================
-- Shown at the top of the column. It pushes the cards down rather than
-- covering them, and never covers the rest of the screen.
local panel = Instance.new("Frame")
panel.Name = "Announcement"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.fromScale(0.5, 0)
panel.Size = UDim2.new(1, 0, 0, ANNOUNCE_HEIGHT)
panel.BackgroundColor3 = COLORS.Panel
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = slot
HudStack.Corner(panel, 18)
local panelStroke = HudStack.Stroke(panel, COLORS.Amber, 4)

local panelPop = Instance.new("UIScale")
panelPop.Parent = panel

-- A short accent band along the top edge. It stays steady; nothing flashes.
local band = Instance.new("Frame")
band.Name = "Accent"
band.AnchorPoint = Vector2.new(0.5, 0)
band.Position = UDim2.new(0.5, 0, 0, 7)
band.Size = UDim2.new(0.42, 0, 0, 5)
band.BackgroundColor3 = COLORS.Amber
band.BorderSizePixel = 0
band.ZIndex = 2
band.Parent = panel
HudStack.Corner(band, 3)

local announceTitle = Instance.new("TextLabel")
announceTitle.Name = "Title"
announceTitle.BackgroundTransparency = 1
announceTitle.Font = HudStack.FONT
announceTitle.TextScaled = true   -- a long title shrinks onto one line instead of clipping
announceTitle.TextColor3 = COLORS.Text
announceTitle.Position = UDim2.new(0, 18, 0, 17)
announceTitle.Size = UDim2.new(1, -36, 0, 52)
announceTitle.ZIndex = 3
announceTitle.Parent = panel
do
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 46
	cap.MinTextSize = 22
	cap.Parent = announceTitle
end
local titleStroke = HudStack.Stroke(announceTitle, COLORS.Outline, 4, true)

local titleGradient = Instance.new("UIGradient")
titleGradient.Rotation = 90
titleGradient.Enabled = false
titleGradient.Parent = announceTitle

local announceSub = HudStack.Label(panel, "Status", { Name = "Subtitle" })
announceSub.AutomaticSize = Enum.AutomaticSize.None
announceSub.TextYAlignment = Enum.TextYAlignment.Top
announceSub.Position = UDim2.new(0, 22, 0, 72)
announceSub.Size = UDim2.new(1, -44, 0, 46)
local subStroke = announceSub:FindFirstChildOfClass("UIStroke")

local OPEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)   -- slight overshoot
local APPEAR = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function panelTransparency(alpha, info)
	local targets = {
		{ panel, "BackgroundTransparency" },
		{ band, "BackgroundTransparency" },
		{ announceTitle, "TextTransparency" },
		{ announceSub, "TextTransparency" },
		{ panelStroke, "Transparency" },
		{ titleStroke, "Transparency" },
		{ subStroke, "Transparency" },
	}
	for _, target in ipairs(targets) do
		if info then
			TweenService:Create(target[1], info, { [target[2]] = alpha }):Play()
		else
			target[1][target[2]] = alpha
		end
	end
end

local queue = {}
local current = nil
local token = 0
local present

local function finish(entry)
	if entry and entry.onHide then
		task.spawn(entry.onHide)
	end
end

local function takeNext()
	local now = os.clock()
	for i = #queue, 1, -1 do
		if now - queue[i].queuedAt > 8 then
			finish(table.remove(queue, i))   -- too old to still be news
		end
	end
	local best
	for i, entry in ipairs(queue) do
		if not best or entry.priority > queue[best].priority then best = i end
	end
	return best and table.remove(queue, best)
end

local function close(closingToken)
	panelTransparency(1, CLOSE)
	TweenService:Create(panelPop, CLOSE, { Scale = 0.92 }):Play()
	task.delay(0.25, function()
		if token ~= closingToken then return end
		local nextEntry = takeNext()
		if nextEntry then
			present(nextEntry)
			return
		end
		TweenService:Create(slotHeight, OPEN, { Value = 0 }):Play()
		task.delay(0.22, function()
			if token == closingToken then
				slot.Visible = false
			end
		end)
	end)
end

present = function(entry)
	token += 1
	local myToken = token
	current = entry

	local hasSubtitle = type(entry.subtitle) == "string" and entry.subtitle ~= ""
	local height = if hasSubtitle then ANNOUNCE_HEIGHT else ANNOUNCE_SHORT_HEIGHT
	local accent = entry.accent or COLORS.Amber

	announceTitle.Text = entry.title or ""
	announceSub.Text = if hasSubtitle then entry.subtitle else ""
	announceSub.Visible = hasSubtitle
	panel.Size = UDim2.new(1, 0, 0, height)
	panelStroke.Color = accent
	band.BackgroundColor3 = accent
	if entry.gradient then
		titleGradient.Color = entry.gradient
		titleGradient.Enabled = true
		announceTitle.TextColor3 = COLORS.Text
	else
		titleGradient.Enabled = false
		announceTitle.TextColor3 = accent
	end

	slot.Visible = true
	TweenService:Create(slotHeight, OPEN, { Value = height }):Play()
	panelTransparency(1)
	panelTransparency(0, APPEAR)
	panelPop.Scale = 0.6
	TweenService:Create(panelPop, POP, { Scale = 1 }):Play()

	if entry.onShow then
		task.spawn(entry.onShow)
	end

	task.delay(entry.seconds or 3, function()
		if token ~= myToken or current ~= entry then return end
		current = nil
		finish(entry)
		close(myToken)
	end)
end

-- entry = {
--   key = "ThievingTime",     -- a newer entry with the same key replaces it
--   priority = 10,            -- higher cuts in; lower waits its turn
--   title = "...", subtitle = "..." (optional),
--   accent = Color3, gradient = ColorSequence (optional, for the title),
--   seconds = 3.5,
--   onShow = function() end, onHide = function() end,   -- optional
-- }
function HudStack.Announce(entry)
	entry.priority = entry.priority or 1
	entry.queuedAt = os.clock()

	if entry.key then
		for i = #queue, 1, -1 do
			if queue[i].key == entry.key then
				finish(table.remove(queue, i))
			end
		end
	end

	if current and current.priority > entry.priority then
		table.insert(queue, entry)
		return
	end

	if current then
		local replaced = current
		current = nil
		finish(replaced)
	end
	present(entry)
end

-- Ends (or unqueues) announcements with this key.
function HudStack.Dismiss(key)
	for i = #queue, 1, -1 do
		if queue[i].key == key then
			finish(table.remove(queue, i))
		end
	end
	if current and current.key == key then
		local entry = current
		current = nil
		finish(entry)
		close(token)
	end
end

return HudStack
