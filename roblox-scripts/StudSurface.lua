-- StudSurface (ModuleScript in ReplicatedStorage)
-- The one system for molded toy-brick studs on chunky HUD buttons.
-- Client only.
--
--   local StudSurface = require(ReplicatedStorage.StudSurface)
--   StudSurface.Apply(face, {
--       Color = buttonColor,            -- the button's own plastic colour
--       Icon = iconFrame, Label = nameLabel,
--       CornerRadius = 28, RimInset = 5, -- the face's curve and inner rim
--       Behind = "fade",                -- or "hide": what studs under content do
--       Marks = { { 1, 1, 14 } },       -- "+" marks: { gap column, gap row, size }
--   })
--
-- Each stud is drawn, not a texture (the tiled texture rbxassetid://140302758156355
-- rendered as fine ridges at button size):
--   Shadow     contact shadow in a darker shade of the same plastic, down-right
--   Body       the button's own colour, lit upper-left, shaded lower-right,
--              with a faint rim - molded from the face, not glued on
--   Highlight  a soft white crescent on the upper-left shoulder
--
-- Layout (recomputed only when the tile's design size or its name changes -
-- never during hover / press, so nothing blinks):
--   * one even grid, edge to edge, perfectly symmetric left/right;
--   * studs that would cross the rounded inner rim at a corner are dropped;
--   * studs under the content: "fade" keeps every grid position (no gaps)
--     and presses those behind the name back; "hide" leaves the gift / name
--     clear, as on the Playtime Awards reference. Either way the decision is
--     mirrored, so both sides always match;
--   * "+" marks sit exactly in the gaps between four studs;
--   * faces smaller than MinFace (a tiny phone gear) get no studs at all.
-- Every part is Active = false and a child of the face, so presses and hover
-- bounces carry it and it never takes a tap.
--
-- StudSurface.StudImage: an asset id of ONE stud draws each Body with that
-- picture instead (kept round). SHOW_STUD_BOUNDS outlines the layer.

local TextService = game:GetService("TextService")

local StudSurface = {}
print("[StudSurface] build 2026-10-01g (reference pass)")

StudSurface.AssetId = "rbxassetid://140302758156355"
StudSurface.StudImage = nil
StudSurface.SHOW_STUD_BOUNDS = false

local INK = Color3.fromRGB(20, 28, 65)
local WHITE = Color3.new(1, 1, 1)

local DEFAULTS = {
	ZIndex = 1,               -- under the face's rim light, gloss and the content
	Margin = 10,              -- design px from the face edge to the first stud's edge
	SizeShare = 0.15,         -- stud diameter as a share of the face's short side
	MinDiameter = 12,
	MaxDiameter = 20,
	MinScreenPx = 9,          -- never smaller than this on screen
	PitchShare = 1.75,        -- centre-to-centre, in diameters
	MaxColumns = 9,
	MaxRows = 4,
	MinFace = 50,             -- smaller faces: no studs
	CornerRadius = 0,
	RimInset = 0,
	Behind = "fade",
	IconCore = 0.8,           -- share of the icon box that counts as the artwork
	AvoidPad = 1.5,
	MarksMinWidth = 120,
}

local function scaleOf(object)
	local k, node = 1, object
	while node and not node:IsA("LayerCollector") do
		for _, child in ipairs(node:GetChildren()) do
			if child:IsA("UIScale") then k *= child.Scale end
		end
		node = node.Parent
	end
	return math.max(k, 0.01)
end

local function round(parent, name, size, position, color, z, transparency)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = z
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = f
	return f
end

local function buildStud(layer, x, y, d, color, faded)
	local stud = Instance.new("Frame")
	stud.Name = "Stud"
	stud.AnchorPoint = Vector2.new(0.5, 0.5)
	stud.Position = UDim2.fromOffset(x, y)
	stud.Size = UDim2.fromOffset(d, d)
	stud.BackgroundTransparency = 1
	stud.Active = false
	stud.ZIndex = 1
	stud.Parent = layer
	local square = Instance.new("UIAspectRatioConstraint")   -- always a circle
	square.AspectRatio = 1
	square.Parent = stud

	round(stud, "Shadow", UDim2.fromScale(1, 1), UDim2.new(0.5, d * 0.07, 0.5, d * 0.11), color:Lerp(INK, 0.5), 1,
		if faded then 0.82 else 0.45)

	if StudSurface.StudImage then
		local picture = Instance.new("ImageLabel")
		picture.Name = "Body"
		picture.AnchorPoint = Vector2.new(0.5, 0.5)
		picture.Position = UDim2.fromScale(0.5, 0.5)
		picture.Size = UDim2.fromScale(1, 1)
		picture.BackgroundTransparency = 1
		picture.Image = StudSurface.StudImage
		picture.ImageColor3 = color
		picture.ImageTransparency = if faded then 0.55 else 0
		picture.ScaleType = Enum.ScaleType.Fit
		picture.Active = false
		picture.ZIndex = 2
		picture.Parent = stud
		return stud
	end

	local body = round(stud, "Body", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), WHITE, 2, if faded then 0.55 else 0)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 45
	shade.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(WHITE, 0.5)),
		ColorSequenceKeypoint.new(0.4, color:Lerp(WHITE, 0.08)),
		ColorSequenceKeypoint.new(1, color:Lerp(INK, 0.2)),
	})
	shade.Parent = body
	local rim = Instance.new("UIStroke")
	rim.Color = color:Lerp(INK, 0.35)
	rim.Thickness = math.max(1, d * 0.05)
	rim.Transparency = if faded then 0.85 else 0.55
	rim.Parent = body

	local glint = round(body, "Highlight", UDim2.fromScale(0.42, 0.24), UDim2.fromScale(0.36, 0.27), WHITE, 3,
		if faded then 0.75 else 0.3)
	glint.Rotation = -38
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0, 0.7)
	fade.Parent = glint
	return stud
