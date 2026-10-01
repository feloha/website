-- LimitedOfferClient (LocalScript in StarterPlayerScripts)
-- Limited-time offer side popup.
--
-- Updated:
-- - Replaced breathing pulse with a subtle rattle/shake.
-- - Shake is small and cartoonish, not aggressive.
-- - Robux price row is moved slightly higher.
-- - Clean slide-off animation works when pressing X and when timer expires.
-- - No swoop / no rotation on slide-out.
-- - Popup sits ABOVE the Playtime Awards button.
-- - Rescales for phones/tablets/desktops.
-- - Uses your shared GuiStyle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GuiStyle = require(ReplicatedStorage:WaitForChild("GuiStyle"))
local Config = require(ReplicatedStorage:WaitForChild("LimitedOfferConfig"))

local UiResponsive do
	local module = ReplicatedStorage:FindFirstChild("UiResponsive")
	local ok, result = pcall(function() return module and require(module) end)
	UiResponsive = if ok and type(result) == "table" then result else nil
end

local GuiManager do
	local module = ReplicatedStorage:FindFirstChild("GuiManager")
	local ok, result = pcall(function() return module and require(module) end)
	GuiManager = if ok and type(result) == "table" then result else nil
end

local remotes = ReplicatedStorage:WaitForChild("LimitedOfferRemotes")
local showOfferRemote = remotes:WaitForChild("ShowOffer")
local dismissOfferRemote = remotes:WaitForChild("DismissOffer")
local purchaseOfferRemote = remotes:WaitForChild("PurchaseOffer")

local FONT = GuiStyle.FONT
local COL = GuiStyle.COL

-- Remove old copy if Studio reruns the script.
local old = playerGui:FindFirstChild("LimitedOfferUI")
if old then
	old:Destroy()
end

-- ===== GUI ROOT =====

local gui = Instance.new("ScreenGui")
gui.Name = "LimitedOfferUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 60
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

-- ===== SETTINGS =====

local camera = workspace.CurrentCamera
local DESIGN = Vector2.new(1280, 720)

local CARD_W = 330
local CARD_H = 250

local ABOVE_PLAYTIME_GAP = 22
local FALLBACK_Y_SCALE = 0.58

local shownPosition = UDim2.new(1, -22, 0.58, 0)
local hiddenPosition = UDim2.new(1, CARD_W + 90, 0.58, 0)

local currentOfferId = nil
local countdownToken = 0
local isShowing = false

-- Used to stop old shake loops safely.
local rattleToken = 0

-- ===== SMALL HELPERS =====

local function makeText(parent, props)
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "TextLabel"
	label.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	label.Position = props.Position or UDim2.fromScale(0, 0)
	label.Size = props.Size or UDim2.fromOffset(100, 40)
	label.BackgroundTransparency = props.BackgroundTransparency or 1
	label.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(255, 255, 255)
	label.Text = props.Text or ""
	label.Font = props.Font or FONT
	label.TextColor3 = props.TextColor3 or COL.Light
	label.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center
	label.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	label.TextWrapped = props.TextWrapped or false
	label.TextScaled = true
	label.ZIndex = props.ZIndex or 1
	label.Parent = parent

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = props.MinTextSize or 12
	constraint.MaxTextSize = props.MaxTextSize or 36
	constraint.Parent = label

	if props.Stroke ~= false then
		GuiStyle.TextStroke(label, props.StrokeThickness or 2)
	end

	if props.Gloss then
		GuiStyle.GlossText(label)
	end

	return label
end

local function formatRobux(n)
	n = tonumber(n) or 0
	return tostring(math.floor(n))
end

local function findPlaytimeSlot()
	local hud = playerGui:FindFirstChild("MainHUD")
	if not hud then
		return nil
	end

	local slot = hud:FindFirstChild("PlaytimeSlot", true)
	if slot and slot:IsA("GuiObject") then
		return slot
	end

	return nil
end

-- ===== RESPONSIVE HOLDER =====

local holder = Instance.new("Frame")
holder.Name = "LimitedOfferHolder"
holder.AnchorPoint = Vector2.new(1, 0.5)
holder.Position = hiddenPosition
holder.Size = UDim2.fromOffset(CARD_W, CARD_H)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.ZIndex = 20
holder.Rotation = 0
holder.Parent = root

