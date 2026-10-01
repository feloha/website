-- REPLACE StarterPlayer > StarterPlayerScripts > MergeGuideClient (LocalScript).
-- Animated chevrons stream from your character toward one valid matching hole.
-- Client-only guidance; server ownership, merging and currency are unchanged.
-- No images, asset IDs, floor circles or additional scripts are required.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SizeVariants = require(ReplicatedStorage:WaitForChild("SizeVariantConfig"))
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local TierConfig = require(ReplicatedStorage:WaitForChild("BlackHoleTierConfig"))

local function optional(name)
	local module = ReplicatedStorage:FindFirstChild(name)
	local ok, result = pcall(function() return module and require(module) end)
	return if ok and type(result) == "table" then result else nil
end

local Settings = optional("ClientSettings")
local UiResponsive = optional("UiResponsive")
local Coordinator = optional("PresentationCoordinator")
local GuiManager = optional("GuiManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TAG = "BlackHole"
local FONT = Enum.Font.FredokaOne
local PALE = Color3.fromRGB(215, 245, 255)
local OUTLINE = Color3.fromRGB(12, 16, 34)
local LABEL_PADDING = 1.9     -- same anchor as BlackHoleLabelController (studs above the black hole)
local MARKER_LIFT = 142       -- pixels above that anchor: clears the name label card

local REFRESH_SECONDS = 0.2
local SWITCH_RATIO = 0.8
local SWITCH_STUDS = 3

-- Sizes are designed for a desktop screen; on phones everything (marker,
-- arrows, edge pointer, spacing) follows the same curve as the HUD instead
-- of staying desktop-sized on a tiny screen.
local function guideScale()
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.55, 1)
end

local function reduceMotion()
	return Settings ~= nil and Settings.Get ~= nil and Settings.Get("ReduceMotion") == true
end

local function guideEnabled()
	return not (Settings and Settings.Get and Settings.Get("MergeGuide") == false)
end

-- ===================== CLEAN START =====================
-- Removes anything the previous version of this script created (arrow, rings).
for _, name in ipairs({ "MergeGuide", "MergeGuideHint", "MergeGuideWorld", "MergeGuideEdge", "MergeGuideMarker", "MergeGuideTrail" }) do
	local old = playerGui:FindFirstChild(name)
	if old then old:Destroy() end
end
do
	local old = workspace:FindFirstChild("MergeGuideFX")
	if old then old:Destroy() end
end

-- ===================== SHAPES =====================
-- A chevron from two rounded bars with a dark outline. pointing = "down" | "right".
local function chevron(parent, size, pointing, z)
	local holder = Instance.new("Frame")
	holder.Name = "Chevron"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = size
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent
	local arms = if pointing == "down"
		then { { 0.32, 0.42, 40 }, { 0.68, 0.42, -40 } }
		else { { 0.42, 0.32, 40 }, { 0.42, 0.68, -40 } }
	for _, arm in ipairs(arms) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(arm[1], arm[2])
		bar.Size = if pointing == "down" then UDim2.fromScale(0.56, 0.26) else UDim2.fromScale(0.26, 0.56)
		bar.Rotation = if pointing == "down" then arm[3] else -arm[3]
		bar.BackgroundColor3 = PALE
		bar.BorderSizePixel = 0
		bar.ZIndex = z
		bar.Parent = holder
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = bar
		local stroke = Instance.new("UIStroke")
		stroke.Color = OUTLINE
		stroke.Thickness = 2
		stroke.Parent = bar
	end
	return holder
end

local function smallText(parent, text, size, z)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.Text = text
	label.TextSize = size
	label.TextColor3 = PALE
	label.ZIndex = z
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	return label
end

-- ===================== MARKER (one, reused) =====================
-- Plain frames only (no CanvasGroup: it doesn't render reliably inside a
-- BillboardGui). A small dark pill with "MERGE · T32" and a chevron under it.
local marker = Instance.new("BillboardGui")
marker.Name = "MergeGuideMarker"
marker.Size = UDim2.fromOffset(160, MARKER_LIFT + 66)
marker.SizeOffset = Vector2.new(0, 0.5)   -- bottom edge at the label anchor, content at the top
marker.AlwaysOnTop = true
marker.LightInfluence = 0
marker.MaxDistance = 260
marker.ResetOnSpawn = false
marker.Enabled = false
marker.Parent = playerGui

