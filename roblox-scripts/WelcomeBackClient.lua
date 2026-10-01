-- WelcomeBackClient (LocalScript in StarterPlayer > StarterPlayerScripts)
-- Offline earnings popup. Displays the server's authoritative value only.
--
-- Structure (one UIScale per object, nothing visible outside Card):
--   WelcomeBackHUD            ScreenGui
--     Backdrop                full-screen dim
--     Wrapper                 responsive UIScale
--       WelcomeBackPanel      registered with GuiManager, transparent
--         Card                everything visible, pop UIScale

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local MarketplaceService=game:GetService("MarketplaceService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local GuiStyle = require(ReplicatedStorage:WaitForChild("GuiStyle"))

local UIAssets do
	-- Image ids live in ReplicatedStorage > UIAssets. Missing module = no art,
	-- never a broken HUD.
	local module = ReplicatedStorage:WaitForChild("UIAssets", 10)
	if module then
		UIAssets = require(module)
	else
		warn("[WelcomeBack] ReplicatedStorage > UIAssets is missing: icons will be blank.")
		UIAssets = {}
	end
end

local UiResponsive do
	local module = ReplicatedStorage:FindFirstChild("UiResponsive")
	local ok, result = pcall(function() return module and require(module) end)
	UiResponsive = if ok and type(result) == "table" then result else nil
end

local Format do
	local module = ReplicatedStorage:WaitForChild("NumberFormatter", 10)
	Format = module and require(module) or {
		Abbreviate = function(n) return tostring(math.floor(tonumber(n) or 0)) end,
	}
end

local GuiManager do
	local module = ReplicatedStorage:FindFirstChild("GuiManager")
		or ReplicatedStorage:FindFirstChild("PopupManager")
	GuiManager = module and require(module) or nil
end

local FONT = GuiStyle.FONT

local COLOR = {
	Panel = Color3.fromRGB(10, 14, 32),
	Header = Color3.fromRGB(5, 8, 22),
	Inset = Color3.fromRGB(18, 24, 52),
	Rim = Color3.fromRGB(58, 118, 222),
	RimSoft = Color3.fromRGB(44, 74, 148),
	Navy = Color3.fromRGB(8, 12, 28),
	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(138, 160, 205),
	Gold = Color3.fromRGB(255, 215, 90),
	GoldDeep = Color3.fromRGB(226, 158, 28),
	Green = Color3.fromRGB(56, 222, 104),
	Track = Color3.fromRGB(28, 38, 76),
	Fill = Color3.fromRGB(78, 162, 255),
	Medallion = Color3.fromRGB(22, 34, 78),
	InnerRing = Color3.fromRGB(118, 186, 255),
	Spark = Color3.fromRGB(255, 244, 196),
}

-- The popup's corner radius, in pixels. The card, its shadow and the header
-- all read this, so the silhouette is defined once.
local CARD_CORNER = 30

-- Top-to-bottom layout. Every element has a fixed slot, so nothing can overlap.
local LAYOUT = {
	Width = 640,
	Height = 660,
	HeaderHeight = 72,
	AwayY = 78,
	MedallionY = 128,
	MedallionSize = 88,
	EarnedY = 224,
	RewardY = 244,
	RewardHeight = 48,
	CurrencyY = 296,
	StripY = 330,
	StripHeight = 48,
	ButtonHeight = 80,
	ButtonBottom = 50,
	SideInset = 24,
}

local MOTION = {
	Pop = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Settle = TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Close = TweenInfo.new(0.19, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
	Soft = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Shine = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Count = 0.45,
}

local function makeSound(name, id, volume)
	local existing = SoundService:FindFirstChild(name)
	if existing then return existing end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local openSound = makeSound("WelcomeBackOpenSound", "rbxassetid://7218169592", 0.5)
local chimeSound = makeSound("WelcomeBackChimeSound", "rbxassetid://7218169592", 0.42)

local function play(sound)
	if sound and sound.Volume > 0 then
		sound.TimePosition = 0
		sound:Play()
	end
end

-- ===================== HELPERS =====================
-- Every label is built here so a transparent background is never forgotten.
local function makeLabel(props)
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "Label"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = FONT
	label.TextScaled = true
	label.Text = props.Text or ""
	label.TextColor3 = props.Color or COLOR.Text
	label.TextXAlignment = props.AlignX or Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.AnchorPoint = props.AnchorPoint or Vector2.zero
	label.Position = props.Position
	label.Size = props.Size
	label.ZIndex = props.ZIndex or 1
	label.Parent = props.Parent

	if props.Max then
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = props.Max
		cap.Parent = label
	end

	if props.Stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = props.Stroke
		stroke.Color = COLOR.Navy
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label
	end

	return label
end

local function makeFrame(props)
	local frame = Instance.new("Frame")
	frame.Name = props.Name or "Frame"
	frame.BackgroundColor3 = props.Color or COLOR.Inset
	frame.BackgroundTransparency = props.Transparency or 0
	frame.BorderSizePixel = 0
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.Position = props.Position or UDim2.new()
	frame.Size = props.Size
	frame.ZIndex = props.ZIndex or 1
	frame.Parent = props.Parent
	return frame
end

-- Reversible descendant fade; each closing sequence owns and cancels its tweens.
local function createFader(root)
	local saved={}
	local running={}
	local function cancel()
		for _,t in ipairs(running) do t:Cancel() end
		table.clear(running)
	end
	local function restore()
		cancel()
		for object,properties in pairs(saved) do
			if object.Parent then for key,value in pairs(properties) do object[key]=value end end
		end
		table.clear(saved)
	end
	local function fade(duration)
		cancel()
		local objects=root:GetDescendants();table.insert(objects,root)
		for _,object in ipairs(objects) do
			local properties={}
			if object:IsA("GuiObject") then properties.BackgroundTransparency=object.BackgroundTransparency end
			if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
				properties.TextTransparency=object.TextTransparency
				properties.TextStrokeTransparency=object.TextStrokeTransparency
			elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then properties.ImageTransparency=object.ImageTransparency
			elseif object:IsA("UIStroke") then properties.Transparency=object.Transparency end
			if next(properties) then
				saved[object]=saved[object] or properties
				local goal={};for key in pairs(properties) do goal[key]=1 end
				local t=TweenService:Create(object,TweenInfo.new(duration,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),goal)
				table.insert(running,t);t:Play()
			end
		end
	end
	script.Destroying:Connect(cancel)
	return {Restore=restore,Fade=fade}
end

-- ===================== SHELL =====================
local old = playerGui:FindFirstChild("WelcomeBackHUD")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "WelcomeBackHUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.DisplayOrder = 8
gui.Parent = playerGui

local dim = makeFrame({
	Name = "Backdrop",
	Parent = gui,
	Size = UDim2.fromScale(1, 1),
	Color = Color3.fromRGB(6, 10, 26),
	Transparency = 1,
	ZIndex = 1,
})
dim.Visible = false

local wrapper = makeFrame({
	Name = "Wrapper",
	Parent = gui,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(LAYOUT.Width, LAYOUT.Height),
	Transparency = 1,
	ZIndex = 2,
})

local responsive = Instance.new("UIScale")
responsive.Name = "ResponsiveScale"
responsive.Parent = wrapper

local drawerDesktop=false
-- Set once the player dismisses the 2X offer. The wrapper then stops reserving
-- room for it, and because the wrapper is anchored centre that is what pulls
-- the main panel back into the middle of the screen.
local drawerDismissed=false
local refreshTimeOfferLayout=function() end
-- The area the popup must fit: the device safe area (notches, rounded
-- corners, home bar), and past 1080p it may grow with the screen.
local function fitArea()
	camera=workspace.CurrentCamera or camera
	local vp=camera.ViewportSize
	if UiResponsive and UiResponsive.SafeRect then
		local ok,_,size=pcall(UiResponsive.SafeRect)
		if ok and typeof(size)=="Vector2" and size.X>1 then vp=size end
	end
	return vp,1.05*math.clamp(math.min(vp.X/1920,vp.Y/1080),1,1.6)
end
local function popupScaleFor(width)
	local vp,maxScale=fitArea()
	-- Phones: a small edge margin, so the card uses the short screen height
	-- instead of wasting it (bigger card = more readable text).
	local margin=if math.min(vp.X,vp.Y)<520 then 14 else 48
	return math.max(.1,math.min((vp.X-margin)/(width+24),(vp.Y-margin)/(LAYOUT.Height+24),maxScale))
end
local function refreshScale()
	local vp=fitArea()
	if vp.X<1 or vp.Y<1 then return end
	drawerDesktop=vp.X>=1100 and vp.Y>=650
	local width=LAYOUT.Width+((drawerDesktop and not drawerDismissed) and 336 or 0)
	wrapper.Size=UDim2.fromOffset(width,LAYOUT.Height)
	responsive.Scale=popupScaleFor(width)
	wrapper.Position=UDim2.fromScale(.5,.5)
	refreshTimeOfferLayout()
end
refreshScale()
if UiResponsive then
	UiResponsive.Changed:Connect(refreshScale)
else
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
end

-- GuiManager owns this frame's visibility and its UIScale. Nothing else here.
local panel = makeFrame({
	Name = "WelcomeBackPanel",
	Parent = wrapper,
	Size = UDim2.fromOffset(LAYOUT.Width, LAYOUT.Height),
	Transparency = 1,
})
panel.Visible = false

local card = makeFrame({
	Name = "Card",
	Parent = panel,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	Color = COLOR.Panel,
	Transparency = 0.1,
})
card.ClipsDescendants = true
GuiStyle.Corner(card, 0).CornerRadius = UDim.new(0, CARD_CORNER)
GuiStyle.Stroke(card, COLOR.Rim, 3)

local cardScale = Instance.new("UIScale")
cardScale.Name = "PopScale"
cardScale.Parent = card

-- ===================== HEADER =====================
local header = makeFrame({
	Name = "Header",
	Parent = card,
	Size = UDim2.new(1, 0, 0, LAYOUT.HeaderHeight),
	Color = COLOR.Header,
	Transparency = 0.1,
})

-- ClipsDescendants clips to the card's rectangle, never to its corner radius,
-- so a full-width header paints over both top curves and they read square.
-- The header carries the same radius instead. Its own bottom corners would
-- then cut two notches above the separator, so HeaderFoot fills that band back
-- in: same paint, same transparency, no seam.
local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, CARD_CORNER)
headerCorner.Parent = header

local headerFoot = makeFrame({
	Name = "HeaderFoot",
	Parent = header,
	Position = UDim2.new(0, 0, 1, -(CARD_CORNER + 2)),
	Size = UDim2.new(1, 0, 0, CARD_CORNER + 2),
	Color = COLOR.Header,
	Transparency = 0.1,
})

makeFrame({
	Name = "HeaderLine",
	Parent = header,
	Position = UDim2.new(0, 0, 1, -3),
	Size = UDim2.new(1, 0, 0, 3),
	Color = COLOR.Rim,
	ZIndex = 3,
})

makeLabel({
	Name = "Title",
	Parent = header,
	Text = "WELCOME BACK!",
	Position = UDim2.fromOffset(22, 14),
	Size = UDim2.new(1, -44, 0, 44),
	AlignX = Enum.TextXAlignment.Left,
	Max = 34,
	Stroke = 3,
	ZIndex = 3,
})

-- ===================== MEDALLION =====================
makeLabel({
	Name = "Away",
	Parent = card,
	Text = "YOUR COSMOS KEPT WORKING",
	Color = COLOR.TextDim,
	Position = UDim2.new(0, 0, 0, LAYOUT.AwayY),
	Size = UDim2.new(1, 0, 0, 20),
	Max = 16,
})

local medallion = makeFrame({
	Name = "Medallion",
	Parent = card,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, LAYOUT.MedallionY),
	Size = UDim2.fromOffset(LAYOUT.MedallionSize, LAYOUT.MedallionSize),
	Color = COLOR.Medallion,
})
GuiStyle.Corner(medallion, 1)
GuiStyle.Stroke(medallion, COLOR.Rim, 4)

local medallionScale = Instance.new("UIScale")
medallionScale.Parent = medallion

-- True circle: a square frame at full corner radius. A wide frame would give
-- a pill shape, which is what the old orbit line looked like.
local innerRing = makeFrame({
	Name = "InnerRing",
	Parent = medallion,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.8, 0.8),
	Transparency = 1,
	ZIndex = 1,
})
GuiStyle.Corner(innerRing, 1)
local innerRingStroke = Instance.new("UIStroke")
innerRingStroke.Thickness = 2
innerRingStroke.Color = COLOR.InnerRing
innerRingStroke.Transparency = 0.7
innerRingStroke.Parent = innerRing

