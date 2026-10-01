-- RebirthClient (LocalScript in StarterPlayer > StarterPlayerScripts)
-- The Rebirth window, opened by the Rebirth button in MainHUD's side menu.
--
-- Layout: illustrated header, then three columns - Current Rebirths, Next
-- Rebirth Rewards, Requirements - and a big REBIRTH button.
--
-- Every number comes from the game:
--   * requirements: the server's RebirthRequirements attribute (JSON rows it
--     builds from RebirthConfig.GetRequirements), plus CanRebirth;
--   * rewards: RebirthConfig / UpgradeConfig (what the next rebirth changes);
--   * the count: the Rebirths attribute.
-- The server (BlackHoleSystemServer, REBIRTH section) does every check and
-- the reset; this window only asks.
--
-- Artwork: UIAssets.RebirthArt. Any empty entry is drawn here instead.
--
-- Nibbles can point at parts of this window: set the window's attribute
-- GuideHighlight to "Requirements", "Rewards" or "Button" and that part
-- glows until it is cleared (""). The REBIRTH button also glows on its own
-- whenever the player can rebirth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GuiManager = require(ReplicatedStorage:WaitForChild("GuiManager"))
local RebirthConfig = require(ReplicatedStorage:WaitForChild("RebirthConfig"))
local UpgradeConfig = require(ReplicatedStorage:WaitForChild("UpgradeConfig"))

local function optional(name)
	local module = ReplicatedStorage:FindFirstChild(name)
	local ok, result = pcall(function() return module and require(module) end)
	return if ok and type(result) == "table" then result else nil
end
local UiResponsive = optional("UiResponsive")
local UIAssets = optional("UIAssets") or {}
local Format = optional("NumberFormatter")

local ART = UIAssets.RebirthArt or {}
local REWARD_ICONS = ART.RewardIcons or {}
local REQUIREMENT_ICONS = ART.RequirementIcons or {}
local REBIRTHS = UpgradeConfig.RebirthAttribute or "Rebirths"

-- ===================== STYLE =====================
local FONT = Enum.Font.FredokaOne
local INK = Color3.fromRGB(12, 18, 58)
local WHITE = Color3.fromRGB(255, 255, 255)
local CYAN = Color3.fromRGB(90, 225, 255)
local GOLD = Color3.fromRGB(255, 205, 50)
local GREEN = Color3.fromRGB(90, 235, 120)
local RED = Color3.fromRGB(255, 120, 120)
local MUTED = Color3.fromRGB(175, 190, 235)
local SUBTITLE = "Reset your progress to gain permanent boosts\nand reach new cosmic heights!"

-- Everything is laid out on a fixed design panel; one UIScale fits it to
-- the screen, so it always scales as a single unit.
local PANEL = Vector2.new(1180, 800)
local FIT = Vector2.new(1260, 860)
local INSET = 20
local CW, CH = PANEL.X - INSET * 2, PANEL.Y - INSET * 2

local function reduced()
	return player:GetAttribute("ReduceMotion") == true
end

local function abbreviate(n)
	if Format and Format.Abbreviate then return Format.Abbreviate(n) end
	n = math.floor(tonumber(n) or 0)
	local units = { "", "K", "M", "B", "T", "Qa" }
	local i = 1
	while n >= 1000 and i < #units do n /= 1000; i += 1 end
	return (if i == 1 then tostring(n) else ("%.2f"):format(n)) .. units[i]
end

-- ===================== DRAWING HELPERS =====================
local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do object[key] = value end
	object.Parent = parent
	return object
end

local function box(parent, name, x, y, w, h, color, z, props)
	local f = make("Frame", {
		Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color or WHITE, BorderSizePixel = 0, ZIndex = z or 1,
	}, parent)
	if props then for key, value in pairs(props) do f[key] = value end end
	return f
end

local function round(parent, px)
	make("UICorner", { CornerRadius = UDim.new(0, px) }, parent)
	return parent
end

local function pill(parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, parent)
	return parent
end

local function gradient(parent, stops, rotation)
	local keys = {}
	for i, stop in ipairs(stops) do keys[i] = ColorSequenceKeypoint.new(stop[1], stop[2]) end
	return make("UIGradient", { Color = ColorSequence.new(keys), Rotation = rotation or 90 }, parent)
end

local function stroke(parent, color, thickness, contextual, transparency)
	return make("UIStroke", {
		Color = color or INK, Thickness = thickness or 3, Transparency = transparency or 0,
		ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function text(parent, name, str, x, y, w, h, size, color, z, align)
	local label = make("TextLabel", {
		Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1, Text = str, Font = FONT, TextColor3 = color or WHITE,
		TextScaled = true, TextWrapped = true, ZIndex = z or 5,
		TextXAlignment = align or Enum.TextXAlignment.Center,
	}, parent)
	make("UITextSizeConstraint", { MaxTextSize = size, MinTextSize = math.floor(size * 0.5) }, label)
	stroke(label, INK, math.max(2, size / 11), true)
	return label
end

local function image(parent, name, id, cx, cy, w, h, z)
	return make("ImageLabel", {
		Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1, Image = id or "",
		ScaleType = Enum.ScaleType.Fit, ZIndex = z or 5,
	}, parent)
end

local function has(id)
	return type(id) == "string" and id ~= ""
end

local function dot(parent, cx, cy, size, color, alpha, z)
	return pill(box(parent, "Dot", cx, cy, size, size, color, z, {
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = alpha or 0,
	}))
end

-- Soft round light made of three stacked discs.
local function glow(parent, cx, cy, radius, color, strength, z)
	for i, spec in ipairs({ { 1, 0.9 }, { 0.68, 0.84 }, { 0.38, 0.76 } }) do
		local disc = dot(parent, cx, cy, radius * 2 * spec[1], color, 1 - (1 - spec[2]) * (strength or 1), z)
		disc.Name = "Glow" .. i
	end
end

local function orbit(parent, cx, cy, w, h, color, thickness, rotation, z)
	local ring = pill(box(parent, "Orbit", cx, cy, w, h, WHITE, z, {
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Rotation = rotation or 0,
	}))
	stroke(ring, color, thickness or 4)
	return ring
end

-- Four-point sparkle: two rounded bars and a diamond core. Twinkles while open.
local twinkles = {}
local function sparkle(parent, cx, cy, size, color, z, twinkle)
	local holder = box(parent, "Sparkle", cx, cy, size, size, WHITE, z, {
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
	})
	local function bar(w, h, rotation)
		return pill(box(holder, "Ray", size / 2, size / 2, w, h, color, z, {
			AnchorPoint = Vector2.new(0.5, 0.5), Rotation = rotation or 0,
		}))
	end
	bar(size * 0.26, size)
	bar(size, size * 0.26)
	local core = bar(size * 0.46, size * 0.46, 45)
	core:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.2, 0)
	local scale = make("UIScale", {}, holder)
	if twinkle then table.insert(twinkles, scale) end
	return holder
end

local function starfield(parent, w, h, count, seed, z)
	local rng = Random.new(seed)
	for _ = 1, count do
		dot(parent, rng:NextInteger(6, w - 6), rng:NextInteger(6, h - 6), rng:NextInteger(2, 4),
			if rng:NextNumber() < 0.25 then CYAN else WHITE, rng:NextNumber(0.25, 0.7), z)
	end
end

local function cutAt(at)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(at - 0.001, 0),
		NumberSequenceKeypoint.new(at, 1), NumberSequenceKeypoint.new(1, 1),
	})
