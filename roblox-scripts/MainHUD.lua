-- MainHUD / GUI (LocalScript)
-- Put in: StarterPlayer > StarterPlayerScripts > GUI
-- Main HUD + Stardust counter + side buttons + Playtime button
-- + Upgrade GUI that spends Stardust.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Config = require(ReplicatedStorage:WaitForChild("UpgradeConfig"))
local buyRemote = ReplicatedStorage:WaitForChild("UpgradeRemotes"):WaitForChild("BuyUpgrade")

local UIAssets do
	-- Image ids live in ReplicatedStorage > UIAssets. Missing module = no art,
	-- never a broken HUD.
	local module = ReplicatedStorage:WaitForChild("UIAssets", 10)
	if module then
		UIAssets = require(module)
	else
		warn("[MainHUD] ReplicatedStorage > UIAssets is missing: icons will be blank.")
		UIAssets = {}
	end
end


-- The HUD is the earliest client script, so this is where the whole UI's
-- artwork starts warming: HUD first, then the Store, then the leaderboard,
-- then the rest. By the time a player presses a button the pictures are
-- normally already cached, which is the point - the gates in the individual
-- windows are the backup path, not the normal one.
if UIAssets.WarmStartup then
	UIAssets.WarmStartup()
elseif UIAssets.Preload then
	UIAssets.Preload("Nav")
end

local oldGui = playerGui:FindFirstChild("MainHUD")
if oldGui then
	oldGui:Destroy()
end

local oldBlur = Lighting:FindFirstChild("UpgradeGuiBlur")
if oldBlur then
	oldBlur:Destroy()
end

-- ===== responsive scaling =====
local camera = workspace.CurrentCamera
local DESIGN = Vector2.new(1280, 720)
local MIN_SCALE, MAX_SCALE = 0.45, 1

local scaleMultipliers = {}   -- [GuiObject] = extra factor (set by the phone layout)
-- Size of the Stardust + Gems counters relative to their design size
-- (UIAssets.HudArt.CurrencyHeight). 1 = the size the artwork was laid out for.
local CURRENCY_HUD_SCALE = 1
-- The Gems panel next to it, as a share of the Stardust panel's size.
local GEMS_HUD_SCALE = 0.85   -- about 67% of the Stardust panel's width
local scaleRefreshers = {}

local function autoScale(guiObject)
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = guiObject

	local function refresh()
		local vp = camera.ViewportSize
		if vp.X < 1 then return end

		uiScale.Scale = math.clamp(
			math.min(vp.X / DESIGN.X, vp.Y / DESIGN.Y),
			MIN_SCALE,
			MAX_SCALE
		) * math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 1, 1.6)   -- grows past 1080p
			* (scaleMultipliers[guiObject] or 1)
	end

	scaleRefreshers[guiObject] = refresh
	refresh()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)

	return uiScale
end

-- ===== sounds =====
local HOVER_SOUND_ID = "rbxassetid://7218169592"
local CLICK_SOUND_ID = "rbxassetid://129349771709668"

local hoverSound = Instance.new("Sound")
hoverSound.Name = "HUDHoverSound"
hoverSound.SoundId = HOVER_SOUND_ID
hoverSound.Volume = 0.5
hoverSound.Parent = SoundService

local clickSound = Instance.new("Sound")
clickSound.Name = "UpgradeClickSound"
clickSound.SoundId = CLICK_SOUND_ID
clickSound.Volume = 0.8
clickSound.Parent = SoundService

local function playHoverSound()
	hoverSound.TimePosition = 0
	hoverSound:Play()
end

local function playClickSound()
	clickSound.TimePosition = 0
	clickSound:Play()
end

-- ===== theme =====
local THEME = {
	Gold = Color3.fromRGB(255, 215, 90),
	Accent = Color3.fromRGB(150, 225, 255),
	Text = Color3.fromRGB(255, 255, 255),
	Outline = Color3.fromRGB(28, 20, 48),

	Store = Color3.fromRGB(255, 196, 64),
	Leaderboards = Color3.fromRGB(40, 200, 190),
	Index = Color3.fromRGB(74, 108, 240),
	Rebirth = Color3.fromRGB(170, 80, 232),
	Inventory = Color3.fromRGB(236, 120, 60),
	Gems = Color3.fromRGB(80, 190, 255),
	Playtime = Color3.fromRGB(255, 150, 70),

	Upgrade = Color3.fromRGB(25, 235, 95),
	LockBase = Color3.fromRGB(225, 55, 85),
	Locked = Color3.fromRGB(165, 35, 65),
	Cooldown = Color3.fromRGB(100, 105, 125),

	PopupBody = Color3.fromRGB(255, 246, 199),
	PriceGreen = Color3.fromRGB(15, 230, 20),
	Red = Color3.fromRGB(240, 72, 82),
	RedBorder = Color3.fromRGB(255, 150, 155),
	Shadow = Color3.fromRGB(16, 9, 32),
	CardDark = Color3.fromRGB(5, 25, 20),
}

local FONT = Enum.Font.FredokaOne

-- ===== number formatting =====
local SUFFIX = {"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"}

local function abbreviate(n)
	n = tonumber(n) or 0
	n = math.max(n, 0)

	if n < 1000 then
		return tostring(math.floor(n))
	end

	local idx = math.clamp(math.floor(math.log(n) / math.log(1000)), 1, #SUFFIX - 1)
	local scaled = n / (1000 ^ idx)

	return (string.format("%.2f", scaled):gsub("%.?0+$", "")) .. SUFFIX[idx + 1]
end

local function fmtSeconds(sec)
	sec = math.max(0, math.floor(sec))

	local m = math.floor(sec / 60)
	local s = sec % 60

	if m > 0 then
		return string.format("%d:%02d", m, s)
	end

	return tostring(s) .. "s"
end

-- ===== UI helpers =====
local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(r, 0)
	c.Parent = parent
	return c
end

local function outline(parent, mode, thickness)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = mode
	s.Color = THEME.Outline
	s.Thickness = thickness
	s.Parent = parent
	return s
end

local function addShadow(parent)
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, 0, 0.5, 5)
	shadow.Size = UDim2.new(1, 8, 1, 8)
	shadow.BackgroundColor3 = THEME.Shadow
	shadow.BackgroundTransparency = 0.4
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 0
	shadow.Parent = parent
	corner(shadow, 0.3)
	return shadow
end

local function offsetUDim2(base, addX, addY)
	return UDim2.new(
		base.X.Scale,
		base.X.Offset + addX,
		base.Y.Scale,
		base.Y.Offset + addY
	)
end

local function addSizeUDim2(base, addX, addY)
	return UDim2.new(
		base.X.Scale,
		base.X.Offset + addX,
		base.Y.Scale,
		base.Y.Offset + addY
	)
end

local function makeChunkyX(parent, position, size, zIndex)
	local xshadow = Instance.new("Frame")
	xshadow.Name = "CloseShadow"
	xshadow.AnchorPoint = Vector2.new(1, 0.5)
	xshadow.Position = offsetUDim2(position, 2, 4)
	xshadow.Size = addSizeUDim2(size, 4, 4)
	xshadow.BackgroundColor3 = THEME.Shadow
	xshadow.BackgroundTransparency = 0.5
	xshadow.BorderSizePixel = 0
	xshadow.ZIndex = zIndex
	xshadow.Parent = parent
	corner(xshadow, 0.32)

	local xbtn = Instance.new("TextButton")
	xbtn.Name = "CloseButton"
	xbtn.AnchorPoint = Vector2.new(1, 0.5)
	xbtn.Position = position
	xbtn.Size = size
	xbtn.BackgroundColor3 = THEME.Red
	xbtn.AutoButtonColor = false
	xbtn.Text = ""
	xbtn.ZIndex = zIndex + 2
	xbtn.Parent = parent
	corner(xbtn, 0.32)

	local stroke = Instance.new("UIStroke")
	stroke.Color = THEME.RedBorder
	stroke.Thickness = 3
	stroke.Parent = xbtn

	local function xbar(rot)
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.fromScale(0.5, 0.5)
		b.Size = UDim2.new(0.62, 0, 0.17, 0)
		b.BackgroundColor3 = THEME.Text
		b.BorderSizePixel = 0
		b.Rotation = rot
		b.ZIndex = zIndex + 3
		b.Parent = xbtn
		corner(b, 1)
	end

	xbar(45)
	xbar(-45)

	local xScale = Instance.new("UIScale")
	xScale.Scale = 1
	xScale.Parent = xbtn

	local shadowScale = Instance.new("UIScale")
	shadowScale.Scale = 1
	shadowScale.Parent = xshadow

	xbtn.MouseEnter:Connect(function()
		playHoverSound()

		TweenService:Create(
			xScale,
			TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1.12 }
		):Play()

		TweenService:Create(
			shadowScale,
			TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1.12 }
		):Play()
	end)

	xbtn.MouseLeave:Connect(function()
		TweenService:Create(
			xScale,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()

		TweenService:Create(
			shadowScale,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end)

	return xbtn
end

-- ===== main ScreenGui =====
local gui = Instance.new("ScreenGui")
gui.Name = "MainHUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Parent = playerGui

-- ===== top buttons =====
local actionBar = Instance.new("Frame")
actionBar.Name = "TopActionButtons"
actionBar.AnchorPoint = Vector2.new(0.5, 0)
actionBar.Position = UDim2.new(0.5, 0, 0, 14)
actionBar.Size = UDim2.fromOffset(660, 78)
actionBar.BackgroundTransparency = 1
actionBar.ZIndex = 10
actionBar.Parent = gui

local actionLayout = Instance.new("UIListLayout")
actionLayout.FillDirection = Enum.FillDirection.Horizontal
actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
actionLayout.Padding = UDim.new(0, 18)
actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
actionLayout.Parent = actionBar

-- ===== stardust + gems counters =====
-- Bottom-left, under the side menu (see placeStardust at the end). Two
-- matching glossy modules: a near-black navy edge, a blue band, a deep navy
-- surface with a thin cyan inner line and a soft top gloss. Stardust is the
-- wide one (big coin, amount, caption); Gems sits right beside it. A few small
-- decorative stars (UIAssets.CurrencyHUD) - decoration only, never currency.
-- Values always show the real balance at once; gains add a small pop at most
-- every 0.1 s however many coins arrive.
local function buildCurrencyHud()
	local ART = UIAssets.CurrencyHUD or {}
	local HUD_ART = UIAssets.HudArt or { Layout = {} }
	local LAYOUT = HUD_ART.Layout or {}

	-- The panels are the supplied pictures (UIAssets.HudArt): borders, gloss
	-- and sparkles are painted in, so nothing of that is drawn here. Only the
	-- live icon and numbers sit on top, placed as shares of the painted panel.
	-- The pictures set the size: each panel keeps its own shape at this
	-- height, and the whole counter is scaled to the screen (autoScale).
	local H = HUD_ART.CurrencyHeight or 74       -- design height of both panels
	local INK = Color3.fromRGB(6, 11, 42)

	local function paint(object, stops, rotation)
		local keys = {}
		for i, stop in ipairs(stops) do keys[i] = ColorSequenceKeypoint.new(stop[1], stop[2]) end
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(keys)
		g.Rotation = rotation or 90
		g.Parent = object
		return g
	end
	local function box(object, spec)
		object.Position = UDim2.fromScale(spec[1], spec[2])
		object.Size = UDim2.fromScale(spec[3], spec[4])
	end
	local function iconAt(parent, name, image, spec, z)
		local img = Instance.new("ImageLabel")
		img.Name = name
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(spec[1], spec[2])
		img.SizeConstraint = Enum.SizeConstraint.RelativeYY   -- a share of the panel HEIGHT, always square
		img.Size = UDim2.fromScale(spec[3], spec[3])
		img.BackgroundTransparency = 1
		img.Image = image or ""
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = z or 10
		img.Parent = parent
		local s = Instance.new("UIScale")
		s.Parent = img
		return img, s
	end

	-- One illustrated panel: the picture, placed so its painted panel body
	-- fills the frame exactly (UIAssets.HudArt.Geometry, measured from the
	-- PNG files); transparent margins and sparkles hang outside. The frame
	-- has the body's own shape, so nothing is stretched.
	local GEOMETRY = HUD_ART.Geometry or {}
	local function panel(name, artId, geometry)
		local root = Instance.new("Frame")
		root.Name = name
		local aspect = if geometry then UIAssets.BodyAspect(geometry) else 3
		root.Size = UDim2.fromOffset(math.floor(H * aspect + 0.5), H)
		root.BackgroundTransparency = 1
		root.ZIndex = 8
		root.Parent = gui
		local art = Instance.new("ImageLabel")
		art.Name = "Background"
		art.Size = UDim2.fromScale(1, 1)
		art.BackgroundTransparency = 1
		art.Image = artId or ""
		art.ScaleType = Enum.ScaleType.Fit
		art.ZIndex = 8
		art.Parent = root
		if geometry then UIAssets.FitArt(art, geometry.Body) end
		return root
	end

	-- Shared lettering: TextScaled into its box, thick navy outline, and a
	-- navy copy just below for depth. Returns label, pop, depth, depthPop.
	local function amountText(parent, name, spec, maxSize, stops)
		local function make(labelName, z, dy)
			local l = Instance.new("TextLabel")
			l.Name = labelName
			l.BackgroundTransparency = 1
			l.Position = UDim2.new(spec[1], 0, spec[2], dy)
			l.Size = UDim2.fromScale(spec[3], spec[4])
			l.Text = "0"
			l.Font = FONT
			l.TextScaled = true
			l.TextXAlignment = Enum.TextXAlignment.Center
			l.TextColor3 = Color3.new(1, 1, 1)
			l.ZIndex = z
			l.Parent = parent
			local limit = Instance.new("UITextSizeConstraint")
			limit.MinTextSize = 14
			limit.MaxTextSize = maxSize
			limit.Parent = l
			local st = Instance.new("UIStroke")
			st.Color = INK
			st.Thickness = 3.5
			st.LineJoinMode = Enum.LineJoinMode.Round
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			st.Parent = l
			local pop = Instance.new("UIScale")
			pop.Parent = l
			return l, pop
		end
		local depth, depthPop = make(name .. "Depth", 10, 3)
		depth.TextColor3 = INK
		local label, pop = make(name, 11, 0)
		paint(label, stops)
		return label, pop, depth, depthPop
	end

	-- ---------- Stardust ----------
	local S = LAYOUT.Stardust
	local top = panel("StardustDisplay", HUD_ART.StardustBackground, GEOMETRY.Stardust)
	local coin, coinScale = iconAt(top, "Star", ART.Stardust or UIAssets.Stardust, S.Icon, 10)
	local amount, amountPop, amountDepth, amountDepthPop = amountText(top, "Amount", S.Amount, 44, {
		{ 0, Color3.fromRGB(255, 252, 226) }, { 0.5, Color3.fromRGB(255, 232, 120) }, { 1, Color3.fromRGB(255, 190, 50) },
	})
	-- The word STARDUST is the supplied picture (not text), trimmed to its
	-- letters and centred under the amount.
	local caption = Instance.new("Frame")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	box(caption, S.Label)
	caption.ZIndex = 11
	caption.Parent = top
	UIAssets.WordImage(caption, HUD_ART.StardustWord, GEOMETRY.StardustWord, 11)

	-- ---------- Gems ----------
	local G = LAYOUT.Gems
	local gemsPill = panel("GemsDisplay", HUD_ART.GemsBackground, GEOMETRY.Gems)
	gemsPill.AnchorPoint = Vector2.new(0, 0.5)
	gemsPill.Visible = false
	local gemIcon, gemsPop = iconAt(gemsPill, "GemIcon", ART.Gems or UIAssets.Gems, G.Icon, 10)
	-- Named differently from the Stardust "Amount" so reward animations keep
	-- flying to Stardust.
	local gemsAmount, gemsTextPop, gemsDepth, gemsDepthPop = amountText(gemsPill, "GemsAmount", G.Amount, 44, {
		{ 0, Color3.new(1, 1, 1) }, { 0.55, Color3.fromRGB(236, 250, 255) }, { 1, Color3.fromRGB(176, 230, 255) },
	})

	-- ---------- icon glint: a small four-point shine, now and then ----------
	local function glintOn(parent, x, y, size)
		local holder = Instance.new("Frame")
		holder.Name = "Glint"
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(x, y)
		holder.Size = UDim2.fromOffset(size, size)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 13
		holder.Parent = parent
		for _, rotation in ipairs({ 0, 90 }) do
			local ray = Instance.new("Frame")
			ray.AnchorPoint = Vector2.new(0.5, 0.5)
			ray.Position = UDim2.fromScale(0.5, 0.5)
			ray.Size = UDim2.new(1, 0, 0, math.max(2, size / 7))
			ray.Rotation = rotation
			ray.BackgroundColor3 = Color3.new(1, 1, 1)
			ray.BackgroundTransparency = 0.1
			ray.BorderSizePixel = 0
			ray.ZIndex = 13
			ray.Parent = holder
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = ray
			local taper = Instance.new("UIGradient")
			taper.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
			})
			taper.Parent = ray
		end
		local s = Instance.new("UIScale")
		s.Scale = 0
		s.Parent = holder
		return s
	end
	local starGlint = glintOn(coin, 0.72, 0.26, 22)
	local gemGlint = glintOn(gemIcon, 0.7, 0.3, 18)
	local function flash(s)
		local up = TweenService:Create(s, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
		up.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				TweenService:Create(s, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
			end
		end)
		up:Play()
	end

	-- ---------- live values ----------
	local QUICK_UP = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local QUICK_DOWN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local function bump(scales, peak)
		for _, s in ipairs(scales) do
			local up = TweenService:Create(s, QUICK_UP, { Scale = peak })
			up.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					TweenService:Create(s, QUICK_DOWN, { Scale = 1 }):Play()
				end
			end)
			up:Play()
		end
	end

	local lastStardust = tonumber(player:GetAttribute("Stardust")) or 0
	local lastPop = 0
	local popQueued = false
	local function pop()
		lastPop = os.clock()
		bump({ amountPop, amountDepthPop }, 1.055)
	end
	local function refreshStardust()
		local value = tonumber(player:GetAttribute("Stardust")) or 0
		amount.Text = abbreviate(value)
		amountDepth.Text = amount.Text
		if value > lastStardust then
			-- Many coins in a moment make one pop, not a shaking counter.
			local wait = 0.1 - (os.clock() - lastPop)
			if wait <= 0 then
				pop()
			elseif not popQueued then
				popQueued = true
				task.delay(wait, function()
					popQueued = false
					pop()
				end)
			end
		end
		lastStardust = value
	end
	player:GetAttributeChangedSignal("Stardust"):Connect(refreshStardust)
	refreshStardust()

	local lastGems = nil
	local lastGemPop = 0
	local function refreshGems()
		local value = player:GetAttribute("Gems")
		if value == nil then
			gemsPill.Visible = false
			return
		end
		value = math.max(math.floor(tonumber(value) or 0), 0)
		gemsPill.Visible = true
		gemsAmount.Text = abbreviate(value)
		gemsDepth.Text = gemsAmount.Text
		-- Only a real change after the first sync animates (loading is silent).
		if lastGems ~= nil and value > lastGems and os.clock() - lastGemPop > 0.1 then
			lastGemPop = os.clock()
			bump({ gemsTextPop, gemsDepthPop }, 1.04)
			bump({ gemsPop }, 1.1)
		end
		lastGems = value
	end
	player:GetAttributeChangedSignal("Gems"):Connect(refreshGems)
	refreshGems()

	-- Big collection moments pulse harder, icon too (StardustDropClient).
	do
		local folder = ReplicatedStorage:FindFirstChild("ClientSignals")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "ClientSignals"
			folder.Parent = ReplicatedStorage
		end
		local pulse = folder:FindFirstChild("CurrencyPulse")
		if not pulse then
			pulse = Instance.new("BindableEvent")
			pulse.Name = "CurrencyPulse"
			pulse.Parent = folder
		end
		pulse.Event:Connect(function(peak, withIcon)
			peak = math.clamp(tonumber(peak) or 1.04, 1, 1.1)
			lastPop = os.clock()   -- this pulse counts as the counter's pop
			bump({ amountPop, amountDepthPop }, peak)
			if withIcon then
				bump({ coinScale }, peak + 0.03)
				flash(starGlint)
			end
		end)
	end

	-- ---------- idle: a quick shine on one icon now and then ----------
	task.spawn(function()
		while gui.Parent do
			task.wait(5 + math.random() * 4)
			if player:GetAttribute("ReduceMotion") ~= true then
				flash(if math.random() < 0.65 or not gemsPill.Visible then starGlint else gemGlint)
			end
		end
	end)

	return top, gemsPill