-- The offline reward artwork. Centred, untinted, with room for its glow.
local star = Instance.new("ImageLabel")
star.Name = "Star"
star.BackgroundTransparency = 1
star.BorderSizePixel = 0
star.AnchorPoint = Vector2.new(0.5, 0.5)
star.Position = UDim2.new(0.5, 0, 0.5, 0)
star.Size = UDim2.fromScale(0.78, 0.78)
star.Image = UIAssets.WelcomeBackStardust or ""
star.ScaleType = Enum.ScaleType.Fit
star.ZIndex = 2
star.Parent = medallion

local starScale = Instance.new("UIScale")
starScale.Parent = star

-- Shine is a gradient on a copy of the glyph, so the sweep is masked to the
-- star's own shape. A separate rotated frame ignores ClipsDescendants and
-- draws straight across the card.
local shine = Instance.new("ImageLabel")
shine.Name = "Shine"
shine.BackgroundTransparency = 1
shine.BorderSizePixel = 0
shine.Size = UDim2.fromScale(1, 1)
shine.Image = star.Image
shine.ScaleType = Enum.ScaleType.Fit
shine.ImageColor3 = Color3.new(1, 1, 1)
shine.ZIndex = 3
shine.Parent = star
local shineGrad = Instance.new("UIGradient")
shineGrad.Rotation = 25
shineGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.42, 1),
	NumberSequenceKeypoint.new(0.5, 0.3),
	NumberSequenceKeypoint.new(0.58, 1),
	NumberSequenceKeypoint.new(1, 1),
})
shineGrad.Offset = Vector2.new(-1, 0)
shineGrad.Parent = shine

local MEDALLION_CENTRE_Y = LAYOUT.MedallionY + LAYOUT.MedallionSize / 2

local sparkles = {}
for index = 1, 5 do
	sparkles[index] = makeLabel({
		Name = "Sparkle",
		Parent = card,
		Text = "✦",
		Color = COLOR.Spark,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, MEDALLION_CENTRE_Y),
		Size = UDim2.fromOffset(16, 16),
		ZIndex = 5,
	})
	sparkles[index].TextTransparency = 1
end

-- ===================== REWARD =====================
makeLabel({
	Name = "Earned",
	Parent = card,
	Text = "YOU EARNED",
	Color = COLOR.TextDim,
	Position = UDim2.new(0, 0, 0, LAYOUT.EarnedY),
	Size = UDim2.new(1, 0, 0, 18),
	Max = 15,
})

local rewardHolder = makeFrame({
	Name = "Reward",
	Parent = card,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, LAYOUT.RewardY),
	Size = UDim2.new(1, -40, 0, LAYOUT.RewardHeight),
	Transparency = 1,
})

local rewardScale = Instance.new("UIScale")
rewardScale.Parent = rewardHolder

local rewardText = makeLabel({
	Name = "Amount",
	Parent = rewardHolder,
	Text = "+★0",
	Color = COLOR.Green,
	Position = UDim2.new(),
	Size = UDim2.fromScale(1, 1),
	Max = 52,
	Stroke = 4,
})

makeLabel({
	Name = "Currency",
	Parent = card,
	Text = "STARDUST",
	Color = COLOR.Gold,
	Position = UDim2.new(0, 0, 0, LAYOUT.CurrencyY),
	Size = UDim2.new(1, 0, 0, 18),
	Max = 16,
	Stroke = 2,
})

-- ===================== OFFLINE STRIP =====================
local strip = makeFrame({
	Name = "OfflineStrip",
	Parent = card,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, LAYOUT.StripY),
	Size = UDim2.new(1, -LAYOUT.SideInset * 2, 0, LAYOUT.StripHeight),
	Color = COLOR.Inset,
	Transparency = 0.2,
})
GuiStyle.Corner(strip, 0.28)
GuiStyle.Stroke(strip, COLOR.RimSoft, 2)

local stripLabel = makeLabel({
	Name = "OfflineLabel",
	Parent = strip,
	Text = "◷ OFFLINE TIME",
	Color = COLOR.TextDim,
	Position = UDim2.new(0, 14, 0, 7),
	Size = UDim2.new(0.55, -14, 0, 16),
	AlignX = Enum.TextXAlignment.Left,
	Max = 13,
})

local stripValue = makeLabel({
	Name = "OfflineValue",
	Parent = strip,
	Text = "--",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 6),
	Size = UDim2.new(0.45, -14, 0, 18),
	AlignX = Enum.TextXAlignment.Right,
	Max = 16,
})

local barTrack = makeFrame({
	Name = "Track",
	Parent = strip,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -9),
	Size = UDim2.new(1, -28, 0, 10),
	Color = COLOR.Track,
})
GuiStyle.Corner(barTrack, 1)

local barFill = makeFrame({
	Name = "Fill",
	Parent = barTrack,
	Size = UDim2.fromScale(0, 1),
	Color = COLOR.Fill,
})
GuiStyle.Corner(barFill, 1)

-- ===================== CONTINUE =====================
-- The reward is granted server-side before this fires, so this only dismisses.
local cta = Instance.new("TextButton")
cta.Name = "Continue"
cta.AnchorPoint = Vector2.new(0.5, 1)
cta.Position = UDim2.new(0.5, 0, 1, -LAYOUT.ButtonBottom)
cta.Size = UDim2.new(1, -LAYOUT.SideInset * 2, 0, LAYOUT.ButtonHeight)
cta.BackgroundColor3 = GuiStyle.COL.Green
cta.AutoButtonColor = false
cta.Text = "CONTINUE"
cta.Font = FONT
cta.TextScaled = true
cta.TextColor3 = COLOR.Text
cta.Parent = card
GuiStyle.Corner(cta, 0.28)
GuiStyle.Stroke(cta, GuiStyle.COL.GreenDark, 3)
GuiStyle.Gradient(cta, Color3.fromRGB(255, 255, 255), Color3.fromRGB(198, 198, 198))
GuiStyle.TextStroke(cta, 3)

local ctaCap = Instance.new("UITextSizeConstraint")
ctaCap.MaxTextSize = 36
ctaCap.Parent = cta
local ctaPad = Instance.new("UIPadding")
ctaPad.PaddingTop = UDim.new(0, 10)
ctaPad.PaddingBottom = UDim.new(0, 10)
ctaPad.Parent = cta

-- Two choices; normal earnings have already been credited by the server.
cta.AnchorPoint=Vector2.new(0,1)
cta.Position=UDim2.new(0,LAYOUT.SideInset,1,-LAYOUT.ButtonBottom)
cta.Size=UDim2.new(.45,-LAYOUT.SideInset-8,0,88)
cta.Text="CLAIM"
local doubleButton=cta:Clone()
doubleButton.Name="DoubleOffline";doubleButton.AnchorPoint=Vector2.new(1,1)
doubleButton.Position=UDim2.new(1,-LAYOUT.SideInset,1,-LAYOUT.ButtonBottom)
doubleButton.Size=UDim2.new(.55,-LAYOUT.SideInset-8,0,88)
doubleButton.BackgroundColor3=Color3.fromRGB(255,184,32)
doubleButton.Text="2X CLAIM · 19 R$\nCOMING SOON"
doubleButton.Parent=card
local outline=doubleButton:FindFirstChildOfClass("UIStroke")
if outline then outline.Color=Color3.fromRGB(153,91,9) end
local purchaseReady=false
local currentOffer=nil
local purchasing=false
local offerVersion=0
local refreshOfferVisuals=function() end
local function configureDouble(data)
	currentOffer=data;purchasing=data.purchasePending==true;offerVersion+=1
	local version=offerVersion
	refreshOfferVisuals()
	purchaseReady=false
	doubleButton.Active=true
	doubleButton.Text=purchasing and "PURCHASE PENDING" or "2X CLAIM · 19 R$\nCOMING SOON"
	if not data.doubleAvailable or purchasing then return end
	doubleButton.Text="CHECKING PRICE..."
	task.spawn(function()
		local ok,info=pcall(MarketplaceService.GetProductInfo,MarketplaceService,data.doubleProductId,Enum.InfoType.Product)
		if offerVersion~=version then return end
		if not ok or not info or not tonumber(info.PriceInRobux) then doubleButton.Text="2X UNAVAILABLE";return end
		currentOffer.price=info.PriceInRobux
		doubleButton.Text="2X CLAIM · "..info.PriceInRobux.." R$\nTOTAL "..Format.Abbreviate((data.amount or 0)*2)
		purchaseReady=true;doubleButton.Active=true
	end)
end


-- Wide, uncluttered CTA: one title, one horizontal price badge, separate status line.
doubleButton.Active=true;doubleButton.Selectable=true
doubleButton.TextTransparency=1;doubleButton.TextStrokeTransparency=1
doubleButton.ClipsDescendants=true;doubleButton.ZIndex=3
doubleButton.BackgroundColor3=Color3.new(1,1,1)
for _,o in ipairs(doubleButton:GetChildren()) do
	if o:IsA("UIGradient") or o:IsA("UIStroke") or o:IsA("UIPadding") or o:IsA("UITextSizeConstraint") then o:Destroy() end
end
for _,button in ipairs({cta,doubleButton}) do
	local corner=button:FindFirstChildOfClass("UICorner")
	if corner then corner.CornerRadius=UDim.new(0,18) end
end
local border=Instance.new("UIStroke");border.Color=Color3.fromRGB(136,79,7);border.Thickness=3.5
border.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;border.Parent=doubleButton
local gold=Instance.new("UIGradient");gold.Rotation=90
gold.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,226,94)),ColorSequenceKeypoint.new(.36,Color3.fromRGB(255,194,27)),ColorSequenceKeypoint.new(.54,Color3.fromRGB(255,235,111)),ColorSequenceKeypoint.new(.72,Color3.fromRGB(255,195,31)),ColorSequenceKeypoint.new(1,Color3.fromRGB(255,163,0))})
gold.Parent=doubleButton
local shine=Instance.new("Frame");shine.Name="GoldGlint";shine.Size=UDim2.fromScale(1,1)
shine.BorderSizePixel=0;shine.BackgroundColor3=Color3.new(1,1,1);shine.Active=false;shine.ZIndex=4;shine.Parent=doubleButton
local shineCorner=Instance.new("UICorner");shineCorner.CornerRadius=UDim.new(0,18);shineCorner.Parent=shine
local shineMask=Instance.new("UIGradient");shineMask.Rotation=22;shineMask.Offset=Vector2.new(-1.4,0)
shineMask.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.38,1),NumberSequenceKeypoint.new(.49,.64),NumberSequenceKeypoint.new(.57,1),NumberSequenceKeypoint.new(1,1)})
shineMask.Parent=shine
local big=Instance.new("TextLabel");big.Name="ClaimTitle";big.BackgroundTransparency=1
big.Position=UDim2.new(0,12,0,9);big.Size=UDim2.new(1,-108,0,37)
big.Font=FONT;big.Text="2X CLAIM";big.TextScaled=true;big.TextColor3=Color3.new(1,1,1)
big.Active=false;big.ZIndex=5;big.Parent=doubleButton
local textOutline=Instance.new("UIStroke");textOutline.Color=Color3.fromRGB(39,23,7);textOutline.Thickness=2.8;textOutline.Parent=big
local cap=Instance.new("UITextSizeConstraint");cap.MaxTextSize=33;cap.MinTextSize=10;cap.Parent=big
local badge=Instance.new("Frame");badge.Name="PriceBadge";badge.AnchorPoint=Vector2.new(1,.5)
badge.Position=UDim2.new(1,-12,.5,0);badge.Size=UDim2.fromOffset(80,40)
badge.BackgroundColor3=Color3.fromRGB(255,221,100);badge.BorderSizePixel=0;badge.Active=false;badge.ZIndex=5;badge.Parent=doubleButton
local badgeCorner=Instance.new("UICorner");badgeCorner.CornerRadius=UDim.new(0,12);badgeCorner.Parent=badge
local price=Instance.new("TextLabel");price.Name="RobuxPrice";price.BackgroundTransparency=1
price.Position=UDim2.fromOffset(5,3);price.Size=UDim2.new(1,-10,1,-6)
price.Font=FONT;price.TextScaled=true;price.TextColor3=Color3.fromRGB(112,64,12);price.Active=false;price.ZIndex=6;price.Parent=badge
local priceCap=Instance.new("UITextSizeConstraint");priceCap.MaxTextSize=21;priceCap.MinTextSize=8;priceCap.Parent=price
local detail=Instance.new("TextLabel");detail.Name="PurchaseStatus";detail.BackgroundTransparency=1
detail.Position=UDim2.new(0,LAYOUT.SideInset,1,-33);detail.Size=UDim2.new(1,-LAYOUT.SideInset*2,0,20)
detail.Font=FONT;detail.TextScaled=true;detail.TextColor3=COLOR.TextDim;detail.Active=false;detail.ZIndex=3;detail.Parent=card
local detailCap=Instance.new("UITextSizeConstraint");detailCap.MaxTextSize=14;detailCap.MinTextSize=8;detailCap.Parent=detail

