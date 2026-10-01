-- SettingsClient (LocalScript in StarterPlayer > StarterPlayerScripts)
-- Gear button bottom-right + settings panel. Additive; no existing UI is modified.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local Settings = require(ReplicatedStorage:WaitForChild("ClientSettings"))
local GuiStyle = require(ReplicatedStorage:WaitForChild("GuiStyle"))

local UiResponsive do
	local module = ReplicatedStorage:FindFirstChild("UiResponsive")
	local ok, result = pcall(function() return module and require(module) end)
	UiResponsive = if ok and type(result) == "table" then result else nil
end

local GuiManager do
	local module = ReplicatedStorage:FindFirstChild("GuiManager")
		or ReplicatedStorage:FindFirstChild("PopupManager")
	GuiManager = module and require(module) or nil
end

local COL = GuiStyle.COL
local FONT = GuiStyle.FONT
local IS_TOUCH = UserInputService.TouchEnabled

local MOTION = {
	Open = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Settle = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Close = TweenInfo.new(0.20, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
	Fade = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

local SOUND = {
	OpenId = "rbxassetid://7218169592",
	OpenVolume = 0.55,
	TickId = "rbxassetid://7218169592",
	TickVolume = 0.32,
	HoverId = "rbxassetid://7218169592",
	HoverVolume = 0.24,
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

local openSound = makeSound("SettingsOpenSound", SOUND.OpenId, SOUND.OpenVolume)
local tickSound = makeSound("SettingsTickSound", SOUND.TickId, SOUND.TickVolume)
local hoverSound = makeSound("SettingsHoverSound", SOUND.HoverId, SOUND.HoverVolume)

local function play(sound)
	if sound and sound.Volume > 0 then
		sound.TimePosition = 0
		sound:Play()
	end
end

local old = playerGui:FindFirstChild("SettingsHUD")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "SettingsHUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.DisplayOrder = 6
gui.Parent = playerGui

-- ===================== GEAR BUTTON =====================
local gearHolder = Instance.new("Frame")
gearHolder.Name = "SettingsButtonHolder"
gearHolder.AnchorPoint = Vector2.new(1, 1)
gearHolder.Position = if IS_TOUCH then UDim2.new(1, -20, 1, -186) else UDim2.new(1, -22, 1, -22)
gearHolder.Size = UDim2.fromOffset(68, 68)
gearHolder.BackgroundTransparency = 1
gearHolder.ZIndex = 20
gearHolder.Parent = gui

local gearScale = Instance.new("UIScale")
gearScale.Parent = gearHolder

local gearShadow = Instance.new("Frame")
gearShadow.Position = UDim2.fromOffset(0, 5)
gearShadow.Size = UDim2.fromScale(1, 1)
gearShadow.BackgroundColor3 = COL.Shadow
gearShadow.BackgroundTransparency = 0.4
gearShadow.BorderSizePixel = 0
gearShadow.ZIndex = 20
gearShadow.Parent = gearHolder
GuiStyle.Corner(gearShadow, 0.3)

local gearBtn = Instance.new("TextButton")
gearBtn.Name = "SettingsButton"
gearBtn.Size = UDim2.fromScale(1, 1)
gearBtn.BackgroundColor3 = Color3.fromRGB(86, 168, 255)
gearBtn.AutoButtonColor = false
gearBtn.Text = ""
gearBtn.ZIndex = 21
gearBtn.Parent = gearHolder
GuiStyle.Corner(gearBtn, 0.3)
GuiStyle.Stroke(gearBtn, COL.Outline, 4)
GuiStyle.Gradient(gearBtn, Color3.fromRGB(255, 255, 255), Color3.fromRGB(198, 198, 198))

-- Centred by its own frame rather than by padding, which was skewing the glyph.
local gearIcon = Instance.new("TextLabel")
gearIcon.AnchorPoint = Vector2.new(0.5, 0.5)
gearIcon.Position = UDim2.fromScale(0.5, 0.5)
gearIcon.Size = UDim2.fromScale(0.62, 0.62)
gearIcon.BackgroundTransparency = 1
gearIcon.Text = "⚙"
gearIcon.Font = FONT
gearIcon.TextScaled = true
gearIcon.TextXAlignment = Enum.TextXAlignment.Center
gearIcon.TextYAlignment = Enum.TextYAlignment.Center
gearIcon.TextColor3 = COL.Light
gearIcon.ZIndex = 22
gearIcon.Parent = gearBtn
GuiStyle.TextStroke(gearIcon, 2.5)
local iconRatio = Instance.new("UIAspectRatioConstraint")
iconRatio.AspectRatio = 1
iconRatio.Parent = gearIcon

gearBtn.MouseEnter:Connect(function()
	play(hoverSound)
	TweenService:Create(gearScale, GuiStyle.HOVER_IN, { Scale = 1.09 }):Play()
	TweenService:Create(gearIcon, MOTION.Settle, { Rotation = 45 }):Play()
end)
gearBtn.MouseLeave:Connect(function()
	TweenService:Create(gearScale, GuiStyle.HOVER_OUT, { Scale = 1 }):Play()
	TweenService:Create(gearIcon, MOTION.Settle, { Rotation = 0 }):Play()
end)

-- ===================== FPS COUNTER =====================
local fpsLabel = Instance.new("TextLabel")
fpsLabel.Name = "FpsCounter"
fpsLabel.AnchorPoint = Vector2.new(1, 1)
fpsLabel.Position = if IS_TOUCH then UDim2.new(1, -20, 1, -260) else UDim2.new(1, -22, 1, -96)
fpsLabel.Size = UDim2.fromOffset(88, 28)
fpsLabel.BackgroundColor3 = Color3.fromRGB(26, 32, 62)
fpsLabel.BackgroundTransparency = 0.2
fpsLabel.Text = "-- FPS"
fpsLabel.Font = FONT
fpsLabel.TextScaled = true
fpsLabel.TextColor3 = COL.Cyan
fpsLabel.Visible = false
fpsLabel.ZIndex = 20
fpsLabel.Parent = gui
GuiStyle.Corner(fpsLabel, 0.3)
GuiStyle.Stroke(fpsLabel, COL.Outline, 2)
local fpsPad = Instance.new("UIPadding")
fpsPad.PaddingTop = UDim.new(0, 4)
fpsPad.PaddingBottom = UDim.new(0, 4)
fpsPad.Parent = fpsLabel

task.spawn(function()
	while gui.Parent do
		if fpsLabel.Visible then
			local fps = Settings.GetFps()
			fpsLabel.Text = math.floor(fps + 0.5) .. " FPS"
			fpsLabel.TextColor3 = if fps >= 45 then COL.Green
				elseif fps >= 28 then COL.Yellow
				else COL.X
		end
		task.wait(0.5)
	end
end)

-- ===================== PANEL =====================
local dim = Instance.new("Frame")
dim.Name = "SettingsDim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.fromRGB(2, 4, 14)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Visible = false
dim.ZIndex = 28
dim.Parent = gui

local wrapper = Instance.new("Frame")
wrapper.Name = "SettingsWrapper"
wrapper.AnchorPoint = Vector2.new(0.5, 0.5)
wrapper.Position = UDim2.fromScale(0.5, 0.5)
wrapper.Size = UDim2.fromOffset(620, 500)
wrapper.BackgroundTransparency = 1
wrapper.ZIndex = 30
wrapper.Parent = gui

local responsive = Instance.new("UIScale")
responsive.Name = "ResponsiveScale"
responsive.Parent = wrapper

local function refreshScale()
	if UiResponsive then
		-- Phones get a shorter panel (the list scrolls) instead of tiny text.
		local scale, width, height = UiResponsive.FitPanel(620, 500, { minWidth = 460, minHeight = 280, margin = 16 })
		responsive.Scale = scale
		wrapper.Size = UDim2.fromOffset(width, height)

		-- Gear and FPS counter: inside the safe area, and above the jump button
		-- while playing with touch.
		local safeOffset, safeSize = UiResponsive.SafeRect()
		local screen = UiResponsive.Screen()
		local right = math.max(screen.X - (safeOffset.X + safeSize.X), 0)
		local bottom = math.max(screen.Y - (safeOffset.Y + safeSize.Y), 0)
		-- Placed by what the device CAN do, not the last input, so the gear never
		-- jumps around when a touch screen also sends mouse clicks.
		local touchDevice = UserInputService.TouchEnabled
		local phone = touchDevice and UiResponsive.Layout() == "compact"
		if phone then
			-- Top-right, well away from the jump button and the playtime button.
			local top = math.max(UiResponsive.TopInset(), safeOffset.Y) + 6
			gearHolder.AnchorPoint = Vector2.new(1, 0)
			-- Right zone: one stack with the Playtime button (MainHUD owns the
			-- zone). The gear sits on the Playtime button's centre line, one
			-- sibling gap above it; 40 matches the HUD buttons around it.
			local SP = UiResponsive.Space or { M = 12, L = 18 }
			gearHolder.AnchorPoint = Vector2.new(0.5, 1)
			gearHolder.Size = UDim2.fromOffset(40, 40)
			local hud = playerGui:FindFirstChild("MainHUD")
			local slot = hud and hud:FindFirstChild("PlaytimeSlot", true)
			if slot and slot.AbsoluteSize.X > 0 then
				local at = UiResponsive.ToScreen(slot.AbsolutePosition)
				gearHolder.Position = UDim2.fromOffset(math.floor(at.X + slot.AbsoluteSize.X / 2 + 0.5), math.floor(at.Y - SP.M + 0.5))
			else
				gearHolder.Position = UDim2.new(1, -(right + SP.M + 20), 0, top + SP.L + 40)
			end
			fpsLabel.AnchorPoint = Vector2.new(1, 0)
			fpsLabel.Position = UDim2.new(1, -(right + 58), 0, top + 6)
		elseif touchDevice then
			gearHolder.AnchorPoint = Vector2.new(1, 1)
			gearHolder.Size = UDim2.fromOffset(68, 68)
			gearHolder.Position = UDim2.new(1, -(right + 20), 1, -(bottom + 186))
			fpsLabel.AnchorPoint = Vector2.new(1, 1)
			fpsLabel.Position = UDim2.new(1, -(right + 20), 1, -(bottom + 260))
		else
			gearHolder.AnchorPoint = Vector2.new(1, 1)
			gearHolder.Size = UDim2.fromOffset(68, 68)
			gearHolder.Position = UDim2.new(1, -(right + 22), 1, -(bottom + 22))
			fpsLabel.AnchorPoint = Vector2.new(1, 1)
			fpsLabel.Position = UDim2.new(1, -(right + 22), 1, -(bottom + 96))
		end
		return
	end
	local vp = camera.ViewportSize
	if vp.X < 1 then return end
	responsive.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.5, 1)
		* math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 1, 1.6)
end
refreshScale()
if UiResponsive then
	UiResponsive.Changed:Connect(refreshScale)
else
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
end
-- The phone gear follows MainHUD's Playtime button (same right stack).
task.spawn(function()
	local hud = playerGui:WaitForChild("MainHUD", 30)
	local slot = hud and hud:WaitForChild("PlaytimeSlot", 30)
	if not slot then return end
	slot:GetPropertyChangedSignal("AbsolutePosition"):Connect(refreshScale)
	slot:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshScale)
	refreshScale()
end)

