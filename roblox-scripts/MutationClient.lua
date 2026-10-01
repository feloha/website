-- MutationClient (LocalScript in StarterPlayerScripts)
-- Presentation for black-hole merges and mutations. The server decides and
-- saves every result before any of this plays; nothing here can change it.
--
--   1. World merge (everyone nearby, about 0.7 s): both black holes react,
--      swoop together along short curves, their energy converges into one
--      bright point, and the result pops into place with an income popup.
--   2. Confirmation (owner): merging a mutated black hole asks first.
--   3. Reveal (owner, mutations only, about 7-9 s): the screen goes dark, a
--      star in the mutation's colour builds, the screen cracks and shatters,
--      a reel of mutation cards spins and settles on the result the server
--      already picked, then the mutated black hole appears with its name and
--      real odds and bonuses. The finished result stays on screen until
--      CONTINUE (tap anywhere to hide the buttons for a screenshot or clip).
--      RETURN TO GAME closes it at any time for free (a short message says
--      what landed on your base). Jumping straight to the result (REVEAL NOW)
--      needs the Instant Reveal game pass (MutationConfig.InstantReveal).
--
-- The reel is presentation only: filler cards are random and cosmetic, card
-- counts say nothing about odds, and it always lands on the committed result.
-- No camera, character or Lighting changes: the reveal is a full-screen
-- overlay, so the HUD underneath is left exactly as it was.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SizeVariants = require(ReplicatedStorage:WaitForChild("SizeVariantConfig"))
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Debris = game:GetService("Debris")

local MutationConfig = require(ReplicatedStorage:WaitForChild("MutationConfig"))
local TierConfig = require(ReplicatedStorage:WaitForChild("BlackHoleTierConfig"))

local function optional(name)
	local module = ReplicatedStorage:FindFirstChild(name)
	local ok, result = pcall(function() return module and require(module) end)
	return if ok and type(result) == "table" then result else nil
end

local Cosmetics = optional("BlackHoleCosmetics")
local Settings = optional("ClientSettings")
local UiResponsive = optional("UiResponsive")
local Sounds = optional("GameSounds")
local Format = optional("NumberFormatter")
local Coordinator = optional("PresentationCoordinator")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("BlackHoleRemotes")
local mergeFusion = remotes:WaitForChild("MergeFusion")
local mutationResult = remotes:WaitForChild("MutationResult")
local mergeConfirmPrompt = remotes:WaitForChild("MergeConfirmPrompt")
local confirmMerge = remotes:WaitForChild("ConfirmMerge")

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local OUTLINE = Color3.fromRGB(14, 10, 34)
local DEEP = Color3.fromRGB(6, 6, 18)
local GOLD = Color3.fromRGB(255, 214, 80)
local GREEN = Color3.fromRGB(80, 226, 110)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local REVEAL = MutationConfig.Reveal
local RARITY_COLORS = MutationConfig.RarityColors or {
	Common = Color3.fromRGB(110, 190, 255), Mid = Color3.fromRGB(196, 120, 255), Rare = Color3.fromRGB(255, 196, 64),
}
local RARITY_NAMES = MutationConfig.RarityNames or { Common = "COMMON", Mid = "RARE", Rare = "LEGENDARY" }
local ACCENT_SOUND = { Common = "COMMON_REVEAL_ID", Mid = "RARE_REVEAL_ID", Rare = "LEGENDARY_REVEAL_ID" }

if not Sounds then
	warn("[MutationClient] ReplicatedStorage.GameSounds is missing: merges and reveals will be silent.")
end

local function reduceMotion()
	return Settings ~= nil and Settings.Get ~= nil and Settings.Get("ReduceMotion") == true
end

local function quality()
	local value = Settings and Settings.Get and Settings.Get("Quality")
	return if value == "LOW" or value == "MODERATE" or value == "HIGH" then value else "MODERATE"
end

local function tierColor(tier)
	local data = TierConfig.GetTier(tier)
	return (data and (data.DiskGlowColor or data.GlowColor)) or Color3.fromRGB(170, 120, 255)
end

local function colorFor(mutationId, tier)
	local mutation = MutationConfig.Get(mutationId)
	return if mutation then mutation.Main else tierColor(tier)
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(1, 0)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, contextual)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function gradient(parent, a, b, rotation)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

-- Sounds never block or break anything: a missing module or id is silent.
local function sfx(slot, options)
	if not Sounds then return nil end
	local ok, sound = pcall(Sounds.Play, slot, options)
	return if ok then sound else nil
end

local function fadeSound(sound, seconds)
	if Sounds and sound then pcall(Sounds.Fade, sound, seconds) end
end

-- ===================== INSTANT REVEAL (game pass) =====================
-- Owners (confirmed by InstantRevealServer) get REVEAL NOW and an AUTO toggle.
-- Everyone else sees INSTANT REVEAL with the pass's real Robux price; the
-- purchase prompt opens only when that button is pressed, never by itself or
-- from a keyboard shortcut. With no GamepassId set, the button is hidden.
local INSTANT_PASS_ID = math.floor(tonumber((MutationConfig.InstantReveal or {}).GamepassId) or 0)
local instantRemotes = nil
task.spawn(function()
	instantRemotes = ReplicatedStorage:WaitForChild("InstantRevealRemotes", 15)
	if not instantRemotes and RunService:IsStudio() then
		warn("[MutationClient] ReplicatedStorage.InstantRevealRemotes is missing: add the InstantRevealServer script, "
			.. "or Instant Reveal pass owners won't be recognised.")
	end
end)

local function ownsInstantReveal()
	return player:GetAttribute("InstantRevealOwned") == true
end

local function instantRevealForSale()
	return INSTANT_PASS_ID > 0 and not ownsInstantReveal()
end

local function autoInstantReveal()
	return ownsInstantReveal() and Settings ~= nil and Settings.Get ~= nil and Settings.Get("AutoInstantReveal") == true
end

-- The price comes from Roblox (whatever you set on the pass), fetched once.
local passPrice = nil
local priceState = "idle"   -- idle | loading | done
local priceLoaded = Instance.new("BindableEvent")

local function loadPassPrice()
	if INSTANT_PASS_ID <= 0 or priceState ~= "idle" then return end
	priceState = "loading"
	task.spawn(function()
		for attempt = 1, 3 do
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, INSTANT_PASS_ID, Enum.InfoType.GamePass)
			if ok and type(info) == "table" then
				passPrice = tonumber(info.PriceInRobux)
				priceState = "done"
				priceLoaded:Fire()
				return
			end
			task.wait(attempt * 3)
		end
		priceState = "idle"   -- try again on the next reveal
	end)
end

local purchasePromptOpen = false
local promptToken = 0

local function promptInstantReveal()
	if not instantRevealForSale() or purchasePromptOpen then return end
	purchasePromptOpen = true
	promptToken += 1
	local token = promptToken
	local ok, err = pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, INSTANT_PASS_ID)
	if not ok then
		purchasePromptOpen = false
		warn("[MutationClient] Couldn't open the Instant Reveal purchase:", err)
		return
	end
	-- In case the close event never reaches this client, stop ignoring keys soon.
	task.delay(15, function()
		if promptToken == token then purchasePromptOpen = false end
	end)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who, passId)
	if who ~= player or passId ~= INSTANT_PASS_ID then return end
	purchasePromptOpen = false
	promptToken += 1
	-- The server also hears about the purchase; this covers "you already own it".
	local refresh = instantRemotes and instantRemotes:FindFirstChild("Refresh")
	if refresh then refresh:FireServer() end
end)
player:GetAttributeChangedSignal("InstantRevealOwned"):Connect(function()
	if ownsInstantReveal() then purchasePromptOpen = false end
end)

local function clamp01(x) return math.clamp(x, 0, 1) end
local function lerp(a, b, t) return a + (b - a) * t end
local function easeOutQuad(t) return 1 - (1 - t) * (1 - t) end
local function easeInQuad(t) return t * t end
local function easeOutCubic(t) return 1 - (1 - t) ^ 3 end
local function easeInOutCubic(t)
	return if t < 0.5 then 4 * t * t * t else 1 - (-2 * t + 2) ^ 3 / 2
end
local function easeOutBack(t)
	return 1 + 2.70158 * (t - 1) ^ 3 + 1.70158 * (t - 1) ^ 2
end

-- ===================== MODELS =====================
local function findCore(model)
	local core, largest, largestSize = nil, nil, 0
	for _, instance in ipairs(model:GetDescendants()) do
		if instance:IsA("LuaSourceContainer") or instance:IsA("Sound") then
			instance:Destroy()
		elseif instance:IsA("BasePart") then
			instance.Anchored = true
			instance.CanCollide = false
			instance.CanQuery = false
			instance.CanTouch = false
			instance.CastShadow = false
			if not core and instance.Name:lower():match("^t0*%d+_core$") then
				core = instance
			end
			local size = instance.Size.Magnitude
			if size > largestSize then largest, largestSize = instance, size end
		end
	end
	return core or largest
end

-- A cosmetic copy of a tier (no collisions, no gameplay), with its mutation.
local function buildModel(tier, mutationId, options)
	local folder = ReplicatedStorage:FindFirstChild("BlackHoleCompleteModels")
	local template = folder and folder:FindFirstChild("T" .. tostring(tier))
	local model
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = Instance.new("Model")
		local ball = Instance.new("Part")
		ball.Name = "T" .. tostring(tier) .. "_Core"
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * 4
		ball.Parent = model
	end
	model.Name = "MutationDisplayModel"

	local core = findCore(model)
	if not core then
		model:Destroy()
		return nil
	end
	core.PivotOffset = core.CFrame:ToObjectSpace(CFrame.new(core.Position))
	model.PrimaryPart = core
	local _, extent = model:GetBoundingBox()
	local diameter = math.max(extent.X, extent.Y, extent.Z, 0.1)

	local cosmetic = nil
	if Cosmetics then
		local ok, result = pcall(Cosmetics.Build, model, core, tier, {
			reference = diameter,
			mutation = mutationId,
			quality = options.quality,
			viewport = options.viewport,
			projection = options.projection,
		})
		if ok then cosmetic = result end
	end
	return model, core, diameter, cosmetic
end

-- ===================== 1. WORLD MERGE =====================
-- Short and clean (about 0.7 s to the result, then a quick settle):
--   Respond   both black holes pulse and lift together
--   Travel    each swoops along a short curve to the shared point (mirrored,
--             so they meet like a clean S), with a faint trail
--   Converge  they shrink into one bright point while a ring closes in
--   Result    the point flares once, a thin shockwave rolls out, a few
--             sparkles, and the new black hole pops in (BlackHoleVisualClient)
-- The result appears exactly when the server reveals it (FusionRevealAt).

local FUSION = REVEAL.Fusion or { Respond = 0.12, Travel = 0.4, Converge = 0.14, Linger = 0.8 }

local proxyFolder = Instance.new("Folder")
proxyFolder.Name = "MergeFusionProxies"
proxyFolder.Parent = workspace

-- Tells BlackHoleCarryClient that merges are drawn here (its old flash skips).
player:SetAttribute("MergeFusionClient", true)

local fusions = {}
local fusionConnection = nil