local markerGroup = Instance.new("Frame")
markerGroup.Name = "Group"
markerGroup.AnchorPoint = Vector2.new(0.5, 0)
markerGroup.Position = UDim2.new(0.5, 0, 0, 0)
markerGroup.Size = UDim2.new(1, 0, 0, 66)
markerGroup.BackgroundTransparency = 1
markerGroup.Parent = marker
local markerScale = Instance.new("UIScale")
markerScale.Parent = markerGroup

local pill = Instance.new("Frame")
pill.Name = "Pill"
pill.AnchorPoint = Vector2.new(0.5, 0)
pill.Position = UDim2.new(0.5, 0, 0, 0)
pill.Size = UDim2.fromOffset(142, 30)
pill.BackgroundColor3 = Color3.fromRGB(255, 194, 55)
pill.BackgroundTransparency = 0
pill.BorderSizePixel = 0
pill.Parent = markerGroup
do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pill
end
local pillStroke = Instance.new("UIStroke")
pillStroke.Color = OUTLINE
pillStroke.Thickness = 3
pillStroke.Transparency = 0
pillStroke.Parent = pill

local markerText = smallText(pill, "MERGE! · T1", 18, 2)
markerText.AnchorPoint = Vector2.new(0.5, 0.5)
markerText.Position = UDim2.fromScale(0.5, 0.5)
markerText.Size = UDim2.new(1, -8, 1, 0)
markerText.TextColor3 = Color3.new(1, 1, 1)
local badgeGloss = Instance.new("UIGradient")
badgeGloss.Color = ColorSequence.new(Color3.fromRGB(255, 230, 105), Color3.fromRGB(255, 157, 42))
badgeGloss.Rotation = 90
badgeGloss.Parent = pill

local markerChevron = chevron(markerGroup, UDim2.fromOffset(34, 22), "down", 2)
markerChevron.Position = UDim2.new(0.5, 0, 0, 49)
for _, bar in ipairs(markerChevron:GetChildren()) do
	if bar:IsA("Frame") then bar.BackgroundColor3 = Color3.fromRGB(255, 216, 74) end
end

-- Everything the fade touches, with its fully visible transparency.
local fadeTargets = {
	{ pill, "BackgroundTransparency", 0 },
	{ pillStroke, "Transparency", 0 },
	{ markerText, "TextTransparency", 0 },
}
for _, object in ipairs(markerText:GetChildren()) do
	if object:IsA("UIStroke") then table.insert(fadeTargets, { object, "Transparency", 0 }) end
end
for _, bar in ipairs(markerChevron:GetChildren()) do
	if bar:IsA("Frame") then
		table.insert(fadeTargets, { bar, "BackgroundTransparency", 0 })
		local stroke = bar:FindFirstChildOfClass("UIStroke")
		if stroke then table.insert(fadeTargets, { stroke, "Transparency", 0 }) end
	end
end

local fadeValue = Instance.new("NumberValue")   -- 0 = hidden, 1 = shown
fadeValue.Value = 0
local function applyFade(alpha)
	for _, item in ipairs(fadeTargets) do
		item[1][item[2]] = 1 - (1 - item[3]) * alpha
	end
end
fadeValue.Changed:Connect(applyFade)
applyFade(0)

-- ===================== OUTLINE (one, reused) =====================
-- The Highlight lives in its own client folder and points at the model with
-- Adornee. It is never parented inside a black hole model: those models are
-- rebuilt, and destroying one would destroy the Highlight with it.
local fxFolder = Instance.new("Folder")
fxFolder.Name = "MergeGuideFX"
fxFolder.Parent = workspace

local outline = nil
local function getOutline()
	if outline and outline.Parent == fxFolder then return outline end
	outline = Instance.new("Highlight")
	outline.Name = "MergeGuideOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = PALE
	outline.OutlineTransparency = 0.45
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Enabled = false
	outline.Parent = fxFolder
	return outline
end
getOutline()
local lastModelLookup = 0

-- ===================== EDGE CHEVRON (one, reused) =====================
local edgeGui = Instance.new("ScreenGui")
edgeGui.Name = "MergeGuideEdge"
edgeGui.ResetOnSpawn = false
edgeGui.IgnoreGuiInset = true
edgeGui.DisplayOrder = 2
pcall(function() edgeGui.ScreenInsets = Enum.ScreenInsets.None end)   -- positions are viewport coordinates
edgeGui.Enabled = false
edgeGui.Parent = playerGui