end
local top, gemsPill = buildCurrencyHud()

-- ===== button animation presets =====
local POP_IN = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Star-gloss navigation v5: illustrated highlights and original Stardust motifs.
local function buildCohesiveNav(text,color,iconId)
	local palette={Store=Color3.fromRGB(255,194,22),Leaderboards=Color3.fromRGB(0,214,214),Index=Color3.fromRGB(25,119,255),Rebirth=Color3.fromRGB(177,53,247),Inventory=Color3.fromRGB(255,137,29)}
	color=palette[text] or color
	local ink=Color3.fromRGB(20,28,65)
	local btn=Instance.new("TextButton")
	btn.Name=text;btn.Text="";btn.BackgroundTransparency=1;btn.AutoButtonColor=false
	btn.AnchorPoint=Vector2.new(.5,.5);btn.Position=UDim2.fromScale(.5,.5);btn.Size=UDim2.fromScale(1,1);btn.ZIndex=2
	local function plate(name,y,tint,z)
		local frame=Instance.new("Frame");frame.Name=name;frame.Position=UDim2.fromOffset(0,y);frame.Size=UDim2.fromScale(1,1)
		frame.BackgroundColor3=tint;frame.BorderSizePixel=0;frame.ZIndex=z;frame.Parent=btn
		local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,23);c.Parent=frame
		return frame
	end
	local shadow=plate("Shadow",8,ink,0);shadow.BackgroundTransparency=.5
	local edge=plate("Extrusion",5,color:Lerp(ink,.4),1)
	local face=plate("Face",0,Color3.new(1,1,1),2)
	local line=Instance.new("UIStroke");line.Thickness=3.3;line.Color=ink;line.Parent=face
	local gradient=Instance.new("UIGradient");gradient.Rotation=90
	gradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,color:Lerp(Color3.new(1,1,1),.35)),ColorSequenceKeypoint.new(.34,color:Lerp(Color3.new(1,1,1),.1)),ColorSequenceKeypoint.new(1,color:Lerp(ink,.1))});gradient.Parent=face
	-- Molded studs: above the face's gradient, under its gloss (ZIndex 2-3)
	-- and under the icon and label (the content layer on the button).
	do
		local module = game:GetService("ReplicatedStorage"):FindFirstChild("StudSurface")
		local ok, StudSurface = pcall(function() return module and require(module) end)
		if ok and type(StudSurface) == "table" then
			StudSurface.Apply(face, { Tint = color, CornerRadius = 23, ZIndex = 1 })
		end
	end
	-- A broad curved reflection, not a thin horizontal streak.
	local inset=Instance.new("Frame");inset.Name="CandyInset";inset.BackgroundTransparency=1
	inset.Position=UDim2.fromOffset(7,5);inset.Size=UDim2.new(1,-14,1,-11);inset.ZIndex=2;inset.Parent=face
	local insetCorner=Instance.new("UICorner");insetCorner.CornerRadius=UDim.new(0,18);insetCorner.Parent=inset
	local insetLine=Instance.new("UIStroke");insetLine.Color=color:Lerp(Color3.new(1,1,1),.65);insetLine.Thickness=1.6;insetLine.Transparency=.32;insetLine.Parent=inset
	local reflection=Instance.new("Frame");reflection.Name="SoftReflection";reflection.BackgroundColor3=Color3.new(1,1,1)
	reflection.BackgroundTransparency=.85;reflection.BorderSizePixel=0;reflection.Position=UDim2.fromOffset(10,7);reflection.Size=UDim2.new(1,-20,.31,0);reflection.ZIndex=2;reflection.Parent=face
	local reflectionCorner=Instance.new("UICorner");reflectionCorner.CornerRadius=UDim.new(1,0);reflectionCorner.Parent=reflection
	local reflectionFade=Instance.new("UIGradient");reflectionFade.Rotation=90;reflectionFade.Transparency=NumberSequence.new(0,1);reflectionFade.Parent=reflection
	-- Elliptical glints and four-point stars are GUI shapes, not external image assets.
	local function shape(parent,name,x,y,w,h,tint,rotation,alpha)
		local p=Instance.new("Frame");p.Name=name;p.AnchorPoint=Vector2.new(.5,.5)
		p.Position=UDim2.fromScale(x,y);p.Size=UDim2.fromOffset(w,h);p.BorderSizePixel=0
		p.BackgroundColor3=tint;p.BackgroundTransparency=alpha or 0;p.Rotation=rotation or 0;p.ZIndex=3;p.Parent=parent
		local c=Instance.new("UICorner");c.CornerRadius=UDim.new(1,0);c.Parent=p
		return p
	end
	do
		-- Both highlights fade out at their ends. A solid bar with square ends
		-- is what made the glint look blocky.
		local streak=shape(face,"GlossStroke",.15,.17,34,6,Color3.fromRGB(255,255,238),-32,.3)
		local taper=Instance.new("UIGradient")
		taper.Transparency=NumberSequence.new({
			NumberSequenceKeypoint.new(0,1),
			NumberSequenceKeypoint.new(.5,0),
			NumberSequenceKeypoint.new(1,1),
		})
		taper.Parent=streak

		local dot=shape(face,"GlossDot",.075,.32,7,7,Color3.new(1,1,1),0,.4)
		local soften=Instance.new("UIGradient")
		soften.Rotation=90
		soften.Transparency=NumberSequence.new({
			NumberSequenceKeypoint.new(0,.15),
			NumberSequenceKeypoint.new(1,1),
		})
		soften.Parent=dot
	end
	local starColor=color:Lerp(Color3.fromRGB(255,255,209),.72)
	for i,spec in ipairs({{.2,.48,13},{.8,.38,13},{.87,.58,8}}) do
		local star=Instance.new("Frame");star.Name="StardustSparkle"..i;star.BackgroundTransparency=1
		star.AnchorPoint=Vector2.new(.5,.5);star.Position=UDim2.fromScale(spec[1],spec[2]);star.Size=UDim2.fromOffset(spec[3],spec[3]);star.ZIndex=3;star.Parent=face
		shape(star,"Vertical",.5,.5,spec[3]*.35,spec[3],starColor,0,.08)
		shape(star,"Horizontal",.5,.5,spec[3],spec[3]*.35,starColor,0,.08)
		local core=shape(star,"Diamond",.5,.5,spec[3]*.58,spec[3]*.58,starColor,45,.08)
		core:FindFirstChildOfClass("UICorner").CornerRadius=UDim.new(.18,0)
	end
	local content=Instance.new("Frame");content.Name="NavContent";content.BackgroundTransparency=1
	content.Position=UDim2.fromOffset(4,0);content.Size=UDim2.new(1,-8,1,0);content.ZIndex=3;content.Parent=btn
	local label=Instance.new("TextLabel");label.Name="Label";label.BackgroundTransparency=1
	label.AnchorPoint=Vector2.new(.5,1);label.Position=UDim2.new(.5,0,1,-4);label.Size=UDim2.new(1,0,0,27)
	label.Text=text;label.Font=Enum.Font.FredokaOne;label.TextColor3=Color3.fromRGB(255,254,247)
	label.TextScaled=false;label.TextWrapped=false;label.ZIndex=4;label.Parent=content
	local fontSize=text=="Leaderboards" and 22 or 27
	local measure=game:GetService("TextService")
	while fontSize>18 and measure:GetTextSize(label.Text,fontSize,Enum.Font.FredokaOne,Vector2.new(1000,100)).X>172 do fontSize-=1 end
	label.TextSize=fontSize
	local stroke=Instance.new("UIStroke");stroke.Color=ink;stroke.Thickness=2.2;stroke.Transparency=.05;stroke.Parent=label
	local function placeIcon(icon)
		icon.AnchorPoint=Vector2.new(.5,0)
		icon.Position=UDim2.new(.5,0,0,1);icon.Size=UDim2.fromOffset(52,47);icon.ZIndex=4
		icon.Parent=content
	end
	if iconId and iconId~="" then
		-- Exactly one artwork per button. Each PNG already carries its own
		-- navy outline, gloss and colour, so it is drawn once, untinted and
		-- never stretched. Fit can only letterbox, never crop, so the podium's
		-- "1", the book edges, the rebirth sparkle and the chest corners all
		-- stay whole. The scale below evens out their different aspect ratios
		-- so no button's icon looks bigger than its neighbours'.
		local visualScale={Store=1,Leaderboards=1,Index=.94,Rebirth=.94,Inventory=1}
		local icon=Instance.new("Frame");icon.Name="Icon";icon.BackgroundTransparency=1;placeIcon(icon)
		local size=visualScale[text] or 1
		local image=Instance.new("ImageLabel");image.Name="IconArtwork"
		image.BackgroundTransparency=1;image.BorderSizePixel=0
		image.Active=false                      -- the button keeps the click
		image.AnchorPoint=Vector2.new(.5,.5);image.Position=UDim2.fromScale(.5,.5)
		image.Size=UDim2.fromScale(size,size)
		image.Image=iconId;image.ScaleType=Enum.ScaleType.Fit
		image.ImageColor3=Color3.fromRGB(255,255,255)
		image.ZIndex=3;image.Parent=icon
	end
	local scale=Instance.new("UIScale");scale.Parent=btn
	local hover,down=false,false
	local tweens={}
	local function update()
		for _,t in ipairs(tweens) do t:Cancel() end;table.clear(tweens)
		local reduced=player:GetAttribute("ReduceMotion")==true
		local offset=reduced and 0 or (down and 3 or (hover and -.75 or 0))
		local function animate(object,goal)
			local t=TweenService:Create(object,TweenInfo.new(reduced and 0 or .14,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),goal)
			tweens[#tweens+1]=t;t:Play()
		end
		animate(scale,{Scale=reduced and 1 or (down and .98 or (hover and 1.025 or 1))})
		animate(face,{Position=UDim2.fromOffset(0,offset),BackgroundColor3=hover and Color3.new(1,1,1) or Color3.fromRGB(248,248,255)})
		animate(content,{Position=UDim2.fromOffset(4,offset)})
	end
	btn.MouseEnter:Connect(function() hover=true;playHoverSound();update() end)
	btn.MouseLeave:Connect(function() hover=false;down=false;update() end)
	btn.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch or input.KeyCode==Enum.KeyCode.ButtonA then down=true;update() end end)
	btn.InputEnded:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch or input.KeyCode==Enum.KeyCode.ButtonA then down=false;update() end end)
	btn.Activated:Connect(function() down=false;update() end)
	btn.Destroying:Connect(function() for _,t in ipairs(tweens) do t:Cancel() end end)
	return btn
end

local function buildButton(text, color, iconId, glimmer)
	if text=="Store" or text=="Leaderboards" or text=="Index" or text=="Rebirth" or text=="Inventory" then return buildCohesiveNav(text,color,iconId) end
	local btn = Instance.new("TextButton")
	btn.Name = text
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.fromScale(0.5, 0.5)
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundColor3 = color
	btn.AutoButtonColor = false
	btn.ClipsDescendants = true
	btn.Text = ""
	btn.ZIndex = 2

	corner(btn, 0.28)
	outline(btn, Enum.ApplyStrokeMode.Border, 4)

	local shade = Instance.new("UIGradient")
	shade.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200))
	shade.Rotation = 90
	shade.Parent = btn

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = FONT
	label.TextColor3 = THEME.Text
	label.TextScaled = true
	label.TextWrapped = true
	label.ZIndex = 3
	label.Parent = btn
	outline(label, Enum.ApplyStrokeMode.Contextual, 2.5)

	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 44
	sc.Parent = label

	local hasIcon = iconId ~= nil and iconId ~= ""

	if hasIcon then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.fromScale(0.5, 0.04)
		icon.Size = UDim2.fromScale(0.62, 0.62)
		icon.BackgroundTransparency = 1
		icon.Image = iconId
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 3
		icon.Parent = btn

		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = icon

		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.fromScale(0.5, 0.97)
		label.Size = UDim2.fromScale(0.92, 0.34)
	else
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(0.88, 0.62)
	end

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = btn

	local shineGrad
	local shineTween

	if glimmer then
		local shine = Instance.new("Frame")
		shine.Name = "Shine"
		shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		shine.BorderSizePixel = 0
		shine.Size = UDim2.fromScale(1, 1)
		shine.ZIndex = 5
		shine.Parent = btn
		corner(shine, 0.28)

		shineGrad = Instance.new("UIGradient")
		shineGrad.Rotation = 18
		shineGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		shineGrad.Offset = Vector2.new(-1, 0)
		shineGrad.Parent = shine

		shineTween = TweenService:Create(
			shineGrad,
			TweenInfo.new(0.8, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
			{ Offset = Vector2.new(1, 0) }
		)
	end

	btn.MouseEnter:Connect(function()
		playHoverSound()
		TweenService:Create(scale, POP_IN, { Scale = 1.06 }):Play()

		if shineTween then
			shineTween:Play()
		end
	end)

	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, POP_OUT, { Scale = 1 }):Play()

		if shineTween and shineGrad then
			shineTween:Cancel()
			shineGrad.Offset = Vector2.new(-1, 0)
		end
	end)

	return btn
end

local function makeSlot(parent, name, size, layoutOrder)
	local slot = Instance.new("Frame")
	slot.Name = name .. "Slot"
	slot.LayoutOrder = layoutOrder or 1
	slot.Size = size
	slot.BackgroundTransparency = 1
	slot.ZIndex = 1
	slot.Parent = parent
	addShadow(slot)
	return slot
end

-- ===== top action buttons =====
-- UPGRADE and LOCK BASE / PROTECTED are finished artwork from
-- UIAssets.TopButtons: face, icon, wording and outline are all in the PNG, so
-- nothing is drawn behind or on top of them. The only live element is the
-- protection timer beside LOCK BASE / PROTECTED.
local TOP_ART = UIAssets.TopButtons or {}

-- Each PNG is the whole button on a transparent canvas slightly larger than
-- the pill itself. The art keeps the canvas proportions (never stretched) and
-- is sized so the pill lines up with the 300x72 hit box. If a re-exported PNG
-- has a different canvas, these numbers are the only ones to change.
local TOP_SLOT_SIZE = Vector2.new(300, 72)   -- the hit box of each top button
local TOP_ART_ASPECT = 3.05   -- canvas width / canvas height
local TOP_ART_WIDTH = 1.06    -- canvas width as a share of the hit box width

local TOP_HOVER_SCALE = 1.025
local TOP_PRESS_SCALE = 0.965

local TOP_MOTION = {
	Hover = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Press = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Release = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Dip = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Settle = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Fade = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Reveal = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Glint = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
}

local function reducedMotion()
	return player:GetAttribute("ReduceMotion") == true
end

