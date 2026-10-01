-- StudSurface (ModuleScript in ReplicatedStorage)
-- One system for the molded toy-brick studs on chunky HUD buttons.
-- Client only.
--
--   local StudSurface = require(ReplicatedStorage.StudSurface)
--   StudSurface.Apply(face, {
--       Color = buttonColor,          -- the button's own colour
--       Icon = iconFrame,             -- content that sits ON the studs
--       Label = nameLabel,
--   })
--
-- Why drawn studs: the tiled texture (rbxassetid://140302758156355) rendered
-- as fine vertical ridges at button size - a texture made of many small
-- studs cannot be shown at 4-6 studs across without cropping it, and its
-- layout isn't known here. So every stud is a small, deliberate shape:
--
--   Shadow     contact shadow in a darker shade of the same plastic, down-right
--   Body       the button's own colour, lit upper-left, shaded lower-right,
--              with a faint rim - molded from the face, not glued on
--   Highlight  a soft white crescent on the upper-left shoulder
--
-- Layout, recomputed only when the face or its content actually changes:
--   * one even grid over the whole face, edge to edge, up to 7 across and
--     2-3 rows; the icon and name sit ON it;
--   * only studs that would land right behind the lettering or the icon's
--     centre are left out (never moved), so the grid stays regular;
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
print("[StudSurface] build 2026-10-01f (no gaps, no hover rebuild)")

StudSurface.AssetId = "rbxassetid://140302758156355"   -- the supplied texture (see above)
StudSurface.StudImage = nil
StudSurface.SHOW_STUD_BOUNDS = false

local INK = Color3.fromRGB(20, 28, 65)
local WHITE = Color3.new(1, 1, 1)

local DEFAULTS = {
	ZIndex = 1,               -- under the face's gloss (2+) and the content layer
	Margin = 9,               -- design px from the face edge to the first stud's edge
	SizeShare = 0.19,         -- stud diameter as a share of the face's short side
	MinDiameter = 12,         -- design px; studs never shrink below this
	MaxDiameter = 20,
	MinScreenPx = 10,         -- and never below this on screen (phones)
	PitchShare = 1.85,        -- centre-to-centre spacing, in diameters
	MaxColumns = 7,
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

	-- Contact shadow: a darker version of the same plastic, down-right.
	-- Behind the lettering a stud stays in the grid (no gaps) but is pressed
	-- back, so the name reads cleanly on top of it.
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
		picture.ScaleType = Enum.ScaleType.Fit
		picture.Active = false
		picture.ZIndex = 2
		picture.Parent = stud
		return stud
	end

	-- Body: molded from the button's own plastic - lit edge upper-left,
	-- the face colour through the middle, a soft shade lower-right.
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

	-- Glint: a soft white crescent on the upper-left shoulder.
	local glint = round(body, "Highlight", UDim2.fromScale(0.42, 0.24), UDim2.fromScale(0.36, 0.27), WHITE, 3, if faded then 0.75 else 0.3)
	glint.Rotation = -38
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0, 0.7)
	fade.Parent = glint
	return stud
end

-- Design-space rectangles relative to the face.
local function localRect(object, face, k)
	if not (object and object.Parent and object:IsA("GuiObject") and object.Visible) then return nil end
	if object.AbsoluteSize.X < 1 then return nil end
	return (object.AbsolutePosition - face.AbsolutePosition) / k, object.AbsoluteSize / k
end

-- The label's actual lettering (not its whole box), so short names keep
-- the studs beside them.
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
	local lastW, lastH = -1, -1
	local function layout(force)
		if not layer.Parent then return end
		local k = scaleOf(face)
		local size = face.AbsoluteSize / k
		if size.X < 8 or size.Y < 8 then return end
		-- Hover / press only rescale the button: its design size is unchanged,
		-- so nothing is rebuilt (that rebuild is what made studs blink).
		local W, H = math.floor(size.X + 0.5), math.floor(size.Y + 0.5)
		if not force and math.abs(W - lastW) <= 3 and math.abs(H - lastH) <= 3 then return end
		lastW, lastH = W, H
		local d = math.clamp(math.min(W, H) * opts.SizeShare, opts.MinDiameter, opts.MaxDiameter)
		d = math.max(d, opts.MinScreenPx / k)
		local r = d / 2
		local margin = opts.Margin

		-- One even grid over the whole face. Columns spread edge to edge at
		-- about PitchShare diameters apart (fewer on small faces, so the
		-- studs stay big); rows may be a little closer than columns.
		local spanX = W - 2 * margin - d
		local spanY = H - 2 * margin - d
		local columns = math.clamp(math.floor(spanX / (d * opts.PitchShare)) + 1, 2, opts.MaxColumns)
		local rows = math.clamp(math.floor(spanY / (d * 1.4)) + 1, 1, opts.MaxRows or 99)
		local pitchX = spanX / math.max(columns - 1, 1)
		local pitchY = if rows > 1 then spanY / (rows - 1) else 0
		local x0, y0 = margin + r, margin + r
		if rows == 1 then y0 = H / 2 end

		-- Every grid position gets a stud, so there are never gaps. The icon
		-- simply sits on top; studs right behind the lettering are pressed
		-- back (faded) so the name stays clean.
		local labelRect = textRect(opts.Label, face, k)
		local spots = {}
		for row = 0, rows - 1 do
			for column = 0, columns - 1 do
				local x, y = x0 + column * pitchX, y0 + row * pitchY
				local faded = labelRect ~= nil and x > labelRect[1] and x < labelRect[3]
					and y > labelRect[2] and y < labelRect[4]
				table.insert(spots, { x, y, faded })
			end
		end
		-- Mirror the fading left-right, so a name that is a hair off-centre
		-- never fades one side's stud and not the other's.
		for _, spot in ipairs(spots) do
			for _, other in ipairs(spots) do
				if math.abs(other[2] - spot[2]) < 0.5 and math.abs((W - other[1]) - spot[1]) < 0.5 and other[3] then
					spot[3] = true
				end
			end
		end

		local parts = { math.floor(d * 10) }
		for _, spot in ipairs(spots) do
			table.insert(parts, math.floor(spot[1]) .. "," .. math.floor(spot[2]) .. (if spot[3] then "f" else ""))
		end
		local key = table.concat(parts, "|")
		if key == lastKey then return end
		lastKey = key

		for _, child in ipairs(layer:GetChildren()) do
			if child.Name == "Stud" then child:Destroy() end
		end
		for _, spot in ipairs(spots) do
			buildStud(layer, spot[1], spot[2], d, color, spot[3])
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
	-- Content changes that really move things (phone icon-only mode, a new
	-- name): never their size flickering during a hover tween.
	local label = opts.Label
	if label and label:IsA("TextLabel") then
		for _, property in ipairs({ "Visible", "Text", "TextSize" }) do
			label:GetPropertyChangedSignal(property):Connect(function() schedule(true) end)
		end
	end
	schedule(true)
	return layer
end

return StudSurface