-- Premium typography uses a single thin outline, without a duplicate shadow layer.
local function goldenText(label)
	label.TextColor3=Color3.new(1,1,1);label.TextStrokeTransparency=1
	local gradient=Instance.new("UIGradient");gradient.Rotation=90
	gradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,252,215)),ColorSequenceKeypoint.new(.46,Color3.fromRGB(255,221,104)),ColorSequenceKeypoint.new(1,Color3.fromRGB(241,162,34))})
	gradient.Parent=label
end
big.TextColor3=Color3.fromRGB(255,243,179) -- Solid cream-gold fill for clear contrast.
local title=header:FindFirstChild("Title")
if title then
	goldenText(title)
	local stroke=title:FindFirstChildOfClass("UIStroke");if stroke then stroke.Thickness=1.4 end
end
local amountStroke=rewardText:FindFirstChildOfClass("UIStroke")
if amountStroke then amountStroke.Thickness=2;amountStroke.Color=Color3.fromRGB(10,37,25) end
card.BackgroundColor3=Color3.new(1,1,1)
local panelGradient=Instance.new("UIGradient");panelGradient.Rotation=90
panelGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(8,13,31)),ColorSequenceKeypoint.new(.42,Color3.fromRGB(19,31,59)),ColorSequenceKeypoint.new(1,Color3.fromRGB(8,14,32))});panelGradient.Parent=card
local medallionGradient=Instance.new("UIGradient");medallionGradient.Rotation=45
medallionGradient.Color=ColorSequence.new(Color3.fromRGB(182,221,255),Color3.fromRGB(81,113,185));medallionGradient.Parent=medallion
local trackGradient=Instance.new("UIGradient");trackGradient.Color=ColorSequence.new(Color3.fromRGB(124,225,255),Color3.fromRGB(81,135,255));trackGradient.Parent=barFill
local comparison=makeFrame({Name="RewardComparison",Parent=card,Position=UDim2.new(0,0,0,390),Size=UDim2.new(1,0,0,118),Transparency=1,ZIndex=2})
makeLabel({Name="ComparisonCaption",Parent=comparison,Text="DOUBLE YOUR REWARD",Color=COLOR.TextDim,Position=UDim2.new(0,0,0,0),Size=UDim2.new(1,0,0,20),Max=16})
local normalCard=makeFrame({Name="NormalReward",Parent=comparison,Position=UDim2.new(0,LAYOUT.SideInset,0,28),Size=UDim2.new(.5,-LAYOUT.SideInset-10,0,88),Color=Color3.fromRGB(10,20,37),ZIndex=2})
local premiumCard=makeFrame({Name="DoubleReward",Parent=comparison,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-LAYOUT.SideInset,0,28),Size=UDim2.new(.5,-LAYOUT.SideInset-10,0,88),Color=Color3.fromRGB(31,27,39),ZIndex=2})
GuiStyle.Corner(normalCard,.16);GuiStyle.Corner(premiumCard,.16)
GuiStyle.Stroke(normalCard,Color3.fromRGB(50,81,126),1)
GuiStyle.Stroke(premiumCard,Color3.fromRGB(244,190,66),2)
makeLabel({Parent=normalCard,Text="NORMAL",Color=COLOR.TextDim,Position=UDim2.new(0,12,0,9),Size=UDim2.new(1,-24,0,23),Max=18})
local premiumTitle=makeLabel({Parent=premiumCard,Text="2X REWARD",Color=COLOR.Gold,Position=UDim2.new(0,12,0,9),Size=UDim2.new(1,-24,0,23),Max=18})
goldenText(premiumTitle)
local normalAmount=makeLabel({Name="NormalAmount",Parent=normalCard,Text="--",Color=Color3.fromRGB(115,223,162),Position=UDim2.new(0,12,0,31),Size=UDim2.new(1,-24,0,35),Max=25})
local doubleAmount=makeLabel({Name="DoubleAmount",Parent=premiumCard,Text="--",Color=COLOR.Green,Position=UDim2.new(0,12,0,31),Size=UDim2.new(1,-24,0,35),Max=35})
local transfer=makeLabel({Name="Transfer",Parent=comparison,Text="→",Color=COLOR.Gold,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,0,72),Size=UDim2.fromOffset(24,34),Max=31,ZIndex=3})
local gift=Instance.new("TextLabel");gift.Name="DoubledRewardCaption";gift.BackgroundTransparency=1
gift.Position=UDim2.new(0,12,0,49);gift.Size=UDim2.new(1,-108,0,25)
gift.Font=FONT;gift.TextScaled=true;gift.TextColor3=Color3.fromRGB(95,51,8);gift.Active=false;gift.ZIndex=5;gift.Parent=doubleButton
local giftCap=Instance.new("UITextSizeConstraint");giftCap.MaxTextSize=19;giftCap.MinTextSize=8;giftCap.Parent=gift
-- A blue orbit with four quiet stars gives the medallion depth without a particle loop.
local orbit=makeFrame({Name="MedallionOrbit",Parent=medallion,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(1.13,1.13),Transparency=1,ZIndex=1})
GuiStyle.Corner(orbit,1)
local orbitLine=Instance.new("UIStroke");orbitLine.Color=Color3.fromRGB(103,159,245);orbitLine.Transparency=.65;orbitLine.Thickness=1;orbitLine.Parent=orbit
for i=1,4 do
	local a=i*math.pi/2+.32
	makeLabel({Name="OrbitStar",Parent=orbit,Text="✦",Color=COLOR.Gold,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5+.5*math.cos(a),.5+.5*math.sin(a)),Size=UDim2.fromOffset(10,10),Max=10,ZIndex=2})
end

local function syncCopy()
	local value=doubleButton.Text
	local amount=tonumber(currentOffer and currentOffer.amount) or 0
	normalAmount.Text=Format.Abbreviate(amount)
	doubleAmount.Text=Format.Abbreviate(amount*2)
	gift.Text="GET ★ "..Format.Abbreviate(amount*2)
	price.Text=tostring(currentOffer and currentOffer.price or 19).." R$"
	big.Text="2X CLAIM"
	if value:find("2X CLAIMED",1,true) then
		big.Text="CLAIMED!";gift.Text="BONUS ADDED";detail.Text="Your double reward has been added."
	elseif purchasing then
		big.Text="WAITING...";detail.Text="Waiting for Roblox to confirm your purchase."
	elseif value:find("COMING SOON!",1,true) then
		detail.Text="Coming soon - your normal earnings are already yours."
	elseif not currentOffer or (tonumber(currentOffer.doubleProductId) or 0)<=0 then
		detail.Text="2X COMING SOON · Your Stardust is ready to claim."
	elseif not currentOffer.doubleAvailable then
		detail.Text="No double bonus is available for this reward."
	elseif value:find("CHECKING",1,true) then
		detail.Text="Checking the purchase price..."
	elseif value:find("TOTAL ",1,true) then
		detail.Text=""
	else
		detail.Text=value:gsub("\n"," - ")
	end
end
refreshOfferVisuals=syncCopy
doubleButton:GetPropertyChangedSignal("Text"):Connect(syncCopy)
syncCopy()
local buttonScale=Instance.new("UIScale");buttonScale.Parent=doubleButton
local hover=false
local bounceTween
local function bounce(value)
	if bounceTween then bounceTween:Cancel() end
	if player:GetAttribute("ReduceMotion")==true then buttonScale.Scale=1;return end
	bounceTween=TweenService:Create(buttonScale,TweenInfo.new(.16,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=value});bounceTween:Play()
end
doubleButton.MouseEnter:Connect(function() hover=true;bounce(1.025) end)
doubleButton.MouseLeave:Connect(function() hover=false;bounce(1) end)
doubleButton.MouseButton1Down:Connect(function() bounce(.965) end)
doubleButton.MouseButton1Up:Connect(function() bounce(hover and 1.025 or 1) end)
doubleButton.Activated:Connect(function() bounce(.965);task.delay(.10,function() if doubleButton.Parent then bounce(hover and 1.025 or 1) end end) end)
local shineTween
local transferTween
local orbitTween
local alive=true
local function glint()
	if shineTween then shineTween:Cancel() end
	shineMask.Offset=Vector2.new(-1.4,0)
	if not panel.Visible or panel:GetAttribute("Closing")==true or player:GetAttribute("ReduceMotion")==true then return end
	shineTween=TweenService:Create(shineMask,TweenInfo.new(.85,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Offset=Vector2.new(1.4,0)})
	shineTween:Play()
	if transferTween then transferTween:Cancel() end
	transfer.TextTransparency=.55
	transferTween=TweenService:Create(transfer,TweenInfo.new(.7,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,0,true),{TextTransparency=0})
	transferTween:Play()
	if orbitTween then orbitTween:Cancel() end
	orbitTween=TweenService:Create(orbit,TweenInfo.new(1.7,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,0,true),{Rotation=orbit.Rotation==0 and 4 or 0})
	orbitTween:Play()
end
panel:GetPropertyChangedSignal("Visible"):Connect(function()
	buttonScale.Scale=1
	if not panel.Visible then
		if transferTween then transferTween:Cancel() end
		if orbitTween then orbitTween:Cancel() end
	end
	if panel.Visible then glint() elseif shineTween then shineTween:Cancel();shineMask.Offset=Vector2.new(-1.4,0) end
end)
task.spawn(function()
	while alive and doubleButton.Parent do
		task.wait(3.8)
		if alive and panel.Visible then glint() end
	end
end)
script.Destroying:Connect(function()
	alive=false
	if shineTween then shineTween:Cancel() end
	if bounceTween then bounceTween:Cancel() end
	if transferTween then transferTween:Cancel() end
	if orbitTween then orbitTween:Cancel() end
end)


-- Separate backing layers provide physical depth; none intercepts input.
local claimHit=Instance.new("TextButton")
claimHit.Name="ClaimHitTarget";claimHit.Text="";claimHit.BackgroundTransparency=1
claimHit.AnchorPoint=cta.AnchorPoint;claimHit.Position=cta.Position+UDim2.fromOffset(0,7)
claimHit.Size=cta.Size+UDim2.fromOffset(0,7);claimHit.ZIndex=20
claimHit.Active=true;claimHit.Selectable=true;claimHit.AutoButtonColor=false;claimHit.Parent=card
cta.Active=false;cta.Selectable=false