-- Returns the button (named as before, so the tutorial still finds it), its
-- artwork, the UIScale used for state-change transitions and the text
-- fallback. Hover and press live on a separate
-- UIScale on the button, so the two never fight. With glint, one light sweep
-- crosses the button each time the pointer moves onto it.
local function buildTopActionButton(slot, name, fallbackText, fallbackColor, glint)
	-- The artwork carries its own shadow and outline; the drawn slot shadow
	-- would show as a dark rectangle behind it.
	local slotShadow = slot:FindFirstChild("Shadow")
	if slotShadow then slotShadow.Visible = false end

	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.fromScale(0.5, 0.5)
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.ZIndex = 2
	-- ButtonPressClient skips buttons that animate their own press.
	btn:SetAttribute("OwnPressAnimation", true)

	local interactionScale = Instance.new("UIScale")
	interactionScale.Name = "InteractionScale"
	interactionScale.Parent = btn

	local visual = Instance.new("Frame")
	visual.Name = "Visual"
	visual.AnchorPoint = Vector2.new(0.5, 0.5)
	visual.Position = UDim2.fromScale(0.5, 0.5)
	visual.Size = UDim2.fromScale(1, 1)
	visual.BackgroundTransparency = 1
	visual.ZIndex = 2
	visual.Parent = btn

	local transitionScale = Instance.new("UIScale")
	transitionScale.Name = "TransitionScale"
	transitionScale.Parent = visual

	local art = Instance.new("ImageLabel")
	art.Name = "ButtonImage"
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(TOP_ART_WIDTH, TOP_ART_WIDTH * TOP_SLOT_SIZE.X / TOP_SLOT_SIZE.Y / TOP_ART_ASPECT)
	art.BackgroundTransparency = 1
	art.BorderSizePixel = 0
	art.Active = false                    -- the button keeps the click
	art.Image = ""                        -- set once the artwork has resolved
	art.ScaleType = Enum.ScaleType.Fit
	art.ImageTransparency = 1             -- revealed once the art is cached
	art.ZIndex = 3
	art.Parent = visual

	-- Shown only if the artwork failed to load, so the control is never an
	-- invisible hit box.
	local fallback = Instance.new("TextLabel")
	fallback.Name = "FallbackLabel"
	fallback.Size = UDim2.fromScale(1, 1)
	fallback.BackgroundColor3 = fallbackColor
	fallback.Text = fallbackText
	fallback.Font = FONT
	fallback.TextColor3 = THEME.Text
	fallback.TextScaled = true
	fallback.Visible = false
	fallback.ZIndex = 3
	fallback.Parent = visual
	corner(fallback, 0.28)
	outline(fallback, Enum.ApplyStrokeMode.Contextual, 2.5)
	local fallbackPadding = Instance.new("UIPadding")
	fallbackPadding.PaddingTop = UDim.new(0.18, 0)
	fallbackPadding.PaddingBottom = UDim.new(0.18, 0)
	fallbackPadding.Parent = fallback

	-- The glint is clipped to the pill by a rounded CanvasGroup, so the light
	-- never shows outside the button's own shape.
	local glintMask, glintGradient, glintTween
	if glint then
		glintMask = Instance.new("CanvasGroup")
		glintMask.Name = "Glint"
		glintMask.AnchorPoint = Vector2.new(0.5, 0.5)
		glintMask.Position = UDim2.fromScale(0.5, 0.5)
		glintMask.Size = UDim2.new(1, -8, 1, -8)
		glintMask.BackgroundTransparency = 1
		glintMask.BorderSizePixel = 0
		glintMask.Visible = false
		glintMask.ZIndex = 4
		glintMask.Parent = visual
		corner(glintMask, 0.5)

		local band = Instance.new("Frame")
		band.Name = "Band"
		band.Size = UDim2.fromScale(1, 1)
		band.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		band.BorderSizePixel = 0
		band.ZIndex = 4
		band.Parent = glintMask

		glintGradient = Instance.new("UIGradient")
		glintGradient.Rotation = 20
		glintGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 0.4),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		glintGradient.Offset = Vector2.new(-1, 0)
		glintGradient.Parent = band
	end

	local function playGlint()
		if not glintGradient or reducedMotion() then return end
		if glintTween then glintTween:Cancel() end
		glintGradient.Offset = Vector2.new(-1, 0)
		glintMask.Visible = true
		glintTween = TweenService:Create(glintGradient, TOP_MOTION.Glint, { Offset = Vector2.new(1, 0) })
		glintTween.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed then
				glintMask.Visible = false
			end
		end)
		glintTween:Play()
	end

	local hover, down = false, false
	local scaleTween

	local function settle(info)
		if scaleTween then scaleTween:Cancel() end
		local goal = if down then TOP_PRESS_SCALE elseif hover then TOP_HOVER_SCALE else 1
		if reducedMotion() then
			interactionScale.Scale = 1
			return
		end
		scaleTween = TweenService:Create(interactionScale, info, { Scale = goal })
		scaleTween:Play()
	end

	local function isPress(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
	end

	btn.MouseEnter:Connect(function()
		hover = true
		playHoverSound()
		settle(TOP_MOTION.Hover)
		playGlint()
	end)
	btn.MouseLeave:Connect(function()
		hover, down = false, false
		settle(TOP_MOTION.Hover)
	end)
	btn.InputBegan:Connect(function(input)
		if isPress(input) then
			down = true
			settle(TOP_MOTION.Press)
		end
	end)
	btn.InputEnded:Connect(function(input)
		if isPress(input) and down then
			down = false
			settle(TOP_MOTION.Release)
		end
	end)
	btn.Destroying:Connect(function()
		if scaleTween then scaleTween:Cancel() end
		if glintTween then glintTween:Cancel() end
	end)

	btn.Parent = slot
	return btn, art, transitionScale, fallback
end

local upgradeSlot = makeSlot(actionBar, "Upgrade", UDim2.fromOffset(TOP_SLOT_SIZE.X, TOP_SLOT_SIZE.Y), 1)
local lockSlot = makeSlot(actionBar, "LockBase", UDim2.fromOffset(TOP_SLOT_SIZE.X, TOP_SLOT_SIZE.Y), 2)

local upgradeBtn, upgradeArt, _, upgradeFallback =
	buildTopActionButton(upgradeSlot, "UPGRADE", "UPGRADE", THEME.Upgrade, true)

local lockBaseBtn, lockBaseArt, lockBaseTransition, lockBaseFallback =
	buildTopActionButton(lockSlot, "LOCK BASE", "LOCK BASE", THEME.LockBase, false)

-- Puts one resolved artwork on a button. The label is always TOP_ART_WIDTH
-- of the hit box wide; its height is set from the picture's own shape, so
-- Fit fills that width and nothing is squashed or shrunk. A decal's
-- thumbnail arrives as a square with the button fitted across it, so for
-- that the label is square (and overhangs the hit box invisibly above and
-- below - only the button itself has any pixels).
local function setButtonArt(art, resolved)
	art.Image = if resolved then resolved.url else ""
	local aspect = if resolved and resolved.square then 1 else TOP_ART_ASPECT
	art.Size = UDim2.fromScale(TOP_ART_WIDTH, TOP_ART_WIDTH * TOP_SLOT_SIZE.X / TOP_SLOT_SIZE.Y / aspect)
end

-- The live countdown. A separate chip just right of the button, so the clean
-- PROTECTED artwork is never covered and the button never changes size.
local TIMER_INK = Color3.fromRGB(14, 24, 64)

local protectionTimer = Instance.new("Frame")
protectionTimer.Name = "ProtectionTimer"
protectionTimer.AnchorPoint = Vector2.new(0, 0.5)
protectionTimer.Position = UDim2.new(1, 8, 0.5, 0)
protectionTimer.Size = UDim2.fromOffset(78, 42)
protectionTimer.BackgroundColor3 = Color3.fromRGB(26, 64, 156)
protectionTimer.BorderSizePixel = 0
protectionTimer.Visible = false
protectionTimer.ZIndex = 4
protectionTimer.Parent = lockBaseBtn
corner(protectionTimer, 0.5)

local timerBorder = Instance.new("UIStroke")
timerBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
timerBorder.Color = TIMER_INK
timerBorder.Thickness = 3
timerBorder.Parent = protectionTimer

local timerShade = Instance.new("UIGradient")
timerShade.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 205, 235))
timerShade.Rotation = 90
timerShade.Parent = protectionTimer

local timerText = Instance.new("TextLabel")
timerText.Name = "Time"
timerText.AnchorPoint = Vector2.new(0.5, 0.5)
timerText.Position = UDim2.fromScale(0.5, 0.5)
timerText.Size = UDim2.new(1, -12, 1, -8)
timerText.BackgroundTransparency = 1
timerText.Font = FONT
timerText.Text = ""
timerText.TextColor3 = THEME.Text
timerText.TextScaled = true
timerText.ZIndex = 5
timerText.Parent = protectionTimer

local timerTextStroke = Instance.new("UIStroke")
timerTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
timerTextStroke.Color = TIMER_INK
timerTextStroke.Thickness = 2.5
timerTextStroke.Parent = timerText

local timerTextLimit = Instance.new("UITextSizeConstraint")
timerTextLimit.MaxTextSize = 28
timerTextLimit.Parent = timerText

-- ===== left menu =====
local menu = Instance.new("Frame")
menu.Name = "SideMenu"
menu.AnchorPoint = Vector2.new(0, 0.5)
menu.Position = UDim2.new(0, 20, 0.5, 0)
menu.Size = UDim2.fromOffset(184, 10)
menu.AutomaticSize = Enum.AutomaticSize.Y
menu.BackgroundTransparency = 1
menu.Parent = gui

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 12)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = menu

local function addMenuButton(text, color, iconId, glimmer, order)
	local slot = makeSlot(menu, text, UDim2.fromOffset(184, 76), order)
	local button = buildButton(text, color, iconId, glimmer)
	button.Parent = slot
	local oldShadow=slot:FindFirstChild("Shadow");if oldShadow then oldShadow.Visible=false end

	button.Activated:Connect(function()
		print("[HUD] clicked:", text)
	end)

	return button
end

-- Side menu artwork: ReplicatedStorage > UIAssets > NavIcons.
local function navIcon(name)
	local map = UIAssets.NavIcons
	return (map and map[name]) or ""
end

addMenuButton("Store", THEME.Store, navIcon("Store"), true, 1)
addMenuButton("Leaderboards", THEME.Leaderboards, navIcon("Leaderboards"), false, 2)
addMenuButton("Index", THEME.Index, navIcon("Index"), false, 3)
addMenuButton("Rebirth", THEME.Rebirth, navIcon("Rebirth"), false, 4)

-- Inventory (InventoryClient opens it). Same button, same slot, same click:
-- only its icon changed, from the drawn chest to the chest artwork.
addMenuButton("Inventory", THEME.Inventory, navIcon("Inventory"), false, 5)

-- ===== right playtime awards =====
local playSlot = Instance.new("Frame")
playSlot.Name = "PlaytimeSlot"
playSlot.AnchorPoint = Vector2.new(1, 0.5)
playSlot.Position = UDim2.new(1, -14, 0.46, 0)
playSlot.Size = UDim2.fromOffset(108, 108)
playSlot.BackgroundTransparency = 1
playSlot.Parent = gui

local playShadow = addShadow(playSlot)

local playBtn = buildButton("Playtime Awards", THEME.Playtime, "rbxassetid://126373776467964", false)
playBtn.Parent = playSlot

-- One graphic for the whole button, when UIAssets carries one. The drawn
-- button stays underneath and comes back if the image never arrives, so a
-- missing or slow id can never leave an empty square here.
do
	-- The id is carried here as well as in UIAssets, so an older copy of the
	-- module cannot stop the swap happening.
	local artId = UIAssets.PlaytimeButton
	if type(artId) ~= "string" or artId == "" then
		artId = "rbxassetid://124105198585397"
	end

	print(("[MainHUD] build 2026-09-25  playtime art: %s"):format(artId))

	if artId ~= "" then
		-- 1.33, measured off the rendered button (200 x 150 on screen), not
		-- 1.22. With Fit and a slot that is too wide, the artwork was
		-- width-bound and sat in a 9px vertical letterbox - which is why the
		-- badge, positioned against the SLOT, kept landing above the visible
		-- button instead of on it. Matching the ratio removes the letterbox,
		-- so the slot and the button are now the same rectangle.
		local ART_RATIO = 1.33          -- width / height of the button artwork
		-- ===== THE SIZE KNOB =====
		-- This one number is the whole size of the Playtime Awards button.
		-- The original was 108. The icon and the lettering are part of the
		-- same graphic, so they scale with it and nothing needs re-centring.
		-- Change it and nothing else; the print below confirms what took.
		local ART_HEIGHT = 206
		playSlot.Size = UDim2.fromOffset(math.floor(ART_HEIGHT * ART_RATIO), ART_HEIGHT)
		-- Printed so the size can be confirmed from the output rather than by
		-- eye. If this line says anything other than 214x176, the copy of
		-- MainHUD that is running is not this one.
		print(("[MainHUD] playtime slot %dx%d"):format(
			playSlot.Size.X.Offset, playSlot.Size.Y.Offset))

		local art = Instance.new("ImageLabel")
		art.Name = "PlaytimeArtwork"
		art.BackgroundTransparency = 1
		art.BorderSizePixel = 0
		art.Active = false
		art.Size = UDim2.fromScale(1, 1)
		art.Image = artId
		art.ScaleType = Enum.ScaleType.Fit
		art.ImageColor3 = Color3.new(1, 1, 1)
		-- Drawn from the first frame, on top of the drawn button. Roblox only
		-- fetches an image for a label it is actually rendering, so a hidden or
		-- fully transparent label may never load at all - which is exactly why
		-- the earlier attempts never swapped. Until the picture arrives this
		-- label draws nothing, so the drawn button underneath is what shows.
		art.ZIndex = 8
		art.Parent = playBtn

		local function useArtwork(on)
			art.ImageTransparency = 0
			for _, child in ipairs(playBtn:GetChildren()) do
				if child ~= art and (child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("ImageLabel")) then
					child.Visible = not on
				end
			end
			art.Visible = true
			playBtn.BackgroundTransparency = if on then 1 else 0
			local edge = playBtn:FindFirstChildOfClass("UIStroke")
			if edge then edge.Transparency = if on then 1 else 0 end
			-- The drawn button's own drop shadow would otherwise sit behind the
			-- artwork as a dark rectangle, since the artwork carries its own.
			if playShadow then playShadow.Visible = not on end
		end

		task.spawn(function()
			local deadline = os.clock() + 12
			while os.clock() < deadline and not art.IsLoaded do
				task.wait(0.2)
			end
			if not art.IsLoaded then
				-- Keep watching for ten minutes: a fresh upload can be held in
				-- moderation long after the game has started.
				local giveUp = os.clock() + 600
				while os.clock() < giveUp and not art.IsLoaded do
					task.wait(3)
				end
			end
			print(("[MainHUD] playtime button art %s -> %s"):format(
				artId, if art.IsLoaded then "LOADED, drawn button hidden"
					else "not confirmed loaded; artwork is on screen with the drawn button behind it"))
			if art.IsLoaded then
				useArtwork(true)
			end
		end)
	end
end

local shadowDown = playShadow.Position
local shadowUp = shadowDown - UDim2.fromOffset(0, 8)

playBtn.MouseEnter:Connect(function()
	TweenService:Create(playShadow, POP_IN, { Position = shadowUp }):Play()
end)

playBtn.MouseLeave:Connect(function()
	TweenService:Create(playShadow, POP_OUT, { Position = shadowDown }):Play()
end)

-- ===== upgrade popup =====
-- One composed cosmic window: illustrated header, three cards on top and two
-- wide cards below, all visible at once. Only the look lives here - prices,
-- levels, MAXED, the rebirth caps and every purchase still come from
-- UpgradeConfig and the server's BuyUpgrade remote, exactly as before.
--
-- The finished pictures (title, arrow, the five hero icons, the five name
-- labels and the MAXED button) come from UIAssets.UpgradeArt. The window
-- does not open until they have been fetched, so it never shows a half-drawn
-- card, and no drawn stand-in is ever put under or in place of them.
local GuiManager = require(ReplicatedStorage:WaitForChild("GuiManager"))

local UiResponsive do
	local module = ReplicatedStorage:FindFirstChild("UiResponsive")
	local ok, result = pcall(function() return module and require(module) end)
	UiResponsive = if ok and type(result) == "table" then result else nil
end

-- Exposed to the rest of the HUD (the UPGRADE button and the gamepad back).
local openUpgradePopup, closeUpgradePopup, refreshUpgradeCards, dataFailed, statusLabel