local function effectPart(name, shape, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material
	part.Color = color
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Parent = parent
	return part
end

local function newRing(anchor, color)
	local ring = Instance.new("CylinderHandleAdornment")
	ring.Name = "FusionRing"
	ring.Adornee = anchor
	ring.Color3 = color
	ring.Transparency = 1
	ring.Height = 0.03
	ring.Radius = 0.02
	ring.InnerRadius = 0
	ring.Parent = anchor
	return ring
end

-- Keeps InnerRadius below Radius while both change.
local function setRing(ring, outer, inner, transparency)
	outer = math.max(outer, 0.02)
	ring.InnerRadius = 0
	ring.Radius = outer
	ring.InnerRadius = math.clamp(inner, 0, outer - 0.01)
	ring.Transparency = clamp01(transparency)
end

local function facing(from, cameraPosition)
	local direction = cameraPosition - from
	if direction.Magnitude < 0.01 then return CFrame.new() end
	return CFrame.lookAt(Vector3.zero, direction)
end

-- Owner popup: the new black hole's name and a big "★4/s!".
local function showIncomePopup(fusion)
	local data = TierConfig.GetTier(fusion.resultTier)
	local name = tostring(data and data.DisplayName or ("Tier " .. fusion.resultTier))
	local power = tonumber(data and (data.StellarPower or data.IncomePerSecond)) or 0
	local powerText = if Format and Format.Power then Format.Power(power) else ("★" .. math.floor(power) .. "/s")

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MergeIncomePopup"
	billboard.Adornee = fusion.anchor
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 200
	billboard.Size = UDim2.fromOffset(300, 104)
	billboard.StudsOffset = Vector3.new(0, fusion.resultSize * 0.75 + 1.2, 0)
	billboard.Parent = fusion.anchor

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = billboard
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = holder

	local function line(text, y, height, size, color, outlineColor, thickness)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, y)
		label.Size = UDim2.new(1, 0, 0, height)
		label.Font = FONT
		label.Text = text
		label.TextSize = size
		label.TextColor3 = color
		label.Parent = holder
		local outline = stroke(label, outlineColor, thickness, true)
		return label, outline
	end

	local size = SizeVariants.Read(fusion.sizeMultiplier)
	local resultText = if size>1 then (if SizeVariants.IsProtected(size) then "GIANT · " else "SIZE VARIANT · ") .. SizeVariants.Text(size) else name
	local title, titleOutline = line(resultText, 0, 30, 24, WHITE, OUTLINE, 2.5)
	local income, incomeOutline = line(powerText .. "!", 30, 70, 58, WHITE, Color3.fromRGB(18, 70, 30), 4.5)
	gradient(income, Color3.fromRGB(150, 255, 150), Color3.fromRGB(56, 214, 90))

	TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(billboard, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = billboard.StudsOffset + Vector3.new(0, 1.4, 0),
	}):Play()
	task.delay(0.85, function()
		if not billboard.Parent then return end
		local fade = TweenInfo.new(0.28)
		TweenService:Create(title, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(income, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(titleOutline, fade, { Transparency = 1 }):Play()
		TweenService:Create(incomeOutline, fade, { Transparency = 1 }):Play()
	end)
	Debris:AddItem(billboard, 1.2)
end

local function arrive(fusion)
	fusion.arrived = true
	for _, proxy in ipairs(fusion.proxies) do
		if proxy.model then
			proxy.model:Destroy()
			proxy.model = nil
		end
		if proxy.glow then
			proxy.glow:Destroy()
			proxy.glow = nil
		end
	end
	if fusion.sparkles and fusion.sparkleCount > 0 then
		fusion.sparkles:Emit(fusion.sparkleCount)
	end
	fadeSound(fusion.pullSound, 0.1)
	-- The cores meet: the impact (2D for your own merge, in the world for others).
	sfx("MERGE_FUSION_ID", { position = if fusion.mine then nil else fusion.center, sequence = fusion.sequence })
	-- A mutated result is revealed on screen next, so no popup under it.
	if fusion.mine and fusion.mutation == "" then
		showIncomePopup(fusion)
	end
end

-- Returns false once the fusion has finished.
local function stepFusion(fusion, now, cameraPosition)
	local e = now - fusion.start
	local size = fusion.resultSize
	local R, T, C = fusion.respondTime, fusion.travelTime, fusion.convergeTime

	if e < fusion.duration then
		local respond = clamp01(e / R)
		local travel = clamp01((e - R) / T)
		local converge = clamp01((e - R - T) / C)
		local focus = fusion.center + Vector3.new(0, size * 0.1 * (1 - converge), 0)

		for _, proxy in ipairs(fusion.proxies) do
			if proxy.model then
				local lift = Vector3.new(0, proxy.size * 0.14 * easeOutQuad(respond), 0)
				local from = proxy.start + lift
				local k = easeInOutCubic(travel)
				local position
				if fusion.calm then
					position = from:Lerp(focus, k)
				else
					local a = from:Lerp(proxy.control, k)
					local b = proxy.control:Lerp(focus, k)
					position = a:Lerp(b, k)
				end

				local pulse = if fusion.calm then 1 else 1 + 0.1 * math.sin(math.pi * respond)
				local grow = pulse * lerp(1, 0.6, easeInQuad(travel)) * (1 - 0.94 * easeInQuad(converge))
				local visual = proxy.size * grow
				local scale = math.max(proxy.scalePerStud * visual, 0.001)
				if math.abs(scale - proxy.appliedScale) > proxy.appliedScale * 0.01 then
					proxy.model:ScaleTo(scale)
					proxy.appliedScale = scale
					if proxy.cosmetic then proxy.cosmetic:SetSize(visual) end
				end
				local spin = if fusion.calm then 0 else proxy.direction * (e * 2.2 + travel * travel * 3)
				proxy.model:PivotTo(CFrame.new(position) * CFrame.Angles(0, proxy.yaw + spin, 0))
				if proxy.cosmetic then proxy.cosmetic:Face(cameraPosition) end

				if proxy.glow then
					proxy.glow.CFrame = CFrame.new(position)
					proxy.glow.Size = Vector3.one * math.max(visual * 0.5, 0.05)
					proxy.glow.Transparency = lerp(0.9, 0.5, travel) + 0.5 * converge
				end
			end
		end

		fusion.anchor.CFrame = CFrame.new(focus)

		-- The shared energy point forms as they meet.
		local form = clamp01((e - R - T * 0.6) / (T * 0.4 + C))
		local coreSize = size * 0.42 * easeOutBack(form)
		fusion.core.CFrame = CFrame.new(focus)
		fusion.core.Size = Vector3.one * math.max(coreSize, 0.05)
		fusion.core.Transparency = 1 - clamp01(form * 1.5)
		fusion.coreGlow.CFrame = CFrame.new(focus)
		fusion.coreGlow.Size = Vector3.one * math.max(coreSize * 1.7, 0.05)
		fusion.coreGlow.Transparency = 1 - 0.5 * form

		if fusion.implode then
			if converge > 0 then
				local radius = size * lerp(1.5, 0.3, easeInQuad(converge))
				setRing(fusion.implode, radius, radius * 0.9, lerp(0.7, 0.2, converge))
				fusion.implode.CFrame = facing(focus, cameraPosition)
			else
				fusion.implode.Transparency = 1
			end
		end
		if fusion.light then
			fusion.light.Brightness = 3 * form
			fusion.light.Range = size * 2.5 * form
		end
		return true
	end

	if not fusion.arrived then
		arrive(fusion)
	end
	local b = e - fusion.duration
	local center = fusion.center
	fusion.anchor.CFrame = CFrame.new(center)

	-- One crisp flare that shrinks into the new black hole.
	local swell = clamp01(b / 0.05)
	local shrink = clamp01((b - 0.05) / 0.22)
	local flare = size * lerp(0.42, 0.7, easeOutQuad(swell)) * (1 - easeInQuad(shrink))
	fusion.core.CFrame = CFrame.new(center)
	fusion.core.Size = Vector3.one * math.max(flare * 0.7, 0.05)
	fusion.core.Transparency = shrink
	fusion.coreGlow.CFrame = CFrame.new(center)
	fusion.coreGlow.Size = Vector3.one * math.max(flare, 0.05)
	fusion.coreGlow.Transparency = lerp(0.45, 1, shrink)
	if fusion.implode then fusion.implode.Transparency = 1 end

	if fusion.wave then
		local p = clamp01(b / 0.38)
		local radius = size * lerp(0.5, 2.3, easeOutCubic(p))
		setRing(fusion.wave, radius, radius * lerp(0.8, 0.95, p), lerp(if fusion.calm then 0.55 else 0.15, 1, p))
		fusion.wave.CFrame = facing(center, cameraPosition)
	end
	if fusion.disk then
		local p = clamp01(b / 0.45)
		local radius = size * lerp(0.6, 2.9, easeOutCubic(p))
		setRing(fusion.disk, radius, radius * 0.9, lerp(0.45, 1, p))
		fusion.disk.CFrame = fusion.diskFrame
	end
	if fusion.light then
		fusion.light.Brightness = lerp(5, 0, clamp01(b / 0.3))
		fusion.light.Range = size * 3
	end

	return b < fusion.linger
end

local function stepFusions()
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero

	for index = #fusions, 1, -1 do
		local fusion = fusions[index]
		local ok, alive = pcall(stepFusion, fusion, now, cameraPosition)
		if not ok then
			warn("[MutationClient] Merge effect failed:", alive)
		end
		if not ok or not alive then
			if not fusion.arrived and fusion.pullSound then
				fadeSound(fusion.pullSound, 0.08)
			end
			fusion.folder:Destroy()
			table.remove(fusions, index)
		end
	end

	if #fusions == 0 and fusionConnection then
		fusionConnection:Disconnect()
		fusionConnection = nil
	end
end

local recentFusionIds = {}   -- the same merge is never played twice

local function playFusion(payload)
	if type(payload) ~= "table" or type(payload.sources) ~= "table" then return end
	if type(payload.id) == "string" then
		if recentFusionIds[payload.id] then return end
		recentFusionIds[payload.id] = true
		task.delay(5, function() recentFusionIds[payload.id] = nil end)
	end
	local camera = workspace.CurrentCamera
	local center = payload.resultPosition
	if not camera or typeof(center) ~= "Vector3" then return end
	local distance = (camera.CFrame.Position - center).Magnitude
	if distance > (REVEAL.WorldFusionDistance or 220) then return end
	if #fusions >= 6 then return end

	local duration = math.clamp(tonumber(payload.duration) or 0.66, 0.3, 2)
	local planned = FUSION.Respond + FUSION.Travel + FUSION.Converge
	local stretch = duration / planned
	local calm = reduceMotion()
	local level = quality()
	local far = distance > 120
	local resultTier = math.clamp(math.floor(tonumber(payload.resultTier) or 1), 1, 99)
	local mutation = if type(payload.mutation) == "string" then payload.mutation else ""
	local mine = payload.ownerUserId == player.UserId
	-- The owner of a mutated merge sees the reveal next: don't spoil its colour.
	local color = if mine and mutation ~= "" then tierColor(resultTier) else colorFor(mutation, resultTier)
	local resultData = TierConfig.GetTier(resultTier)
	local sizeMultiplier = SizeVariants.Read(payload.sizeMultiplier)
	local resultSize = (tonumber(resultData and resultData.VisualSize) or 4) * sizeMultiplier

	-- Stay in step with the server even if the event arrived late.
	local late = 0
	local startedAt = tonumber(payload.startedAt)
	if startedAt then
		late = math.clamp(workspace:GetServerTimeNow() - startedAt, 0, duration * 0.6)
	end

	local folder = Instance.new("Folder")
	folder.Name = "Fusion"
	folder.Parent = proxyFolder

	local sparkleCount = if level == "HIGH" then 16 elseif level == "MODERATE" then 11 else 6
	if calm then sparkleCount = 5 end
	if far then sparkleCount = math.ceil(sparkleCount / 2) end

	local fusion = {
		start = os.clock() - late,
		duration = duration,
		respondTime = FUSION.Respond * stretch,
		travelTime = FUSION.Travel * stretch,
		convergeTime = FUSION.Converge * stretch,
		linger = FUSION.Linger or 0.8,
		center = center,
		sequence = if type(payload.id) == "string" then ("merge:" .. string.sub(payload.id, 1, 8)) else "merge",
		color = color,
		resultSize = resultSize,
		sizeMultiplier = sizeMultiplier,
		resultTier = resultTier,
		mutation = mutation,
		mine = mine,
		calm = calm,
		sparkleCount = sparkleCount,
		folder = folder,
		proxies = {},
		diskFrame = CFrame.Angles(math.rad(math.random(-10, 10)), 0, math.rad(math.random(-10, 10)))
			* CFrame.Angles(math.rad(90), 0, 0),
	}

	for index, source in ipairs(payload.sources) do
		if index > 2 then break end
		if type(source) == "table" and typeof(source.position) == "Vector3" then
			local tier = math.clamp(math.floor(tonumber(source.tier) or 1), 1, 99)
			local sourceMutation = if type(source.mutation) == "string" then source.mutation else ""
			local model, core, diameter, cosmetic = buildModel(tier, sourceMutation, { quality = level })
			if model then
				local data = TierConfig.GetTier(tier)
				local size = (tonumber(data and data.VisualSize) or 4) * SizeVariants.Read(source.sizeMultiplier)
				local scalePerStud = model:GetScale() / diameter
				model:ScaleTo(math.max(scalePerStud * size, 0.001))
				model:PivotTo(CFrame.new(source.position))
				model.Parent = folder
				if cosmetic then
					cosmetic:SetSize(size)
					cosmetic:SetDetail("FULL", true)
				end

				local sourceColor = colorFor(sourceMutation, tier)
				if not calm and core and level ~= "LOW" then
					-- Restrained trail; positions are in unscaled model units.
					local top = Instance.new("Attachment")
					top.Position = Vector3.new(0, diameter * 0.12, 0)
					top.Parent = core
					local bottom = Instance.new("Attachment")
					bottom.Position = Vector3.new(0, -diameter * 0.12, 0)
					bottom.Parent = core
					local trail = Instance.new("Trail")
					trail.Attachment0 = top
					trail.Attachment1 = bottom
					trail.Lifetime = 0.16
					trail.MinLength = 0.05
					trail.LightEmission = 1
					trail.LightInfluence = 0
					trail.FaceCamera = true
					trail.WidthScale = NumberSequence.new(1, 0)
					trail.Color = ColorSequence.new(sourceColor:Lerp(WHITE, 0.4), sourceColor)
					trail.Transparency = NumberSequence.new(0.45, 1)
					trail.Parent = core
				end

				-- Short curve: each source bows out to its own side of the path.
				local path = center - source.position
				local flat = Vector3.new(path.X, 0, path.Z)
				local side = if index == 1 then 1 else -1
				local bow = Vector3.zero
				if flat.Magnitude > 0.05 then
					bow = Vector3.new(-flat.Z, 0, flat.X).Unit * flat.Magnitude * 0.22 * side
				end
				local control = (source.position + center) / 2 + bow + Vector3.new(0, resultSize * 0.22, 0)

				local glow = effectPart("FusionSourceGlow", Enum.PartType.Ball, sourceColor:Lerp(WHITE, 0.3), Enum.Material.Neon, folder)

				table.insert(fusion.proxies, {
					model = model, cosmetic = cosmetic, core = core, glow = glow,
					start = source.position, control = control, size = size,
					scalePerStud = scalePerStud, appliedScale = scalePerStud * size,
					yaw = math.random() * math.pi * 2, direction = side,
				})
			end
		end
	end

	if #fusion.proxies == 0 then
		folder:Destroy()
		return
	end

	local anchor = effectPart("FusionAnchor", Enum.PartType.Block, WHITE, Enum.Material.SmoothPlastic, folder)
	anchor.CFrame = CFrame.new(center)
	fusion.anchor = anchor
	local burstPoint = Instance.new("Attachment")
	burstPoint.Parent = anchor

	fusion.core = effectPart("FusionCore", Enum.PartType.Ball, WHITE:Lerp(color, 0.15), Enum.Material.Neon, folder)
	fusion.coreGlow = effectPart("FusionCoreGlow", Enum.PartType.Ball, color, Enum.Material.Neon, folder)
	fusion.wave = newRing(anchor, WHITE:Lerp(color, 0.35))
	if not calm then
		fusion.implode = newRing(anchor, color:Lerp(WHITE, 0.5))
		if level ~= "LOW" and not far then
			fusion.disk = newRing(anchor, color)
		end
	end
	if level ~= "LOW" and not far and not calm then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Brightness = 0
		light.Range = 0
		light.Shadows = false
		light.Parent = anchor
		fusion.light = light
	end

	local sparkle = resultSize * 0.09
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FusionSparkles"
	emitter.Texture = SPARKLE
	emitter.Enabled = false
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Speed = NumberRange.new(resultSize * 2, resultSize * 4.5)
	emitter.Drag = 7
	emitter.Lifetime = NumberRange.new(0.45, 0.8)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.12, sparkle),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new(WHITE, color)
	emitter.Parent = burstPoint
	fusion.sparkles = emitter

	-- Starts with the movement; if the event arrived late, the sound skips the
	-- same amount so it still peaks as the black holes close in.
	fusion.pullSound = sfx("MERGE_PULL_ID", {
		position = if mine then nil else center,
		offset = late,
		key = if type(payload.id) == "string" then ("pull:" .. payload.id) else nil,
		sequence = if type(payload.id) == "string" then ("merge:" .. string.sub(payload.id, 1, 8)) else "merge",
	})

	table.insert(fusions, fusion)
	if not fusionConnection then
		fusionConnection = RunService.RenderStepped:Connect(stepFusions)
	end
end

mergeFusion.OnClientEvent:Connect(function(payload)
	local ok, err = pcall(playFusion, payload)
	if not ok then
		warn("[MutationClient] Merge effect failed:", err)
		local active = {}
		for _, fusion in ipairs(fusions) do active[fusion.folder] = true end
		for _, child in ipairs(proxyFolder:GetChildren()) do
			if not active[child] then child:Destroy() end
		end
	end
end)

-- ===================== TEXT STYLE =====================
-- One font, one outline colour, one soft drop shadow, fixed sizes per role:
--   Title 72, Heading 30, Odds 30, Body 24, Small 20. Sizes are design pixels
--   inside a UIScale'd stage, so hierarchy stays the same on every screen.
-- UIStroke thickness isn't changed by UIScale, so it's scaled by hand.

local function styledText(parent, props, uiScale)
	uiScale = uiScale or 1
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "Text"
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.Text = props.Text or ""
	label.TextSize = props.TextSize or 24
	label.TextColor3 = props.Color or WHITE
	label.TextXAlignment = props.AlignX or Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = props.Wrap == true
	label.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
	label.Position = props.Position or UDim2.fromScale(0.5, 0.5)
	label.Size = props.Size or UDim2.fromOffset(400, 40)
	label.ZIndex = props.ZIndex or 6
	label.Parent = parent
	if props.Gradient then
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = props.Gradient
		g.Parent = label
	end

	local thickness = props.Outline or math.clamp(label.TextSize / 13, 1.5, 5.5)
	local outline = stroke(label, props.OutlineColor or OUTLINE, math.max(thickness * uiScale, 1), true)

	local shadow = nil
	if props.Shadow ~= false then
		shadow = Instance.new("TextLabel")
		shadow.Name = label.Name .. "Shadow"
		shadow.BackgroundTransparency = 1
		shadow.Font = FONT
		shadow.Text = label.Text
		shadow.TextSize = label.TextSize
		shadow.TextColor3 = BLACK
		shadow.TextTransparency = 0.5
		shadow.TextXAlignment = label.TextXAlignment
		shadow.TextWrapped = label.TextWrapped
		shadow.AnchorPoint = label.AnchorPoint
		shadow.Position = label.Position + UDim2.fromOffset(0, math.max(3, math.floor(label.TextSize / 14)))
		shadow.Size = label.Size
		shadow.ZIndex = label.ZIndex - 1
		shadow.Parent = parent
		stroke(shadow, BLACK, math.max(thickness * uiScale, 1), true).Transparency = 0.5
	end

	local text = { label = label, outline = outline, shadow = shadow, alpha = 1 }
	function text.SetAlpha(alpha)
		text.alpha = alpha
		label.TextTransparency = 1 - alpha
		outline.Transparency = 1 - alpha
		if shadow then
			shadow.TextTransparency = 1 - alpha * 0.5
			local s = shadow:FindFirstChildOfClass("UIStroke")
			if s then s.Transparency = 1 - alpha * 0.5 end
		end
	end
	function text.SetText(value)
		label.Text = value
		if shadow then shadow.Text = value end
	end
	return text
end

local function fitScale(designW, designH)
	if UiResponsive then
		return UiResponsive.FitScale(designW, designH, { margin = 14, min = 0.45, max = 1 })
	end
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return math.clamp(math.min((viewport.X - 28) / designW, (viewport.Y - 28) / designH), 0.45, 1)
end

-- Chunky cartoon button: coloured body, darker base, white outlined text.
local function cartoonButton(parent, props, uiScale)
	uiScale = uiScale or 1
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
	button.Position = props.Position
	button.Size = props.Size
	button.BackgroundColor3 = props.Color
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = props.ZIndex or 40
	button.Parent = parent
	corner(button, UDim.new(0, 16))
	local body = gradient(button, props.Color:Lerp(WHITE, 0.18), props.Color:Lerp(BLACK, 0.12))
	local border = stroke(button, OUTLINE, 3.5 * uiScale)
	local text = styledText(button, {
		Name = "Label", Text = props.Text, TextSize = props.TextSize or 28,
		Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.new(1, -16, 1, -8),
		ZIndex = button.ZIndex + 2, Outline = 2.6,
	}, uiScale)
	local pop = Instance.new("UIScale")
	pop.Parent = button

	button.MouseEnter:Connect(function()
		sfx("UI_HOVER_ID")
		TweenService:Create(pop, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.06 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		sfx("UI_CLICK_ID")
	end)

	return { button = button, text = text, body = body, border = border, pop = pop }
end

local function paintButton(entry, color)
	entry.button.BackgroundColor3 = color
	entry.body.Color = ColorSequence.new(color:Lerp(WHITE, 0.18), color:Lerp(BLACK, 0.12))
end

local function placeText(text, position, size, textSize)
	text.label.Position = position
	text.label.Size = size
	text.label.TextSize = math.floor(textSize)
	if text.shadow then
		text.shadow.Position = position + UDim2.fromOffset(0, math.max(3, math.floor(text.label.TextSize / 14)))
		text.shadow.Size = size
		text.shadow.TextSize = text.label.TextSize
	end
end

-- ===================== 2. CONFIRMATION =====================
local promptGui = Instance.new("ScreenGui")
promptGui.Name = "MergeConfirmPrompt"
promptGui.ResetOnSpawn = false
promptGui.IgnoreGuiInset = true
promptGui.DisplayOrder = 90   -- above the carry card (80): its buttons must never be covered
promptGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
promptGui.Enabled = false
promptGui.Parent = playerGui

local promptPanel = Instance.new("Frame")
promptPanel.Name = "Panel"
promptPanel.AnchorPoint = Vector2.new(0.5, 0.5)
promptPanel.Position = UDim2.fromScale(0.5, 0.46)
promptPanel.Size = UDim2.fromOffset(520, 330)
promptPanel.BackgroundColor3 = Color3.fromRGB(20, 22, 48)
promptPanel.BackgroundTransparency = 0.02
promptPanel.Active = true
promptPanel.Parent = promptGui
corner(promptPanel, UDim.new(0, 22))
stroke(promptPanel, OUTLINE, 4)
local promptScale = Instance.new("UIScale")
promptScale.Parent = promptPanel

local promptHeader = Instance.new("Frame")
promptHeader.Name = "Header"
promptHeader.Size = UDim2.new(1, 0, 0, 64)
promptHeader.BackgroundColor3 = Color3.fromRGB(255, 96, 176)
promptHeader.ZIndex = 2
promptHeader.Parent = promptPanel
corner(promptHeader, UDim.new(0, 22))
local promptHeaderGradient = gradient(promptHeader, Color3.fromRGB(255, 140, 200), Color3.fromRGB(220, 60, 150))
stroke(promptHeader, OUTLINE, 4)
styledText(promptHeader, { Text = "MERGE RARE BLACK HOLES?", TextSize = 34, Size = UDim2.new(1, -30, 1, 0), ZIndex = 4 })

local promptParentA = styledText(promptPanel, { Name = "ParentA", TextSize = 22, Position = UDim2.new(0.5, 0, 0, 96), Size = UDim2.new(1, -40, 0, 28), ZIndex = 3 })
local promptParentB = styledText(promptPanel, { Name = "ParentB", TextSize = 22, Position = UDim2.new(0.5, 0, 0, 130), Size = UDim2.new(1, -40, 0, 28), ZIndex = 3 })
styledText(promptPanel, {
	Text = "Both black holes are consumed. Their mutations and sizes are lost. The result gets NEW, independent mutation and size rolls.",
	TextSize = 20, Wrap = true, Color = Color3.fromRGB(200, 208, 240), Shadow = false,
	Position = UDim2.new(0.5, 0, 0, 190), Size = UDim2.new(1, -56, 0, 64), ZIndex = 3,
})

local keep = cartoonButton(promptPanel, {
	Name = "Keep", Text = "KEEP THEM", Color = Color3.fromRGB(96, 110, 170),
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.27, 0, 1, -20), Size = UDim2.new(0.42, 0, 0, 60), ZIndex = 5,
})
local merge = cartoonButton(promptPanel, {
	Name = "Merge", Text = "MERGE", Color = Color3.fromRGB(80, 210, 100),
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.73, 0, 1, -20), Size = UDim2.new(0.42, 0, 0, 60), ZIndex = 5,
})
local keepButton, mergeButton = keep.button, merge.button