local depthTweens={}
local depthBases={}
local function CreateButtonDepth(button,edgeColor,premium)
	button.ZIndex=4
	local base=button.Position;depthBases[button]=base
	local radius=20
	local layers={}
	local connections={}
	local scaleConnection
	local function syncLayers()
		local faceScale=button:FindFirstChildOfClass("UIScale")
		local scale=faceScale and faceScale.Scale or 1
		for _,layer in ipairs(layers) do
			layer.frame.AnchorPoint=button.AnchorPoint
			layer.frame.Position=button.Position+UDim2.fromOffset((button.AnchorPoint.X-.5)*layer.extra*scale,layer.dy*scale)
			layer.frame.Size=button.Size+UDim2.fromOffset(layer.extra,0)
			layer.scale.Scale=scale
			layer.frame.Visible=button.Visible
		end
	end
	local function bindScale()
		if scaleConnection then scaleConnection:Disconnect();scaleConnection=nil end
		local faceScale=button:FindFirstChildOfClass("UIScale")
		if faceScale then scaleConnection=faceScale:GetPropertyChangedSignal("Scale"):Connect(syncLayers) end
		syncLayers()
	end
	local function backing(name,dy,extra,color,transparency,z)
		local p=Instance.new("Frame");p.Name=name;p.AnchorPoint=button.AnchorPoint
		local xShift=(button.AnchorPoint.X-.5)*extra
		p.Position=base+UDim2.fromOffset(xShift,dy)
		p.Size=button.Size+UDim2.fromOffset(extra,0)
		p.BackgroundColor3=color;p.BackgroundTransparency=transparency;p.BorderSizePixel=0
		p.ZIndex=z;p.Active=false;p.Parent=button.Parent
		local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,radius);corner.Parent=p
		local layerScale=Instance.new("UIScale");layerScale.Parent=p
		table.insert(layers,{frame=p,scale=layerScale,dy=dy,extra=extra})
		return p
	end
	backing(button.Name.."SoftShadow",16,6,Color3.fromRGB(0,0,0),.48,1)
	backing(button.Name.."ContactShadow",13,3,Color3.fromRGB(0,0,0),.12,2)
	backing(button.Name.."Extrusion",10,0,edgeColor,0,3)
	-- Follow the exact face transform during presses, hover and release.
	-- Input targets stay stable; every visible button layer moves together.
	for _,property in ipairs({"Position","Size","AnchorPoint","Visible"}) do
		table.insert(connections,button:GetPropertyChangedSignal(property):Connect(syncLayers))
	end
	table.insert(connections,button.ChildAdded:Connect(function(child) if child:IsA("UIScale") then bindScale() end end))
	table.insert(connections,button.ChildRemoved:Connect(function(child) if child:IsA("UIScale") then bindScale() end end))
	bindScale()
	script.Destroying:Connect(function()
		for _,connection in ipairs(connections) do connection:Disconnect() end
		if scaleConnection then scaleConnection:Disconnect() end
	end)
	local corner=button:FindFirstChildOfClass("UICorner");if corner then corner.CornerRadius=UDim.new(0,radius) end
	local function press(down)
		if depthTweens[button] then depthTweens[button]:Cancel() end
		local dy=down and 4 or 0
		if player:GetAttribute("ReduceMotion")==true then dy=0 end
		depthTweens[button]=TweenService:Create(button,TweenInfo.new(.10,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=base+UDim2.fromOffset(0,dy)})
		depthTweens[button]:Play()
	end
	local inputTarget=button==cta and claimHit or button
	inputTarget.MouseButton1Down:Connect(function() press(true) end)
	inputTarget.MouseButton1Up:Connect(function() press(false) end)
	inputTarget.MouseLeave:Connect(function() press(false) end)
	inputTarget.Activated:Connect(function() press(true);task.delay(.12,function() if button.Parent then press(false) end end) end)
	if not premium then return end
	local top=Instance.new("Frame");top.Name="FaceHighlight";top.AnchorPoint=Vector2.new(.5,0)
	top.Position=UDim2.new(.5,0,0,5);top.Size=UDim2.new(1,-36,0,5)
	GuiStyle.Corner(top,1)
	top.BackgroundColor3=Color3.fromRGB(255,252,213);top.BackgroundTransparency=premium and .12 or .65
	top.BorderSizePixel=0;top.Active=false;top.ZIndex=5;top.Parent=button
end
CreateButtonDepth(cta,Color3.fromRGB(17,111,43),false)
CreateButtonDepth(doubleButton,Color3.fromRGB(119,66,0),true)
local normalGradient=cta:FindFirstChildOfClass("UIGradient")
cta.BackgroundColor3=Color3.new(1,1,1)
if normalGradient then normalGradient.Color=ColorSequence.new(Color3.fromRGB(61,199,89),Color3.fromRGB(39,170,69)) end
cta.TextColor3=Color3.fromRGB(255,255,239)
cta.TextStrokeTransparency=1
for _,s in ipairs(cta:GetChildren()) do if s:IsA("UIStroke") then s:Destroy() end end
local claimBorder=Instance.new("UIStroke");claimBorder.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;claimBorder.Color=Color3.fromRGB(17,96,38);claimBorder.Thickness=2.5;claimBorder.Parent=cta
local claimTextRim=Instance.new("UIStroke");claimTextRim.ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual;claimTextRim.Color=Color3.fromRGB(9,39,21);claimTextRim.Thickness=2;claimTextRim.Parent=cta
ctaCap.MaxTextSize=32
cta.TextTransparency=1
claimTextRim:Destroy()
local claimPadding=cta:FindFirstChildOfClass("UIPadding")
if claimPadding then claimPadding:Destroy() end
local claimFaceText=makeLabel({Name="ClaimTitle",Parent=cta,Text="CLAIM",Color=Color3.fromRGB(255,255,235),Position=UDim2.fromOffset(12,8),Size=UDim2.new(1,-24,1,-16),Max=35,Stroke=2.3,ZIndex=6})
normalGradient.Rotation=90
normalGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(92,225,108)),ColorSequenceKeypoint.new(.48,Color3.fromRGB(48,202,80)),ColorSequenceKeypoint.new(1,Color3.fromRGB(27,160,60))})

local priceRim=Instance.new("UIStroke");priceRim.Color=Color3.fromRGB(182,111,11);priceRim.Thickness=1.5;priceRim.Parent=badge
local numberRim=Instance.new("UIStroke");numberRim.Color=Color3.fromRGB(8,39,20);numberRim.Thickness=1.5;numberRim.Parent=doubleAmount

local function polishAmount(container,label,premium)
	local row=makeFrame({Name="CenteredStardust",Parent=container,Position=UDim2.fromOffset(12,36),Size=UDim2.new(1,-24,0,44),Transparency=1,ZIndex=3})
	local layout=Instance.new("UIListLayout")
	layout.FillDirection=Enum.FillDirection.Horizontal
	layout.HorizontalAlignment=Enum.HorizontalAlignment.Center
	layout.VerticalAlignment=Enum.VerticalAlignment.Center
	layout.SortOrder=Enum.SortOrder.LayoutOrder
	layout.Padding=UDim.new(0,8);layout.Parent=row
	local icon=Instance.new("ImageLabel");icon.Name="StardustIcon";icon.Parent=row
	icon.BackgroundTransparency=1;icon.BorderSizePixel=0;icon.Size=UDim2.fromOffset(38,38)
	icon.Image=UIAssets.Stardust or "";icon.ScaleType=Enum.ScaleType.Fit;icon.ZIndex=4
	icon.LayoutOrder=1
	label.Parent=row;label.LayoutOrder=2;label.AnchorPoint=Vector2.zero
	label.TextColor3=Color3.new(1,1,1);label.TextStrokeTransparency=1;label.ZIndex=4
	local cap=label:FindFirstChildOfClass("UITextSizeConstraint");cap.MaxTextSize=premium and 39 or 33
	local function measure()
		local measured=game:GetService("TextService"):GetTextSize(label.Text,cap.MaxTextSize,FONT,Vector2.new(1000,44))
		local width=container.Size.X.Scale*LAYOUT.Width+container.Size.X.Offset
		label.Size=UDim2.fromOffset(math.min(measured.X+5,width-70),44)
	end
	label:GetPropertyChangedSignal("Text"):Connect(measure);measure()
	local fill=Instance.new("UIGradient");fill.Rotation=90
	fill.Color=ColorSequence.new(premium and Color3.fromRGB(219,255,192) or Color3.fromRGB(188,255,213),premium and Color3.fromRGB(63,241,111) or Color3.fromRGB(103,225,162));fill.Parent=label
	local rim=label:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	rim.Color=Color3.fromRGB(5,30,19);rim.Thickness=1.2;rim.Parent=label
end
polishAmount(normalCard,normalAmount,false)
polishAmount(premiumCard,doubleAmount,true)

local warmBacking=makeFrame({Name="PremiumOfferBacking",Parent=card,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-LAYOUT.SideInset+6,0,418),Size=UDim2.new(.55,-LAYOUT.SideInset+4,0,207),Color=Color3.fromRGB(88,62,21),Transparency=.79,ZIndex=1})
GuiStyle.Corner(warmBacking,.08)
local panelShadow=makeFrame({Name="PopupShadow",Parent=panel,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,.5,11),Size=UDim2.new(1,8,1,0),Color=Color3.new(0,0,0),Transparency=.6,ZIndex=1})
GuiStyle.Corner(panelShadow,0).CornerRadius=UDim.new(0,CARD_CORNER+4)
card.ZIndex=2
-- Keep the backing in step with the existing open/close animation.
local shadowScale=Instance.new("UIScale");shadowScale.Scale=cardScale.Scale;shadowScale.Parent=panelShadow
local scaleConnection=cardScale:GetPropertyChangedSignal("Scale"):Connect(function() shadowScale.Scale=cardScale.Scale end)
local fadeConnection=card:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
	panelShadow.BackgroundTransparency=.6+.4*card.BackgroundTransparency
end)
panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if not panel.Visible then
		for button,t in pairs(depthTweens) do t:Cancel();button.Position=depthBases[button] end
	end
end)
script.Destroying:Connect(function()
	scaleConnection:Disconnect();fadeConnection:Disconnect()
	for _,t in pairs(depthTweens) do t:Cancel() end
end)


-- Art direction stays scoped: the existing hierarchy and purchase controller remain intact.
do
	local function rim(object,color,width)
		local line=object:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		line.Color=color;line.Thickness=width;line.Parent=object
		if object:IsA("TextButton") or object:IsA("Frame") then line.ApplyStrokeMode=Enum.ApplyStrokeMode.Border end
		return line
	end
	local ink=Color3.fromRGB(7,12,33)
	local function lettering(label,size,width,color)
		local limit=label:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then limit.MaxTextSize=size end
		local line=rim(label,color or ink,width);line.ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual
	end
	local corner=card:FindFirstChildOfClass("UICorner");corner.CornerRadius=UDim.new(0,CARD_CORNER)
	rim(card,Color3.fromRGB(74,144,255),4.5)
	header.BackgroundColor3=Color3.fromRGB(13,21,53)
	header.BackgroundTransparency=0
	headerFoot.BackgroundColor3=header.BackgroundColor3
	headerFoot.BackgroundTransparency=header.BackgroundTransparency
	lettering(title,40,2.6)
	title.Rotation=-1
	panelGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(15,28,67)),ColorSequenceKeypoint.new(.48,Color3.fromRGB(25,42,82)),ColorSequenceKeypoint.new(1,Color3.fromRGB(11,20,48))})
	lettering(rewardText,59,3,Color3.fromRGB(5,48,20))
	rewardText.TextColor3=Color3.fromRGB(80,255,109)
	rewardHolder.Size=UDim2.new(1,-40,0,54)
	rewardHolder.Position=UDim2.new(.5,0,0,241)
	medallion.BackgroundColor3=Color3.fromRGB(255,229,135)
	medallionGradient.Color=ColorSequence.new(Color3.fromRGB(255,247,181),Color3.fromRGB(238,160,42))
	rim(medallion,Color3.fromRGB(91,55,14),4)
	innerRing.BackgroundTransparency=0
	innerRing.BackgroundColor3=Color3.fromRGB(23,46,98)
	innerRingStroke.Color=Color3.fromRGB(255,236,163);innerRingStroke.Transparency=.12;innerRingStroke.Thickness=3
	star.Size=UDim2.fromScale(.82,.82)
	orbitLine.Color=Color3.fromRGB(255,213,87);orbitLine.Transparency=.45;orbitLine.Thickness=2
	for i,spec in ipairs({{-.18,.26,16},{1.16,.67,12},{1.04,.02,18}}) do
		makeLabel({Name="BadgeSparkle"..i,Parent=medallion,Text="✦",Color=COLOR.Gold,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(spec[1],spec[2]),Size=UDim2.fromOffset(spec[3],spec[3]),Max=spec[3],Stroke=1.3,ZIndex=4})
	end
	for _,box in ipairs({normalCard,premiumCard}) do
		local premium=box==premiumCard
		box.BackgroundColor3=Color3.new(1,1,1)
		box:FindFirstChildOfClass("UICorner").CornerRadius=UDim.new(0,18)
		rim(box,premium and Color3.fromRGB(255,205,60) or Color3.fromRGB(72,123,184),premium and 3.5 or 2.5)
		local gradient=Instance.new("UIGradient");gradient.Rotation=90
		gradient.Color=ColorSequence.new(premium and Color3.fromRGB(80,48,27) or Color3.fromRGB(30,53,87),premium and Color3.fromRGB(37,27,45) or Color3.fromRGB(12,27,50));gradient.Parent=box
		local shelf=makeFrame({Name="RewardBoxBase",Parent=box,AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-5),Size=UDim2.new(1,-18,0,7),Color=premium and Color3.fromRGB(124,77,17) or Color3.fromRGB(8,20,40),ZIndex=1})
		GuiStyle.Corner(shelf,1)
		for _,label in ipairs(box:GetChildren()) do
			if label:IsA("TextLabel") and (label.Text=="NORMAL" or label.Text=="2X REWARD") then
				lettering(label,20,1.8)
				if not premium then label.TextColor3=Color3.fromRGB(195,221,255) end
			end
		end
	end
	warmBacking.BackgroundColor3=Color3.fromRGB(205,130,25);warmBacking.BackgroundTransparency=.87
	local sticker=makeFrame({Name="DoubleBurstSticker",Parent=premiumCard,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(1,-23,0,5),Size=UDim2.fromOffset(40,40),Color=Color3.fromRGB(255,200,39),ZIndex=7})
	sticker.Rotation=11;GuiStyle.Corner(sticker,.25);rim(sticker,ink,3)
	makeLabel({Parent=sticker,Text="2X!",Color=Color3.fromRGB(255,255,230),Position=UDim2.fromOffset(2,1),Size=UDim2.new(1,-4,1,-2),Max=21,Stroke=2,ZIndex=8})
	-- Fatter, readable toy faces. Depth layers still track every press and scale.
	claimBorder.Thickness=4;claimBorder.Color=Color3.fromRGB(6,74,28)
	lettering(claimFaceText,40,3)
	border.Thickness=4.5;border.Color=Color3.fromRGB(104,55,6)
	textOutline.Thickness=3.2;cap.MaxTextSize=36
	big.Position=UDim2.fromOffset(10,10);big.Size=UDim2.new(1,-103,0,39)
	gift.Position=UDim2.fromOffset(10,52);giftCap.MaxTextSize=20
	priceRim.Thickness=2.5;priceCap.MaxTextSize=23
	badge.BackgroundColor3=Color3.fromRGB(255,237,145)
	normalGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(155,255,121)),ColorSequenceKeypoint.new(.34,Color3.fromRGB(77,228,81)),ColorSequenceKeypoint.new(1,Color3.fromRGB(17,174,59))})
	gold.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,249,169)),ColorSequenceKeypoint.new(.26,Color3.fromRGB(255,210,56)),ColorSequenceKeypoint.new(.52,Color3.fromRGB(255,235,100)),ColorSequenceKeypoint.new(.76,Color3.fromRGB(255,184,20)),ColorSequenceKeypoint.new(1,Color3.fromRGB(246,141,6))})
	transfer.Text="›";transfer.Size=UDim2.fromOffset(14,28)