end

-- Glossy shapes: a navy silhouette, then the coloured fill, so pieces that
-- overlap share one outline. `cut` keeps only the top part (diamond -> triangle).
local function outlined(parent, pieces, fill, outlineWidth, z)
	for pass = 1, 2 do
		for _, p in ipairs(pieces) do
			local grow = if pass == 1 then outlineWidth * 2 else 0
			local piece = box(parent, "Piece", p.x, p.y, p.w + grow, p.h + grow, if pass == 1 then INK else WHITE,
				z + pass - 1, { AnchorPoint = Vector2.new(0.5, 0.5), Rotation = p.r or 0 })
			make("UICorner", { CornerRadius = UDim.new(0, (p.corner or 8) + (if pass == 1 then outlineWidth else 0)) }, piece)
			local rotation = 90 - (p.r or 0)
			if pass == 2 then
				local g = gradient(piece, fill, rotation)
				if p.cut then g.Transparency = cutAt(p.cut) end
			elseif p.cut then
				make("UIGradient", { Rotation = rotation, Transparency = cutAt(p.cut + outlineWidth / ((p.w + grow) * math.sqrt(2))) }, piece)
			end
		end
	end
end

local GREEN_FILL = { { 0, Color3.fromRGB(170, 255, 150) }, { 0.35, Color3.fromRGB(70, 230, 90) }, { 1, Color3.fromRGB(20, 150, 60) } }
local GOLD_FILL = { { 0, Color3.fromRGB(255, 250, 170) }, { 0.45, Color3.fromRGB(255, 205, 40) }, { 1, Color3.fromRGB(255, 130, 20) } }

-- Gold lettering: cyan halo, navy extrusion, gold face.
local function goldText(parent, name, str, x, y, w, h, size, z)
	local top
	for i, layer in ipairs({
		{ offset = 0, color = CYAN, strokeColor = CYAN, width = 9, alpha = 0.35 },
		{ offset = 6, color = INK, strokeColor = INK, width = 6 },
		{ offset = 0, color = WHITE, strokeColor = INK, width = 5, gold = true },
		}) do
		local label = text(parent, name .. (if layer.gold then "" else "Layer" .. i), str, x, y + layer.offset, w, h, size, layer.color, z + i - 1)
		label.TextWrapped = false
		label:FindFirstChildOfClass("UIStroke"):Destroy()
		stroke(label, layer.strokeColor, layer.width, true, layer.alpha)
		if layer.gold then
			gradient(label, GOLD_FILL)
			top = label
		end
	end
	return top
end

-- A drawn black hole: glow, tilted rings, a dark core with a bright rim.
local function drawnVortex(parent, cx, cy, size, z)
	glow(parent, cx, cy, size * 0.62, Color3.fromRGB(170, 70, 255), 0.8, z)
	orbit(parent, cx, cy, size * 1.0, size * 0.46, Color3.fromRGB(230, 110, 255), 7, -18, z + 1)
	orbit(parent, cx, cy, size * 0.82, size * 0.36, Color3.fromRGB(80, 230, 255), 5, -18, z + 2)
	local core = dot(parent, cx, cy, size * 0.42, Color3.fromRGB(4, 2, 16), 0, z + 3)
	stroke(core, Color3.fromRGB(150, 230, 255), 4)
	return core
end

-- ===================== WINDOW =====================
local old = playerGui:FindFirstChild("RebirthUI")
if old then old:Destroy() end

local gui = make("ScreenGui", {
	Name = "RebirthUI", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 6,
}, playerGui)
if UiResponsive and UiResponsive.UseModalInsets then UiResponsive.UseModalInsets(gui) end   -- below the top bar

local root = make("Frame", {
	Name = "RebirthWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47),
	Size = UDim2.fromOffset(PANEL.X, PANEL.Y), BackgroundTransparency = 1, Visible = false,
}, gui)
root:SetAttribute("GuideHighlight", "")

-- GuiManager puts its open/close UIScale on the root; the fit scale is one
-- level down, because an object only honours one UIScale.
local panel = make("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(PANEL.X, PANEL.Y), BackgroundTransparency = 1,
}, root)
local fitScale = make("UIScale", { Name = "ResponsiveScale" }, panel)

