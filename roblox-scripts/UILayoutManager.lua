-- UILayoutManager (ModuleScript in ReplicatedStorage)  -- NEW
-- One place that knows where every piece of HUD is, and keeps them apart.
-- Client only: require it from LocalScripts or client modules.
--
-- Scripts REGISTER their UI instead of patching positions per device:
--
--   local Layout = require(ReplicatedStorage.UILayoutManager)
--   Layout.Register("CarryCard", cardHolder, {
--       Priority = 70,               -- higher wins; lower gives way
--       CanMove = true,              -- may be moved to a candidate spot
--       Home = UDim2.new(0.5, 0, 1, -26),   -- where it lives when nothing is in the way
--       Candidates = { "BottomRight", "BottomLeft" },   -- PreferredRegion order
--       Place = function(position) ... end,  -- optional: the owner moves it
--       State = "INTERACTION",       -- shown = this UI state is active
--   })
--
-- Options (all optional):
--   Priority       number, default 50
--   CanMove        moves to the candidate with the least displacement
--   CanScale       with SetScale(scale): shrinks down to MinimumScale first
--   MinimumScale   default 0.8
--   CanHide        with SetHidden(bool): hidden as a last resort / by state
--   SetVariant     function("FULL" | "COMPACT"): a compact form (Island Event)
--   Optional       de-emphasised (compact, or hidden if HideInTutorial) in TUTORIAL
--   HideInModal    hidden (SetHidden) while a major window is open
--   Modal          this is a major window (only one shows; GuiManager does that)
--   State          "TUTORIAL" | "INTERACTION" | "COMBAT" | "EVENT" while shown
--   Transient      counts toward the occupancy budget (popping-up gameplay UI)
--   CompactWithStates  { TUTORIAL = true }: compact whenever that state is on
--   AvoidClearZone a movable entry never moves INTO the gameplay clear zone
--   Home / Candidates / Place   see above. Candidate names: BottomCenter,
--                  BottomRight, BottomLeft, RightCenter, LeftCenter,
--                  TopCenter, Center. Home is always tried first.
--
-- How it decides (event driven, debounced; nothing runs every frame):
--   1. The usable rectangle: the device safe area, below Roblox's top bar.
--      On touch screens the joystick and jump button are reserved too.
--   2. Entries are solved from the highest priority down. Fixed entries are
--      measured (AbsolutePosition / AbsoluteSize). A movable entry tries Home,
--      then each candidate, and each of those nudged clear of whatever it
--      hits; the valid spot closest to Home wins. It only moves if that beats
--      where it is now by a clear margin (hysteresis), and the move is a
--      0.2 s tween.
--   3. A fixed entry that is hit takes its compact form, then hides if it may.
--   4. Occupancy budget: not overlapping is not enough. When the transient
--      pieces together cover more than Layout.OccupancyBudget of the usable
--      screen, every transient piece but the most important one goes compact.
--   5. Gameplay clear zone: the middle of the screen (Layout.ClearZone) is
--      kept for the game. Movable pieces with AvoidClearZone never move into it.
--   Padding between pieces is responsive: 2.5% of the short side, 12-24 px.
--
-- Responsive scale and animation scale stay separate: a UIScale ON the
-- registered object is treated as its animation (pop in) and divided out;
-- UIScales on its parents are the responsive scale.
--
-- UI states (highest wins): MODAL > TUTORIAL > INTERACTION > COMBAT > EVENT > NORMAL.
-- Layout.GetState(), Layout.StateChanged:Connect(fn(state)), Layout.SetFlag("COMBAT", on).
--
-- Studio only: Ctrl+J toggles a visualiser with every rectangle labelled, and
-- Output prints "UI COLLISION: A <-> B" whenever two shown pieces overlap.
-- Objects tagged "UILayout" (CollectionService) register themselves as fixed
-- entries; attributes LayoutName / LayoutPriority / LayoutState are read.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function optionalModule(name)
	local module = ReplicatedStorage:FindFirstChild(name)
	if not (module and module:IsA("ModuleScript")) then return nil end
	local ok, result = pcall(require, module)
	return if ok and type(result) == "table" then result else nil