end
-- Refine the reward boxes without changing their centered value groups.
do
	local sticker=premiumCard:FindFirstChild("DoubleBurstSticker")
	if sticker then sticker:Destroy() end
	for _,box in ipairs({normalCard,premiumCard}) do
		local premium=box==premiumCard
		local shelf=box:FindFirstChild("RewardBoxBase");if shelf then shelf:Destroy() end
		local gradient=box:FindFirstChildOfClass("UIGradient")
		gradient.Color=ColorSequence.new(premium and Color3.fromRGB(45,41,66) or Color3.fromRGB(25,44,75),premium and Color3.fromRGB(28,29,49) or Color3.fromRGB(17,31,57))
		local rim=box:FindFirstChildOfClass("UIStroke")
		rim.Thickness=premium and 3 or 2.5
		box:FindFirstChildOfClass("UICorner").CornerRadius=UDim.new(0,17)
		local row=box:FindFirstChild("CenteredStardust")
		row.Position=UDim2.fromOffset(12,35);row.Size=UDim2.new(1,-24,0,45)
		row:FindFirstChildOfClass("UIListLayout").Padding=UDim.new(0,6)
		for _,label in ipairs(box:GetChildren()) do
			if label:IsA("TextLabel") then
				label.Position=UDim2.fromOffset(12,10)
				local line=label:FindFirstChildOfClass("UIStroke");if line then line.Thickness=1.3 end
			end
		end
	end
	transfer.Visible=false
	warmBacking.Visible=false
	title.Rotation=0
	title:FindFirstChildOfClass("UIStroke").Thickness=2
	claimFaceText:FindFirstChildOfClass("UIStroke").Thickness=2.6
	textOutline.Thickness=2.7
	for _,button in ipairs({doubleButton}) do
		local highlight=button:FindFirstChild("FaceHighlight")
		if highlight then highlight.Size=UDim2.new(1,-40,0,3);highlight.BackgroundTransparency=.25 end
	end
end
do
	for _,value in ipairs({normalAmount,doubleAmount}) do
		local outline=value:FindFirstChildOfClass("UIStroke")
		if outline then outline.Thickness=1.8 end
	end
	rewardText.TextColor3=Color3.fromRGB(128,255,139)
	local rewardFill=Instance.new("UIGradient");rewardFill.Rotation=90
	rewardFill.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(151,230,155));rewardFill.Parent=rewardText
end
do
	local away=card:FindFirstChild("Away")
	away.Size=UDim2.new(1,-48,0,17);away.Position=UDim2.fromOffset(24,LAYOUT.AwayY)
	away:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize=14
	away.TextColor3=Color3.fromRGB(185,207,246)
	-- Keep the orbit and decorative sparkles below the supporting caption.
	orbit.Size=UDim2.fromScale(1.09,1.09)
	for _,decoration in ipairs(medallion:GetChildren()) do
		if decoration.Name:match("^BadgeSparkle") then decoration:Destroy() end
	end
	local currency=card:FindFirstChild("Currency")
	currency.AnchorPoint=Vector2.new(.5,0);currency.Position=UDim2.new(.5,0,0,299)
	currency.Size=UDim2.fromOffset(126,23);currency.BackgroundTransparency=0
	currency.BackgroundColor3=Color3.fromRGB(40,47,77)
	GuiStyle.Corner(currency,.45)
	currency.TextColor3=Color3.fromRGB(255,225,106)
	currency:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize=15
	currency:FindFirstChildOfClass("UIStroke").Thickness=1.2
	detail.TextColor3=Color3.fromRGB(185,205,236)
	detailCap.MaxTextSize=13
	for _,label in ipairs({normalAmount,doubleAmount}) do
		label:FindFirstChildOfClass("UIStroke").Color=Color3.fromRGB(8,33,31)
	end
	-- Shared navy outlines and cream lettering tie the navigation and reward buttons together.
	claimFaceText.TextColor3=Color3.fromRGB(255,255,235)
	claimBorder.Thickness=3.5;border.Thickness=3.5