local promptTarget = nil
local promptSourceId = nil
local promptToken = 0
local suppressed = setmetatable({}, { __mode = "k" })   -- [target] = until (os.clock)

local function mutationLine(name, mutationId)
	local mutation = MutationConfig.Get(mutationId)
	if mutation then
		return ("%s  •  ✦ %s"):format(tostring(name or "Black Hole"), string.upper(mutation.DisplayName)), mutation.Main
	end
	return tostring(name or "Black Hole") .. "  •  no mutation", Color3.fromRGB(210, 218, 245)
end

-- The prompt goes in the free space between the top HUD (Upgrade / Lock
-- Base) and the carry card, so it never sits under or over either of them.
-- It only shrinks if that space is too small.
local function placePrompt()
	local scale = fitScale(520, 330)
	if not UiResponsive then
		promptScale.Scale = scale
		promptPanel.Position = UDim2.fromScale(0.5, 0.46)
		return
	end
	local screen = UiResponsive.Screen()
	local top = UiResponsive.TopInset() + 8
	local hud = playerGui:FindFirstChild("MainHUD")
	local actions = hud and hud:FindFirstChild("TopActionButtons", true)
	if actions and actions:IsA("GuiObject") and actions.Visible and actions.AbsoluteSize.Y > 0 then
		top = math.max(top, UiResponsive.ToScreen(actions.AbsolutePosition).Y + actions.AbsoluteSize.Y + 10)
	end
	local bottom = screen.Y - 10
	local actionGui = playerGui:FindFirstChild("BlackHoleActionUI")
	local card = actionGui and actionGui:FindFirstChild("CarryCard", true)
	if card and card:IsA("GuiObject") and card.Visible and card.AbsoluteSize.Y > 0 then
		bottom = math.min(bottom, UiResponsive.ToScreen(card.AbsolutePosition).Y - 10)
	end
	local room = bottom - top
	if room > 80 then
		scale = math.min(scale, room / 330)
		promptPanel.Position = UDim2.new(0.5, 0, 0, math.floor((top + bottom) / 2 + 0.5))
	else
		promptPanel.Position = UDim2.fromScale(0.5, 0.46)
	end
	promptScale.Scale = scale
end

if UiResponsive and UiResponsive.Changed then
	UiResponsive.Changed:Connect(function()
		if promptGui.Enabled then placePrompt() end
	end)
end

local function hidePrompt()
	promptToken += 1
	promptGui.Enabled = false
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(promptGui) then
		GuiService.SelectedObject = nil
	end
	promptTarget = nil
end

mergeConfirmPrompt.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or typeof(data.target) ~= "Instance" then return end
	local target = data.target
	if (suppressed[target] or 0) > os.clock() then return end

	promptToken += 1
	local token = promptToken
	promptTarget = target
	promptSourceId = data.sourceId

	local textA, colorA = mutationLine(data.sourceName, data.sourceMutation)
	local textB, colorB = mutationLine(target:GetAttribute("DisplayName"), data.targetMutation)
	promptParentA.SetText("Holding:  " .. textA .. " · " .. SizeVariants.Text(data.sourceSize))
	promptParentA.label.TextColor3 = colorA
	promptParentB.SetText("Target:  " .. textB .. " · " .. SizeVariants.Text(data.targetSize))
	promptParentB.label.TextColor3 = colorB
	local accent = colorFor(if data.sourceMutation ~= "" then data.sourceMutation else data.targetMutation, data.tier)
	promptHeaderGradient.Color = ColorSequence.new(accent:Lerp(WHITE, 0.25), accent:Lerp(BLACK, 0.2))
	placePrompt()
	promptGui.Enabled = true
	sfx("UI_CLICK_ID")

	if UiResponsive and UiResponsive.IsGamepad() then
		GuiService.SelectedObject = keepButton   -- the safe choice first
	end

	task.delay(12, function()
		if promptToken == token then hidePrompt() end
	end)
end)

keepButton.Activated:Connect(function()
	if promptTarget then
		suppressed[promptTarget] = os.clock() + 10
	end
	hidePrompt()
end)

mergeButton.Activated:Connect(function()
	local target = promptTarget
	local sourceId = promptSourceId
	local requestId = game:GetService("HttpService"):GenerateGUID(false)
	hidePrompt()
	if not target then return end
	local ok, result = pcall(function()
		return confirmMerge:InvokeServer(target, requestId, sourceId)
	end)
	if not ok or type(result) ~= "table" or not result.ok then
		warn("[MutationClient] Merge not completed:", ok and type(result) == "table" and result.reason or result)
	end
end)

-- ===================== 3. REVEAL =====================
local revealGui = Instance.new("ScreenGui")
revealGui.Name = "MutationReveal"
revealGui.ResetOnSpawn = false
revealGui.IgnoreGuiInset = true
revealGui.DisplayOrder = 1000   -- above every HUD; the HUD itself is never changed
revealGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
revealGui.Enabled = false
revealGui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = DEEP
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Active = true   -- nothing behind the reveal can be clicked
root.Parent = revealGui

-- Design canvas: everything below is laid out in these pixels and scaled to
-- fit the safe area. The star, the reel and the black hole share HERO_Y.
local DESIGN = Vector2.new(1100, 690)
local HERO_Y = 250
local CARD_W, CARD_H, CARD_GAP = 170, 158, 14
local PITCH = CARD_W + CARD_GAP
local WINDOW_W, WINDOW_H = 1000, 180
local REEL_CARDS = 46

local current = nil   -- the reveal on screen

local function track(tween)
	if current then table.insert(current.tweens, tween) end
	tween:Play()
	return tween
end

local function tweenTo(object, seconds, props, style, direction)
	return track(TweenService:Create(object,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props))
end

-- The real screen size, always measured live. It must never come from this
-- ScreenGui (root.AbsoluteSize): while the reveal is switched off Roblox doesn't
-- lay it out, so that can still be the size the window had when you joined.
-- That stale size is what pushed the first reveal of a session (usually
-- Ionized, the most common mutation) into a corner.
local function screenSize()
	if UiResponsive and UiResponsive.Screen then
		local size = UiResponsive.Screen()
		if size.X >= 2 and size.Y >= 2 then return size end
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

local function circle(parent, name, color, transparency, sizeScale, zIndex)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(sizeScale, sizeScale)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex or 1
	frame.Parent = parent
	corner(frame)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = frame
	return frame
end

-- A tapered glowing ray: brightest in the middle, fading to both tips.
local function ray(parent, length, thickness, rotation, color, zIndex, strength)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(length, 0, thickness, 0)
	frame.Rotation = rotation
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	frame.Parent = parent
	local g = Instance.new("UIGradient")
	local peak = 1 - (strength or 1)
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.35, math.min(peak + 0.55, 1)),
		NumberSequenceKeypoint.new(0.5, peak),
		NumberSequenceKeypoint.new(0.65, math.min(peak + 0.55, 1)),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = frame
	corner(frame)
	return frame
end

-- ===================== REVEAL AUDIO TIMELINE =====================
-- MutationConfig.Reveal.Audio lists the cues. cue() is called at the exact
-- visual moment; a Delay (seconds) can nudge it. Pending cues belong to the
-- reveal's audioToken, so skipping or closing cancels them.
local AUDIO = REVEAL.Audio or {}

local function cueDelay(reveal, conf)
	local delay = conf.Delay or 0
	if type(delay) == "table" then
		delay = delay[reveal.mutation.Rarity] or 0
	end
	return math.max(tonumber(delay) or 0, 0)
end

local function cue(reveal, name, slotOverride)
	local conf = AUDIO[name] or {}
	local slot = slotOverride or conf.Slot
	if not slot then return end
	local delay = cueDelay(reveal, conf)
	local token = reveal.audioToken
	local entry = { name = name, slot = slot, intended = os.clock() - reveal.startedAt + delay, status = "pending" }
	table.insert(reveal.cueLog, entry)
	local function fire()
		if reveal.closed or reveal.audioToken ~= token then
			entry.status = "cancelled"
			return
		end
		entry.requested = os.clock() - reveal.startedAt
		local handle = sfx(slot, {
			sequence = reveal.sequenceId,
			onStart = function(h)
				entry.actual = h.StartedAt - reveal.startedAt
				entry.status = "played"
			end,
			onEnd = function(h)
				if h.Status ~= "finished" and not entry.actual then
					entry.status = h.Status .. (if h.Reason then (": " .. h.Reason) else "")
				end
			end,
		})
		if not handle then
			entry.status = "not requested (empty, muted or rate limited)"
			return
		end
		if entry.status == "pending" then entry.status = "waiting to load" end
		table.insert(reveal.sounds, handle)
		reveal.cueSounds[name] = handle
	end
	if delay > 0 then task.delay(delay, fire) else fire() end
end

-- Stops everything the reveal was building towards (on skip).
local function cancelCues(reveal)
	reveal.audioToken += 1
	for _, sound in pairs(reveal.cueSounds) do
		fadeSound(sound, 0.12)
	end
	table.clear(reveal.cueSounds)
