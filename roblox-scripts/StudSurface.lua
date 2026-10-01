-- StudSurface (ModuleScript in ReplicatedStorage)
-- One system for the molded toy-brick studs on chunky HUD buttons.
-- Client only.
--
--   local StudSurface = require(ReplicatedStorage.StudSurface)
--   StudSurface.Apply(face, {
--       Color = buttonColor,          -- the button's own colour
--       Avoid = { icon },             -- content the studs frame instead of covering
--       Above = label,                -- optional: studs stay above this object's box
--   })
--
-- Why drawn studs: the tiled texture (rbxassetid://140302758156355) rendered
-- as fine vertical ridges at button size - a texture made of many small
-- studs cannot be shown at 4-6 studs across without cropping it, and its
-- layout isn't known here. So every stud is a small, deliberate shape:
--
--   Shadow     contact shadow, offset down-right
--   Body       round, a slightly deeper version of the button colour, lit
--              from the upper-left (gradient) with a thin darker rim
--   Cap        the lighter raised top face, nudged up-left
--   Highlight  a small bright glint, upper-left
--
-- Layout, recomputed only when the face or its content actually changes:
--   * one even grid, centred on the face, ~4-8 studs across, 2-3 rows;
--   * studs that would sit behind the icon or the label's actual lettering
--     are left out (never moved), so the grid stays perfectly regular and
--     the content is framed by it;
--   * a small/square face (phones, icon-only) gets four corner studs;
--   * stud size follows the face, with a floor, so they never become dots.
-- The layer is purely visual: Active = false, Interactable = false. It is a
-- child of the face, so presses and hover bounces move it with the button.
--
-- Set StudSurface.StudImage to an asset id of ONE stud to draw each Body with
-- that picture instead of shapes (each stays round: Fit, square box).
-- StudSurface.SHOW_STUD_BOUNDS = true outlines the layer.

local TextService = game:GetService("TextService")

local StudSurface = {}
print("[StudSurface] build 2026-10-01d (drawn studs)")

StudSurface.AssetId = "rbxassetid://140302758156355"   -- the supplied texture (see above)
StudSurface.StudImage = nil
StudSurface.SHOW_STUD_BOUNDS = false

local INK = Color3.fromRGB(20, 28, 65)
local WHITE = Color3.new(1, 1, 1)

local DEFAULTS = {
	ZIndex = 1,               -- under the face's gloss (2+) and the content layer
	Margin = 9,               -- design px from the face edge to the first stud
	SizeShare = 0.18,         -- stud diameter as a share of the face's short side
	MinDiameter = 11,         -- design px; studs never shrink below this
	MaxDiameter = 17,
	PitchShare = 1.62,        -- centre-to-centre spacing, in diameters
	AvoidPad = 3,             -- breathing room around the icon / lettering
}

-- Product of every UIScale on the object and its ancestors.
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

local function buildStud(layer, x, y, d, color)
	local stud = Instance.new("Frame")
	stud.Name = "Stud"
	stud.AnchorPoint = Vector2.new(0.5, 0.5)
	stud.Position = UDim2.fromOffset(x, y)
	stud.Size = UDim2.fromOffset(d, d)
	stud.BackgroundTransparency = 1
	stud.Active = false
	stud.ZIndex = 1
	stud.Parent = layer

	local deep = color:Lerp(INK, 0.16)
	round(stud, "Shadow", UDim2.fromScale(1, 1), UDim2.new(0.5, d * 0.1, 0.5, d * 0.14), INK, 1, 0.5)

	if StudSurface.StudImage then
		local picture = Instance.new("ImageLabel")
		picture.Name = "Body"
		picture.AnchorPoint = Vector2.new(0.5, 0.5)
		picture.Position = UDim2.fromScale(0.5, 0.5)
		picture.Size = UDim2.fromScale(1, 1)
		picture.BackgroundTransparency = 1
		picture.Image = StudSurface.StudImage
		picture.ImageColor3 = deep:Lerp(WHITE, 0.2)
		picture.ScaleType = Enum.ScaleType.Fit
		picture.Active = false
		picture.ZIndex = 2
		picture.Parent = stud
		return stud
	end

	local body = round(stud, "Body", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), WHITE, 2)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 45   -- upper-left light, lower-right shadow
	shade.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, deep:Lerp(WHITE, 0.34)),
		ColorSequenceKeypoint.new(0.55, deep),
		ColorSequenceKeypoint.new(1, deep:Lerp(INK, 0.3)),
	})
	shade.Parent = body
	local rim = Instance.new("UIStroke")
	rim.Color = color:Lerp(INK, 0.5)
	rim.Thickness = math.max(1, d * 0.07)
	rim.Transparency = 0.25
	rim.Parent = body

	-- The raised top face: lighter, a little up-left of centre.
	local cap = round(body, "Cap", UDim2.fromScale(0.66, 0.66), UDim2.fromScale(0.46, 0.44), WHITE, 3)
	local capShade = Instance.new("UIGradient")
	capShade.Rotation = 45
	capShade.Color = ColorSequence.new(deep:Lerp(WHITE, 0.42), deep:Lerp(WHITE, 0.08))
	capShade.Parent = cap

	-- The glint.
	local glint = round(body, "Highlight", UDim2.fromScale(0.3, 0.19), UDim2.fromScale(0.34, 0.3), WHITE, 4, 0.18)
	glint.Rotation = -35
	return stud