-- Clouds behind the frame: only what pokes out past the edge shows.
local backDecor = box(panel, "BackDecor", 0, 0, PANEL.X, PANEL.Y, WHITE, 0, { BackgroundTransparency = 1 })
local function cloudBank(cx, cy, flip)
	if has(ART.Cloud) then
		image(backDecor, "Cloud", ART.Cloud, cx, cy, 320, 160, 0)
		return
	end
	local dir = if flip then -1 else 1
	local puffs = {
		{ x = cx - 100 * dir, y = cy + 20, w = 140, h = 110 },
		{ x = cx, y = cy, w = 170, h = 150 },
		{ x = cx + 100 * dir, y = cy + 26, w = 130, h = 100 },
		{ x = cx, y = cy + 56, w = 320, h = 80 },
	}
	for _, p in ipairs(puffs) do p.corner = math.floor(math.min(p.w, p.h) / 2) end
	outlined(backDecor, puffs, { { 0, WHITE }, { 0.6, Color3.fromRGB(200, 225, 255) }, { 1, Color3.fromRGB(170, 160, 240) } }, 3, 0)
end
cloudBank(0, PANEL.Y - 30, false)
cloudBank(PANEL.X, PANEL.Y - 30, true)

-- Layered neon frame: soft halo, navy structure, electric blue, cyan, seam.
for i, spec in ipairs({ { -14, 0.86 }, { -7, 0.74 } }) do
	local halo = box(panel, "Halo" .. i, spec[1], spec[1], PANEL.X - spec[1] * 2, PANEL.Y - spec[1] * 2, Color3.fromRGB(40, 170, 255), 1)
	halo.BackgroundTransparency = spec[2]
	round(halo, 56)
end
for i, spec in ipairs({
	{ "Structure", 0, INK, 48 }, { "Electric", 5, Color3.fromRGB(30, 95, 255), 44 },
	{ "Cyan", 10, Color3.fromRGB(70, 215, 255), 40 }, { "Seam", 14, Color3.fromRGB(14, 30, 110), 36 },
	}) do
	local layer = round(box(panel, spec[1], spec[2], spec[2], PANEL.X - spec[2] * 2, PANEL.Y - spec[2] * 2, spec[3], 1 + i), spec[4])
	if spec[1] == "Electric" then
		gradient(layer, { { 0, Color3.fromRGB(70, 150, 255) }, { 1, Color3.fromRGB(25, 70, 220) } })
	end
end

local content = round(box(panel, "Content", INSET, INSET, CW, CH, WHITE, 6), 32)
gradient(content, { { 0, Color3.fromRGB(34, 36, 132) }, { 0.4, Color3.fromRGB(20, 24, 92) }, { 1, Color3.fromRGB(10, 12, 50) } })
glow(content, 200, 560, 260, Color3.fromRGB(130, 60, 230), 0.5, 6)
glow(content, 900, 380, 300, Color3.fromRGB(40, 110, 255), 0.45, 6)
starfield(content, CW, CH, 80, 31, 7)

-- ===================== HEADER =====================
local header = box(content, "Header", 0, 0, CW, 200, WHITE, 8, { BackgroundTransparency = 1 })

if has(ART.HeaderVortex) then
	image(header, "Vortex", ART.HeaderVortex, 150, 100, 230, 200, 9)
else
	drawnVortex(header, 150, 96, 190, 9)
end
sparkle(header, 60, 60, 34, GOLD, 16, true)
sparkle(header, 250, 30, 30, GOLD, 16, true)
sparkle(header, 90, 170, 26, GOLD, 16, true)
sparkle(header, 300, 120, 18, WHITE, 16, true)

goldText(header, "Title", "Rebirth", 280, 6, 580, 124, 118, 12)
local subtitle = text(header, "Subtitle", SUBTITLE, 270, 128, 600, 62, 27, Color3.fromRGB(215, 240, 255), 14)

local planetHolder = box(header, "Planet", 960, 96, 200, 150, WHITE, 9, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1 })
if has(ART.Planet) then
	image(planetHolder, "PlanetArt", ART.Planet, 100, 75, 200, 150, 11)
else
	glow(planetHolder, 100, 75, 100, Color3.fromRGB(190, 90, 255), 0.5, 9)
	orbit(planetHolder, 100, 78, 190, 48, Color3.fromRGB(255, 120, 230), 7, -14, 10)
	local ball = dot(planetHolder, 100, 75, 112, WHITE, 0, 11)
	gradient(ball, { { 0, Color3.fromRGB(230, 170, 255) }, { 0.5, Color3.fromRGB(160, 80, 240) }, { 1, Color3.fromRGB(90, 40, 170) } }, 60)
	stroke(ball, INK, 4)
	local front = orbit(planetHolder, 100, 78, 190, 48, Color3.fromRGB(255, 150, 240), 7, -14, 12)
	make("UIGradient", { Rotation = -90, Transparency = cutAt(0.45) }, front:FindFirstChildOfClass("UIStroke"))
	dot(ball, 34, 30, 24, WHITE, 0.55, 12)
end
dot(header, 870, 150, 26, Color3.fromRGB(80, 110, 230), 0, 9)
sparkle(header, 890, 40, 24, GOLD, 16, true)
sparkle(header, 1060, 170, 22, GOLD, 16, true)

local closeButton = make("TextButton", {
	Name = "CloseButton", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CW - 62, 58),
	Size = UDim2.fromOffset(78, 74), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 20,
}, header)
closeButton:SetAttribute("OwnPressAnimation", true)
do
	round(box(closeButton, "Shadow", 0, 6, 78, 74, INK, 20), 18)
	local face = round(box(closeButton, "Face", 0, 0, 78, 74, WHITE, 21), 18)
	stroke(face, INK, 4)
	gradient(face, { { 0, Color3.fromRGB(255, 130, 130) }, { 0.45, Color3.fromRGB(240, 50, 60) }, { 1, Color3.fromRGB(170, 20, 40) } })
	round(box(face, "Shine", 8, 6, 62, 22, WHITE, 22, { BackgroundTransparency = 0.6 }), 10)
	for pass, spec in ipairs({ { 54, 18, INK }, { 46, 11, WHITE } }) do
		for _, rotation in ipairs({ 45, -45 }) do
			pill(box(face, "X", 39, 37, spec[1], spec[2], spec[3], 22 + pass,
				{ AnchorPoint = Vector2.new(0.5, 0.5), Rotation = rotation }))
		end
	end
	local scale = make("UIScale", {}, closeButton)
	closeButton.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1.08 }):Play()
	end)
	closeButton.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
	end)
end