end
local mainFade=createFader(card)
local setDrawer
do
	-- Permanent offline-cap game pass. ID 0 keeps purchasing unavailable.
	local timePanel=makeFrame({Name="OfflineTimeOffer",Parent=panel,Position=UDim2.new(1,320,0,142),Size=UDim2.fromOffset(312,380),AnchorPoint=Vector2.new(.5,.5),Color=Color3.fromRGB(12,20,43),ZIndex=25})
	timePanel.Visible=false;timePanel.ClipsDescendants=true
	GuiStyle.Corner(timePanel,.055);GuiStyle.Stroke(timePanel,Color3.fromRGB(93,179,255),2.5)
	local timeGradient=Instance.new("UIGradient");timeGradient.Rotation=90
	timeGradient.Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(138,151,198));timeGradient.Parent=timePanel
	local timeClose=Instance.new("TextButton");timeClose.Name="DismissTimeOffer";timeClose.Text=""
	timeClose.Position=UDim2.new(1,-35,0,9);timeClose.Size=UDim2.fromOffset(26,26)
	timeClose.BackgroundColor3=Color3.fromRGB(32,48,76);timeClose.TextColor3=COLOR.Text;timeClose.Font=FONT;timeClose.TextSize=24;timeClose.ZIndex=27;timeClose.Parent=timePanel
	GuiStyle.Corner(timeClose,.3)
	timeClose.AutoButtonColor=false
	timeClose.Size=UDim2.fromOffset(30,30);timeClose.Position=UDim2.new(1,-42,0,12)
	for _,rotation in ipairs({45,-45}) do
		local bar=makeFrame({Parent=timeClose,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(14,3),Color=COLOR.Text,ZIndex=28})
		bar.Rotation=rotation;GuiStyle.Corner(bar,1)
	end
	-- ===================== OFFLINE CLOCK =====================
	-- ONE clock, and it is the artwork in UIAssets.OfflineClock.
	--
	-- There is deliberately nothing drawn here any more. The clock that kept
	-- coming back was not an old asset id -- no clock id has ever been written
	-- into this script -- it was a Frame this file built: a yellow disc, two black
	-- hands, a centre pin and a "2X" sticker. The load check underneath it set the
	-- artwork's Visible to false the moment the picture was not ready yet, and
	-- Roblox does not fetch an image for a label it is not drawing, so IsLoaded
	-- could never become true and the drawn clock stayed for the whole session.
	--
	-- The disc, the hands, the sticker and the verdict are all gone. The label is
	-- on screen from the first frame, which is also the only way the picture gets
	-- fetched, and no code path in this file can replace it with anything.
	local clockArt=Instance.new("ImageLabel")
	clockArt.Name="OfflineClock"
	clockArt.BackgroundTransparency=1;clockArt.BorderSizePixel=0;clockArt.Active=false
	clockArt.AnchorPoint=Vector2.new(.5,0)
	clockArt.Position=UDim2.new(.5,0,0,12)
	clockArt.Size=UDim2.fromOffset(104,104)
	clockArt.Image=UIAssets.OfflineClock or ""
	clockArt.ScaleType=Enum.ScaleType.Fit
	clockArt.ImageColor3=Color3.new(1,1,1)
	clockArt.ZIndex=27
	clockArt.Parent=timePanel

	print("[WelcomeBack] build 2026-09-25 (one clock, artwork only)  id: "..tostring(UIAssets.OfflineClock))

	-- UIAssets.Groups.WelcomeBack carries this id. EnsureGroup is single-flight,
	-- so this and the startup warm share one request rather than making two.
	if UIAssets.EnsureGroup then
		UIAssets.EnsureGroup("WelcomeBack")
	elseif UIAssets.Preload then
		UIAssets.Preload("WelcomeBack")
	end

	if clockArt.Image=="" then
		-- No id in the module. The slot stays empty rather than reaching for a
		-- substitute: an out-of-date clock is worse than no clock.
		clockArt.Visible=false
		warn("[WelcomeBack] UIAssets.OfflineClock is empty - add the id to ReplicatedStorage > UIAssets.")
	end
	local timeTitle=makeLabel({Name="TimeOfferTitle",Parent=timePanel,Text="2X YOUR\nOFFLINE TIME!",Color=COLOR.Gold,Position=UDim2.fromOffset(14,124),Size=UDim2.new(1,-28,0,64),Max=31,ZIndex=26})
	goldenText(timeTitle)
	makeLabel({Parent=timePanel,Text="8 HOURS  →  16 HOURS",Color=COLOR.TextDim,Position=UDim2.fromOffset(18,202),Size=UDim2.new(1,-36,0,22),Max=16,ZIndex=26})
	local timeInfo=makeLabel({Name="TimeOfferDetails",Parent=timePanel,Text="Permanent upgrade · 99 R$",Color=Color3.fromRGB(185,207,235),Position=UDim2.fromOffset(18,232),Size=UDim2.new(1,-36,0,24),Max=14,ZIndex=26})
	local timeCTA=Instance.new("TextButton");timeCTA.Name="TimeOfferButton";timeCTA.Text="UNLOCK · 99 R$"
	timeCTA.Position=UDim2.fromOffset(18,280);timeCTA.Size=UDim2.new(1,-36,0,76)
	timeCTA.BackgroundColor3=Color3.fromRGB(44,89,144);timeCTA.Font=FONT;timeCTA.TextSize=19;timeCTA.TextColor3=Color3.fromRGB(213,233,255);timeCTA.ZIndex=26;timeCTA.Parent=timePanel
	GuiStyle.Corner(timeCTA,.2);GuiStyle.Stroke(timeCTA,Color3.fromRGB(90,154,219),2)
	timeCTA.TextScaled=true
	local capButtonTextSize=Instance.new("UITextSizeConstraint");capButtonTextSize.MaxTextSize=19;capButtonTextSize.MinTextSize=10;capButtonTextSize.Parent=timeCTA
	local capConfig=require(ReplicatedStorage:WaitForChild("OfflineEarningsConfig"))
	local capPassId=tonumber(capConfig.OfflineCapGamePassId) or 0
	local capPrice=99
	local capPrompting=false
	local capPriceReady=false
	-- Same premium face, badge, depth and glint as the main offer.
	timeCTA.TextTransparency=1;timeCTA.TextStrokeTransparency=1;timeCTA.AutoButtonColor=false
	timeCTA.BackgroundColor3=Color3.new(1,1,1);timeCTA.ClipsDescendants=true
	local oldTimeBorder=timeCTA:FindFirstChildOfClass("UIStroke");if oldTimeBorder then oldTimeBorder:Destroy() end
	local timeGold=gold:Clone();timeGold.Parent=timeCTA
	local timeBorder=border:Clone();timeBorder.Parent=timeCTA
	CreateButtonDepth(timeCTA,Color3.fromRGB(119,66,0),true)
	local timeBig=big:Clone();timeBig.Text="DOUBLE TIME";timeBig.Position=UDim2.fromOffset(8,10);timeBig.Size=UDim2.new(1,-96,0,29);timeBig:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize=26;timeBig.Parent=timeCTA
	local timeGift=gift:Clone();timeGift.Text="8h → 16h FOREVER";timeGift.Position=UDim2.fromOffset(8,43);timeGift.Size=UDim2.new(1,-96,0,23);timeGift:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize=15;timeGift.Parent=timeCTA
	local timeBadge=badge:Clone();timeBadge.Size=UDim2.fromOffset(70,38);timeBadge.Parent=timeCTA
	local timePrice=timeBadge:FindFirstChild("RobuxPrice")
	local timeShine=shine:Clone();timeShine.Parent=timeCTA
	local timeMask=timeShine:FindFirstChildOfClass("UIGradient");timeMask.Offset=Vector2.new(-1.4,0)
	local function syncTimeFace()
		local value=timeCTA.Text
		timePrice.Text=tostring(capPrice).." R$"
		timeBig.Text="DOUBLE TIME";timeGift.Text="8h → 16h FOREVER"
		if value:find("UNLOCKED",1,true) then timeBig.Text="UNLOCKED!";timeGift.Text="16-HOUR CAP ACTIVE"
		elseif value:find("PENDING",1,true) then timeBig.Text="WAITING..."
		elseif value:find("COMING SOON",1,true) then timeGift.Text="COMING SOON · 8h → 16h"
		elseif value:find("UNAVAILABLE",1,true) then timeGift.Text="PRICE UNAVAILABLE" end
	end
	timeCTA:GetPropertyChangedSignal("Text"):Connect(syncTimeFace)
	syncTimeFace()
	local function refreshCapOffer()
		if player:GetAttribute("OfflineCapPassOwned")==true then
			timeCTA.Text="16 HOURS UNLOCKED";timeInfo.Text="Permanent upgrade active";return
		end
		if capPassId<=0 then timeCTA.Text="99 R$ · COMING SOON";timeInfo.Text="Permanent upgrade · 8h → 16h";return end
		timeCTA.Text=capPrompting and "PURCHASE PENDING" or "UNLOCK · "..capPrice.." R$"
		timeInfo.Text="Applies to future offline earnings"
	end
	refreshCapOffer()
	if capPassId>0 then
		task.spawn(function()
			local ok,info=pcall(MarketplaceService.GetProductInfo,MarketplaceService,capPassId,Enum.InfoType.GamePass)
			if ok and info and tonumber(info.PriceInRobux) then capPrice=info.PriceInRobux;capPriceReady=true end
			refreshCapOffer()
			if not capPriceReady then timeCTA.Text="PRICE UNAVAILABLE" end
		end)
	end
	timeCTA.Activated:Connect(function()
		if player:GetAttribute("OfflineCapPassOwned")==true then timeInfo.Text="Your 16-hour cap is already active";return end
		if capPassId<=0 then timeInfo.Text="Coming soon — purchases aren't enabled";return end
		if capPrompting then return end
		if not capPriceReady then timeInfo.Text="Price unavailable. Please rejoin to retry.";return end
		capPrompting=true;refreshCapOffer()
		local ok=pcall(MarketplaceService.PromptGamePassPurchase,MarketplaceService,player,capPassId)
		if not ok then capPrompting=false;refreshCapOffer();timeInfo.Text="Purchase prompt unavailable. Try again." end
	end)
	local capAttributeConnection=player:GetAttributeChangedSignal("OfflineCapPassOwned"):Connect(refreshCapOffer)
	local capFinishedConnection=MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who,id,purchased)
		if who~=player or id~=capPassId then return end
		capPrompting=false;refreshCapOffer()
		if purchased and player:GetAttribute("OfflineCapPassOwned")~=true then timeInfo.Text="Verifying your permanent upgrade..." end
	end)
	script.Destroying:Connect(function() capAttributeConnection:Disconnect();capFinishedConnection:Disconnect() end)
	local drawerFade=createFader(timePanel)
	local stopSideEffects=function() end
	local drawerTween
	local drawerOpen=false
	local drawerGeneration=0
	local function drawerPosition(opened)
		if drawerDesktop then return UDim2.fromOffset(LAYOUT.Width+(opened and 180 or 500),LAYOUT.Height/2) end
		return UDim2.fromOffset(LAYOUT.Width+(opened and -180 or 200),LAYOUT.Height/2)
	end
	setDrawer=function(opened)
		if not opened and not timePanel.Visible then return end
		drawerGeneration+=1;local generation=drawerGeneration
		drawerOpen=opened
		if drawerTween then drawerTween:Cancel() end
		local reduced=player:GetAttribute("ReduceMotion")==true
		local duration=reduced and .12 or .28
		if opened then
			drawerFade.Restore()
			timePanel.Position=drawerPosition(true)+UDim2.fromOffset(reduced and 0 or 36,0)
			timePanel.Visible=true
			drawerTween=TweenService:Create(timePanel,TweenInfo.new(duration,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=drawerPosition(true)})
		else
			stopSideEffects()
			drawerFade.Fade(duration)
			drawerTween=TweenService:Create(timePanel,TweenInfo.new(duration,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Position=timePanel.Position+UDim2.fromOffset(reduced and 0 or 32,0)})
			task.delay(duration+.02,function()
				if generation==drawerGeneration then timePanel.Visible=false;drawerFade.Restore() end
			end)
		end
		drawerTween:Play()
	end
	timeClose.Activated:Connect(function()
		if drawerDismissed then return end
		drawerDismissed=true                 -- also stops the delayed auto-open
		timeClose.Active=false

		local reduced=player:GetAttribute("ReduceMotion")==true
		local slide=reduced and .12 or .3
		local settle=reduced and .12 or .34

		-- 1. the offer slides off the right edge, fading as it goes
		drawerGeneration+=1
		local generation=drawerGeneration
		if drawerTween then drawerTween:Cancel() end
		stopSideEffects()
		drawerFade.Fade(slide)
		drawerTween=TweenService:Create(timePanel,
			TweenInfo.new(slide,Enum.EasingStyle.Quint,Enum.EasingDirection.In),
			{Position=timePanel.Position+UDim2.fromOffset(420,0)})
		drawerTween:Play()

		-- 2. part way through, the wrapper gives back the space it was holding for
		-- the offer and the main panel glides into the centre. The scale is tweened
		-- with it, so the panel does not pop when refreshScale lands on the same
		-- numbers afterwards.
		task.delay(slide*.72,function()
			if generation~=drawerGeneration then return end
			local info=TweenInfo.new(settle,Enum.EasingStyle.Quint,Enum.EasingDirection.Out)
			TweenService:Create(wrapper,info,{Size=UDim2.fromOffset(LAYOUT.Width,LAYOUT.Height)}):Play()
			local vp=fitArea()
			if vp.X>1 and vp.Y>1 then
				TweenService:Create(responsive,info,{Scale=popupScaleFor(LAYOUT.Width)}):Play()
			end
		end)

		task.delay(slide+.04,function()
			if generation~=drawerGeneration then return end
			timePanel.Visible=false
			drawerFade.Restore()
			drawerOpen=false
		end)
	end)
	refreshTimeOfferLayout=function()
		if drawerTween then drawerTween:Cancel() end
		drawerGeneration+=1
		if not drawerOpen then timePanel.Visible=false end
		drawerFade.Restore()
		timePanel.Position=drawerPosition(drawerOpen)
	end
	refreshTimeOfferLayout()
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		drawerGeneration+=1;local generation=drawerGeneration
		if not panel.Visible then
			if drawerTween then drawerTween:Cancel() end
			drawerOpen=false;timePanel.Visible=false
			drawerDismissed=false
			timeClose.Active=true
			refreshScale()
			return
		end
		timePanel.Position=drawerPosition(false)
		task.delay(.65,function()
			if generation==drawerGeneration and panel.Visible and not drawerDismissed and panel:GetAttribute("Closing")~=true then setDrawer(true) end
		end)
	end)
	script.Destroying:Connect(function() drawerGeneration+=1;if drawerTween then drawerTween:Cancel() end end)


	local attentionScale=Instance.new("UIScale");attentionScale.Parent=timePanel
	local shakeTween
	local breatheTween
	local timeGlintTween
	local attentionRunning=false
	local function stopAttention()
		attentionRunning=false
		if shakeTween then shakeTween:Cancel();shakeTween=nil end
		if breatheTween then breatheTween:Cancel();breatheTween=nil end
		if timeGlintTween then timeGlintTween:Cancel();timeGlintTween=nil end
		attentionScale.Scale=1;timePanel.Rotation=0
		timeMask.Offset=Vector2.new(-1.4,0)
	end
	stopSideEffects=stopAttention
	local function refreshAttention()
		local enabled=alive and drawerOpen and panel.Visible and timePanel.Visible and panel:GetAttribute("Closing")~=true and player:GetAttribute("ReduceMotion")~=true
		if not enabled then stopAttention();return end
		if attentionRunning then return end
		attentionRunning=true
		timePanel.Rotation=-.45
		shakeTween=TweenService:Create(timePanel,TweenInfo.new(.42,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Rotation=.45})
		breatheTween=TweenService:Create(attentionScale,TweenInfo.new(1.8,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Scale=1.008})
		shakeTween:Play();breatheTween:Play()
	end
	local attentionConnections={
		timePanel:GetPropertyChangedSignal("Visible"):Connect(refreshAttention),
		panel:GetPropertyChangedSignal("Visible"):Connect(refreshAttention),
		panel:GetAttributeChangedSignal("Closing"):Connect(refreshAttention),
		player:GetAttributeChangedSignal("ReduceMotion"):Connect(refreshAttention),
	}
	refreshAttention()
	task.spawn(function()
		while alive do
			task.wait(4.2)
			if not alive then break end
			if attentionRunning then
				if timeGlintTween then timeGlintTween:Cancel() end
				timeMask.Offset=Vector2.new(-1.4,0)
				timeGlintTween=TweenService:Create(timeMask,TweenInfo.new(.8,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Offset=Vector2.new(1.4,0)})
				timeGlintTween:Play()
			end
		end
	end)
	script.Destroying:Connect(function()
		for _,connection in ipairs(attentionConnections) do connection:Disconnect() end
		stopAttention()
	end)
	-- Slow hue travel distinguishes the permanent upgrade from the gold reward offer.
	-- Only updates while visible; no per-frame render connection is retained.
	do
		timePanel.BackgroundColor3=Color3.new(1,1,1)
		local titleGradient=timeTitle:FindFirstChildOfClass("UIGradient")
		if titleGradient then titleGradient:Destroy() end
		timeTitle.TextColor3=Color3.fromRGB(255,252,244)
		timeBig.TextColor3=Color3.fromRGB(255,255,244)
		timeGift.TextColor3=Color3.fromRGB(27,25,60)
		timeBadge.BackgroundColor3=Color3.fromRGB(255,249,226)
		timePrice.TextColor3=Color3.fromRGB(46,31,70)
		timeBorder.Color=Color3.fromRGB(91,55,128)
		local rim=timePanel:FindFirstChildOfClass("UIStroke")
		local function rainbow(phase,saturation,value)
			local points={}
			for i=0,6 do points[#points+1]=ColorSequenceKeypoint.new(i/6,Color3.fromHSV((phase+i/18)%1,saturation,value)) end
			return ColorSequence.new(points)
		end
		local function paint(phase)
			timeGradient.Rotation=35;timeGradient.Color=rainbow(phase,.43,.24)
			timeGold.Rotation=25;timeGold.Color=rainbow(phase,.38,1)
			if rim then rim.Color=Color3.fromHSV((phase+.15)%1,.48,1) end
		end
		paint(.55)
		task.spawn(function()
			while alive do
				if drawerOpen and timePanel.Visible and panel.Visible and panel:GetAttribute("Closing")~=true and player:GetAttribute("ReduceMotion")~=true then
					paint((os.clock()/16)%1)
					task.wait(.05)
				else task.wait(.25) end
			end
		end)
	end
	do
		-- Sticker headline and thick frame; rainbow remains exclusive to this
		-- offer. Nothing in here touches the clock any more: it is artwork, and it
		-- carries its own face, rim and hands.
		local ink=Color3.fromRGB(15,14,42)
		local frameRim=timePanel:FindFirstChildOfClass("UIStroke");frameRim.Thickness=4
		timePanel:FindFirstChildOfClass("UICorner").CornerRadius=UDim.new(0,25)
		timeTitle.Rotation=-2;timeTitle:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize=34
		local titleRim=Instance.new("UIStroke");titleRim.Color=ink;titleRim.Thickness=2.8;titleRim.Parent=timeTitle
		timeBig:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize=28
		timeBig:FindFirstChildOfClass("UIStroke").Thickness=3
		timeBorder.Thickness=4
		timeBadge:FindFirstChildOfClass("UIStroke").Thickness=2.5
		for i,spec in ipairs({{.21,62,16},{.77,91,13}}) do
			makeLabel({Name="ClockSparkle"..i,Parent=timePanel,Text="✦",Color=Color3.fromRGB(255,240,141),AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(spec[1],0,0,spec[2]),Size=UDim2.fromOffset(spec[3],spec[3]),Max=spec[3],Stroke=1.2,ZIndex=27})
		end
	end
	do
		timeTitle.Rotation=0
		timeTitle:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize=31
		for _,line in ipairs(timeTitle:GetChildren()) do if line:IsA("UIStroke") then line.Thickness=2 end end
		timeBig:FindFirstChildOfClass("UIStroke").Thickness=2.5
		timeBig:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize=25
		local highlight=timeCTA:FindFirstChild("FaceHighlight")
		if highlight then highlight.Size=UDim2.new(1,-40,0,3);highlight.BackgroundTransparency=.25 end
	end
end -- side-offer UI scope

local ctaScale = Instance.new("UIScale")
ctaScale.Parent = cta

if GuiManager then
	GuiManager:Register("WelcomeBack", panel, {
		BlurSize = 10,
		OpenScale = 1,
		OpenOvershootScale = 1,
		CloseBounceScale = 1,
		CloseScale = 1,
		CloseBounceTween = TweenInfo.new(0),
		CloseShrinkTween = TweenInfo.new(0),
	})
end

-- ===================== CONTROLLER =====================
local isOpen = false
local sequenceToken = 0
local sequenceTweens = {}

local function tween(instance, info, goal)
	local t = TweenService:Create(instance, info, goal)
	table.insert(sequenceTweens, t)
	t:Play()
	return t
end

local function cancelSequence()
	for _, t in ipairs(sequenceTweens) do
		t:Cancel()
	end
	table.clear(sequenceTweens)
end

-- Repeating tweens: created once, played and cancelled, never accumulated.
local idleBreathe = TweenService:Create(starScale,
	TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Scale = 1.025 })