local responsiveScale = Instance.new("UIScale")
responsiveScale.Name = "ResponsiveScale"
responsiveScale.Scale = 1
responsiveScale.Parent = holder

-- This wrapper is what rattles.
-- The holder handles slide-in/out.
local rattleWrapper = Instance.new("Frame")
rattleWrapper.Name = "RattleWrapper"
rattleWrapper.AnchorPoint = Vector2.new(0.5, 0.5)
rattleWrapper.Position = UDim2.fromScale(0.5, 0.5)
rattleWrapper.Size = UDim2.fromOffset(CARD_W, CARD_H)
rattleWrapper.BackgroundTransparency = 1
rattleWrapper.ZIndex = 20
rattleWrapper.Rotation = 0
rattleWrapper.Parent = holder

local function refreshLayout()
	local vp = camera.ViewportSize
	if vp.X < 1 or vp.Y < 1 then return end

	local scale = math.min(vp.X / DESIGN.X, vp.Y / DESIGN.Y)

	if vp.X <= 700 then
		scale = math.clamp(scale, 0.48, 0.66)
	elseif vp.X <= 1000 then
		scale = math.clamp(scale, 0.58, 0.80)
	else
		scale = math.clamp(scale, 0.72, 1)
	end

	local maxAllowedScaleByHeight = (vp.Y * 0.72) / CARD_H
	scale = math.min(scale, maxAllowedScaleByHeight)
	scale = math.clamp(scale, 0.42, 1)
	-- Past 1080p it grows with the screen (never past the height cap above).
	scale = math.min(scale * math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 1, 1.6), maxAllowedScaleByHeight)

	responsiveScale.Scale = scale

	local rightGap = 22
	if vp.X <= 700 then
		rightGap = 12
	elseif vp.X <= 1000 then
		rightGap = 16
	end
	if UiResponsive then
		-- Stay clear of notches and rounded corners.
		local safeOffset, safeSize = UiResponsive.SafeRect()
		rightGap += math.max(UiResponsive.Screen().X - (safeOffset.X + safeSize.X), 0)
	end

	local holderHeight = CARD_H * scale
	local desiredCenterY = vp.Y * FALLBACK_Y_SCALE

	local playtimeSlot = findPlaytimeSlot()
	if playtimeSlot then
		-- AbsolutePosition is measured below the top bar; root is full screen,
		-- so subtracting its position gives this ScreenGui's coordinates.
		local playtimeTopY = playtimeSlot.AbsolutePosition.Y - root.AbsolutePosition.Y
		desiredCenterY = playtimeTopY - ABOVE_PLAYTIME_GAP - (holderHeight / 2)
		-- Phones: Settings and Playtime fill the top of the right column, so
		-- the offer goes UNDER Playtime instead of being squeezed on top of
		-- (and covering) both buttons.
		if UiResponsive and UiResponsive.Layout() == "compact" then
			local playtimeBottomY = playtimeTopY + playtimeSlot.AbsoluteSize.Y
			desiredCenterY = playtimeBottomY + 12 + (holderHeight / 2)
		end
	end

	local minCenterY = (holderHeight / 2) + 12
	local maxCenterY = vp.Y - (holderHeight / 2) - 12

	if maxCenterY < minCenterY then
		desiredCenterY = vp.Y * 0.5
	else
		desiredCenterY = math.clamp(desiredCenterY, minCenterY, maxCenterY)
	end

	shownPosition = UDim2.new(1, -rightGap, 0, desiredCenterY)
	hiddenPosition = UDim2.new(1, CARD_W + 90, 0, desiredCenterY)

	if isShowing then
		holder.Position = shownPosition
	else
		holder.Position = hiddenPosition
	end
end

refreshLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshLayout)
if UiResponsive then
	UiResponsive.Changed:Connect(refreshLayout)
end

-- Never cover an open menu or purchase screen: the offer keeps its timer and
-- simply isn't drawn until the menu closes.
if GuiManager and GuiManager.Changed then
	local function refreshEnabled()
		gui.Enabled = GuiManager:GetCurrent() == nil
	end
	GuiManager.Changed:Connect(refreshEnabled)
	refreshEnabled()