-- ===================== COLUMNS =====================
local glows = {}   -- [GuideHighlight name] = UIStroke

-- A column card: layered edge, glossy magenta title, cosmic body.
local function column(name, x, y, w, h, heading)
	local holder = box(content, name, x, y, w, h, WHITE, 10, { BackgroundTransparency = 1 })
	round(box(holder, "Structure", 0, 0, w, h, INK, 10), 24)
	local edge = round(box(holder, "Edge", 3, 3, w - 6, h - 6, WHITE, 11), 21)
	gradient(edge, { { 0, Color3.fromRGB(255, 90, 210) }, { 0.3, Color3.fromRGB(80, 140, 255) }, { 1, Color3.fromRGB(40, 100, 240) } })
	round(box(holder, "Cyan", 6, 6, w - 12, h - 12, Color3.fromRGB(80, 210, 255), 12), 19)
	local body = round(box(holder, "Body", 8, 8, w - 16, h - 16, WHITE, 13), 17)
	gradient(body, { { 0, Color3.fromRGB(26, 34, 100) }, { 0.5, Color3.fromRGB(16, 22, 70) }, { 1, Color3.fromRGB(10, 13, 44) } })
	local bw, bh = w - 16, h - 16
	starfield(body, bw, bh, 12, #name * 13, 14)

	local bar = round(box(body, "TitleBar", 0, 0, bw, 52, WHITE, 16), 17)
	gradient(bar, { { 0, Color3.fromRGB(255, 150, 230) }, { 0.4, Color3.fromRGB(240, 50, 180) }, { 1, Color3.fromRGB(150, 25, 150) } })
	box(body, "TitleBarBase", 0, 34, bw, 18, Color3.fromRGB(150, 25, 150), 15)
	box(body, "TitleBarLine", 0, 52, bw, 3, INK, 17)
	round(box(bar, "Shine", 10, 4, bw - 20, 14, WHITE, 17, { BackgroundTransparency = 0.68 }), 7)
	text(body, "Title", heading, 12, 6, bw - 24, 42, 30, WHITE, 18)

	local glowFrame = round(box(holder, "GuideGlow", -4, -4, w + 8, h + 8, WHITE, 30, { BackgroundTransparency = 1 }), 28)
	glows[name] = stroke(glowFrame, GOLD, 6, false, 1)
	return body, bw, bh
end

-- A row inside a column: rounded strip, icon on the left.
local function row(parent, name, y, w, h)
	local strip = round(box(parent, name, 10, y, w - 20, h, WHITE, 18), 14)
	stroke(strip, Color3.fromRGB(70, 130, 240), 2)
	gradient(strip, { { 0, Color3.fromRGB(34, 46, 120) }, { 1, Color3.fromRGB(18, 24, 70) } })
	return strip, w - 20
end

-- ---------- Icons (artwork when set, drawn otherwise) ----------
local drawnIcons = {}
drawnIcons.Income = function(holder, s)
	sparkle(holder, s / 2, s / 2, s * 0.9, GOLD, 22)
end
drawnIcons.SpawnSpeed = function(holder, s)
	orbit(holder, s / 2, s / 2, s * 0.9, s * 0.9, Color3.fromRGB(230, 110, 255), 4, 0, 21)
	orbit(holder, s / 2, s / 2, s * 0.6, s * 0.6, Color3.fromRGB(80, 230, 255), 4, 0, 22)
	dot(holder, s / 2, s / 2, s * 0.28, Color3.fromRGB(4, 2, 16), 0, 23)
end
drawnIcons.UpgradeCaps = function(holder, s)
	outlined(holder, {
		{ x = s / 2, y = s * 0.44, w = s * 0.62, h = s * 0.62, r = 45, corner = 6, cut = 0.5 },
		{ x = s / 2, y = s * 0.66, w = s * 0.36, h = s * 0.44, corner = 6 },
	}, GREEN_FILL, 3, 21)
end
drawnIcons.StartingTier = function(holder, s)
	for i, y in ipairs({ 0.36, 0.64 }) do
		local fill = if i == 1 then { { 0, Color3.fromRGB(255, 200, 250) }, { 1, Color3.fromRGB(230, 90, 220) } }
			else { { 0, Color3.fromRGB(200, 255, 255) }, { 1, Color3.fromRGB(40, 200, 240) } }
		outlined(holder, {
			{ x = s * 0.36, y = s * y, w = s * 0.42, h = s * 0.16, r = -45, corner = 4 },
			{ x = s * 0.64, y = s * y, w = s * 0.42, h = s * 0.16, r = 45, corner = 4 },
		}, fill, 2, 21)
	end
end
drawnIcons.Tier = function(holder, s)
	-- A gauge: the top half of a ring, with a needle.
	local ring = orbit(holder, s / 2, s * 0.6, s * 0.84, s * 0.84, WHITE, 6, 0, 21)
	make("UIGradient", { Rotation = 90, Transparency = cutAt(0.55) }, ring:FindFirstChildOfClass("UIStroke"))
	pill(box(holder, "Needle", s / 2, s * 0.6, s * 0.36, 5, Color3.fromRGB(255, 120, 150), 22,
		{ AnchorPoint = Vector2.new(0, 0.5), Rotation = -40 }))
	dot(holder, s / 2, s * 0.6, s * 0.16, WHITE, 0, 23)
end
drawnIcons.Stardust = drawnIcons.Income
drawnIcons.BlackHoles = function(holder, s)
	glow(holder, s / 2, s / 2, s * 0.5, Color3.fromRGB(170, 70, 255), 0.7, 20)
	local hole = dot(holder, s / 2, s / 2, s * 0.66, Color3.fromRGB(4, 2, 16), 0, 21)
	stroke(hole, Color3.fromRGB(210, 130, 255), 4)
end
drawnIcons.UpgradesAtCap = function(holder, s)
	local shackle = pill(box(holder, "Shackle", s / 2, s * 0.36, s * 0.46, s * 0.5, WHITE, 21,
		{ AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1 }))
	stroke(shackle, Color3.fromRGB(225, 240, 255), 5)
	local body = round(box(holder, "Body", s * 0.2, s * 0.44, s * 0.6, s * 0.46, WHITE, 22), 6)
	stroke(body, INK, 3)
	gradient(body, { { 0, WHITE }, { 1, Color3.fromRGB(150, 200, 255) } })
	dot(body, s * 0.3, s * 0.2, s * 0.12, Color3.fromRGB(30, 80, 200), 0, 23)
end

local function icon(parent, name, artId, drawKey, x, y, s)
	local holder = box(parent, name, x, y, s, s, WHITE, 20, { BackgroundTransparency = 1 })
	if has(artId) then
		image(holder, "Art", artId, s / 2, s / 2, s, s, 22)
	elseif drawnIcons[drawKey] then
		drawnIcons[drawKey](holder, s)
	end
	return holder
end

-- A green check in a rounded box; an empty box while not met.
local function checkBox(parent, x, y, s)
	local holder = box(parent, "Check", x, y, s, s, WHITE, 20, { BackgroundTransparency = 1 })
	local frame = round(box(holder, "Box", 0, 0, s, s, Color3.fromRGB(20, 40, 60), 20), 10)
	local frameStroke = stroke(frame, Color3.fromRGB(90, 230, 150), 3)
	local mark = box(holder, "Mark", 0, 0, s, s, WHITE, 21, { BackgroundTransparency = 1 })
	outlined(mark, {
		{ x = s * 0.36, y = s * 0.58, w = s * 0.34, h = s * 0.16, r = 45, corner = 4 },
		{ x = s * 0.58, y = s * 0.46, w = s * 0.56, h = s * 0.16, r = -50, corner = 4 },
	}, { { 0, Color3.fromRGB(190, 255, 190) }, { 1, Color3.fromRGB(50, 210, 90) } }, 2, 21)
	return function(met)
		mark.Visible = met
		frameStroke.Color = if met then Color3.fromRGB(90, 230, 150) else Color3.fromRGB(110, 120, 160)
		frame.BackgroundColor3 = if met then Color3.fromRGB(20, 60, 50) else Color3.fromRGB(24, 28, 60)
	end
end

-- ---------- Column layout ----------
local COL_Y, COL_H = 206, 384
local LEFT_W, MID_W = 320, 440
local RIGHT_W = CW - 40 - LEFT_W - MID_W - 32
local LEFT_X = 20
local MID_X = LEFT_X + LEFT_W + 16
local RIGHT_X = MID_X + MID_W + 16

-- Current Rebirths: the count inside a glowing black hole.
local countBody, cbw, cbh = column("CurrentRebirths", LEFT_X, COL_Y, LEFT_W, COL_H, "Current Rebirths")
if has(ART.CounterRing) then
	image(countBody, "CounterArt", ART.CounterRing, cbw / 2, 174, 260, 220, 19)
else
	drawnVortex(countBody, cbw / 2, 174, 230, 19)
end
for _, s in ipairs({ { 0.18, 0.28, 24, GOLD }, { 0.84, 0.26, 28, GOLD }, { 0.2, 0.58, 22, GOLD }, { 0.8, 0.6, 24, GOLD }, { 0.5, 0.2, 14, WHITE } }) do
	sparkle(countBody, cbw * s[1], cbh * s[2], s[3], s[4], 25, true)
end
local countLabel = text(countBody, "Count", "0", cbw / 2 - 80, 124, 160, 100, 96, WHITE, 26)
countLabel.TextWrapped = false
gradient(countLabel, { { 0, Color3.fromRGB(255, 255, 255) }, { 1, Color3.fromRGB(150, 230, 255) } })
local countPop = make("UIScale", {}, countLabel)
text(countBody, "Tagline", "Each rebirth makes you stronger forever!", 16, cbh - 76, cbw - 32, 58, 24, WHITE, 20)

-- Next Rebirth Rewards: four rows, value + note.
local rewardsBody, rbw = column("Rewards", MID_X, COL_Y, MID_W, COL_H, "Next Rebirth Rewards")
local REWARD_KEYS = { "Income", "SpawnSpeed", "UpgradeCaps", "StartingTier" }
local rewardRows = {}
for i, key in ipairs(REWARD_KEYS) do
	local strip, sw = row(rewardsBody, "Reward" .. key, 62 + (i - 1) * 76, rbw, 68)
	icon(strip, "Icon", REWARD_ICONS[key], key, 8, 6, 58)
	rewardRows[key] = {
		value = text(strip, "Value", "", 76, 6, sw - 88, 32, 26, CYAN, 22, Enum.TextXAlignment.Left),
		note = text(strip, "Note", "(Permanent)", 76, 38, sw - 88, 24, 19, MUTED, 22, Enum.TextXAlignment.Left),
	}
end

-- Requirements: one row per RebirthConfig requirement (up to four shown).
local reqBody, qbw = column("Requirements", RIGHT_X, COL_Y, RIGHT_W, COL_H, "Requirements")
local REQUIREMENT_LABELS = {
	Tier = "Max Tier Reached", Stardust = "Stardust", BlackHoles = "Black Holes", UpgradesAtCap = "All Upgrades",
}
local requirementRows = {}
for i = 1, 4 do
	local strip, sw = row(reqBody, "Requirement" .. i, 62 + (i - 1) * 76, qbw, 68)
	requirementRows[i] = {
		strip = strip,
		iconHolder = box(strip, "IconHolder", 8, 6, 58, 58, WHITE, 20, { BackgroundTransparency = 1 }),
		label = text(strip, "Label", "", 74, 6, sw - 132, 30, 23, WHITE, 22, Enum.TextXAlignment.Left),
		value = text(strip, "Value", "", 74, 36, sw - 132, 28, 23, GREEN, 22, Enum.TextXAlignment.Left),
		setCheck = checkBox(strip, sw - 54, 13, 44),
		kind = nil,
	}
end
local allDone = text(reqBody, "AllDone", "Every rebirth complete!", 16, 150, qbw - 32, 80, 28, GOLD, 20)

text(content, "ResetNote", "Rebirthing resets Stardust, black holes & inventory. Upgrades, Gems & the Index are kept.",
	60, COL_Y + COL_H + 4, CW - 120, 24, 19, Color3.fromRGB(255, 205, 160), 12)

-- ===================== REBIRTH BUTTON =====================
local BUTTON_W, BUTTON_H = 580, 100
local rebirthButton = make("TextButton", {
	Name = "RebirthButton", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CW / 2, CH - 72),
	Size = UDim2.fromOffset(BUTTON_W, BUTTON_H), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 30,
}, content)
rebirthButton:SetAttribute("OwnPressAnimation", true)
local buttonScale = make("UIScale", {}, rebirthButton)
-- Outer ring (magenta -> cyan, like the reference), then the glossy face.
local ringFrame = pill(box(rebirthButton, "Ring", -10, -10, BUTTON_W + 20, BUTTON_H + 20, WHITE, 30))
stroke(ringFrame, INK, 4)
gradient(ringFrame, { { 0, Color3.fromRGB(255, 110, 230) }, { 1, Color3.fromRGB(80, 200, 255) } }, 0)
pill(box(rebirthButton, "Depth", 0, 8, BUTTON_W, BUTTON_H, INK, 31))
local face = pill(box(rebirthButton, "Face", 0, 0, BUTTON_W, BUTTON_H, WHITE, 32))
stroke(face, INK, 4)
local faceGradient = gradient(face, GREEN_FILL)
pill(box(face, "Shine", 30, 8, BUTTON_W - 60, 32, WHITE, 33, { BackgroundTransparency = 0.62 }))
sparkle(face, 60, 30, 22, WHITE, 34, true)
sparkle(face, BUTTON_W - 60, 80, 18, WHITE, 34, true)

