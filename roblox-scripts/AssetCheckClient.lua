-- AssetCheckClient (TEMPORARY LocalScript in StarterPlayer > StarterPlayerScripts)
--
-- Reports which ids in ReplicatedStorage > UIAssets actually render.
--
-- Why the last version said "0 ok, 40 not rendering" when the art was fine:
-- it built its grid inside a ScreenGui with Enabled = false. Roblox only
-- fetches an image for a label it is actually drawing, so nothing was ever
-- requested and IsLoaded stayed false for every single id. The checker was
-- wrong, not the artwork.
--
-- So the verdict now comes from a strip of tiny labels that really are on
-- screen: 6x6 pixels each, in a row along the bottom-left corner. They are the
-- test. The big K grid is only there for looking at.
--
-- Press K to show the grid, K again to hide it. Delete this script when you
-- are done with it; it changes nothing in the game.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Development tool: never runs for real players (its probe strip used to sit
-- along the bottom of every player's screen).
if not RunService:IsStudio() then return end
local player = game:GetService("Players").LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local module = ReplicatedStorage:WaitForChild("UIAssets", 20)
if not module then
	warn("[AssetCheck] ReplicatedStorage > UIAssets is missing.")
	return
end

local UIAssets = require(module)

-- ===================== COLLECT =====================
-- Top-level fields and one level of nested tables (CardArt, NavIcons, the
-- preload lists), deduplicated by id.
local entries, seen = {}, {}

local function consider(name, value)
	if type(value) == "string" and value:match("^rbxassetid://%d+$") and not seen[value] then
		seen[value] = true
		table.insert(entries, { name = name, id = value })
	end
end

for name, value in pairs(UIAssets) do
	if type(value) == "table" then
		for key, nested in pairs(value) do
			consider(name .. "." .. tostring(key), nested)
		end
	else
		consider(name, value)
	end
end

table.sort(entries, function(a, b) return a.name < b.name end)

if #entries == 0 then
	warn("[AssetCheck] No image ids found in UIAssets.")
	return
end

-- ===================== THE ACTUAL TEST =====================
-- Small, real, on screen. This is what IsLoaded is read from.
local probeGui = Instance.new("ScreenGui")
probeGui.Name = "AssetCheckProbes"
probeGui.ResetOnSpawn = false
probeGui.IgnoreGuiInset = true
probeGui.DisplayOrder = 1
probeGui.Parent = playerGui

local probeRow = Instance.new("Frame")
probeRow.Name = "Probes"
probeRow.AnchorPoint = Vector2.new(0, 1)
probeRow.Position = UDim2.new(0, 0, 1, 0)
probeRow.Size = UDim2.fromOffset(#entries * 7, 7)
probeRow.BackgroundTransparency = 1
probeRow.Parent = probeGui

local probeLayout = Instance.new("UIListLayout")
probeLayout.FillDirection = Enum.FillDirection.Horizontal
probeLayout.Padding = UDim.new(0, 1)
probeLayout.Parent = probeRow

for _, entry in ipairs(entries) do
	local probe = Instance.new("ImageLabel")
	probe.Name = entry.name
	probe.Size = UDim2.fromOffset(6, 6)
	probe.BackgroundTransparency = 1
	probe.BorderSizePixel = 0
	probe.Active = false
	probe.Image = entry.id
	probe.ScaleType = Enum.ScaleType.Fit
	probe.Parent = probeRow
	entry.probe = probe
end

-- ===================== THE GRID YOU LOOK AT =====================
local sheet = Instance.new("ScreenGui")
sheet.Name = "AssetCheckSheet"
sheet.ResetOnSpawn = false
sheet.IgnoreGuiInset = true
sheet.DisplayOrder = 500
sheet.Enabled = false
sheet.Parent = playerGui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromScale(0.9, 0.9)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(16, 20, 44)
panel.BorderSizePixel = 0
panel.Parent = sheet

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "UIAssets  -  a blank square means that id is not rendering (K to close)"
title.Font = Enum.Font.Gotham
title.TextSize = 17
title.TextColor3 = Color3.new(1, 1, 1)
title.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(8, 34)
scroll.Size = UDim2.new(1, -16, 1, -42)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.ScrollBarThickness = 8
scroll.Parent = panel

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(150, 150)
grid.CellPadding = UDim2.fromOffset(10, 10)
grid.Parent = scroll

for _, entry in ipairs(entries) do
	local cell = Instance.new("Frame")
	cell.Name = entry.name
	cell.BackgroundColor3 = Color3.fromRGB(32, 38, 74)
	cell.BorderSizePixel = 0
	cell.Parent = scroll

	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.Size = UDim2.new(1, -8, 1, -38)
	art.Position = UDim2.fromOffset(4, 4)
	art.Image = entry.id
	art.ScaleType = Enum.ScaleType.Fit
	art.Parent = cell

	local label = Instance.new("TextLabel")
	label.Name = "Caption"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -2)
	label.Size = UDim2.new(1, -6, 0, 32)
	label.BackgroundTransparency = 1
	label.Text = entry.name .. "\n" .. (entry.id:match("%d+") or "")
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextColor3 = Color3.fromRGB(190, 200, 220)
	label.Parent = cell

	entry.caption = label
end

-- ===================== REPORT =====================
task.spawn(function()
	print(("[AssetCheck] Checking %d images. The verdict comes from %d labels that are really on screen."):format(#entries, #entries))

	-- Give them time to arrive; a slow join is not a failure.
	local deadline = os.clock() + 30
	while os.clock() < deadline do
		local waiting = 0
		for _, entry in ipairs(entries) do
			if not entry.probe.IsLoaded then
				waiting += 1
			end
		end
		if waiting == 0 then break end
		task.wait(0.5)
	end

	local failed = {}

	print("[AssetCheck] ---------------- RESULT ----------------")
	for _, entry in ipairs(entries) do
		local ok = entry.probe.IsLoaded
		entry.caption.TextColor3 = if ok then Color3.fromRGB(150, 255, 170) else Color3.fromRGB(255, 140, 140)
		if not ok then
			table.insert(failed, entry)
		end
		print(("[AssetCheck] %s  %-26s %s"):format(if ok then "OK  " else "FAIL", entry.name, entry.id))
	end
	print(("[AssetCheck] %d ok, %d not rendering."):format(#entries - #failed, #failed))
	probeGui:Destroy()   -- the verdict is in: take the strip off the screen

	if #failed == 0 then
		print("[AssetCheck] Everything renders. Press K to look.")
		return
	end

	-- Only the failures get a web lookup, slowly, so the client is not
	-- rate-limited into reporting nonsense.
	print("[AssetCheck] ------------- FAILED DETAIL -------------")
	for index, entry in ipairs(failed) do
		if index > 8 then
			print("[AssetCheck] (stopping here to stay under the request limit)")
			break
		end

		local id = tonumber(entry.id:match("%d+"))
		local info
		local ok = pcall(function()
			info = MarketplaceService:GetProductInfo(id, Enum.InfoType.Asset)
		end)

		if ok and info then
			local kind = if info.AssetTypeId == 1 then "Image"
				elseif info.AssetTypeId == 13 then "DECAL - needs resolving to its image id"
				else "AssetTypeId " .. tostring(info.AssetTypeId)
			print(("[AssetCheck] %-26s %s  type=%s  name=%q"):format(
				entry.name, entry.id, kind, tostring(info.Name)))
		else
			print(("[AssetCheck] %-26s %s  lookup rate-limited; try again in a minute"):format(
				entry.name, entry.id))
		end

		task.wait(2)
	end

	print("[AssetCheck] A DECAL can never render in an ImageLabel: run ResolveDecals in the command bar.")
	print("[AssetCheck] An Image that will not render is waiting on moderation.")
end)

if RunService:IsStudio() then
	print("[AssetCheck] Press Ctrl+P to show every image on screen.")

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		-- Ctrl+P: K is the base-attack "25% HP" debug key, which kept
		-- toggling this sheet on by accident.
		if input.KeyCode == Enum.KeyCode.P and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			sheet.Enabled = not sheet.Enabled
		end
	end)
end