end

task.spawn(function()
	local hud = playerGui:WaitForChild("MainHUD", 15)
	if not hud then return end

	local playtimeSlot = hud:WaitForChild("PlaytimeSlot", 15)
	if not playtimeSlot then return end

	refreshLayout()

	playtimeSlot:GetPropertyChangedSignal("AbsolutePosition"):Connect(refreshLayout)
	playtimeSlot:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshLayout)
end)

-- ===== POPUP CARD =====

local shadow = Instance.new("Frame")
shadow.Name = "DealShadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.fromScale(0.5, 0.5) + UDim2.fromOffset(0, 8)
shadow.Size = UDim2.fromOffset(CARD_W + 12, CARD_H + 12)
shadow.BackgroundColor3 = Color3.fromRGB(16, 9, 32)
shadow.BackgroundTransparency = 0.45
shadow.BorderSizePixel = 0
shadow.ZIndex = 20
shadow.Parent = rattleWrapper
GuiStyle.Corner(shadow, 0.08)

local card = Instance.new("Frame")
card.Name = "LimitedOfferCard"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.fromOffset(CARD_W, CARD_H)
card.BackgroundColor3 = Color3.fromRGB(17, 20, 38)
card.BackgroundTransparency = 0.08
card.BorderSizePixel = 0
card.ZIndex = 25
card.Parent = rattleWrapper
GuiStyle.Corner(card, 0.08)
GuiStyle.Stroke(card, COL.Outline, 4)
GuiStyle.Gradient(card, Color3.fromRGB(42, 52, 105), Color3.fromRGB(12, 16, 34))

local cardTapButton = Instance.new("TextButton")
cardTapButton.Name = "CardTapLayer"
cardTapButton.BackgroundTransparency = 1
cardTapButton.Text = ""
cardTapButton.Size = UDim2.fromScale(1, 1)
cardTapButton.ZIndex = 26
cardTapButton.Parent = card

-- ===== HEADER =====

local header = Instance.new("Frame")
header.Name = "Header"
header.Position = UDim2.fromOffset(0, 0)
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundColor3 = COL.Pink
header.ZIndex = 30
header.Parent = card
GuiStyle.Corner(header, 0.08)
GuiStyle.Stroke(header, COL.Outline, 3)

local headerGrad = Instance.new("UIGradient")
headerGrad.Rotation = 90
headerGrad.Color = ColorSequence.new(COL.Pink, COL.Purple)
headerGrad.Parent = header

local titleLabel = makeText(header, {
	Name = "Title",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 14, 0.5, 0),
	Size = UDim2.new(1, -72, 0.8, 0),
	Text = "LIMITED DEAL!",
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 31,
	StrokeThickness = 3,
	Gloss = true,
	MinTextSize = 18,
	MaxTextSize = 34,
})

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -10, 0.5, 0)
closeButton.Size = UDim2.fromOffset(40, 40)
closeButton.BackgroundColor3 = COL.X
closeButton.AutoButtonColor = false
closeButton.Text = ""
closeButton.ZIndex = 70
closeButton.Parent = header
GuiStyle.Corner(closeButton, 0.3)
GuiStyle.Stroke(closeButton, COL.XBorder, 2.5)

local closeScale = Instance.new("UIScale")
closeScale.Parent = closeButton
GuiStyle.AddHoverScale(closeButton, closeScale, 1.1)

local function makeXBar(rot)
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.Size = UDim2.new(0.58, 0, 0.15, 0)
	bar.BackgroundColor3 = COL.Light
	bar.BorderSizePixel = 0
	bar.Rotation = rot
	bar.ZIndex = 71
	bar.Parent = closeButton
	GuiStyle.Corner(bar, 1)
end

makeXBar(45)
makeXBar(-45)

-- ===== MAIN CONTENT =====

local iconBox = Instance.new("Frame")
iconBox.Name = "IconPlaceholder"
iconBox.Position = UDim2.fromOffset(16, 68)
iconBox.Size = UDim2.fromOffset(92, 92)
iconBox.BackgroundColor3 = Color3.fromRGB(8, 10, 22)
iconBox.BackgroundTransparency = 0.12
iconBox.ZIndex = 30
iconBox.Parent = card
GuiStyle.Corner(iconBox, 0.12)
GuiStyle.Stroke(iconBox, COL.Outline, 3)

