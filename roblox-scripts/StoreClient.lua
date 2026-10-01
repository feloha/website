-- StoreClient (LocalScript in StarterPlayer > StarterPlayerScripts)
--
-- SECRET STORE - STRUCTURAL REBUILD, STAGE 1
--   window shell -> header -> GAMEPASSES banner -> one card template -> rows
--
-- Background decoration, extra motion and the responsive breakpoints are
-- deliberately NOT in this stage. Structure first.
--
-- Every proportion in the layout comes from TUNE below, so a change after a
-- playtest is a number here, never a rewrite.
--
-- Unchanged from before: StoreConfig items, titles and prices; the purchase
-- placeholder (all StoreConfig ids are still 0); the RedeemCode remote; the
-- gift popup; GuiManager registration, back handler and the collapse
-- open/close animation; the MainHUD Store button hookup; artwork ids from
-- ReplicatedStorage > UIAssets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GuiManager = require(ReplicatedStorage:WaitForChild("GuiManager"))
local StoreConfig = require(ReplicatedStorage:WaitForChild("StoreConfig"))
local GuiStyle = require(ReplicatedStorage:WaitForChild("GuiStyle"))
local StardustCollectAnimator = require(ReplicatedStorage:WaitForChild("StardustCollectAnimator"))

local UIAssets do
	local module = ReplicatedStorage:WaitForChild("UIAssets", 10)
	if module then
		UIAssets = require(module)
	else
		warn("[StoreClient] ReplicatedStorage > UIAssets is missing: add the module to show the store artwork.")
		UIAssets = { CardArt = {} }
	end
end


-- Did this image really load? Uses the module's helper when it is there, and
-- does the same check itself when it is not, so an older UIAssets copy cannot
-- leave the artwork switched off.
local function whenImageReady(id, callback)
	if UIAssets.WhenReady then
		UIAssets.WhenReady(id, callback)
		return
	end

	if type(id) ~= "string" or id == "" then
		task.spawn(callback, false)
		return
	end

	task.spawn(function()
		local loaded = false
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ id }, function(_, status)
				loaded = status == Enum.AssetFetchStatus.Success
			end)
		end)
		callback(ok and loaded)
	end)
end


-- Waits for an ImageLabel to actually have its picture, then reports. Uses the
-- label's own IsLoaded flag, so nothing else has to be installed for this to
-- work. Never yields the caller.
local function watchImage(label, callback)
	task.spawn(function()
		local deadline = os.clock() + 12
		while os.clock() < deadline do
			if label.IsLoaded then
				callback(true)
				return
			end
			task.wait(0.2)
		end

		if label.IsLoaded then
			callback(true)
			return
		end

		-- Not there yet: say so, then keep watching. A slow image that lands
		-- late still gets its moment instead of being written off.
		callback(false)

		-- Moderation on a fresh upload can take a while, so this keeps looking
		-- for ten minutes. The moment the image is served it takes over.
		local giveUp = os.clock() + 600
		while os.clock() < giveUp do
			if label.IsLoaded then
				callback(true)
				return
			end
			task.wait(3)
		end
	end)
end

local UiResponsive do
	local module = ReplicatedStorage:FindFirstChild("UiResponsive")
	local ok, result = pcall(function() return module and require(module) end)
	UiResponsive = if ok and type(result) == "table" then result else nil
end

local remotes = ReplicatedStorage:WaitForChild("StoreRemotes")
local redeemRemote = remotes:WaitForChild("RedeemCode")

local FONT = Enum.Font.FredokaOne
local COL = GuiStyle.COL

-- ===================== TUNE =====================
-- The whole layout in one place. After a playtest, this is what changes.
local TUNE = {
	-- Window. Design pixels; a UIScale fits them to the screen.
	-- Wider than before: on a 16:9 screen the height binds, so extra design
	-- width is free real estate and goes straight into the cards.
	DesignWidth = 1760,
	DesignHeight = 1190,
	-- Phones (landscape screens are short): a shorter window with the same
	-- header. The products scroll, and the window can be drawn ~30% larger,
	-- so cards and text are bigger instead of squeezed into a tall frame.
	CompactDesignHeight = 900,
	-- Share of the screen the window may use. Desktop matches the Upgrade and
	-- Leaderboards windows; phones keep the full size (space is tight there).
	WidthShare = 0.72,
	HeightShare = 0.76,
	CompactWidthShare = 0.92,   -- phones: of the usable area (below the top bar)
	CompactHeightShare = 0.9,
	MaxUpscale = 1.2,

	HeaderHeight = 0.32,      -- share of window height
	BodyPadTop = 8,
	BodyPadBottom = 8,
	BodySideMargin = 20,

	-- Header pieces, in pixels at design size. The cart is deliberately taller
	-- than the header band: in the reference it reads as a sticker stuck on
	-- top of the panel, not an icon sitting inside a bar.
	ShopIcon = 420,           -- layout slot: the title and subtitle measure from this
	ShopLeft = 26,

	-- The cart is drawn on its own layer outside the window so it can hang
	-- over the frame. These three are the whole effect: how much bigger it is
	-- drawn than its layout slot, and how far past the window's edge it pokes,
	-- in design pixels.
	--
	-- The spill is sideways, not upward, and that is a constraint rather than
	-- a preference. The window is 1190 design tall and fits itself to the
	-- screen by height, so it leaves only about 18-26 design pixels above it
	-- at every common resolution (1920x1080 -> 18, 1366x768 -> 26,
	-- 1680x1050 -> 19). Sideways it has 102-224 to play with. So the cart
	-- hangs well past the left edge and barely over the top; anything more
	-- upward and it is the screen that clips it, not the window.
	ShopSpillScale = 1.14,
	ShopSpillLeft = 96,       -- 86px of overhang; the tightest screen allows ~102
	ShopSpillUp = 0,          -- the recentring alone puts 10px over the top edge

	TitleAspect = 1.8,        -- width / height of the logo artwork itself

	-- The logo, as its own three numbers rather than measured off the cart.
	-- The cart is drawn outside the window now, so its layout slot no longer
	-- says where the logo should start.
	--
	-- TitleHeight has a ceiling: the lettering inside the artwork ends around
	-- 76% down its box, and the subtitle at y=342 cannot move. 440 leaves 8px
	-- between them; 470 would put the lower stars through the subtitle.
	TitleHeight = 440,
	TitleLeft = 170,
	TitleTop = 0,
	-- Kept where it was so a bigger logo does not push the subtitle down into
	-- the body: this is the old 6 + 360 - 24.
	SubtitleTop = 342,
	SubtitleHeight = 32,
	GiftSize = 244,
	CloseSize = 112,
	HeaderGapRight = 30,

	-- Section banner.
	BannerWidth = 0.42,       -- share of the body width
	BannerHeight = 60,
	BannerStar = 58,
	BannerGapBelow = 10,

	-- Cards.
	CardGap = 30,
	CardRowGap = 12,
	CardsPerRow = 3,
	LastRowScale = 1.04,      -- the short bottom row runs slightly larger
	CardRatio = 1.64,         -- width / height; the reference sits at 1.25,
	-- and this is the tallest that keeps both rows
	-- on screen with no scrolling.

	-- Card interior, as shares of card height. They must not overlap.
	-- strip 17.5%  ->  artwork 43.5%  ->  description 13.5%  ->  footer 19%
	-- Close to the reference's 19 / 16 / 20 split, with the extra height left
	-- in the artwork because our illustration is squarer than the drawing in
	-- the reference and needs height to reach the same width.
	-- The strip starts flush with the top of the card, like packaging.
	StripTop = 0.005, StripHeight = 0.17,
	ArtTop = 0.19, ArtHeight = 0.45,
	DescTop = 0.66, DescHeight = 0.12,
	FooterHeight = 0.19, FooterBottom = 0.975,

	-- Long names ("Quicker Protection Cooldown") get a taller two-line strip
	-- and give the room back from the artwork, exactly as the reference does.
	LongTitleChars = 20,
	LongStripExtra = 0.055,
}

-- ===================== ARTWORK CROP =====================
-- Each perk PNG has its name printed across the bottom, and the card already
-- has a pink title strip saying the same thing. The file is never edited: it
-- sits in a ClipsDescendants window, and only the band named here is shown.
--
--   Aspect = width / height of the whole PNG
--   Crop   = share of the height hidden at the BOTTOM (the lettering)
--   Top    = share of the height hidden at the TOP (empty margin)
--   Nudge  = moves the window inside its slot, for optical centring
--
-- The window is always exactly as tall as the artwork slot, so how large the
-- illustration looks depends only on how much of the file is inside it.
--
-- These were measured with the tuner (press 9 in Studio), not estimated, which
-- is why they differ so much: Auto Merge is a portrait canvas needing 28% off
-- the top, while Quicker Launch is landscape and needs almost nothing. No one
-- crop was ever going to fit all five.
local ART_CROP = {
	AutoMerge                 = { Aspect = 0.80, Crop = 0.29, Top = 0.28, Nudge = 0.08, Tint = Color3.fromRGB(122, 150, 255) },
	X2Spawn                   = { Aspect = 1.10, Crop = 0.22, Top = 0.18, Nudge = 0.08, Tint = Color3.fromRGB(150, 116, 255) },
	X2BlackHoleHP             = { Aspect = 1.10, Crop = 0.17, Top = 0.16, Nudge = 0.08, Tint = Color3.fromRGB(196, 110, 255) },
	QuickerProtectionCooldown = { Aspect = 1.10, Crop = 0.15, Top = 0.14, Nudge = 0.06, Tint = Color3.fromRGB(110, 190, 255) },
	QuickerLaunchCooldown     = { Aspect = 1.10, Crop = 0.13, Top = 0.13, Nudge = 0.08, Tint = Color3.fromRGB(110, 190, 255) },
}

-- Every cropped picture registers here so the Studio tuner can adjust it live.
local CROPPED = {}