-- Built inside its own function: a Luau function may hold at most 200
-- locals, and this window's helpers would push the HUD's main chunk past it.
local function buildUpgradeWindow()
	local ART = UIAssets.UpgradeArt or {}
	local ICONS = ART.Icons or {}
	local LABELS = ART.Labels or {}

	local INK = Color3.fromRGB(12, 18, 58)          -- the navy every outline uses
	local WHITE = Color3.fromRGB(255, 255, 255)
	local CYAN = Color3.fromRGB(90, 225, 255)
	local GOLD = Color3.fromRGB(255, 205, 50)
	local SUBTITLE = "Spend Stardust to upgrade your black hole base!"

	-- Everything is laid out in design pixels on a fixed 1340 x 940 panel, and
	-- one UIScale fits the whole panel to the screen, so it always scales as a
	-- single unit and nothing reflows or scrolls.
	local PANEL = Vector2.new(1340, 940)
	local FIT = Vector2.new(1430, 1020)             -- panel plus the arrow, stars and clouds that overhang it
	local INSET = 22                                -- frame thickness
	local CW, CH = PANEL.X - INSET * 2, PANEL.Y - INSET * 2

	local HEADER_H = 178
	local COL_GAP, ROW_GAP = 18, 16
	local TOP_PAD, BOTTOM_PAD = 26, 50              -- the bottom row sits in a little, clear of the clouds
	local TOP_Y, TOP_H = HEADER_H + 4, 408
	local BOTTOM_Y = TOP_Y + TOP_H + ROW_GAP
	local BOTTOM_H = CH - 14 - BOTTOM_Y

	-- Button pills: the same shape as the supplied MAXED picture, so a card
	-- never changes shape when it changes state.
	local TOP_BUTTON = Vector2.new(290, 66)
	local WIDE_BUTTON = Vector2.new(272, 62)

	-- Rendering layers. Only siblings compare ZIndex, so each value is what
	-- that kind of object uses inside its own parent.
	local Z = {
		Halo = 1, Frame = 2, Bump = 7, Content = 8, Clouds = 9, Decor = 40,  -- in the panel
		Sky = 2, Plate = 3, Card = 10, Header = 20,                         -- in the interior
		Close = 30,                                                         -- in the header
		CardBack = 11, Glow = 14, Hero = 15, TitleBar = 16, Text = 18, Button = 20, -- in a card
	}

	-- Which card goes where. UpgradeConfig ids, not display names, so saved
	-- levels keep their keys.
	local TOP_ROW = { "SpawnTier", "MaxSpawn", "LockBase" }
	local BOTTOM_ROW = { "CoinDropRate", "CurrencyMagnet" }

	local COPY = {
		SpawnTier = "Raise lower-tier holes and spawn higher tiers!",
		MaxSpawn = "Room for one more black hole on your plot!",
		LockBase = "Improve your base lock time!",
		CoinDropRate = "Currency drops appear more often!",
		CurrencyMagnet = "Increase currency attraction range!",
	}

	-- The light each card's artwork throws onto its own card.
	local CARD_LIGHT = {
		SpawnTier = { Color3.fromRGB(120, 80, 255), Color3.fromRGB(60, 170, 255) },
		MaxSpawn = { Color3.fromRGB(170, 70, 255), Color3.fromRGB(240, 80, 220) },
		LockBase = { Color3.fromRGB(50, 200, 255), Color3.fromRGB(80, 120, 255) },
		CoinDropRate = { Color3.fromRGB(150, 80, 255), Color3.fromRGB(255, 200, 60) },
		CurrencyMagnet = { Color3.fromRGB(60, 210, 255), Color3.fromRGB(255, 170, 70) },
	}

	local MOTION = {
		CardHover = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Hover = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Press = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Release = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		Squash = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Pop = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		Burst = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Flash = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	}

	local function reduced()
		return player:GetAttribute("ReduceMotion") == true
	end

	-- ---------- small drawing helpers ----------
	local function make(className, props, parent)
		local object = Instance.new(className)
		for key, value in pairs(props) do
			object[key] = value
		end
		object.Parent = parent
		return object
	end

	local function box(parent, name, x, y, w, h, color, z, props)
		local f = make("Frame", {
			Name = name,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = color or WHITE,
			BorderSizePixel = 0,
			ZIndex = z or 1,
		}, parent)
		if props then
			for key, value in pairs(props) do f[key] = value end
		end
		return f
	end

	local function round(parent, px)
		return make("UICorner", { CornerRadius = UDim.new(0, px) }, parent)
	end

	local function pill(parent)
		return make("UICorner", { CornerRadius = UDim.new(1, 0) }, parent)
	end

	local function gradient(parent, stops, rotation)
		local keys = {}
		for i, stop in ipairs(stops) do
			keys[i] = ColorSequenceKeypoint.new(stop[1], stop[2])
		end
		return make("UIGradient", { Color = ColorSequence.new(keys), Rotation = rotation or 90 }, parent)
	end

	local function stroke(parent, color, thickness, mode, transparency)
		return make("UIStroke", {
			Color = color or INK,
			Thickness = thickness or 3,
			ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border,
			Transparency = transparency or 0,
		}, parent)
	end

	-- Every card label's size limits, so the minimum can follow the window's
	-- scale (refreshUpgradeScale): on a phone the boxes are small, and a fixed
	-- minimum made text spill out of its box and overlap the next line.
	local textLimits = {}
	local function text(parent, name, str, x, y, w, h, size, color, z, props)
		local label = make("TextLabel", {
			Name = name,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundTransparency = 1,
			Text = str,
			Font = FONT,
			TextColor3 = color or WHITE,
			TextScaled = true,
			TextWrapped = true,
			ZIndex = z or 5,
		}, parent)
		local limit = make("UITextSizeConstraint", { MaxTextSize = size, MinTextSize = math.floor(size * 0.55) }, label)
		textLimits[limit] = size
		if props then
			for key, value in pairs(props) do label[key] = value end
		end
		return label
	end

	-- Artwork is always Fit: the whole picture shows, never stretched or cropped.
	local function image(parent, name, id, cx, cy, w, h, z, props)
		local img = make("ImageLabel", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(w, h),
			BackgroundTransparency = 1,
			Image = id or "",
			ScaleType = Enum.ScaleType.Fit,
			Active = false,
			ZIndex = z or 3,
		}, parent)
		if props then
			for key, value in pairs(props) do img[key] = value end
		end
		return img
	end

	-- A soft round light. GUI has no radial gradient, so it is eight faint
	-- discs, each a little smaller than the last: the light builds up towards
	-- the middle and no single disc edge is visible.
	local function glow(parent, cx, cy, radius, color, strength, z)
		local alpha = 1 - 0.075 * (strength or 1)
		local holder = make("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(radius * 2, radius * 2),
			BackgroundTransparency = 1,
			ZIndex = z or 2,
		}, parent)
		for i = 1, 8 do
			local size = 1 - (i - 1) * 0.11
			local disc = make("Frame", {
				Name = "Ring" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(size, size),
				BackgroundColor3 = color,
				BackgroundTransparency = alpha,
				BorderSizePixel = 0,
				ZIndex = z or 2,
			}, holder)
			pill(disc)
		end
		return holder
	end

	-- A four-point glint: two thin rays that fade out towards their tips, a
	-- bright core and a faint halo. Drawn, so it can be any colour. Twinkling
	-- ones are collected with how far they may shrink.
	local RAY = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.5),
		NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.7, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	local twinkles = {}
	local function sparkle(parent, cx, cy, size, color, z, twinkle)
		z = z or 4
		local holder = make("Frame", {
			Name = "Sparkle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			ZIndex = z,
		}, parent)
		local halo = make("Frame", {
			Name = "Halo",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.6, 0.6),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
			ZIndex = z,
		}, holder)
		pill(halo)
		for _, vertical in ipairs({ true, false }) do
			local ray = make("Frame", {
				Name = "Ray",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = if vertical then UDim2.fromScale(0.2, 1) else UDim2.fromScale(1, 0.2),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = z,
			}, holder)
			pill(ray)
			make("UIGradient", { Rotation = if vertical then 90 else 0, Transparency = RAY }, ray)
		end
		local core = make("Frame", {
			Name = "Core",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.24, 0.24),
			BackgroundColor3 = color:Lerp(WHITE, 0.7),
			BorderSizePixel = 0,
			Rotation = 45,
			ZIndex = z + 1,
		}, holder)
		make("UICorner", { CornerRadius = UDim.new(0.3, 0) }, core)
		local scale = make("UIScale", {}, holder)
		if twinkle then
			table.insert(twinkles, { scale = scale, low = 0.6 })
		end
		return holder
	end

	-- The game's glossy gold star artwork for the big accents; a gold glint
	-- if that art is not set. Big stars only ever dim a little.
	local function goldStar(parent, cx, cy, size, z)
		if (ART.GoldStar or "") == "" then
			return sparkle(parent, cx, cy, size, GOLD, z, true)
		end
		local star = image(parent, "GoldStar", ART.GoldStar, cx, cy, size, size, z)
		table.insert(twinkles, { scale = make("UIScale", {}, star), low = 0.88 })
		return star
	end

	local function dot(parent, cx, cy, size, color, alpha, z)
		local d = make("Frame", {
			Name = "Dot",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color,
			BackgroundTransparency = alpha or 0,
			BorderSizePixel = 0,
			ZIndex = z or 2,
		}, parent)
		pill(d)
		return d
	end

	-- Scatter of tiny stars. Seeded, so the sky is the same every session.
	local function starfield(parent, w, h, count, seed, z)
		local rng = Random.new(seed)
		for _ = 1, count do
			local tint = if rng:NextNumber() < 0.3 then CYAN else WHITE
			dot(parent, rng:NextInteger(6, w - 6), rng:NextInteger(6, h - 6),
				rng:NextInteger(2, 3), tint, rng:NextNumber(0.35, 0.75), z)
		end
	end

	local GOLD_FILL = {
		{ 0, Color3.fromRGB(255, 250, 170) }, { 0.45, Color3.fromRGB(255, 205, 40) },
		{ 1, Color3.fromRGB(255, 130, 20) },
	}

	-- Gold lettering with navy extrusion and a thin cyan separation line
	-- behind it: the title only if UpgradeArt.Title is left empty.
	local function goldText(parent, name, str, x, y, w, h, size, z, alignment)
		local layers = {
			{ offset = 0, color = CYAN, strokeColor = CYAN, strokeWidth = 9, transparency = 0.35 },
			{ offset = 5, color = INK, strokeColor = INK, strokeWidth = 6 },
			{ offset = 0, color = WHITE, strokeColor = INK, strokeWidth = 5, gold = true },
		}
		local top
		for i, layer in ipairs(layers) do
			local label = text(parent, name .. (if layer.gold then "" else "Layer" .. i), str,
				x, y + layer.offset, w, h, size, layer.color, z + i - 1)
			label.TextXAlignment = alignment or Enum.TextXAlignment.Center
			label.TextWrapped = false
			stroke(label, layer.strokeColor, layer.strokeWidth, Enum.ApplyStrokeMode.Contextual, layer.transparency)
			if layer.gold then
				gradient(label, GOLD_FILL, 90)
				top = label
			end
		end
		return top
	end

	-- ---------- root ----------
	local upgradePopup = make("Frame", {
		Name = "UpgradePopup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL.X, PANEL.Y),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 21,
	}, gui)

	-- GuiManager owns a UIScale on the root for open/close; the fit-to-screen
	-- scale lives one level down, because an object only honours one UIScale.
	local panel = make("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL.X, PANEL.Y),
		BackgroundTransparency = 1,
		ZIndex = 21,
	}, upgradePopup)
	local fitScale = make("UIScale", { Name = "ResponsiveScale" }, panel)

	-- ---------- layered frame ----------
	-- Soft blue light outside, then navy structure -> electric blue -> cyan
	-- light -> a thin navy seam, then the cosmic interior. The raised dome
	-- behind the arrow (top left) is drawn with the same layers at the same
	-- ZIndex as the frame, so the two outlines merge into one silhouette.
	local BUMP = { x = 56, y = -40, w = 236, h = 156, radius = 72 }
	local CONTENT_TOP = Color3.fromRGB(8, 46, 178)

	-- Every drawn frame piece is listed, so the supplied background picture
	-- can replace the whole drawn frame (never a second frame under it).
	local drawnFrame = {}
	local function frameLayer(name, inset, color, radius, z, alpha)
		local main = box(panel, name, inset, inset, PANEL.X - inset * 2, PANEL.Y - inset * 2, color, z,
			{ BackgroundTransparency = alpha or 0 })
		round(main, radius)
		local bump = box(panel, name .. "Dome", BUMP.x + inset, BUMP.y + inset, BUMP.w - inset * 2, BUMP.h - inset * 2, color, z,
			{ BackgroundTransparency = alpha or 0 })
		round(bump, math.max(BUMP.radius - inset, 12))
		table.insert(drawnFrame, main)
		table.insert(drawnFrame, bump)
		return main, bump
	end

	frameLayer("Halo1", -18, Color3.fromRGB(0, 140, 255), 68, Z.Halo, 0.8)
	frameLayer("Halo2", -9, Color3.fromRGB(30, 180, 255), 59, Z.Halo, 0.5)
	frameLayer("Structure", 0, INK, 50, Z.Frame)
	-- A bright cyan line on the outside of the blue band as well as inside it.
	frameLayer("OuterLight", 3, Color3.fromRGB(90, 215, 255), 47, Z.Frame)
	local electric, electricDome = frameLayer("Electric", 5, WHITE, 45, Z.Frame + 1)
	gradient(electric, { { 0, Color3.fromRGB(25, 125, 255) }, { 0.5, Color3.fromRGB(5, 100, 250) }, { 1, Color3.fromRGB(0, 78, 238) } })
	-- The dome's own gradient settles on the frame's top colour before the
	-- two meet, so there is no seam where they join.
	gradient(electricDome, { { 0, Color3.fromRGB(70, 160, 255) }, { 0.3, Color3.fromRGB(25, 125, 255) }, { 1, Color3.fromRGB(25, 125, 255) } })
	local cyanLayer = frameLayer("Cyan", 15, Color3.fromRGB(110, 230, 255), 35, Z.Frame + 2)
	do
		-- Specular: the top edge catches the light, the bottom does not.
		local spec = stroke(cyanLayer, WHITE, 1.5, Enum.ApplyStrokeMode.Border)
		make("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.3, 0.85),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, spec)
	end
	frameLayer("Seam", 19, Color3.fromRGB(6, 22, 96), 31, Z.Frame + 3)
	-- Dome interior, the same blue as the top of the header it opens into.
	local domeInside = box(panel, "DomeInside", BUMP.x + INSET, BUMP.y + INSET, BUMP.w - INSET * 2, BUMP.h - INSET * 2, CONTENT_TOP, Z.Bump)
	round(domeInside, BUMP.radius - INSET)
	table.insert(drawnFrame, domeInside)

	local content = box(panel, "Content", INSET, INSET, CW, CH, WHITE, Z.Content)
	round(content, 28)
	gradient(content, {
		{ 0, CONTENT_TOP }, { 0.3, Color3.fromRGB(4, 30, 142) },
		{ 1, Color3.fromRGB(2, 20, 108) },
	})

	-- Window background: the supplied picture (UpgradeArt.Background) is the
	-- whole window, frame included. Once fetched it is shown at the window's
	-- own size (never cropped or enlarged) and the drawn frame is hidden, so
	-- there is only one frame. Without it, drawn nebula light and a sky.
	local backdrop = make("ImageLabel", {
		Name = "Backdrop",
		Size = UDim2.fromOffset(PANEL.X, PANEL.Y),
		BackgroundTransparency = 1,
		Image = "",
		ScaleType = Enum.ScaleType.Stretch,
		Active = false,
		Visible = false,
		ZIndex = Z.Frame,
	}, panel)
	local sky = make("Frame", {
		Name = "Sky",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = Z.Sky,
	}, content)
	glow(sky, 170, 580, 320, Color3.fromRGB(90, 60, 255), 0.45, Z.Sky)
	glow(sky, 860, 440, 420, Color3.fromRGB(0, 110, 255), 0.9, Z.Sky)
	starfield(sky, CW, CH, 40, 11, Z.Sky)

	-- Header plate: a lighter band the header sits on, with a lit edge
	-- underneath that divides it from the cards.
	do
		local plate = box(content, "HeaderPlate", 0, 0, CW, HEADER_H - 2, Color3.fromRGB(0, 100, 255), Z.Plate,
			{ BackgroundTransparency = 0.82 })
		round(plate, 28)
		local divider = box(content, "HeaderDivider", 24, HEADER_H - 3, CW - 48, 2, Color3.fromRGB(130, 225, 255), Z.Plate + 1)
		table.insert(drawnFrame, plate)
		table.insert(drawnFrame, divider)
		make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.12, 0.25),
				NumberSequenceKeypoint.new(0.88, 0.25), NumberSequenceKeypoint.new(1, 1),
			}),
		}, divider)
	end
	-- Match the dome to the plate so the two read as one lit surface.
	domeInside.BackgroundColor3 = CONTENT_TOP:Lerp(Color3.fromRGB(0, 100, 255), 0.18)

	-- ---------- header ----------
	local header = make("Frame", {
		Name = "Header",
		Size = UDim2.fromOffset(CW, HEADER_H),
		BackgroundTransparency = 1,
		ZIndex = Z.Header,
	}, content)

	-- The arrow sits in the dome, rising a little above the frame. Its slot is
	-- filled once the artwork has been fetched (see "artwork" below).
	local ARROW = { x = BUMP.x + BUMP.w / 2 - INSET, y = 40, size = 196 }
	local arrowSlot = make("Frame", {
		Name = "HeroArrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(ARROW.x, ARROW.y),
		Size = UDim2.fromOffset(ARROW.size, ARROW.size),
		BackgroundTransparency = 1,
		ZIndex = Z.Header + 1,
	}, header)

	-- "Upgrade" lettering to the right of the arrow.
	local TITLE = { x = 470, y = 70, w = 440, h = 147 }
	local titleSlot = make("Frame", {
		Name = "TitleSlot",
		Size = UDim2.fromOffset(CW, HEADER_H),
		BackgroundTransparency = 1,
		ZIndex = Z.Header + 1,
	}, header)

	statusLabel = text(header, "Subtitle", SUBTITLE, 282, 139, 680, 32, 27, Color3.fromRGB(165, 230, 255), Z.Header + 2)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	stroke(statusLabel, INK, 3, Enum.ApplyStrokeMode.Contextual)

	-- Ringed planet. GUI corners only make capsules, so the ring is a band
	-- of overlapping dots laid along a true ellipse: dots on the near half sit
	-- in front of the ball, the rest behind it.
	local PLANET = { x = 1030, y = 80, w = 290, h = 180 }
	local planetHolder = make("Frame", {
		Name = "Planet",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(PLANET.x, PLANET.y),
		Size = UDim2.fromOffset(PLANET.w, PLANET.h),
		BackgroundTransparency = 1,
		ZIndex = Z.Header + 1,
	}, header)
	planetHolder.Visible = false   -- no planet in this window

	-- A few intentional starbursts, not a scatter: two by the arrow, a small
	-- group after the title, two by the close button.
	for _, s in ipairs({
		{ 30, 104, 36, GOLD }, { 64, 140, 22, GOLD }, { 240, 100, 32, GOLD },
		{ 784, 28, 42, GOLD }, { 832, 84, 30, GOLD }, { 716, 46, 20, WHITE },
		{ 900, 60, 18, WHITE }, { 1100, 110, 30, GOLD },
		{ 1214, 152, 20, WHITE }, { 648, 22, 16, CYAN },
		}) do
		sparkle(header, s[1], s[2], s[3], s[4], Z.Header + 6, true)
	end

	-- Close button: the supplied X artwork (UpgradeArt.Close), placed once it
	-- has been fetched; the button itself is always there.
	local closeBtn = make("TextButton", {
		Name = "CloseButton",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(CW - 58, 62),
		Size = UDim2.fromOffset(92, 92),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = Z.Close,
	}, header)
	closeBtn:SetAttribute("OwnPressAnimation", true)
	do
		local scale = make("UIScale", {}, closeBtn)
		closeBtn.MouseEnter:Connect(function()
			playHoverSound()
			TweenService:Create(scale, MOTION.Hover, { Scale = 1.08 }):Play()
		end)
		closeBtn.MouseLeave:Connect(function()
			TweenService:Create(scale, MOTION.Hover, { Scale = 1 }):Play()
		end)
		closeBtn.MouseButton1Down:Connect(function()
			TweenService:Create(scale, MOTION.Press, { Scale = 0.94 }):Play()
		end)
		closeBtn.Activated:Connect(function()
			TweenService:Create(scale, MOTION.Release, { Scale = 1 }):Play()
			closeUpgradePopup()
		end)
	end

	-- ---------- decorations that overhang the frame ----------
	-- Clouds sit on the frame's lower corners (in front of the frame, beside
	-- the inset bottom row, never over a card). Gold stars sit on the frame
	-- edge beside the cards. None of it is Active, so none of it takes clicks.
	local decor = make("Frame", {
		Name = "Decor",
		Size = UDim2.fromOffset(PANEL.X, PANEL.Y),
		BackgroundTransparency = 1,
		ZIndex = Z.Decor,
	}, panel)
	local clouds = make("Frame", {
		Name = "Clouds",
		Size = UDim2.fromOffset(PANEL.X, PANEL.Y),
		BackgroundTransparency = 1,
		ZIndex = Z.Clouds,
	}, panel)

	-- Overlapping puffs hugging a lower corner of the frame: one outline
	-- round all of them, one pale-blue fill, a white sheen on each puff and a
	-- violet shade along the base, so it reads as a single cloud. x is the
	-- frame's outer edge; the bank never reaches the inset bottom row.
	local function cloudBank(x, flip)
		local dir = if flip then -1 else 1
		if (ART.Cloud or "") ~= "" then
			image(clouds, "Cloud", ART.Cloud, x + 10 * dir, PANEL.Y - 80, 180, 200, Z.Clouds)
			return
		end
		local puffs = {
			{ x - 6 * dir, PANEL.Y - 38, 112 },
			{ x + 34 * dir, PANEL.Y - 18, 80 },
			{ x - 20 * dir, PANEL.Y - 104, 86 },
			{ x + 6 * dir, PANEL.Y - 154, 54 },
			{ x + 64 * dir, PANEL.Y + 4, 52 },
		}
		glow(clouds, x + 10 * dir, PANEL.Y - 70, 120, Color3.fromRGB(120, 190, 255), 0.6, Z.Clouds)
		for pass = 1, 2 do
			for _, p in ipairs(puffs) do
				local puff = dot(clouds, p[1], p[2], p[3] + (if pass == 1 then 8 else 0),
					if pass == 1 then Color3.fromRGB(70, 125, 240) else Color3.fromRGB(155, 205, 255), 0, Z.Clouds + pass)
				puff.Name = if pass == 1 then "CloudEdge" else "Puff"
			end
		end
		for _, p in ipairs(puffs) do
			local sheen = dot(clouds, p[1] - p[3] * 0.14 * dir, p[2] - p[3] * 0.2, p[3] * 0.46, WHITE, 0.62, Z.Clouds + 3)
			sheen.Name = "Sheen"
		end
		local shade = box(clouds, "Shade", math.min(x - 60 * dir, x + 92 * dir), PANEL.Y - 10, 152, 34,
			Color3.fromRGB(165, 155, 245), Z.Clouds + 4, { BackgroundTransparency = 0.5 })
		pill(shade)
		sparkle(clouds, x + 28 * dir, PANEL.Y - 76, 18, WHITE, Z.Clouds + 5, true)
	end
	cloudBank(0, false)
	cloudBank(PANEL.X, true)

	goldStar(decor, 16, 470, 78, Z.Decor)
	goldStar(decor, PANEL.X - 12, 196, 68, Z.Decor)
	goldStar(decor, PANEL.X - 14, INSET + BOTTOM_Y + 40, 60, Z.Decor)
	sparkle(decor, INSET + BOTTOM_PAD + 12, PANEL.Y - 36, 34, GOLD, Z.Decor, true)
	sparkle(decor, 24, 300, 18, CYAN, Z.Decor, true)

	-- ---------- action button ----------
	-- The MAXED picture is 2000 x 667 with its pill filling the middle
	-- 94.9% x 64.9% of it. Every drawn state uses the same pill shape.
	local MAXED_ASPECT = 2000 / 667
	local MAXED_PILL = Vector2.new(0.949, 0.649)

	-- Every drawn state is the same glossy pill as the MAXED picture: a near-
	-- black navy edge, a coloured depth layer under it, a bright top, a deeper
	-- base, a thin light inner line and gloss at both ends.
	local BUTTON_EDGE = Color3.fromRGB(8, 10, 32)
	local BUTTON_STYLES = {
		buy = {
			fill = {
				{ 0, Color3.fromRGB(196, 255, 120) }, { 0.2, Color3.fromRGB(128, 240, 92) },
				{ 0.58, Color3.fromRGB(46, 202, 78) }, { 1, Color3.fromRGB(12, 132, 72) },
			},
			edge = Color3.fromRGB(215, 255, 230), depth = Color3.fromRGB(6, 88, 50), text = WHITE, icon = true,
		},
		poor = {
			fill = {
				{ 0, Color3.fromRGB(160, 178, 222) }, { 0.2, Color3.fromRGB(124, 142, 192) },
				{ 0.58, Color3.fromRGB(88, 104, 156) }, { 1, Color3.fromRGB(56, 66, 116) },
			},
			edge = Color3.fromRGB(190, 208, 245), depth = Color3.fromRGB(26, 32, 74), text = Color3.fromRGB(232, 238, 252), icon = true,
		},
		-- Drawn only if the MAXED picture cannot load; matches its blue.
		maxed = {
			fill = {
				{ 0, Color3.fromRGB(140, 185, 255) }, { 0.2, Color3.fromRGB(104, 150, 245) },
				{ 0.58, Color3.fromRGB(66, 104, 222) }, { 1, Color3.fromRGB(38, 66, 172) },
			},
			edge = Color3.fromRGB(110, 225, 255), depth = Color3.fromRGB(16, 30, 100), text = WHITE, icon = false,
		},
		wait = {
			fill = {
				{ 0, Color3.fromRGB(160, 178, 222) }, { 0.2, Color3.fromRGB(124, 142, 192) },
				{ 0.58, Color3.fromRGB(88, 104, 156) }, { 1, Color3.fromRGB(56, 66, 116) },
			},
			edge = Color3.fromRGB(190, 208, 245), depth = Color3.fromRGB(26, 32, 74), text = WHITE, icon = false,
		},
		-- Locked behind a rebirth: purple, the rebirth colour.
		locked = {
			fill = {
				{ 0, Color3.fromRGB(232, 175, 255) }, { 0.2, Color3.fromRGB(196, 120, 250) },
				{ 0.58, Color3.fromRGB(148, 68, 232) }, { 1, Color3.fromRGB(86, 32, 160) },
			},
			edge = Color3.fromRGB(240, 210, 255), depth = Color3.fromRGB(52, 16, 104), text = WHITE, icon = false,
		},
	}

	local maxedArt = nil   -- { url, square } once the MAXED picture has loaded
	local actionButtons = {}

	local function actionButton(parent, cx, cy, w, h, z)
		local button = make("TextButton", {
			Name = "PriceButton",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(w, h),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = z,
		}, parent)
		button:SetAttribute("OwnPressAnimation", true)

		-- Drawn pill for every state except MAXED: navy depth, glossy face,
		-- a lit inner line and the two specular glints the MAXED art has.
		local drawn = make("Frame", {
			Name = "Drawn",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = z,
		}, button)
		local shadow = box(drawn, "Shadow", 0, 8, w, h, BUTTON_EDGE, z, { BackgroundTransparency = 0.55 })
		pill(shadow)
		local depth = box(drawn, "Depth", 0, 5, w, h, BUTTON_STYLES.wait.depth, z)
		pill(depth)
		stroke(depth, BUTTON_EDGE, 4)
		local face = box(drawn, "Face", 0, 0, w, h, WHITE, z + 1)
		pill(face)
		stroke(face, BUTTON_EDGE, 4)
		local faceGradient = gradient(face, BUTTON_STYLES.wait.fill)
		-- Soft darker base inside the face: the pill reads as rounded, not flat.
		local base = box(face, "Base", h * 0.2, h * 0.6, w - h * 0.4, h * 0.3, BUTTON_EDGE, z + 2, { BackgroundTransparency = 0.84 })
		pill(base)
		local inner = box(face, "InnerLine", 4, 4, w - 8, h - 8, WHITE, z + 2, { BackgroundTransparency = 1 })
		pill(inner)
		local edgeStroke = stroke(inner, BUTTON_STYLES.wait.edge, 1.5, nil, 0.35)
		-- Glossy reflection across the top half, strongest at the very top.
		local shine = box(face, "Shine", h * 0.32, 4, w - h * 0.64, h * 0.34, WHITE, z + 2, { BackgroundTransparency = 0.5 })
		pill(shine)
		make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.1, 0.85) }, shine)
		for _, side in ipairs({ -1, 1 }) do
			local gx = if side < 0 then h * 0.34 else w - h * 0.34
			local specular = box(face, "Specular", gx, h * 0.28, h * 0.3, h * 0.12, WHITE, z + 3,
				{ AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 0.1, Rotation = side * 34 })
			pill(specular)
		end
		-- Success feedback: a white flash and a bright streak across the face.
		local flash = box(face, "Flash", 0, 0, w, h, WHITE, z + 3, { BackgroundTransparency = 1 })
		pill(flash)
		local streakClip = make("Frame", {
			Name = "StreakClip", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			ClipsDescendants = true, ZIndex = z + 3,
		}, face)
		local streak = box(streakClip, "Streak", -h, -h * 0.25, h * 0.35, h * 1.5, WHITE, z + 3,
			{ BackgroundTransparency = 0.45, Rotation = 18 })
		make("UIGradient", { Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1),
		}) }, streak)

		-- One line: optional Stardust icon + wording.
		local row = make("Frame", {
			Name = "Content",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, h),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			ZIndex = z + 4,
		}, button)
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		local icon = make("ImageLabel", {
			Name = "Stardust",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(h * 0.58, h * 0.58),
			BackgroundTransparency = 1,
			Image = UIAssets.Stardust or "",
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = z + 5,
		}, row)
		local label = make("TextLabel", {
			Name = "Label",
			LayoutOrder = 2,
			Size = UDim2.fromOffset(0, h),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = FONT,
			Text = "",
			TextSize = math.floor(h * 0.52),
			TextColor3 = WHITE,
			ZIndex = z + 5,
		}, row)
		stroke(label, BUTTON_EDGE, 3.5, Enum.ApplyStrokeMode.Contextual)
		-- White lettering with a faint cool shade at the bottom.
		gradient(label, { { 0, WHITE }, { 0.55, WHITE }, { 1, Color3.fromRGB(200, 240, 255) } }, 90)

		-- Two lines, for the rebirth lock: REBIRTH over TO UNLOCK, both large
		-- enough to read.
		local stack = make("Frame", {
			Name = "TwoLine",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = z + 4,
		}, button)
		local mainLine = text(stack, "Main", "", 0, h * 0.08, w, h * 0.5, math.floor(h * 0.47), WHITE, z + 5)
		stroke(mainLine, INK, 3, Enum.ApplyStrokeMode.Contextual)
		local subLine = text(stack, "Sub", "", 0, h * 0.54, w, h * 0.32, math.floor(h * 0.3), Color3.fromRGB(242, 228, 255), z + 5)
		stroke(subLine, INK, 2.5, Enum.ApplyStrokeMode.Contextual)

		-- The supplied MAXED picture, sized so its pill is exactly this button.
		local maxedImage = make("ImageLabel", {
			Name = "MaxedArt",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = "",
			ScaleType = Enum.ScaleType.Fit,
			Visible = false,
			Active = false,
			ZIndex = z + 6,
		}, button)

		local scale = make("UIScale", {}, button)
		local hover, down = false, false
		local showingArt = false   -- the MAXED picture never animates like a button
		local tween
		local function settle(info)
			if tween then tween:Cancel() end
			if reduced() or showingArt then scale.Scale = 1 return end
			local goal = if down then 0.96 elseif hover and button.Active then 1.025 else 1
			tween = TweenService:Create(scale, info, { Scale = goal })
			tween:Play()
		end
		button.MouseEnter:Connect(function()
			hover = true
			if button.Active and not showingArt then playHoverSound() end
			settle(MOTION.Hover)
		end)
		button.MouseLeave:Connect(function()
			hover, down = false, false
			settle(MOTION.Hover)
		end)
		button.InputBegan:Connect(function(input)
			if not button.Active then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
				or input.KeyCode == Enum.KeyCode.ButtonA then
				down = true
				settle(MOTION.Press)
			end
		end)
		button.InputEnded:Connect(function(input)
			if down and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
				or input.KeyCode == Enum.KeyCode.ButtonA) then
				down = false
				settle(MOTION.Release)
			end
		end)

		local api = { Button = button, Scale = scale }

		-- Called once the MAXED picture has loaded.
		function api.UseMaxedArt()
			if not maxedArt then return end
			local iw = w / MAXED_PILL.X
			maxedImage.Image = maxedArt.url
			-- A decal's thumbnail is the picture fitted into a square.
			maxedImage.Size = UDim2.fromOffset(iw, if maxedArt.square then iw else iw / MAXED_ASPECT)
		end

		function api.SetState(styleName, str, subStr)
			local showArt = styleName == "maxed" and maxedArt ~= nil
			showingArt = showArt
			maxedImage.Visible = showArt
			drawn.Visible = not showArt
			if showArt then
				-- The picture carries its own MAXED lettering: nothing on top.
				row.Visible = false
				stack.Visible = false
				return
			end
			local style = BUTTON_STYLES[styleName] or BUTTON_STYLES.wait
			local keys = {}
			for i, stop in ipairs(style.fill) do keys[i] = ColorSequenceKeypoint.new(stop[1], stop[2]) end
			faceGradient.Color = ColorSequence.new(keys)
			edgeStroke.Color = style.edge
			depth.BackgroundColor3 = style.depth
			if subStr then
				row.Visible = false
				stack.Visible = true
				mainLine.Text = str
				mainLine.TextColor3 = style.text
				subLine.Text = subStr
				return
			end
			stack.Visible = false
			row.Visible = true
			label.TextColor3 = style.text
			label.Text = str
			-- Longer wording steps down to fit between the pill's round ends.
			-- Fredoka One capitals plus the outline run about 0.66 of the size.
			-- Phones: the price is the thing people read, so it and its star
			-- run larger (the window itself is drawn small there).
			local big = UiResponsive ~= nil and UiResponsive.Layout() == "compact"
			local iconK = if big then 0.64 else 0.58
			icon.Size = UDim2.fromOffset(h * iconK, h * iconK)
			local iconW = if style.icon then h * iconK + 6 else 0
			local fitWidth = (w - h * 0.8 - iconW) / math.max((utf8.len(str) or #str) * 0.66, 1)
			label.TextSize = math.floor(math.min(h * (if big then 0.62 else 0.52), fitWidth))
			icon.Visible = style.icon and icon.Image ~= ""
		end

		-- Success: a quick squash and settle, a white flash and a streak across
		-- the face - never holding up the result.
		function api.Celebrate()
			if reduced() then return end
			if tween then tween:Cancel() end
			flash.BackgroundTransparency = 0.35
			TweenService:Create(flash, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
			streak.Position = UDim2.fromOffset(-h, -h * 0.25)
			TweenService:Create(streak, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(w + h * 0.5, -h * 0.25) }):Play()
			local squash = TweenService:Create(scale, MOTION.Squash, { Scale = 0.93 })
			squash.Completed:Connect(function(state)
				if state ~= Enum.PlaybackState.Completed then return end
				local pop = TweenService:Create(scale, MOTION.Pop, { Scale = if hover then 1.025 else 1 })
				tween = pop
				pop:Play()
			end)
			tween = squash
			squash:Play()
		end

		table.insert(actionButtons, api)
		return api
	end

	-- A few glints thrown out from a point and faded; cleaned up after.
	local function sparkleBurst(parent, cx, cy)
		if reduced() then return end
		for i = 1, 7 do
			local angle = (i / 7) * math.pi * 2 + math.random() * 0.4
			local color = if i % 3 == 0 then GOLD elseif i % 3 == 1 then CYAN else WHITE
			local s = sparkle(parent, cx, cy, math.random(16, 24), color, 60)
			local distance = math.random(40, 70)
			TweenService:Create(s, MOTION.Burst, {
				Position = UDim2.fromOffset(cx + math.cos(angle) * distance, cy + math.sin(angle) * distance),
				Rotation = math.random(-60, 60),
			}):Play()
			local fade = TweenService:Create(s:FindFirstChildOfClass("UIScale"), MOTION.Burst, { Scale = 0 })
			fade.Completed:Connect(function() s:Destroy() end)
			fade:Play()
		end
	end

	-- ---------- cards ----------
	local cards = {}

	local function buildCard(item, x, y, w, h, wide)
		local id = item.Id
		local light = CARD_LIGHT[id] or { CYAN, CYAN }

		local card = make("Frame", {
			Name = id .. "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x + w / 2, y + h / 2),
			Size = UDim2.fromOffset(w, h),
			BackgroundTransparency = 1,
			ZIndex = Z.Card,
		}, content)
		local hoverScale = make("UIScale", {}, card)

		-- Layered edge: soft blue haze -> navy structure -> magenta / violet /
		-- blue band -> dark seam -> body, with a thin cyan light on the body.
		for i, spec in ipairs({ { 10, 0.8, Color3.fromRGB(60, 110, 255) }, { 5, 0.5, Color3.fromRGB(40, 140, 255) } }) do
			local haze = box(card, "Haze" .. i, -spec[1], -spec[1], w + spec[1] * 2, h + spec[1] * 2, spec[3], Z.CardBack,
				{ BackgroundTransparency = spec[2] })
			round(haze, 26 + spec[1])
		end
		local structure = box(card, "Structure", 0, 0, w, h, INK, Z.CardBack)
		round(structure, 26)
		local edge = box(card, "Edge", 3, 3, w - 6, h - 6, WHITE, Z.CardBack)
		round(edge, 23)
		gradient(edge, {
			{ 0, Color3.fromRGB(255, 140, 235) }, { 0.2, Color3.fromRGB(250, 75, 215) },
			{ 0.55, Color3.fromRGB(170, 95, 255) }, { 1, Color3.fromRGB(80, 140, 255) },
		})
		local seam = box(card, "Seam", 9, 9, w - 18, h - 18, Color3.fromRGB(16, 14, 64), Z.CardBack)
		round(seam, 18)
		local body = box(card, "Body", 12, 12, w - 24, h - 24, WHITE, Z.CardBack)
		round(body, 16)
		gradient(body, {
			{ 0, Color3.fromRGB(30, 26, 116) }, { 0.45, Color3.fromRGB(10, 20, 76) },
			{ 1, Color3.fromRGB(4, 14, 54) },
		})
		local lit = stroke(body, Color3.fromRGB(115, 220, 255), 1.5, Enum.ApplyStrokeMode.Border, 0.3)
		local bw, bh = w - 24, h - 24
		starfield(body, bw, bh, 8, #id * 7 + math.floor(w), Z.CardBack)

		-- Glossy magenta title bar: bright top, deeper base, a pale rim and a
		-- navy line underneath.
		local barH = 52
		local bar = box(body, "TitleBar", 0, 0, bw, barH, WHITE, Z.TitleBar)
		round(bar, 16)
		gradient(bar, {
			{ 0, Color3.fromRGB(255, 175, 240) }, { 0.3, Color3.fromRGB(252, 80, 205) },
			{ 0.75, Color3.fromRGB(215, 40, 180) }, { 1, Color3.fromRGB(160, 28, 160) },
		})
		-- Squares off the bar's lower corners, continuing the bar's gradient.
		local base = box(body, "TitleBarBase", 0, barH - 18, bw, 18, WHITE, Z.TitleBar - 1)
		gradient(base, { { 0, Color3.fromRGB(223, 49, 185) }, { 0.28, Color3.fromRGB(215, 40, 180) }, { 1, Color3.fromRGB(160, 28, 160) } })
		local barLine = box(body, "TitleBarLine", 0, barH, bw, 3, INK, Z.TitleBar + 1)
		local shadow = box(body, "TitleBarShadow", 0, barH + 3, bw, 8, INK, Z.TitleBar)
		make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.45, 1) }, shadow)
		local barShine = box(bar, "Shine", 12, 5, bw - 24, 13, WHITE, Z.TitleBar + 1, { BackgroundTransparency = 0.6 })
		pill(barShine)
		local rim = box(bar, "Rim", 18, 2, bw - 36, 2, Color3.fromRGB(255, 215, 250), Z.TitleBar + 2, { BackgroundTransparency = 0.25 })
		pill(rim)
		local title = text(body, "Title", item.Title, 12, 4, bw - 24, barH - 8, 31, WHITE, Z.Text)
		stroke(title, Color3.fromRGB(45, 18, 92), 3, Enum.ApplyStrokeMode.Contextual)

		-- Where the hero picture and the text stack go.
		local artX, artY, artW, artH, textX, textW
		if wide then
			artX, artY, artW, artH = 8, barH + 4, bw * 0.45, bh - barH - 10
			textX, textW = bw * 0.47, bw * 0.53 - 12
		else
			artX, artY, artW, artH = 10, barH + 4, bw - 20, 142
			textX, textW = 12, bw - 24
		end

		-- The card's own light behind its picture: soft, no disc edges.
		local heroGlow = glow(body, artX + artW / 2, artY + artH / 2, artH * 0.72, light[1], 0.75, Z.Glow)
		glow(body, artX + artW * 0.62, artY + artH * 0.55, artH * 0.42, light[2], 0.55, Z.Glow)
		local art = make("Frame", {
			Name = "HeroArt",
			Position = UDim2.fromOffset(artX, artY),
			Size = UDim2.fromOffset(artW, artH),
			BackgroundTransparency = 1,
			ZIndex = Z.Hero,
		}, body)

		-- Text stack: description -> value -> level -> button, with room between.
		local descY, valueY, levelY, buttonSize, buttonCY
		if wide then
			descY, valueY, levelY = barH + 6, barH + 55, barH + 93
			buttonSize = WIDE_BUTTON
			buttonCY = bh - 16 - buttonSize.Y / 2
		else
			descY, valueY, levelY = barH + 146, barH + 195, barH + 231
			buttonSize = TOP_BUTTON
			buttonCY = bh - 10 - buttonSize.Y / 2
		end
		-- Top cards wrap the description over a narrower measure (two even lines).
		local descW = if wide then textW else math.min(textW, 282)
		local description = text(body, "Description", COPY[id] or item.Description, textX + (textW - descW) / 2, descY, descW, 48, 23, WHITE, Z.Text)
		stroke(description, INK, 3, Enum.ApplyStrokeMode.Contextual)
		local valueSize = if wide then 38 else 36
		local value = text(body, "Value", "", textX, valueY, textW, valueSize, valueSize, WHITE, Z.Text)
		stroke(value, INK, 3.5, Enum.ApplyStrokeMode.Contextual)
		gradient(value, { { 0, Color3.fromRGB(195, 255, 255) }, { 1, Color3.fromRGB(40, 215, 240) } })
		local valuePop = make("UIScale", {}, value)
		local level = text(body, "Level", "", textX, levelY, textW, 24, 22, Color3.fromRGB(168, 198, 255), Z.Text)
		stroke(level, INK, 2.5, Enum.ApplyStrokeMode.Contextual)

		local action = actionButton(body, textX + textW / 2, buttonCY, buttonSize.X, buttonSize.Y, Z.Button)

		-- Hover: a hair bigger and a brighter lit edge. Nothing bounces.
		card.MouseEnter:Connect(function()
			if reduced() then return end
			TweenService:Create(hoverScale, MOTION.CardHover, { Scale = 1.008 }):Play()
			TweenService:Create(lit, MOTION.CardHover, { Transparency = 0.05 }):Play()
		end)
		card.MouseLeave:Connect(function()
			TweenService:Create(hoverScale, MOTION.CardHover, { Scale = 1 }):Play()
			TweenService:Create(lit, MOTION.CardHover, { Transparency = 0.3 }):Play()
		end)

		cards[id] = {
			Item = item, Card = card, Body = body, Value = value, ValuePop = valuePop, Level = level,
			Action = action, Price = action.Button, Art = art, ArtW = artW, ArtH = artH, Glow = heroGlow,
			-- The drawn title bar, hidden if the card's label picture loads.
			TitleParts = { bar, base, barLine, shadow, title },
			W = w, LabelWidth = if wide then 370 else 350, LabelTop = if wide then 3 else 4,
		}
		return cards[id]
	end

	local function layoutRow(ids, y, h, pad, wide)
		local count = #ids
		local width = (CW - pad * 2 - COL_GAP * (count - 1)) / count
		for i, id in ipairs(ids) do
			local item = Config.GetItem(id)
			if item then
				buildCard(item, pad + (i - 1) * (width + COL_GAP), y, width, h, wide)
			else
				warn("[MainHUD] UpgradeConfig has no item", id, "- its card is left out.")
			end
		end
	end
	layoutRow(TOP_ROW, TOP_Y, TOP_H, TOP_PAD, false)
	layoutRow(BOTTOM_ROW, BOTTOM_Y, BOTTOM_H, BOTTOM_PAD, true)

	-- ---------- hero pictures ----------
	-- Each card shows only its supplied picture (UpgradeArt.Icons), placed once
	-- it has been fetched. ART.HeroScale can enlarge every picture if the
	-- uploads carry wide transparent margins.
	local HERO_SCALE = tonumber(ART.HeroScale) or 1

	local function fillHero(card, url)
		local art, w, h = card.Art, card.ArtW, card.ArtH
		card.Hero = image(art, "Picture", url, w / 2, h / 2, w * HERO_SCALE, h * HERO_SCALE, 3)
		card.HeroHome = card.Hero.Position
		card.HeroScale = make("UIScale", {}, card.Hero)
		if card.Item.Id == "LockBase" then
			-- The occasional cyan glint on the shield's upper edge.
			card.Flash = sparkle(art, w * 0.64, h * 0.2, 30, Color3.fromRGB(150, 240, 255), 6)
			card.Flash:FindFirstChildOfClass("UIScale").Scale = 0
		end
	end

	-- ---------- name labels ----------
	-- Each label picture is 2000 x 667 with its pill filling the middle
	-- 97.5% x 51.5%, centred a little above half height. The pill sits on
	-- the card's top edge like a nameplate, in place of the drawn bar, with a
	-- soft magenta light behind it.
	local LABEL_ASPECT = 2000 / 667
	local LABEL_PILL = Vector2.new(0.975, 0.515)
	local LABEL_PILL_Y = 0.476

	local function applyLabel(card, url, square)
		for _, part in ipairs(card.TitleParts) do part.Visible = false end
		local pillW = card.LabelWidth
		local iw = pillW / LABEL_PILL.X
		local ih = iw / LABEL_ASPECT
		local pillH = ih * LABEL_PILL.Y
		local halo = box(card.Card, "LabelGlow", (card.W - pillW) / 2 - 8, card.LabelTop - 5, pillW + 16, pillH + 10,
			Color3.fromRGB(255, 80, 215), Z.CardBack + 1, { BackgroundTransparency = 0.7 })
		pill(halo)
		-- A decal's thumbnail is the picture fitted into a square.
		image(card.Card, "LabelArt", url, card.W / 2, card.LabelTop + pillH / 2 + (0.5 - LABEL_PILL_Y) * ih,
			iw, if square then iw else ih, Z.CardBack + 2)
	end

	-- ---------- fit to screen ----------
	local lastFit = nil
	local UPGRADE_PHONE_GROW = 1.1      -- phones: the whole window, uniformly
	local function refreshUpgradeScale()
		local availW, availH
		local fit, below = FIT, 0
		if UiResponsive and UiResponsive.ModalArea then
			-- Below Roblox's top bar, inside the notch, centred in that space.
			local phone = UiResponsive.Layout() == "compact"
			availW, availH = UiResponsive.ModalArea(if phone then { shareW = 1, shareH = 0.96 } else nil)
			below = math.max(UiResponsive.TopInset(), 0) / 2
			-- Phones: fit the panel itself; only its decorative stars and
			-- clouds may hang past the edge, never a button.
			if UiResponsive.Layout() == "compact" then fit = PANEL end
		elseif UiResponsive and UiResponsive.SafeRect then
			local _, size = UiResponsive.SafeRect()
			availW, availH = size.X, size.Y
		else
			local vp = (workspace.CurrentCamera or camera).ViewportSize
			availW, availH = vp.X, vp.Y
		end
		if availW < 2 or availH < 2 then return end
		local scale = math.clamp(math.min((availW - 24) / fit.X, (availH - 24) / fit.Y), 0.3, 1)
		if UiResponsive and UiResponsive.ModalArea and UiResponsive.Layout() == "compact" then
			-- Phones: 10% larger, uniformly. The panel may use the middle of
			-- the top-bar strip only when its whole width clears Roblox's
			-- buttons there; otherwise it stays below the bar.
			local want = scale * UPGRADE_PHONE_GROW
			local _, safe = UiResponsive.SafeRect()
			local fullW, belowH = UiResponsive.ModalArea({ shareW = 1, shareH = 1 })
			local roomH = belowH - 10
			local screenW = UiResponsive.Screen().X
			local panelW = PANEL.X * want
			local free = nil
			pcall(function() free = game:GetService("GuiService").TopbarInset end)
			if free and free.Height > 0 then
				local left, right = screenW / 2 - panelW / 2, screenW / 2 + panelW / 2
				if left >= free.Min.X + 8 and right <= free.Max.X - 8 then roomH = safe.Y - 12 end
			end
			scale = math.max(scale, math.min(want, (fullW - 16) / PANEL.X, roomH / PANEL.Y))
			-- As low as the space allows (clear of the bar), never off the bottom.
			below = math.max(0, math.min(below, (safe.Y - PANEL.Y * scale) / 2 - 6))
		end
		upgradePopup.Position = UDim2.new(0.5, 0, 0.5, below)
		if scale == lastFit then return end
		lastFit = scale
		fitScale.Scale = scale
		-- Text shrinks to fit its own box rather than overflowing it.
		local shrink = math.min(1, scale)
		for limit, size in pairs(textLimits) do
			limit.MinTextSize = math.max(1, math.floor(size * 0.55 * shrink))
		end
	end
	refreshUpgradeScale()
	if UiResponsive then
		UiResponsive.Changed:Connect(refreshUpgradeScale)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshUpgradeScale)

	-- Pop in: 0.86 -> 1 with Back easing (its own small overshoot) while it
	-- rises 8 px into place; clicks wait until it lands. Pop out: 1 -> 0.92,
	-- Quad In, then hidden. GuiManager cancels either one if the other starts.
	GuiManager:Register("Upgrade", upgradePopup, {
		OpenScale = 0.86,
		OpenOvershootScale = 1,
		OpenRise = 8,
		OpenPopTween = TweenInfo.new(0.23, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		CloseBounceScale = 1,
		CloseScale = 0.92,
		CloseShrinkTween = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	})

	-- ---------- ambient motion (only while open) ----------
	-- Slow and small: the planet turns a few degrees, glints twinkle on their
	-- own clocks, and each hero picture has one gentle movement of its own
	-- (never more than about 2% of its size).
	local HERO_MOTION = {
		SpawnTier = { time = 6, rotation = 3 },                -- the vortex turns a touch
		MaxSpawn = { time = 2.4, scale = 1.012 },             -- the portals shimmer
		CoinDropRate = { time = 3.2, offset = Vector2.new(0, -4) }, -- the star bobs on its orbit
		CurrencyMagnet = { time = 2.6, offset = Vector2.new(4, 0) }, -- the magnet tugs at its coins
		LockBase = { flashEvery = 3.6 },                      -- an occasional cyan glint
	}
	local ambient = {}
	local ambientToken = 0
	local function stopAmbient()
		ambientToken += 1
		for _, tween in ipairs(ambient) do tween:Cancel() end
		table.clear(ambient)
		for _, twinkle in ipairs(twinkles) do twinkle.scale.Scale = 1 end
		planetHolder.Rotation = 0
		for _, card in pairs(cards) do
			if card.Hero then
				card.Hero.Rotation = 0
				card.Hero.Position = card.HeroHome
				card.HeroScale.Scale = 1
			end
			if card.Flash then card.Flash:FindFirstChildOfClass("UIScale").Scale = 0 end
		end
	end
	local function loop(object, seconds, goal, delay)
		local tween = TweenService:Create(object,
			TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, delay or 0), goal)
		tween:Play()
		table.insert(ambient, tween)
	end
	local function startAmbient()
		stopAmbient()
		if reduced() then return end
		local token = ambientToken
		loop(planetHolder, 8, { Rotation = 3 })
		for _, twinkle in ipairs(twinkles) do
			loop(twinkle.scale, math.random(14, 26) / 10, { Scale = twinkle.low }, math.random() * 2)
		end
		for id, card in pairs(cards) do
			local motion = HERO_MOTION[id]
			if card.Hero and motion then
				local delay = math.random() * 1.5
				if motion.rotation then loop(card.Hero, motion.time, { Rotation = motion.rotation }, delay) end
				if motion.scale then loop(card.HeroScale, motion.time, { Scale = motion.scale }, delay) end
				if motion.offset then
					loop(card.Hero, motion.time, { Position = card.HeroHome + UDim2.fromOffset(motion.offset.X, motion.offset.Y) }, delay)
				end
			end
			if card.Flash and motion and motion.flashEvery then
				local flashScale = card.Flash:FindFirstChildOfClass("UIScale")
				task.spawn(function()
					while ambientToken == token do
						task.wait(motion.flashEvery)
						if ambientToken ~= token then break end
						local grow = TweenService:Create(flashScale, MOTION.Flash, { Scale = 1 })
						table.insert(ambient, grow)
						grow:Play()
						grow.Completed:Wait()
						if ambientToken ~= token then break end
						local fade = TweenService:Create(flashScale, MOTION.Flash, { Scale = 0 })
						table.insert(ambient, fade)
						fade:Play()
					end
				end)
			end
		end
	end
	upgradePopup:GetPropertyChangedSignal("Visible"):Connect(function()
		if upgradePopup.Visible then startAmbient() else stopAmbient() end
	end)

	-- ---------- data ----------
	local purchaseBusy = false
	local statusToken = 0

	local function setStatus(message, hold)
		statusToken += 1
		local token = statusToken
		statusLabel.Text = message
		if hold then return end
		task.delay(3, function()
			if token == statusToken then statusLabel.Text = SUBTITLE end
		end)
	end

	local function dataReady()
		return player:GetAttribute("UpgradeDataReady") == true
			and player:GetAttribute("StardustDataReady") == true
			and player:GetAttribute("BlackHoleDataReady") == true
	end

	function dataFailed()
		return player:GetAttribute("UpgradeDataFailed") == true
			or player:GetAttribute("StardustDataFailed") == true
			or player:GetAttribute("BlackHoleDataFailed") == true
	end

	-- The live stat line for each upgrade: the current value, plus what the
	-- next level gives while there is one.
	local function valueText(id, level, hasNext)
		if id == "SpawnTier" then
			return "T" .. (1 + level) .. (if hasNext then " → T" .. (2 + level) else "")
		elseif id == "MaxSpawn" then
			return tostring(8 + level) .. (if hasNext then " → " .. (9 + level) else "") .. " black holes"
		elseif id == "LockBase" then
			return "+" .. (level * 5) .. "s" .. (if hasNext then " → +" .. ((level + 1) * 5) .. "s" else "")
		elseif id == "CoinDropRate" then
			return ("%.2fx"):format(Config.GetCoinDropFrequency(level))
				.. (if hasNext then (" → %.2fx"):format(Config.GetCoinDropFrequency(level + 1)) else "")
		elseif id == "CurrencyMagnet" and Config.GetMagnetMultiplier then
			local function pct(l) return math.floor((Config.GetMagnetMultiplier(l) - 1) * 100 + 0.5) end
			return "+" .. pct(level) .. "%" .. (if hasNext then " → +" .. pct(level + 1) .. "%" else "")
		end
		return "Level " .. level
	end

	-- Client-only signal to TutorialClient ("an upgrade hit its rebirth cap").
	-- Whichever script asks first creates it; both use the same one.
	local function rebirthGuideSignal()
		local folder = ReplicatedStorage:FindFirstChild("ClientSignals")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "ClientSignals"
			folder.Parent = ReplicatedStorage
		end
		local event = folder:FindFirstChild("RebirthCapGuide")
		if not event then
			event = Instance.new("BindableEvent")
			event.Name = "RebirthCapGuide"
			event.Parent = folder
		end
		return event
	end
	rebirthGuideSignal()

	-- The level this upgrade can be bought to right now, from the server-set
	-- rebirth count. Older configs without caps fall back to MaxLevel.
	local function levelCap(item)
		if Config.GetLevelCap then
			return Config.GetLevelCap(item.Id, player:GetAttribute(Config.RebirthAttribute))
		end
		return item.MaxLevel
	end

	local function rebirthCount()
		return math.max(0, math.floor(tonumber(player:GetAttribute(Config.RebirthAttribute or "Rebirths")) or 0))
	end

	-- Everything a card shows comes from the level, this run's cap and the
	-- rebirth count, so a rebirth (levels back to 0) refreshes every card at
	-- once and nothing can stay MAXED from the last run.
	local function updateCard(id)
		local card = cards[id]
		if not card then return end
		local item = card.Item
		local rebirths = rebirthCount()
		local level = math.max(0, math.floor(tonumber(player:GetAttribute(item.LevelAttribute)) or 0))
		local cap = levelCap(item)
		local locked = Config.IsLocked ~= nil and Config.IsLocked(id, rebirths)
		local atCap = level >= cap
		local price = if atCap then nil else Config.GetPrice(id, level, rebirths)
		local nextCap = Config.GetNextLevelCap and Config.GetNextLevelCap(id, rebirths)
		card.Value.Text = if dataReady() then valueText(id, level, price ~= nil) else "—"
		card.Level.Text = if locked then ("Unlocks at Rebirth %d"):format(item.RequiredRebirths or 1)
			else "Level " .. level .. " / " .. math.max(cap, level)
		local affordable = price ~= nil and (tonumber(player:GetAttribute(Config.CurrencyAttribute)) or 0) >= price
		card.Capped = atCap
		card.Locked = locked
		-- MAXED stays clickable only while a rebirth would raise the cap: the
		-- click explains that (and starts Nibbles' guide the first time).
		card.Price.Active = dataReady() and not purchaseBusy and (price ~= nil or locked or (atCap and nextCap ~= nil))
		if dataFailed() then
			card.Action.SetState("wait", "REJOIN TO LOAD")
		elseif not dataReady() then
			card.Action.SetState("wait", "LOADING…")
		elseif locked then
			card.Action.SetState("locked", "REBIRTH", "TO UNLOCK")
		elseif atCap or not price then
			card.Action.SetState("maxed", "MAXED")
		elseif purchaseBusy then
			card.Action.SetState("wait", "PLEASE WAIT…")
		else
			card.Action.SetState(if affordable then "buy" else "poor", abbreviate(price))
		end
	end

	-- A short, card-specific celebration once the server confirms a purchase.
	local function celebrateCard(card)
		if reduced() then return end
		local id = card.Item.Id
		local artCenterX = card.Art.Position.X.Offset + card.ArtW / 2
		local artCenterY = card.Art.Position.Y.Offset + card.ArtH / 2
		if card.HeroScale then
			local peak = if id == "MaxSpawn" then 1.12 else 1.08
			card.HeroScale.Scale = peak
			TweenService:Create(card.HeroScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		if id == "SpawnTier" and card.Hero then
			-- The vortex whips round and settles.
			card.Hero.Rotation = -30
			TweenService:Create(card.Hero, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
		elseif id == "LockBase" and card.Flash then
			local flashScale = card.Flash:FindFirstChildOfClass("UIScale")
			flashScale.Scale = 1.3
			TweenService:Create(flashScale, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
		elseif id == "CoinDropRate" then
			sparkleBurst(card.Body, artCenterX, artCenterY)
		elseif id == "CurrencyMagnet" then
			-- A cyan ring pulses out of the magnet (the world ring is drawn by
			-- StardustDropClient when the magnet level rises).
			local ring = make("Frame", {
				Name = "MagnetPulse",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(artCenterX, artCenterY),
				Size = UDim2.fromOffset(card.ArtH * 0.5, card.ArtH * 0.5),
				BackgroundTransparency = 1,
				ZIndex = Z.Hero + 1,
			}, card.Body)
			pill(ring)
			local ringStroke = stroke(ring, Color3.fromRGB(110, 240, 255), 5)
			TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(card.ArtH * 1.3, card.ArtH * 1.3) }):Play()
			local fade = TweenService:Create(ringStroke, TweenInfo.new(0.45), { Transparency = 1 })
			fade.Completed:Connect(function() ring:Destroy() end)
			fade:Play()
		end
	end

	-- A card that fails to update must not take the others (or the HUD) down.
	local cardWarned = false
	function refreshUpgradeCards()
		for id in pairs(cards) do
			local ok, err = pcall(updateCard, id)
			if not ok and not cardWarned then
				cardWarned = true
				warn("[MainHUD] upgrade card update failed:", err)
			end
		end
	end

	for id, card in pairs(cards) do
		local item = card.Item
		card.Price.Activated:Connect(function()
			if purchaseBusy or not dataReady() then return end
			local currentLevel = player:GetAttribute(item.LevelAttribute) or 0
			if card.Locked then
				setStatus(("%s unlocks at Rebirth %d!"):format(item.Title, item.RequiredRebirths or 1))
				return
			end
			if card.Capped then
				local nextCap = Config.GetNextLevelCap
					and Config.GetNextLevelCap(item.Id, player:GetAttribute(Config.RebirthAttribute))
				setStatus(if nextCap then ("%s is maxed for this run - rebirth to raise the cap to %d!"):format(item.Title, nextCap)
					else item.Title .. " is maxed!")
				-- Nibbles explains rebirthing the first time this happens
				-- (TutorialClient decides whether it has been shown before).
				if nextCap then
					rebirthGuideSignal():Fire({ title = item.Title, cap = levelCap(item), nextCap = nextCap })
				end
				return
			end
			purchaseBusy = true
			refreshUpgradeCards()
			local ok, result = pcall(function() return buyRemote:InvokeServer(item.Id, currentLevel) end)
			purchaseBusy = false
			refreshUpgradeCards()
			if not ok or type(result) ~= "table" then
				setStatus("Upgrade failed. Try again.")
			elseif result.ok then
				playClickSound()
				setStatus(item.Title .. " upgraded!")
				card.Action.Celebrate()
				local center = card.Price.Position
				sparkleBurst(card.Body, center.X.Offset, center.Y.Offset)
				celebrateCard(card)
				if not reduced() then
					card.ValuePop.Scale = 1.15
					TweenService:Create(card.ValuePop, MOTION.Pop, { Scale = 1 }):Play()
				end
			elseif result.reason == "not_enough" then
				setStatus("Need " .. abbreviate(result.needed or 0) .. " more Stardust!")
			elseif result.reason == "maxed" then
				setStatus(item.Title .. " is already maxed!")
			elseif result.reason == "capped" then
				setStatus(if result.nextCap then ("%s is maxed for this run - rebirth to raise the cap to %d!"):format(item.Title, result.nextCap)
					else item.Title .. " is maxed!")
			elseif result.reason == "rebirth_locked" then
				setStatus(if result.nextCap then ("Rebirth to raise %s's cap to level %d!"):format(item.Title, result.nextCap)
					else item.Title .. " is at its cap.")
			elseif result.reason == "data_failed" then
				setStatus("Saved data could not load. Please rejoin.", true)
			elseif result.reason == "loading" then
				setStatus("Your saved progress is still loading.")
			else
				setStatus("Please wait a moment and try again.")
			end
		end)
		player:GetAttributeChangedSignal(item.LevelAttribute):Connect(function() pcall(updateCard, id) end)
	end

	for _, attribute in ipairs({ Config.CurrencyAttribute, Config.RebirthAttribute or "Rebirths", "UpgradeDataReady", "StardustDataReady", "BlackHoleDataReady", "UpgradeDataFailed", "StardustDataFailed", "BlackHoleDataFailed" }) do
		player:GetAttributeChangedSignal(attribute):Connect(refreshUpgradeCards)
	end
	refreshUpgradeCards()

	-- ---------- artwork ----------
	-- Every picture is fetched now, while the window is still closed, and the
	-- window will not open until they have all answered (see
	-- openUpgradePopup), so it never shows a half-built card.
	-- An image id is used as it is. A decal id is drawn from its thumbnail
	-- (UIAssets.ResolveButtonArt). If the preload reports a failure the id is
	-- STILL used: Studio can report Failure for images that draw perfectly
	-- well, and the supplied art is never swapped for anything else.
	local artPending = 0
	local artWaiters = {}

	local function resolveArt(id, onResult)
		if type(id) ~= "string" or id == "" then
			onResult(nil, false)
			return
		end
		artPending += 1
		local settled = false
		local function settle(url, square)
			if settled then return end
			settled = true
			local ok, err = pcall(onResult, url or id, if url then square else false)
			if not ok then warn("[MainHUD] Upgrade window artwork:", err) end
			artPending -= 1
			if artPending == 0 then
				local waiting = artWaiters
				artWaiters = {}
				for _, callback in ipairs(waiting) do task.spawn(callback) end
			end
		end
		if UIAssets.ResolveButtonArt then
			UIAssets.ResolveButtonArt(id, settle)
			-- A request that never answers must not hold the window shut.
			task.delay(6, settle, nil, false)
		else
			settle(id, false)
		end
	end

	resolveArt(ART.HeaderArrow, function(url)
		if url then
			image(arrowSlot, "ArrowArt", url, ARROW.size / 2, ARROW.size / 2, ARROW.size, ARROW.size, Z.Header + 2)
		end
	end)

	resolveArt(ART.Close, function(url)
		if url then
			image(closeBtn, "CloseArt", url, 46, 46, 92, 92, Z.Close + 1)
		end
	end)

	resolveArt(ART.Background, function(url)
		if url then
			backdrop.Image = url
			-- "Stretch" lines the picture's frame up with the window exactly;
			-- set UpgradeArt.BackgroundScaleType = "Fit" if it ever looks squashed.
			backdrop.ScaleType = if ART.BackgroundScaleType == "Fit" then Enum.ScaleType.Fit else Enum.ScaleType.Stretch
			backdrop.Visible = true
			-- The picture replaces the drawn frame and sky: nothing under it.
			sky.Visible = false
			for _, piece in ipairs(drawnFrame) do piece.Visible = false end
			content.BackgroundTransparency = 1
		end
	end)

	resolveArt(ART.Title, function(url, square)
		if url then
			image(titleSlot, "TitleArt", url, TITLE.x, TITLE.y, TITLE.w, if square then TITLE.w else TITLE.h, Z.Header + 2)
		else
			goldText(titleSlot, "Title", "Upgrade", 258, 6, 520, 124, 104, Z.Header + 2, Enum.TextXAlignment.Left)
		end
	end)

	resolveArt(ART.Maxed, function(url, square)
		if not url then return end   -- no MAXED picture set: the drawn blue pill stays
		maxedArt = { url = url, square = square }
		for _, api in ipairs(actionButtons) do api.UseMaxedArt() end
		refreshUpgradeCards()
	end)

	for id, card in pairs(cards) do
		resolveArt(ICONS[id], function(url)
			if url then fillHero(card, url) end
		end)
		resolveArt(LABELS[id], function(url, square)
			if url then applyLabel(card, url, square) end   -- no label set: the drawn bar stays
		end)
	end

	local openQueued = false

	function openUpgradePopup()
		refreshUpgradeCards()
		if UIAssets.EnsureGroup then UIAssets.EnsureGroup("Upgrade") end
		statusLabel.Text = if dataFailed() then "Saved data could not load. Please rejoin." else SUBTITLE
		if artPending == 0 then
			GuiManager:Open("Upgrade")
			return
		end
		-- Only possible in the first moments after joining: stay closed until
		-- the pictures are in (3 seconds at most), then open. If another
		-- window was opened meanwhile, this one stands down.
		if openQueued then return end
		openQueued = true
		local function openWhenReady()
			if not openQueued then return end
			openQueued = false
			if GuiManager:GetCurrent() == nil then
				GuiManager:Open("Upgrade")
			end
		end
		table.insert(artWaiters, openWhenReady)
		task.delay(3, openWhenReady)
	end

	function closeUpgradePopup()
		openQueued = false
		if GuiManager:GetCurrent() == "Upgrade" then
			GuiManager:Close("Upgrade")
		end
	end
end
buildUpgradeWindow()

-- Gamepad B closes it the same way as the X.
GuiManager:SetBackHandler("Upgrade", closeUpgradePopup)

require(game:GetService("ReplicatedStorage"):WaitForChild("UIInputRouter")).Signal(upgradeBtn, "Open Upgrade"):Connect(function()
	if GuiManager:GetCurrent() == "Upgrade" then
		closeUpgradePopup()
	else
		openUpgradePopup()
	end
end)

-- ===== lock base logic =====
local lockRemote

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("LockBaseRemotes", 10)

	if remotes then
		lockRemote = remotes:WaitForChild("RequestLock", 10)
	end

	if not lockRemote then
		warn("[MainHUD] LockBaseRemotes/RequestLock was not found. Make sure LockBaseServer exists.")
	end
end)

-- ===== base protection button state =====
-- The server is the only authority: LockBaseServer (and PlaytimeAwardsServer's
-- shield reward) write BaseLockedUntil / LockBaseCooldownUntil, and this reads
-- them. A click never changes the art by itself; the art follows the
-- attributes, so PROTECTED only appears once the server has confirmed it.
--
--   Ready      LOCK BASE art, no timer
--   Protected  PROTECTED art, timer counting down the real remaining time
--   Cooldown   LOCK BASE art dimmed, timer showing the recharge (the server
--              still rejects a lock until it ends, exactly as before)
local SHOW_COOLDOWN_TIMER = true
local WARN_SECONDS = 10             -- timer warms to amber for the last 10s

local TIMER_STYLE = {
	Protected = { Fill = Color3.fromRGB(26, 64, 156), Text = THEME.Text },
	Warning = { Fill = Color3.fromRGB(26, 64, 156), Text = Color3.fromRGB(255, 196, 72) },
	Cooldown = { Fill = Color3.fromRGB(62, 68, 96), Text = Color3.fromRGB(215, 220, 235) },
}
local COOLDOWN_TINT = Color3.fromRGB(150, 150, 165)
local READY_TINT = Color3.fromRGB(255, 255, 255)

local lockArtRevealed = false       -- art stays hidden until it is cached
local lockArt = {}                  -- [ "LockBase" | "Protected" ] = { url, square }
local lockState = nil               -- last state drawn: "Ready" | "Protected" | "Cooldown"
local lockTransitionToken = 0
local timerShown = false

-- Server time, not the local clock: the attributes are server os.time()
-- stamps, so a client whose clock is off would otherwise count down wrong.
local function serverNow()
	return workspace:GetServerTimeNow()
end

local function readLockState()
	local now = serverNow()
	local lockedUntil = tonumber(player:GetAttribute("BaseLockedUntil")) or 0
	local cooldownUntil = tonumber(player:GetAttribute("LockBaseCooldownUntil")) or 0

	if lockedUntil > now then
		return "Protected", lockedUntil - now
	elseif cooldownUntil > now then
		return "Cooldown", cooldownUntil - now
	end
	return "Ready", 0
end

local function timerWanted(state)
	return state == "Protected" or (state == "Cooldown" and SHOW_COOLDOWN_TIMER)
end

local function setTimerShown(shown, animate)
	if shown == timerShown then return end
	timerShown = shown

	local alpha = if shown then 0 else 1
	if shown and not protectionTimer.Visible then
		-- Start a fade-in from fully clear.
		protectionTimer.BackgroundTransparency = 1
		timerBorder.Transparency = 1
		timerText.TextTransparency = 1
		timerTextStroke.Transparency = 1
		protectionTimer.Visible = true
	end

	if not animate or reducedMotion() then
		protectionTimer.BackgroundTransparency = alpha
		timerBorder.Transparency = alpha
		timerText.TextTransparency = alpha
		timerTextStroke.Transparency = alpha
		protectionTimer.Visible = shown
		return
	end

	TweenService:Create(protectionTimer, TOP_MOTION.Fade, { BackgroundTransparency = alpha }):Play()
	TweenService:Create(timerBorder, TOP_MOTION.Fade, { Transparency = alpha }):Play()
	TweenService:Create(timerTextStroke, TOP_MOTION.Fade, { Transparency = alpha }):Play()
	local fade = TweenService:Create(timerText, TOP_MOTION.Fade, { TextTransparency = alpha })
	fade.Completed:Connect(function()
		if not timerShown then protectionTimer.Visible = false end
	end)
	fade:Play()
end

local function artFor(state)
	return if state == "Protected" then lockArt.Protected else lockArt.LockBase
end

-- Swaps the one ButtonImage in place. After the first reveal a swap dips the
-- art slightly, changes the image at the smallest point and settles back, so
-- the change reads as one motion (about 0.25s in total). Nothing moves or
-- resizes: the dip is on the art's own UIScale, inside the fixed hit box.
local function applyLockArt(state, animate)
	lockTransitionToken += 1
	local token = lockTransitionToken

	local resolved = artFor(state)
	local tint = if state == "Cooldown" then COOLDOWN_TINT else READY_TINT
	local imageChanges = lockBaseArt.Image ~= (if resolved then resolved.url else "")

	if not animate or reducedMotion() then
		setButtonArt(lockBaseArt, resolved)
		lockBaseArt.ImageColor3 = tint
		lockBaseTransition.Scale = 1
		setTimerShown(timerWanted(state), false)
		return
	end

	if not imageChanges then
		-- Cooldown -> Ready: same artwork, it only brightens.
		TweenService:Create(lockBaseArt, TOP_MOTION.Fade, { ImageColor3 = tint }):Play()
		TweenService:Create(lockBaseTransition, TOP_MOTION.Settle, { Scale = 1 }):Play()
		setTimerShown(timerWanted(state), true)
		return
	end

	-- Leaving a timer state fades the chip out alongside the dip; entering one
	-- fades it in once the new art has settled.
	if not timerWanted(state) then setTimerShown(false, true) end

	local dip = TweenService:Create(lockBaseTransition, TOP_MOTION.Dip, { Scale = 0.94 })
	dip.Completed:Connect(function(playbackState)
		if token ~= lockTransitionToken or playbackState ~= Enum.PlaybackState.Completed then return end
		setButtonArt(lockBaseArt, resolved)
		lockBaseArt.ImageColor3 = tint
		TweenService:Create(lockBaseTransition, TOP_MOTION.Settle, { Scale = 1 }):Play()
		if timerWanted(state) then setTimerShown(true, true) end
	end)
	dip:Play()
end

-- The one function that draws this control. Everything that can change the
-- protection state calls it; nothing else writes the button's image.
local function updateBaseProtectionUI()
	if not lockArtRevealed then return end

	local state, remaining = readLockState()

	if state ~= lockState then
		local first = lockState == nil
		lockState = state
		applyLockArt(state, not first)
		-- Only ever seen if the artwork failed to load.
		lockBaseFallback.Text = if state == "Protected" then "PROTECTED" else "LOCK BASE"
		lockBaseFallback.BackgroundColor3 = if state == "Protected" then Color3.fromRGB(58, 176, 255)
			elseif state == "Cooldown" then THEME.Cooldown
			else THEME.LockBase
	end

	if state == "Ready" then return end

	local seconds = math.ceil(remaining)
	local style = if state == "Cooldown" then TIMER_STYLE.Cooldown
		elseif seconds <= WARN_SECONDS then TIMER_STYLE.Warning
		else TIMER_STYLE.Protected
	protectionTimer.BackgroundColor3 = style.Fill
	timerText.TextColor3 = style.Text
	timerText.Text = fmtSeconds(seconds)
end

-- Each button stays hidden until its artwork has resolved (image id, or a
-- decal id drawn from its thumbnail), then fades in already showing the
-- correct state: an already-protected player sees PROTECTED and the right
-- time on the very first frame, never LOCK BASE.
local resolveArt = UIAssets.ResolveButtonArt or function(id, callback)
	task.spawn(callback, if type(id) == "string" and id ~= "" then id else nil, false)
end

-- Resolves every id in the table, then calls onDone once with
-- { [key] = { url, square } } (a key is missing if it did not load). A dead
-- id can never keep the buttons hidden: after 12s it goes with what it has.
local function resolveButtonArt(ids, onDone)
	local results, pending, finished = {}, 0, false
	local function finish()
		if finished then return end
		finished = true
		onDone(results)
	end
	-- Count first, then start: an id that answers straight away must not
	-- finish the batch before the others have even been asked.
	for _ in pairs(ids) do pending += 1 end
	for key, id in pairs(ids) do
		resolveArt(id, function(url, square)
			if url then results[key] = { url = url, square = square } end
			pending -= 1
			if pending == 0 then finish() end
		end)
	end
	if pending == 0 then finish() end
	task.delay(12, finish)
end

local function fadeInArt(art)
	if reducedMotion() then
		art.ImageTransparency = 0
	else
		TweenService:Create(art, TOP_MOTION.Reveal, { ImageTransparency = 0 }):Play()
	end
end

local function useTextFallback(art, fallback, label)
	warn("[MainHUD] " .. label .. " artwork did not load - showing the text fallback. See the [UIAssets] line above.")
	art.Visible = false
	fallback.Visible = true
end

resolveButtonArt({ Upgrade = TOP_ART.Upgrade }, function(results)
	if results.Upgrade then
		setButtonArt(upgradeArt, results.Upgrade)
		fadeInArt(upgradeArt)
	else
		useTextFallback(upgradeArt, upgradeFallback, "Upgrade")
	end
end)

resolveButtonArt({ LockBase = TOP_ART.LockBase, Protected = TOP_ART.Protected }, function(results)
	lockArt = results
	local complete = results.LockBase ~= nil and results.Protected ~= nil
	lockArtRevealed = true
	updateBaseProtectionUI()
	if complete then
		fadeInArt(lockBaseArt)
	else
		useTextFallback(lockBaseArt, lockBaseFallback, "Lock Base / Protected")
	end
end)

local lockRequestInFlight = false

require(game:GetService("ReplicatedStorage"):WaitForChild("UIInputRouter")).Signal(lockBaseBtn, "Lock Base", { Kind = "Action" }):Connect(function()
	-- One request at a time: a second click while the first is still on its
	-- way to the server is ignored rather than queued.
	if lockRequestInFlight then return end

	if not lockRemote then
		warn("[MainHUD] Lock Base server remote is missing.")
		return
	end

	lockRequestInFlight = true
	local ok, result = pcall(function()
		return lockRemote:InvokeServer()
	end)
	lockRequestInFlight = false

	if not ok then
		warn("[MainHUD] Lock Base request failed:", result)
		return
	end

	if type(result) == "table" and result.ok == false then
		warn("[MainHUD] Lock Base rejected:", result.reason)
	end

	updateBaseProtectionUI()
end)

player:GetAttributeChangedSignal("BaseLockedUntil"):Connect(updateBaseProtectionUI)
player:GetAttributeChangedSignal("LockBaseCooldownUntil"):Connect(updateBaseProtectionUI)

-- The only timer updater for this control. It is started once, here, for the
-- life of the HUD (MainHUD is ResetOnSpawn = false, so respawns reuse it), and
-- it also catches expiry: when the time runs out the state flips back to
-- LOCK BASE on the next tick with no attribute change needed.
task.spawn(function()
	while gui.Parent do
		updateBaseProtectionUI()
		task.wait(0.25)
	end
end)

autoScale(actionBar)
scaleMultipliers[top] = CURRENCY_HUD_SCALE
scaleMultipliers[gemsPill] = CURRENCY_HUD_SCALE * GEMS_HUD_SCALE
autoScale(top)
autoScale(gemsPill)
autoScale(menu)
autoScale(playSlot)

-- ===== responsive HUD layout =====
-- Phones (compact): smaller top buttons, and the side menu becomes a small 2x2
-- grid of icon buttons tucked under Roblox's top-left icons, clear of the
-- thumbstick. The playtime button gets smaller too. Tablets and desktop keep
-- the original layout. Everything stays inside the device safe area.
local menuGrid = Instance.new("UIGridLayout")
menuGrid.CellSize = UDim2.fromOffset(88, 88)
menuGrid.CellPadding = UDim2.fromOffset(10, 10)
menuGrid.FillDirectionMaxCells = 2
menuGrid.SortOrder = Enum.SortOrder.LayoutOrder

-- Icon-only buttons on phones: remember each menu button's original layout.
local menuButtons = {}
for _, slot in ipairs(menu:GetChildren()) do
	if slot:IsA("Frame") then
		for _, button in ipairs(slot:GetChildren()) do
			if button:IsA("GuiButton") then
				local icon = button:FindFirstChild("Icon",true)
				local labelText = button:FindFirstChild("Label",true)
				table.insert(menuButtons, {
					slot = slot, slotSize = slot.Size, icon = icon, label = labelText,
					iconAnchor = icon and icon.AnchorPoint, iconPosition = icon and icon.Position, iconSize = icon and icon.Size,
				})
			end
		end
	end
end

local function setIconOnly(iconOnly)
	for _, item in ipairs(menuButtons) do
		if item.label then item.label.Visible = not iconOnly end
		if item.icon then
			item.icon.AnchorPoint = if iconOnly then Vector2.new(0.5, 0.5) else item.iconAnchor
			item.icon.Position = if iconOnly then UDim2.fromScale(0.5, 0.5) else item.iconPosition
			item.icon.Size = if iconOnly then UDim2.fromScale(0.74, 0.74) else item.iconSize
		end
	end
end

local function setMultipliers(values)
	for object, value in pairs(values) do
		scaleMultipliers[object] = value
		local refresh = scaleRefreshers[object]
		if refresh then refresh() end
	end
end

local hudLayoutKey = nil

local function applyHudLayout()
	if not UiResponsive then return end
	-- In this ScreenGui's own coordinates (it may already start at the safe
	-- edge), so the side zones sit at the real edges, not an inset further in.
	local safeOffset, safeSize = UiResponsive.SafeRectIn(gui)
	local rightInset = math.max(gui.AbsoluteSize.X - (safeOffset.X + safeSize.X), 0)
	local compact = UiResponsive.Layout() == "compact"

	local key = ("%s:%d:%d:%d"):format(tostring(compact), safeOffset.X, rightInset, UiResponsive.TopInset())
	if key == hudLayoutKey then return end
	hudLayoutKey = key

	if compact then
		-- ===== PHONE ZONES =====
		-- Top-left belongs to Roblox (menu / chat / mic). Our zones:
		--   LEFT  : action grid, then currencies (placeStardust), from the
		--           safe left edge, starting a section gap below the top bar
		--   RIGHT : one stack, Settings above Playtime (SettingsClient lines
		--           the gear up on this slot's centre), from the safe right edge
		--   TOP   : Upgrade / Lock Base, then the status column (HudStack)
		-- Every gap comes from the one spacing scale.
		local SP = UiResponsive.Space or { M = 12, L = 18 }
		-- Edge padding: ~2.5% of the usable width (never under the M gap).
		local edge = math.max(SP.M, math.floor(safeSize.X * 0.025 + 0.5))
		local zoneTop = math.max(UiResponsive.TopInset() - UiResponsive.ToScreen(gui.AbsolutePosition).Y, safeOffset.Y) + SP.L
		layout.Parent = nil
		menuGrid.Parent = menu
		menuGrid.CellPadding = UDim2.fromOffset(SP.M, SP.M)
		setIconOnly(true)
		menu.AnchorPoint = Vector2.new(0, 0)
		menu.Size = UDim2.fromOffset(88 * 2 + SP.M, 10)
		menu.Position = UDim2.fromOffset(safeOffset.X + edge, zoneTop)
		-- Right stack: the gear (40) sits on top, so Playtime starts below it.
		playSlot.AnchorPoint = Vector2.new(1, 0)
		playSlot.Position = UDim2.new(1, -(rightInset + edge), 0, zoneTop + 40 + SP.M)
		-- 0.7 of the new 228 is 160, which is what 0.8 of the old 196 came to, so
		-- phones keep the size they had while desktop gets the bigger button.
		-- Grid at full HUD scale: its cells stay comfortably tappable (~40-48 px).
		setMultipliers({ [actionBar] = 0.9, [top] = 0.9 * CURRENCY_HUD_SCALE, [gemsPill] = 0.9 * CURRENCY_HUD_SCALE * GEMS_HUD_SCALE, [menu] = 1, [playSlot] = 0.7 })
	else
		menuGrid.Parent = nil
		menuGrid.CellPadding = UDim2.fromOffset(10, 10)
		layout.Parent = menu
		setIconOnly(false)
		playSlot.AnchorPoint = Vector2.new(1, 0.5)
		actionBar.Position = UDim2.new(0.5, 0, 0, 14)
		menu.AnchorPoint = Vector2.new(0, 0.5)
		menu.Size = UDim2.fromOffset(184, 10)
		menu.Position = UDim2.new(0, safeOffset.X + 20, 0.5, 0)
		-- Further in from the edge and a little above centre: it was sitting
		-- tight against the screen edge with nothing around it.
		playSlot.Position = UDim2.new(1, -(rightInset + 14), 0.46, 0)
		setMultipliers({ [actionBar] = 1, [top] = CURRENCY_HUD_SCALE, [gemsPill] = CURRENCY_HUD_SCALE * GEMS_HUD_SCALE, [menu] = 1, [playSlot] = 1 })
	end
end

applyHudLayout()
if UiResponsive then
	UiResponsive.Changed:Connect(applyHudLayout)
end

-- Phones: Upgrade / Lock Base share the top-bar row only with real room to
-- spare beside Roblox's buttons (GuiService.TopbarInset is the part of that
-- row Roblox leaves free). Otherwise the pair drops just below the bar, on
-- the same centre line, so it never crowds the menu / chat / mic buttons.
local function placeTopActions()
	if not (UiResponsive and UiResponsive.Layout() == "compact") then return end
	local GuiServiceLocal = game:GetService("GuiService")
	local SP = UiResponsive.Space or { S = 8, L = 18, XL = 28 }
	local screenW = UiResponsive.Screen().X
	local halfW = actionBar.AbsoluteSize.X / 2
	local freeLeft = 0
	pcall(function() freeLeft = GuiServiceLocal.TopbarInset.Min.X end)
	local y = SP.S
	if screenW / 2 - halfW < freeLeft + SP.XL then
		y = UiResponsive.TopInset() + SP.S
	end
	if actionBar.Position.Y.Offset ~= y then
		actionBar.Position = UDim2.new(0.5, 0, 0, y)
	end