local iconText = makeText(iconBox, {
	Name = "IconText",
	Size = UDim2.fromScale(1, 1),
	Text = "ITEM\nART",
	TextColor3 = COL.Muted,
	ZIndex = 31,
	StrokeThickness = 1.5,
	MinTextSize = 12,
	MaxTextSize = 24,
})

local iconImage = Instance.new("ImageLabel")
iconImage.Name = "IconImagePlaceholder"
iconImage.BackgroundTransparency = 1
iconImage.Size = UDim2.fromScale(1, 1)
iconImage.Image = ""
iconImage.ScaleType = Enum.ScaleType.Fit
iconImage.Visible = false
iconImage.ZIndex = 32
iconImage.Parent = iconBox

local itemNameLabel = makeText(card, {
	Name = "ItemName",
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.fromOffset(120, 66),
	Size = UDim2.fromOffset(190, 42),
	Text = "2x Stardust",
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 30,
	StrokeThickness = 2.5,
	Gloss = true,
	MinTextSize = 18,
	MaxTextSize = 34,
})

local descLabel = makeText(card, {
	Name = "Description",
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.fromOffset(120, 110),
	Size = UDim2.fromOffset(188, 50),
	Text = "Grab this boost before it vanishes!",
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(210, 230, 255),
	ZIndex = 30,
	StrokeThickness = 1.5,
	MinTextSize = 12,
	MaxTextSize = 21,
})

-- ===== PRICE ROW =====

local priceRow = Instance.new("Frame")
priceRow.Name = "PriceRow"
priceRow.BackgroundTransparency = 1
priceRow.Position = UDim2.fromOffset(16, 154)
priceRow.Size = UDim2.fromOffset(298, 42)
priceRow.ZIndex = 30
priceRow.Parent = card

local originalPrice = makeText(priceRow, {
	Name = "OriginalPrice",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 0, 0.5, 0),
	Size = UDim2.fromOffset(120, 38),
	Text = "R$ 1000",
	TextColor3 = Color3.fromRGB(180, 190, 215),
	ZIndex = 31,
	StrokeThickness = 1.5,
	MinTextSize = 18,
	MaxTextSize = 28,
})

local strike = Instance.new("Frame")
strike.Name = "Strikethrough"
strike.AnchorPoint = Vector2.new(0.5, 0.5)
strike.Position = UDim2.fromScale(0.5, 0.52)
strike.Size = UDim2.new(0.86, 0, 0, 4)
strike.BackgroundColor3 = COL.X
strike.BorderSizePixel = 0
strike.Rotation = -7
strike.ZIndex = 32
strike.Parent = originalPrice
GuiStyle.Corner(strike, 1)

makeText(priceRow, {
	Name = "Arrow",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 118, 0.5, 0),
	Size = UDim2.fromOffset(36, 34),
	Text = "→",
	TextColor3 = COL.Cyan,
	ZIndex = 31,
	StrokeThickness = 2,
	MinTextSize = 22,
	MaxTextSize = 32,
})

local dealPrice = makeText(priceRow, {
	Name = "DealPrice",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 154, 0.5, 0),
	Size = UDim2.fromOffset(138, 40),
	Text = "R$ 499",
	TextColor3 = COL.Yellow,
	ZIndex = 31,
	StrokeThickness = 3,
	Gloss = true,
	MinTextSize = 24,
	MaxTextSize = 38,
})

-- ===== BUY BUTTON =====

local buyButton = Instance.new("TextButton")
buyButton.Name = "BuyButton"
buyButton.AnchorPoint = Vector2.new(1, 1)
buyButton.Position = UDim2.new(1, -14, 1, -12)
buyButton.Size = UDim2.fromOffset(116, 38)
buyButton.BackgroundColor3 = COL.Green
buyButton.AutoButtonColor = false
buyButton.Text = "BUY"
buyButton.Font = FONT
buyButton.TextScaled = true
buyButton.TextColor3 = COL.Light
buyButton.ZIndex = 70
buyButton.Parent = card
GuiStyle.Corner(buyButton, 0.18)
GuiStyle.Stroke(buyButton, COL.Outline, 3)
GuiStyle.TextStroke(buyButton, 2.5)
GuiStyle.Gradient(buyButton, Color3.fromRGB(95, 255, 120), COL.GreenDark)