-- Button content: circular-arrows icon + label, centred together.
local buttonRow = box(face, "Content", BUTTON_W / 2, BUTTON_H / 2, 0, BUTTON_H, WHITE, 35, {
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X,
})
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder,
}, buttonRow)
local buttonIcon = box(buttonRow, "Icon", 0, 0, 78, 78, WHITE, 36, { BackgroundTransparency = 1, LayoutOrder = 1 })
if has(ART.ButtonIcon) then
	image(buttonIcon, "Art", ART.ButtonIcon, 39, 39, 78, 78, 37)
else
	-- Circular arrows: a thick ring with two gaps (a band cut across it at
	-- 45 degrees) and an arrow head at each gap.
	for pass, spec in ipairs({ { INK, 18 }, { WHITE, 11 } }) do
		local ring = orbit(buttonIcon, 39, 39, 52, 52, spec[1], spec[2], 0, 36 + pass)
		make("UIGradient", {
			Rotation = 45,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.44, 0), NumberSequenceKeypoint.new(0.445, 1),
				NumberSequenceKeypoint.new(0.555, 1), NumberSequenceKeypoint.new(0.56, 0), NumberSequenceKeypoint.new(1, 0),
			}),
		}, ring:FindFirstChildOfClass("UIStroke"))
	end
	for _, head in ipairs({ { 62, 22, 135 }, { 16, 56, -45 } }) do
		outlined(buttonIcon, { { x = head[1], y = head[2], w = 22, h = 22, r = head[3], corner = 3, cut = 0.5 } },
		{ { 0, WHITE }, { 1, Color3.fromRGB(200, 235, 255) } }, 3, 38)
	end