end

local function printTimeline(reveal)
	if not RunService:IsStudio() or AUDIO.DebugTimeline == false or #reveal.cueLog == 0 then return end
	local lines = { ("[RevealAudio] %s  seq=%s  (intended = its visual moment, actual = when the sound started)"):format(reveal.mutation.DisplayName, tostring(reveal.sequenceId)) }
	for _, entry in ipairs(reveal.cueLog) do
		local actual = if entry.actual then ("%.3f"):format(entry.actual) else "  -  "
		entry.status = entry.status or "?"
		local diff = if entry.actual then ("%+.0f ms"):format((entry.actual - entry.intended) * 1000) else ""
		table.insert(lines, ("  %-10s %-20s intended %.3f  actual %s  %s  %s"):format(entry.name, entry.slot, entry.intended, actual, diff, entry.status))
	end
	print(table.concat(lines, "\n"))
end

local function waitFor(reveal, seconds)
	local finish = os.clock() + seconds
	while os.clock() < finish do
		if reveal.skip or reveal.closed then return false end
		RunService.RenderStepped:Wait()
	end
	return not (reveal.skip or reveal.closed)
end

-- ----- card icon: a tiny black hole built from shapes, one look per effect -----
local function dot(parent, color, size, x, y, transparency, zIndex, rotation)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(size, size)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Rotation = rotation or 0
	frame.ZIndex = zIndex
	frame.Parent = parent
	if not rotation then corner(frame) end
	return frame
end

local function bar(parent, color, length, thickness, x, y, rotation, zIndex, transparency)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(length, thickness)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Rotation = rotation
	frame.ZIndex = zIndex
	frame.Parent = parent
	corner(frame)
	return frame
end

local function ringShape(parent, color, size, thickness, zIndex, transparency, squash)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(size, size * (squash or 1))
	frame.BackgroundTransparency = 1
	frame.ZIndex = zIndex
	frame.Parent = parent
	corner(frame)
	local s = stroke(frame, color, thickness)
	s.Transparency = transparency or 0
	return frame
end

local function drawIcon(parent, mutation, z, uiScale)
	local main, rim, hot, band, accent = mutation.Main, mutation.Rim, mutation.Hot, mutation.Band, mutation.Accent
	local px = uiScale or 1
	dot(parent, main, 0.98, 0.5, 0.5, 0.8, z)                       -- glow
	dot(parent, main, 0.72, 0.5, 0.5, 0.62, z)
	local disk = ringShape(parent, band, 0.96, 4 * px, z + 1, 0, 0.3)  -- accretion disk
	disk.Rotation = -14
	dot(parent, BLACK, 0.44, 0.5, 0.5, 0, z + 2)                     -- event horizon
	local rimRing = ringShape(parent, rim, 0.46, 3 * px, z + 3, 0)
	rimRing.Name = "Rim"
	bar(parent, hot, 0.62, 0.035, 0.5, 0.56, -14, z + 4, 0.1)         -- disk passing in front

	local effect = mutation.Effect
	if effect == "charge" then
		bar(parent, accent, 0.16, 0.04, 0.17, 0.26, 60, z + 5)
		bar(parent, accent, 0.16, 0.04, 0.24, 0.36, -30, z + 5)
		bar(parent, accent, 0.16, 0.04, 0.8, 0.72, 60, z + 5)
		bar(parent, accent, 0.16, 0.04, 0.87, 0.62, -30, z + 5)
	elseif effect == "dust" then
		for i, p in ipairs({ { 0.14, 0.3 }, { 0.3, 0.12 }, { 0.84, 0.24 }, { 0.9, 0.7 }, { 0.2, 0.82 }, { 0.66, 0.9 } }) do
			dot(parent, if i % 2 == 0 then hot else accent, 0.06, p[1], p[2], 0, z + 5)
		end
	elseif effect == "flare" then
		for i = 0, 3 do
			local a = math.rad(45 + i * 90)
			bar(parent, accent, 0.2, 0.05, 0.5 + math.cos(a) * 0.38, 0.5 + math.sin(a) * 0.38, 45 + i * 90, z + 5)
		end
	elseif effect == "crystals" then
		for _, p in ipairs({ { 0.16, 0.3 }, { 0.86, 0.36 }, { 0.62, 0.86 } }) do
			dot(parent, hot, 0.12, p[1], p[2], 0.05, z + 5, 45)
		end
	elseif effect == "vapor" then
		for i, p in ipairs({ { 0.34, 0.16 }, { 0.56, 0.08 }, { 0.72, 0.2 } }) do
			dot(parent, band, 0.14 + i * 0.02, p[1], p[2], 0.35, z + 5)
		end
	elseif effect == "flow" then
		ringShape(parent, accent, 0.66, 2.5 * px, z + 1, 0.15)
		dot(parent, accent, 0.07, 0.18, 0.5, 0, z + 5)
		dot(parent, accent, 0.07, 0.82, 0.5, 0, z + 5)
	elseif effect == "arcs" then
		bar(parent, accent, 0.18, 0.045, 0.16, 0.24, 70, z + 5)
		bar(parent, accent, 0.18, 0.045, 0.24, 0.36, -10, z + 5)
		bar(parent, accent, 0.18, 0.045, 0.32, 0.48, 70, z + 5)
		bar(parent, accent, 0.18, 0.045, 0.72, 0.62, 70, z + 5)
		bar(parent, accent, 0.18, 0.045, 0.8, 0.74, -10, z + 5)
	elseif effect == "prism" and mutation.Spectrum then
		for i, color in ipairs(mutation.Spectrum) do
			local a = math.rad(-90 + (i - 1) * 60)
			dot(parent, color, 0.12, 0.5 + math.cos(a) * 0.4, 0.5 + math.sin(a) * 0.4, 0, z + 5)
		end
	elseif effect == "eclipse" then
		ringShape(parent, WHITE, 0.52, 3 * px, z + 3, 0)
		dot(parent, hot, 0.2, 0.34, 0.36, 0.55, z + 1)
	elseif effect == "stars" then
		for _, p in ipairs({ { 0.14, 0.2 }, { 0.86, 0.16 }, { 0.9, 0.78 }, { 0.12, 0.8 }, { 0.5, 0.06 } }) do
			dot(parent, accent, 0.09, p[1], p[2], 0, z + 5, 45)
		end
	elseif effect == "nova" then
		ringShape(parent, hot, 0.9, 3 * px, z + 1, 0.1)
		dot(parent, hot, 0.1, 0.5, 0.04, 0, z + 5, 45)
		dot(parent, hot, 0.1, 0.5, 0.96, 0, z + 5, 45)
	elseif effect == "singularity" then
		ringShape(parent, WHITE, 0.64, 2 * px, z + 3, 0)
		dot(parent, BLACK, 0.52, 0.5, 0.5, 0, z + 2)
		ringShape(parent, accent, 0.54, 2 * px, z + 3, 0.2)
	end
end

local function makeReelCard(parent, mutationId, x, zIndex, uiScale)
	local mutation = MutationConfig.Get(mutationId)
	local rarityColor = RARITY_COLORS[mutation.Rarity] or WHITE

	local card = Instance.new("Frame")
	card.Name = "Card_" .. mutationId
	-- Anchored at the centre so a pop or the winner's enlarge stays centred.
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0, x + CARD_W / 2, 0.5, 0)
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.ZIndex = zIndex
	card.Parent = parent
	corner(card, UDim.new(0, 16))
	gradient(card, mutation.Main:Lerp(BLACK, 0.5), Color3.fromRGB(16, 18, 40))
	local border = stroke(card, rarityColor, 4 * uiScale)
	local pop = Instance.new("UIScale")
	pop.Parent = card

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 10)
	icon.Size = UDim2.fromOffset(98, 98)
	icon.BackgroundTransparency = 1
	icon.ZIndex = zIndex + 1
	icon.Parent = card
	drawIcon(icon, mutation, zIndex + 1, uiScale)

	styledText(card, {
		Name = "Name", Text = string.upper(mutation.DisplayName), TextSize = 23,
		Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.new(1, -10, 0, 28), ZIndex = zIndex + 9, Outline = 2.4,
	}, uiScale)

	local rarityBar = Instance.new("Frame")
	rarityBar.Name = "Rarity"
	rarityBar.AnchorPoint = Vector2.new(0.5, 1)
	rarityBar.Position = UDim2.new(0.5, 0, 1, -7)
	rarityBar.Size = UDim2.new(1, -30, 0, 6)
	rarityBar.BackgroundColor3 = rarityColor
	rarityBar.BorderSizePixel = 0
	rarityBar.ZIndex = zIndex + 8
	rarityBar.Parent = card
	corner(rarityBar)

	return { frame = card, pop = pop, border = border, id = mutationId, x = x }
end