local buyTextConstraint = Instance.new("UITextSizeConstraint")
buyTextConstraint.MinTextSize = 18
buyTextConstraint.MaxTextSize = 30
buyTextConstraint.Parent = buyButton

local buyScale = Instance.new("UIScale")
buyScale.Parent = buyButton
GuiStyle.AddHoverScale(buyButton, buyScale, 1.08)

-- ===== SIZZLING FUSE COUNTDOWN =====

local fuseArea = Instance.new("Frame")
fuseArea.Name = "FuseCountdown"
fuseArea.BackgroundTransparency = 1
fuseArea.Position = UDim2.fromOffset(16, 212)
fuseArea.Size = UDim2.fromOffset(178, 28)
fuseArea.ZIndex = 35
fuseArea.Parent = card

local fuseTrack = Instance.new("Frame")
fuseTrack.Name = "FuseTrack"
fuseTrack.AnchorPoint = Vector2.new(0, 0.5)
fuseTrack.Position = UDim2.new(0, 0, 0.5, 0)
fuseTrack.Size = UDim2.fromOffset(130, 12)
fuseTrack.BackgroundColor3 = Color3.fromRGB(45, 32, 24)
fuseTrack.BorderSizePixel = 0
fuseTrack.ZIndex = 36
fuseTrack.Parent = fuseArea
GuiStyle.Corner(fuseTrack, 1)
GuiStyle.Stroke(fuseTrack, COL.Outline, 2)

local fuseFill = Instance.new("Frame")
fuseFill.Name = "BurningFuse"
fuseFill.AnchorPoint = Vector2.new(0, 0.5)
fuseFill.Position = UDim2.new(0, 0, 0.5, 0)
fuseFill.Size = UDim2.new(1, 0, 1, 0)
fuseFill.BackgroundColor3 = COL.Yellow
fuseFill.BorderSizePixel = 0
fuseFill.ZIndex = 37
fuseFill.Parent = fuseTrack
GuiStyle.Corner(fuseFill, 1)

local fuseGradient = Instance.new("UIGradient")
fuseGradient.Rotation = 0
fuseGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 90)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 145, 40)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 70)),
})
fuseGradient.Parent = fuseFill

local spark = Instance.new("TextLabel")
spark.Name = "Spark"
spark.AnchorPoint = Vector2.new(0.5, 0.5)
spark.Position = UDim2.new(1, 0, 0.5, 0)
spark.Size = UDim2.fromOffset(30, 30)
spark.BackgroundTransparency = 1
spark.Text = "✦"
spark.Font = FONT
spark.TextScaled = true
spark.TextColor3 = COL.Yellow
spark.TextStrokeColor3 = COL.X
spark.TextStrokeTransparency = 0.1
spark.Rotation = 0
spark.ZIndex = 40
spark.Parent = fuseTrack

local bomb = Instance.new("TextLabel")
bomb.Name = "BombPlaceholder"
bomb.AnchorPoint = Vector2.new(1, 0.5)
bomb.Position = UDim2.new(1, 0, 0.5, 0)
bomb.Size = UDim2.fromOffset(38, 38)
bomb.BackgroundTransparency = 1
bomb.Text = "💣"
bomb.Font = FONT
bomb.TextScaled = true
bomb.ZIndex = 40
bomb.Parent = fuseArea

local timeLabel = makeText(fuseArea, {
	Name = "TimeLabel",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -38, 0.5, 0),
	Size = UDim2.fromOffset(52, 22),
	Text = "15s",
	TextColor3 = COL.Light,
	ZIndex = 39,
	StrokeThickness = 2,
	MinTextSize = 13,
	MaxTextSize = 20,
})