-- Flat translucent navy. The old multiply-gradient crushed this to near black.
local panel = Instance.new("Frame")
panel.Name = "SettingsPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(1, 1)
panel.BackgroundColor3 = Color3.fromRGB(30, 37, 74)
panel.BackgroundTransparency = 0.18
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Visible = false
panel.ZIndex = 30
panel.Parent = wrapper
GuiStyle.Corner(panel, 0.045)
GuiStyle.Stroke(panel, COL.Cyan, 3)

local panelScale = Instance.new("UIScale")
panelScale.Name = "PanelScale"
panelScale.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 78)
header.BackgroundColor3 = Color3.fromRGB(38, 76, 156)
header.BackgroundTransparency = 0.05
header.BorderSizePixel = 0
header.ZIndex = 35
header.Parent = panel
GuiStyle.Gradient(header, Color3.fromRGB(255, 255, 255), Color3.fromRGB(176, 196, 255))
GuiStyle.Stroke(header, COL.Outline, 3)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(24, 8)
title.Size = UDim2.new(1, -110, 1, -16)
title.Text = "Settings"
title.Font = FONT
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = COL.Light
title.ZIndex = 37
title.Parent = header
GuiStyle.TextStroke(title, 3)
GuiStyle.GlossText(title)
local titleCap = Instance.new("UITextSizeConstraint")
titleCap.MaxTextSize = 46
titleCap.Parent = title