end
actionBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTopActions)

-- Phones: a window (Store, Upgrade, Playtime, ...) is its own state. While
-- one is open the gameplay HUD steps aside - action grid, top buttons,
-- Playtime and the status column - so the window is the only thing competing
-- for the small screen. The currencies stay (you see what you can spend).
-- Settings follows the same rule in their scripts.
local function refreshModalHud()
	local phone = UiResponsive ~= nil and UiResponsive.Layout() == "compact"
	local open = phone and GuiManager:GetCurrent() ~= nil
	menu.Visible = not open
	actionBar.Visible = not open
	playSlot.Visible = not open
	local stack = playerGui:FindFirstChild("HudStack")
	if stack and stack:IsA("ScreenGui") then stack.Enabled = not open end
end
GuiManager.Changed:Connect(refreshModalHud)
if UiResponsive then UiResponsive.Changed:Connect(refreshModalHud) end
if UiResponsive then UiResponsive.Changed:Connect(function() task.defer(placeTopActions) end) end
task.defer(placeTopActions)

-- ===== stardust placement =====
-- Desktop and tablets: right under the side menu, as marked. If there's no
-- room there (short windows), it tucks up toward the menu, clear of the bottom
-- edge. Phones: under the 2x2 menu grid in the
-- top-left, well away from the thumbstick.
local GuiService = game:GetService("GuiService")
-- Room kept clear at the bottom edge. (This used to be 84 for the small
-- Nibbles button bottom-left; that button is gone, so only a margin is left.)
local BOTTOM_MARGIN = 12
-- Where Gems sits under Stardust, as a share of the spare width between them:
-- 0 = same left edge, 0.5 = centred. A little left of centre reads as one
-- compact cluster.
local GEMS_SHIFT = 0.2