local edge = Instance.new("Frame")
edge.Name = "Edge"
edge.AnchorPoint = Vector2.new(0.5, 0.5)
edge.Size = UDim2.fromOffset(28, 28)
edge.BackgroundTransparency = 1
edge.Parent = edgeGui
local edgeChevron = chevron(edge, UDim2.fromOffset(20, 26), "right", 2)
edgeChevron.Position = UDim2.fromScale(0.5, 0.5)
local edgeText = smallText(edgeGui, "", 13, 2)
edgeText.AnchorPoint = Vector2.new(0.5, 0.5)
edgeText.Size = UDim2.fromOffset(80, 16)
local edgeScale = Instance.new("UIScale")
edgeScale.Parent = edge
local edgeTextScale = Instance.new("UIScale")
edgeTextScale.Parent = edgeText

-- Applies the size factor (only when it changes).
local appliedScale = nil
local trailArrows = {}
local function applyGuideScale()
	local s = guideScale()
	if s == appliedScale then return s end
	appliedScale = s
	markerScale.Scale = s
	marker.Size = UDim2.fromOffset(math.floor(160 * s), math.floor((MARKER_LIFT + 66) * s))
	markerGroup.Size = UDim2.new(1 / s, 0, 0, 66)
	edgeScale.Scale = s
	edgeTextScale.Scale = s
	for _, entry in ipairs(trailArrows) do
		entry.frame.Size = UDim2.fromOffset(math.floor(28 * s + 0.5), math.floor(36 * s + 0.5))
	end
	return s
end

-- A fixed pool of screen-projected chevrons. The path itself lives in world
-- space, so it follows the character and target naturally as the camera turns.
local trailGui = Instance.new("ScreenGui")
trailGui.Name = "MergeGuideTrail"
trailGui.IgnoreGuiInset = true
trailGui.ResetOnSpawn = false
trailGui.DisplayOrder = 2
pcall(function() trailGui.ScreenInsets = Enum.ScreenInsets.None end)   -- positions are viewport coordinates
trailGui.Enabled = false
trailGui.Parent = playerGui
for index = 1, 8 do
	local arrow = chevron(trailGui, UDim2.fromOffset(28, 36), "right", 1)
	arrow.Name = "FlowArrow" .. index
	arrow.Visible = false
	local bars = {}
	for _, bar in ipairs(arrow:GetChildren()) do
		if bar:IsA("Frame") then
			bar.BackgroundColor3 = Color3.fromRGB(105, 237, 255)
			local border = bar:FindFirstChildOfClass("UIStroke")
			if border then border.Thickness = 2.5 end
			table.insert(bars, {bar, border})
		end
	end
	trailArrows[index] = {frame = arrow, bars = bars}
end

-- ===================== REGISTRY =====================
local own = {}       -- [hole] = true (your black holes)
local watched = {}   -- [hole] = connections
local dirty = true

local function markDirty() dirty = true end

local function unwatch(hole)
	own[hole] = nil
	local list = watched[hole]
	if list then
		for _, connection in ipairs(list) do connection:Disconnect() end
		watched[hole] = nil
	end
	dirty = true
end

local WATCHED = { "Tier", "HeldBy", "MergeLocked", "Favorite", "BeingConsumed", "Defeated", "AttackingId", "FusionRevealAt", "OwnerPlateName", "SizeMultiplier", "StealReservedBy" }

local function watch(hole)
	if not hole:IsA("BasePart") or watched[hole] then return end
	local connections = {}
	watched[hole] = connections
	local function refreshOwner()
		own[hole] = if hole:GetAttribute("OwnerUserId") == player.UserId then true else nil
		dirty = true
	end
	table.insert(connections, hole:GetAttributeChangedSignal("OwnerUserId"):Connect(refreshOwner))
	for _, attribute in ipairs(WATCHED) do
		table.insert(connections, hole:GetAttributeChangedSignal(attribute):Connect(markDirty))
	end
	table.insert(connections, hole.AncestryChanged:Connect(function()
		if not hole:IsDescendantOf(workspace) then unwatch(hole) end
	end))
	refreshOwner()
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(unwatch)
for _, hole in ipairs(CollectionService:GetTagged(TAG)) do watch(hole) end