-- ===================== PALETTE =====================
local C = {
	Shadow = Color3.fromRGB(3, 6, 26),
	ShellNavy = Color3.fromRGB(10, 18, 58),        -- outer dark edge
	BorderBlue = Color3.fromRGB(46, 134, 255),     -- bright blue frame
	EdgeCyan = Color3.fromRGB(111, 232, 255),      -- inner highlight

	-- Dark canvas, bright contents. The reference gets its punch from this.
	BodyTop = Color3.fromRGB(38, 66, 190),         -- store interior
	BodyMid = Color3.fromRGB(22, 40, 138),
	BodyBottom = Color3.fromRGB(34, 54, 168),

	HeaderTop = Color3.fromRGB(48, 88, 228),
	HeaderBottom = Color3.fromRGB(14, 26, 104),

	BannerTop = Color3.fromRGB(70, 96, 232),
	BannerBottom = Color3.fromRGB(26, 40, 136),

	CardEdge = Color3.fromRGB(10, 22, 70),         -- deep navy outline
	CardRim = Color3.fromRGB(86, 222, 255),        -- bright cyan edge
	CardRimHover = Color3.fromRGB(176, 248, 255),
	-- Card interior: violet under the strip, royal purple through the middle
	-- where the artwork sits, deep blue at the bottom behind the price.
	CardTop = Color3.fromRGB(92, 58, 218),
	CardMid = Color3.fromRGB(104, 72, 236),
	CardBottom = Color3.fromRGB(18, 30, 116),
	CardGlow = Color3.fromRGB(168, 138, 255),
	CardInnerEdge = Color3.fromRGB(120, 220, 255),

	StripTop = Color3.fromRGB(255, 168, 252),      -- magenta title strip
	StripMid = Color3.fromRGB(246, 62, 216),
	StripBottom = Color3.fromRGB(198, 20, 168),
	StripEdge = Color3.fromRGB(96, 12, 92),

	GreenTop = Color3.fromRGB(186, 255, 104),      -- purchase footer
	GreenMid = Color3.fromRGB(92, 232, 86),
	GreenBottom = Color3.fromRGB(22, 176, 62),
	GreenEdge = Color3.fromRGB(10, 92, 44),

	OwnedTop = Color3.fromRGB(128, 246, 214),
	OwnedBottom = Color3.fromRGB(24, 176, 148),
	OwnedEdge = Color3.fromRGB(8, 84, 70),

	Cream = Color3.fromRGB(255, 252, 240),
	Ink = Color3.fromRGB(14, 22, 58),
}

local old = playerGui:FindFirstChild("StoreUI")
if old then
	old:Destroy()
end

-- Store item click sound removed.
-- TODO: Later, put your real Store click sound here.
local function playStoreClickSoundLater()
end

-- ===================== BUILDING BLOCKS =====================
local function corner(object, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = if typeof(radius) == "UDim" then radius else UDim.new(0, radius or 12)
	c.Parent = object
	return c
end

local function stroke(object, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = object
	return s
end

local function gradient(object, top, bottom, rotation)
	object.BackgroundColor3 = Color3.new(1, 1, 1)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 90
	g.Color = if typeof(top) == "ColorSequence" then top else ColorSequence.new(top, bottom)
	g.Parent = object
	return g
end

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.Name = props.Name or "Frame"
	f.AnchorPoint = props.AnchorPoint or Vector2.zero
	f.Position = props.Position or UDim2.new()
	f.Size = props.Size or UDim2.fromScale(1, 1)
	f.BackgroundColor3 = props.Color or Color3.new(1, 1, 1)
	f.BackgroundTransparency = props.Transparency or 0
	f.BorderSizePixel = 0
	f.Rotation = props.Rotation or 0
	f.LayoutOrder = props.Order or 0
	f.ZIndex = props.ZIndex or 1
	f.ClipsDescendants = props.Clip or false
	f.Parent = parent
	if props.Radius then corner(f, props.Radius) end
	if props.Round then corner(f, UDim.new(1, 0)) end
	if props.Gradient then gradient(f, props.Gradient[1], props.Gradient[2], props.Gradient[3]) end
	if props.Stroke then stroke(f, props.Stroke[1], props.Stroke[2], props.Stroke[3]) end
	return f
end

local function text(parent, props)
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "Text"
	label.BackgroundTransparency = 1
	label.AnchorPoint = props.AnchorPoint or Vector2.zero
	label.Position = props.Position or UDim2.new()
	label.Size = props.Size or UDim2.fromScale(1, 1)
	label.Text = props.Text or ""
	label.Font = props.Font or FONT
	label.TextWrapped = props.Wrap or false
	label.TextColor3 = props.Color or C.Cream
	label.TextXAlignment = props.AlignX or Enum.TextXAlignment.Center
	label.TextYAlignment = props.AlignY or Enum.TextYAlignment.Center
	label.ZIndex = props.ZIndex or 5
	label.TextScaled = true
	label.Visible = props.Visible ~= false
	label.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = props.Min or 12
	limit.MaxTextSize = props.Max or 34
	limit.Parent = label
	if props.Stroke ~= false then
		local s = Instance.new("UIStroke")
		s.Color = props.StrokeColor or C.Ink
		s.Thickness = props.StrokeThickness or 2.5
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Parent = label
	end
	return label
end

-- Artwork: never tinted, never stretched, always given room for its glow.
local function image(parent, props)
	local i = Instance.new("ImageLabel")
	i.Name = props.Name or "Art"
	i.BackgroundTransparency = 1
	i.BorderSizePixel = 0
	i.Active = false
	i.Image = props.Image or ""
	i.ImageTransparency = props.Alpha or 0
	i.ImageColor3 = Color3.new(1, 1, 1)
	i.ScaleType = Enum.ScaleType.Fit
	i.AnchorPoint = props.AnchorPoint or Vector2.zero
	i.Position = props.Position or UDim2.new()
	i.Size = props.Size or UDim2.fromScale(1, 1)
	i.ZIndex = props.ZIndex or 5
	i.ClipsDescendants = false
	i.Parent = parent
	return i
end

local function hoverScale(button, hover, press)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local current
	local function to(target)
		if current then current:Cancel() end
		current = TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Scale = target })
		current:Play()
	end
	local function held(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	button.MouseEnter:Connect(function() to(hover or 1.03) end)
	button.MouseLeave:Connect(function() to(1) end)
	button.InputBegan:Connect(function(input) if held(input) then to(press or 0.975) end end)
	button.InputEnded:Connect(function(input) if held(input) then to(1) end end)
	button.Activated:Connect(function() to(1) end)
	return scale
end

local function imageButton(parent, props)
	local b = Instance.new("ImageButton")
	b.Name = props.Name or "ArtButton"
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Image = props.Image or ""
	b.ImageColor3 = Color3.new(1, 1, 1)
	b.ScaleType = Enum.ScaleType.Fit
	b.AnchorPoint = props.AnchorPoint or Vector2.zero
	b.Position = props.Position or UDim2.new()
	b.Size = props.Size or UDim2.fromScale(1, 1)
	b.ZIndex = props.ZIndex or 20
	b.Parent = parent
	hoverScale(b, props.Hover, props.Press)
	return b
end

-- A broad soft sheen across the top of a surface.
local function gloss(face, inset, height, strength)
	local shine = frame(face, {
		Name = "Gloss",
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -inset * 2, height, 0),
		Color = Color3.new(1, 1, 1),
		Transparency = strength or 0.55,
		Radius = 16,
		ZIndex = face.ZIndex + 1,
	})
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0, 1)
	fade.Parent = shine
	return shine
end

local function displayTitle(title)
	if title == "x2 Stardust" then return "2x Stardust" end
	if title == "x4 Stardust" then return "4x Stardust" end
	if title == "x8 Stardust" then return "8x Stardust" end
	return title
end

if UIAssets.Preload then
	UIAssets.Preload("Primary")
end

-- ===================== WINDOW =====================
local gui = Instance.new("ScreenGui")
gui.Name = "StoreUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
if UiResponsive and UiResponsive.UseModalInsets then UiResponsive.UseModalInsets(gui) end   -- below the top bar
gui.DisplayOrder = 25
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

-- Decided once, from the real screen: phones never change size class.
local PHONE_STORE = false
do
	local cam = workspace.CurrentCamera
	local waited = 0
	while cam and cam.ViewportSize.X < 2 and waited < 3 do
		waited += task.wait()
	end
	PHONE_STORE = UiResponsive ~= nil and UiResponsive.Layout ~= nil and UiResponsive.Layout() == "compact"
end
local DESIGN_W = TUNE.DesignWidth
local DESIGN_H = if PHONE_STORE then TUNE.CompactDesignHeight else TUNE.DesignHeight

-- Layer 1: the shadow the window lifts off.
local windowShadow = frame(root, {
	Name = "OuterShadow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 18),
	Color = C.Shadow,
	Transparency = 0.42,
	Radius = 46,
	ZIndex = 9,
})
windowShadow.Visible = false

-- Layer 2 + 3: dark navy body carrying the bright blue frame.
local popup = Instance.new("Frame")
popup.Name = "StorePopup"
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.Position = UDim2.fromScale(0.5, 0.5)
popup.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H)
popup.BackgroundColor3 = C.ShellNavy
popup.Visible = false
popup.ClipsDescendants = true    -- the collapse animation needs this
popup.ZIndex = 10
popup.Parent = root
corner(popup, 38)
stroke(popup, C.BorderBlue, 9)

-- Layer 4: the cyan highlight just inside the frame.
frame(popup, {
	Name = "InnerEdge",
	Position = UDim2.fromOffset(9, 9),
	Size = UDim2.new(1, -18, 1, -18),
	Transparency = 1,
	Radius = 31,
	Stroke = { C.EdgeCyan, 3, 0.1 },
	ZIndex = 60,
})

-- Layer 5: the cosmic interior.
local content = frame(popup, {
	Name = "Content",
	Position = UDim2.fromOffset(13, 13),
	Size = UDim2.new(1, -26, 1, -26),
	Radius = 27,
	Clip = true,
	ZIndex = 11,
	Gradient = { ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.BodyTop),
		ColorSequenceKeypoint.new(0.55, C.BodyMid),
		ColorSequenceKeypoint.new(1, C.BodyBottom),
	}) },
})

-- A dark cosmic canvas so the bright things on top of it can pop. The drawn
-- version is always built; if your painted background actually loads it is
-- shown over the top and the drawn one is switched off. An id that is still a
-- Decal, or is waiting on moderation, sets Image happily and then draws
-- nothing, so "is the field set" is not a safe test: this asks the engine.
local backdrop = frame(content, { Name = "Backdrop", Transparency = 1, ZIndex = 12 })
local drawnSky = frame(backdrop, { Name = "DrawnSky", Transparency = 1, ZIndex = 12 })

do
	local function field(x, y, size, tint, alpha)
		local blob = frame(drawnSky, {
			Name = "ColourField", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(size, size * 0.72), Round = true, Color = tint,
			Transparency = alpha, ZIndex = 12,
		})
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = blob
	end
	field(0.2, 0.16, 0.7, Color3.fromRGB(96, 158, 255), 0.82)      -- upper left cobalt
	field(0.78, 0.2, 0.55, Color3.fromRGB(120, 130, 255), 0.88)    -- upper right lilac
	field(0.5, 0.62, 1.05, Color3.fromRGB(14, 24, 92), 0.8)        -- gentle depth, not a hole
	field(0.12, 0.9, 0.62, Color3.fromRGB(150, 128, 255), 0.84)    -- lower left violet
	field(0.9, 0.86, 0.64, Color3.fromRGB(96, 206, 255), 0.84)     -- lower right cyan

	-- A restrained star field: tiny points, not a photograph.
	local dust = {
		{ 0.07, 0.3, 4 }, { 0.13, 0.52, 3 }, { 0.26, 0.24, 3 }, { 0.33, 0.61, 4 },
		{ 0.46, 0.18, 3 }, { 0.58, 0.46, 3 }, { 0.68, 0.26, 4 }, { 0.79, 0.58, 3 },
		{ 0.88, 0.36, 4 }, { 0.94, 0.6, 3 }, { 0.5, 0.78, 3 }, { 0.21, 0.72, 3 },
	}
	for index, spot in ipairs(dust) do
		frame(drawnSky, {
			Name = "Dust" .. index, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spot[1], spot[2]), Size = UDim2.fromOffset(spot[3], spot[3]),
			Round = true, Color = if index % 3 == 0 then Color3.fromRGB(150, 235, 255) else Color3.new(1, 1, 1),
			Transparency = 0.25, ZIndex = 13,
		})
	end