local body = Instance.new("ScrollingFrame")
body.Position = UDim2.new(0, 14, 0, 90)
body.Size = UDim2.new(1, -28, 1, -104)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 5
body.ScrollBarImageColor3 = COL.Cyan
body.CanvasSize = UDim2.new()
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.ZIndex = 31
body.Parent = panel

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = body

local rowOrder = 0
local function nextOrder()
	rowOrder += 1
	return rowOrder
end

local function section(text)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = nextOrder()
	label.Size = UDim2.new(1, -12, 0, 30)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = FONT
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = COL.Cyan
	label.ZIndex = 32
	label.Parent = body
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 21
	cap.Parent = label
	GuiStyle.TextStroke(label, 2)
end

local function row(labelText, hint)
	local frame = Instance.new("Frame")
	frame.LayoutOrder = nextOrder()
	frame.Size = UDim2.new(1, -12, 0, if hint then 60 else 48)
	frame.BackgroundColor3 = Color3.fromRGB(48, 58, 108)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.ZIndex = 32
	frame.Parent = body
	GuiStyle.Corner(frame, 0.22)
	GuiStyle.Stroke(frame, Color3.fromRGB(78, 92, 158), 2)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 14, 0, if hint then 7 else 0)
	label.Size = if hint then UDim2.new(0.44, -14, 0, 24) else UDim2.new(0.44, -14, 1, 0)
	label.Text = labelText
	label.Font = FONT
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = COL.Light
	label.ZIndex = 33
	label.Parent = frame
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 19
	cap.Parent = label
	GuiStyle.TextStroke(label, 1.5)

	if hint then
		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.new(0, 14, 0, 33)
		sub.Size = UDim2.new(0.5, -14, 0, 18)
		sub.Text = hint
		sub.Font = FONT
		sub.TextScaled = true
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.TextColor3 = Color3.fromRGB(186, 200, 235)
		sub.ZIndex = 33
		sub.Parent = frame
		local subCap = Instance.new("UITextSizeConstraint")
		subCap.MaxTextSize = 14
		subCap.Parent = sub
	end

	return frame