end
local UiResponsive = optionalModule("UiResponsive")

local Layout = {}

local STATE_ORDER = { "MODAL", "TUTORIAL", "INTERACTION", "COMBAT", "EVENT", "NORMAL" }
local MOVE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HYSTERESIS = 32          -- px a new spot must beat the current one by
local DEBOUNCE = 0.06

local entries = {}             -- array, registration order
local byName = {}
local flags = {}               -- manual states (COMBAT, ...)
local state = "NORMAL"

local stateEvent = Instance.new("BindableEvent")
Layout.StateChanged = stateEvent.Event
local solvedEvent = Instance.new("BindableEvent")
Layout.Solved = solvedEvent.Event

-- ===================== GEOMETRY =====================
local function screen()
	if UiResponsive then return UiResponsive.Screen() end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

local function toScreen(at)
	if UiResponsive then return UiResponsive.ToScreen(at) end
	return at + GuiService:GetGuiInset()
end

local function rect(x0, y0, x1, y1)
	return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

local function rectAt(topLeft, size)
	return rect(topLeft.X, topLeft.Y, topLeft.X + size.X, topLeft.Y + size.Y)
end

local function hits(a, b, pad)
	pad = pad or 0
	return a.x0 < b.x1 + pad and b.x0 < a.x1 + pad and a.y0 < b.y1 + pad and b.y0 < a.y1 + pad
end

local function inside(a, outer, tolerance)
	tolerance = tolerance or 1
	return a.x0 >= outer.x0 - tolerance and a.y0 >= outer.y0 - tolerance
		and a.x1 <= outer.x1 + tolerance and a.y1 <= outer.y1 + tolerance
end