end
local buttonLabel = make("TextLabel", {
	Name = "Label", LayoutOrder = 2, Size = UDim2.fromOffset(0, BUTTON_H), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1, Font = FONT, Text = "REBIRTH", TextSize = 68, TextColor3 = WHITE, ZIndex = 36,
}, buttonRow)
stroke(buttonLabel, INK, 5, true)
gradient(buttonLabel, { { 0, WHITE }, { 1, Color3.fromRGB(200, 240, 255) } })

local buttonGlowFrame = pill(box(rebirthButton, "GuideGlow", -18, -18, BUTTON_W + 36, BUTTON_H + 36, WHITE, 29, { BackgroundTransparency = 1 }))
glows.Button = stroke(buttonGlowFrame, GOLD, 7, false, 1)

local BUTTON_FILLS = {
	ready = GREEN_FILL,
	locked = { { 0, Color3.fromRGB(160, 170, 205) }, { 0.45, Color3.fromRGB(100, 108, 146) }, { 1, Color3.fromRGB(62, 66, 104) } },
	confirm = { { 0, Color3.fromRGB(255, 180, 150) }, { 0.45, Color3.fromRGB(240, 80, 90) }, { 1, Color3.fromRGB(160, 20, 60) } },
}
local function setButton(styleName, label)
	local keys = {}
	for i, stop in ipairs(BUTTON_FILLS[styleName]) do keys[i] = ColorSequenceKeypoint.new(stop[1], stop[2]) end
	faceGradient.Color = ColorSequence.new(keys)
	buttonLabel.Text = label
	-- Longer wording steps down so it always fits the button.
	buttonLabel.TextSize = math.floor(math.min(68, (BUTTON_W - 150) / math.max(#label * 0.66, 1)))
	buttonIcon.Visible = styleName ~= "confirm"
end

-- Decorations on the frame edge (plain labels: they never take clicks).
local decor = box(panel, "Decor", 0, 0, PANEL.X, PANEL.Y, WHITE, 40, { BackgroundTransparency = 1 })
local function bigStar(cx, cy, size)
	if has(ART.GoldStar) then image(decor, "GoldStar", ART.GoldStar, cx, cy, size, size, 44)
	else sparkle(decor, cx, cy, size, GOLD, 44, true) end
end
bigStar(24, 520, 76)
bigStar(PANEL.X - 18, 280, 70)
bigStar(PANEL.X - 26, 660, 70)
bigStar(80, 60, 64)

-- ===================== FIT / REGISTER =====================
local function refreshScale()
	local availW, availH
	if UiResponsive and UiResponsive.ModalArea then
		availW, availH = UiResponsive.ModalArea()
	elseif UiResponsive and UiResponsive.SafeRect then
		local _, size = UiResponsive.SafeRect()
		availW, availH = size.X, size.Y
	else
		local vp = workspace.CurrentCamera.ViewportSize
		availW, availH = vp.X, vp.Y
	end
	if availW < 2 then return end
	local boost = if UiResponsive and UiResponsive.Boost then UiResponsive.Boost() else 1
	fitScale.Scale = math.clamp(math.min((availW - 24) / FIT.X, (availH - 24) / FIT.Y), 0.3, boost)
end
refreshScale()
if UiResponsive and UiResponsive.Changed then UiResponsive.Changed:Connect(refreshScale) end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)

-- Same pop-in / pop-out as the Upgrade window.
GuiManager:Register("Rebirth", root, {
	OpenScale = 0.86, OpenOvershootScale = 1, OpenRise = 8,
	OpenPopTween = TweenInfo.new(0.23, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	CloseBounceScale = 1,
	CloseScale = 0.92, CloseShrinkTween = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
})

-- ===================== STATE =====================
local confirmUntil = 0
local requesting = false
local subtitleUntil = 0

local function rebirths()
	return math.max(0, math.floor(tonumber(player:GetAttribute(REBIRTHS)) or 0))
end

local function requirementList()
	local raw = player:GetAttribute("RebirthRequirements")
	if type(raw) == "string" and raw ~= "" then
		local ok, rows = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(rows) == "table" then return rows end
	end
	return {}
end

local function canRebirth()
	return player:GetAttribute("CanRebirth") == true
end

local function capAt(count)
	local best = 0
	for _, item in ipairs(UpgradeConfig.Items) do
		best = math.max(best, if UpgradeConfig.GetLevelCap then UpgradeConfig.GetLevelCap(item.Id, count) else item.MaxLevel)
	end
	return best
end

local function percent(multiplier)
	return math.floor((multiplier - 1) * 100 + 0.5)
end

local function setSubtitle(message, seconds)
	subtitle.Text = message
	subtitleUntil = os.clock() + (seconds or 3)
end

local function refreshNow()
	local count = rebirths()
	local nextCount = count + 1
	countLabel.Text = tostring(count)
	if os.clock() >= subtitleUntil then subtitle.Text = SUBTITLE end

	-- Rewards: what the next rebirth adds.
	local speedGain = percent(RebirthConfig.GetSpawnSpeedMultiplier(nextCount)) - percent(RebirthConfig.GetSpawnSpeedMultiplier(count))
	rewardRows.Income.value.Text = ("Stardust x%.2f → x%.2f"):format(
		RebirthConfig.GetIncomeMultiplier(count), RebirthConfig.GetIncomeMultiplier(nextCount))
	rewardRows.Income.note.Text = "(Permanent - coins are worth more too)"
	rewardRows.SpawnSpeed.value.Text = ("+%d%% Spawn Speed"):format(speedGain)
	local tierCap, nextTierCap = capAt(count), capAt(nextCount)
	rewardRows.UpgradeCaps.value.Text = if RebirthConfig.GetSpawnTierCap
		then ("Spawn Tier cap %d → %d"):format(RebirthConfig.GetSpawnTierCap(count), RebirthConfig.GetSpawnTierCap(nextCount))
		else ("Upgrade Caps Lv %d → %d"):format(tierCap, nextTierCap)
	rewardRows.UpgradeCaps.note.Text = "Upgrades restart at 0 - go further!"
	local startNow, startNext = RebirthConfig.GetStartingTier(count), RebirthConfig.GetStartingTier(nextCount)
	rewardRows.StartingTier.value.Text = if startNext > startNow then ("Start at Tier %d"):format(startNext) else "Starting Tier maxed"
	rewardRows.StartingTier.note.Text = if startNext > startNow then "Spawn stronger black holes!" else "(Permanent)"

	-- Requirements: exactly what the server says.
	local list = requirementList()
	local complete = player:GetAttribute("RebirthsComplete") == true
	allDone.Visible = complete
	for i, r in ipairs(requirementRows) do
		local data = list[i]
		r.strip.Visible = data ~= nil and not complete
		if data then
			if r.kind ~= data.kind then
				r.kind = data.kind
				r.iconHolder:ClearAllChildren()
				local artId = REQUIREMENT_ICONS[data.kind]
				if has(artId) then
					image(r.iconHolder, "Art", artId, 29, 29, 58, 58, 22)
				elseif drawnIcons[data.kind] then
					drawnIcons[data.kind](r.iconHolder, 58)
				end
			end
			local have, need = tonumber(data.have) or 0, tonumber(data.need) or 0
			r.label.Text = REQUIREMENT_LABELS[data.kind] or tostring(data.kind)
			if data.kind == "Tier" then
				r.value.Text = ("T%d / T%d"):format(math.min(have, need), need)
			elseif data.kind == "Stardust" then
				r.value.Text = ("%s / %s"):format(abbreviate(math.min(have, need)), abbreviate(need))
			elseif data.kind == "UpgradesAtCap" then
				r.value.Text = if data.met then "At Level Cap" else "Not at cap yet"
			else
				r.value.Text = ("%d / %d"):format(math.min(have, need), need)
			end
			r.value.TextColor3 = if data.met then GREEN else RED
			r.setCheck(data.met == true)
		end
	end

	-- Button.
	local can = canRebirth()
	rebirthButton.Active = can and not requesting
	if requesting then
		setButton("locked", "REBIRTHING…")
	elseif complete then
		setButton("locked", "ALL DONE")
	elseif not can then
		setButton("locked", "REBIRTH")
	elseif os.clock() < confirmUntil then
		setButton("confirm", "PRESS AGAIN TO CONFIRM")
	else
		setButton("ready", "REBIRTH")
	end
end

-- One bad value must never stop the window (or the side button) working.
local refreshWarned = false
local function refresh()
	local ok, err = pcall(refreshNow)
	if not ok and not refreshWarned then
		refreshWarned = true
		warn("[RebirthClient] refresh failed:", err)
	end
end

-- ===================== MOTION (only while open) =====================
local ambient = {}
local glowRunning = false
local function stopMotion()
	for _, t in ipairs(ambient) do t:Cancel() end
	table.clear(ambient)
	for _, scale in ipairs(twinkles) do scale.Scale = 1 end
	planetHolder.Rotation = 0
end
local function startMotion()
	stopMotion()
	if not reduced() then
		for _, scale in ipairs(twinkles) do
			local tween = TweenService:Create(scale,
				TweenInfo.new(math.random(14, 26) / 10, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, math.random() * 2),
				{ Scale = 0.55 })
			tween:Play()
			table.insert(ambient, tween)
		end
		local drift = TweenService:Create(planetHolder, TweenInfo.new(7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 4 })
		drift:Play()
		table.insert(ambient, drift)
	end
	if glowRunning then return end
	glowRunning = true
	task.spawn(function()
		-- The REBIRTH button glows whenever it can be pressed; a panel glows
		-- while Nibbles points at it.
		while root.Visible do
			local wave = if reduced() then 0.5 else (math.sin(os.clock() * 4) + 1) / 2
			local focus = root:GetAttribute("GuideHighlight") or ""
			local can = canRebirth() and not requesting
			for name, s in pairs(glows) do
				local on = focus == name or (name == "Button" and can)
				s.Transparency = if on then 0.05 + wave * 0.45 else 1
				s.Thickness = if on then 5 + wave * 4 else 5
			end
			buttonScale.Scale = if can and not reduced() then 1 + wave * 0.02 else 1
			task.wait(1 / 30)
		end
		for _, s in pairs(glows) do s.Transparency = 1 end
		glowRunning = false
	end)
end
root:GetPropertyChangedSignal("Visible"):Connect(function()
	if root.Visible then startMotion() else stopMotion() end
end)

-- ===================== OPEN / CLOSE =====================
local function openWindow()
	confirmUntil = 0
	refresh()
	if UIAssets.EnsureGroup then UIAssets.EnsureGroup("Rebirth") end
	GuiManager:Open("Rebirth")
end

local function closeWindow()
	if GuiManager:GetCurrent() == "Rebirth" then
		GuiManager:Close("Rebirth")
	end
end
GuiManager:SetBackHandler("Rebirth", closeWindow)
closeButton.Activated:Connect(closeWindow)

-- ===================== REBIRTH =====================
local remote = nil
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("BlackHoleRemotes", 60)
	remote = folder and folder:WaitForChild("RequestRebirth", 30)
	if not remote then
		warn("[RebirthClient] BlackHoleRemotes.RequestRebirth not found. Update BlackHoleSystemServer.")
	end
end)

local clickSound = make("Sound", { Name = "RebirthClick", SoundId = "rbxassetid://129349771709668", Volume = 0.8 }, SoundService)

rebirthButton.Activated:Connect(function()
	if requesting or not canRebirth() then return end
	-- Two presses: a rebirth resets progress, so it is never one mis-click.
	if os.clock() >= confirmUntil then
		confirmUntil = os.clock() + 4
		refresh()
		return
	end
	if not remote then
		setSubtitle("Rebirth isn't available right now.")
		return
	end
	confirmUntil = 0
	requesting = true
	refresh()
	local ok, result = pcall(function() return remote:InvokeServer() end)
	requesting = false
	if ok and type(result) == "table" and result.ok then
		-- Only now (the server has done it) does the ceremony play: the
		-- window steps aside and RebirthCeremonyClient takes over.
		clickSound:Play()
		setSubtitle("Rebirth complete! You're stronger forever!", 4)
		closeWindow()
		local folder = ReplicatedStorage:FindFirstChild("ClientSignals")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "ClientSignals"
			folder.Parent = ReplicatedStorage
		end
		local signal = folder:FindFirstChild("RebirthCelebration")
		if not signal then
			signal = Instance.new("BindableEvent")
			signal.Name = "RebirthCelebration"
			signal.Parent = folder
		end
		signal:Fire(tonumber(result.rebirths) or rebirths())
	elseif ok and type(result) == "table" and result.reason == "requirement" then
		setSubtitle("Not every requirement is met yet.")
	elseif ok and type(result) == "table" and result.reason == "busy" then
		setSubtitle("One moment…", 1.5)
	else
		setSubtitle("Rebirth failed. Try again.")
	end
	refresh()
end)

-- Hover / press on the REBIRTH button: the face lifts and sinks.
rebirthButton.MouseEnter:Connect(function()
	if not rebirthButton.Active or reduced() then return end
	TweenService:Create(face, TweenInfo.new(0.12), { Position = UDim2.fromOffset(0, -3) }):Play()
end)
rebirthButton.MouseLeave:Connect(function()
	TweenService:Create(face, TweenInfo.new(0.12), { Position = UDim2.fromOffset(0, 0) }):Play()
end)
rebirthButton.MouseButton1Down:Connect(function()
	if rebirthButton.Active then
		TweenService:Create(face, TweenInfo.new(0.06), { Position = UDim2.fromOffset(0, 5) }):Play()
	end
end)
rebirthButton.MouseButton1Up:Connect(function()
	TweenService:Create(face, TweenInfo.new(0.14, Enum.EasingStyle.Back), { Position = UDim2.fromOffset(0, 0) }):Play()
end)

for _, attribute in ipairs({ REBIRTHS, "RebirthRequirements", "CanRebirth", "RebirthsComplete" }) do
	player:GetAttributeChangedSignal(attribute):Connect(refresh)
end
task.spawn(function()
	-- The confirm prompt and messages time out on their own.
	while true do
		task.wait(0.5)
		if root.Visible then refresh() end
	end
end)
refresh()

-- ===================== SIDE MENU BUTTON =====================
task.spawn(function()
	local hud = playerGui:WaitForChild("MainHUD", 30)
	local slot = hud and hud:FindFirstChild("RebirthSlot", true)
	local started = os.clock()
	while hud and not slot and os.clock() - started < 15 do
		task.wait(0.2)
		slot = hud:FindFirstChild("RebirthSlot", true)
	end
	local button = slot and slot:FindFirstChild("Rebirth")
	if not button then
		warn("[RebirthClient] Couldn't find the Rebirth button in MainHUD.")
		return
	end
	button.Activated:Connect(function()
		if GuiManager:GetCurrent() == "Rebirth" then
			closeWindow()
		else
			openWindow()
		end
	end)
end)