end

-- A "+" printed on the plastic: a light tint of the button colour.
local function buildMark(layer, x, y, size, color)
	local mark = Instance.new("Frame")
	mark.Name = "Plus"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromOffset(x, y)
	mark.Size = UDim2.fromOffset(size, size)
	mark.BackgroundTransparency = 1
	mark.Active = false
	mark.ZIndex = 3
	mark.Parent = layer
	for _, horizontal in ipairs({ true, false }) do
		local bar = Instance.new("Frame")
		bar.Active = false
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = if horizontal then UDim2.new(1, 0, 0.34, 0) else UDim2.new(0.34, 0, 1, 0)
		bar.BackgroundColor3 = color:Lerp(WHITE, 0.8)
		bar.BackgroundTransparency = 0.06
		bar.ZIndex = 3
		bar.Parent = mark
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = bar
	end
end

-- Rectangles relative to the face, in design px.
local function localRect(object, face, k)
	if not (object and object.Parent and object:IsA("GuiObject") and object.Visible) then return nil end
	if object.AbsoluteSize.X < 1 then return nil end
	return (object.AbsolutePosition - face.AbsolutePosition) / k, object.AbsoluteSize / k
end

-- The label's actual lettering, not its whole box.
local function textRect(label, face, k)
	if not (label and label:IsA("TextLabel")) or label.Text == "" then return nil end
	local at, size = localRect(label, face, k)
	if not at then return nil end
	local textSize = if label.TextScaled then size.Y else label.TextSize
	local bounds = TextService:GetTextSize(label.Text, textSize, label.Font, Vector2.new(10000, 10000))
	local w, h = math.min(bounds.X + 4, size.X), math.min(bounds.Y * 0.8, size.Y)
	local left = at.X + (size.X - w) / 2
	if label.TextXAlignment == Enum.TextXAlignment.Left then left = at.X end
	if label.TextXAlignment == Enum.TextXAlignment.Right then left = at.X + size.X - w end
	local top = at.Y + (size.Y - h) / 2
	return { left, top, left + w, top + h }
end

local function coreRect(object, face, k, share)
	local at, size = localRect(object, face, k)
	if not at then return nil end
	local inset = size * (1 - share) / 2
	return { at.X + inset.X, at.Y + inset.Y, at.X + size.X - inset.X, at.Y + size.Y - inset.Y }
end

local function circleHits(x, y, r, rect)
	local nx = math.clamp(x, rect[1], rect[3])
	local ny = math.clamp(y, rect[2], rect[4])
	return (x - nx) ^ 2 + (y - ny) ^ 2 < r * r
end