end

local backgroundArt = image(backdrop, {
	Name = "BackgroundArt", Size = UDim2.fromScale(1, 1), ZIndex = 12,
	Image = UIAssets.StoreBackground or "",
})
backgroundArt.ScaleType = Enum.ScaleType.Crop

if backgroundArt.Image == "" then
	backgroundArt.Visible = false
else
	-- Never hidden by a verdict. An ImageLabel with an id that has not
	-- arrived yet simply draws nothing, so the drawn sky behind it is what
	-- shows; when the picture is confirmed, the drawn sky is what turns off.
	-- The old code hid the artwork instead, which meant one early "not loaded"
	-- answer hid it permanently even though the image arrived moments later.
	backgroundArt.Visible = true
	watchImage(backgroundArt, function(loaded)
		if loaded then
			drawnSky.Visible = false
		else
			warn(("[StoreClient] background art %s has not arrived; drawn sky kept."):format(
				backgroundArt.Image))
		end
	end)
end

-- The lower half is left clear on purpose: cloud banks, large stars and a
-- planet used to sit here and kept colliding with each other and with the
-- Codes panel. The soft colour wash above is all that remains.

local responsiveScale = Instance.new("UIScale")
responsiveScale.Name = "ResponsiveScale"
responsiveScale.Parent = popup
local shadowScale = Instance.new("UIScale")
shadowScale.Parent = windowShadow

local camera = workspace.CurrentCamera

local STORE_NORMAL_SIZE = UDim2.fromOffset(DESIGN_W, DESIGN_H)
local STORE_COLLAPSED_SIZE = UDim2.fromOffset(160, 26)
local STORE_HALF_OPEN_SIZE = UDim2.fromOffset(DESIGN_W, 96)

local storeAnimating = false

-- Everything that has to escape the window's clipping lives here. It is the
-- same size, position and scale as the window, so a child positioned at window
-- coordinates lands exactly where it would have inside - it simply is not cut
-- off at the edge. ZIndex 62 puts it over the frame's inner edge (60).
local spillLayer = Instance.new("Frame")
spillLayer.Name = "SpillLayer"
spillLayer.AnchorPoint = Vector2.new(0.5, 0.5)
spillLayer.Position = UDim2.fromScale(0.5, 0.5)
spillLayer.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H)
spillLayer.BackgroundTransparency = 1
spillLayer.BorderSizePixel = 0
spillLayer.Visible = false
spillLayer.ZIndex = 62
spillLayer.Parent = root

local spillScale = Instance.new("UIScale")
spillScale.Parent = spillLayer

local function syncShadow()
	windowShadow.Size = UDim2.fromOffset(popup.Size.X.Offset + 30, popup.Size.Y.Offset + 30)
	shadowScale.Scale = responsiveScale.Scale
	windowShadow.Visible = popup.Visible

	-- The cart rides the window: same size, same scale, shown and hidden with
	-- it. It is hidden while the window is collapsed or mid-animation, so it
	-- never floats on its own during the open and close.
	spillScale.Scale = responsiveScale.Scale
	spillLayer.Size = popup.Size
	spillLayer.Visible = popup.Visible
		and popup.Size.Y.Offset > DESIGN_H * 0.9
end

local function screenSize()
	if UiResponsive and UiResponsive.Screen then
		local ok, size = pcall(UiResponsive.Screen)
		if ok and typeof(size) == "Vector2" and size.X > 1 then
			return size
		end
	end
	return camera.ViewportSize
end

local function refreshScale()
	local vp = screenSize()
	if vp.X < 1 then return end
	-- Phones: the window fits the usable area (below the top bar, inside the
	-- notch). Bigger screens keep the exact size they had.
	if UiResponsive and UiResponsive.ModalArea and UiResponsive.Layout and UiResponsive.Layout() == "compact" then
		local ok, w, h = pcall(UiResponsive.ModalArea, { shareW = 1, shareH = 1 })
		if ok and type(w) == "number" and w > 1 then vp = Vector2.new(w, h) end
	end

	local compact = UiResponsive ~= nil and UiResponsive.Layout ~= nil and UiResponsive.Layout() == "compact"
	local scale = math.min(
		(vp.X * (if compact then TUNE.CompactWidthShare else TUNE.WidthShare)) / DESIGN_W,
		(vp.Y * (if compact then TUNE.CompactHeightShare else TUNE.HeightShare)) / DESIGN_H,
		TUNE.MaxUpscale * math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 1, 1.6)
	)

	responsiveScale.Scale = math.max(scale, 0.2)
	syncShadow()
end

refreshScale()
if UiResponsive then
	UiResponsive.Changed:Connect(refreshScale)
else
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
end
popup:GetPropertyChangedSignal("Size"):Connect(syncShadow)
popup:GetPropertyChangedSignal("Visible"):Connect(syncShadow)

GuiManager:Register("Store", popup, {
	BlurSize = 18,
	OpenScale = 1,
	OpenOvershootScale = 1,
	CloseBounceScale = 1,
	CloseScale = 1,
})

-- ===================== COLLAPSE OPEN/CLOSE =====================
local STORE_NORMAL_TRANSPARENCY = 0
local STORE_HALF_TRANSPARENCY = 0.2
local STORE_COLLAPSED_TRANSPARENCY = 1

local function forceManagerScaleNeutral()
	local managerScale = popup:FindFirstChild("GuiManagerScale")
	if managerScale then
		managerScale.Scale = 1
	end
end

local function openStoreNow()
	if storeAnimating then return end
	if GuiManager:GetCurrent() == "Store" or popup.Visible then return end

	storeAnimating = true

	popup.ClipsDescendants = true
	popup.Size = STORE_COLLAPSED_SIZE
	popup.Rotation = 0
	popup.BackgroundTransparency = STORE_COLLAPSED_TRANSPARENCY

	GuiManager:Open("Store")
	forceManagerScaleNeutral()

	local unfoldHeight = TweenService:Create(
		popup,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = STORE_HALF_OPEN_SIZE, BackgroundTransparency = STORE_HALF_TRANSPARENCY }
	)

	unfoldHeight:Play()

	unfoldHeight.Completed:Connect(function()
		if not popup.Visible then
			storeAnimating = false
			return
		end

		local unfoldFull = TweenService:Create(
			popup,
			TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Size = STORE_NORMAL_SIZE, BackgroundTransparency = STORE_NORMAL_TRANSPARENCY }
		)

		unfoldFull:Play()

		unfoldFull.Completed:Connect(function()
			popup.Size = STORE_NORMAL_SIZE
			popup.Rotation = 0
			popup.BackgroundTransparency = STORE_NORMAL_TRANSPARENCY
			forceManagerScaleNeutral()
			storeAnimating = false
		end)
	end)
end

local giftPopupCloser = nil

local function closeStoreCollapsed()
	if storeAnimating then return end
	if GuiManager:GetCurrent() ~= "Store" and not popup.Visible then return end
	if GuiManager.BeginClose then GuiManager:BeginClose("Store") end

	storeAnimating = true
	popup.ClipsDescendants = true
	forceManagerScaleNeutral()

	local collapseHeight = TweenService:Create(
		popup,
		TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = STORE_HALF_OPEN_SIZE, BackgroundTransparency = STORE_HALF_TRANSPARENCY }
	)

	collapseHeight:Play()

	collapseHeight.Completed:Connect(function()
		local collapseFull = TweenService:Create(
			popup,
			TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ Size = STORE_COLLAPSED_SIZE, BackgroundTransparency = STORE_COLLAPSED_TRANSPARENCY }
		)

		collapseFull:Play()

		collapseFull.Completed:Connect(function()
			GuiManager:Close("Store")
			popup.Visible = false
			popup.Size = STORE_NORMAL_SIZE
			popup.Rotation = 0
			popup.BackgroundTransparency = STORE_NORMAL_TRANSPARENCY
			forceManagerScaleNeutral()
			storeAnimating = false
		end)
	end)
end

GuiManager:SetBackHandler("Store", function()
	if giftPopupCloser and giftPopupCloser() then return end
	closeStoreCollapsed()
end)

-- ===================== TOAST =====================
local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -18)
toast.Size = UDim2.new(0.86, 0, 0, 54)
toast.BackgroundColor3 = Color3.fromRGB(8, 10, 22)
toast.BackgroundTransparency = 0.08
toast.Text = ""
toast.Font = FONT
toast.TextScaled = true
toast.TextColor3 = COL.Light
toast.TextTransparency = 1
toast.Visible = false
toast.ZIndex = 90
toast.Parent = popup
GuiStyle.Corner(toast, 0.22)
GuiStyle.Stroke(toast, COL.Outline, 3)
GuiStyle.TextStroke(toast, 2)

local toastConstraint = Instance.new("UITextSizeConstraint")
toastConstraint.MinTextSize = 16
toastConstraint.MaxTextSize = 32
toastConstraint.Parent = toast

local toastToken = 0

local function showToast(message, color)
	toastToken += 1
	local token = toastToken

	toast.Text = tostring(message or "")
	toast.TextColor3 = color or COL.Light
	toast.Visible = true
	toast.TextTransparency = 1

	TweenService:Create(toast, TweenInfo.new(0.15), { TextTransparency = 0 }):Play()

	task.delay(1.6, function()
		if toastToken ~= token then return end
		local fade = TweenService:Create(toast, TweenInfo.new(0.25), { TextTransparency = 1 })
		fade:Play()
		fade.Completed:Connect(function()
			if toastToken == token then
				toast.Visible = false
			end
		end)
	end)
end

-- ===================== HEADER =====================
local headerHeight = math.floor(TUNE.DesignHeight * TUNE.HeaderHeight)   -- same header on every screen

local header = frame(content, {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, headerHeight),
	Radius = 27,
	Gradient = { C.HeaderTop, C.HeaderBottom },
	ZIndex = 20,
})
frame(header, {   -- squares off the bottom edge against the body
	Name = "Skirt", Position = UDim2.new(0, 0, 1, -27), Size = UDim2.new(1, 0, 0, 27),
	Color = C.HeaderBottom, ZIndex = 20,
})
gloss(header, 16, 0.32, 0.84)

