-- GuiManager (ModuleScript in ReplicatedStorage)
-- Shared popup manager:
-- - only one popup open at a time
-- - shared SCREEN DIM (a see-through navy layer in the UI, under the popup):
--   the 3D world is never blurred, so attacks, coins and effects stay sharp
--   while a menu is open (a Lighting BlurEffect blurs the whole world)
-- - pop-in on open (small -> full size with a light Back overshoot, rising a
--   few pixels) and pop-out on close (shrinks a little, then hides); both
--   cancel each other safely, so rapid open/close never gets stuck
-- - clicks inside the popup are off until the pop-in finishes
-- - modal: an invisible blocker stops taps and clicks reaching the 3D world
--   while a popup is open. It sits UNDER the main HUD, so the side menu,
--   Upgrade, Playtime and Settings buttons still work: pressing another menu's
--   button closes the open popup and opens that one (no X needed).
-- - gamepad: the first control is selected when a popup opens, B closes it,
--   and selection is released when it closes
-- - Changed signal (name or nil) so other UI can step aside while a popup is open
-- - menu sounds: MENU_OPEN_ID when a popup starts opening (also when switching
--   straight from one menu to another: one sound, not a close + open pair),
--   MENU_CLOSE_ID when it starts closing. Auto-opened startup panels use
--   Open(name, true) for silence. Register option
--   Sounds = false turns them off for one popup.

local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiResponsive do
	local module = ReplicatedStorage:FindFirstChild("UiResponsive")
	local ok, result = pcall(function() return module and require(module) end)
	UiResponsive = if ok and type(result) == "table" then result else nil
end

local GuiManager = {}

local Sounds do
	local module = ReplicatedStorage:FindFirstChild("GameSounds")
	local ok, result = pcall(function() return module and require(module) end)
	Sounds = if ok and type(result) == "table" then result else nil
end

-- Explicit silent opens replace a time-based join mute (which also muted real clicks).
local menuHandle = nil
local menuSerial = 0
if Sounds and Sounds.Preload then
	task.spawn(function() pcall(Sounds.Preload, {"MENU_OPEN_ID", "MENU_CLOSE_ID"}) end)
end
local function menuSound(popup, slot)
	if not Sounds or (popup and popup.Options.Sounds == false) then return end
	menuSerial += 1
	if menuHandle and Sounds.Stop then pcall(Sounds.Stop, menuHandle) end
	local ok, handle = pcall(Sounds.Play, slot, {
		sequence = "menu:" .. menuSerial, maxLate = 0.12,
	})
	menuHandle = if ok then handle else nil
end

local popups = {}
local currentName = nil

-- Modal: while this is set, only that popup may be opened. Requests for any
-- other popup are refused, so hotkeys cannot slip past the input blocker.
local modalName = nil

local changedEvent = Instance.new("BindableEvent")
GuiManager.Changed = changedEvent.Event

local DEFAULTS = {
	-- Screen dim behind an open popup (UI only; see the header). 1 = none.
	DimTransparency = 0.62,
	DimColor = Color3.fromRGB(8, 14, 46),

	-- Pop-in: OpenScale -> OpenOvershootScale (Back overshoots on its own),
	-- then settle to 1 if the overshoot scale isn't 1.
	OpenScale = 0.86,
	OpenOvershootScale = 1,
	OpenRise = 0,              -- pixels low it starts and rises from (popups opt in)

	-- Pop-out: CloseBounceScale (skipped when 1), then shrink to CloseScale and hide.
	CloseBounceScale = 1,
	CloseScale = 0.92,

	OpenPopTween = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	OpenSettleTween = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	CloseBounceTween = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	CloseShrinkTween = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),

	DimTween = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	-- Invisible full-screen blocker behind the popup.
	ModalBlocker = true,
}

-- The old shared world blur, if a previous version left one behind.
do
	local oldBlur = Lighting:FindFirstChild("SharedPopupBlur")
	if oldBlur then oldBlur:Destroy() end
end

local function interactable(frame, value)
	pcall(function() frame.Interactable = value end)
end

