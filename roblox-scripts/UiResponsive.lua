-- UiResponsive (ModuleScript in ReplicatedStorage)  -- NEW
-- Shared screen, safe-area, sizing and input helpers for every client UI.
-- Client only. Presentation only.
--
-- Coordinates: everything here is in "full screen" space, the same space as a
-- ScreenGui with IgnoreGuiInset = true (all of this game's HUDs). Positions
-- read from AbsolutePosition are converted with ToScreen, because Roblox
-- reports AbsolutePosition below the top bar.
--
--   Layout()        "compact" (phones), "medium" (tablets, small windows), "wide"
--   SafeRect()      device safe area (notches, rounded corners)
--   TopInset()      height of Roblox's top bar
--   Boost()         1 up to 1080p, then grows with the screen (1440p, 4K,
--                   ultrawide), so UI designed at 1080p keeps its share of
--                   the screen instead of shrinking on big displays
--   ModalArea()     the room a centred window may use: below Roblox's top bar,
--                   inside the device safe area; on phones ~92% x 90% of it
--   UseModalInsets(gui)  make a modal ScreenGui use that same area
--   FitScale()      scale a fixed panel to fit the safe area
--   FitPanel()      scale + size for a panel whose content scrolls: keeps text
--                   readable on phones by shrinking the panel before the text
--   InputMode()     "Touch" | "Gamepad" | "Keyboard" (follows the last input)
--   FirstSelectable(root)  a sensible first control for gamepad selection
--   Changed         fires (deferred) when the screen, safe area or input changes

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UiResponsive = {}

local changed = Instance.new("BindableEvent")
UiResponsive.Changed = changed.Event

local pending = false
local function fireChanged(reason)
	if pending then return end
	pending = true
	task.defer(function()
		pending = false
		changed:Fire(reason)
	end)
end

-- ===================== PROBES =====================
-- Invisible full-screen frames under different inset rules. Their absolute
-- rectangles tell us the real screen, the device safe area and the top bar.
local function probe(name, insets)
	local old = playerGui:FindFirstChild(name)
	if old then old:Destroy() end
	local screen = Instance.new("ScreenGui")
	screen.Name = name
	screen.ResetOnSpawn = false
	screen.DisplayOrder = -100
	screen.IgnoreGuiInset = true
	pcall(function() screen.ScreenInsets = insets end)
	local frame = Instance.new("Frame")
	frame.Name = "Probe"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Active = false
	frame.Parent = screen
	screen.Parent = playerGui
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() fireChanged("screen") end)
	frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function() fireChanged("screen") end)
	return frame
end

local fullProbe = probe("UiProbeFull", Enum.ScreenInsets.None)
local safeProbe = probe("UiProbeSafe", Enum.ScreenInsets.DeviceSafeInsets)
local coreProbe = probe("UiProbeCore", Enum.ScreenInsets.CoreUISafeInsets)

local function cameraSize()
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

-- Full screen size.
function UiResponsive.Screen()
	local size = fullProbe.AbsoluteSize
	if size.X < 2 or size.Y < 2 then return cameraSize() end
	return size
end

-- Converts an AbsolutePosition into full-screen coordinates.
function UiResponsive.ToScreen(absolutePosition)
	return absolutePosition - fullProbe.AbsolutePosition
end

-- Device safe area (position, size) in full-screen coordinates.
function UiResponsive.SafeRect()
	local size = safeProbe.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		return Vector2.zero, UiResponsive.Screen()
	end
	return UiResponsive.ToScreen(safeProbe.AbsolutePosition), size
end

-- Height of Roblox's top bar (0 if it isn't shown).
function UiResponsive.TopInset()
	local size = coreProbe.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		local topLeft = GuiService:GetGuiInset()
		return topLeft.Y
	end
	return math.max(UiResponsive.ToScreen(coreProbe.AbsolutePosition).Y, 0)
end

-- ===================== SPACING =====================
-- The one spacing scale for HUD zones (design px before any UIScale):
--   XS tiny internal, S icon/text, M siblings, L sections, XL regions.
UiResponsive.Space = { XS = 4, S = 8, M = 12, L = 18, XL = 28 }