function StudSurface.Apply(face, options)
	if not (face and face:IsA("GuiObject")) then return nil end
	local opts = {}
	for key, value in pairs(DEFAULTS) do opts[key] = value end
	for key, value in pairs(options or {}) do opts[key] = value end
	local color = opts.Color or face.BackgroundColor3

	-- One stud system: drop the old tiled texture and any earlier layer.
	for _, child in ipairs(face:GetChildren()) do
		if child.Name == "StudOverlay" or child.Name == "StudLayer" then child:Destroy() end
	end

	local layer = Instance.new("Frame")
	layer.Name = "StudLayer"
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.Active = false
	pcall(function() layer.Interactable = false end)
	layer.ZIndex = opts.ZIndex
	layer.Parent = face
	if StudSurface.SHOW_STUD_BOUNDS then
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(255, 40, 40)
		s.Parent = layer
	end

	local lastKey = nil
	local lastW, lastH = -1, -1
	local function layout(force)
		if not layer.Parent then return end
		local k = scaleOf(face)
		local size = face.AbsoluteSize / k
		if size.X < 8 or size.Y < 8 then return end
		local W, H = math.floor(size.X + 0.5), math.floor(size.Y + 0.5)
		if not force and math.abs(W - lastW) <= 3 and math.abs(H - lastH) <= 3 then return end
		lastW, lastH = W, H

		local spots, marks = {}, {}
		local d = math.clamp(math.min(W, H) * opts.SizeShare, opts.MinDiameter, opts.MaxDiameter)
		d = math.max(d, opts.MinScreenPx / k)
		local r = d / 2
		if math.min(W, H) >= opts.MinFace then
			local margin = opts.Margin
			local spanX = W - 2 * margin - d
			local spanY = H - 2 * margin - d
			local columns = math.clamp(math.floor(spanX / (d * opts.PitchShare)) + 1, 2, opts.MaxColumns)
			local rows = math.clamp(math.floor(spanY / (d * 1.4)) + 1, 1, opts.MaxRows)
			local pitchX = spanX / (columns - 1)
			local pitchY = if rows > 1 then spanY / (rows - 1) else 0
			local x0 = margin + r
			local y0 = if rows > 1 then margin + r else H / 2

			-- Inside the rounded inner rim (corner studs that would cross it go).
			local R = opts.CornerRadius
			local limit = R - opts.RimInset - 2
			local function insideCurve(x, y)
				if R <= 0 then return true end
				local cx = math.clamp(x, R, W - R)
				local cy = math.clamp(y, R, H - R)
				if math.abs(x - cx) < 1e-3 and math.abs(y - cy) < 1e-3 then return true end
				return math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) + r <= limit
			end

			local labelRect = textRect(opts.Label, face, k)
			local iconRect = if opts.Behind == "hide" then coreRect(opts.Icon, face, k, opts.IconCore) else nil
			local pad = opts.AvoidPad
			local function covered(x, y)
				if labelRect and circleHits(x, y, r + pad, labelRect) then return true end
				if iconRect and circleHits(x, y, r + pad, iconRect) then return true end
				return false
			end

			local grid = {}
			for row = 0, rows - 1 do
				grid[row] = {}
				for column = 0, columns - 1 do
					local x, y = x0 + column * pitchX, y0 + row * pitchY
					grid[row][column] = { x = x, y = y, keep = insideCurve(x, y), under = covered(x, y) }
				end
			end
			-- Mirror the content decision left/right, so both sides match.
			for row = 0, rows - 1 do
				for column = 0, columns - 1 do
					local cell, twin = grid[row][column], grid[row][columns - 1 - column]
					cell.under = cell.under or twin.under
				end
			end
			for row = 0, rows - 1 do
				for column = 0, columns - 1 do
					local cell = grid[row][column]
					if cell.keep then
						if not cell.under then
							table.insert(spots, { cell.x, cell.y, false })
						elseif opts.Behind ~= "hide" then
							table.insert(spots, { cell.x, cell.y, true })
						end
					end
				end
			end

			-- "+" marks: centred in the gap between four studs. A negative gap
			-- column counts from the right (-1 = the last gap).
			if W >= opts.MarksMinWidth and rows > 1 then
				for _, mark in ipairs(opts.Marks or {}) do
					local gc = if mark[1] < 0 then columns - 1 + mark[1] else mark[1]
					local gr = math.clamp(mark[2], 0, rows - 2)
					if gc >= 0 and gc <= columns - 2 then
						table.insert(marks, { x0 + (gc + 0.5) * pitchX, y0 + (gr + 0.5) * pitchY, mark[3] })
					end
				end
			end
		end

		local parts = { math.floor(d * 10) }
		for _, spot in ipairs(spots) do
			table.insert(parts, math.floor(spot[1]) .. "," .. math.floor(spot[2]) .. (if spot[3] then "f" else ""))
		end
		for _, mark in ipairs(marks) do
			table.insert(parts, "+" .. math.floor(mark[1]) .. "," .. math.floor(mark[2]))
		end
		local key = table.concat(parts, "|")
		if key == lastKey then return end
		lastKey = key

		for _, child in ipairs(layer:GetChildren()) do
			if child.Name == "Stud" or child.Name == "Plus" then child:Destroy() end
		end
		for _, spot in ipairs(spots) do
			buildStud(layer, spot[1], spot[2], d, color, spot[3])
		end
		for _, mark in ipairs(marks) do
			buildMark(layer, mark[1], mark[2], mark[3], color)
		end
	end

	local queued, forced = false, false
	local function schedule(force)
		forced = forced or force == true
		if queued then return end
		queued = true
		task.defer(function()
			queued = false
			local f = forced
			forced = false
			layout(f)
		end)
	end
	face:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() schedule(false) end)
	local label = opts.Label
	if label and label:IsA("TextLabel") then
		for _, property in ipairs({ "Visible", "Text", "TextSize" }) do
			label:GetPropertyChangedSignal(property):Connect(function() schedule(true) end)
		end
	end
	local icon = opts.Icon
	if icon and icon:IsA("GuiObject") then
		icon:GetPropertyChangedSignal("Size"):Connect(function() schedule(true) end)
	end
	schedule(true)
	return layer
end

return StudSurface