local idleSway = TweenService:Create(star,
	TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Rotation = 1.5 })

local idleToken = 0

local function playShine()
	shineGrad.Offset = Vector2.new(-1, 0)
	TweenService:Create(shineGrad, MOTION.Shine, { Offset = Vector2.new(1, 0) }):Play()
end

local function startIdle()
	idleToken += 1
	local token = idleToken
	starScale.Scale = 1
	star.Rotation = -1.5
	idleBreathe:Play()
	idleSway:Play()

	task.spawn(function()
		while idleToken == token and isOpen do
			task.wait(4)
			if idleToken ~= token or not isOpen then return end
			playShine()
		end
	end)
end

local function stopIdle()
	idleToken += 1
	idleBreathe:Cancel()
	idleSway:Cancel()
end

local function formatDuration(seconds)
	seconds = math.max(0, math.floor(seconds))
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if days > 0 then return string.format("%dd %dh", days, hours) end
	if hours > 0 then return string.format("%dh %dm", hours, minutes) end
	return math.max(minutes, 1) .. "m"
end

local function formatCap(hours)
	if hours >= 24 then return math.floor(hours / 24) .. "d" end
	return math.floor(hours) .. "h"
end

local function burstSparkles(token)
	for index, sparkle in ipairs(sparkles) do
		if sequenceToken ~= token then return end
		local angle = (index / #sparkles) * math.pi * 2
		sparkle.Position = UDim2.new(0.5, 0, 0, MEDALLION_CENTRE_Y)
		sparkle.Size = UDim2.fromOffset(18, 18)
		sparkle.TextTransparency = 0.15
		tween(sparkle, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(angle) * 92, 0, MEDALLION_CENTRE_Y + math.sin(angle) * 92),
			Size = UDim2.fromOffset(9, 9),
			TextTransparency = 1,
		})
	end
end

local function countUp(amount, token)
	local start = os.clock()
	task.spawn(function()
		while sequenceToken == token and isOpen do
			local t = (os.clock() - start) / MOTION.Count
			if t >= 1 then break end
			rewardText.Text = "+★" .. Format.Abbreviate(amount * (1 - (1 - t) ^ 4))
			task.wait()
		end
		if sequenceToken ~= token or not isOpen then return end

		rewardText.Text = "+★" .. Format.Abbreviate(amount)
		tween(rewardScale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.07 })
		task.wait(0.1)
		if sequenceToken ~= token then return end
		tween(rewardScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		burstSparkles(token)
		play(chimeSound)
	end)
end

local function resetVisuals()
	rewardText.TextTransparency=0
	local outline=rewardText:FindFirstChildOfClass("UIStroke");if outline then outline.Transparency=0 end
	dim.BackgroundTransparency = 1
	card.BackgroundTransparency = 1
	cardScale.Scale = 0.9
	medallionScale.Scale = 0.78
	starScale.Scale = 1
	star.Rotation = 0
	shineGrad.Offset = Vector2.new(-1, 0)
	rewardScale.Scale = 1
	rewardText.Text = "+★0"
	barFill.Size = UDim2.fromScale(0, 1)
	strip.BackgroundTransparency = 1
	for _, sparkle in ipairs(sparkles) do
		sparkle.TextTransparency = 1
	end
end

local function hideNow()
	panel.Visible = false
	dim.Visible = false
	if GuiManager and GuiManager:GetCurrent() == "WelcomeBack" then
		GuiManager:Close("WelcomeBack")
	end
end

local function close()
	if not isOpen then return end
	if GuiManager then
		if GuiManager.ClearModal then GuiManager:ClearModal("WelcomeBack") end
		GuiManager:BeginClose("WelcomeBack")
	end
	isOpen = false
	sequenceToken += 1
	local token = sequenceToken
	stopIdle()
	cancelSequence()

	panel:SetAttribute("Closing",true)
	setDrawer(false)
	if shineTween then shineTween:Cancel() end
	if transferTween then transferTween:Cancel() end
	if orbitTween then orbitTween:Cancel() end
	local reduced=player:GetAttribute("ReduceMotion")==true
	local duration=reduced and .12 or .28
	local closing=TweenInfo.new(duration,Enum.EasingStyle.Quad,Enum.EasingDirection.InOut)
	mainFade.Fade(duration)
	tween(dim,closing,{BackgroundTransparency=1})
	tween(cardScale,closing,{Scale=reduced and 1 or .95})
	task.delay(duration+.03, function()
		if isOpen or sequenceToken ~= token then return end
		hideNow()
	end)
end

if GuiManager and GuiManager.SetBackHandler then
	GuiManager:SetBackHandler("WelcomeBack", function() end)
end