-- A divider with real weight, not a hairline.
frame(header, {
	Name = "Divider", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 7), Color = C.EdgeCyan, Transparency = 0.12, ZIndex = 22,
})
frame(header, {
	Name = "DividerGlow", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -7),
	Size = UDim2.new(1, 0, 0, 10), Color = C.EdgeCyan, Transparency = 0.8, ZIndex = 21,
})

-- Header decoration: a planet on the right and a few sparkles around the
-- branding. Above the header fill, below every button and every word.
do
	-- A thin star field across the band.
	local dust = {
		{ 0.42, 0.22 }, { 0.5, 0.72 }, { 0.58, 0.3 },
		{ 0.72, 0.74 }, { 0.8, 0.26 }, { 0.88, 0.62 },
	}
	for index, spot in ipairs(dust) do
		frame(header, {
			Name = "HeaderDust" .. index, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spot[1], spot[2]),
			Size = UDim2.fromOffset(if index % 3 == 0 then 5 else 3, if index % 3 == 0 then 5 else 3),
			Round = true, Color = if index % 2 == 0 then Color3.fromRGB(160, 235, 255) else Color3.new(1, 1, 1),
			Transparency = 0.25, ZIndex = 21,
		})
	end

	-- The planet keeps its own pocket of space between the logo and the
	-- buttons: no cloud, no sparkle cluster, nothing else in that area.
	image(header, {
		Name = "HeaderPlanet", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.705, 0.46),
		Size = UDim2.fromOffset(175, 175), Alpha = 0.34, ZIndex = 21, Image = UIAssets.Planet,
	})
	-- Four, each in clear space: two near the branding, two in the gap
	-- between the planet and the buttons.
	local sparkles = {
		{ 0.29, 0.12, 38, UIAssets.StarVariant2 },
		{ 0.47, 0.76, 28, UIAssets.CyanStar },
		{ 0.54, 0.18, 26, UIAssets.StarVariant1 },
		{ 0.76, 0.2, 24, UIAssets.CyanStar },
	}
	for _, spot in ipairs(sparkles) do
		image(header, {
			Name = "HeaderSparkle", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spot[1], spot[2]), Size = UDim2.fromOffset(spot[3], spot[3]),
			Alpha = 0.35, ZIndex = 21, Image = spot[4],
		})
	end
end

-- Cart and logo are one branded group: the cart overhangs the header band
-- like a sticker, and the logo starts inside the cart's own padding so the
-- two read as a single lockup instead of two separate icons.
--
-- A tight aura behind an icon: one soft shape, no silhouette. Repeating the
-- artwork itself was what made the header look foggy - a second copy of the
-- picture doubles every edge instead of lighting it.
local function neon(parent, _id, position, size, anchor, tint, zIndex)
	local pad = math.max(size.X, size.Y) * 0.16
	-- Grows the aura symmetrically whatever the anchor is.
	local dx = (anchor.X - 0.5) * pad
	local dy = (anchor.Y - 0.5) * pad
	local halo = frame(parent, {
		Name = "Glow", AnchorPoint = anchor,
		Position = position + UDim2.fromOffset(dx, dy),
		Size = UDim2.fromOffset(size.X + pad, size.Y + pad),
		Color = tint, Transparency = 0.86, Round = true, ZIndex = zIndex,
	})
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.35, 0.5),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.65, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = halo
end
-- The cart, drawn on the spill layer rather than in the header.
--
-- Where it used to sit, in window coordinates: the content frame is inset 13,
-- the header starts at its top, and the cart sat at (ShopLeft, 6) inside that.
-- So 13 + 26 = 39 across and 13 + 6 = 19 down. Pulling it back by
-- ShopSpillLeft/Up from there is what pushes it over the corner, and the extra
-- ShopSpillScale keeps the drawn cart centred on the slot it came from.
local SHOP_DRAWN = math.floor(TUNE.ShopIcon * TUNE.ShopSpillScale)
local SHOP_RECENTRE = math.floor((SHOP_DRAWN - TUNE.ShopIcon) / 2)
local SHOP_X = 13 + TUNE.ShopLeft - TUNE.ShopSpillLeft - SHOP_RECENTRE
local SHOP_Y = 13 + 6 - TUNE.ShopSpillUp - SHOP_RECENTRE

neon(spillLayer, UIAssets.Shop, UDim2.fromOffset(SHOP_X, SHOP_Y),
	Vector2.new(SHOP_DRAWN, SHOP_DRAWN), Vector2.new(0, 0), Color3.fromRGB(255, 226, 120), 62)

local shopIcon = image(spillLayer, {
	Name = "ShopIcon", Position = UDim2.fromOffset(SHOP_X, SHOP_Y),
	Size = UDim2.fromOffset(SHOP_DRAWN, SHOP_DRAWN), ZIndex = 63, Image = UIAssets.Shop,
})

-- Overlapping the cart's own padding is what makes them read as one lockup.
local TITLE_WIDTH = math.floor(TUNE.TitleHeight * TUNE.TitleAspect)
local TITLE_LEFT = TUNE.TitleLeft

neon(header, UIAssets.SecretStore, UDim2.fromOffset(TITLE_LEFT, TUNE.TitleTop - 4),
	Vector2.new(TITLE_WIDTH, TUNE.TitleHeight), Vector2.new(0, 0), Color3.fromRGB(120, 210, 255), 22)

local titleArt = image(header, {
	Name = "SecretStoreTitle", Position = UDim2.fromOffset(TITLE_LEFT, TUNE.TitleTop),
	Size = UDim2.fromOffset(TITLE_WIDTH, TUNE.TitleHeight), ZIndex = 23, Image = UIAssets.SecretStore,
})
-- The logo already reads "Secret Store"; this keeps the name in the hierarchy.
local titleLabel = text(header, {
	Name = "Title", Position = titleArt.Position, Size = titleArt.Size,
	Text = "Secret Store", AlignX = Enum.TextXAlignment.Left, Visible = false, ZIndex = 23,
})

local subtitle = text(header, {
	Name = "Subtitle",
	-- Clear of the cart, which hangs below the band on the left.
	Position = UDim2.fromOffset(TUNE.TitleLeft + 150, TUNE.SubtitleTop),
	Size = UDim2.fromOffset(620, TUNE.SubtitleHeight),
	Text = "Get exclusive perks to progress faster!", AlignX = Enum.TextXAlignment.Left,
	Color = Color3.fromRGB(216, 248, 255), Max = 32, Min = 14, StrokeThickness = 3, ZIndex = 23,
})

neon(header, UIAssets.Gift, UDim2.new(1, -(TUNE.HeaderGapRight + TUNE.CloseSize + 30), 0.5, 0),
	Vector2.new(TUNE.GiftSize, TUNE.GiftSize), Vector2.new(1, 0.5), Color3.fromRGB(150, 205, 255), 24)

local giftButton = imageButton(header, {
	Name = "GiftButton", AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -(TUNE.HeaderGapRight + TUNE.CloseSize + 30), 0.5, 0),
	Size = UDim2.fromOffset(TUNE.GiftSize, TUNE.GiftSize), ZIndex = 26, Image = UIAssets.Gift,
	Hover = 1.03, Press = 0.97,
})

local closeButton = imageButton(header, {
	Name = "CloseButton", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -TUNE.HeaderGapRight, 0.5, 0),
	Size = UDim2.fromOffset(TUNE.CloseSize, TUNE.CloseSize), ZIndex = 26, Image = UIAssets.Close,
	Hover = 1.04, Press = 0.97,
})
closeButton.Activated:Connect(function()
	closeStoreCollapsed()
end)

-- ===================== BODY =====================
local body = frame(content, {
	Name = "Body", Position = UDim2.fromOffset(0, headerHeight), Size = UDim2.new(1, 0, 1, -headerHeight),
	Transparency = 1, ZIndex = 14,
})

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Scroll"
scroll.Position = UDim2.fromOffset(TUNE.BodySideMargin, TUNE.BodyPadTop)
scroll.Size = UDim2.new(1, -TUNE.BodySideMargin * 2, 1, -(TUNE.BodyPadTop + TUNE.BodyPadBottom))
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = Color3.fromRGB(150, 240, 255)
scroll.ScrollBarImageTransparency = 0.55
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.fromOffset(0, 0)
scroll.ZIndex = 15
scroll.Parent = body
if UiResponsive and UiResponsive.TouchScroll then UiResponsive.TouchScroll(scroll) end   -- easy thumb scrolling

local scrollLayout = Instance.new("UIListLayout")
scrollLayout.Padding = UDim.new(0, 34)
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
scrollLayout.Parent = scroll

local scrollPad = Instance.new("UIPadding")
scrollPad.PaddingTop = UDim.new(0, 4)
scrollPad.PaddingBottom = UDim.new(0, 26)
scrollPad.Parent = scroll

-- The bar only exists when there is something below the fold.
local function refreshScrollBar()
	local canvas = scrollLayout.AbsoluteContentSize.Y + 30
	local view = scroll.AbsoluteSize.Y
	-- Desktop shows the five cards without a bar; small screens keep one.
	local needed = canvas > view + 4
	scroll.ScrollBarThickness = if needed and view < 520 then 4 else 0
end
scrollLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshScrollBar)
scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshScrollBar)

-- ===================== PURCHASE PLACEHOLDER =====================
-- Unchanged: StoreConfig ids are still 0, so this only reports what is missing.
local function purchaseStub(item, purchaseType)
	if purchaseType == "Gamepass" then
		print("[StoreStub] Gamepass:", item.Key, "GamepassId:", item.GamepassId, "Effect:", item.OwnedEffect)
		showToast("Placeholder: add Gamepass ID for " .. displayTitle(item.Title), COL.Yellow)

	elseif purchaseType == "Product" then
		print("[StoreStub] Product:", item.Key, "ProductId:", item.ProductId, "Amount:", item.Amount)
		showToast("Placeholder: add Product ID for " .. displayTitle(item.Title), COL.Yellow)
	end
end

