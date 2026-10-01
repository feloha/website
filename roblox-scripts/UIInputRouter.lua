-- UIInputRouter (ModuleScript in ReplicatedStorage)  -- NEW
-- One pathway from a button press to an action, for every HUD / window button.
-- Client only: require it from LocalScripts.
--
--   local Router = require(ReplicatedStorage.UIInputRouter)
--   Router.Bind(button, "Open PlaytimeAwards", function() ... end, { Kind = "Window" })
--
-- What it guarantees:
--   ONE GESTURE = ONE ACTION. Every press (touch, click, gamepad A) starts a
--     gesture. The first bound action that fires during a gesture owns it;
--     any other bound button reached by the same gesture is ignored.
--   NO CLICK-THROUGH. While a window is open, a press that started INSIDE
--     that window can only act on buttons inside it - never on a HUD button
--     that happens to sit behind the window.
--   SHORT TRANSITION LOCK. A "Window" action locks other "Window" actions for
--     TRANSITION seconds (about one open/close animation), so a quick double
--     tap cannot open one window and then another.
--   ONE CONNECTION PER BUTTON. Binding a button twice disconnects the old
--     connection and warns "Duplicate UI action registration".
--
-- Options:
--   Kind = "Window"   opens/closes a major window (takes part in the lock)
--   AllowThroughModal = true   may act even from inside another window's area
--
-- Studio only: every routed press prints a [UI INPUT] line (button, action,
-- position, rect, input type, time, current window), and refused presses say
-- why, so one tap firing two actions is visible immediately.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Router = {}

local TRANSITION = 0.25         -- seconds; GuiManager's open/close is ~0.23
local STUDIO = RunService:IsStudio()

local GuiManager do
	local module = ReplicatedStorage:FindFirstChild("GuiManager")
	local ok, result = pcall(function() return module and require(module) end)
	GuiManager = if ok and type(result) == "table" then result else nil
end
local UiResponsive do
	local module = ReplicatedStorage:FindFirstChild("UiResponsive")
	local ok, result = pcall(function() return module and require(module) end)
	UiResponsive = if ok and type(result) == "table" then result else nil
end

-- ===================== GESTURES =====================
local gesture = 0               -- id of the newest press
local gestureAt = nil           -- where it started (screen px)
local gestureInput = "None"
local gestureWindow = nil       -- the window the press started inside, if any
local ownedGesture = -1         -- the gesture that already produced an action
local lockedUntil = 0
local gestureTime = 0

local PRESS_TYPES = {
	[Enum.UserInputType.Touch] = true,
	[Enum.UserInputType.MouseButton1] = true,
}

local function toScreen(at)
	if UiResponsive then return UiResponsive.ToScreen(at) end
	return at
end

local function currentWindow()
	if not GuiManager then return nil, nil end
	local ok, name = pcall(GuiManager.GetCurrent, GuiManager)
	if not ok or not name then return nil, nil end
	local frame = Router._windowFrames[name]
	if not frame and GuiManager.GetFrame then frame = GuiManager:GetFrame(name) end
	return name, frame
end
Router._windowFrames = {}       -- [window name] = its frame (filled by Router.Window)

-- Registers a window's frame so presses inside it are known to belong to it.
function Router.Window(name, frame)
	Router._windowFrames[name] = frame
end

local function insideFrame(frame, point)
	if not (frame and frame.Parent and frame.Visible and point) then return false end
	local at = toScreen(frame.AbsolutePosition)
	local size = frame.AbsoluteSize
	return point.X >= at.X and point.Y >= at.Y and point.X <= at.X + size.X and point.Y <= at.Y + size.Y
end

UserInputService.InputBegan:Connect(function(input)
	local isPress = PRESS_TYPES[input.UserInputType] or input.KeyCode == Enum.KeyCode.ButtonA
	if not isPress then return end
	gesture += 1
	gestureTime = os.clock()
	gestureInput = if input.KeyCode == Enum.KeyCode.ButtonA then "Gamepad" else input.UserInputType.Name
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- InputObject positions are below the top bar; make them screen px.
		gestureAt = toScreen(Vector2.new(input.Position.X, input.Position.Y))
	else
		gestureAt = nil
	end
	local name, frame = currentWindow()
	gestureWindow = if name and insideFrame(frame, gestureAt) then name else nil
end)

-- ===================== LOGGING =====================
local function rectText(button)
	local at, size = toScreen(button.AbsolutePosition), button.AbsoluteSize
	return ("(%d,%d %dx%d)"):format(at.X, at.Y, size.X, size.Y)
end

local function log(kind, button, action, reason)
	if not STUDIO then return end
	local where = if gestureAt then ("(%d,%d)"):format(gestureAt.X, gestureAt.Y) else "-"
	local window = currentWindow() or "none"
	local line = ("[UI INPUT] %s  Button: %s  Action: %s  Position: %s  Rect: %s  Input: %s  t=%.2f  CurrentModal: %s")
		:format(kind, button.Name, action, where, rectText(button), gestureInput, os.clock(), window)
	if reason then line ..= "  (" .. reason .. ")" end
	if kind == "IGNORED" then warn(line) else print(line) end
end

-- ===================== BINDING =====================
local bindings = {}             -- [button] = { connection, action }

local function allowed(button, opts)
	if gesture == ownedGesture and gesture > 0 and os.clock() - gestureTime < 1.5 then
		return false, "this tap already ran an action"
	end
	if opts.Kind == "Window" and os.clock() < lockedUntil then
		return false, "window transition in progress"
	end
	if gestureWindow and not opts.AllowThroughModal then
		local _, frame = currentWindow()
		if frame and not button:IsDescendantOf(frame) then
			return false, "press started inside the " .. gestureWindow .. " window"
		end
	end
	return true
end

function Router.Bind(button, action, handler, opts)
	if not (button and button:IsA("GuiButton")) then return nil end
	opts = opts or {}
	local old = bindings[button]
	if old then
		warn(("Duplicate UI action registration: %s (%s) - the old connection was replaced")
			:format(button:GetFullName(), action))
		old.connection:Disconnect()
	end
	local record = { action = action }
	record.connection = button.Activated:Connect(function(...)
		local ok, reason = allowed(button, opts)
		if not ok then
			log("IGNORED", button, action, reason)
			return
		end
		ownedGesture = gesture
		if opts.Kind == "Window" then lockedUntil = os.clock() + TRANSITION end
		log("ACTIVATED", button, action)
		handler(...)
	end)
	bindings[button] = record
	button.Destroying:Connect(function()
		if bindings[button] == record then
			record.connection:Disconnect()
			bindings[button] = nil
		end
	end)
	return record.connection
end

-- Drop-in for button.Activated: Router.Signal(button, "Open Store"):Connect(fn)
function Router.Signal(button, action, opts)
	return {
		Connect = function(_, handler)
			return Router.Bind(button, action, handler, opts or { Kind = "Window" })
		end,
	}
end

-- Every routed button, for the Studio hitbox visualiser.
function Router.Bindings()
	local list = {}
	for button, record in pairs(bindings) do
		table.insert(list, { button = button, action = record.action })
	end
	return list
end

-- Lets scripts mark an action that did not come through a button (hotkeys).
function Router.Claim()
	ownedGesture = gesture
end

return Router