end

-- ---------- controls ----------
local function makeToggle(parent, key)
	local track = Instance.new("TextButton")
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -14, 0.5, 0)
	track.Size = UDim2.fromOffset(62, 30)
	track.AutoButtonColor = false
	track.Text = ""
	track.BackgroundColor3 = Color3.fromRGB(60, 70, 118)
	track.ZIndex = 34
	track.Parent = parent
	GuiStyle.Corner(track, 1)
	GuiStyle.Stroke(track, COL.Outline, 2)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Size = UDim2.fromOffset(24, 24)
	knob.BackgroundColor3 = COL.Light
	knob.BorderSizePixel = 0
	knob.ZIndex = 35
	knob.Parent = track
	GuiStyle.Corner(knob, 1)

	local function render()
		local on = Settings.Get(key) == true
		TweenService:Create(track, MOTION.Settle, {
			BackgroundColor3 = if on then COL.Green else Color3.fromRGB(60, 70, 118),
		}):Play()
		TweenService:Create(knob, GuiStyle.HOVER_IN, {
			Position = if on then UDim2.new(1, -27, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
		}):Play()
	end

	render()
	track.Activated:Connect(function()
		play(tickSound)
		Settings.Set(key, not (Settings.Get(key) == true))
	end)
	track.MouseEnter:Connect(function() play(hoverSound) end)
	Settings.OnChanged(function(changed)
		if changed == key then render() end
	end)
end

local function makeSlider(parent, key)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -14, 0.5, 0)
	holder.Size = UDim2.fromOffset(235, 34)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 34
	holder.Parent = parent

	local readout = Instance.new("TextLabel")
	readout.AnchorPoint = Vector2.new(1, 0.5)
	readout.Position = UDim2.new(1, 0, 0.5, 0)
	readout.Size = UDim2.fromOffset(52, 22)
	readout.BackgroundTransparency = 1
	readout.Font = FONT
	readout.TextScaled = true
	readout.TextXAlignment = Enum.TextXAlignment.Right
	readout.TextColor3 = COL.Yellow
	readout.ZIndex = 35
	readout.Parent = holder
	GuiStyle.TextStroke(readout, 1.5)

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 0, 0.5, 0)
	track.Size = UDim2.new(1, -60, 0, 12)
	track.BackgroundColor3 = Color3.fromRGB(22, 27, 56)
	track.BorderSizePixel = 0
	track.ZIndex = 34
	track.Parent = holder
	GuiStyle.Corner(track, 1)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = COL.Cyan
	fill.BorderSizePixel = 0
	fill.ZIndex = 35
	fill.Parent = track
	GuiStyle.Corner(fill, 1)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.Size = UDim2.fromOffset(22, 22)
	knob.BackgroundColor3 = COL.Light
	knob.BorderSizePixel = 0
	knob.ZIndex = 36
	knob.Parent = track
	GuiStyle.Corner(knob, 1)
	GuiStyle.Stroke(knob, COL.Outline, 2)

	local function render(value)
		fill.Size = UDim2.fromScale(value, 1)
		knob.Position = UDim2.fromScale(value, 0.5)
		readout.Text = math.floor(value * 100 + 0.5) .. "%"
	end

	render(Settings.Get(key))

	local dragging = false
	local lastTick = 0
	local function setFrom(x)
		local width = track.AbsoluteSize.X
		if width <= 0 then return end
		local value = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		render(value)
		Settings.Set(key, value)
		local now = os.clock()
		if now - lastTick > 0.12 then
			lastTick = now
			play(tickSound)
		end
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFrom(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			setFrom(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	Settings.OnChanged(function(changed)
		if changed == key and not dragging then render(Settings.Get(key)) end
	end)
end

local function makeSegmented(parent, options, getValue, setValue)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -14, 0.5, 0)
	holder.Size = UDim2.fromOffset(280, 36)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 34
	holder.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = holder

	local buttons = {}
	local function render()
		local current = getValue()
		for value, button in pairs(buttons) do
			local on = value == current
			TweenService:Create(button, MOTION.Settle, {
				BackgroundColor3 = if on then COL.Blue else Color3.fromRGB(60, 70, 118),
			}):Play()
			button.TextColor3 = if on then COL.Light else Color3.fromRGB(182, 195, 230)
		end
	end

	for index, option in ipairs(options) do
		local button = Instance.new("TextButton")
		button.LayoutOrder = index
		button.Size = UDim2.new(1 / #options, -6, 1, 0)
		button.BackgroundColor3 = Color3.fromRGB(60, 70, 118)
		button.AutoButtonColor = false
		button.Text = option.text
		button.Font = FONT
		button.TextScaled = true
		button.TextColor3 = Color3.fromRGB(182, 195, 230)
		button.ZIndex = 35
		button.Parent = holder
		GuiStyle.Corner(button, 0.28)
		GuiStyle.Stroke(button, COL.Outline, 2)
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = 16
		cap.Parent = button
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 9)
		pad.PaddingBottom = UDim.new(0, 9)
		pad.Parent = button

		buttons[option.value] = button
		button.Activated:Connect(function()
			play(tickSound)
			setValue(option.value)
			render()
		end)
		button.MouseEnter:Connect(function() play(hoverSound) end)
	end

	render()
	Settings.OnChanged(render)
end

-- ---------- rows ----------
section("AUDIO")
makeSlider(row("Music Volume"), "MusicVolume")
makeSlider(row("Sound Effects"), "SfxVolume")

section("GRAPHICS")
makeSegmented(
	row("Quality Preset", "Changing anything below switches this to Custom"),
	{
		{ text = "LOW", value = "LOW" },
		{ text = "MODERATE", value = "MODERATE" },
		{ text = "HIGH", value = "HIGH" },
	},
	function() return Settings.Get("Quality") end,
	function(value) Settings.ApplyPreset(value) end
)
makeToggle(row("Orbital Rings", "Spinning arcs around each black hole"), "OrbitalRings")
makeToggle(row("Particles", "Debris drifting inward"), "Particles")
makeToggle(row("Shadows"), "Shadows")
makeToggle(row("Bloom Glow", "Off by default, adds a soft halo"), "Bloom")
makeToggle(row("Reduce Motion", "Freezes spin and float animation"), "ReduceMotion")
makeSegmented(
	row("Render Distance", "How far black hole models draw"),
	{
		{ text = "NEAR", value = 110 },
		{ text = "MID", value = 175 },
		{ text = "FAR", value = 280 },
	},
	function() return Settings.Get("RenderDistance") end,
	function(value) Settings.Set("RenderDistance", value) end
)

section("INTERFACE")
makeSegmented(
	row("Name Labels", "Cards floating above each black hole"),
	{
		{ text = "OFF", value = "Off" },
		{ text = "NEARBY", value = "Nearby" },
		{ text = "ALL", value = "All" },
	},
	function() return Settings.Get("LabelMode") end,
	function(value) Settings.Set("LabelMode", value) end
)
makeToggle(row("Income Popups", "The floating +★ amounts"), "IncomePopups")
makeToggle(row("FPS Counter"), "FpsCounter")

section("PERFORMANCE")
makeToggle(row("Auto Quality", "Drops a level if framerate falls"), "AutoQuality")

do
	local resetRow = row("Reset to Defaults")
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -14, 0.5, 0)
	button.Size = UDim2.fromOffset(120, 34)
	button.BackgroundColor3 = COL.X
	button.AutoButtonColor = false
	button.Text = "RESET"
	button.Font = FONT
	button.TextScaled = true
	button.TextColor3 = COL.Light
	button.ZIndex = 34
	button.Parent = resetRow
	GuiStyle.Corner(button, 0.28)
	GuiStyle.Stroke(button, COL.XBorder, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = button

	button.MouseEnter:Connect(function() play(hoverSound) end)
	button.Activated:Connect(function()
		play(tickSound)
		Settings.ApplyPreset("HIGH")
		Settings.Set("MusicVolume", 0.5)
		Settings.Set("SfxVolume", 0.8)
		Settings.Set("AutoQuality", false)
		Settings.Set("FpsCounter", false)
	end)
end

local spacer = Instance.new("Frame")
spacer.LayoutOrder = nextOrder()
spacer.Size = UDim2.new(1, 0, 0, 12)
spacer.BackgroundTransparency = 1
spacer.Parent = body

-- ===================== OPEN / CLOSE =====================
-- GuiManager still owns the blur and single-popup rule; the motion is ours.
local isOpen, busy = false, false

if GuiManager then
	GuiManager:Register("Settings", panel, {
		OpenScale = 1, OpenOvershootScale = 1,
		CloseBounceScale = 1, CloseScale = 1,
		CloseBounceTween = TweenInfo.new(0),
		CloseShrinkTween = TweenInfo.new(0),
	})
end

local function openPanel()
	if isOpen or busy then return end
	-- A modal popup (Welcome Back) owns the screen until it is resolved.
	if GuiManager and GuiManager.GetModal and GuiManager:GetModal() then return end
	isOpen, busy = true, true

	if GuiManager then GuiManager:Open("Settings") end
	panel.Visible = true
	dim.Visible = true

	dim.BackgroundTransparency = 1
	panel.BackgroundTransparency = 1
	panelScale.Scale = 0.9
	body.Position = UDim2.new(0, 14, 0, 106)

	TweenService:Create(dim, MOTION.Fade, { BackgroundTransparency = 0.55 }):Play()
	TweenService:Create(panel, MOTION.Open, { BackgroundTransparency = 0.18 }):Play()

	local pop = TweenService:Create(panelScale, MOTION.Open, { Scale = 1.015 })
	pop:Play()
	pop.Completed:Connect(function()
		if isOpen then
			TweenService:Create(panelScale, MOTION.Settle, { Scale = 1 }):Play()
		end
	end)

	task.delay(0.06, function()
		if isOpen then
			TweenService:Create(body, MOTION.Open, { Position = UDim2.new(0, 14, 0, 90) }):Play()
		end
	end)

	task.delay(0.3, function() busy = false end)
end

local function closePanel()
	if not isOpen or busy then return end
	if GuiManager then GuiManager:BeginClose("Settings") end
	isOpen, busy = false, true

	TweenService:Create(dim, MOTION.Close, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(panel, MOTION.Close, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(panelScale, MOTION.Close, { Scale = 0.92 }):Play()

	task.delay(0.21, function()
		busy = false
		if isOpen then return end
		panel.Visible = false
		dim.Visible = false
		panelScale.Scale = 0.9
		if GuiManager then GuiManager:Close("Settings") end
	end)
end

GuiStyle.MakePlaytimeX(header, function()
	play(tickSound)
	closePanel()
end)

if GuiManager and GuiManager.SetBackHandler then
	GuiManager:SetBackHandler("Settings", closePanel)
end

gearBtn.Activated:Connect(function()

	if isOpen then closePanel() else openPanel() end
end)

-- Another popup taking over closes ours cleanly.
panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if not panel.Visible and isOpen then
		isOpen = false
		dim.Visible = false
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and isOpen then
		closePanel()
	end
end)

Settings.OnChanged(function(key)
	if key == "FpsCounter" then
		fpsLabel.Visible = Settings.Get("FpsCounter") == true
	end
end)
fpsLabel.Visible = Settings.Get("FpsCounter") == true

-- ===================== OPTIONAL PERSISTENCE =====================
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("SettingsRemotes", 8)
	if not remotes then return end

	remotes:WaitForChild("SettingsLoaded").OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then return end
		for key, value in pairs(data) do
			if key == "Quality" then
				if Settings.PRESETS[value] then Settings.ApplyPreset(value) end
			else
				Settings.Set(key, value, true)
			end
		end
	end)

	local queued = false
	Settings.OnChanged(function()
		if queued then return end
		queued = true
		task.delay(2, function()
			queued = false
			remotes.SaveSettings:FireServer(Settings.All())
		end)
	end)
end)