-- ===================== THE CARD TEMPLATE =====================
-- One structure, five products. Everything is a share of the card, so a card
-- is correct at any size:
--   title strip -> artwork -> description -> green purchase footer
local function makeCard(parent, item, purchaseType)
	local card = frame(parent, { Name = item.Key .. "Card", Transparency = 1, ZIndex = 16 })

	-- Depth, outside in: two soft shadows, a dark navy silhouette, then one
	-- thin cyan rim light. The shadow does the lifting so the cyan can stay
	-- thin instead of reading as a box drawn around the card.
	-- A wide cyan halo behind the card, then the shadow, then the silhouette.
	-- The halo is what turns an outlined rectangle into a glowing card, so the
	-- solid cyan line itself can stay thin.
	frame(card, {
		Name = "CardGlow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 16, 1, 16), Color = C.CardRim, Transparency = 0.9, Radius = 52, ZIndex = 15,
	})
	frame(card, {
		Name = "CardShadowSoft", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 26),
		Size = UDim2.new(1, 30, 1, -8), Color = C.Shadow, Transparency = 0.54, Radius = 54, ZIndex = 15,
	})
	frame(card, {
		Name = "CardShadow", Position = UDim2.fromOffset(4, 16), Color = C.Shadow,
		Transparency = 0.24, Radius = 48, ZIndex = 16,
	})
	local shell = frame(card, { Name = "Shell", Radius = 48, Color = C.CardEdge, ZIndex = 17 })
	local rim = stroke(shell, C.CardRim, 2)

	local inner = frame(shell, {
		Name = "Body", Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12),
		Radius = 43, ZIndex = 18, Clip = true,
		Gradient = { ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.CardTop),
			ColorSequenceKeypoint.new(0.42, C.CardMid),
			ColorSequenceKeypoint.new(1, C.CardBottom),
		}) },
	})

	-- Long names get a taller two-line strip; the artwork gives back the room.
	local longTitle = #tostring(item.Title) > TUNE.LongTitleChars
	local extra = if longTitle then TUNE.LongStripExtra else 0
	local stripHeight = TUNE.StripHeight + extra
	local artTop = TUNE.ArtTop + extra
	local artHeight = TUNE.ArtHeight - extra

	-- A soft round glow behind the artwork. No rectangle: the picture should
	-- look like it is floating in the card, not pasted onto a panel.
	do
		local tint = (ART_CROP[item.Key] and ART_CROP[item.Key].Tint) or C.CardGlow
		local halo = frame(inner, {
			Name = "ArtGlow", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, artTop + artHeight * 0.5),
			Size = UDim2.fromScale(0.66, artHeight * 1.04), Round = true,
			Color = tint, Transparency = 0.8, ZIndex = 18,
		})
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.45),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.7, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = halo
	end

	-- A handful of tiny sparks, so the card interior reads as cosmic too.
	for index, spot in ipairs({ { 0.12, 0.34, 4 }, { 0.88, 0.3, 4 }, { 0.2, 0.56, 3 }, { 0.82, 0.58, 3 } }) do
		frame(inner, {
			Name = "CardDust" .. index, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spot[1], spot[2]), Size = UDim2.fromOffset(spot[3], spot[3]),
			Round = true, Color = Color3.fromRGB(226, 240, 255), Transparency = 0.4, ZIndex = 19,
		})
	end

	-- Title strip: full width, flush with the top of the card, rounded to match
	-- the card's own corners and squared off along the bottom.
	local strip = frame(inner, {
		Name = "TitleStrip", Position = UDim2.fromScale(0, TUNE.StripTop),
		Size = UDim2.fromScale(1, stripHeight), Radius = 43, ZIndex = 19,
		Gradient = { ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.StripTop),
			ColorSequenceKeypoint.new(0.52, C.StripMid),
			ColorSequenceKeypoint.new(1, C.StripBottom),
		}) },
	})
	frame(strip, {   -- squares the bottom corners and gives the lip its weight
		Name = "StripBase", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0.34, 0), Color = C.StripBottom, ZIndex = 19,
	})
	frame(strip, {
		Name = "StripEdge", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 4), Color = C.StripEdge, Transparency = 0.45, ZIndex = 20,
	})
	gloss(strip, 10, 0.4, 0.55)
	text(strip, {
		Name = "Title", Position = UDim2.fromScale(0.05, 0.1), Size = UDim2.fromScale(0.9, 0.74),
		Text = displayTitle(item.Title), Color = C.Cream, Wrap = true, Max = 44, Min = 14,
		StrokeColor = Color3.fromRGB(78, 10, 74), StrokeThickness = 3.5, ZIndex = 22,
	})

	-- Artwork. Cropped perks show illustration only; anything without a crop
	-- entry (the Stardust icon) is simply fitted.
	local crop = ART_CROP[item.Key]
	local artSlot = frame(inner, {
		Name = "ArtworkSlot", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, artTop),
		Size = UDim2.fromScale(0.96, artHeight), Transparency = 1, ZIndex = 20,
	})
	local artImage = (UIAssets.CardArt and UIAssets.CardArt[item.Key]) or UIAssets.Stardust

	if crop then
		-- 8% safe padding, so the artwork's own glow never touches the window
		-- edge, and a per-perk nudge for optical centring.
		local viewport = frame(artSlot, {
			Name = "ArtworkViewport", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5 + (crop.Nudge or 0)),
			Size = UDim2.fromScale(0.92, 0.92), Transparency = 1, Clip = true, ZIndex = 20,
		})
		-- The window is exactly the shape of the part we keep, so the picture
		-- fills it edge to edge instead of being letterboxed.
		local shape = Instance.new("UIAspectRatioConstraint")
		shape.DominantAxis = Enum.DominantAxis.Height
		shape.Parent = viewport

		local picture = image(viewport, {
			Name = "Artwork", AnchorPoint = Vector2.new(0.5, 0), ZIndex = 20, Image = artImage,
		})

		local function applyCrop()
			viewport.Position = UDim2.fromScale(0.5, 0.5 + (crop.Nudge or 0))
			local top = crop.Top or 0
			local keep = math.clamp(1 - crop.Crop - top, 0.15, 1)   -- share of the file shown
			shape.AspectRatio = crop.Aspect / keep
			picture.Position = UDim2.fromScale(0.5, -top / keep)
			picture.Size = UDim2.fromScale(1, 1 / keep)
		end

		applyCrop()
		table.insert(CROPPED, { key = item.Key, spec = crop, apply = applyCrop, image = artImage })
	else
		image(artSlot, {
			Name = "Artwork", Size = UDim2.fromScale(1, 1), ZIndex = 20, Image = artImage,
		})
	end

	-- Description: two lines, centred, with room above and below it.
	text(inner, {
		Name = "Description", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, TUNE.DescTop),
		Size = UDim2.fromScale(0.84, TUNE.DescHeight), Text = item.Description or "",
		Color = Color3.fromRGB(244, 252, 255), Wrap = true, Max = 34, Min = 14,
		StrokeThickness = 3.5, ZIndex = 22,
	})

	-- Purchase footer: the whole green bar is the button, and the price is the
	-- call to action. BUY is a small line above it, never the main label.
	local footer = Instance.new("TextButton")
	footer.Name = "PurchaseFooter"
	footer.AnchorPoint = Vector2.new(0.5, 1)
	footer.Position = UDim2.fromScale(0.5, TUNE.FooterBottom)
	footer.Size = UDim2.fromScale(0.94, TUNE.FooterHeight)
	footer.BackgroundTransparency = 1
	footer.AutoButtonColor = false
	footer.Text = ""
	footer.ZIndex = 24
	footer.Parent = inner

	frame(footer, { Name = "Shadow", Position = UDim2.fromOffset(0, 11), Color = C.Shadow, Transparency = 0.3, Radius = 26, ZIndex = 24 })
	frame(footer, { Name = "Extrusion", Position = UDim2.fromOffset(0, 7), Color = C.GreenEdge, Radius = 26, ZIndex = 25 })
	local face = frame(footer, {
		Name = "Face", Radius = 26, ZIndex = 26, Stroke = { C.GreenEdge, 3.5 },
		Gradient = { ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.GreenTop),
			ColorSequenceKeypoint.new(0.5, C.GreenMid),
			ColorSequenceKeypoint.new(1, C.GreenBottom),
		}) },
	})
	gloss(face, 8, 0.44, 0.45)
	frame(face, {   -- bright lip along the top, dark lip along the bottom
		Name = "TopLip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5),
		Size = UDim2.new(1, -18, 0, 5), Color = Color3.fromRGB(226, 255, 190), Transparency = 0.35,
		Round = true, ZIndex = 28,
	})
	frame(face, {
		Name = "BottomLip", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -20, 0, 4), Color = C.GreenEdge, Transparency = 0.45,
		Round = true, ZIndex = 28,
	})

	local buyLabel = text(face, {
		Name = "Buy", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.06),
		Size = UDim2.fromScale(0.8, 0.2), Text = "BUY", Color = Color3.fromRGB(226, 255, 216),
		Max = 22, Min = 10, StrokeColor = C.GreenEdge, StrokeThickness = 2.5, ZIndex = 30,
	})
	local priceLabel = text(face, {
		Name = "Price", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.96),
		Size = UDim2.fromScale(0.94, 0.72), Text = ("R$  %s"):format(tostring(item.Price or 0)),
		Color = C.Cream, Max = 84, Min = 18, StrokeColor = Color3.fromRGB(8, 64, 32),
		StrokeThickness = 4.5, ZIndex = 30,
	})

	hoverScale(footer, 1.02, 0.975)
	footer.Activated:Connect(function()
		purchaseStub(item, purchaseType)
	end)

	-- Owned: the purchase call to action goes away. Only ever runs once a real
	-- game pass id exists in StoreConfig; with id 0 nothing is asked.
	local function showOwned()
		buyLabel.Visible = false
		priceLabel.Position = UDim2.fromScale(0.5, 0.88)
		priceLabel.Size = UDim2.fromScale(0.9, 0.66)
		priceLabel.Text = "✓ OWNED"
		face:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(C.OwnedTop, C.OwnedBottom)
		local edge = face:FindFirstChildOfClass("UIStroke")
		if edge then edge.Color = C.OwnedEdge end
		footer.Active = false
		footer.AutoButtonColor = false
	end

	if purchaseType == "Gamepass" and type(item.GamepassId) == "number" and item.GamepassId > 0 then
		task.spawn(function()
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, item.GamepassId)
			end)
			if ok and owns then
				showOwned()
			end
		end)
	end

	-- Hover: the card lifts and its rim brightens. Nothing loops.
	local lift = Instance.new("UIScale")
	lift.Parent = card
	local hoverTweens = {}
	local function hover(on)
		for _, tween in ipairs(hoverTweens) do tween:Cancel() end
		table.clear(hoverTweens)
		local reduced = player:GetAttribute("ReduceMotion") == true
		local info = TweenInfo.new(if reduced then 0 else 0.14, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		local a = TweenService:Create(lift, info, { Scale = if on and not reduced then 1.02 else 1 })
		local b = TweenService:Create(shell, info, { Position = UDim2.fromOffset(0, if on and not reduced then -3 else 0) })
		local c = TweenService:Create(rim, info, { Color = if on then C.CardRimHover else C.CardRim })
		hoverTweens = { a, b, c }
		a:Play() b:Play() c:Play()
	end
	card.MouseEnter:Connect(function() hover(true) end)
	card.MouseLeave:Connect(function() hover(false) end)

	return card
end

-- ===================== SECTION =====================
local function makeSection(titleText, items, purchaseType, order)
	local section = frame(scroll, {
		Name = titleText:gsub("%s+", "") .. "Section", Size = UDim2.new(1, -8, 0, 140),
		Transparency = 1, ZIndex = 15, Order = order,
	})

	-- Banner: a pill, not a floating label.
	local banner = frame(section, {
		Name = "SectionBanner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(TUNE.BannerWidth, 0, 0, TUNE.BannerHeight), Radius = 32, ZIndex = 17,
		Gradient = { C.BannerTop, C.BannerBottom }, Stroke = { C.EdgeCyan, 3, 0.05 },
	})
	frame(section, {   -- soft glow, so the pill sits in light instead of on flat blue
		Name = "BannerGlow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -10),
		Size = UDim2.new(TUNE.BannerWidth + 0.04, 0, 0, TUNE.BannerHeight + 14), Color = C.EdgeCyan,
		Transparency = 0.91, Radius = 40, ZIndex = 15,
	})
	frame(banner, { Name = "BannerShadow", Position = UDim2.fromOffset(0, 9), Color = C.Shadow, Transparency = 0.42, Radius = 36, ZIndex = 16 })
	gloss(banner, 10, 0.46, 0.76)
	text(banner, {
		Name = "BannerTitle", Position = UDim2.fromScale(0.12, 0.1), Size = UDim2.fromScale(0.76, 0.8),
		Text = titleText, Color = Color3.fromRGB(250, 244, 255), Max = 48, Min = 16,
		StrokeColor = Color3.fromRGB(22, 14, 84), StrokeThickness = 4, ZIndex = 19,
	})
	for _, side in ipairs({ 0, 1 }) do
		image(banner, {
			Name = "BannerStar", AnchorPoint = Vector2.new(side, 0.5),
			Position = UDim2.new(side, (if side == 0 then 10 else -10), 0.5, 0),
			Size = UDim2.fromOffset(TUNE.BannerStar, TUNE.BannerStar), ZIndex = 19,
			Image = if side == 0 then UIAssets.StarVariant1 else UIAssets.StarVariant2,
		})
		-- A sparkle out in the empty band beside the pill.
		image(section, {
			Name = "BannerSparkle", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(if side == 0 then 0.13 else 0.87, 0, 0, TUNE.BannerHeight * 0.5),
			Size = UDim2.fromOffset(46, 46), Alpha = 0.35, ZIndex = 15,
			Image = if side == 0 then UIAssets.CyanStar else UIAssets.StarVariant1,
		})
	end

	local holder = frame(section, {
		Name = "Cards", Position = UDim2.fromOffset(0, TUNE.BannerHeight + TUNE.BannerGapBelow),
		Size = UDim2.new(1, 0, 0, 100), Transparency = 1, ZIndex = 15,
	})

	local cards = {}
	for _, item in ipairs(items) do
		table.insert(cards, makeCard(holder, item, purchaseType))
	end

	local lastWidth
	local function layout()
		if popup.Size.X.Offset < 300 then return end   -- mid collapse animation
		local width = holder.AbsoluteSize.X
		if width < 10 then return end
		local scaleNow = math.max(responsiveScale.Scale, 0.05)
		width /= scaleNow                                    -- design pixels
		if math.abs(width - (lastWidth or -1e6)) < 0.5 then return end
		lastWidth = width

		local gap = TUNE.CardGap
		-- Phones: two bigger, readable cards per row (the list scrolls).
		local phone = UiResponsive ~= nil and UiResponsive.Layout ~= nil and UiResponsive.Layout() == "compact"
		local columns = math.clamp(if phone then 2 else TUNE.CardsPerRow, 1, #cards)
		local cardWidth = (width - (columns - 1) * gap) / columns
		local cardHeight = math.floor(cardWidth / TUNE.CardRatio)
		local rows = math.ceil(#cards / columns)

		local lastRow = rows - 1
		local shortLast = (#cards - lastRow * columns) < columns
		local bigger = if shortLast then TUNE.LastRowScale else 1

		for index, card in ipairs(cards) do
			local row = math.floor((index - 1) / columns)
			local column = (index - 1) % columns
			local inRow = math.min(columns, #cards - row * columns)
			local grow = if row == lastRow then bigger else 1
			local w, h = cardWidth * grow, cardHeight * grow
			-- Every row centres itself, so the short second row sits centred
			-- under the first.
			local left = (width - (inRow * w + (inRow - 1) * gap)) / 2
			card.Position = UDim2.fromOffset(left + column * (w + gap), row * (cardHeight + TUNE.CardRowGap))
			card.Size = UDim2.fromOffset(w, h)
		end

		local height = lastRow * (cardHeight + TUNE.CardRowGap) + cardHeight * bigger
		holder.Size = UDim2.new(1, 0, 0, height)
		section.Size = UDim2.new(1, -8, 0, TUNE.BannerHeight + TUNE.BannerGapBelow + height)

	end

	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	popup:GetPropertyChangedSignal("Size"):Connect(layout)
	task.defer(layout)
end

-- ===================== CODES =====================
-- Its own feature, not a form: banner, wide panel, big input with an icon,
-- chunky button, and decoration framing it. The TextBox and the redeem call
-- are the same ones as before.
local function makeCodesSection()
	local PANEL_H = 430
	local section = frame(scroll, {
		Name = "CodesSection", -- No cloud bank hanging below it any more, so the section ends with the panel.
		Size = UDim2.new(1, -8, 0, TUNE.BannerHeight + TUNE.BannerGapBelow + PANEL_H + 14),
		Transparency = 1, ZIndex = 15, Order = 9,
	})

	-- Banner, matching the GAMEPASSES one but a touch wider.
	frame(section, {
		Name = "CodesBannerGlow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -10),
		Size = UDim2.new(0.42, 0, 0, TUNE.BannerHeight + 14), Color = C.EdgeCyan,
		Transparency = 0.9, Radius = 40, ZIndex = 15,
	})
	local banner = frame(section, {
		Name = "CodesBanner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0.38, 0, 0, TUNE.BannerHeight), Radius = 34, ZIndex = 17,
		Gradient = { C.BannerTop, C.BannerBottom }, Stroke = { C.EdgeCyan, 3, 0.05 },
	})
	frame(banner, { Name = "BannerShadow", Position = UDim2.fromOffset(0, 9), Color = C.Shadow, Transparency = 0.42, Radius = 34, ZIndex = 16 })
	gloss(banner, 10, 0.46, 0.76)
	text(banner, {
		Name = "CodesTitle", Position = UDim2.fromScale(0.16, 0.1), Size = UDim2.fromScale(0.68, 0.8),
		Text = "CODES", Color = Color3.fromRGB(250, 244, 255), Max = 48, Min = 16,
		StrokeColor = Color3.fromRGB(22, 14, 84), StrokeThickness = 4, ZIndex = 19,
	})
	for _, side in ipairs({ 0, 1 }) do
		image(banner, {
			Name = "BannerStar", AnchorPoint = Vector2.new(side, 0.5),
			Position = UDim2.new(side, (if side == 0 then 12 else -12), 0.5, 0),
			Size = UDim2.fromOffset(TUNE.BannerStar, TUNE.BannerStar), ZIndex = 19,
			Image = if side == 0 then UIAssets.StarVariant1 else UIAssets.StarVariant2,
		})
	end

	local top = TUNE.BannerHeight + TUNE.BannerGapBelow + 6

	-- No decoration around this panel: the clouds, stars and planet that used
	-- to frame it were the source of the overlapping.

	-- ---------- the panel ----------
	frame(section, {
		Name = "PanelGlow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, top - 12),
		Size = UDim2.new(0.74, 0, 0, PANEL_H + 16), Color = C.EdgeCyan, Transparency = 0.91,
		Radius = 46, ZIndex = 16,
	})
	frame(section, {
		Name = "PanelShadow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, top + 14),
		Size = UDim2.new(0.72, 0, 0, PANEL_H), Color = C.Shadow, Transparency = 0.34,
		Radius = 40, ZIndex = 16,
	})
	local shell = frame(section, {
		Name = "CodesPanel", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, top),
		Size = UDim2.new(0.72, 0, 0, PANEL_H), Radius = 40, Color = C.CardEdge, ZIndex = 17,
	})
	stroke(shell, C.CardRim, 2.5)

	local panel = frame(shell, {
		Name = "Body", Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12),
		Radius = 35, ZIndex = 18,
		Gradient = { ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 62, 176)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(26, 44, 142)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 24, 96)),
		}) },
	})
	frame(panel, {
		Name = "TopHighlight", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, -18, 0.34, 0), Color = Color3.fromRGB(150, 190, 255), Transparency = 0.88,
		Radius = 30, ZIndex = 18,
	})

	text(panel, {
		Name = "RedeemTitle", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 26),
		Size = UDim2.new(0.9, 0, 0, 62), Text = "Redeem Codes!", Color = Color3.fromRGB(232, 248, 255),
		Max = 54, Min = 20, StrokeColor = Color3.fromRGB(12, 40, 110), StrokeThickness = 4, ZIndex = 20,
	})
	text(panel, {
		Name = "RedeemSubtitle", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 94),
		Size = UDim2.new(0.86, 0, 0, 32), Text = "Follow us on our socials for exclusive codes!",
		Color = Color3.fromRGB(168, 198, 240), Max = 26, Min = 13, StrokeThickness = 2.5, ZIndex = 20,
	})

	-- ---------- input ----------
	frame(panel, {
		Name = "InputGlow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 142),
		Size = UDim2.new(0.83, 0, 0, 90), Color = C.EdgeCyan, Transparency = 0.9, Round = true, ZIndex = 19,
	})
	local inputWrap = frame(panel, {
		Name = "InputField", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.new(0.82, 0, 0, 80), Round = true, Color = Color3.fromRGB(8, 14, 44),
		Stroke = { C.EdgeCyan, 3 }, ZIndex = 20,
	})
	frame(inputWrap, {
		Name = "InnerEdge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -10, 1, -10), Transparency = 1, Round = true,
		Stroke = { Color3.fromRGB(70, 130, 220), 1.5, 0.4 }, ZIndex = 20,
	})

	-- Its own icon, shown as drawn: the Gift artwork was never meant for this
	-- size and brings its own lettering with it. The id lives in UIAssets when
	-- it is there, and here when it is not, so the field never falls back to
	-- the gift by accident.
	local iconWindow = frame(inputWrap, {
		Name = "CodeIcon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 20, 0.5, 0),
		Size = UDim2.fromOffset(60, 60), Transparency = 1, Clip = true, ZIndex = 22,
	})
	local codeIcon = image(iconWindow, {
		Name = "Art", Size = UDim2.fromScale(1, 1), ZIndex = 22,
		Image = UIAssets.CodeIcon or "rbxassetid://93617937032122",
	})

	-- The stand-in is a separate label that is simply hidden, rather than the
	-- real icon having its Image overwritten. That way a late-arriving icon
	-- can still take over, and the swap is reversible.
	local standInWindow = frame(inputWrap, {
		Name = "CodeIconStandIn", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 20, 0.5, 0),
		Size = UDim2.fromOffset(60, 60), Transparency = 1, Clip = true, ZIndex = 21,
	})
	standInWindow.Visible = false
	do
		local KEEP = 0.68   -- share of the Gift file shown: its lettering is below this
		local shape = Instance.new("UIAspectRatioConstraint")
		shape.AspectRatio = 0.95 / KEEP
		shape.DominantAxis = Enum.DominantAxis.Height
		shape.Parent = standInWindow
		image(standInWindow, {
			Name = "Art", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(1, 1 / KEEP), ZIndex = 21, Image = UIAssets.Gift or "",
		})
	end

	local iconDivider = frame(inputWrap, {
		Name = "IconDivider", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 84, 0.5, 0),
		Size = UDim2.fromOffset(2, 40), Color = Color3.fromRGB(86, 122, 190), Transparency = 0.3, ZIndex = 21,
	})

	local box = Instance.new("TextBox")
	box.Name = "CodeBox"
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.Position = UDim2.new(0, 100, 0.5, 0)
	box.Size = UDim2.new(1, -124, 0, 52)
	box.BackgroundTransparency = 1
	box.PlaceholderText = "Type code here..."
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Font = FONT
	box.TextScaled = true
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextColor3 = Color3.fromRGB(245, 250, 255)
	box.PlaceholderColor3 = Color3.fromRGB(130, 156, 200)
	box.ZIndex = 22
	box.Parent = inputWrap
	GuiStyle.TextStroke(box, 2)

	local boxConstraint = Instance.new("UITextSizeConstraint")
	boxConstraint.MinTextSize = 16
	boxConstraint.MaxTextSize = 34
	boxConstraint.Parent = box

	-- This is why the field showed the wrong present. The old code took a
	-- ONE-SHOT verdict and did `iconWindow.Visible = loaded`, so a single early
	-- "not loaded" answer hid the real code icon permanently and left the
	-- cropped Gift stand-in on screen for the rest of the session - even though
	-- the correct id had arrived moments later.
	--
	-- The real icon is now never hidden. It draws nothing until it arrives, the
	-- stand-in sits behind it at a lower ZIndex until then, and the STAND-IN is
	-- what gets switched off once the picture is confirmed.
	iconWindow.Visible = true
	standInWindow.Visible = true
	watchImage(codeIcon, function(loaded)
		if loaded then
			standInWindow.Visible = false
		else
			warn(("[StoreClient] code field icon %s has not arrived; gift stand-in kept."):format(
				codeIcon.Image))
		end
	end)

	-- ---------- status line, only there when there is something to say ----------
	local status = text(panel, {
		Name = "Status", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 240),
		Size = UDim2.new(0.86, 0, 0, 30), Text = "", Color = Color3.fromRGB(150, 255, 200),
		Max = 26, Min = 12, StrokeThickness = 2.5, ZIndex = 20, Visible = false,
	})

	local statusToken = 0
	local function say(message, colour)
		statusToken += 1
		local token = statusToken
		status.Text = message
		status.TextColor3 = colour
		status.Visible = true
		task.delay(4, function()
			if statusToken == token then
				status.Visible = false
			end
		end)
	end

	-- ---------- redeem ----------
	local redeem = Instance.new("TextButton")
	redeem.Name = "RedeemButton"
	redeem.AnchorPoint = Vector2.new(0.5, 0)
	redeem.Position = UDim2.new(0.5, 0, 0, 286)
	redeem.Size = UDim2.new(0.5, 0, 0, 98)
	redeem.BackgroundTransparency = 1
	redeem.AutoButtonColor = false
	redeem.Text = ""
	redeem.ZIndex = 21
	redeem.Parent = panel

	frame(redeem, { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 14, 1, 14), Color = C.GreenMid, Transparency = 0.9, Radius = 32, ZIndex = 20 })
	frame(redeem, { Name = "Shadow", Position = UDim2.fromOffset(0, 12), Color = C.Shadow, Transparency = 0.3, Radius = 28, ZIndex = 21 })
	frame(redeem, { Name = "Extrusion", Position = UDim2.fromOffset(0, 8), Color = C.GreenEdge, Radius = 28, ZIndex = 22 })
	local redeemFace = frame(redeem, {
		Name = "Face", Radius = 28, ZIndex = 23, Stroke = { C.GreenEdge, 3.5 },
		Gradient = { ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.GreenTop),
			ColorSequenceKeypoint.new(0.5, C.GreenMid),
			ColorSequenceKeypoint.new(1, C.GreenBottom),
		}) },
	})
	gloss(redeemFace, 9, 0.44, 0.45)
	frame(redeemFace, {
		Name = "TopLip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, -22, 0, 5), Color = Color3.fromRGB(226, 255, 190), Transparency = 0.35,
		Round = true, ZIndex = 25,
	})
	text(redeemFace, {
		Name = "RedeemText", Size = UDim2.fromScale(1, 0.62), Position = UDim2.fromScale(0, 0.17),
		Text = "REDEEM", Color = C.Cream, Max = 46, Min = 16, StrokeColor = Color3.fromRGB(8, 64, 32),
		StrokeThickness = 3.5, ZIndex = 27,
	})
	hoverScale(redeem, 1.02, 0.975)

	-- Unchanged: the same remote, the same reward animation.
	local busy = false
	local function submit()
		if busy then return end
		if box.Text == "" then
			say("Type a code first.", Color3.fromRGB(255, 214, 120))
			return
		end

		busy = true
		local ok, result = pcall(function()
			return redeemRemote:InvokeServer(box.Text)
		end)
		busy = false

		if not ok then
			warn("[StoreClient] Redeem remote failed:", result)
			say("Code error. Check Output.", Color3.fromRGB(255, 150, 150))
			return
		end

		if type(result) == "table" and result.ok then
			box.Text = ""
			say(result.message or "Code redeemed!", Color3.fromRGB(150, 255, 200))
			StardustCollectAnimator.Play(playerGui, redeem, result.reward or 0)

		else
			local message = if type(result) == "table" then (result.message or "Invalid code!") else "Invalid code!"
			local alreadyUsed = string.find(string.lower(message), "already") ~= nil
			say(message, if alreadyUsed then Color3.fromRGB(255, 214, 120) else Color3.fromRGB(255, 150, 150))
		end
	end

	redeem.Activated:Connect(submit)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit()
		end
	end)
