-- StudSurface (ModuleScript in ReplicatedStorage)  -- NEW
-- One system for the molded toy-brick stud texture on chunky HUD buttons.
-- Client only.
--
--   local StudSurface = require(ReplicatedStorage.StudSurface)
--   StudSurface.Apply(face, { Tint = buttonColor, CornerRadius = 23, ZIndex = 1 })
--
-- What one call does to `face` (the button's coloured surface Frame):
--   * adds ONE ImageLabel named "StudOverlay" (re-used on later calls, never
--     stacked), drawing the supplied stud texture TILED, so studs stay round
--     and evenly spaced on any width - never stretched;
--   * inset from the border by about half a stud, and sized to a whole
--     number of studs, centred, so no row is cut off or squeezed at an edge;
--   * rounded with a concentric corner (the face's radius minus the inset),
--     so it follows the curved shape exactly and never covers the stroke;
--   * tinted from the button's own colour (a little richer, so gold reads as
--     gold, not washed-out yellow), and a touch more see-through toward the
--     bottom, where the label sits;
--   * purely visual: Active = false, Interactable = false, an ImageLabel -
--     it never takes a tap and never changes the button's size or hitbox;
--   * stud size follows the HUD's responsive UIScale but is clamped in screen
--     pixels, so phones don't get microscopic studs or desktops huge ones;
--   * deterministic: the pattern starts at the overlay's top-left every time.
-- Hover brightens the studs very slightly; a disabled button dims them.
--
-- Layer rule: put it ABOVE the face's gradient and BELOW its gloss, icons and
-- text. In a Sibling-ZIndex ScreenGui a child always draws over its parent,
-- so ZIndex 1 inside the face puts it under the face's gloss children (2+)
-- and under the button's content layer.

local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local StudSurface = {}
print("[StudSurface] build 2026-10-01c")

StudSurface.AssetId = "rbxassetid://140302758156355"

-- Development only: outlines every StudOverlay so its bounds can be checked
-- against the button (corners, inset, no overflow). Keep false in production.
StudSurface.SHOW_STUD_BOUNDS = false

local DEFAULTS = {
	Transparency = 0.06,      -- clearly visible; the gloss still sits on top
	HoverTransparency = 0.0,
	DisabledTransparency = 0.6,
	TileSize = 15,            -- design px per stud cell (before the HUD's UIScale)
	-- How many studs ACROSS the supplied image. 1 = the image is one stud
	-- cell (the usual seamless tile). If the picture is a whole grid of studs
	-- (e.g. 4 x 4), set 4 and every stud keeps the size above.
	-- The supplied texture holds a grid of studs (it rendered as fine noise
	-- at 1), so each repeat of the picture spans this many stud cells.
	StudsPerTile = 4,
	MinTilePx = 8,            -- on-screen clamp per stud, phones
	MaxTilePx = 22,           -- on-screen clamp per stud, large monitors
	InsetShare = 0.5,         -- edge breathing room, in studs
	CornerRadius = 0,         -- the face's own radius, in px
	ZIndex = 1,
	TintLighten = 0.32,      -- lighter than the face, so the studs stand out of it       -- toward white, so the baked shading still reads
	TintDeepen = 0.08,        -- toward the colour's own darker shade, for richness
	LabelFade = 0.12,         -- extra transparency at the bottom (behind the label)
}

local INK = Color3.fromRGB(20, 28, 65)

-- Preloaded once, so buttons never appear without studs and then pop them in.
local preloaded = false
local function preload()
	if preloaded then return end
	preloaded = true
	task.spawn(function()
		local probe = Instance.new("ImageLabel")
		probe.Image = StudSurface.AssetId
		pcall(function() ContentProvider:PreloadAsync({ probe }) end)
		probe:Destroy()
	end)
end

-- Product of the responsive UIScales above (and on) an object.
local function responsiveScale(object)
	local k, node = 1, object
	while node and not node:IsA("LayerCollector") do
		for _, child in ipairs(node:GetChildren()) do
			if child:IsA("UIScale") then k *= child.Scale end
		end
		node = node.Parent
	end
	return math.max(k, 0.01)
end

local function tintFor(color, opts)
	-- A richer version of the surface colour: a little toward white so the
	-- texture's own highlights survive, and a little toward a deeper shade so
	-- it never looks chalky.
	local h, s, v = color:ToHSV()
	local deep = Color3.fromHSV(h, math.min(1, s * 1.08), v)
	return deep:Lerp(Color3.new(1, 1, 1), opts.TintLighten):Lerp(color:Lerp(INK, 0.25), opts.TintDeepen)
end

local function findButton(face)
	local node = face
	while node and not node:IsA("LayerCollector") do
		if node:IsA("GuiButton") then return node end
		node = node.Parent
	end
	return nil
end

function StudSurface.Apply(face, options)
	if not (face and face:IsA("GuiObject")) then return nil end
	preload()
	local opts = {}
	for key, value in pairs(DEFAULTS) do opts[key] = value end
	for key, value in pairs(options or {}) do opts[key] = value end

	-- Re-use, never stack.
	local overlay = face:FindFirstChild("StudOverlay")
	if not (overlay and overlay:IsA("ImageLabel")) then
		if overlay then overlay:Destroy() end
		overlay = Instance.new("ImageLabel")
		overlay.Name = "StudOverlay"
		overlay.Parent = face
	end
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Active = false
	pcall(function() overlay.Interactable = false end)
	overlay.Selectable = false
	overlay.Image = opts.AssetId or StudSurface.AssetId
	overlay.ScaleType = Enum.ScaleType.Tile
	overlay.Rotation = 0                       -- one orientation everywhere (light from upper-left)
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.Position = UDim2.fromScale(0.5, 0.5)
	overlay.ZIndex = opts.ZIndex
	overlay.ImageColor3 = tintFor(opts.Tint or face.BackgroundColor3, opts)

	local corner = overlay:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.Parent = overlay

	-- Slightly lighter behind the label at the bottom; seamless, no hard edge.
	local fade = overlay:FindFirstChild("StudFade") or Instance.new("UIGradient")
	fade.Name = "StudFade"
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.55, opts.LabelFade * 0.4),
		NumberSequenceKeypoint.new(1, opts.LabelFade),
	})
	fade.Parent = overlay

	local bounds = overlay:FindFirstChild("StudBounds")
	if StudSurface.SHOW_STUD_BOUNDS and not bounds then
		bounds = Instance.new("UIStroke")
		bounds.Name = "StudBounds"
		bounds.Color = Color3.fromRGB(255, 40, 40)
		bounds.Thickness = 1
		bounds.Parent = overlay
	elseif bounds and not StudSurface.SHOW_STUD_BOUNDS then
		bounds:Destroy()
	end

	-- Size: a whole number of studs, centred, inset from the border.
	local function layout()
		local k = responsiveScale(face)
		local size = face.AbsoluteSize / k                -- design px
		if size.X < 4 or size.Y < 4 then return end
		local tilePx = math.clamp(opts.TileSize * k, opts.MinTilePx, opts.MaxTilePx)
		local stud = tilePx / k
		local inset = stud * opts.InsetShare
		-- Whole stud cells only, so no row or column is cut at an edge.
		local columns = math.max(1, math.floor((size.X - inset * 2) / stud))
		local rows = math.max(1, math.floor((size.Y - inset * 2) / stud))
		local per = math.max(1, opts.StudsPerTile or 1)
		overlay.TileSize = UDim2.fromOffset(stud * per, stud * per)
		overlay.Size = UDim2.fromOffset(columns * stud, rows * stud)
		corner.CornerRadius = UDim.new(0, math.max((opts.CornerRadius or 0) - inset, 0))
	end
	layout()
	print(("[StudSurface] %s: %dx%d stud area, tile %s, transparency %.2f"):format(
		face:GetFullName():gsub("^Players%.[^%.]+%.PlayerGui%.", ""), overlay.Size.X.Offset, overlay.Size.Y.Offset,
		tostring(overlay.TileSize), opts.Transparency))
	if not overlay:GetAttribute("StudWired") then
		overlay:SetAttribute("StudWired", true)
		face:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

		-- Hover and disabled follow the real button; the studs move with the
		-- face (they are its child), so presses and bounces carry them along.
		local button = findButton(face)
		local hovering = false
		local function enabled()
			if not button then return true end
			local ok, value = pcall(function() return button.Interactable end)
			return button.Active and not (ok and value == false)
		end
		local function refresh(animated)
			local goal = if not enabled() then opts.DisabledTransparency
				elseif hovering then opts.HoverTransparency else opts.Transparency
			if animated then
				TweenService:Create(overlay, TweenInfo.new(0.14, Enum.EasingStyle.Quad), { ImageTransparency = goal }):Play()
			else
				overlay.ImageTransparency = goal
			end
		end
		refresh(false)
		if button then
			button.MouseEnter:Connect(function() hovering = true refresh(true) end)
			button.MouseLeave:Connect(function() hovering = false refresh(true) end)
			button:GetPropertyChangedSignal("Active"):Connect(function() refresh(true) end)
			pcall(function()
				button:GetPropertyChangedSignal("Interactable"):Connect(function() refresh(true) end)
			end)
		end
	else
		overlay.ImageTransparency = opts.Transparency
	end
	return overlay
end

return StudSurface