-- ===================== ELIGIBILITY =====================
local function tierOf(hole)
	return math.floor(tonumber(hole:GetAttribute("Tier")) or 0)
end

local function sizeOf(hole)
	return SizeVariants.Diameter(hole)
end

local function isAvailableTarget(hole, serverNow)
	return hole.Parent ~= nil and hole:IsDescendantOf(workspace)
		and hole:GetAttribute("OwnerUserId") == player.UserId
		and (tonumber(hole:GetAttribute("HeldBy")) or 0) == 0
		and hole:GetAttribute("MergeLocked") ~= true
		and hole:GetAttribute("Favorite") ~= true
		and not hole:GetAttribute("BeingConsumed")
		and not hole:GetAttribute("Defeated")
		and not hole:GetAttribute("AttackingId")
		and not hole:GetAttribute("StealReservedBy")
		and (tonumber(hole:GetAttribute("FusionRevealAt")) or 0) <= serverNow
end

local function findSource()
	for hole in pairs(own) do
		if hole:GetAttribute("HeldBy") == player.UserId and hole:IsDescendantOf(workspace) then
			return hole
		end
	end
	return nil
end

local function canMerge(carried)
	local tier = tierOf(carried)
	return tier > 0 and carried:GetAttribute("MergeLocked") ~= true
		and carried:GetAttribute("Favorite") ~= true
		and not carried:GetAttribute("BeingConsumed")
		and not carried:GetAttribute("Defeated")
		and not carried:GetAttribute("AttackingId")
		and TierConfig.GetNextTier(tier) ~= nil
end

local function flatDistance(a, b)
	local d = a - b
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

-- ===================== STATE =====================
local source, target = nil, nil
local dead = false

local function blocked()
	if not guideEnabled() or dead then return true end
	if Coordinator and Coordinator.IsCinematic and Coordinator.IsCinematic() then return true end
	if GuiManager and GuiManager.GetCurrent and GuiManager:GetCurrent() ~= nil then return true end
	return false
end

local function chooseTarget(serverNow)
	local tier = tierOf(source)
	local plate = source:GetAttribute("OwnerPlateName")
	local function samePlate(hole)
		return not plate or not hole:GetAttribute("OwnerPlateName") or hole:GetAttribute("OwnerPlateName") == plate
	end
	local origin = source.Position
	local best, bestDistance = nil, math.huge
	for hole in pairs(own) do
		if hole ~= source and tierOf(hole) == tier and samePlate(hole) and isAvailableTarget(hole, serverNow) then
			local distance = flatDistance(hole.Position, origin)
			if distance < bestDistance then best, bestDistance = hole, distance end
		end
	end
	if target and target ~= source and own[target] and tierOf(target) == tier and samePlate(target) and isAvailableTarget(target, serverNow) then
		local current = flatDistance(target.Position, origin)
		if best and best ~= target and bestDistance < current * SWITCH_RATIO and current - bestDistance > SWITCH_STUDS then
			return best
		end
		return target
	end
	return best
end