-- Tiny spark particles around the burn point.
local function spawnSparkParticle()
	if not holder.Visible then return end

	local particle = Instance.new("TextLabel")
	particle.Name = "FuseSparkParticle"
	particle.AnchorPoint = Vector2.new(0.5, 0.5)
	particle.Size = UDim2.fromOffset(math.random(10, 18), math.random(10, 18))
	particle.BackgroundTransparency = 1
	particle.Text = "✦"
	particle.Font = FONT
	particle.TextScaled = true
	particle.TextColor3 = math.random(1, 2) == 1 and COL.Yellow or COL.XBorder
	particle.TextStrokeTransparency = 1
	particle.Rotation = math.random(-30, 30)
	particle.ZIndex = 80
	particle.Parent = card

	local sparkCenter = spark.AbsolutePosition + spark.AbsoluteSize / 2
	local cardOrigin = card.AbsolutePosition
	local localX = sparkCenter.X - cardOrigin.X
	local localY = sparkCenter.Y - cardOrigin.Y

	particle.Position = UDim2.fromOffset(localX, localY)

	local endX = localX + math.random(-18, 18)
	local endY = localY + math.random(-22, 8)

	local tween = TweenService:Create(
		particle,
		TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromOffset(endX, endY),
			TextTransparency = 1,
			Rotation = particle.Rotation + math.random(-90, 90),
		}
	)

	tween:Play()
	tween.Completed:Connect(function()
		if particle then
			particle:Destroy()
		end
	end)
end

local sparkSpinTween = TweenService:Create(
	spark,
	TweenInfo.new(0.35, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
	{ Rotation = 360 }
)

local bombPulseTween = TweenService:Create(
	bomb,
	TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Size = UDim2.fromOffset(42, 42) }
)

-- ===== RATTLE / SHAKE ANIMATION =====

local function stopRattle()
	rattleToken += 1

	rattleWrapper.Position = UDim2.fromScale(0.5, 0.5)
	rattleWrapper.Rotation = 0
end