-- Reel order: random cosmetic filler, the committed result at winIndex, and
-- every mutation shown at least once well before the result. Nothing is
-- placed next to the result on purpose.
local function reelOrder(rng, winner, count, winIndex)
	local catalog = MutationConfig.Order
	local order = {}
	for i = 1, count do
		if i == winIndex then
			order[i] = winner
		else
			local pick
			repeat
				pick = catalog[rng:NextInteger(1, #catalog)]
			until pick ~= order[i - 1] or #catalog < 2
			order[i] = pick
		end
	end
	local present = {}
	for _, id in ipairs(order) do present[id] = true end
	local slots = {}
	for i = 2, winIndex - 6 do table.insert(slots, i) end
	for _, id in ipairs(catalog) do
		if not present[id] and #slots > 0 then
			local slot = table.remove(slots, rng:NextInteger(1, #slots))
			order[slot] = id
			present[id] = true
		end
	end
	return order
end

-- ----- building the reveal -----
local function buildReveal(item)
	local mutation = MutationConfig.Get(item.mutation)
	local main = mutation.Main
	local rarityColor = RARITY_COLORS[mutation.Rarity] or WHITE
	local screen = screenSize()
	local safeOffset, safeSize = Vector2.zero, screen
	if UiResponsive and UiResponsive.SafeRect then
		safeOffset, safeSize = UiResponsive.SafeRect()
	end
	local scale = math.clamp(math.min((safeSize.X - 12) / DESIGN.X, (safeSize.Y - 12) / DESIGN.Y), 0.4, 1.4)
	-- Centred on the screen itself (not the safe area, which is lopsided with
	-- the top bar), scaled so it still fits inside the safe area.
	local center = screen / 2 + Vector2.new(0, (HERO_Y - DESIGN.Y / 2) * scale)
	local minDim = math.min(screen.X, screen.Y)
	local rng = Random.new()

	local reveal = {
		item = item, mutation = mutation, scale = scale, center = center, minDim = minDim, rng = rng,
		tweens = {}, connections = {}, sounds = {}, motes = {},
		skip = false, closed = false,
		-- audio timeline
		startedAt = os.clock(), audioToken = 0, cueSounds = {}, cueLog = {},
		sequenceId = "reveal:" .. tostring(item.id or math.floor(os.clock() * 1000) % 100000),
	}

	-- Backdrop (shown once the screen is dark) ------------------------------
	local scene = Instance.new("Frame")
	scene.Name = "Scene"
	scene.Size = UDim2.fromScale(1, 1)
	scene.BackgroundColor3 = DEEP
	scene.BorderSizePixel = 0
	scene.ZIndex = 1
	scene.Visible = false
	scene.Parent = root
	gradient(scene, Color3.fromRGB(16, 12, 42), Color3.fromRGB(4, 4, 14))
	reveal.scene = scene

	for _ = 1, 3 do
		local nebula = circle(scene, "Nebula", main:Lerp(Color3.fromRGB(80, 60, 180), 0.5), 0.93, 0.5 + rng:NextNumber() * 0.4, 1)
		nebula.Position = UDim2.fromScale(0.15 + rng:NextNumber() * 0.7, 0.15 + rng:NextNumber() * 0.7)
		nebula.SizeConstraint = Enum.SizeConstraint.RelativeYY
	end
	reveal.twinkles = {}
	for i = 1, 40 do
		local star = Instance.new("Frame")
		star.Name = "Star"
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber())
		local pixel = rng:NextInteger(1, 3)
		star.Size = UDim2.fromOffset(pixel, pixel)
		star.BackgroundColor3 = WHITE
		star.BackgroundTransparency = 0.3 + rng:NextNumber() * 0.5
		star.BorderSizePixel = 0
		star.ZIndex = 2
		star.Parent = scene
		if i % 3 == 0 then
			table.insert(reveal.twinkles, { frame = star, seed = rng:NextNumber() * 6.28 })
		end
	end

	-- Stage (scaled design canvas) -------------------------------------------
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)   -- stays centred if the window changes size
	stage.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
	stage.BackgroundTransparency = 1
	stage.ZIndex = 3
	stage.Visible = false
	stage.Parent = root
	local stageScale = Instance.new("UIScale")
	stageScale.Scale = scale
	stageScale.Parent = stage
	reveal.stage = stage
	reveal.stageScale = stageScale

	-- Result: halo + the mutated black hole
	local hero = Instance.new("Frame")
	hero.Name = "Hero"
	hero.AnchorPoint = Vector2.new(0.5, 0.5)
	hero.Position = UDim2.fromOffset(DESIGN.X / 2, HERO_Y)
	hero.Size = UDim2.fromOffset(380, 380)
	hero.BackgroundTransparency = 1
	hero.ZIndex = 3
	hero.Visible = false
	hero.Parent = stage
	local heroScale = Instance.new("UIScale")
	heroScale.Parent = hero
	reveal.hero, reveal.heroScale = hero, heroScale

	local haloRings = {
		circle(hero, "HaloOuter", main, 0.92, 1.4, 3),
		circle(hero, "HaloMid", main, 0.86, 1.02, 3),
		circle(hero, "HaloInner", main:Lerp(WHITE, 0.3), 0.72, 0.62, 3),
		circle(hero, "Photon", main:Lerp(WHITE, 0.6), 0.3, 0.44, 3),
	}
	for _, ring in ipairs(haloRings) do
		ring:SetAttribute("Target", ring.BackgroundTransparency)
		ring.BackgroundTransparency = 1
	end
	reveal.haloRings = haloRings

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Model"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(120, 120, 150)
	viewport.LightColor = main:Lerp(WHITE, 0.5)
	viewport.LightDirection = Vector3.new(-0.3, -0.7, -0.6)
	viewport.ImageTransparency = 1
	viewport.ZIndex = 4
	viewport.Parent = hero
	reveal.viewport = viewport

	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local model, _, _, cosmetic = buildModel(item.tier, item.mutation, { viewport = true, quality = "MODERATE" })
	if model then
		model:PivotTo(CFrame.new())
		model:ScaleTo(model:GetScale() * SizeVariants.Read(item.sizeMultiplier))
		model.Parent = world
		local boundsFrame, bounds = model:GetBoundingBox()
		reveal.radius = bounds.Magnitude * 0.5 + (boundsFrame.Position - model:GetPivot().Position).Magnitude
		reveal.model = model
		reveal.cosmetic = cosmetic
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	reveal.camera = camera

	-- Result text (under the black hole, never over its core)
	local texts = {}
	reveal.pills = {}

	local rarityPill = Instance.new("Frame")
	rarityPill.Name = "RarityPill"
	rarityPill.AnchorPoint = Vector2.new(0.5, 0.5)
	rarityPill.Position = UDim2.fromOffset(DESIGN.X / 2, 452)
	rarityPill.Size = UDim2.fromOffset(210, 38)
	rarityPill.BackgroundColor3 = rarityColor
	rarityPill.BackgroundTransparency = 1
	rarityPill.ZIndex = 6
	rarityPill.Parent = stage
	corner(rarityPill)
	gradient(rarityPill, rarityColor:Lerp(WHITE, 0.25), rarityColor:Lerp(BLACK, 0.15))
	local rarityStroke = stroke(rarityPill, OUTLINE, 3 * scale)
	rarityStroke.Transparency = 1
	table.insert(reveal.pills, { frame = rarityPill, stroke = rarityStroke })
	texts.rarity = styledText(rarityPill, {
		Name = "Rarity", Text = RARITY_NAMES[mutation.Rarity] or string.upper(mutation.Rarity),
		TextSize = 22, Size = UDim2.new(1, -12, 1, 0), ZIndex = 8, Outline = 2.4,
	}, scale)

	texts.name = styledText(stage, {
		Name = "MutationName", Text = string.upper(mutation.DisplayName), TextSize = 76,
		Position = UDim2.fromOffset(DESIGN.X / 2, 506), Size = UDim2.fromOffset(1000, 84), ZIndex = 7,
		Gradient = ColorSequence.new(main:Lerp(WHITE, 0.65), main), Outline = 5.5,
	}, scale)

	local oddsPill = Instance.new("Frame")
	oddsPill.Name = "OddsPill"
	oddsPill.AnchorPoint = Vector2.new(0.5, 0.5)
	oddsPill.Position = UDim2.fromOffset(DESIGN.X / 2, 568)
	oddsPill.Size = UDim2.fromOffset(if (tonumber(item.luck) or 1) > 1 then 400 else 280, 46)
	oddsPill.BackgroundColor3 = Color3.fromRGB(18, 18, 44)
	oddsPill.BackgroundTransparency = 1
	oddsPill.ZIndex = 6
	oddsPill.Parent = stage
	corner(oddsPill)
	local oddsStroke = stroke(oddsPill, main, 3 * scale)
	oddsStroke.Transparency = 1
	table.insert(reveal.pills, { frame = oddsPill, stroke = oddsStroke, fill = 0.1 })
	texts.odds = styledText(oddsPill, {
		Name = "Odds", Text = MutationConfig.OddsText(item.oneIn) .. (if (tonumber(item.luck) or 1) > 1
			then ("  (%sx LUCK)"):format((string.format("%.2f", item.luck):gsub("%.?0+$", ""))) else ""), TextSize = 30,
		Size = UDim2.new(1, -16, 1, 0), ZIndex = 8, Color = main:Lerp(WHITE, 0.55), Outline = 3,
	}, scale)

	texts.bonus = styledText(stage, {
		Name = "Bonus", Text = if MutationConfig.BonusText then MutationConfig.BonusText(item.mutation) else "",
		TextSize = 24, Position = UDim2.fromOffset(DESIGN.X / 2, 614), Size = UDim2.fromOffset(1000, 30), ZIndex = 7,
		Color = GOLD, Outline = 2.5,
	}, scale)

	texts.tier = styledText(stage, {
		Name = "TierName", Text = tostring(item.tierName or "") .. "  •  SIZE " .. SizeVariants.Text(item.sizeMultiplier), TextSize = 24,
		Position = UDim2.fromOffset(DESIGN.X / 2, 656), Size = UDim2.fromOffset(900, 30), ZIndex = 7,
		Color = Color3.fromRGB(218, 222, 248), Outline = 2.5,
	}, scale)

	for _, text in pairs(texts) do
		text.SetAlpha(0)
		local pop = Instance.new("UIScale")
		pop.Name = "Pop"
		pop.Parent = text.label
		text.pop = pop
	end
	reveal.texts = texts

	local newBadge = Instance.new("Frame")
	newBadge.Name = "NewDiscovery"
	newBadge.AnchorPoint = Vector2.new(0.5, 0.5)
	newBadge.Position = UDim2.fromOffset(DESIGN.X / 2, 40)
	newBadge.Size = UDim2.fromOffset(330, 54)
	newBadge.BackgroundColor3 = GOLD
	newBadge.Visible = false
	newBadge.ZIndex = 8
	newBadge.Parent = stage
	corner(newBadge)
	gradient(newBadge, Color3.fromRGB(255, 236, 130), Color3.fromRGB(255, 170, 40))
	stroke(newBadge, OUTLINE, 4 * scale)
	styledText(newBadge, { Text = "NEW DISCOVERY!", TextSize = 30, Size = UDim2.new(1, -16, 1, 0), ZIndex = 10, Outline = 3 }, scale)
	local badgePop = Instance.new("UIScale")
	badgePop.Parent = newBadge
	reveal.newBadge, reveal.badgePop = newBadge, badgePop

	-- Reel ---------------------------------------------------------------------
	local reel = Instance.new("CanvasGroup")
	reel.Name = "Reel"
	reel.AnchorPoint = Vector2.new(0.5, 0.5)
	reel.Position = UDim2.fromOffset(DESIGN.X / 2, HERO_Y - 25)   -- puts the window's centre on HERO_Y
	reel.Size = UDim2.fromOffset(1070, 330)
	reel.BackgroundTransparency = 1
	reel.GroupTransparency = 1
	reel.ZIndex = 5
	reel.Visible = false
	reel.Parent = stage
	local reelScale = Instance.new("UIScale")
	reelScale.Parent = reel
	reveal.reel, reveal.reelScale = reel, reelScale

	local reelTitle = styledText(reel, {
		Name = "ReelTitle", Text = "ROLLING MUTATION", TextSize = 34,
		Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.new(1, 0, 0, 44), ZIndex = 6,
		Gradient = ColorSequence.new(WHITE, Color3.fromRGB(200, 208, 255)),
	}, scale)
	reveal.reelTitle = reelTitle

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0, 190)
	panel.Size = UDim2.fromOffset(WINDOW_W + 44, WINDOW_H + 36)
	panel.BackgroundColor3 = Color3.fromRGB(26, 28, 62)
	panel.ZIndex = 5
	panel.Parent = reel
	corner(panel, UDim.new(0, 26))
	gradient(panel, Color3.fromRGB(44, 48, 104), Color3.fromRGB(18, 20, 46))
	stroke(panel, OUTLINE, 5 * scale)

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(WINDOW_W, WINDOW_H)
	window.BackgroundColor3 = Color3.fromRGB(8, 9, 24)
	window.ClipsDescendants = true
	window.ZIndex = 6
	window.Parent = panel
	corner(window, UDim.new(0, 18))

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.AnchorPoint = Vector2.new(0, 0.5)
	strip.Size = UDim2.fromOffset(REEL_CARDS * PITCH, CARD_H)
	strip.BackgroundTransparency = 1
	strip.ZIndex = 7
	strip.Parent = window

	local winIndex = REEL_CARDS - 5
	local order = reelOrder(rng, item.mutation, REEL_CARDS, winIndex)
	local cards = {}
	for i, id in ipairs(order) do
		cards[i] = makeReelCard(strip, id, (i - 1) * PITCH, 8, scale)
	end

	-- soft fade at both window edges
	for _, side in ipairs({ 0, 1 }) do
		local fade = Instance.new("Frame")
		fade.Name = "EdgeFade"
		fade.AnchorPoint = Vector2.new(side, 0)
		fade.Position = UDim2.fromScale(side, 0)
		fade.Size = UDim2.new(0, 150, 1, 0)
		fade.BackgroundColor3 = Color3.fromRGB(8, 9, 24)
		fade.BorderSizePixel = 0
		fade.ZIndex = 30
		fade.Parent = window
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new(if side == 0 then 0 else 1, if side == 0 then 1 else 0)
		g.Parent = fade
	end

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = BLACK
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.ZIndex = 31
	dim.Parent = window

	-- selection marker: a glowing line with a pointer above and below
	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.new(0, 6, 1, 0)
	marker.BackgroundColor3 = GOLD
	marker.BorderSizePixel = 0
	marker.ZIndex = 40
	marker.Parent = window
	local markerGradient = Instance.new("UIGradient")
	markerGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0.1),
	})
	markerGradient.Parent = marker
	reveal.marker = marker
	for _, y in ipairs({ -1, 1 }) do
		local pointer = Instance.new("Frame")
		pointer.Name = "Pointer"
		pointer.AnchorPoint = Vector2.new(0.5, 0.5)
		pointer.Position = UDim2.new(0.5, 0, 0.5, y * (WINDOW_H / 2 + 20))
		pointer.Size = UDim2.fromOffset(30, 30)
		pointer.Rotation = 45
		pointer.BackgroundColor3 = GOLD
		pointer.ZIndex = 8
		pointer.Parent = panel
		corner(pointer, UDim.new(0, 5))
		stroke(pointer, OUTLINE, 3.5 * scale)
	end

	local markerX = WINDOW_W / 2
	local function stripXFor(index, offset)
		return markerX - ((index - 1) * PITCH + CARD_W / 2) - offset
	end
	reveal.roll = {
		strip = strip, window = window, dim = dim, cards = cards, winIndex = winIndex,
		markerX = markerX,
		startX = stripXFor(4, 0),
		-- Brakes a little past the centre, then settles back onto it exactly.
		landX = stripXFor(winIndex, rng:NextNumber(0.06, 0.16) * CARD_W),
		finalX = stripXFor(winIndex, 0),
	}
	strip.Position = UDim2.new(0, reveal.roll.startX, 0.5, 0)

	-- Barrier: four quarter-plane shards meeting at the star --------------
	-- A square whose corner sits on the centre covers exactly a 90° wedge, so
	-- four of them tile the whole screen and can fly apart along the cracks.
	local barrier = Instance.new("Frame")
	barrier.Name = "Barrier"
	barrier.Size = UDim2.fromScale(1, 1)
	barrier.BackgroundTransparency = 1
	barrier.ZIndex = 10
	barrier.Visible = false
	barrier.Parent = root
	reveal.barrier = barrier

	local diagonal = screen.Magnitude
	local side = diagonal * 2.2
	local baseAngle = rng:NextNumber(10, 35)
	reveal.shards = {}
	for k = 0, 3 do
		local angle = baseAngle + k * 90
		local bisector = math.rad(angle + 45)
		local shard = Instance.new("Frame")
		shard.Name = "Shard"
		shard.AnchorPoint = Vector2.new(0.5, 0.5)
		shard.Size = UDim2.fromOffset(side, side)
		local offset = Vector2.new(math.cos(bisector), math.sin(bisector)) * (side / math.sqrt(2))
		shard.Position = UDim2.fromOffset(center.X + offset.X, center.Y + offset.Y)
		shard.Rotation = angle
		shard.BackgroundColor3 = DEEP:Lerp(main, 0.05 + 0.02 * k)
		shard.BorderSizePixel = 0
		shard.ZIndex = 10
		shard.Parent = barrier
		table.insert(reveal.shards, { frame = shard, direction = Vector2.new(math.cos(bisector), math.sin(bisector)), start = offset })
	end

	-- Star -----------------------------------------------------------------
	local starHolder = Instance.new("Frame")
	starHolder.Name = "StarBurst"
	starHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	starHolder.Position = UDim2.fromOffset(center.X, center.Y)
	starHolder.Size = UDim2.fromOffset(minDim * 0.62, minDim * 0.62)
	starHolder.BackgroundTransparency = 1
	starHolder.Rotation = 18
	starHolder.ZIndex = 20
	starHolder.Visible = false
	starHolder.Parent = root
	local starScale = Instance.new("UIScale")
	starScale.Scale = 0.02
	starScale.Parent = starHolder
	local boost = if mutation.Rarity == "Rare" then 1.15 elseif mutation.Rarity == "Mid" then 1.05 else 1
	local starGlow = circle(starHolder, "Glow", main, 0.82, 0.55 * boost, 20)
	circle(starHolder, "GlowInner", main:Lerp(WHITE, 0.3), 0.6, 0.2, 21)
	ray(starHolder, 1.0 * boost, 0.05, 0, main, 22, 0.9)
	ray(starHolder, 0.78 * boost, 0.045, 90, main, 22, 0.9)
	ray(starHolder, 0.9 * boost, 0.014, 0, main:Lerp(WHITE, 0.75), 23, 1)
	ray(starHolder, 0.7 * boost, 0.012, 90, main:Lerp(WHITE, 0.75), 23, 1)
	if mutation.Rarity ~= "Common" then
		ray(starHolder, 0.42, 0.01, 45, main:Lerp(WHITE, 0.5), 22, 0.6)
		ray(starHolder, 0.42, 0.01, -45, main:Lerp(WHITE, 0.5), 22, 0.6)
	end
	circle(starHolder, "Core", WHITE, 0, 0.045, 24)
	reveal.star = { holder = starHolder, scale = starScale, glow = starGlow }

	-- Cracks -----------------------------------------------------------------
	local crackLayer = Instance.new("Frame")
	crackLayer.Name = "Cracks"
	crackLayer.Size = UDim2.fromScale(1, 1)
	crackLayer.BackgroundTransparency = 1
	crackLayer.ZIndex = 15
	crackLayer.Visible = false
	crackLayer.Parent = root
	reveal.crackLayer = crackLayer
	reveal.cracks = {}

	local function addCrack(start, angle, length, thickness, delay)
		local pivot = Instance.new("Frame")
		pivot.Name = "Crack"
		pivot.AnchorPoint = Vector2.new(0.5, 0.5)
		pivot.Position = UDim2.fromOffset(start.X, start.Y)
		pivot.Size = UDim2.fromOffset(0, 0)
		pivot.Rotation = angle
		pivot.BackgroundTransparency = 1
		pivot.ZIndex = 15
		pivot.Parent = crackLayer

		local glowLine = Instance.new("Frame")
		glowLine.AnchorPoint = Vector2.new(0, 0.5)
		glowLine.Size = UDim2.fromOffset(0, math.max(thickness * 3.2, 3))
		glowLine.BackgroundColor3 = main
		glowLine.BackgroundTransparency = 0.55
		glowLine.BorderSizePixel = 0
		glowLine.ZIndex = 15
		glowLine.Parent = pivot
		corner(glowLine)

		local coreLine = Instance.new("Frame")
		coreLine.AnchorPoint = Vector2.new(0, 0.5)
		coreLine.Size = UDim2.fromOffset(0, math.max(thickness, 1.5))
		coreLine.BackgroundColor3 = main:Lerp(WHITE, 0.8)
		coreLine.BorderSizePixel = 0
		coreLine.ZIndex = 16
		coreLine.Parent = pivot
		corner(coreLine)

		table.insert(reveal.cracks, { glow = glowLine, core = coreLine, length = length, delay = delay })
		return start + Vector2.new(math.cos(math.rad(angle)), math.sin(math.rad(angle))) * length
	end

	local reach = diagonal * 0.55
	local branchCount = if mutation.Rarity == "Rare" then 10 elseif mutation.Rarity == "Mid" then 8 else 6
	for i = 1, branchCount do
		local aligned = i <= 4
		local angle = if aligned then baseAngle + (i - 1) * 90 else rng:NextNumber(0, 360)
		local position = center
		local thickness = minDim * 0.009
		local travelled = 0
		for step = 1, 3 do
			local length = reach * (0.2 + rng:NextNumber() * 0.14)
			local finish = addCrack(position, angle, length, thickness, travelled / reach)
			if step >= 2 and rng:NextNumber() < 0.65 then
				local turn = if rng:NextNumber() < 0.5 then -1 else 1
				addCrack(position:Lerp(finish, 0.4), angle + turn * rng:NextNumber(24, 48), length * 0.5, thickness * 0.55, (travelled + length * 0.4) / reach)
			end
			travelled += length
			position = finish
			angle += if aligned and step == 1 then 0 else rng:NextNumber(-16, 16)
			thickness *= 0.62
		end
	end

	local fx = Instance.new("Frame")
	fx.Name = "Effects"
	fx.Size = UDim2.fromScale(1, 1)
	fx.BackgroundTransparency = 1
	fx.ZIndex = 25
	fx.Parent = root
	reveal.fx = fx

	-- Buttons (inside the safe area, comfortable touch size) -----------------
	-- Bottom right: the main button (REVEAL NOW for pass owners, INSTANT REVEAL
	-- with the price for everyone else, CONTINUE once the result shows) and
	-- RETURN TO GAME beside it (above it on short screens). Bottom left, pass
	-- owners only: the AUTO toggle. refreshRevealButtons decides what shows.
	local buttonScale = math.clamp(scale, 0.8, 1.15)
	reveal.buttonScale = buttonScale
	reveal.safeOffset, reveal.safeSize = safeOffset, safeSize

	local main = cartoonButton(root, {
		Name = "Main", Text = "REVEAL NOW", Color = GOLD, TextSize = 26,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromOffset(safeOffset.X + safeSize.X - 18, safeOffset.Y + safeSize.Y - 18),
		Size = UDim2.fromOffset(270 * buttonScale, 68 * buttonScale), ZIndex = 40,
	}, buttonScale)
	main.button.Modal = true   -- frees a locked mouse so the buttons can be clicked
	main.sub = styledText(main.button, {
		Name = "Price", Text = "", TextSize = math.floor(17 * buttonScale),
		Position = UDim2.fromScale(0.5, 0.75), Size = UDim2.new(1, -14, 0.34, 0),
		ZIndex = main.button.ZIndex + 2, Outline = 2, Color = Color3.fromRGB(255, 248, 220), Shadow = false,
	}, buttonScale)
	main.sub.label.Visible = false
	reveal.mainButton = main

	local back = cartoonButton(root, {
		Name = "ReturnToGame", Text = "RETURN TO GAME", Color = Color3.fromRGB(96, 104, 170), TextSize = 20,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromOffset(safeOffset.X + safeSize.X - 18, safeOffset.Y + safeSize.Y - 18),
		Size = UDim2.fromOffset(200 * buttonScale, 54 * buttonScale), ZIndex = 40,
	}, buttonScale)
	placeText(back.text, UDim2.fromScale(0.5, 0.47), UDim2.new(1, -16, 1, -8), 20 * buttonScale)
	reveal.returnButton = back

	local auto = cartoonButton(root, {
		Name = "AutoInstant", Text = "AUTO INSTANT: OFF", Color = Color3.fromRGB(70, 76, 120), TextSize = 17,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset(safeOffset.X + 18, safeOffset.Y + safeSize.Y - 18),
		Size = UDim2.fromOffset(210 * buttonScale, 46 * buttonScale), ZIndex = 40,
	}, buttonScale)
	placeText(auto.text, UDim2.fromScale(0.5, 0.47), UDim2.new(1, -14, 1, -8), 17 * buttonScale)
	auto.button.Visible = false
	reveal.autoButton = auto

	return reveal