-- ===================== INPUT OWNERSHIP =====================
-- A window owns every press that lands on it:
--   Sink    an invisible button under all of the window's contents, so a tap
--           on an empty part of the window never reaches a HUD button behind.
--   Shield  an invisible button over the window while it animates (OPENING /
--           CLOSING): presses are swallowed instead of falling through.
-- (Interactable = false used to do the second job, but a non-interactable
-- window lets taps pass through to whatever is behind it - that is how one
-- tap could open a window and then a second one behind it.)
local function inputCatcher(frame, name, zIndex)
	local existing = frame:FindFirstChild(name)
	if existing then return existing end
	local catcher = Instance.new("TextButton")
	catcher.Name = name
	catcher:SetAttribute("OwnPressAnimation", true)   -- no press bounce on it
	catcher:SetAttribute("InputCatcher", true)
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.BackgroundTransparency = 1
	catcher.BorderSizePixel = 0
	catcher.Selectable = false
	catcher.Active = true
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.ZIndex = zIndex
	catcher.Parent = frame
	return catcher
end

local function setShield(popup, on)
	if popup.Shield then popup.Shield.Visible = on end
end

local function mergeOptions(options)
	local merged = {}

	for key, value in pairs(DEFAULTS) do
		merged[key] = value
	end

	if options then
		for key, value in pairs(options) do
			merged[key] = value
		end
	end

	return merged
end

-- ===================== MODAL BLOCKER =====================
-- One shared blocker in its own ScreenGui, on one of two layers.
-- Normal popups: 3, under HudStack (4) and MainHUD (5). It catches clicks on
-- the world only, so the HUD stays usable and you can go straight from one
-- popup to another.
-- Modal popups: 7, over MainHUD (5) and Settings (6) but under Welcome Back
-- (8), so the modal's own buttons are the only thing left to click.
local BLOCKER_DISPLAY_ORDER = 3
local BLOCKER_MODAL_DISPLAY_ORDER = 7
local blockerGui, blocker = nil, nil
local blockedBy = {}   -- [popup name] = true

local function getBlocker()
	if blocker and blocker.Parent and blockerGui and blockerGui.Parent then return blocker end
	local player = game:GetService("Players").LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return nil end

	local old = playerGui:FindFirstChild("PopupInputBlocker")
	if old then old:Destroy() end
	blockerGui = Instance.new("ScreenGui")
	blockerGui.Name = "PopupInputBlocker"
	blockerGui.ResetOnSpawn = false
	blockerGui.IgnoreGuiInset = true
	blockerGui.DisplayOrder = if modalName then BLOCKER_MODAL_DISPLAY_ORDER else BLOCKER_DISPLAY_ORDER
	blockerGui.Parent = playerGui

	-- The dim: a see-through navy layer over the world, never over the HUD
	-- or the popup (it lives in this low ScreenGui). It takes no clicks.
	local dim = Instance.new("Frame")
	dim.Name = "ScreenDim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = DEFAULTS.DimColor
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Active = false
	dim.Parent = blockerGui
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Transparency = NumberSequence.new(0.1, 0)
	shade.Parent = dim

	blocker = Instance.new("TextButton")
	blocker.Name = "ModalBlocker"
	blocker.Text = ""
	blocker.AutoButtonColor = false
	blocker.BackgroundTransparency = 1
	blocker.BorderSizePixel = 0
	blocker.Selectable = false
	blocker.Active = true
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.Visible = false
	blocker.Parent = blockerGui
	return blocker
end

-- Tweens the screen dim (UI only). Popups that opt out use 1.
local function setDim(transparency, info)
	if not getBlocker() then return end
	local dim = blockerGui:FindFirstChild("ScreenDim")
	if dim then
		TweenService:Create(dim, info or DEFAULTS.DimTween, { BackgroundTransparency = transparency }):Play()
	end
end

local function refreshBlockerLayer()
	if blockerGui and blockerGui.Parent then
		blockerGui.DisplayOrder = if modalName then BLOCKER_MODAL_DISPLAY_ORDER else BLOCKER_DISPLAY_ORDER
	end
end

local function setBlocked(popup, blocked)
	if popup.Options.ModalBlocker == false then return end
	for name, candidate in pairs(popups) do
		if candidate == popup then
			blockedBy[name] = if blocked then true else nil
		end
	end
	local shared = getBlocker()
	if shared then
		refreshBlockerLayer()
		shared.Visible = next(blockedBy) ~= nil
	end
end

-- ===================== GAMEPAD =====================
local BACK_ACTION = "GuiManagerBack"
local backBound = false

