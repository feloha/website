-- LegacyGuiCleanup (Script)
-- Put in: ServerScriptService > LegacyGuiCleanup
--
-- Why old GUIs flash for a split second:
-- Every current screen (MainHUD, LeaderboardsUI, StoreUI, ...) is built by
-- its own client script. Old copies of them saved in StarterGui are still
-- copied into each player's PlayerGui when they join or respawn, so they
-- show until the new script finds and deletes them - that's the flash.
--
-- This removes those old copies from StarterGui as soon as the server
-- starts, before anyone joins, so they are never copied in at all. Any that
-- were already copied into a PlayerGui are removed too. Only server-made
-- copies can be seen here; the GUIs the client scripts build are local to
-- each player, so they are never touched.
--
-- It also prints every other ScreenGui left in StarterGui, so you can spot
-- old ones with different names. Add their names to EXTRA_OLD_GUIS (or just
-- delete them from StarterGui in Studio - that's the permanent fix).

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

-- Every screen the client scripts build for themselves.
local SCRIPT_BUILT = {
	"MainHUD", "LeaderboardsUI", "StoreUI", "InventoryUI", "CosmicIndexHUD",
	"RebirthUI", "RebirthCeremony", "SettingsHUD", "PlaytimeAwardsUI",
	"LimitedOfferUI", "WelcomeBackHUD", "TutorialHUD", "TutorialPointerHUD",
	"BaseAttackHUD", "BaseAttackTags", "BlackHoleActionUI", "BlackHoleCooldowns",
	"BlackHoleHealthBars", "BlackHoleLabels", "ThievingTimeHUD", "ComboMeter",
	"StardustGainUI", "ToggleAttackTargeting",
}
-- Old GUIs under other names (see the Output list). Example: "OldLeaderboard".
local EXTRA_OLD_GUIS = {}

local remove = {}
for _, name in ipairs(SCRIPT_BUILT) do remove[name] = true end
for _, name in ipairs(EXTRA_OLD_GUIS) do remove[name] = true end

local function isOld(object)
	return object:IsA("LayerCollector") and remove[object.Name] == true
end

-- 1) Out of StarterGui, so nothing is copied in any more.
local kept = {}
for _, child in ipairs(StarterGui:GetChildren()) do
	if isOld(child) then
		child:Destroy()
	elseif child:IsA("LayerCollector") then
		table.insert(kept, child.Name)
	end
end
if #kept > 0 then
	print("[LegacyGuiCleanup] Still in StarterGui (delete any that are old): " .. table.concat(kept, ", "))
end

-- 2) Any copy that reached a PlayerGui before this ran (e.g. Play Solo).
local function sweep(playerGui)
	for _, child in ipairs(playerGui:GetChildren()) do
		if isOld(child) then child:Destroy() end
	end
	playerGui.ChildAdded:Connect(function(child)
		if isOld(child) then task.defer(child.Destroy, child) end
	end)
end

local function onPlayer(player)
	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 30)
	if playerGui then sweep(playerGui) end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, player) end
