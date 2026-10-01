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
	{ "TutorialButton", "TutorialHUD", "TutorialButton" },
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