-- ===================== LAYOUT =====================
function UiResponsive.Layout()
	local _, size = UiResponsive.SafeRect()
	local short = math.min(size.X, size.Y)
	if short < 520 then return "compact" end
	if short < 820 or size.X < 1100 then return "medium" end
	return "wide"
end

function UiResponsive.IsPortrait()
	local _, size = UiResponsive.SafeRect()
	return size.Y > size.X
end

-- Large-screen factor: exactly 1 at 1920x1080 and below, then follows the
-- smaller of width/height growth (so ultrawide is sized by its height, not
-- stretched by its width). Capped so huge monitors stay sensible.
function UiResponsive.Boost()
	local size = UiResponsive.Screen()
	return math.clamp(math.min(size.X / 1920, size.Y / 1080), 1, 1.6)
end

-- Width, height a centred window may use: the area below Roblox's top bar
-- and inside the device safe area (CoreUISafeInsets). Modal ScreenGuis use
-- the same area (UiResponsive.UseModalInsets), so a window centred in its
-- ScreenGui is centred in this space and never sits under the menu / chat /
-- mic buttons. On phones it also keeps a margin of game visible around it.
-- options: shareW / shareH override the phone share (0.92 x 0.9).
function UiResponsive.ModalArea(options)
	options = options or {}
	local size = coreProbe.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		local _, safe = UiResponsive.SafeRect()
		size = safe - Vector2.new(0, UiResponsive.TopInset())
	end
	local width, height = size.X, size.Y
	local compact = UiResponsive.Layout() == "compact"
	local shareW = options.shareW or (if compact then 0.92 else 1)
	local shareH = options.shareH or (if compact then 0.9 else 1)
	return width * shareW, height * shareH
end