local function startRattle()
	stopRattle()

	local myToken = rattleToken

	task.spawn(function()
		while isShowing and rattleToken == myToken do
			-- Small delay between shake bursts.
			-- This avoids constant stressful shaking.
			task.wait(0.55 + math.random() * 0.35)

			if not isShowing or rattleToken ~= myToken then
				break
			end

			-- Quick cartoon rattle burst.
			for i = 1, 6 do
				if not isShowing or rattleToken ~= myToken then
					break
				end

				local offsetX = math.random(-4, 4)
				local offsetY = math.random(-3, 3)
				local rot = math.random(-25, 25) / 10 -- -2.5 to 2.5 degrees

				local t = TweenService:Create(
					rattleWrapper,
					TweenInfo.new(0.045, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{
						Position = UDim2.fromScale(0.5, 0.5) + UDim2.fromOffset(offsetX, offsetY),
						Rotation = rot,
					}
				)

				t:Play()
				t.Completed:Wait()
			end

			if isShowing and rattleToken == myToken then
				local reset = TweenService:Create(
					rattleWrapper,
					TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{
						Position = UDim2.fromScale(0.5, 0.5),
						Rotation = 0,
					}
				)

				reset:Play()
				reset.Completed:Wait()
			end
		end
	end)
end

-- ===== OFFER ANIMATION =====

local function slideOut(reason)
	if not isShowing then return end

	local startPosition = holder.Position

	-- Slide out to the right from the current Y position.
	-- This avoids sudden jumps if the screen/layout changes.
	local targetPosition = UDim2.new(
		1,
		CARD_W + 90,
		holder.Position.Y.Scale,
		holder.Position.Y.Offset
	)

	local offerIdToDismiss = currentOfferId

	isShowing = false
	countdownToken += 1

	stopRattle()
	sparkSpinTween:Cancel()
	bombPulseTween:Cancel()

	holder.Position = startPosition
	holder.Rotation = 0
	holder.Visible = true

	local outInfo = TweenInfo.new(
		0.38,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.In
	)

	local tween = TweenService:Create(holder, outInfo, {
		Position = targetPosition,
		Rotation = 0,
	})

	tween:Play()

	tween.Completed:Connect(function()
		if not isShowing then
			holder.Visible = false
			holder.Rotation = 0
			holder.Position = targetPosition
		end
	end)

	if offerIdToDismiss then
		dismissOfferRemote:FireServer(offerIdToDismiss, reason or "dismissed")
	end
end

local function applyDeal(deal)
	deal = deal or Config.Deal

	titleLabel.Text = deal.Title or "LIMITED DEAL!"
	itemNameLabel.Text = deal.ItemName or "Mystery Item"
	descLabel.Text = deal.Description or "Special limited-time offer!"

	originalPrice.Text = "R$ " .. formatRobux(deal.OriginalPrice)
	dealPrice.Text = "R$ " .. formatRobux(deal.DealPrice)

	if deal.IconImage and deal.IconImage ~= "" then
		iconImage.Image = deal.IconImage
		iconImage.Visible = true
		iconText.Visible = false
	else
		iconImage.Visible = false
		iconText.Visible = true
	end
end

local function startCountdown(duration)
	countdownToken += 1
	local token = countdownToken

	duration = math.max(1, tonumber(duration) or 15)

	local finishClock = os.clock() + duration

	fuseFill.Size = UDim2.new(1, 0, 1, 0)
	spark.Position = UDim2.new(1, 0, 0.5, 0)
	timeLabel.Text = tostring(math.ceil(duration)) .. "s"

	sparkSpinTween:Play()
	bombPulseTween:Play()

	task.spawn(function()
		local sparkAccumulator = 0

		while countdownToken == token and isShowing do
			local remaining = finishClock - os.clock()
			local alpha = math.clamp(remaining / duration, 0, 1)

			fuseFill.Size = UDim2.new(alpha, 0, 1, 0)
			spark.Position = UDim2.new(alpha, 0, 0.5, 0)
			timeLabel.Text = tostring(math.ceil(math.max(0, remaining))) .. "s"

			local dt = RunService.Heartbeat:Wait()
			sparkAccumulator += dt

			if sparkAccumulator >= 0.10 then
				sparkAccumulator = 0
				spawnSparkParticle()
			end

			if remaining <= 0 then
				break
			end
		end

		if countdownToken == token and isShowing then
			timeLabel.Text = "0s"
			fuseFill.Size = UDim2.new(0, 0, 1, 0)
			spark.Position = UDim2.new(0, 0, 0.5, 0)

			slideOut("expired")
		end
	end)
end

local function slideIn(payload)
	local deal = payload and payload.Deal or Config.Deal
	local duration = payload and payload.Duration or Config.OfferDurationSeconds

	currentOfferId = payload and payload.OfferId or "LocalOffer"

	applyDeal(deal)

	isShowing = true
	holder.Visible = true
	holder.Rotation = 0

	rattleWrapper.Position = UDim2.fromScale(0.5, 0.5)
	rattleWrapper.Rotation = 0

	refreshLayout()
	holder.Position = hiddenPosition

	local inInfo = TweenInfo.new(0.42, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

	TweenService:Create(holder, inInfo, {
		Position = shownPosition,
		Rotation = 0,
	}):Play()

	startCountdown(duration)

	-- Start rattling after it finishes sliding in.
	task.delay(0.45, function()
		if isShowing then
			startRattle()
		end
	end)
end

-- ===== BUTTON EVENTS =====

closeButton.Activated:Connect(function()
	slideOut("closed")
end)

buyButton.Activated:Connect(function()
	if not currentOfferId then return end

	-- Purchase placeholder only.
	-- TODO: Later replace this with your real MarketplaceService prompt.
	--
	-- Example for gamepass later:
	-- local MarketplaceService = game:GetService("MarketplaceService")
	-- MarketplaceService:PromptGamePassPurchase(player, YOUR_GAMEPASS_ID)
	--
	-- Example for developer product later:
	-- MarketplaceService:PromptProductPurchase(player, YOUR_PRODUCT_ID)

	print("[LimitedOfferClient] Purchase placeholder clicked for offer:", currentOfferId)
	purchaseOfferRemote:FireServer(currentOfferId)
end)

cardTapButton.Activated:Connect(function()
	if not currentOfferId then return end

	print("[LimitedOfferClient] Offer card tapped:", currentOfferId)
	purchaseOfferRemote:FireServer(currentOfferId)
end)

-- ===== SERVER EVENT =====

showOfferRemote.OnClientEvent:Connect(function(payload)
	if isShowing then
		slideOut("replaced")
		task.wait(0.45)
	end

	slideIn(payload)
end)