end

-- ----- per-frame animation (model spin, halo breathing, stars, finish motes) -----
local function startFrameLoop(reveal)
	local startedAt = os.clock()
	local connection = RunService.RenderStepped:Connect(function()
		local now = os.clock() - startedAt
		local camera = reveal.camera
		if reveal.model and camera then
			local radius = reveal.radius or 4
			local pixels = reveal.viewport.AbsoluteSize
			local vertical = math.rad(camera.FieldOfView*0.5)
			local half = math.min(vertical, math.atan(math.tan(vertical)*math.max(pixels.X,1)/math.max(pixels.Y,1)))
			local distance = radius / math.sin(half) * 1.1 * (reveal.zoom or 1)
			reveal.model:PivotTo(CFrame.Angles(math.rad(16), now * (if reduceMotion() then 0.15 else 0.45), 0))
			camera.CFrame = CFrame.lookAt(Vector3.new(0, distance * 0.28, distance), Vector3.zero)
		end

		if reveal.haloShown then
			local breathe = 0.5 + 0.5 * math.sin(now * 1.6)
			for index, ring in ipairs(reveal.haloRings) do
				local target = ring:GetAttribute("Target") or 0.8
				ring.BackgroundTransparency = math.clamp(target + (if index < 4 then 0.03 else 0.1) * breathe, 0, 1)
			end
		end

		for _, twinkle in ipairs(reveal.twinkles) do
			twinkle.frame.BackgroundTransparency = 0.25 + 0.65 * (0.5 + 0.5 * math.sin(now * 2.2 + twinkle.seed))
		end

		for _, mote in ipairs(reveal.motes) do
			mote.update(mote, now)
		end
	end)
	table.insert(reveal.connections, connection)
end

-- ----- mutation-specific finishes around the black hole (GUI only) -----
local FINISH = {
	charge = "orbitFast", dust = "gather", flare = "rays", crystals = "orbitDiamonds", vapor = "rise",
	flow = "inward", arcs = "flicker", prism = "spectrum", eclipse = "eclipse", stars = "twinkle",
	nova = "burst", singularity = "collapse",
}

local function addFinish(reveal)
	local mutation = reveal.mutation
	local kind = FINISH[mutation.Effect] or "orbitFast"
	local stage = reveal.hero
	local rng = reveal.rng
	local main = mutation.Main
	local calm = reduceMotion()
	local count = if mutation.Rarity == "Rare" then 14 elseif mutation.Rarity == "Mid" then 10 else 7
	if calm then count = math.ceil(count / 2) end

	local function mote(color, sizeScale, rotation)
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.fromScale(sizeScale, sizeScale)
		frame.SizeConstraint = Enum.SizeConstraint.RelativeYY
		frame.BackgroundColor3 = color
		frame.BorderSizePixel = 0
		frame.Rotation = rotation or 0
		frame.ZIndex = 5
		frame.Parent = stage
		if not rotation then corner(frame) end
		return frame
	end

	local function add(frame, update)
		table.insert(reveal.motes, { frame = frame, update = update, seed = rng:NextNumber() * math.pi * 2 })
	end

	if kind == "orbitFast" or kind == "orbitDiamonds" or kind == "spectrum" or kind == "twinkle" then
		for i = 1, count do
			local color = if kind == "spectrum" and mutation.Spectrum
				then mutation.Spectrum[(i - 1) % #mutation.Spectrum + 1]
				else (if i % 2 == 0 then main else main:Lerp(WHITE, 0.6))
			local diamond = kind == "orbitDiamonds" or kind == "twinkle"
			local frame = mote(color, if diamond then 0.03 else 0.018, if diamond then 45 else nil)
			local speed = if kind == "orbitFast" then 1.6 elseif kind == "twinkle" then 0.25 else 0.5
			add(frame, function(m, now)
				local angle = m.seed + now * speed * (if calm then 0.3 else 1)
				local radius = if kind == "spectrum" then 0.44 else 0.36 + 0.1 * math.sin(m.seed * 3)
				m.frame.Position = UDim2.fromScale(0.5 + math.cos(angle) * radius, 0.5 + math.sin(angle) * radius * 0.45)
				if kind == "twinkle" then
					m.frame.BackgroundTransparency = 0.2 + 0.7 * (0.5 + 0.5 * math.sin(now * 3 + m.seed * 5))
				end
			end)
		end
	elseif kind == "gather" or kind == "inward" or kind == "collapse" then
		for _ = 1, count do
			local frame = mote(if kind == "inward" then main else main:Lerp(WHITE, 0.5), if kind == "inward" then 0.012 else 0.016)
			add(frame, function(m, now)
				local period = if kind == "collapse" then 1.8 else 1.2
				local t = ((now + m.seed) % period) / period
				local radius = if kind == "gather" then 0.62 - 0.26 * math.min(t * 1.5, 1) else 0.66 * (1 - t)
				local angle = m.seed + (if kind == "inward" then t * 1.2 else t * 0.4)
				m.frame.Position = UDim2.fromScale(0.5 + math.cos(angle) * radius, 0.5 + math.sin(angle) * radius)
				m.frame.BackgroundTransparency = if kind == "gather" then 0.2 else 0.15 + 0.8 * (1 - t)
			end)
		end
	elseif kind == "rise" then
		for _ = 1, count do
			local frame = mote(main, 0.045)
			add(frame, function(m, now)
				local t = ((now * 0.35 + m.seed) % 1)
				m.frame.Position = UDim2.fromScale(0.5 + math.cos(m.seed * 7) * 0.3, 0.75 - t * 0.6)
				m.frame.BackgroundTransparency = 0.55 + 0.45 * t
			end)
		end
	elseif kind == "rays" or kind == "flicker" then
		for i = 1, (if kind == "rays" then 6 else count) do
			local line = Instance.new("Frame")
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.Position = UDim2.fromScale(0.5, 0.5)
			line.Size = UDim2.fromScale(if kind == "rays" then 1.25 else 0.18, 0.006)
			line.BackgroundColor3 = main:Lerp(WHITE, 0.4)
			line.BorderSizePixel = 0
			line.ZIndex = 3
			line.Parent = stage
			if kind == "rays" then
				local g = Instance.new("UIGradient")
				g.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.4),
					NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(0.65, 0.4), NumberSequenceKeypoint.new(1, 1),
				})
				g.Parent = line
			end
			add(line, function(m, now)
				if kind == "rays" then
					m.frame.Rotation = (i * 30) + now * (if calm then 2 else 8)
					m.frame.BackgroundTransparency = 0.35 + 0.3 * math.sin(now * 2 + i)
				else
					local angle = m.seed + math.floor(now * 3 + m.seed) * 1.7
					m.frame.Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.4, 0.5 + math.sin(angle) * 0.4)
					m.frame.Rotation = math.deg(angle) + 90
					m.frame.Visible = math.sin(now * 9 + m.seed * 4) > 0.55
				end
			end)
		end
	elseif kind == "eclipse" then
		local shadow = circle(stage, "EclipseShadow", BLACK, 0, 0.5, 3)
		add(shadow, function(m, now)
			local t = math.clamp(now / 1.4, 0, 1)
			local eased = 1 - (1 - t) ^ 3
			m.frame.Position = UDim2.fromScale(0.5 - 0.45 * (1 - eased) + 0.035, 0.48)
		end)
	elseif kind == "burst" then
		local ring = circle(stage, "NovaRing", main, 1, 0.3, 3)
		local ringStroke = stroke(ring, main:Lerp(WHITE, 0.5), 4 * reveal.scale)
		add(ring, function(m, now)
			local t = ((now % 2.2) / 0.9)
			local p = math.clamp(t, 0, 1)
			m.frame.Size = UDim2.fromScale(0.3 + 1.1 * p, 0.3 + 1.1 * p)
			ringStroke.Transparency = p
		end)
		for _ = 1, count do
			local frame = mote(main:Lerp(WHITE, 0.5), 0.014)
			add(frame, function(m, now)
				local t = math.clamp(((now + m.seed * 0.1) % 2.2 - 0.6) / 0.9, 0, 1)
				local radius = 0.7 * (1 - t) + 0.05
				m.frame.Position = UDim2.fromScale(0.5 + math.cos(m.seed) * radius, 0.5 + math.sin(m.seed) * radius)
				m.frame.BackgroundTransparency = 0.2 + 0.8 * t
			end)
		end
	end
end

-- ----- stage helpers -----
local function showTexts(reveal, instant)
	if instant then reveal.instantTexts = true end
	local order = { reveal.texts.rarity, reveal.texts.name, reveal.texts.odds, reveal.texts.bonus, reveal.texts.tier }
	for _, pill in ipairs(reveal.pills) do
		if instant then
			pill.frame.BackgroundTransparency = pill.fill or 0
			pill.stroke.Transparency = 0
		else
			tweenTo(pill.frame, 0.25, { BackgroundTransparency = pill.fill or 0 })
			tweenTo(pill.stroke, 0.25, { Transparency = 0 })
		end
	end
	for index, text in ipairs(order) do
		if instant then
			text.SetAlpha(1)
			text.pop.Scale = 1
		else
			task.delay((index - 1) * 0.1, function()
				if reveal.closed or reveal.instantTexts then return end
				local value = Instance.new("NumberValue")
				value.Value = 0
				value.Changed:Connect(function(alpha) text.SetAlpha(alpha) end)
				tweenTo(value, 0.24, { Value = 1 })
				Debris:AddItem(value, 0.5)
				if not reduceMotion() then text.pop.Scale = if index == 2 then 0.7 else 0.85 end
				tweenTo(text.pop, 0.34, { Scale = 1 }, Enum.EasingStyle.Back)
			end)
		end
	end
end