-- The visible model for a black hole (BlackHoleVisualClient draws models at the
-- black hole's position in workspace.CompleteBlackHoleVisuals).
local function modelFor(hole)
	local folder = workspace:FindFirstChild("CompleteBlackHoleVisuals")
	if not folder then return nil end
	-- An exact reference avoids highlighting a neighbouring black hole of the
	-- same tier. This lookup runs only when the target/model changes.
	for _, model in ipairs(folder:GetChildren()) do
		local reference = model:FindFirstChild("SourceBlackHole")
		if model:IsA("Model") and reference and reference:IsA("ObjectValue") and reference.Value == hole then
			return model
		end
	end
	local match = nil
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model.Name == "BlackHole_T" .. tierOf(hole)
			and not model:FindFirstChild("SourceBlackHole")
			and (model:GetPivot().Position - hole.Position).Magnitude < 0.2 then
			if match then return nil end -- ambiguous overlap: omit the outline
			match = model
		end
	end
	return match
end

local shownTarget = nil
local fadeTween = nil

local function fadeMarker(visible)
	if fadeTween then fadeTween:Cancel() end
	fadeTween = TweenService:Create(fadeValue, TweenInfo.new(if visible then 0.2 else 0.12), { Value = if visible then 1 else 0 })
	fadeTween:Play()
end

local function hideAll()
	if shownTarget then
		shownTarget = nil
		fadeMarker(false)
	end
	marker.Enabled = false
	marker.Adornee = nil
	local highlight = getOutline()
	highlight.Enabled = false
	highlight.Adornee = nil
	edgeGui.Enabled = false
	trailGui.Enabled = false
end

local function showTarget()
	if shownTarget ~= target then
		shownTarget = target
		marker.Adornee = target
		markerText.Text = ("MERGE! · T%d"):format(tierOf(target))
		marker.Enabled = true
		fadeValue.Value = 0
		fadeMarker(true)
		local highlight = getOutline()
		highlight.Adornee = nil
		highlight.Enabled = false
		lastModelLookup = 0
	end
	marker.StudsOffsetWorldSpace = SizeVariants.WorldCenter(target) - target.Position + Vector3.new(0, sizeOf(target) * 0.5 + LABEL_PADDING, 0)
	-- With name labels off, sit right above the black hole instead.
	local labelsOff = Settings and Settings.Get and Settings.Get("LabelMode") == "Off"
	local labelHeight = 0 -- no phantom space when world labels are hidden
	local holder = playerGui:FindFirstChild("BlackHoleLabels")
	if holder and not labelsOff then
		for _, label in ipairs(holder:GetChildren()) do
			if label:IsA("BillboardGui") and label.Adornee == target and label.Enabled then
				local root = label:FindFirstChild("Root")
				local layout = root and root:FindFirstChildOfClass("UIListLayout")
				local scale = root and root:FindFirstChildOfClass("UIScale")
				labelHeight = if layout then layout.AbsoluteContentSize.Y * (if scale then scale.Scale else 1) + 6 else 0
				break
			end
		end
	end
	marker.Size = UDim2.fromOffset(160, labelHeight + 66)
	-- Keep the outline on the target's model. Models can be rebuilt, so look it
	-- up again when it's gone (at most every 0.3 s, never every frame).
	local highlight = getOutline()
	local adornee = highlight.Adornee
	if not adornee or not adornee:IsDescendantOf(workspace) then
		highlight.Enabled = false
		local now = os.clock()
		if now - lastModelLookup >= 0.3 then
			lastModelLookup = now
			local model = modelFor(target)
			if model then
				highlight.Adornee = model
				highlight.Enabled = true
			end
		end
	end
end

local lastStatus = nil
local function status(text)
	if not RunService:IsStudio() or text == lastStatus then return end
	lastStatus = text
	print("[MergeGuide] " .. text)
end

local function refresh()
	dirty = false
	local serverNow = workspace:GetServerTimeNow()
	local newSource = findSource()
	if newSource ~= source then
		source = newSource
		target = nil
	end
	if not source then
		target = nil
		status("idle (not carrying)")
		return
	end
	if not canMerge(source) then
		target = nil
		status(("carrying T%d: can't merge (favorite, merging or last tier)"):format(tierOf(source)))
		return
	end
	if blocked() then
		target = nil
		local why = "menu open: " .. tostring(GuiManager and GuiManager:GetCurrent())
		if not guideEnabled() then
			why = "Merge Guide setting is off"
		elseif dead then
			why = "dead"
		elseif Coordinator and Coordinator.IsCinematic and Coordinator.IsCinematic() then
			why = "mutation reveal open"
		end
		status(("carrying T%d: hidden (%s)"):format(tierOf(source), why))
		return
	end
	target = chooseTarget(serverNow)
	if target then
		status(("carrying T%d: target %s"):format(tierOf(source), tostring(target:GetAttribute("BlackHoleId") or target.Name)))
	else
		status(("carrying T%d: no other eligible T%d on your base"):format(tierOf(source), tierOf(source)))
	end
end

-- ===================== EDGE PLACEMENT =====================
local function screenBounds(camera)
	local viewport = camera.ViewportSize
	local left, top, right, bottom = 0, 0, viewport.X, viewport.Y
	if UiResponsive and UiResponsive.SafeRect then
		local offset, size = UiResponsive.SafeRect()
		left, top, right, bottom = offset.X, offset.Y, offset.X + size.X, offset.Y + size.Y
		top = math.max(top, UiResponsive.TopInset and UiResponsive.TopInset() or 0)
	end
	local touch = (UiResponsive and UiResponsive.IsTouch and UiResponsive.IsTouch())
		or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
	local s = guideScale()
	-- The no-draw areas come from the real HUD, not fixed desktop numbers
	-- (110 px top / 200 px bottom left nothing of a 390 px phone screen).
	local function screenRect(object)
		if not (object and object:IsA("GuiObject") and object.Visible and object.AbsoluteSize.X > 1) then return nil end
		local at = if UiResponsive and UiResponsive.ToScreen then UiResponsive.ToScreen(object.AbsolutePosition) else object.AbsolutePosition
		return at, object.AbsoluteSize
	end
	local hud = playerGui:FindFirstChild("MainHUD")
	left += 36 * s
	right -= 36 * s
	local actionsAt, actionsSize = screenRect(hud and hud:FindFirstChild("TopActionButtons"))
	top = if actionsAt then math.max(top, actionsAt.Y + actionsSize.Y + 16 * s) else top + 110 * s
	bottom -= (if touch then 0.16 * viewport.Y else 120 * s)   -- thumbstick + jump button
	local actionGui = playerGui:FindFirstChild("BlackHoleActionUI")
	local cardAt = screenRect(actionGui and actionGui:FindFirstChild("CarryCard", true))
	if cardAt then bottom = math.min(bottom, cardAt.Y - 12 * s) end
	for _, name in ipairs({ "SideMenu", "StardustDisplay", "GemsDisplay" }) do
		local at, size = screenRect(hud and hud:FindFirstChild(name, true))
		if at then left = math.max(left, at.X + size.X + 20 * s) end
	end
	local playAt = screenRect(hud and hud:FindFirstChild("PlaytimeSlot"))
	if playAt then right = math.min(right, playAt.X - 20 * s) end
	if right - left < 120 then
		local middle = viewport.X / 2
		left, right = middle - 60, middle + 60
	end
	if bottom - top < 120 then
		local middle = viewport.Y / 2
		top, bottom = middle - 60, middle + 60
	end
	return left, top, right, bottom
end

local clock = 0
local lastPresentation = -math.huge
local function drawTrail(camera, left, top, right, bottom)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not source or not target then trailGui.Enabled = false return end
	local start = root.Position + root.CFrame.RightVector * 1.4 + Vector3.new(0, 1.7, 0)
	local finish = SizeVariants.WorldCenter(target) + Vector3.new(0, math.min(sizeOf(target) * 0.2, 1), 0)
	local distance = (finish - start).Magnitude
	if distance < 2 then trailGui.Enabled = false return end
	local control = (start + finish) * 0.5 + Vector3.new(0, math.clamp(distance * 0.12, 1, 4), 0)
	local a = camera:WorldToViewportPoint(start)
	local b = camera:WorldToViewportPoint(finish)
	local pixels = (Vector2.new(a.X, a.Y) - Vector2.new(b.X, b.Y)).Magnitude
	local count = math.clamp(math.floor(pixels / (58 * appliedScale)), 2, #trailArrows)
	local phase = if reduceMotion() then 0.5 else (clock * 0.65) % 1
	local function point(t)
		return start * (1 - t)^2 + control * (2 * (1 - t) * t) + finish * t^2
	end
	trailGui.Enabled = true
	for index, entry in ipairs(trailArrows) do
		local t = ((index - 1 + phase) / count)
		local visible = index <= count
		local sample, onScreen = camera:WorldToViewportPoint(point(math.clamp(t, 0, 1)))
		local nextPoint = camera:WorldToViewportPoint(point(math.clamp(t + 0.015, 0, 1)))
		visible = visible and onScreen and sample.Z > 0 and nextPoint.Z > 0
			and sample.X > left and sample.X < right and sample.Y > top and sample.Y < bottom
		local tangent = Vector2.new(nextPoint.X - sample.X, nextPoint.Y - sample.Y)
		entry.frame.Visible = visible and tangent.Magnitude > 0.2
		if entry.frame.Visible then
			entry.frame.Position = UDim2.fromOffset(sample.X, sample.Y)
			entry.frame.Rotation = math.deg(math.atan2(tangent.Y, tangent.X))
			local alpha = math.clamp(math.min(t / 0.16, (1-t) / 0.16), 0, 1) * 0.95
			for _, pair in ipairs(entry.bars) do
				pair[1].BackgroundTransparency = 1 - alpha
				if pair[2] then pair[2].Transparency = 1 - alpha end
			end
		end
	end
end

local function place()
	local camera = workspace.CurrentCamera
	if blocked() or not camera or not target or not target.Parent then
		hideAll()
		return
	end
	if shownTarget ~= target or clock - lastPresentation >= REFRESH_SECONDS then
		lastPresentation = clock
		showTarget()
	end

	-- Gentle drift (none with Reduce Motion).
	local drift = if reduceMotion() then 0 else math.sin(clock * 2.4) * 3
	markerGroup.Position = UDim2.new(0.5, 0, 0, drift)

	applyGuideScale()
	local left, top, right, bottom = screenBounds(camera)
	drawTrail(camera, left, top, right, bottom)
	local point, onScreen = camera:WorldToViewportPoint(target.Position + marker.StudsOffsetWorldSpace)
	local markerY = point.Y - marker.Size.Y.Offset + 33 * appliedScale
	if onScreen and point.Z > 0 and point.X >= 80 and point.X <= camera.ViewportSize.X - 80
		and markerY >= 28 and markerY <= camera.ViewportSize.Y - 60 then
		marker.Enabled = true
		edgeGui.Enabled = false
		return
	end

	marker.Enabled = false
	-- Off screen or behind: a small chevron at the edge, pointing the right way.
	-- Camera-space X/Y keep the correct side even behind the camera.
	local relative = camera.CFrame:PointToObjectSpace(SizeVariants.WorldCenter(target))
	local direction = Vector2.new(relative.X, -relative.Y)
	if onScreen and point.Z > 0 then
		direction = Vector2.new(point.X, point.Y) - Vector2.new((left + right) / 2, (top + bottom) / 2)
	elseif relative.Z > 0 and direction.Magnitude < 0.5 then
		direction = Vector2.new(0, 1)
	end
	if direction.Magnitude < 1e-3 then direction = Vector2.new(0, 1) end
	direction = direction.Unit

	local center = Vector2.new((left + right) / 2, (top + bottom) / 2)
	local reachX = if math.abs(direction.X) > 1e-4 then (right - left) / 2 / math.abs(direction.X) else math.huge
	local reachY = if math.abs(direction.Y) > 1e-4 then (bottom - top) / 2 / math.abs(direction.Y) else math.huge
	local spot = center + direction * math.min(reachX, reachY)
	edge.Position = UDim2.fromOffset(spot.X, spot.Y)
	edge.Rotation = math.deg(math.atan2(direction.Y, direction.X))
	local textSpot = spot - direction * 30 * appliedScale
	edgeText.Position = UDim2.fromOffset(textSpot.X, textSpot.Y)
	local studs = source and flatDistance(target.Position, source.Position) or 0
	edgeText.Text = ("MATCH! T%d"):format(tierOf(target))
	edgeGui.Enabled = true
end

-- ===================== LIFECYCLE =====================
local function watchCharacter(character)
	dead = false
	source, target = nil, nil
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			dead = true
			dirty = true
		end)
	end
	dirty = true
end
if player.Character then task.spawn(watchCharacter, player.Character) end
player.CharacterAdded:Connect(watchCharacter)
player.CharacterRemoving:Connect(function()
	dead = true
	dirty = true
end)

if Settings and Settings.OnChanged then
	Settings.OnChanged(function(key)
		if key == "MergeGuide" then dirty = true end
	end)
end
if Coordinator and Coordinator.Changed then Coordinator.Changed:Connect(markDirty) end
if GuiManager and GuiManager.Changed then GuiManager.Changed:Connect(markDirty) end

local sinceRefresh = 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	sinceRefresh += dt
	if dirty or sinceRefresh >= REFRESH_SECONDS then
		sinceRefresh = 0
		local ok, err = pcall(refresh)
		if not ok then
			warn("[MergeGuide] Refresh failed:", err)
			source, target = nil, nil
		end
	end
	if source and target then
		local ok, err = pcall(place)
		if not ok then
			warn("[MergeGuide] Placement failed:", err)
			hideAll()
		end
	elseif marker.Enabled or edgeGui.Enabled or trailGui.Enabled or (outline and outline.Enabled) then
		hideAll()
	end
end)