end

-- ===================== GIFT POPUP =====================
local giftPopup = frame(popup, {
	Name = "GiftComingSoon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(520, 300), Radius = 30, ZIndex = 90,
	Gradient = { Color3.fromRGB(128, 252, 255), Color3.fromRGB(0, 148, 246) },
	Stroke = { Color3.fromRGB(11, 62, 158), 5 },
})
giftPopup.Visible = false
gloss(giftPopup, 14, 0.34, 0.7)

local giftPopupScale = Instance.new("UIScale")
giftPopupScale.Scale = 0.7
giftPopupScale.Parent = giftPopup

image(giftPopup, {
	Name = "GiftArt", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16),
	Size = UDim2.fromOffset(130, 118), ZIndex = 92, Image = UIAssets.Gift,
})
text(giftPopup, {
	Name = "GiftMessage", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 142),
	Size = UDim2.new(0.9, 0, 0, 54), Text = "Gifting Coming Soon!", Wrap = true,
	Color = C.Cream, Max = 40, Min = 18, StrokeThickness = 3, ZIndex = 92,
})

local giftOkay = Instance.new("TextButton")
giftOkay.Name = "GiftOkay"
giftOkay.AnchorPoint = Vector2.new(0.5, 1)
giftOkay.Position = UDim2.new(0.5, 0, 1, -22)
giftOkay.Size = UDim2.fromOffset(210, 64)
giftOkay.BackgroundTransparency = 1
giftOkay.AutoButtonColor = false
giftOkay.Text = ""
giftOkay.ZIndex = 93
giftOkay.Parent = giftPopup