end

-- Design-space rectangle of a content object relative to the face; for a
-- TextLabel only its actual lettering counts, so short names free up room.
local function avoidRect(object, face, k, pad)
	if not (object and object.Parent and object:IsA("GuiObject") and object.Visible) then return nil end
	if object.AbsoluteSize.X < 1 then return nil end
	local at = (object.AbsolutePosition - face.AbsolutePosition) / k
	local size = object.AbsoluteSize / k
	if object:IsA("TextLabel") then
		if object.Text == "" then return nil end
		local textSize = if object.TextScaled then size.Y else object.TextSize
		local bounds = TextService:GetTextSize(object.Text, textSize, object.Font, Vector2.new(10000, 10000))
		local w, h = math.min(bounds.X + 6, size.X), math.min(bounds.Y, size.Y)
		local left
		if object.TextXAlignment == Enum.TextXAlignment.Left then
			left = at.X
		elseif object.TextXAlignment == Enum.TextXAlignment.Right then
			left = at.X + size.X - w
		else
			left = at.X + (size.X - w) / 2
		end
		local top = at.Y + (size.Y - h) / 2
		return { left - pad, top - pad, left + w + pad, top + h + pad }
	end
	-- Icon artwork is drawn Fit inside its box; its corners are mostly empty.
	local inset = size * 0.08
	return { at.X + inset.X - pad, at.Y + inset.Y - pad, at.X + size.X - inset.X + pad, at.Y + size.Y - inset.Y + pad }
end

local function circleHitsRect(x, y, r, rect)
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

	-- One stud system: remove the old tiled texture and any earlier layer.
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
	local function layout()
		if not layer.Parent then return end
		local k = scaleOf(face)
		local size = face.AbsoluteSize / k
		if size.X < 8 or size.Y < 8 then return end
		local W, H = size.X, size.Y
		local d = math.clamp(math.min(W, H) * opts.SizeShare, opts.MinDiameter, opts.MaxDiameter)
		local r = d / 2
		local pitch = d * opts.PitchShare
		local margin = opts.Margin

		-- The band the grid lives in: the whole face, or only above the label
		-- (so every button gets the same studs whatever its name's length).
		local top, bottom = margin, H - margin
		local above = opts.Above
		if above and above.Parent and above.Visible and above.AbsoluteSize.Y > 1 then
			bottom = math.min(bottom, (above.AbsolutePosition.Y - face.AbsolutePosition.Y) / k - 1)
		end
		local bandH = math.max(bottom - top, d)

		local avoid = {}
		for _, object in ipairs(opts.Avoid or {}) do
			local rect = avoidRect(object, face, k, opts.AvoidPad)
			if rect then table.insert(avoid, rect) end
		end

		-- Even grid, centred. Rows may sit a little closer than columns (never
		-- closer than 1.38 diameters), so a short band still gets two rows.
		local columns = math.max(1, math.floor((W - 2 * margin - d) / pitch) + 1)
		local rows = math.max(1, math.floor((bandH - d) / (d * 1.38)) + 1)
		local pitchY = if rows > 1 then math.min(pitch, (bandH - d) / (rows - 1)) else 0
		local x0 = (W - (columns - 1) * pitch) / 2
		local y0 = top + (bandH - (rows - 1) * pitchY) / 2
		local spots = {}
		for row = 0, rows - 1 do
			for column = 0, columns - 1 do
				local x, y = x0 + column * pitch, y0 + row * pitchY
				local free = true
				for _, rect in ipairs(avoid) do
					if circleHitsRect(x, y, r, rect) then free = false break end
				end
				if free then table.insert(spots, { x, y }) end
			end
		end
		-- Small square faces (icon-only on phones): four corner studs.
		local dd = d
		if #spots < 4 then
			dd = math.max(opts.MinDiameter * 0.85, d * 0.78)
			local c = margin + dd / 2
			spots = { { c, c }, { W - c, c }, { c, H - c }, { W - c, H - c } }
		end

		local parts = { math.floor(W + 0.5), math.floor(H + 0.5), math.floor(dd * 10) }
		for _, spot in ipairs(spots) do
			table.insert(parts, math.floor(spot[1]) .. "," .. math.floor(spot[2]))
		end
		local key = table.concat(parts, "|")
		if key == lastKey then return end
		lastKey = key

		for _, child in ipairs(layer:GetChildren()) do
			if child.Name == "Stud" then child:Destroy() end
		end
		for _, spot in ipairs(spots) do
			buildStud(layer, spot[1], spot[2], dd, color)
		end
	end

	local queued = false
	local function schedule()
		if queued then return end
		queued = true
		task.defer(function()
			queued = false
			layout()
		end)
	end
	face:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule)
	local watched = table.clone(opts.Avoid or {})
	if opts.Above then table.insert(watched, opts.Above) end
	for _, object in ipairs(watched) do
		if object and object:IsA("GuiObject") then
			object:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule)
			object:GetPropertyChangedSignal("Visible"):Connect(schedule)
			if object:IsA("TextLabel") then object:GetPropertyChangedSignal("TextSize"):Connect(schedule) end
		end
	end
	schedule()
	return layer
end

return StudSurface