local function placeStardust()
	local screen = camera.ViewportSize
	if screen.X < 2 or menu.AbsoluteSize.Y < 2 then return end
	-- In this ScreenGui's own coordinates: an object's AbsolutePosition
	-- minus the ScreenGui's, whatever area (safe / full) the ScreenGui uses.
	local menuLeft = menu.AbsolutePosition.X - gui.AbsolutePosition.X
	local menuBottom = menu.AbsolutePosition.Y - gui.AbsolutePosition.Y + menu.AbsoluteSize.Y
	local height = top.AbsoluteSize.Y
	local compact = UiResponsive and UiResponsive.Layout() == "compact"
	local SP = UiResponsive and UiResponsive.Space or { M = 12, L = 18 }
	local gap = if compact then SP.L else 14

	-- The cluster sits a little left of the side menu's edge (CLUSTER_NUDGE
	-- design px), but never closer to the screen edge than 1.5% of its width.
	local pixel = top.AbsoluteSize.Y / math.max(top.Size.Y.Offset, 1)
	local CLUSTER_NUDGE = if compact then 0 else 6   -- phones: same left edge as the grid
	-- One currency cluster, placed as a group: Stardust on top, the narrower
	-- Gems panel centred right under it (same centre X), a 6 px gap between.
	local GEMS_GAP = 6 * pixel
	local width = top.AbsoluteSize.X
	local gemsSize = gemsPill.AbsoluteSize
	local total = height + GEMS_GAP + gemsSize.Y
	local x = math.max(menuLeft - CLUSTER_NUDGE * pixel, screen.X * 0.015)
	local y = menuBottom + gap + (if compact then 0 else 4 * pixel)
	-- Always under Inventory, clear of the bottom edge. On short windows
	-- the gaps tighten first, then the cluster tucks up toward the menu.
	if not compact and y + total > screen.Y - BOTTOM_MARGIN then
		GEMS_GAP = 4 * pixel
		total = height + GEMS_GAP + gemsSize.Y
		y = math.max(screen.Y - BOTTOM_MARGIN - total, menuBottom + 4)
	end
	top.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	-- Desktop: Gems a little left of centre under Stardust. Phones: one left edge for the
	-- whole left zone (grid, Stardust, Gems).
	local gemsX = if compact then x else x + (width - gemsSize.X) * GEMS_SHIFT
	gemsPill.Position = UDim2.fromOffset(
		math.floor(gemsX + 0.5),
		math.floor(y + height + GEMS_GAP + gemsSize.Y / 2 + 0.5))
end

menu:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeStardust)
menu:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeStardust)
top:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeStardust)
gemsPill:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeStardust)
camera:GetPropertyChangedSignal("ViewportSize"):Connect(placeStardust)
if UiResponsive then
	UiResponsive.Changed:Connect(function() task.defer(placeStardust) end)
end
task.defer(placeStardust)
-- Upgrade popup uses its own responsive layout above