local claimFlightActive=false
local AnimateRewardToStardust
do
	local sounds
	task.spawn(function()
		local module=ReplicatedStorage:FindFirstChild("GameSounds")
		if module then local ok,value=pcall(require,module);if ok then sounds=value end end
	end)
	local function cue(slot,volume)
		if sounds and type(sounds.Play)=="function" then
			pcall(sounds.Play,slot,{volume=volume,maxLate=.08,sequence="OfflineClaim"})
		end
	end
	-- Stardust sprites use the game's star motif; no currency image assets required.
	local function makeStardust(parent,index)
		local sprite=makeFrame({Name="StardustStar"..index,Parent=parent,AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(38,38),Transparency=1,ZIndex=15+index})
		local halo=makeLabel({Name="SoftGlow",Parent=sprite,Text="★",Color=Color3.fromRGB(255,223,102),AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(48,48),Max=46,ZIndex=1})
		halo.TextTransparency=.84
		local core=makeLabel({Name="Star",Parent=sprite,Text="★",Color=Color3.new(1,1,1),Position=UDim2.new(),Size=UDim2.fromScale(1,1),Max=36,Stroke=1.8,ZIndex=2})
		core:FindFirstChildOfClass("UIStroke").Color=Color3.fromRGB(113,68,14)
		local gradient=Instance.new("UIGradient");gradient.Rotation=90
		gradient.Color=ColorSequence.new(Color3.fromRGB(255,254,210),Color3.fromRGB(255,184,41));gradient.Parent=core
		local scale=Instance.new("UIScale");scale.Parent=sprite
		sprite.Visible=false
		return sprite,scale,core,halo
	end
	local connection,layer,token,amountLabel,tokenScale
	local actualAmount=0
	local premiumFlight=false
	local hudScale,hudBase
	local finished=false
	local function dispose()
		if connection then connection:Disconnect();connection=nil end
		if layer then layer:Destroy();layer=nil end
		if hudScale and hudScale.Parent then hudScale.Scale=hudBase end
		hudScale=nil
		rewardScale.Scale=1
		claimFlightActive=false
		claimHit.Active=true
	end
	local function setAmount()
		if not amountLabel then return end
		amountLabel.Text="+ "..Format.Abbreviate(actualAmount)
		local width=game:GetService("TextService"):GetTextSize(amountLabel.Text,34,FONT,Vector2.new(900,50)).X+6
		amountLabel.Size=UDim2.fromOffset(width,50)
		token.Size=UDim2.fromOffset(width+47,52)
	end
	AnimateRewardToStardust=function(amount,premium)
		if not isOpen or panel:GetAttribute("Closing")==true then return end
		if claimFlightActive then
			if premium then actualAmount=tonumber(amount) or actualAmount;premiumFlight=true;setAmount() end
			return
		end
		claimFlightActive=true;finished=false;actualAmount=tonumber(amount) or 0;premiumFlight=premium==true
		sequenceToken+=1;stopIdle();cancelSequence()
		claimHit.Active=false;doubleButton.Active=false
		cue("UI_CLICK_ID",.65)
		local hud=playerGui:FindFirstChild("MainHUD")
		local target=hud and hud:FindFirstChild("StardustDisplay",true)
		if target and (not target:IsA("GuiObject") or not target.Visible) then target=nil end
		local targetNumber=target and target:FindFirstChild("Amount")
		local reduced=player:GetAttribute("ReduceMotion")==true
		layer=Instance.new("ScreenGui");layer.Name="OfflineClaimCelebration";layer.ResetOnSpawn=false
		layer.IgnoreGuiInset=true;layer.DisplayOrder=100;layer.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;layer.Parent=playerGui
		local surface=makeFrame({Parent=layer,Size=UDim2.fromScale(1,1),Transparency=1})
		local function center(object) return object.AbsolutePosition+object.AbsoluteSize/2-surface.AbsolutePosition end
		local start=center(rewardText)
		local designScale=math.clamp(responsive.Scale,.4,1.1)
		token=makeFrame({Name="RewardToken",Parent=surface,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(start.X,start.Y),Size=UDim2.fromOffset(220,52),Transparency=1,ZIndex=10})
		token.Visible=false
		local row=Instance.new("UIListLayout");row.FillDirection=Enum.FillDirection.Horizontal;row.SortOrder=Enum.SortOrder.LayoutOrder
		row.HorizontalAlignment=Enum.HorizontalAlignment.Center;row.VerticalAlignment=Enum.VerticalAlignment.Center;row.Padding=UDim.new(0,5);row.Parent=token
		local icon=makeLabel({Parent=token,Text="★",Color=Color3.fromRGB(255,216,76),Position=UDim2.new(),Size=UDim2.fromOffset(42,48),Max=41,Stroke=2.4,ZIndex=11});icon.LayoutOrder=1
		amountLabel=makeLabel({Parent=token,Text="",Color=Color3.fromRGB(145,255,167),Position=UDim2.new(),Size=UDim2.fromOffset(160,50),Stroke=2.2,ZIndex=11})
		amountLabel.LayoutOrder=2;amountLabel.TextScaled=false;amountLabel.TextSize=34
		tokenScale=Instance.new("UIScale");tokenScale.Parent=token
		setAmount()
		local stars={}
		local count=reduced and 0 or (camera.ViewportSize.X<650 and 14 or (premiumFlight and 26 or 22))
		for i=1,count do
			local bill,scale,core,halo=makeStardust(surface,i)
			local angle=i*2.399963
			local radius=(52+(i%5)*13)*designScale
			stars[i]={object=bill,scale=scale,core=core,halo=halo,rim=core:FindFirstChildOfClass("UIStroke"),scatter=Vector2.new(math.cos(angle)*radius,math.sin(angle)*radius*.65-30*designScale),rotation=(i%7-3)*7,depart=.35+(i-1)*.009,travel=.62+(i%4)*.012,landed=false}
		end
		local lastTick=-1
		local pulseAt=.96
		local sparks={}
		for i=1,(reduced and 0 or 3) do
			sparks[i]=makeLabel({Parent=surface,Text="✦",Color=i%2==0 and COLOR.Gold or Color3.fromRGB(183,255,212),AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(start.X,start.Y),Size=UDim2.fromOffset(12,12),Max=12,ZIndex=9})
			sparks[i].Visible=false
		end
		if targetNumber then hudScale=targetNumber:FindFirstChildOfClass("UIScale");hudBase=hudScale and hudScale.Scale end
		local began=os.clock()
		local popAt=.09
		local flyAt=.35
		local landAt=reduced and .3 or 1.23
		local endAt=landAt+.2
		local popped,launched,landed=false,false,false
		local lifted=start+Vector2.new(0,-54*designScale)
		local function fadeToken(value)
			icon.TextTransparency=value;amountLabel.TextTransparency=value
			icon:FindFirstChildOfClass("UIStroke").Transparency=value
			amountLabel:FindFirstChildOfClass("UIStroke").Transparency=value
		end
		connection=game:GetService("RunService").RenderStepped:Connect(function()
			if not alive or not panel.Visible or not isOpen then dispose();return end
			local elapsed=os.clock()-began
			if elapsed<popAt then
				rewardScale.Scale=reduced and 1 or 1+.07*math.sin(elapsed/popAt*math.pi)
				return
			end
			if not popped then
				popped=true;token.Visible=true;rewardText.TextTransparency=1;rewardScale.Scale=1
				local outline=rewardText:FindFirstChildOfClass("UIStroke");if outline then outline.Transparency=1 end
				cue("GEM_PICKUP_IDS",.7)
			end
			if elapsed>=flyAt and not launched and not reduced then launched=true;cue("ROLL_START_ID",.25) end
			local destination=target and target.Parent and center(targetNumber or target) or lifted
			-- Stars bloom with zero endpoint velocity, then follow soft individual arcs.
			for i,bill in ipairs(stars) do
				local localTime=elapsed-popAt-(i%4)*.008
				if localTime>=0 and not bill.landed then
					bill.object.Visible=true
					local scatter=start+bill.scatter
					scatter=Vector2.new(math.clamp(scatter.X,35,math.max(35,surface.AbsoluteSize.X-35)),math.clamp(scatter.Y,35,math.max(35,surface.AbsoluteSize.Y-35)))
					if elapsed<bill.depart then
						local p=math.clamp(localTime/.22,0,1)
						local ease=p*p*p*(p*(p*6-15)+10)
						local pos=start:Lerp(scatter,ease)
						bill.object.Position=UDim2.fromOffset(pos.X,pos.Y)
						bill.object.Rotation=bill.rotation*ease
						bill.scale.Scale=designScale*(.35+.65*ease+.07*math.sin(p*math.pi)^2)
					else
						local t=math.clamp((elapsed-bill.depart)/bill.travel,0,1)
						local ease=t*t*t*(t*(t*6-15)+10)
						local control=(scatter+destination)/2+Vector2.new((i%3-1)*28,-45-(i%4)*12)*designScale
						local pos=(1-ease)^2*scatter+2*(1-ease)*ease*control+ease*ease*destination
						bill.object.Position=UDim2.fromOffset(pos.X,pos.Y)
						bill.object.Rotation=bill.rotation*(1-ease)
						bill.scale.Scale=designScale*(1-.65*ease)
						local fade=math.clamp((t-.84)/.16,0,1)
						fade=fade*fade*(3-2*fade)
						bill.core.TextTransparency=fade;bill.rim.Transparency=fade
						bill.halo.TextTransparency=.84+.16*fade
						if t>=1 then
							bill.landed=true;bill.object.Visible=false
							if elapsed-lastTick>.13 then cue("GEM_PICKUP_IDS",.2);lastTick=elapsed end
						end
					end
				end
			end
			if hudScale and hudScale.Parent and not reduced then
				local p=math.clamp((elapsed-pulseAt)/(endAt-pulseAt),0,1)
				hudScale.Scale=hudBase*(1+.1*math.sin(p*math.pi)^2)
			end
			if reduced then
				token.Position=UDim2.fromOffset(start.X,start.Y);tokenScale.Scale=designScale
				fadeToken(math.clamp((elapsed-.18)/.12,0,1))
			elseif elapsed<flyAt then
				local p=math.clamp((elapsed-popAt)/.16,0,1)
				local q=p*p*p*(p*(p*6-15)+10)
				local position=start:Lerp(lifted,q)
				token.Position=UDim2.fromOffset(position.X,position.Y)
				tokenScale.Scale=designScale*(.76+.24*q+.1*math.sin(p*math.pi)^2)
				for i,spark in ipairs(sparks) do
					spark.Visible=true
					local angle=(i-1)/#sparks*math.pi*2-.7
					local pos=position+Vector2.new(math.cos(angle)*70,math.sin(angle)*38)*q*designScale
					spark.Position=UDim2.fromOffset(pos.X,pos.Y);spark.TextTransparency=p
				end
			elseif elapsed<landAt then
				local t=math.clamp((elapsed-flyAt)/(landAt-flyAt),0,1)
				local ease=t*t*t*(t*(t*6-15)+10)
				local control=(lifted+destination)/2+Vector2.new(0,-math.min(90,(destination-lifted).Magnitude*.18))
				local function path(u) return (1-u)^2*lifted+2*(1-u)*u*control+u*u*destination end
				local position=path(ease)
				token.Position=UDim2.fromOffset(position.X,position.Y)
				tokenScale.Scale=designScale*(1-.35*ease)
				fadeToken(math.clamp((t-.78)/.22,0,1))
				for i,spark in ipairs(sparks) do
					local u=math.max(0,ease-i*.022);local pos=path(u)
					spark.Position=UDim2.fromOffset(pos.X,pos.Y)
					spark.TextTransparency=math.clamp(.32+i*.1+t*.45,0,1)
				end
			end
			if elapsed>=landAt then
				if not landed then
					landed=true;token.Visible=false;cue("REWARD_CLAIM_ID",.55)
				end
				local t=math.clamp((elapsed-landAt)/.16,0,1)
				for i,spark in ipairs(sparks) do
					spark.Visible=target~=nil
					local angle=i/#sparks*math.pi*2
					local pos=destination+Vector2.new(math.cos(angle)*34,math.sin(angle)*24)*( .5+t)*designScale
					spark.Position=UDim2.fromOffset(pos.X,pos.Y);spark.TextTransparency=t
				end
			end
			if elapsed>=endAt and not finished then
				finished=true;dispose();close()
			end
		end)
	end
	panel:GetPropertyChangedSignal("Visible"):Connect(function() if not panel.Visible then dispose() end end)
	script.Destroying:Connect(dispose)
end

local function open(data)
	configureDouble(data)
	if isOpen then return end
	isOpen = true
	sequenceToken += 1
	local token = sequenceToken
	stopIdle()
	cancelSequence()

	local amount = tonumber(data.amount) or 0
	local seconds = tonumber(data.seconds) or 0
	local capHours = tonumber(data.capHours) or 8

	mainFade.Restore()
	panel:SetAttribute("Closing",false)
	resetVisuals()
	stripValue.Text = formatDuration(seconds) .. "  /  " .. formatCap(capHours)
	stripLabel.Text = if data.capped then "◷ OFFLINE TIME (MAX)" else "◷ OFFLINE TIME"

	if GuiManager then
		GuiManager:Open("WelcomeBack", true)
		-- Claim or 2X claim are the only ways out: nothing else opens, and the
		-- input blocker rises above the HUD until this closes.
		if GuiManager.SetModal then GuiManager:SetModal("WelcomeBack") end
	end
	panel.Visible = true
	dim.Visible = true


	tween(dim, MOTION.Soft, { BackgroundTransparency = 0.60 })
	tween(card, MOTION.Pop, { BackgroundTransparency = 0.1 })
	local pop = tween(cardScale, MOTION.Pop, { Scale = 1.015 })
	pop.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and sequenceToken == token then
			tween(cardScale, MOTION.Settle, { Scale = 1 })
		end
	end)

	task.delay(0.2, function()
		if sequenceToken ~= token then return end
		local rise = tween(medallionScale,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.08 })
		rise.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and sequenceToken == token then
				tween(medallionScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out), { Scale = 1 })
			end
		end)
		playShine()
	end)

	task.delay(0.35, function()
		if sequenceToken ~= token then return end
		countUp(amount, token)
	end)

	task.delay(0.55, function()
		if sequenceToken ~= token then return end
		tween(strip, MOTION.Soft, { BackgroundTransparency = 0.2 })
		tween(barFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(math.clamp(seconds / (capHours * 3600), 0.03, 1), 1),
		})
		startIdle()
	end)
end

doubleButton.Activated:Connect(function()
	if claimFlightActive then return end
	if purchasing then
		doubleButton.Text="PURCHASE PENDING\nWaiting for Roblox confirmation";return
	end
	if not currentOffer or (tonumber(currentOffer.doubleProductId) or 0)<=0 then
		doubleButton.Text="COMING SOON!\nYour normal earnings are already yours"
		return
	end
	if not currentOffer.doubleAvailable then
		doubleButton.Text="BONUS UNAVAILABLE\nYour normal earnings are already yours";return
	end
	if not purchaseReady then
		configureDouble(currentOffer);return
	end
	purchasing=true;doubleButton.Active=false;doubleButton.Text="PLEASE WAIT..."
	local ok,result=pcall(function()
		return ReplicatedStorage.OfflineEarningsRemotes.PrepareDouble:InvokeServer(currentOffer.offerId)
	end)
	if not ok or not result or not result.ok then
		purchasing=false;doubleButton.Active=true;doubleButton.Text=result and result.message or "TRY AGAIN";return
	end
	doubleButton.Text="PURCHASE PENDING"
	-- The server prompts after durably recording the authoritative bonus quote.
end)
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId,productId,purchased)
	if userId~=player.UserId or not currentOffer or productId~=currentOffer.doubleProductId then return end
	if not purchased then
		purchasing=false
		task.delay(1,function()
			if currentOffer then currentOffer.purchasePending=false;configureDouble(currentOffer) end
		end)
	end
end)
-- ===================== INPUT =====================

claimHit.Activated:Connect(function()
	AnimateRewardToStardust(currentOffer and currentOffer.amount,false)
end)

-- If another popup takes over, GuiManager hides the panel. Tidy up with it.
panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if panel.Visible then return end
	if isOpen then
		isOpen = false
		sequenceToken += 1
		stopIdle()
		cancelSequence()
	end
	dim.Visible = false
end)

-- ===================== SERVER =====================
task.spawn(function()
	local remotes=ReplicatedStorage:WaitForChild("OfflineEarningsRemotes",30)
	if not remotes then return end
	local shown={}
	local function receive(data)
		if type(data)~="table" or not data.amount then return end
		local key=data.offerId or tostring(data.amount)..":"..tostring(data.seconds)
		if shown[key] then return end
		shown[key]=true
		task.wait(1.2)
		local waited=0
		while GuiManager and GuiManager:GetCurrent()~=nil and waited<15 do task.wait(.5);waited+=.5 end
		open(data)
	end
	remotes:WaitForChild("OfflineEarned").OnClientEvent:Connect(receive)
	remotes:WaitForChild("DoubleGranted").OnClientEvent:Connect(function(data)
		purchasing=false;offerVersion+=1;doubleButton.Active=false;doubleButton.Text="2X CLAIMED!"
		if currentOffer then currentOffer.doubleAvailable=false end
		if isOpen then
			AnimateRewardToStardust(data.total,true)
		end
	end)
	-- Recover the popup if the server awarded earnings before this GUI connected.
	for i=1,35 do
		local ok,data=pcall(function() return remotes:WaitForChild("GetOfflineOffer"):InvokeServer() end)
		if ok and data then receive(data);break end
		task.wait(2)
	end
end)