local function onBack(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local name = currentName
	local popup = name and popups[name]
	if not popup then
		return Enum.ContextActionResult.Pass
	end
	if popup.BackHandler then
		task.spawn(popup.BackHandler)
	else
		GuiManager:Close(name)
	end
	return Enum.ContextActionResult.Sink
end

local function bindBack(enabled)
	if enabled and not backBound then
		backBound = true
		ContextActionService:BindActionAtPriority(BACK_ACTION, onBack, false,
			Enum.ContextActionPriority.High.Value + 50, Enum.KeyCode.ButtonB)
	elseif not enabled and backBound then
		backBound = false
		ContextActionService:UnbindAction(BACK_ACTION)
	end
end

local function focusPopup(popup, name)
	if not UiResponsive then return end
	-- Wait a moment so the opening animation has laid the controls out.
	task.delay(0.08, function()
		if currentName == name and popup.Frame.Visible then
			UiResponsive.FocusFirst(popup.Frame)
		end
	end)
end

local function releaseFocus(popup)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(popup.Frame) then
		GuiService.SelectedObject = nil
	end
end

-- ===================== API =====================
function GuiManager:Register(name, frame, options)
	assert(type(name) == "string", "GuiManager:Register name must be a string")
	assert(frame and frame:IsA("GuiObject"), "GuiManager:Register frame must be a GuiObject")

	local opts = mergeOptions(options)

	local basePosition = frame.Position
	local scale = frame:FindFirstChild("GuiManagerScale")

	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "GuiManagerScale"
		scale.Scale = opts.OpenScale
		scale.Parent = frame
	end

	frame.Visible = false
	scale.Scale = opts.OpenScale
	-- The window's visible panel owns presses. A full-screen animation group
	-- names its panel with options.InputFrame (otherwise it gets no catchers,
	-- so the HUD around it stays clickable as before).
	local inputFrame = opts.InputFrame or frame
	local fullScreen = inputFrame == frame and frame.Size.X.Scale >= 0.9 and frame.Size.Y.Scale >= 0.9
	local shield = nil
	if not fullScreen then
		pcall(function() inputFrame.Active = true end)
		inputCatcher(inputFrame, "PopupInputSink", 0)
		shield = inputCatcher(inputFrame, "PopupTransitionShield", 100000)
		shield.Visible = false
	end

	local previous = popups[name]

	popups[name] = {
		Frame = frame,
		Scale = scale,
		Options = opts,
		Token = 0,
		BasePosition = basePosition,
		BackHandler = previous and previous.BackHandler or nil,
		Shield = shield,
		InputFrame = inputFrame,
		State = "CLOSED",          -- CLOSED / OPENING / OPEN / CLOSING
	}

	print("[GuiManager] Registered popup:", name)
end

-- Optional: what the gamepad B button does for this popup (for popups with
-- their own close animation). Defaults to GuiManager:Close(name).
function GuiManager:SetBackHandler(name, handler)
	local popup = popups[name]
	if popup then
		popup.BackHandler = handler
	end
end

-- While a popup is modal, nothing else opens until it is closed or released.
function GuiManager:SetModal(name)
	modalName = name
	refreshBlockerLayer()
end

function GuiManager:ClearModal(name)
	if name == nil or modalName == name then
		modalName = nil
		refreshBlockerLayer()
	end
end

function GuiManager:GetModal()
	return modalName
end

function GuiManager:Open(name, silent)
	local popup = popups[name]

	if not popup then
		warn("[GuiManager] Tried to open unregistered popup:", name)
		return false
	end

	if modalName and name ~= modalName then
		-- Deliberate: the modal popup has to be resolved first.
		return false
	end

	if currentName == name then
		return true
	end

	popup.CloseSoundPlayed = nil
	if not silent then menuSound(popup, "MENU_OPEN_ID") end

	-- Hide currently open popup first.
	if currentName and popups[currentName] then
		local old = popups[currentName]
		old.Token += 1
		old.Frame.Visible = false
		old.Scale.Scale = old.Options.OpenScale
		old.Frame.Position = old.BasePosition
		interactable(old.Frame, true)
		setShield(old, false)
		old.State = "CLOSED"
		setBlocked(old, false)
		releaseFocus(old)
	end

	currentName = name

	local frame = popup.Frame
	local scale = popup.Scale
	local opts = popup.Options

	-- A window that is fully closed may have been moved by its own script
	-- (responsive layout): open it where it is now.
	if not frame.Visible then
		popup.BasePosition = frame.Position
	end

	popup.Token += 1
	local token = popup.Token

	setBlocked(popup, true)
	-- A close that was still animating is replaced cleanly: its tweens
	-- check the token and stop, and everything restarts from here.
	frame.Position = popup.BasePosition + UDim2.fromOffset(0, opts.OpenRise or 0)
	frame.Visible = true
	scale.Scale = opts.OpenScale
	interactable(frame, true)
	setShield(popup, true)       -- OPENING: the window owns presses, acts on none
	popup.State = "OPENING"

	setDim(opts.DimTransparency, opts.DimTween)

	local popTween = TweenService:Create(scale, opts.OpenPopTween, {
		Scale = opts.OpenOvershootScale,
	})
	popTween:Play()
	if (opts.OpenRise or 0) ~= 0 then
		TweenService:Create(frame, opts.OpenPopTween, { Position = popup.BasePosition }):Play()
	end

	popTween.Completed:Connect(function()
		if popup.Token ~= token or currentName ~= name then return end
		interactable(frame, true)
		setShield(popup, false)
		popup.State = "OPEN"
		if opts.OpenOvershootScale ~= 1 then
			TweenService:Create(scale, opts.OpenSettleTween, { Scale = 1 }):Play()
		end
	end)
	-- Clicks come back even if the tween is ever cut short.
	task.delay(opts.OpenPopTween.Time + 0.1, function()
		if popup.Token == token and currentName == name then
			interactable(frame, true)
			setShield(popup, false)
			popup.State = "OPEN"
		end
	end)

	bindBack(true)
	focusPopup(popup, name)
	changedEvent:Fire(currentName)

	return true
end

function GuiManager:Close(name)
	name = name or currentName

	-- Closing the modal popup always releases the lock, so a stuck modal can
	-- never leave the game unclickable.
	if name and modalName == name then
		modalName = nil
		refreshBlockerLayer()
	end

	if not name then
		return
	end

	local popup = popups[name]
	if not popup then
		return
	end

	local wasCurrent = currentName == name
	if wasCurrent then
		currentName = nil
		if not popup.CloseSoundPlayed then
			menuSound(popup, "MENU_CLOSE_ID")
		end
	end
	popup.CloseSoundPlayed = nil

	local frame = popup.Frame
	local scale = popup.Scale
	local opts = popup.Options

	popup.Token += 1
	local token = popup.Token

	-- The HUD behind is usable again right away; the popup takes no more clicks.
	setBlocked(popup, false)
	releaseFocus(popup)
	setShield(popup, true)       -- CLOSING: still on screen, so it still owns presses
	popup.State = "CLOSING"
	if currentName == nil then
		bindBack(false)
		-- Only clear the dim when nothing else is open (a switch keeps it).
		setDim(1, opts.DimTween)
	end

	local function finish()
		if popup.Token == token and currentName ~= name then
			frame.Visible = false
			scale.Scale = opts.OpenScale
			frame.Position = popup.BasePosition
			interactable(frame, true)
			setShield(popup, false)
			popup.State = "CLOSED"
		end
	end
	local function shrink()
		if popup.Token ~= token then return end
		local shrinkTween = TweenService:Create(scale, opts.CloseShrinkTween, { Scale = opts.CloseScale })
		shrinkTween.Completed:Connect(finish)
		shrinkTween:Play()
	end
	if opts.CloseBounceScale ~= 1 then
		local bounceTween = TweenService:Create(scale, opts.CloseBounceTween, { Scale = opts.CloseBounceScale })
		bounceTween.Completed:Connect(shrink)
		bounceTween:Play()
	else
		shrink()
	end
	-- Hidden even if a tween is ever cut short.
	task.delay(opts.CloseBounceTween.Time + opts.CloseShrinkTween.Time + 0.15, finish)

	if wasCurrent then
		changedEvent:Fire(currentName)
	end
end

-- For popups with their own closing animation that call Close only at the end:
-- call this when the animation STARTS so the close sound matches what you see.
function GuiManager:BeginClose(name)
	local popup = popups[name]
	if popup and currentName == name and not popup.CloseSoundPlayed then
		popup.CloseSoundPlayed = true
		menuSound(popup, "MENU_CLOSE_ID")
	end
end

function GuiManager:Toggle(name)
	if currentName == name then
		self:Close(name)
	else
		self:Open(name)
	end
end

function GuiManager:DismissCurrent()
	if currentName then
		self:Close(currentName)
	end
end

function GuiManager:GetCurrent()
	return currentName
end

-- The registered frame of a window (for input ownership checks).
function GuiManager:GetFrame(name)
	local popup = name and popups[name]
	return popup and (popup.InputFrame or popup.Frame) or nil
end

-- "CLOSED" | "OPENING" | "OPEN" | "CLOSING"
function GuiManager:GetState(name)
	local popup = name and popups[name]
	return popup and popup.State or "CLOSED"
end

function GuiManager:IsOpen(name)
	if name then
		return currentName == name
	end
	return currentName ~= nil
end

return GuiManager