local function showNewBadge(reveal, instant)
	if reveal.item.isNew ~= true then return end
	reveal.newBadge.Visible = true
	if instant or reduceMotion() then
		reveal.badgePop.Scale = 1
	else
		reveal.badgePop.Scale = 0.4
		tweenTo(reveal.badgePop, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

-- The black hole is visible: its rarity accent now, the choir a moment later
-- (after the accent's first hit) with the ambience lowered underneath.
local function playChoir(reveal)
	if reveal.choirPlayed then return end
	reveal.choirPlayed = true
	cue(reveal, "Accent", ACCENT_SOUND[reveal.mutation.Rarity] or "COMMON_REVEAL_ID")
	local token = reveal.audioToken
	task.delay(cueDelay(reveal, AUDIO.Choir or {}), function()
		if reveal.closed or reveal.audioToken ~= token then return end
		if Sounds and reveal.ambience then pcall(Sounds.Duck, reveal.ambience, AUDIO.AmbienceDuck or 0.35, 0.4) end
	end)
	cue(reveal, "Choir")
end

-- Settled result: the end of the sequence, and where Skip lands.
local function showResultNow(reveal)
	root.BackgroundTransparency = 0
	reveal.scene.Visible = true
	reveal.stage.Visible = true
	reveal.barrier.Visible = false
	reveal.crackLayer.Visible = false
	reveal.star.holder.Visible = false
	reveal.fx:ClearAllChildren()
	reveal.reel.Visible = false
	reveal.hero.Visible = true
	reveal.heroScale.Scale = 1
	reveal.viewport.ImageTransparency = 0
	reveal.zoom = 1
	reveal.haloShown = true
	if #reveal.motes == 0 then pcall(addFinish, reveal) end
	showTexts(reveal, true)
	showNewBadge(reveal, true)
	playChoir(reveal)
end

-- The reel: fast start, long smooth slowdown, a tick each time a card edge
-- passes the marker, then a gentle settle onto the exact centre.
local function runRoll(reveal, duration)
	local roll = reveal.roll
	local calm = reduceMotion()
	if calm then duration = math.min(duration, 1.6) end
	local distance = roll.landX - roll.startX
	local started = os.clock()
	local lastIndex = math.floor((roll.markerX - roll.startX) / PITCH) + 1
	local slowed = false
	local popped = {}
	local lastFrame = started
	local tickQuiet = AUDIO.TickQuietSeconds or 0.3
	local tickGap = 1 / math.max(AUDIO.TickMaxPerSecond or 14, 1)
	local slowdownAt = (AUDIO.Slowdown and AUDIO.Slowdown.AtProgress) or 0.3
	local lastTickAt = -math.huge

	while true do
		if reveal.skip or reveal.closed then return false end
		local now = os.clock()
		local dt = now - lastFrame
		lastFrame = now
		local u = clamp01((now - started) / duration)
		local x = roll.startX + distance * (1 - (1 - u) ^ 4)
		roll.strip.Position = UDim2.new(0, x, 0.5, 0)

		local index = math.floor((roll.markerX - x) / PITCH) + 1
		if index ~= lastIndex then
			lastIndex = index
			local speed = math.abs(4 * distance / duration * (1 - u) ^ 3)
			-- A tick as a card crosses the marker; none under the start whoosh,
			-- and thinned out at full speed so they don't blur together.
			if now - started >= tickQuiet and now - lastTickAt >= tickGap then
				lastTickAt = now
				sfx("ROLL_TICK_IDS", { speed = 1 + math.clamp(1 - speed / 3000, 0, 1) * 0.12 })
			end
			local card = roll.cards[index]
			if card and speed < 1400 and not calm then
				card.pop.Scale = 1.06
				popped[card] = true
			end
		end
		for card in pairs(popped) do
			local s = card.pop.Scale
			s += (1 - s) * math.min(dt * 10, 1)
			if math.abs(s - 1) < 0.002 then
				s = 1
				popped[card] = nil
			end
			card.pop.Scale = s
		end
		if not slowed and u > slowdownAt then
			slowed = true
			cue(reveal, "Slowdown")
		end
		if u >= 1 then break end
		RunService.RenderStepped:Wait()
	end
	for card in pairs(popped) do card.pop.Scale = 1 end

	local settleStart = os.clock()
	local settleTime = if calm then 0.18 else 0.34
	while true do
		if reveal.skip or reveal.closed then return false end
		local u = clamp01((os.clock() - settleStart) / settleTime)
		local e = 0.5 - 0.5 * math.cos(math.pi * u)
		roll.strip.Position = UDim2.new(0, roll.landX + (roll.finalX - roll.landX) * e, 0.5, 0)
		if u >= 1 then break end
		RunService.RenderStepped:Wait()
	end
	roll.strip.Position = UDim2.new(0, roll.finalX, 0.5, 0)
	return true
end

-- The result card pops, the reel falls away and the black hole takes its place.
local function revealResult(reveal)
	local roll = reveal.roll
	local mutation = reveal.mutation
	local calm = reduceMotion()

	cue(reveal, "Lock")   -- the winning card has just settled

	-- lift the winning card above the dimmed reel
	local winner = roll.cards[roll.winIndex]
	if winner then
		winner.frame.Position = UDim2.new(0, roll.finalX + winner.x + CARD_W / 2, 0.5, 0)
		winner.frame.ZIndex = 35
		winner.frame.Parent = roll.window
		tweenTo(winner.pop, 0.32, { Scale = 1.14 }, Enum.EasingStyle.Back)
		tweenTo(winner.border, 0.2, { Color = mutation.Main:Lerp(WHITE, 0.35) })
	end
	tweenTo(roll.dim, 0.25, { BackgroundTransparency = 0.45 })
	tweenTo(reveal.marker, 0.15, { BackgroundColor3 = WHITE })
	reveal.reelTitle.SetText(string.upper(mutation.DisplayName) .. "!")
	reveal.reelTitle.label.TextColor3 = mutation.Main:Lerp(WHITE, 0.4)
	if not waitFor(reveal, if calm then 0.3 else 0.65) then return end

	-- flash and swap to the black hole
	local flash = circle(reveal.fx, "Flash", mutation.Main:Lerp(WHITE, 0.7), 0.15, 0.05, 25)
	flash.Position = UDim2.fromOffset(reveal.center.X, reveal.center.Y)
	flash.SizeConstraint = Enum.SizeConstraint.RelativeYY
	tweenTo(flash, 0.5, { Size = UDim2.fromScale(0.9, 0.9), BackgroundTransparency = 1 })

	tweenTo(reveal.reel, 0.28, { GroupTransparency = 1 })
	if not calm then tweenTo(reveal.reelScale, 0.28, { Scale = 1.08 }) end
	task.delay(0.3, function()
		if not reveal.closed then reveal.reel.Visible = false end
	end)

	reveal.hero.Visible = true
	reveal.heroScale.Scale = if calm then 1 else 0.6
	tweenTo(reveal.heroScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	reveal.zoom = 1.12
	tweenTo(reveal.viewport, 0.35, { ImageTransparency = 0 })
	for _, ring in ipairs(reveal.haloRings) do
		tweenTo(ring, 0.5, { BackgroundTransparency = ring:GetAttribute("Target") })
	end
	task.delay(0.5, function() reveal.haloShown = true end)
	local zoomValue = Instance.new("NumberValue")
	zoomValue.Value = 1.12
	zoomValue.Changed:Connect(function(value) reveal.zoom = value end)
	tweenTo(zoomValue, 0.7, { Value = 1 })
	Debris:AddItem(zoomValue, 1)

	playChoir(reveal)
	addFinish(reveal)
	showTexts(reveal, false)
	task.delay(0.35, function()
		if not reveal.closed and not reveal.instantTexts then showNewBadge(reveal, false) end
	end)
	waitFor(reveal, 0.55)
end

-- Picks what the bottom buttons say and lays them out. Called whenever the
-- stage, ownership, the price or the hide-buttons tap changes.
local function refreshRevealButtons(reveal)
	local main, back, auto = reveal.mainButton, reveal.returnButton, reveal.autoButton
	local s = reveal.buttonScale
	local owns = ownsInstantReveal()
	local shown = reveal.buttonsShown ~= false

	-- Never pretends: no price or purchase while ownership is unknown, and an
	-- unconfigured pass only shows a setup hint in Studio.
	local status = player:GetAttribute("InstantRevealStatus")
	local mode
	if reveal.settled then
		mode = "continue"
	elseif owns then
		mode = "reveal"
	elseif INSTANT_PASS_ID > 0 then
		if status == "checking" then
			mode = "checking"
		elseif status == "error" then
			mode = "unavailable"
		else
			mode = "buy"
		end
	elseif RunService:IsStudio() then
		mode = "setup"
	else
		mode = "none"
	end
	if RunService:IsStudio() and reveal.lastLoggedMode ~= mode then
		reveal.lastLoggedMode = mode
		local reasons = {
			reveal = "you own the pass", buy = "the pass is set up and you don't own it",
			checking = "InstantRevealServer is still asking Roblox", unavailable = "Roblox didn't answer the ownership check",
			setup = "MutationConfig.InstantReveal.GamepassId is 0 (this hint is Studio only; live players see nothing)",
			continue = "the result is showing", none = "not set up",
		}
		print(("[MutationClient] Instant Reveal button: %s (%s). Pass id %d, status %s."):format(
			mode, reasons[mode] or "?", INSTANT_PASS_ID, tostring(status)))
	end
	reveal.mainMode = mode

	main.button.Visible = shown and mode ~= "none"
	if mode == "buy" or mode == "checking" or mode == "unavailable" or mode == "setup" then
		local enabled = mode == "buy"
		paintButton(main, if enabled then Color3.fromRGB(255, 146, 40) else Color3.fromRGB(92, 98, 132))
		main.text.SetText("⚡ INSTANT REVEAL")
		placeText(main.text, UDim2.fromScale(0.5, 0.36), UDim2.new(1, -14, 0.5, 0), 22 * s)
		local sub
		if mode == "buy" then
			sub = if passPrice then ("R$ %d  ·  permanent"):format(passPrice) else "Permanent game pass"
		elseif mode == "checking" then
			sub = "Checking your pass…"
		elseif mode == "unavailable" then
			sub = "Couldn't check your pass"
		else
			sub = "Studio: set GamepassId"
		end
		main.sub.SetText(sub)
		main.sub.label.Visible = true
	else
		if mode == "continue" then
			paintButton(main, GREEN)
			main.text.SetText("CONTINUE")
		else
			paintButton(main, GOLD:Lerp(Color3.fromRGB(255, 150, 40), 0.35))
			main.text.SetText("REVEAL NOW")
		end
		placeText(main.text, UDim2.fromScale(0.5, 0.47), UDim2.new(1, -16, 1, -8), 26 * s)
		main.sub.label.Visible = false
	end

	-- RETURN TO GAME until the result settles (CONTINUE does the same job then).
	back.button.Visible = shown and not reveal.settled
	local right = reveal.safeOffset.X + reveal.safeSize.X - 18
	local bottom = reveal.safeOffset.Y + reveal.safeSize.Y - 18
	local mainSize = main.button.Size
	-- Re-placed every time, so the buttons follow a window resize.
	main.button.Position = UDim2.fromOffset(right, bottom)
	auto.button.Position = UDim2.fromOffset(reveal.safeOffset.X + 18, bottom)
	if mode == "none" then
		back.button.Position = UDim2.fromOffset(right, bottom)
	elseif reveal.safeSize.Y < 600 then
		back.button.Position = UDim2.fromOffset(right, bottom - mainSize.Y.Offset - 10 * s)
	else
		local lift = (mainSize.Y.Offset - back.button.Size.Y.Offset) / 2
		back.button.Position = UDim2.fromOffset(right - mainSize.X.Offset - 14 * s, bottom - lift)
	end

	auto.button.Visible = shown and owns
	local on = autoInstantReveal()
	auto.text.SetText(if on then "AUTO INSTANT: ON" else "AUTO INSTANT: OFF")
	paintButton(auto, if on then GREEN:Lerp(BLACK, 0.2) else Color3.fromRGB(70, 76, 120))
end

local function playReveal(item)
	local mutation = MutationConfig.Get(item.mutation)
	local quick = item.isNew ~= true or item.backlog == true
	local timings = if quick then REVEAL.Quick else (REVEAL[mutation.Rarity] or REVEAL.Common)
	local calm = reduceMotion()

	local previousSelection = GuiService.SelectedObject
	revealGui.Enabled = true
	root.BackgroundTransparency = 1

	local reveal = buildReveal(item)
	current = reveal
	reveal.startedAt = os.clock()
	loadPassPrice()
	if Coordinator then Coordinator.SetCinematic("MutationReveal", true) end

	-- Keep the stage centred and fitted if the window or safe area changes.
	local function relayout()
		if reveal.closed then return end
		local screen = screenSize()
		local safeOffset, safeSize = Vector2.zero, screen
		if UiResponsive and UiResponsive.SafeRect then
			safeOffset, safeSize = UiResponsive.SafeRect()
		end
		local scale = math.clamp(math.min((safeSize.X - 12) / DESIGN.X, (safeSize.Y - 12) / DESIGN.Y), 0.4, 1.4)
		reveal.scale = scale
		reveal.stageScale.Scale = scale
		reveal.center = screen / 2 + Vector2.new(0, (HERO_Y - DESIGN.Y / 2) * scale)
		reveal.safeOffset, reveal.safeSize = safeOffset, safeSize
		refreshRevealButtons(reveal)
	end
	if workspace.CurrentCamera then
		table.insert(reveal.connections, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(relayout)
		end))
	end
	if UiResponsive and UiResponsive.Changed then
		table.insert(reveal.connections, UiResponsive.Changed:Connect(relayout))
	end

	-- REVEAL NOW: pass owners only (checked again here, not just by the button).
	local function revealNow()
		if reveal.closed or reveal.settled or not ownsInstantReveal() then return end
		reveal.skip = true
	end
	-- Free for everyone, at any time. Before the result shows, a short message
	-- says what landed on the base instead.
	local function returnToGame()
		if reveal.closed then return end
		if not reveal.settled then item.returned = true end
		reveal.closed = true
	end
	local function onMain()
		if reveal.closed then return end
		if reveal.mainMode == "continue" then
			if reveal.settled then reveal.closed = true end
		elseif reveal.mainMode == "reveal" then
			revealNow()
		elseif reveal.mainMode == "buy" then
			promptInstantReveal()
		elseif reveal.mainMode == "setup" then
			warn("[MutationClient] Instant Reveal isn't set up: create the game pass, then put its id in MutationConfig.InstantReveal.GamepassId (see README).")
		end
	end
	reveal.mainButton.button.Activated:Connect(onMain)
	reveal.returnButton.button.Activated:Connect(returnToGame)
	reveal.autoButton.button.Activated:Connect(function()
		if not ownsInstantReveal() or not Settings or not Settings.Set then return end
		Settings.Set("AutoInstantReveal", not autoInstantReveal())
		refreshRevealButtons(reveal)
	end)
	-- A purchase mid-reveal turns the button into REVEAL NOW straight away.
	table.insert(reveal.connections, player:GetAttributeChangedSignal("InstantRevealOwned"):Connect(function()
		if not reveal.closed then refreshRevealButtons(reveal) end
	end))
	table.insert(reveal.connections, player:GetAttributeChangedSignal("InstantRevealStatus"):Connect(function()
		if not reveal.closed then refreshRevealButtons(reveal) end
	end))
	table.insert(reveal.connections, priceLoaded.Event:Connect(function()
		if not reveal.closed then refreshRevealButtons(reveal) end
	end))
	refreshRevealButtons(reveal)

	table.insert(reveal.connections, UserInputService.InputBegan:Connect(function(input, processed)
		if purchasePromptOpen then return end
		if processed and input.UserInputType == Enum.UserInputType.Keyboard then return end
		local key = input.KeyCode
		-- A gamepad's A already presses the selected button, so it's handled here
		-- only when nothing in the reveal is selected. Keys never open a purchase.
		local selected = GuiService.SelectedObject
		local selectionHere = selected ~= nil and selected:IsDescendantOf(revealGui)
		if key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Backspace then
			returnToGame()
		elseif key == Enum.KeyCode.Space or key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter
			or (key == Enum.KeyCode.ButtonA and not selectionHere) then
			if reveal.settled then
				reveal.closed = true
			else
				revealNow()
			end
		end
	end))
	-- Respawning doesn't close it: the overlay doesn't depend on the character.
	if UiResponsive and UiResponsive.IsGamepad() then
		GuiService.SelectedObject = if ownsInstantReveal() then reveal.mainButton.button else reveal.returnButton.button
	end

	-- Pass owners with AUTO on go straight to the result.
	if autoInstantReveal() then reveal.skip = true end

	startFrameLoop(reveal)
	reveal.ambience = sfx("REVEAL_AMBIENCE_ID", { sequence = reveal.sequenceId })   -- not a transient cue: skipping keeps it
	table.insert(reveal.cueLog, { name = "Ambience", slot = "REVEAL_AMBIENCE_ID", intended = 0, status = if reveal.ambience then "played" else "silent",
		actual = if reveal.ambience then 0 else nil })

	local ran, err = pcall(function()
		-- A: darken
		tweenTo(root, timings.Dark, { BackgroundTransparency = 0 })
		if not waitFor(reveal, timings.Dark) then return end
		root.BackgroundTransparency = 0
		reveal.scene.Visible = true
		reveal.stage.Visible = true
		reveal.barrier.Visible = true

		-- B: the star builds, turns and pulls in before the impact
		local star = reveal.star
		star.holder.Visible = true
		star.scale.Scale = 0.02
		local gather = timings.Star * 0.8
		tweenTo(star.scale, gather, { Scale = 1 }, Enum.EasingStyle.Quart)
		if not calm then
			tweenTo(star.holder, timings.Star, { Rotation = 34 }, Enum.EasingStyle.Sine)
		end
		cue(reveal, "StarCharge")
		if not waitFor(reveal, gather) then return end
		tweenTo(star.scale, timings.Star * 0.2, { Scale = 0.72 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenTo(star.glow, timings.Star * 0.2, { BackgroundTransparency = 0.95 })
		if not waitFor(reveal, timings.Star * 0.2) then return end
		if timings.Pause and not quick then
			if not waitFor(reveal, timings.Pause) then return end
		end

		-- C: cracks spread from the star
		star.holder.Visible = false
		reveal.crackLayer.Visible = true
		fadeSound(reveal.cueSounds.StarCharge, (AUDIO.StarCharge and AUDIO.StarCharge.FadeOut) or 0.15)
		cue(reveal, "Crack")
		local pulse = circle(reveal.fx, "Impact", mutation.Main:Lerp(WHITE, 0.6), 0.2, 0.02, 25)
		pulse.Position = UDim2.fromOffset(reveal.center.X, reveal.center.Y)
		pulse.SizeConstraint = Enum.SizeConstraint.RelativeYY
		tweenTo(pulse, timings.Fracture + 0.2, { Size = UDim2.fromScale(0.35, 0.35), BackgroundTransparency = 1 })
		for _, crack in ipairs(reveal.cracks) do
			if calm then
				crack.core.Size = UDim2.fromOffset(crack.length, crack.core.Size.Y.Offset)
				crack.glow.Size = UDim2.fromOffset(crack.length, crack.glow.Size.Y.Offset)
				crack.core.BackgroundTransparency = 1
				crack.glow.BackgroundTransparency = 1
				tweenTo(crack.core, timings.Fracture, { BackgroundTransparency = 0 })
				tweenTo(crack.glow, timings.Fracture, { BackgroundTransparency = 0.55 })
			else
				local delay = crack.delay * timings.Fracture * 0.8
				local grow = math.max(timings.Fracture - delay, 0.05)
				task.delay(delay, function()
					if reveal.skip or reveal.closed then return end
					tweenTo(crack.core, grow, { Size = UDim2.fromOffset(crack.length, crack.core.Size.Y.Offset) })
					tweenTo(crack.glow, grow, { Size = UDim2.fromOffset(crack.length, crack.glow.Size.Y.Offset) })
				end)
			end
		end
		if not waitFor(reveal, timings.Fracture) then return end

		-- D: shatter; the reel is waiting underneath
		if Sounds and reveal.cueSounds.Crack then
			pcall(Sounds.Duck, reveal.cueSounds.Crack, (AUDIO.Shatter and AUDIO.Shatter.DuckCrack) or 0.45, 0.2)
		end
		cue(reveal, "Shatter")
		for _, crack in ipairs(reveal.cracks) do
			tweenTo(crack.core, 0.16, { BackgroundTransparency = 1 })
			tweenTo(crack.glow, 0.16, { BackgroundTransparency = 1 })
		end
		for index, shard in ipairs(reveal.shards) do
			local frame = shard.frame
			if calm then
				tweenTo(frame, timings.Shatter, { BackgroundTransparency = 1 })
			else
				local target = reveal.center + shard.start + shard.direction * reveal.minDim * 0.9
				tweenTo(frame, timings.Shatter, {
					Position = UDim2.fromOffset(target.X, target.Y),
					Rotation = frame.Rotation + (if index % 2 == 0 then 9 else -9),
				}, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
				tweenTo(frame, timings.Shatter, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end
		if not calm then
			for _ = 1, (timings.Debris or 10) do
				local piece = Instance.new("Frame")
				local pieceSize = reveal.minDim * reveal.rng:NextNumber(0.012, 0.03)
				piece.AnchorPoint = Vector2.new(0.5, 0.5)
				piece.Size = UDim2.fromOffset(pieceSize, pieceSize)
				piece.Position = UDim2.fromOffset(reveal.center.X, reveal.center.Y)
				piece.Rotation = reveal.rng:NextNumber(0, 90)
				piece.BackgroundColor3 = mutation.Main:Lerp(WHITE, reveal.rng:NextNumber(0.2, 0.7))
				piece.BorderSizePixel = 0
				piece.ZIndex = 26
				piece.Parent = reveal.fx
				local angle = reveal.rng:NextNumber(0, math.pi * 2)
				local distance = reveal.minDim * reveal.rng:NextNumber(0.35, 0.75)
				tweenTo(piece, timings.Shatter + 0.25, {
					Position = UDim2.fromOffset(reveal.center.X + math.cos(angle) * distance, reveal.center.Y + math.sin(angle) * distance),
					Rotation = piece.Rotation + reveal.rng:NextNumber(-200, 200),
					BackgroundTransparency = 1,
				}, Enum.EasingStyle.Quart)
			end
		end

		reveal.reel.Visible = true
		reveal.reelScale.Scale = if calm then 1 else 0.88
		tweenTo(reveal.reel, 0.3, { GroupTransparency = 0 })
		tweenTo(reveal.reelScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		cue(reveal, "ReelOpen")
		if not waitFor(reveal, timings.Shatter) then return end
		reveal.barrier.Visible = false
		reveal.crackLayer.Visible = false

		-- E: the reel spins and lands on the committed result
		cue(reveal, "RollStart")
		if not runRoll(reveal, timings.Roll) then return end

		-- F: the mutated black hole
		revealResult(reveal)
	end)
	if not ran then
		warn("[MutationClient] Reveal animation hit an error; showing the result directly.", err)
	end

	-- Settled result (also where REVEAL NOW lands).
	for _, tween in ipairs(reveal.tweens) do tween:Cancel() end
	table.clear(reveal.tweens)
	if reveal.skip and not reveal.closed then
		cancelCues(reveal)   -- nothing from the skipped part plays late
	end
	if not reveal.closed then
		pcall(showResultNow, reveal)
		reveal.settled = true
		reveal.skip = false
		refreshRevealButtons(reveal)
		if UiResponsive and UiResponsive.IsGamepad() then
			GuiService.SelectedObject = reveal.mainButton.button
		end
		-- Stays until the player presses CONTINUE (or A / B / Space / Enter), so
		-- there's time for screenshots and clips. A tap on empty space hides the
		-- buttons and hint; another tap brings them back.
		-- The hint fits between the bottom-left and bottom-right buttons.
		local sideRoom = reveal.mainButton.button.Size.X.Offset + 30
		local hintWidth = math.clamp(reveal.safeSize.X - sideRoom * 2, 220, 420)
		local hint = styledText(root, {
			Name = "HideHint", Text = "Tap anywhere to hide buttons", TextSize = math.floor(20 * math.clamp(hintWidth / 420, 0.7, 1)),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(reveal.safeOffset.X + reveal.safeSize.X / 2, reveal.safeOffset.Y + reveal.safeSize.Y - 24),
			Size = UDim2.fromOffset(hintWidth, 28),
			Color = Color3.fromRGB(170, 180, 220), ZIndex = 39, Outline = 2,
		})
		local catcher = Instance.new("TextButton")
		catcher.Name = "HideButtons"
		catcher.Size = UDim2.fromScale(1, 1)
		catcher.BackgroundTransparency = 1
		catcher.Text = ""
		catcher.ZIndex = 35
		catcher.Parent = root
		catcher.Activated:Connect(function()
			reveal.buttonsShown = reveal.buttonsShown == false
			refreshRevealButtons(reveal)
			hint.label.Visible = reveal.buttonsShown
			if hint.shadow then hint.shadow.Visible = reveal.buttonsShown end
		end)
		task.delay(4, function()
			if not reveal.closed then
				local fade = Instance.new("NumberValue")
				fade.Value = 1
				fade.Changed:Connect(function(alpha) hint.SetAlpha(alpha) end)
				TweenService:Create(fade, TweenInfo.new(0.6), { Value = 0 }):Play()
				Debris:AddItem(fade, 1)
			end
		end)
		while not reveal.closed do
			RunService.RenderStepped:Wait()
		end
	end

	-- Cleanup: restore exactly what was there before.
	reveal.closed = true
	reveal.audioToken += 1
	printTimeline(reveal)
	fadeSound(reveal.ambience, 0.4)
	for _, sound in ipairs(reveal.sounds) do fadeSound(sound, 0.35) end
	for _, connection in ipairs(reveal.connections) do connection:Disconnect() end
	reveal.stage.Visible = false
	reveal.scene.Visible = false
	local fade = TweenService:Create(root, TweenInfo.new(0.2), { BackgroundTransparency = 1 })
	fade:Play()
	task.wait(0.2)
	root:ClearAllChildren()
	revealGui.Enabled = false
	current = nil
	if Coordinator then Coordinator.SetCinematic("MutationReveal", false) end

	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(revealGui) then
		GuiService.SelectedObject = nil
	end
	if previousSelection and previousSelection.Parent and previousSelection:IsDescendantOf(game) then
		GuiService.SelectedObject = previousSelection
	end
end

-- ----- queue -----
local queue = {}
local running = false
local overflow = 0

local toastGui = Instance.new("ScreenGui")
toastGui.Name = "MutationToast"
toastGui.ResetOnSpawn = false
toastGui.IgnoreGuiInset = true
toastGui.DisplayOrder = 71
toastGui.Parent = playerGui
local toast = styledText(toastGui, {
	Name = "Toast", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.2, 0),
	Size = UDim2.fromOffset(560, 40), TextSize = 28, Color = Color3.fromRGB(255, 226, 120),
})
toast.label.Visible = false
if toast.shadow then toast.shadow.Visible = false end
for _, label in ipairs({ toast.label, toast.shadow }) do
	label.TextScaled = true
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 28
	cap.MinTextSize = 14
	cap.Parent = label
end

local function showToast(text)
	toast.SetText(text)
	toast.SetAlpha(1)
	toast.label.Visible = true
	if toast.shadow then toast.shadow.Visible = true end
	task.delay(3, function()
		for step = 1, 10 do
			toast.SetAlpha(1 - step / 10)
			task.wait(0.04)
		end
		toast.label.Visible = false
		if toast.shadow then toast.shadow.Visible = false end
	end)
end

local function runQueue()
	if running then return end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local item = table.remove(queue, 1)
			local wait = (item.receivedAt + (item.delay or 0)) - os.clock()
			if wait > 0 then task.wait(wait) end
			-- A backlog plays the short version so nobody gets stuck watching.
			if #queue > 0 then
				for _, waiting in ipairs(queue) do waiting.backlog = true end
			end
			local ok, err = pcall(playReveal, item)
			if not ok then
				warn("[MutationClient] Reveal failed:", err)
				if current then
					current.closed = true
					for _, sound in ipairs(current.sounds) do fadeSound(sound, 0.2) end
					fadeSound(current.ambience, 0.2)
					for _, connection in ipairs(current.connections) do connection:Disconnect() end
				end
				revealGui.Enabled = false
				root:ClearAllChildren()
				current = nil
				if Coordinator then Coordinator.SetCinematic("MutationReveal", false) end
			elseif item.returned then
				local mutation = MutationConfig.Get(item.mutation)
				if mutation then
					showToast(("✦ %s (%s) was added to your base!"):format(
						string.upper(mutation.DisplayName), MutationConfig.OddsText(item.oneIn)))
				end
			end
		end
		running = false
		if overflow > 0 then
			showToast(("+%d more mutation%s landed on your base!"):format(overflow, if overflow == 1 then "" else "s"))
			overflow = 0
		end
	end)
end

-- ===================== STUDIO TESTING =====================
-- M: the next merge rolls the next mutation in the list (server, Studio only).
-- P: preview a reveal (Shift+P: the short repeat version). Nothing is saved.
-- F: preview the merge animation in front of you (nothing is merged).
if RunService:IsStudio() then
	local order = MutationConfig.Order
	local forceIndex, previewIndex = 0, 0
	print(("[Mutations] Studio: M = force next merge's mutation, P = preview reveal (Shift+P short), F = preview merge, "
		.. "X = toggle Instant Reveal pass (this session). %.3f%% of merges mutate. Instant Reveal pass: %s."):format(
			(MutationConfig.TotalChance and MutationConfig.TotalChance() or 0) * 100,
			if INSTANT_PASS_ID > 0 then tostring(INSTANT_PASS_ID) else "not configured (purchase button hidden)"))
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.M then
			local debugRemote = remotes:FindFirstChild("DebugForceMutation")
			if not debugRemote then return end
			forceIndex = forceIndex % #order + 1
			debugRemote:FireServer(order[forceIndex])
			print("[Mutations] Next merge will be:", order[forceIndex])
		elseif input.KeyCode == Enum.KeyCode.P then
			previewIndex = previewIndex % #order + 1
			local mutation = MutationConfig.Mutations[order[previewIndex]]
			local short = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			table.insert(queue, {
				mutation = order[previewIndex], oneIn = mutation.OneIn, tier = 20,
				tierName = "Preview Black Hole", isNew = not short, delay = 0, receivedAt = os.clock(),
			})
			runQueue()
		elseif input.KeyCode == Enum.KeyCode.X then
			local toggle = instantRemotes and instantRemotes:FindFirstChild("DebugToggle")
			if toggle then
				toggle:FireServer()
			else
				warn("[Mutations] InstantRevealServer isn't running, so the pass can't be toggled.")
			end
		elseif input.KeyCode == Enum.KeyCode.F then
			local character = player.Character
			local humanoidRoot = character and character:FindFirstChild("HumanoidRootPart")
			if not humanoidRoot then return end
			local flat = humanoidRoot.CFrame.LookVector * Vector3.new(1, 0, 1)
			local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
			local right = humanoidRoot.CFrame.RightVector
			local center = humanoidRoot.Position + forward * 14 + Vector3.new(0, 1, 0)
			local ok, err = pcall(playFusion, {
				ownerUserId = player.UserId, resultTier = 6, mutation = "",
				resultPosition = center, duration = REVEAL.WorldFusionSeconds,
				sources = {
					{ position = center - right * 3 + Vector3.new(0, 2, 0), tier = 5, mutation = "" },
					{ position = center + right * 3, tier = 5, mutation = "" },
				},
			})
			if not ok then warn("[Mutations] Merge preview failed:", err) end
		end
	end)
end

mutationResult.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local mutation = MutationConfig.Get(payload.mutation)
	if not mutation then return end
	local item = {
		mutation = payload.mutation,
		oneIn = tonumber(payload.oneIn) or mutation.OneIn,   -- the odds the server rolled with
		tier = math.clamp(math.floor(tonumber(payload.tier) or 1), 1, 48),
		tierName = payload.tierName,
		sizeMultiplier = SizeVariants.Read(payload.sizeMultiplier),
		isNew = payload.isNew == true,
		delay = math.clamp(tonumber(payload.delay) or 0, 0, 3),
		luck = tonumber(payload.luck) or 1,
		receivedAt = os.clock(),
	}
	if #queue >= (REVEAL.MaxQueue or 3) then
		overflow += 1
		return
	end
	table.insert(queue, item)
	runQueue()
end)