frame(giftOkay, { Name = "Extrusion", Position = UDim2.fromOffset(0, 6), Color = C.GreenEdge, Radius = 22, ZIndex = 93 })
local okayFace = frame(giftOkay, {
	Name = "Face", Radius = 22, ZIndex = 94, Stroke = { C.GreenEdge, 3.5 },
	Gradient = { C.GreenTop, C.GreenBottom },
})
gloss(okayFace, 8, 0.42, 0.55)
text(okayFace, {
	Name = "OkayText", Size = UDim2.fromScale(1, 0.66), Position = UDim2.fromScale(0, 0.15), Text = "OK!",
	Color = C.Cream, Max = 34, Min = 16, StrokeColor = Color3.fromRGB(8, 64, 32), StrokeThickness = 3, ZIndex = 99,
})
hoverScale(giftOkay, 1.03, 0.975)

giftPopupCloser = function()
	if not giftPopup.Visible then return false end
	giftPopup.Visible = false
	return true
end

giftButton.Activated:Connect(function()
	giftPopup.Visible = true
	giftPopupScale.Scale = 0.65

	TweenService:Create(
		giftPopupScale,
		TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end)

giftOkay.Activated:Connect(function()
	local t = TweenService:Create(
		giftPopupScale,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 0.7 }
	)

	t:Play()

	t.Completed:Connect(function()
		giftPopup.Visible = false
	end)
end)

-- ===================== BUILD =====================
makeSection("GAMEPASSES", StoreConfig.Gamepasses, "Gamepass", 1)
makeSection("STARDUST MULTIPLIERS", StoreConfig.StardustMultipliers, "Gamepass", 2)
makeSection("INSTANT STARDUST", StoreConfig.StardustPacks, "Product", 3)
makeCodesSection()

-- The Codes section now closes the canvas with its own cloud composition.

task.defer(refreshScrollBar)

-- ===================== STORE BUTTON =====================
local function buttonLooksLikeStore(button)
	if button.Name == "Store" or button.Name == "StoreButton" then
		return true
	end

	for _, child in ipairs(button:GetDescendants()) do
		if child:IsA("TextLabel") and string.lower(child.Text) == "store" then
			return true
		end
	end

	return false
end

local function findStoreButton(timeout)
	local start = os.clock()

	while os.clock() - start < timeout do
		local mainHud = playerGui:FindFirstChild("MainHUD")

		if mainHud then
			local sideMenu = mainHud:FindFirstChild("SideMenu", true)
			local storeSlot = sideMenu and sideMenu:FindFirstChild("StoreSlot")
			local direct = storeSlot and storeSlot:FindFirstChild("Store")

			if direct and direct:IsA("GuiButton") then
				return direct
			end

			for _, item in ipairs(mainHud:GetDescendants()) do
				if item:IsA("GuiButton") and buttonLooksLikeStore(item) then
					return item
				end
			end
		end

		task.wait(0.1)
	end

	return nil
end