-- Puts a modal ScreenGui in the area below the top bar (see ModalArea).
function UiResponsive.UseModalInsets(screenGui)
	pcall(function() screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
end

-- Scale for a fixed-size panel so it fits the modal area.
-- options: margin (12), min (0.3), max (1)
function UiResponsive.FitScale(designW, designH, options)
	options = options or {}
	local areaW, areaH = UiResponsive.ModalArea(options)
	local margin = options.margin or 12
	local scale = math.min(
		(areaW - margin * 2) / designW,
		(areaH - margin * 2) / designH,
		(options.max or 1) * UiResponsive.Boost())
	return math.max(scale, options.min or 0.3)
end

-- Scale and size for a panel whose content scrolls or wraps.
-- On small screens the panel gets narrower/shorter first (down to minWidth /
-- minHeight), so text stays at a readable scale instead of shrinking with it.
-- options: margin (12), minWidth, minHeight, max (1), readable (per layout)
-- returns scale, width, height (width/height in design units)
function UiResponsive.FitPanel(designW, designH, options)
	options = options or {}
	local areaW, areaH = UiResponsive.ModalArea(options)
	local margin = options.margin or 12
	local availW = math.max(areaW - margin * 2, 60)
	local availH = math.max(areaH - margin * 2, 60)
	local minW = math.min(options.minWidth or designW, designW)
	local minH = math.min(options.minHeight or designH, designH)

	local layout = UiResponsive.Layout()
	local readable = options.readable
		or (if layout == "compact" then 0.7 elseif layout == "medium" then 0.85 else 1)

	local scale = math.min((options.max or 1) * UiResponsive.Boost(), availW / designW, availH / designH)
	if scale >= readable then
		return scale, designW, designH
	end

	scale = math.min(readable, availW / minW, availH / minH)
	local width = math.clamp(availW / scale, minW, designW)
	local height = math.clamp(availH / scale, minH, designH)
	return scale, math.floor(width), math.floor(height)
end

-- Size of wrapped text, in the same (unscaled) units as TextSize.
function UiResponsive.MeasureText(text, textSize, font, width)
	return TextService:GetTextSize(text or "", textSize, font, Vector2.new(width or 100000, 100000))
end

-- ===================== SCROLLING =====================
-- Makes a list easy to scroll with a thumb: one direction only (a swipe never
-- wobbles sideways), elastic ends, and a bar thick enough to see on touch.
function UiResponsive.TouchScroll(frame, direction)
	if not (frame and frame:IsA("ScrollingFrame")) then return end
	frame.ScrollingDirection = direction or Enum.ScrollingDirection.Y
	frame.ElasticBehavior = Enum.ElasticBehavior.Always
	frame.ScrollingEnabled = true
	local function refresh()
		if UiResponsive.InputMode() == "Touch" then
			frame.ScrollBarThickness = math.max(frame.ScrollBarThickness, 8)
			frame.ScrollBarImageTransparency = math.min(frame.ScrollBarImageTransparency, 0.35)
		end
	end
	refresh()
	frame:GetPropertyChangedSignal("ScrollBarThickness"):Connect(function()
		if UiResponsive.InputMode() == "Touch" and frame.ScrollBarThickness < 8 then
			frame.ScrollBarThickness = 8
		end
	end)
	UiResponsive.Changed:Connect(refresh)
end

-- ===================== INPUT =====================
local inputMode

local function modeFor(inputType)
	if inputType == Enum.UserInputType.Touch then return "Touch" end
	if inputType.Name:sub(1, 7) == "Gamepad" then return "Gamepad" end
	if inputType == Enum.UserInputType.Keyboard or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3 or inputType == Enum.UserInputType.MouseWheel then
		return "Keyboard"
	end
	return nil
end

do
	local initial = modeFor(UserInputService:GetLastInputType())
	if not initial then
		if GuiService:IsTenFootInterface() then
			initial = "Gamepad"
		elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			initial = "Touch"
		else
			initial = "Keyboard"
		end
	end
	inputMode = initial
end

UserInputService.LastInputTypeChanged:Connect(function(inputType)
	local mode = modeFor(inputType)
	if mode and mode ~= inputMode then
		inputMode = mode
		fireChanged("input")
	end
end)

function UiResponsive.InputMode()
	return inputMode
end

function UiResponsive.IsGamepad()
	return inputMode == "Gamepad"
end

function UiResponsive.IsTouch()
	return inputMode == "Touch"
end

-- ===================== SELECTION =====================
local function shownWithin(object, root)
	local node = object
	while node and node ~= root do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("LayerCollector") then return node.Enabled end
		node = node.Parent
	end
	return root == nil or (root:IsA("GuiObject") and root.Visible) or root:IsA("LayerCollector")
end

-- The top-left-most visible button under root, preferring anything that isn't
-- a close button. Used to give gamepads a starting point when a menu opens.
function UiResponsive.FirstSelectable(root)
	if not root then return nil end
	local best, bestKey, fallback, fallbackKey
	for _, object in ipairs(root:GetDescendants()) do
		if (object:IsA("GuiButton") or object:IsA("TextBox")) and object.Selectable
			and object.AbsoluteSize.X > 4 and object.AbsoluteSize.Y > 4 and shownWithin(object, root) then
			local position = object.AbsolutePosition
			local key = math.floor(position.Y / 24) * 100000 + position.X
			if object.Name:lower():find("close") then
				if not fallbackKey or key < fallbackKey then fallback, fallbackKey = object, key end
			elseif not bestKey or key < bestKey then
				best, bestKey = object, key
			end
		end
	end
	return best or fallback
end

-- Selects the first control under root when the player is using a gamepad.
function UiResponsive.FocusFirst(root)
	if inputMode ~= "Gamepad" then return end
	local target = UiResponsive.FirstSelectable(root)
	if target then
		GuiService.SelectedObject = target
	end
end

-- Clears gamepad selection if it is inside root.
function UiResponsive.ReleaseFocus(root)
	local selected = GuiService.SelectedObject
	if selected and root and selected:IsDescendantOf(root) then
		GuiService.SelectedObject = nil
	end
end

return UiResponsive
