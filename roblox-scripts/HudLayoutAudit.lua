-- HudLayoutAudit (LocalScript)
-- Put in: StarterPlayer > StarterPlayerScripts > HudLayoutAudit
--
-- DEVELOPMENT ONLY: does nothing outside Roblox Studio.
--
-- Checks the normal gameplay HUD zones and prints problems to Output:
--   OVERLAP      two HUD zones intersect
--   COREGUI      a zone sits under / right against Roblox's menu, chat, mic
--   OUTSIDE      a zone leaves the device safe area or touches a screen edge
--   GAMEPLAY     a zone intrudes into the clear centre of the screen
-- Ctrl+H shows every real button hitbox (overlaps in red; see the bottom).
-- It re-runs by itself when the screen size changes (switch devices in the
-- Device Emulator and watch Output), and Ctrl+L runs it on demand.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UiResponsive = require(ReplicatedStorage:WaitForChild("UiResponsive"))

local EDGE = 4            -- an interactive zone closer than this to a safe edge is "touching"
local CORE_GAP = 12       -- breathing room required beside / below Roblox's buttons
local CENTRE = 0.34       -- the clear gameplay rectangle: middle 34% x 34% of the screen

-- { label, ScreenGui name, object name }
local ZONES = {
	{ "TopActions", "MainHUD", "TopActionButtons" },
	{ "LeftActionGrid", "MainHUD", "SideMenu" },
	{ "Stardust", "MainHUD", "StardustDisplay" },
	{ "Gems", "MainHUD", "GemsDisplay" },
	{ "Playtime", "MainHUD", "PlaytimeSlot" },
	{ "Settings", "SettingsHUD", "SettingsButtonHolder" },
	{ "StatusColumn", "HudStack", "Column" },
	{ "TutorialButton", "TutorialButtonHUD", "TutorialButton" },
}
-- Pairs that are meant to touch/overlap (none for the normal HUD).
local ALLOWED = {}

local function rectOf(object)
	if not (object and object:IsA("GuiObject") and object.Visible) then return nil end
	local size = object.AbsoluteSize
	if size.X < 2 or size.Y < 2 then return nil end
	local at = UiResponsive.ToScreen(object.AbsolutePosition)
	return { x0 = at.X, y0 = at.Y, x1 = at.X + size.X, y1 = at.Y + size.Y }
end

local function shown(object)
	local node = object
	while node do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("LayerCollector") then return node.Enabled end
		node = node.Parent
	end
	return false
end

local function intersects(a, b, pad)
	pad = pad or 0
	return a.x0 < b.x1 + pad and b.x0 < a.x1 + pad and a.y0 < b.y1 + pad and b.y0 < a.y1 + pad
end

local function fmt(r)
	return ("(%d,%d)-(%d,%d)"):format(r.x0, r.y0, r.x1, r.y1)
end