local function centre(r)
	return Vector2.new((r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2)
end

local function fmt(r)
	return ("(%d,%d)-(%d,%d)"):format(r.x0, r.y0, r.x1, r.y1)
end

-- Responsive padding between pieces: 2.5% of the short side, 12-24 px.
function Layout.Padding()
	local size = screen()
	return math.clamp(math.floor(math.min(size.X, size.Y) * 0.025), 12, 24)
end

-- The rectangle HUD may use: safe area, below Roblox's top bar.
function Layout.UsableRect()
	local size = screen()
	local at, safe = Vector2.zero, size
	if UiResponsive then at, safe = UiResponsive.SafeRect() end
	local top = at.Y
	if UiResponsive then top = math.max(top, UiResponsive.TopInset()) end
	return rect(at.X, top, at.X + safe.X, at.Y + safe.Y)
end

-- The middle of the usable screen, kept for the game itself. The tutorial may
-- sit in it when it has to; contextual HUD (Attack / Drop) stays out.
Layout.ClearShare = Vector2.new(0.4, 0.4)
function Layout.ClearZone(usable)
	usable = usable or Layout.UsableRect()
	local w, h = usable.x1 - usable.x0, usable.y1 - usable.y0
	local cw, ch = w * Layout.ClearShare.X, h * Layout.ClearShare.Y
	local cx, cy = (usable.x0 + usable.x1) / 2, usable.y0 + h * 0.46
	return rect(cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2)
end

-- Share of the usable screen transient pieces may cover together.
Layout.OccupancyBudget = 0.3

local function isTouch()
	if UiResponsive and UiResponsive.InputMode then return UiResponsive.InputMode() == "Touch" end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Joystick and jump button. The jump button is measured when Roblox's touch
-- controls exist; the joystick is the thumb's resting zone, bottom-left.
function Layout.ReservedRects()
	local list = {}
	if not isTouch() then return list end
	local usable = Layout.UsableRect()
	local short = math.min(usable.x1 - usable.x0, usable.y1 - usable.y0)
	local touchGui = playerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") and jump.Visible and jump.AbsoluteSize.X > 4 then
		table.insert(list, { name = "JumpButton", rect = rectAt(toScreen(jump.AbsolutePosition), jump.AbsoluteSize) })
	else
		local side = short * 0.3
		table.insert(list, { name = "JumpButton", rect = rect(usable.x1 - side, usable.y1 - side, usable.x1, usable.y1) })
	end
	local side = short * 0.34
	table.insert(list, { name = "Joystick", rect = rect(usable.x0, usable.y1 - side, usable.x0 + side * 1.15, usable.y1) })
	return list
end

-- ===================== OBJECT HELPERS =====================
local function shown(object)
	local node = object
	while node do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("LayerCollector") then return node.Enabled end
		node = node.Parent
	end
	return false
end

local function ownScale(object)
	local scale = object:FindFirstChildOfClass("UIScale")
	return if scale and scale.Scale > 0.01 then scale.Scale else 1
end

-- Responsive scale: every UIScale on the parents (not the object's own).
local function parentScale(object)
	local k, node = 1, object.Parent
	while node and not node:IsA("LayerCollector") do
		local scale = node:FindFirstChildOfClass("UIScale")
		if scale then k *= scale.Scale end
		node = node.Parent
	end
	return math.max(k, 0.01)
end

local function parentRect(object)
	local parent = object.Parent
	if parent and (parent:IsA("GuiObject") or parent:IsA("LayerCollector")) then
		return toScreen(parent.AbsolutePosition), parent.AbsoluteSize
	end
	return Vector2.zero, screen()
end

-- The size without the object's own (animation) UIScale.
local function restingSize(entry)
	return entry.object.AbsoluteSize / ownScale(entry.object)
end

-- Where a Position would put the object, as a screen rectangle.
local function rectForPosition(entry, position)
	local object = entry.object
	local pAt, pSize = parentRect(object)
	local k = parentScale(object)
	local size = restingSize(entry)
	local point = pAt + Vector2.new(
		position.X.Scale * pSize.X + position.X.Offset * k,
		position.Y.Scale * pSize.Y + position.Y.Offset * k)
	return rectAt(point - object.AnchorPoint * size, size)
end

-- The Position (offsets, in the parent's own units) that puts it at rect r.
local function positionForRect(entry, r)
	local object = entry.object
	local pAt = parentRect(object)
	local k = parentScale(object)
	local size = Vector2.new(r.x1 - r.x0, r.y1 - r.y0)
	local point = Vector2.new(r.x0, r.y0) + object.AnchorPoint * size - pAt
	return UDim2.fromOffset(math.floor(point.X / k + 0.5), math.floor(point.Y / k + 0.5))
end

local function measuredRect(entry)
	local object = entry.object
	if object.AbsoluteSize.X < 2 or object.AbsoluteSize.Y < 2 then return nil end
	return rectAt(toScreen(object.AbsolutePosition), object.AbsoluteSize)
end

-- ===================== CANDIDATES =====================
local REGIONS = {
	BottomCenter = function(u, s, pad) return Vector2.new((u.x0 + u.x1 - s.X) / 2, u.y1 - pad - s.Y) end,
	BottomRight = function(u, s, pad) return Vector2.new(u.x1 - pad - s.X, u.y1 - pad - s.Y) end,
	BottomLeft = function(u, s, pad) return Vector2.new(u.x0 + pad, u.y1 - pad - s.Y) end,
	RightCenter = function(u, s, pad) return Vector2.new(u.x1 - pad - s.X, (u.y0 + u.y1 - s.Y) / 2) end,
	LeftCenter = function(u, s, pad) return Vector2.new(u.x0 + pad, (u.y0 + u.y1 - s.Y) / 2) end,
	TopCenter = function(u, s, pad) return Vector2.new((u.x0 + u.x1 - s.X) / 2, u.y0 + pad) end,
	Center = function(u, s, pad) return Vector2.new((u.x0 + u.x1 - s.X) / 2, (u.y0 + u.y1 - s.Y) / 2) end,
}

local function scaled(r, factor)
	-- Shrinks a rectangle around its anchor-free centre.
	if factor == 1 then return r end
	local c = centre(r)
	local hw, hh = (r.x1 - r.x0) * factor / 2, (r.y1 - r.y0) * factor / 2
	return rect(c.X - hw, c.Y - hh, c.X + hw, c.Y + hh)
end

-- isHome: an owner's designed spot only has to be free of real overlaps
-- (reserved zones ignored), except next to transient pieces, which always get
-- a visible gap. avoidClear: the gameplay clear zone counts as a blocker.
local function blocked(r, blockers, pad, isHome, avoidClear)
	for _, blocker in ipairs(blockers) do
		local skip = (blocker.clearZone and not avoidClear) or (isHome and blocker.reserved)
		if not skip then
			local p = if isHome and not blocker.transient then 0 else pad
			if hits(r, blocker.rect, p) then return blocker end
		end
	end
	return nil
end

-- Best spot for a movable entry, or nil.
local function solveMovable(entry, blockers, usable, pad, factor)
	local homeRect = scaled(rectForPosition(entry, entry.home), factor)
	local size = Vector2.new(homeRect.x1 - homeRect.x0, homeRect.y1 - homeRect.y0)
	local homeCentre = centre(homeRect)

	local bases = { { name = "Home", rect = homeRect, home = true } }
	for _, region in ipairs(entry.opts.Candidates or {}) do
		local fn = REGIONS[region]
		if fn then table.insert(bases, { name = region, rect = rectAt(fn(usable, size, pad), size) }) end
	end

	local options = {}
	for index, base in ipairs(bases) do
		table.insert(options, { name = base.name, rect = base.rect, home = base.home, order = index })
		-- Nudged clear of each thing it hits, in the four directions.
		for _, blocker in ipairs(blockers) do
			local b = blocker.rect
			if hits(base.rect, b, pad) then
				local r = base.rect
				local w, h = size.X, size.Y
				for _, at in ipairs({
					Vector2.new(b.x0 - pad - w, r.y0), Vector2.new(b.x1 + pad, r.y0),
					Vector2.new(r.x0, b.y0 - pad - h), Vector2.new(r.x0, b.y1 + pad),
				}) do
					table.insert(options, { name = base.name .. "+nudge", rect = rectAt(at, size), order = index })
				end
			end
		end
	end

	local best, bestScore
	for _, option in ipairs(options) do
		-- Home is where its owner designed it: it only has to be free of real
		-- overlaps. Every other spot keeps the full padding.
		local ok = inside(option.rect, usable, if option.home then 1e6 else 1)
			and not blocked(option.rect, blockers, pad, option.home, entry.opts.AvoidClearZone)
		if ok then
			local score = (centre(option.rect) - homeCentre).Magnitude + option.order * 4
			if not bestScore or score < bestScore then
				best, bestScore = option, score
			end
		end
	end
	if not best then return nil end

	-- Hysteresis: stay put unless the new spot is clearly better.
	local current = entry.target
	if current and current.factor == factor then
		local r = current.rect
		local stillOk = (current.home or inside(r, usable, 1))
			and not blocked(r, blockers, pad, current.home, entry.opts.AvoidClearZone)
		if stillOk then
			local score = (centre(r) - homeCentre).Magnitude + (current.order or 1) * 4
			if score <= bestScore + HYSTERESIS then return current end
		end
	end
	return { rect = best.rect, home = best.home, name = best.name, order = best.order, factor = factor }
end

-- ===================== APPLY =====================
local function place(entry, target)
	local same = entry.target and entry.target.home == target.home
		and entry.target.rect.x0 == target.rect.x0 and entry.target.rect.y0 == target.rect.y0
	entry.target = target
	if same and entry.placed then return end
	entry.placed = true
	local position = if target.home then entry.home else positionForRect(entry, scaled(target.rect, 1 / target.factor))
	if entry.opts.Place then
		task.spawn(entry.opts.Place, position, target.name)
	else
		if entry.tween then entry.tween:Cancel() end
		entry.tween = TweenService:Create(entry.object, MOVE_TWEEN, { Position = position })
		entry.tween:Play()
	end
end

local function setScale(entry, factor)
	if entry.scale == factor then return end
	entry.scale = factor
	if entry.opts.SetScale then task.spawn(entry.opts.SetScale, factor) end
end

local function setVariant(entry, variant)
	if entry.variant == variant then return end
	entry.variant = variant
	if entry.opts.SetVariant then task.spawn(entry.opts.SetVariant, variant) end
end

local function setHidden(entry, hidden)
	if entry.hidden == hidden then return end
	entry.hidden = hidden
	if entry.opts.SetHidden then task.spawn(entry.opts.SetHidden, hidden) end
end

-- ===================== STATE =====================
local function computeState(visible)
	local active = {}
	local GuiManager = Layout._guiManager
	if GuiManager then
		local ok, current = pcall(GuiManager.GetCurrent, GuiManager)
		if ok and current ~= nil then active.MODAL = true end
	end
	for _, entry in ipairs(entries) do
		if visible[entry] and entry.opts.State then active[entry.opts.State] = true end
		if visible[entry] and entry.opts.Modal then active.MODAL = true end
	end
	for name, on in pairs(flags) do
		if on then active[name] = true end
	end
	for _, name in ipairs(STATE_ORDER) do
		if active[name] then return name end
	end
	return "NORMAL"
end

-- ===================== SOLVE =====================
local collisions = {}          -- "A|B" = true while overlapping (warned once)
local debugDraw                -- set by the Studio visualiser

local function solve()
	local usable = Layout.UsableRect()
	local pad = Layout.Padding()
	local reserved = Layout.ReservedRects()

	-- Who is on screen. Hidden-by-us entries still count as wanting space.
	local visible = {}
	for _, entry in ipairs(entries) do
		local object = entry.object
		local sized = object.AbsoluteSize.X >= 2 and object.AbsoluteSize.Y >= 2   -- an empty list is not "shown"
		if object.Parent and ((shown(object) and sized) or entry.hidden) then
			visible[entry] = true
		end
	end

	local newState = computeState(visible)
	if newState ~= state then
		state = newState
		stateEvent:Fire(state)
	end

	-- Occupancy: how much of the usable screen the transient pieces cover.
	local usableArea = math.max((usable.x1 - usable.x0) * (usable.y1 - usable.y0), 1)
	local covered, topTransient = 0, nil
	for _, entry in ipairs(entries) do
		if visible[entry] and entry.opts.Transient and not entry.hidden then
			local r = measuredRect(entry)
			if r then covered += (r.x1 - r.x0) * (r.y1 - r.y0) end
			if not topTransient or entry.priority > topTransient.priority then topTransient = entry end
		end
	end
	local occupancy = covered / usableArea
	if occupancy > Layout.OccupancyBudget then
		Layout._crowded = true
	elseif occupancy < Layout.OccupancyBudget * 0.75 then
		Layout._crowded = false   -- hysteresis: compact pieces are smaller, so leave only when clearly fine
	end

	-- State rules first: they decide what is in play at all.
	for _, entry in ipairs(entries) do
		local opts = entry.opts
		local hideByState = (state == "MODAL" and opts.HideInModal)
			or (state == "TUTORIAL" and opts.Optional and opts.HideInTutorial)
		if opts.CanHide or opts.HideInModal or opts.HideInTutorial then
			entry.stateHidden = hideByState and true or false
		end
		entry.wantCompact = (state == "TUTORIAL" and opts.Optional == true)
			or (opts.CompactWithStates ~= nil and opts.CompactWithStates[state] == true)
			or (Layout._crowded == true and opts.Transient == true and entry ~= topTransient)
	end

	local sorted = {}
	for _, entry in ipairs(entries) do table.insert(sorted, entry) end
	table.sort(sorted, function(a, b)
		if a.priority ~= b.priority then return a.priority > b.priority end
		return a.index < b.index
	end)

	local blockers = {}
	for _, zone in ipairs(reserved) do
		table.insert(blockers, { name = zone.name, rect = zone.rect, reserved = true })
	end
	local clearZone = Layout.ClearZone(usable)
	table.insert(blockers, { name = "GameplayClearZone", rect = clearZone, reserved = true, clearZone = true })

	local final = {}           -- [entry] = rect actually used
	for _, entry in ipairs(sorted) do
		local opts = entry.opts
		if not visible[entry] then
			if entry.compactBecause then entry.compactBecause = nil end
			if not entry.stateHidden then setHidden(entry, false) end
			setVariant(entry, if entry.wantCompact then "COMPACT" else "FULL")
		elseif entry.stateHidden then
			setHidden(entry, true)
		elseif opts.CanMove and entry.home then
			setVariant(entry, if entry.wantCompact then "COMPACT" else "FULL")
			local target
			local factor = 1
			while true do
				target = solveMovable(entry, blockers, usable, pad, factor)
				if target or not (opts.CanScale and opts.SetScale) then break end
				factor -= 0.05
				if factor < (opts.MinimumScale or 0.8) - 1e-3 then break end
			end
			if target then
				setHidden(entry, false)
				setScale(entry, target.factor)
				place(entry, target)
				final[entry] = target.rect
			elseif opts.CanHide and opts.SetHidden then
				setHidden(entry, true)
			else
				-- Nowhere is free: home, and the collision is reported.
				setHidden(entry, false)
				setScale(entry, 1)
				place(entry, { rect = rectForPosition(entry, entry.home), home = true, name = "Home", order = 1, factor = 1 })
				final[entry] = entry.target.rect
			end
		else
			local r = measuredRect(entry)
			if r then
				local hit = blocked(r, blockers, 0, true, false)   -- real overlaps only
				if hit and hit.reserved then hit = nil end
				-- Compact while something important sits on it; back to full
				-- only once that thing is gone or clearly clear of it.
				if hit and opts.SetVariant then
					entry.compactBecause = hit.name
				elseif entry.compactBecause then
					local other = byName[entry.compactBecause]
					local otherRect = other and final[other]
					if not otherRect or not hits(scaled(r, 1.25), otherRect, pad) then
						entry.compactBecause = nil
					end
				end
				local compact = entry.wantCompact or entry.compactBecause ~= nil
				setVariant(entry, if compact then "COMPACT" else "FULL")
				if hit and not opts.SetVariant and opts.CanHide and opts.SetHidden then
					setHidden(entry, true)
				elseif not entry.stateHidden then
					setHidden(entry, false)
				end
				if not entry.hidden then final[entry] = r end
			end
		end
		if final[entry] then
			table.insert(blockers, { name = entry.name, rect = final[entry], entry = entry, transient = opts.Transient == true })
		end
	end

	-- Report what is still overlapping (Studio only).
	if RunService:IsStudio() then
		local now = {}
		local list = {}
		for _, entry in ipairs(sorted) do
			if final[entry] then table.insert(list, entry) end
		end
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i], list[j]
				local allowed = (a.opts.AllowOverlap and a.opts.AllowOverlap[b.name])
					or (b.opts.AllowOverlap and b.opts.AllowOverlap[a.name])
				if not allowed and hits(final[a], final[b]) then
					local key = a.name .. "|" .. b.name
					now[key] = true
					if not collisions[key] then
						warn(("UI COLLISION: %s <-> %s   %s x %s"):format(a.name, b.name, fmt(final[a]), fmt(final[b])))
					end
				end
			end
		end
		collisions = now
	end

	Layout._last = { usable = usable, reserved = reserved, final = final, sorted = sorted, pad = pad,
		clearZone = clearZone, occupancy = occupancy }
	if debugDraw then debugDraw() end
	solvedEvent:Fire(state)
end

local pending = false
local function schedule(immediate)
	if pending then return end
	pending = true
	local function run()
		pending = false
		local ok, err = pcall(solve)
		if not ok then warn("[UILayoutManager] " .. tostring(err)) end
	end
	if immediate then task.defer(run) else task.delay(DEBOUNCE, run) end
end
Layout.Refresh = function() schedule(true) end

-- ===================== REGISTRATION =====================
local function watch(entry)
	local object = entry.object
	local connections = entry.connections
	table.insert(connections, object:GetPropertyChangedSignal("Visible"):Connect(function() schedule(true) end))
	table.insert(connections, object:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() schedule() end))
	if not entry.opts.CanMove then
		-- A movable entry's own movement is ours; only fixed ones are watched.
		table.insert(connections, object:GetPropertyChangedSignal("AbsolutePosition"):Connect(function() schedule() end))
	end
	local gui = object:FindFirstAncestorWhichIsA("LayerCollector")
	if gui then
		table.insert(connections, gui:GetPropertyChangedSignal("Enabled"):Connect(function() schedule(true) end))
	end
	table.insert(connections, object.AncestryChanged:Connect(function(_, parent)
		if parent == nil then Layout.Unregister(entry.name) else schedule(true) end
	end))
end

function Layout.Register(name, object, opts)
	assert(type(name) == "string", "UILayoutManager.Register: name")
	if not (object and object:IsA("GuiObject")) then return nil end
	Layout.Unregister(name)
	opts = opts or {}
	local entry = {
		name = name, object = object, opts = opts,
		priority = opts.Priority or 50,
		home = opts.Home or (if opts.CanMove then object.Position else nil),
		index = #entries + 1, connections = {},
		variant = "FULL", hidden = false, scale = 1,
	}
	table.insert(entries, entry)
	byName[name] = entry
	watch(entry)
	schedule(true)
	return entry
end

function Layout.Unregister(name)
	local entry = byName[name]
	if not entry then return end
	byName[name] = nil
	for _, connection in ipairs(entry.connections) do connection:Disconnect() end
	local index = table.find(entries, entry)
	if index then table.remove(entries, index) end
	for i, other in ipairs(entries) do other.index = i end
	schedule(true)
end

-- The owner changed where its piece lives (e.g. a new phone layout).
function Layout.SetHome(name, position)
	local entry = byName[name]
	if not entry then return end
	entry.home = position
	entry.target = nil
	entry.placed = false
	schedule(true)
end

function Layout.GetState()
	return state
end

function Layout.SetFlag(name, on)
	flags[name] = on and true or nil
	schedule(true)
end

-- Registers a piece another script builds, once it exists.
function Layout.Track(guiName, objectName, name, opts)
	task.spawn(function()
		local function bind(gui)
			local object = gui:FindFirstChild(objectName, true) or gui:WaitForChild(objectName, 30)
			if object and object:IsA("GuiObject") and byName[name] == nil then
				Layout.Register(name, object, opts)
			end
		end
		local gui = playerGui:FindFirstChild(guiName)
		if gui then bind(gui) end
		playerGui.ChildAdded:Connect(function(child)
			if child.Name == guiName then
				Layout.Unregister(name)
				task.defer(bind, child)
			end
		end)
	end)
end

-- ===================== TRIGGERS =====================
if UiResponsive and UiResponsive.Changed then
	UiResponsive.Changed:Connect(function() schedule(true) end)
end
do
	local function bindCamera()
		local camera = workspace.CurrentCamera
		if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() schedule() end) end
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()
end
task.spawn(function()
	local GuiManager = optionalModule("GuiManager")
	Layout._guiManager = GuiManager
	if GuiManager and GuiManager.Changed then
		GuiManager.Changed:Connect(function() schedule(true) end)
	end
	schedule(true)
end)