-- ===================== ASSET GATE =====================
-- The Store does not open half-drawn. If its critical artwork is not ready
-- yet - which in practice only happens on a first open with a cold cache -
-- a small notice holds the place until it is.

local storeOpenPending = false
local storeOpenRequest = 0      -- bumped to cancel a held open
local loadingGui = nil
local loadingDots = nil
local loadingRunning = false

local function buildLoadingNotice()
	if loadingGui then return end

	loadingGui = Instance.new("ScreenGui")
	loadingGui.Name = "StoreLoadingNotice"
	loadingGui.ResetOnSpawn = false
	loadingGui.IgnoreGuiInset = true
	loadingGui.DisplayOrder = 24          -- just under the Store's own 25
	loadingGui.Enabled = false
	loadingGui.Parent = playerGui

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(300, 74)
	card.BackgroundColor3 = C.ShellNavy
	card.BackgroundTransparency = 0.06
	card.BorderSizePixel = 0
	card.Parent = loadingGui

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 18)
	round.Parent = card

	local edge = Instance.new("UIStroke")
	edge.Color = C.BorderBlue
	edge.Thickness = 3
	edge.Parent = card

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = GuiStyle.FONT
	label.Text = "Loading Store"
	label.TextColor3 = C.Cream
	label.TextSize = 24
	label.Parent = card

	local labelEdge = Instance.new("UIStroke")
	labelEdge.Color = C.Ink
	labelEdge.Thickness = 2.5
	labelEdge.Parent = label

	loadingDots = label
end

local function setLoadingNotice(on)
	buildLoadingNotice()
	loadingGui.Enabled = on

	if not on then
		loadingRunning = false
		return
	end

	if loadingRunning then return end
	loadingRunning = true

	-- Three dots, cycling. Driven by the notice being open, not by a timer
	-- that decides how long loading takes.
	task.spawn(function()
		local step = 0
		while loadingRunning and loadingGui and loadingGui.Enabled do
			step = (step + 1) % 4
			loadingDots.Text = "Loading Store" .. string.rep(".", step)
			task.wait(0.28)
		end
	end)
end

local function openStoreCollapsed()
	if storeAnimating or storeOpenPending then return end
	if GuiManager:GetCurrent() == "Store" or popup.Visible then return end

	local ready = UIAssets.GroupStatus == nil
		or UIAssets.GroupStatus("SecretStore") == "ready"

	if ready then
		openStoreNow()
		return
	end

	-- Rapid clicking cannot start a second request: this flag blocks re-entry
	-- and EnsureGroup joins the preload already in flight rather than
	-- launching another one.
	storeOpenPending = true
	storeOpenRequest += 1
	local request = storeOpenRequest
	setLoadingNotice(true)

	UIAssets.EnsureGroup("SecretStore", function(failures)
		-- A held open only goes ahead if it is still wanted: not cancelled
		-- (another window was opened meanwhile, or Store tapped again) and
		-- nothing else is open now. Without this, tapping Store and then
		-- Playtime made the Store pop up over Playtime once its art arrived.
		if request ~= storeOpenRequest or not storeOpenPending then return end
		storeOpenPending = false
		setLoadingNotice(false)
		if GuiManager:GetCurrent() ~= nil then return end

		if failures and #failures > 0 then
			warn(("[StoreClient] opening with %d asset(s) missing; fallbacks in use."):format(#failures))
		end

		openStoreNow()
	end)
end

-- Opening any other window cancels a held Store open.
local function cancelPendingStoreOpen()
	if not storeOpenPending then return end
	storeOpenPending = false
	storeOpenRequest += 1
	setLoadingNotice(false)
end
GuiManager.Changed:Connect(function(name)
	if name ~= nil and name ~= "Store" then cancelPendingStoreOpen() end
end)

local storeButton = findStoreButton(15)

if storeButton then
	storeButton.Activated:Connect(function()
		if storeOpenPending then cancelPendingStoreOpen() return end   -- second tap while loading = never mind
		if GuiManager:GetCurrent() == "Store" or popup.Visible then
			closeStoreCollapsed()
		else
			openStoreCollapsed()
		end
	end)

	print(("[StoreClient] build 2026-09-26  cart %dpx at (%d,%d), logo %dx%d at x=%d"):format(
		SHOP_DRAWN, SHOP_X, SHOP_Y, TITLE_WIDTH, TUNE.TitleHeight, TITLE_LEFT))
	print("[StoreClient] Connected existing Store button:", storeButton:GetFullName())
else
	warn("[StoreClient] Could not find MainHUD Store button.")
	warn("[StoreClient] Expected: PlayerGui > MainHUD > SideMenu > StoreSlot > Store")
end

-- ===================== STUDIO CROP TUNER =====================
-- Studio only, and it changes nothing in the game. Press 9 while the Store is
-- open, then dial the selected picture until it looks right and press 0: the
-- exact ART_CROP lines are printed for pasting into this script.
--
--   9  tuner on/off      H  next artwork
--   I / O  less / more trimmed off the BOTTOM
--   J / L  less / more trimmed off the TOP
--   B / N  narrower / wider source shape
--   0  print the table
if RunService:IsStudio() then
	local index = 1
	local readout = nil
	local lens, lensBox, lensArt, lensTop, lensBottom = nil, nil, nil, nil, nil

	-- The magnifier shows the WHOLE file, big, with a red wash over the parts
	-- the card is hiding. Dialling the crop moves the red bands live, so the
	-- line between illustration and lettering is something you can see rather
	-- than guess at.
	local function buildLens()
		lens = frame(popup, {
			Name = "CropLens", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44),
			Size = UDim2.fromScale(0.52, 0.62), Color = Color3.fromRGB(8, 12, 30), Transparency = 0.04,
			Radius = 18, ZIndex = 118,
		})
		stroke(lens, Color3.fromRGB(120, 220, 255), 2)

		text(lens, {
			Name = "LensTitle", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
			Size = UDim2.new(1, -20, 0, 24), Text = "red = hidden on the card", Font = Enum.Font.Code,
			Color = Color3.fromRGB(255, 170, 170), Max = 18, Min = 10, ZIndex = 119,
		})

		lensBox = frame(lens, {
			Name = "Sheet", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.54),
			Size = UDim2.fromScale(0.94, 0.8), Transparency = 1, ZIndex = 119,
		})
		local shape = Instance.new("UIAspectRatioConstraint")
		shape.Name = "Shape"
		shape.DominantAxis = Enum.DominantAxis.Height
		shape.Parent = lensBox

		lensArt = image(lensBox, { Name = "Full", Size = UDim2.fromScale(1, 1), ZIndex = 119 })
		lensTop = frame(lensBox, {
			Name = "HiddenTop", Color = Color3.fromRGB(255, 60, 60), Transparency = 0.62, ZIndex = 120,
		})
		lensBottom = frame(lensBox, {
			Name = "HiddenBottom", AnchorPoint = Vector2.new(0, 1), Color = Color3.fromRGB(255, 60, 60),
			Transparency = 0.62, ZIndex = 120,
		})
	end

	local function refreshLens()
		local entry = CROPPED[index]
		if not lens or not entry then return end
		lensBox:FindFirstChild("Shape").AspectRatio = entry.spec.Aspect
		lensArt.Image = entry.image
		local top = entry.spec.Top or 0
		lensTop.Position = UDim2.fromScale(0, 0)
		lensTop.Size = UDim2.fromScale(1, top)
		lensBottom.Position = UDim2.fromScale(0, 1)
		lensBottom.Size = UDim2.fromScale(1, entry.spec.Crop)
	end

	local function show()
		local entry = CROPPED[index]
		if not entry or not readout then return end
		readout.Text = ("%d/%d  %s\nbottom %.2f   top %.2f   shape %.2f   nudge %.2f\n9 off   8 magnify   H next   F/G bottom   J/L top   1/2 shape   M/N nudge   0 print")
			:format(index, #CROPPED, entry.key, entry.spec.Crop, entry.spec.Top or 0, entry.spec.Aspect, entry.spec.Nudge or 0)
	end

	local function adjust(field, delta)
		local entry = CROPPED[index]
		if not entry then return end
		local low = if field == "Nudge" then -0.3 else 0
		entry.spec[field] = math.clamp((entry.spec[field] or 0) + delta, low, 0.8)
		entry.apply()
		show()
		refreshLens()
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		local key = input.KeyCode

		if key == Enum.KeyCode.Nine then
			if readout then
				readout.Parent:Destroy()
				readout = nil
				if lens then
					lens:Destroy()
					lens, lensBox, lensArt, lensTop, lensBottom = nil, nil, nil, nil, nil
				end
				return
			end
			local panel = frame(popup, {
				Name = "CropTuner", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
				Size = UDim2.fromOffset(640, 104), Color = Color3.fromRGB(6, 10, 26), Transparency = 0.06,
				Radius = 16, ZIndex = 120,
			})
			readout = text(panel, {
				Name = "Readout", Size = UDim2.fromScale(1, 1), Text = "", Color = Color3.fromRGB(190, 240, 255),
				Font = Enum.Font.Code, Max = 22, Min = 10, Wrap = true, ZIndex = 121,
			})
			show()

		elseif readout then
			if key == Enum.KeyCode.H then
				index = if index >= #CROPPED then 1 else index + 1
				show()
				refreshLens()
			elseif key == Enum.KeyCode.Eight then
				if lens then
					lens:Destroy()
					lens, lensBox, lensArt, lensTop, lensBottom = nil, nil, nil, nil, nil
				else
					buildLens()
					refreshLens()
				end
			elseif key == Enum.KeyCode.F then adjust("Crop", -0.01)
			elseif key == Enum.KeyCode.G then adjust("Crop", 0.01)
			elseif key == Enum.KeyCode.J then adjust("Top", -0.01)
			elseif key == Enum.KeyCode.L then adjust("Top", 0.01)
			elseif key == Enum.KeyCode.One then adjust("Aspect", -0.02)
			elseif key == Enum.KeyCode.Two then adjust("Aspect", 0.02)
			elseif key == Enum.KeyCode.M then adjust("Nudge", -0.01)
			elseif key == Enum.KeyCode.N then adjust("Nudge", 0.01)
			elseif key == Enum.KeyCode.Zero then
				print("[StoreCrop] paste this over ART_CROP in StoreClient:")
				for _, entry in ipairs(CROPPED) do
					print(("\t%-25s = { Aspect = %.2f, Crop = %.2f, Top = %.2f, Nudge = %.2f },")
						:format(entry.key, entry.spec.Aspect, entry.spec.Crop, entry.spec.Top or 0, entry.spec.Nudge or 0))
				end
			end
		end
	end)

	print("[StoreCrop] Studio: press 9 with the Store open to tune the artwork crop, then 8 to magnify it.")
end

local _kept = { playStoreClickSoundLater, shopIcon, titleArt, titleLabel, subtitle }