local function audit(reason)
	local screen = UiResponsive.Screen()
	local safeAt, safeSize = UiResponsive.SafeRect()
	local safe = { x0 = safeAt.X, y0 = safeAt.Y, x1 = safeAt.X + safeSize.X, y1 = safeAt.Y + safeSize.Y }
	local freeLeft = 0
	pcall(function() freeLeft = GuiService.TopbarInset.Min.X end)
	local core = { x0 = 0, y0 = 0, x1 = math.max(freeLeft, 0), y1 = UiResponsive.TopInset() }
	local centre = {
		x0 = screen.X * (0.5 - CENTRE / 2), x1 = screen.X * (0.5 + CENTRE / 2),
		y0 = screen.Y * (0.5 - CENTRE / 2), y1 = screen.Y * (0.5 + CENTRE / 2),
	}

	local rects, problems = {}, {}
	for _, zone in ipairs(ZONES) do
		local gui = playerGui:FindFirstChild(zone[2])
		local object = gui and gui:FindFirstChild(zone[3], true)
		local rect = object and shown(object) and rectOf(object)
		if rect then table.insert(rects, { name = zone[1], rect = rect }) end
	end

	for i, a in ipairs(rects) do
		local r = a.rect
		if r.x0 < safe.x0 + EDGE or r.y0 < safe.y0 + EDGE or r.x1 > safe.x1 - EDGE or r.y1 > safe.y1 - EDGE then
			table.insert(problems, ("OUTSIDE   %s %s  (safe %s)"):format(a.name, fmt(r), fmt(safe)))
		end
		if core.x1 > 0 and intersects(r, core, CORE_GAP) then
			table.insert(problems, ("COREGUI   %s %s  (Roblox buttons %s)"):format(a.name, fmt(r), fmt(core)))
		end
		if intersects(r, centre) then
			table.insert(problems, ("GAMEPLAY  %s %s  (clear centre %s)"):format(a.name, fmt(r), fmt(centre)))
		end
		for j = i + 1, #rects do
			local b = rects[j]
			local key = a.name .. "|" .. b.name
			if not ALLOWED[key] and intersects(r, b.rect) then
				table.insert(problems, ("OVERLAP   %s %s  x  %s %s"):format(a.name, fmt(r), b.name, fmt(b.rect)))
			end
		end
	end

	print(("[HudLayoutAudit] %dx%d (%s, %s) - %d zones checked, %d problem(s)")
		:format(screen.X, screen.Y, UiResponsive.Layout(), reason, #rects, #problems))
	for _, line in ipairs(problems) do
		warn("[HudLayoutAudit] " .. line)
	end
end

local pending = false
local function schedule(reason)
	if pending then return end
	pending = true
	task.delay(0.6, function()   -- let every HUD script finish its own layout first
		pending = false
		audit(reason)
	end)
end

UiResponsive.Changed:Connect(function() schedule("screen changed") end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.L and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		audit("Ctrl+L")
	end
end)
task.delay(3, function() audit("startup") end)

-- ===================== TAP TRACER =====================
-- Finds taps that open the wrong window. Every tap prints the buttons under
-- it (topmost first), and every button that actually fires prints its name:
--   [TapTrace] tap (812,140) -> MainHUD.PlaytimeSlot.Playtime Awards | ...
--   [TapTrace] ACTIVATED Players.<you>.PlayerGui.MainHUD.SideMenu.RebirthSlot.Rebirth
-- If the ACTIVATED button is not the one you tapped, the first name on the
-- tap line is what is sitting on top of it.
local traced = {}
local function trace(object)
	if traced[object] or not object:IsA("GuiButton") then return end
	traced[object] = true
	object.Activated:Connect(function()
		print("[TapTrace] ACTIVATED " .. object:GetFullName())
	end)
end
for _, object in ipairs(playerGui:GetDescendants()) do trace(object) end
playerGui.DescendantAdded:Connect(trace)

UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local at = input.Position
	local names = {}
	for _, object in ipairs(playerGui:GetGuiObjectsAtPosition(at.X, at.Y)) do
		if object:IsA("GuiButton") or object.Active then
			table.insert(names, (object:GetFullName():gsub("^Players%.[^%.]+%.PlayerGui%.", "")))
			if #names >= 4 then break end
		end
	end
	print(("[TapTrace] tap (%d,%d) -> %s"):format(at.X, at.Y, if #names > 0 then table.concat(names, " | ") else "nothing clickable"))
end)

-- ===================== HITBOX VISUALISER =====================
-- Ctrl+H: draws the REAL clickable rectangle (AbsolutePosition/AbsoluteSize)
-- of every button that can take a tap right now, labelled with its name (and
-- its routed action). Two hitboxes that overlap are drawn red and printed:
--   HITBOX OVERLAP: MainHUD.PlaytimeSlot.Playtime Awards <-> LimitedOfferUI...
-- A button's own touch area next to its face (same parent) is not counted.
do
	local Router do
		local module = ReplicatedStorage:FindFirstChild("UIInputRouter")
		local ok, result = pcall(function() return module and require(module) end)
		Router = if ok and type(result) == "table" then result else nil
	end

	local overlay = Instance.new("ScreenGui")
	overlay.Name = "HitboxDebug"
	overlay.ResetOnSpawn = false
	overlay.IgnoreGuiInset = true
	pcall(function() overlay.ScreenInsets = Enum.ScreenInsets.None end)
	overlay.DisplayOrder = 1001
	overlay.Enabled = false
	overlay.Parent = playerGui

	local function takesInput(button)
		if not button.Active or button:GetAttribute("InputCatcher") then return false end
		local node = button
		while node do
			if node:IsA("GuiObject") then
				if not node.Visible then return false end
				local ok, value = pcall(function() return node.Interactable end)
				if ok and value == false then return false end
			end
			if node:IsA("LayerCollector") then
				return node.Enabled and node ~= overlay and node.Name ~= "UILayoutDebug"
			end
			node = node.Parent
		end
		return false
	end

	local warned = {}
	local function draw()
		overlay:ClearAllChildren()
		local actions = {}
		if Router and Router.Bindings then
			for _, item in ipairs(Router.Bindings()) do actions[item.button] = item.action end
		end
		local list = {}
		for _, object in ipairs(playerGui:GetDescendants()) do
			if object:IsA("GuiButton") and object.AbsoluteSize.X > 2 and object.AbsoluteSize.Y > 2 and takesInput(object) then
				table.insert(list, { button = object, rect = rectOf(object) })
			end
		end
		local bad = {}
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i], list[j]
				local related = a.button:IsDescendantOf(b.button) or b.button:IsDescendantOf(a.button)
					or a.button.Parent == b.button.Parent
				if a.rect and b.rect and not related and intersects(a.rect, b.rect) then
					bad[a.button], bad[b.button] = true, true
					local key = a.button:GetFullName() .. "|" .. b.button:GetFullName()
					if not warned[key] then
						warned[key] = true
						local short = function(o) return (o:GetFullName():gsub("^Players%.[^%.]+%.PlayerGui%.", "")) end
						warn(("HITBOX OVERLAP: %s <-> %s"):format(short(a.button), short(b.button)))
					end
				end
			end
		end
		for _, item in ipairs(list) do
			local r = item.rect
			if r then
				local f = Instance.new("Frame")
				f.Active = false
				f.BackgroundColor3 = if bad[item.button] then Color3.fromRGB(255, 60, 60) else Color3.fromRGB(60, 200, 255)
				f.BackgroundTransparency = 0.8
				f.Position = UDim2.fromOffset(r.x0, r.y0)
				f.Size = UDim2.fromOffset(r.x1 - r.x0, r.y1 - r.y0)
				f.Parent = overlay
				local s = Instance.new("UIStroke")
				s.Color = f.BackgroundColor3
				s.Thickness = 1
				s.Parent = f
				local t = Instance.new("TextLabel")
				t.BackgroundTransparency = 0.4
				t.BackgroundColor3 = Color3.new(0, 0, 0)
				t.TextColor3 = Color3.new(1, 1, 1)
				t.Font = Enum.Font.GothamBold
				t.TextSize = 10
				t.AutomaticSize = Enum.AutomaticSize.XY
				t.Size = UDim2.new()
				t.Text = " " .. string.upper(actions[item.button] or item.button.Name) .. " "
				t.Parent = f
			end
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.H and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			overlay.Enabled = not overlay.Enabled
			print("[HudLayoutAudit] hitboxes " .. (if overlay.Enabled then "on (red = overlapping)" else "off"))
			if overlay.Enabled then
				task.spawn(function()
					while overlay.Enabled do
						draw()
						task.wait(1)
					end
					overlay:ClearAllChildren()
				end)
			end
		end
	end)
end