-- The fixed HUD zones every other piece has to respect.
Layout.Track("MainHUD", "TopActionButtons", "TopActions", { Priority = 80 })
Layout.Track("MainHUD", "SideMenu", "LeftActionGrid", { Priority = 80 })
Layout.Track("MainHUD", "PlaytimeSlot", "Playtime", { Priority = 80 })
Layout.Track("MainHUD", "StardustDisplay", "Stardust", { Priority = 75 })
Layout.Track("MainHUD", "GemsDisplay", "Gems", { Priority = 75 })
Layout.Track("SettingsHUD", "SettingsButtonHolder", "Settings", { Priority = 75 })

-- CollectionService: tag a GuiObject "UILayout" to register it as fixed.
do
	local function fromTag(object)
		if not object:IsA("GuiObject") or not object:IsDescendantOf(playerGui) then return end
		Layout.Register(object:GetAttribute("LayoutName") or object:GetFullName(), object, {
			Priority = object:GetAttribute("LayoutPriority") or 50,
			State = object:GetAttribute("LayoutState"),
		})
	end
	for _, object in ipairs(CollectionService:GetTagged("UILayout")) do task.spawn(fromTag, object) end
	CollectionService:GetInstanceAddedSignal("UILayout"):Connect(fromTag)
end

-- ===================== STUDIO VISUALISER =====================
if RunService:IsStudio() then
	local gui = Instance.new("ScreenGui")
	gui.Name = "UILayoutDebug"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
	gui.DisplayOrder = 1000
	gui.Enabled = false
	gui.Parent = playerGui

	local function box(r, colour, label, thickness)
		local f = Instance.new("Frame")
		f.BackgroundTransparency = 1
		f.Position = UDim2.fromOffset(r.x0, r.y0)
		f.Size = UDim2.fromOffset(r.x1 - r.x0, r.y1 - r.y0)
		f.Active = false
		f.Parent = gui
		local s = Instance.new("UIStroke")
		s.Color = colour
		s.Thickness = thickness or 2
		s.Parent = f
		if label then
			local t = Instance.new("TextLabel")
			t.BackgroundColor3 = Color3.new(0, 0, 0)
			t.BackgroundTransparency = 0.35
			t.TextColor3 = colour
			t.Font = Enum.Font.GothamBold
			t.TextSize = 12
			t.AutomaticSize = Enum.AutomaticSize.XY
			t.Size = UDim2.new()
			t.Text = " " .. label .. " "
			t.Parent = f
		end
	end

	debugDraw = function()
		if not gui.Enabled then return end
		gui:ClearAllChildren()
		local last = Layout._last
		if not last then return end
		box(last.usable, Color3.fromRGB(80, 160, 255), ("usable  pad %d  occupancy %d%%%s"):format(last.pad,
			math.floor(last.occupancy * 100 + 0.5), if Layout._crowded then "  CROWDED" else ""), 1)
		box(last.clearZone, Color3.fromRGB(255, 220, 90), "gameplay clear zone", 1)
		for _, zone in ipairs(last.reserved) do
			box(zone.rect, Color3.fromRGB(160, 160, 160), zone.name .. " (reserved)", 1)
		end
		for _, entry in ipairs(last.sorted) do
			local r = last.final[entry]
			if r then
				local hit = false
				for key in pairs(collisions) do
					if key:find(entry.name, 1, true) then hit = true break end
				end
				local tag = ("%s  P%d%s%s"):format(entry.name, entry.priority,
					if entry.variant == "COMPACT" then "  COMPACT" else "",
					if entry.target and not entry.target.home then "  -> " .. entry.target.name else "")
				box(r, if hit then Color3.fromRGB(255, 70, 70) else Color3.fromRGB(90, 255, 140), tag)
			end
		end
		box(rect(8, 8, 9, 9), Color3.new(1, 1, 1), "STATE " .. state, 1)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.J and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			gui.Enabled = not gui.Enabled
			if gui.Enabled then debugDraw() else gui:ClearAllChildren() end
			print("[UILayoutManager] visualiser " .. (if gui.Enabled then "on" else "off") .. ", state " .. state)
		end
	end)
end

return Layout
