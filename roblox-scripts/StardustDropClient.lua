-- StardustDropClient (LocalScript in StarterPlayer > StarterPlayerScripts)
-- Draws the Stardust pickups that BlackHoleSystemServer spawns on bases and
-- makes collecting them feel great. PRESENTATION ONLY: the server spawns
-- every piece, decides who collects it and pays each one exactly once. Nothing
-- here can add Stardust.
--
-- WHAT YOU SEE
--   Showers   a drop event bursts out of a black hole as 5-18 pieces (the
--             server splits the value; the pieces add up to it exactly).
--   Magnet    SOFT range (1.3x): your pieces lean towards you.
--             HARD range (Currency Magnet range): a piece pops, then is
--             pulled in - accelerating, curving (no two paths alike), with a
--             short glowing trail - and snaps into you, shrinking.
--   Feel      sounds, streak, combo meter, milestones, magnet stream loop,
--             gain label and HUD pulses all live in CurrencyFeedback
--             (tuning: CurrencyFeedbackConfig). This script only tells it
--             when a piece arrives and how many are flying.
--   Combo     the combo BONUS is paid by the server; the meter shows it.
--   Mega      the rare Mega Stardust: big, glowing, slow spin, own sound.
--   Ring      buying Currency Magnet shows a ring of your new range.
--
-- PREDICTION: a piece starts flying the moment you're inside the server's
-- range (same formula, UpgradeConfig.GetMagnetRange), without waiting. If the
-- server never confirms it, the piece comes back.
--
-- PERFORMANCE: every piece's parts are pooled and reused (nothing is created
-- or destroyed per pickup); one RenderStepped loop runs only while something
-- is on screen; at most MAX_VISIBLE pieces are drawn (fewer on lower
-- graphics). Rewards never depend on what is drawn.
--
-- MUST be a LocalScript.

local RunService = game:GetService("RunService")
if not RunService:IsClient() then
	warn("[StardustDropClient] This must be a LocalScript in StarterPlayer > StarterPlayerScripts, not a Script. It did nothing.")
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local function optional(name)
	local module = ReplicatedStorage:FindFirstChild(name)
	local ok, result = pcall(function() return module and require(module) end)
	return if ok and type(result) == "table" then result else nil
end

local Settings = optional("ClientSettings")
local Sounds = optional("GameSounds")
local Format = optional("NumberFormatter")
local GemsConfig = optional("GemsConfig")
local UpgradeConfig = optional("UpgradeConfig")
-- ===================== COLLECTION FEEDBACK =====================
-- Built in here (it was a separate CurrencyFeedback module, which could go
-- missing and leave pickups silent). Tuning: ReplicatedStorage >
-- CurrencyFeedbackConfig if present, otherwise the same values built in.
--   Beats       pickups arriving together are ONE sound (at most ~12 a
--               second), a step up a capped pitch ladder, every 4th beat the
--               bright accent; bigger pieces sound bigger; Mega has its own.
--   Budget      at most 5 pickup sounds at once; mega > milestone > finisher
--               > beat > tiny.
--   Streak      x10 / x25 / x50 / x100 milestones (once per streak), a
--               finisher when a 25+ streak ends.
--   Magnet      one looped stream sound + inflowing sparks, one whoosh.
--   Meter       the COMBO meter (own panel): streak, server bonus, timer.
--   Gain        one "+★4B" label over your head adding up the streak.
-- Presentation only: the server pays every piece and the combo bonus.
local Feedback = (function()
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")
	local HapticService = game:GetService("HapticService")
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")

	local Feedback = {}
	if not RunService:IsClient() then return Feedback end

	local function optional(name)
		local module = ReplicatedStorage:FindFirstChild(name)
		local ok, result = pcall(function() return module and require(module) end)
		return if ok and type(result) == "table" then result else nil
	end

	-- ReplicatedStorage.CurrencyFeedbackConfig overrides these built-in values
	-- when it is there (the server reads the same module for the combo bonus).
	local Config = optional("CurrencyFeedbackConfig") or (function()
	local Config = {}

	-- ===== STREAK =====
	Config.ComboWindow = 0.8        -- a pickup this soon after the last one continues the streak
	Config.ComboResetTime = 1.1     -- the streak ends after this long without a pickup

	-- ===== COMBO REWARD (server-authoritative) =====
	-- The server keeps its own streak of pieces collected. Every StepEvery pieces
	-- in a streak adds StepBonus to that piece's value, up to MaxBonus.
	--   x10 +5%   x20 +10%   ...   x100 +50% (cap)
	-- Only pickup pieces get it - never passive income. Collecting a piece is
	-- still the only way to earn it, so a combo can't be faked by the client.
	Config.Combo = {
		Enabled = true,
		StepEvery = 10,
		StepBonus = 0.05,
		MaxBonus = 0.50,
		-- A little more lenient than the client's timer, because the server
		-- collects in 0.1 s ticks.
		ServerResetTime = 1.4,
	}

	function Config.GetComboBonus(combo)
		local c = Config.Combo
		if not c.Enabled then return 0 end
		local steps = math.floor(math.max(tonumber(combo) or 0, 0) / c.StepEvery)
		return math.min(steps * c.StepBonus, c.MaxBonus)
	end

	-- ===== SOUND RHYTHM =====
	-- Pickups are grouped into BEATS: everything collected inside one beat is
	-- one sound. That turns 50 coins in a second into a rhythm, not 50 sounds.
	Config.SoundInterval = 0.085        -- seconds between beats (~12 a second at most)
	Config.BusyInterval = 0.115         -- beat spacing once the streak passes BusyFrom (~9 a second)
	Config.BusyFrom = 40
	Config.MaxConcurrentSounds = 5      -- pickup-family sounds playing at once
	Config.AccentEvery = 4              -- every 4th beat is the brighter accent ("tick tick tick TING")

	-- Pitch ladder: each beat is a step up, capped; a pause relaxes it and the
	-- end of a streak resets it.
	Config.BasePitch = 0.96
	Config.PitchStep = 0.025
	Config.MaxPitch = 1.18
	Config.PitchJitter = 0.008          -- tiny random detune so repeats never sound identical
	Config.PitchRelaxAfter = 0.45       -- a gap this long drops the ladder halfway

	-- The pickup sound family (GameSounds slots). Several ids per slot are
	-- picked at random, never the same twice in a row.
	Config.Sounds = {
		Soft = "PICKUP_SOFT_IDS",        -- normal tick
		Bright = "PICKUP_BRIGHT_IDS",    -- the accent / medium-value pickup
		MagnetWhoosh = "MAGNET_WHOOSH_ID",   -- once, when a pull starts after a quiet moment
		MagnetStream = "MAGNET_STREAM_ID",   -- ONE looped sound, louder with more coins in flight
		Mega = "REWARD_CLAIM_ID",
	}

	-- Value-aware feedback. Pieces are compared with the configured drop kinds
	-- (ProgressionConfig.Drops.Kinds), never with anyone's wallet.
	--   coin  light tick         bar  brighter pickup
	--   gem   (Star Crystal) low + bright layered chime
	--   mega  its own sparkle impact
	Config.KindWeight = { coin = 1, bar = 2, gem = 3, mega = 4 }

	-- Priority when the sound budget is full (lower number wins):
	-- 1 mega, 2 milestone, 3 finisher, 4 rhythmic beat, 5 tiny beat.
	Config.Priority = { Mega = 1, Milestone = 2, Finisher = 3, Beat = 4, Tiny = 5 }

	-- ===== STREAK TIERS =====
	-- Pieces in the streak -> tier. Tiers drive sound brightness, sparkles,
	-- trail length and HUD pulse size.
	Config.Tiers = { 1, 5, 10, 25, 50 }   -- tier n starts at Tiers[n] pieces

	-- ===== MILESTONES (once per streak) =====
	Config.Milestones = {
		[10] = { Slot = "PICKUP_BRIGHT_IDS", Speed = 1.3, Volume = 1.6, Sparkles = 6 },          -- bright ping
		[25] = { Slot = "GEMS_EARNED_ID", Speed = 1.12, Volume = 0.55, Sparkles = 10 },          -- chime + star sparkle
		[50] = { Slot = "REWARD_CLAIM_ID", Speed = 1.08, Volume = 0.5, Sparkles = 16, Camera = 1.2 },   -- flourish
		[100] = { Slot = "LEVEL_UP_ID", Speed = 1.05, Volume = 0.6, Sparkles = 26, Camera = 2.2 },      -- big but brief
	}

	-- ===== FINISHER (when a big streak ends) =====
	Config.FinisherMinimumStreak = 25
	Config.Finishers = {
		{ From = 100, Slot = "STAR_CHARGE_ID", Speed = 1.25, Volume = 0.55 },   -- short cosmic flourish
		{ From = 50, Slot = "GEMS_EARNED_ID", Speed = 1.25, Volume = 0.45 },    -- bright chime
		{ From = 25, Slot = "PICKUP_BRIGHT_IDS", Speed = 1.45, Volume = 1.2 },  -- small shimmer
	}

	-- ===== MAGNET STREAM =====
	-- One looped sound for every coin in flight together, never one per coin.
	Config.MagnetStream = {
		-- coins in flight -> loop volume (0-1 of the slot's volume)
		Levels = { { 1, 0.25 }, { 6, 0.6 }, { 16, 1 } },
		FadeOut = 0.25,
		WhooshQuietTime = 0.8,          -- the whoosh plays again only after this long with nothing pulled
		ClusterChime = 6,               -- this many magnet pieces in one beat add a sparkle chime
		-- Streak particles flowing into you (by coins in flight).
		ParticleLevels = { { 1, 0 }, { 6, 10 }, { 16, 24 } },
	}

	-- ===== VISUALS =====
	Config.SparkleEvery = 8             -- a tiny gold/cyan/purple sparkle every N pieces
	Config.SparkleColors = {
		Color3.fromRGB(255, 214, 90), Color3.fromRGB(110, 230, 255), Color3.fromRGB(200, 130, 255),
	}
	Config.Trail = { Base = 0.16, Stretch = 0.12, Snap = 0.04 }   -- trail lifetime: base, +stretch on approach, snap

	-- ===== HUD =====
	Config.HUDPulseCooldown = 0.10
	Config.HUDPulse = { Normal = 1.04, Big = 1.07, Seconds = 0.16 }

	-- Floating gain: ONE label over your head that adds up the streak.
	Config.GainText = { UpdateEvery = 0.15, HoldAfter = 0.8, BigFrom = 25 }

	-- ===== COMBO METER (its own panel, not on the Stardust counter) =====
	Config.Meter = {
		ShowFrom = 3,
		Placement = "TopRight",                   -- "TopRight" (below Roblox's top bar), or "Position" to use Position
		Margin = Vector2.new(0.008, 0.025),       -- kept clear of the right and top screen edges (shares of the screen)
		Position = UDim2.new(0.5, 0, 0.8, 0),    -- used when Placement = "Position" (e.g. centre, below your character)
		Width = 500,                              -- design pixels at 1920x1080 (scales with the screen)
	}

	-- ===== CAMERA / HAPTICS (rare, tiny) =====
	Config.Camera = { Enabled = true, Seconds = 0.22 }   -- a field-of-view pulse, never a shake
	Config.Haptics = { Enabled = true, Big = 0.25, Major = 0.45, Seconds = 0.08 }

	return Config

	end)()
	local Sounds = optional("GameSounds")
	local Settings = optional("ClientSettings")
	local Format = optional("NumberFormatter")
	local UIAssets = optional("UIAssets") or {}

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local FONT = Enum.Font.FredokaOne
	local INK = Color3.fromRGB(6, 11, 42)
	local GOLD_LIGHT = Color3.fromRGB(255, 232, 120)
	local CYAN = Color3.fromRGB(110, 230, 255)
	local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

	local function reduceMotion()
		return (Settings ~= nil and Settings.Get ~= nil and Settings.Get("ReduceMotion") == true)
			or player:GetAttribute("ReduceMotion") == true
	end

	local function abbreviate(n)
		if Format and Format.Abbreviate then return Format.Abbreviate(n) end
		return tostring(math.floor(n))
	end

	local function signal(name)
		local folder = ReplicatedStorage:FindFirstChild("ClientSignals")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "ClientSignals"
			folder.Parent = ReplicatedStorage
		end
		local event = folder:FindFirstChild(name)
		if not event then
			event = Instance.new("BindableEvent")
			event.Name = name
			event.Parent = folder
		end
		return event
	end
	local pulseSignal = signal("CurrencyPulse")

	local function rootPart()
		local character = player.Character
		return character and character:FindFirstChild("HumanoidRootPart")
	end

	-- ===================== SOUND BUDGET =====================
	-- The pickup-family sounds this module started that are still playing.
	local playing = {}   -- { handle = ..., priority = n }

	local function live()
		for i = #playing, 1, -1 do
			local entry = playing[i]
			if entry.handle.Done then table.remove(playing, i) end
		end
		return #playing
	end

	-- Plays a sound if the budget allows; a more important sound replaces the
	-- least important one playing. Returns the handle (or nil).
	local function play(slot, priority, speed, volume)
		if not Sounds or not slot then return nil end
		if live() >= Config.MaxConcurrentSounds then
			local worst, worstAt = nil, nil
			for i, entry in ipairs(playing) do
				if not worst or entry.priority > worst.priority then worst, worstAt = entry, i end
			end
			if not worst or worst.priority <= priority then return nil end   -- nothing less important to drop
			pcall(Sounds.Stop, worst.handle)
			table.remove(playing, worstAt)
		end
		local ok, handle = pcall(Sounds.Play, slot, { speed = speed, volume = volume })
		if ok and handle then
			table.insert(playing, { handle = handle, priority = priority })
			return handle
		end
		return nil
	end

	-- ===================== STATE =====================
	local streak = 0              -- pieces in the current streak
	local lastPickup = 0
	local milestonesHit = {}
	local beatIndex = 0           -- steps up the pitch ladder
	local lastBeat = 0
	local pending = { count = 0, weight = 0, magnet = 0, kinds = {} }
	local serverCombo, serverBonus = 0, 0
	local streakValue = 0         -- server-confirmed Stardust in this streak
	local inFlight = 0
	local lastPullAt = -math.huge
	local lastClusterChime = 0
	local lastHudPulse = 0

	local function tierOf(n)
		local tier = 0
		for i, from in ipairs(Config.Tiers) do
			if n >= from then tier = i end
		end
		return tier
	end

	function Feedback.Tier()
		return tierOf(streak)
	end

	-- Trail lifetime for a piece being pulled: it stretches as the piece
	-- speeds up, then snaps short right at you. Brighter streaks, longer trails.
	function Feedback.TrailLifetime(progress, snapping)
		local t = Config.Trail
		if snapping then return t.Snap end
		local tierBoost = if tierOf(streak) >= 4 then 1.35 else 1
		return (t.Base + t.Stretch * math.clamp(progress, 0, 1)) * tierBoost
	end

	-- ===================== WORLD FX (made once) =====================
	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "CurrencyFeedbackFX"
	fxFolder.Parent = workspace

	local sparklePart = Instance.new("Part")
	sparklePart.Name = "SparkleAnchor"
	sparklePart.Anchored = true
	sparklePart.CanCollide = false
	sparklePart.CanQuery = false
	sparklePart.CanTouch = false
	sparklePart.Transparency = 1
	sparklePart.Size = Vector3.one * 0.2
	sparklePart.Parent = fxFolder
	local sparkleEmitter = Instance.new("ParticleEmitter")
	sparkleEmitter.Texture = SPARKLE
	sparkleEmitter.LightEmission = 1
	sparkleEmitter.Rate = 0
	sparkleEmitter.Lifetime = NumberRange.new(0.35, 0.6)
	sparkleEmitter.Speed = NumberRange.new(3, 7)
	sparkleEmitter.SpreadAngle = Vector2.new(180, 180)
	sparkleEmitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	sparkleEmitter.Parent = sparklePart

	-- Particles that flow INTO you while many coins are flying (a sphere around
	-- you emitting inwards; locked to you, so they follow as you move).
	local streamPart = Instance.new("Part")
	streamPart.Name = "MagnetStream"
	streamPart.Shape = Enum.PartType.Ball
	streamPart.Anchored = true
	streamPart.CanCollide = false
	streamPart.CanQuery = false
	streamPart.CanTouch = false
	streamPart.Transparency = 1
	streamPart.Size = Vector3.one * 14
	streamPart.Parent = fxFolder
	local streamEmitter = Instance.new("ParticleEmitter")
	streamEmitter.Texture = SPARKLE
	streamEmitter.LightEmission = 1
	streamEmitter.Rate = 0
	streamEmitter.Shape = Enum.ParticleEmitterShape.Sphere
	streamEmitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	streamEmitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	streamEmitter.Speed = NumberRange.new(16, 20)
	streamEmitter.Lifetime = NumberRange.new(0.35, 0.42)
	streamEmitter.LockedToPart = true
	streamEmitter.Color = ColorSequence.new(GOLD_LIGHT, CYAN)
	streamEmitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(0.6, 0.3), NumberSequenceKeypoint.new(1, 0) })
	streamEmitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.2), NumberSequenceKeypoint.new(1, 0.6) })
	streamEmitter.Parent = streamPart

	local sparkleColor = 0
	local function sparkle(count)
		local root = rootPart()
		if not root or reduceMotion() then return end
		sparkleColor = sparkleColor % #Config.SparkleColors + 1
		local color = Config.SparkleColors[sparkleColor]
		sparklePart.CFrame = CFrame.new(root.Position + Vector3.new(0, 1.2, 0))
		sparkleEmitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		sparkleEmitter:Emit(count)
	end

	-- ===================== HUD PULSE / CAMERA / HAPTICS =====================
	local function hudPulse(peak, withIcon)
		local now = os.clock()
		if now - lastHudPulse < Config.HUDPulseCooldown then return end
		lastHudPulse = now
		pulseSignal:Fire(peak, withIcon == true, Config.HUDPulse.Seconds)
	end

	local cameraBusy = false
	local function cameraPulse(amount)
		if not Config.Camera.Enabled or cameraBusy or reduceMotion() or not amount then return end
		local camera = workspace.CurrentCamera
		if not camera then return end
		cameraBusy = true
		local base = camera.FieldOfView
		local half = Config.Camera.Seconds / 2
		local out = TweenService:Create(camera, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base + amount })
		out.Completed:Connect(function()
			local back = TweenService:Create(camera, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { FieldOfView = base })
			back.Completed:Connect(function() cameraBusy = false end)
			back:Play()
		end)
		out:Play()
		task.delay(Config.Camera.Seconds + 0.5, function() cameraBusy = false end)
	end

	local function haptic(strength)
		if not Config.Haptics.Enabled or not strength then return end
		if UserInputService:GetLastInputType() ~= Enum.UserInputType.Gamepad1 then return end
		pcall(function()
			if not HapticService:IsVibrationSupported(Enum.UserInputType.Gamepad1) then return end
			if not HapticService:IsMotorSupported(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small) then return end
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, strength)
			task.delay(Config.Haptics.Seconds, function()
				pcall(HapticService.SetMotor, HapticService, Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
			end)
		end)
	end

	-- ===================== GAIN LABEL (one, reused) =====================
	local gain = {}
	do
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "StardustStreakGain"
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.Size = UDim2.fromOffset(260, 56)
		billboard.StudsOffset = Vector3.new(0, 3, 0)
		billboard.Enabled = false
		billboard.ResetOnSpawn = false
		billboard.Parent = playerGui
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = FONT
		label.TextSize = 32
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = ""
		label.Parent = billboard
		local fill = Instance.new("UIGradient")
		fill.Rotation = 90
		fill.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220), Color3.fromRGB(255, 205, 80))
		fill.Parent = label
		local outline = Instance.new("UIStroke")
		outline.Color = INK
		outline.Thickness = 3.5
		outline.LineJoinMode = Enum.LineJoinMode.Round
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		outline.Parent = label
		local scale = Instance.new("UIScale")
		scale.Parent = label
		gain.billboard, gain.label, gain.outline, gain.scale = billboard, label, outline, scale
		gain.shown, gain.lastUpdate, gain.dirty = 0, 0, false
	end

	local function showGain()
		local root = rootPart()
		local character = player.Character
		local head = character and (character:FindFirstChild("Head") or root)
		if not head or streakValue <= 0 then return end
		gain.billboard.Adornee = head
		gain.billboard.Enabled = true
		gain.label.TextTransparency = 0
		gain.outline.Transparency = 0
		gain.label.Text = "+★" .. abbreviate(streakValue)
		gain.label.TextSize = if streak >= Config.GainText.BigFrom then 38 else 32
		gain.scale.Scale = 1.12
		TweenService:Create(gain.scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		gain.lastUpdate = os.clock()
		gain.dirty = false
	end

	local function hideGain()
		if not gain.billboard.Enabled then return end
		local fadeInfo = TweenInfo.new(0.3)
		TweenService:Create(gain.label, fadeInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(gain.outline, fadeInfo, { Transparency = 1 }):Play()
		task.delay(0.32, function()
			if os.clock() - lastPickup > Config.ComboResetTime then gain.billboard.Enabled = false end
		end)
	end

	-- ===================== COMBO METER (its own panel) =====================
	-- The supplied COMBO picture (UIAssets.HudArt.ComboBackground) with the
	-- COMBO title picture, the live xN, the server's Stardust bonus and the
	-- timer on top. The bar TRACK is painted into the picture: only the moving
	-- gold fill is created, inside it (never a second track or border).
	local meter = {}
	do
		local HUD_ART = UIAssets.HudArt or {}
		local L = HUD_ART.Layout.Combo
		local GEO = HUD_ART.Geometry            -- measured from the PNG files
		local WIDTH = Config.Meter.Width or 500          -- design pixels at 1920x1080
		local aspect = UIAssets.BodyAspect(GEO.Combo)

		local gui = Instance.new("ScreenGui")
		gui.Name = "ComboMeter"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 6
		gui.Parent = playerGui

		local root = Instance.new("Frame")
		root.Name = "Meter"
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = Config.Meter.Position
		root.BackgroundTransparency = 1
		root.Visible = false
		root.Parent = gui
		local rootScale = Instance.new("UIScale")   -- the pop in / pop out
		rootScale.Parent = root

		-- Size follows the screen (the panel's own shape is kept). Placement:
		-- "TopRight" = the top-right corner, below Roblox's top bar, with
		-- Margin (shares of the screen) kept clear; otherwise Position.
		local function resize()
			local camera = workspace.CurrentCamera
			local vp = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
			local s = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.55, 1.2)
			local w = math.floor(WIDTH * s + 0.5)
			local h = math.floor(WIDTH * s / aspect + 0.5)
			root.Size = UDim2.fromOffset(w, h)
			if Config.Meter.Placement == "TopRight" then
				local margin = Config.Meter.Margin or Vector2.new(0.025, 0.025)
				local inset = game:GetService("GuiService"):GetGuiInset().Y
				root.AnchorPoint = Vector2.new(0.5, 0.5)   -- pops from its centre
				root.Position = UDim2.fromOffset(
					math.floor(vp.X * (1 - margin.X) - w / 2 + 0.5),
					math.floor(inset + vp.Y * margin.Y + h / 2 + 0.5))
			end
		end
		resize()
		if workspace.CurrentCamera then
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
		end

		local art = Instance.new("ImageLabel")
		art.Name = "Background"
		art.Size = UDim2.fromScale(1, 1)
		art.BackgroundTransparency = 1
		art.Image = HUD_ART.ComboBackground or ""
		art.ScaleType = Enum.ScaleType.Fit   -- never stretched
		art.ZIndex = 1
		art.Parent = root

		local function place(object, spec)
			object.Position = UDim2.fromScale(spec[1], spec[2])
			object.Size = UDim2.fromScale(spec[3], spec[4])
		end

		-- The COMBO title picture, trimmed to its letters (its transparent
		-- margin is measured and pushed outside), keeping its shape.
		local titleBox = Instance.new("Frame")
		titleBox.Name = "ComboTitleBox"
		titleBox.BackgroundTransparency = 1
		place(titleBox, L.Title)
		titleBox.ZIndex = 4
		titleBox.Parent = root
		local titleShape = Instance.new("UIAspectRatioConstraint")
		titleShape.AspectRatio = 3.4
		titleShape.Parent = titleBox
		local title = Instance.new("ImageLabel")
		title.Name = "ComboTitle"
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromScale(1, 1)
		title.Image = HUD_ART.ComboTitle or ""
		title.ScaleType = Enum.ScaleType.Fit
		title.ZIndex = 4
		title.Parent = titleBox
		titleShape.AspectRatio = UIAssets.BodyAspect(GEO.ComboTitle, "Content")
		UIAssets.FitArt(title, GEO.ComboTitle.Content)

		local function text(name, spec, maxSize, color, align, z)
			local l = Instance.new("TextLabel")
			l.Name = name
			l.BackgroundTransparency = 1
			place(l, spec)
			l.Font = FONT
			l.Text = ""
			l.TextScaled = true
			l.TextColor3 = color
			l.TextXAlignment = align or Enum.TextXAlignment.Left
			l.ZIndex = z or 5
			l.Parent = root
			local limit = Instance.new("UITextSizeConstraint")
			limit.MinTextSize = 12
			limit.MaxTextSize = maxSize
			limit.Parent = l
			local st = Instance.new("UIStroke")
			st.Color = INK
			st.Thickness = 4
			st.LineJoinMode = Enum.LineJoinMode.Round
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			st.Parent = l
			local s = Instance.new("UIScale")
			s.Parent = l
			return l, s, st
		end

		-- xN: gold with an orange depth copy just below.
		local countDepth = text("CountDepth", L.Count, 96, Color3.fromRGB(214, 110, 20), Enum.TextXAlignment.Left, 5)
		countDepth.Position = UDim2.new(L.Count[1], 0, L.Count[2], 4)
		local count, countScale = text("Count", L.Count, 96, Color3.new(1, 1, 1), Enum.TextXAlignment.Left, 6)
		local countFill = Instance.new("UIGradient")
		countFill.Rotation = 90
		countFill.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 190)), ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 222, 40)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 176, 20)),
		})
		countFill.Parent = count
		meter.countFill = countFill
		local countDepthScale = countDepth:FindFirstChildOfClass("UIScale")

		-- Right side: [star] +N%  over  STARDUST.
		local star = Instance.new("ImageLabel")
		star.Name = "StardustIcon"
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(L.Star[1], L.Star[2])
		star.SizeConstraint = Enum.SizeConstraint.RelativeYY
		star.Size = UDim2.fromScale(L.Star[3], L.Star[3])
		star.BackgroundTransparency = 1
		star.Image = (UIAssets.CurrencyHUD and UIAssets.CurrencyHUD.Stardust) or UIAssets.Stardust or ""
		star.ScaleType = Enum.ScaleType.Fit
		star.ZIndex = 5
		star.Parent = root
		-- +N%: FredokaOne, white-to-gold, thick navy outline, navy shadow below.
		local bonusDepth = text("BonusDepth", L.Bonus, 56, Color3.fromRGB(6, 11, 42), Enum.TextXAlignment.Left, 5)
		bonusDepth.Position = UDim2.new(L.Bonus[1], 0, L.Bonus[2], 3)
		bonusDepth.Text = "+0%"
		local bonus, bonusScale, bonusStroke = text("Bonus", L.Bonus, 56, Color3.new(1, 1, 1), Enum.TextXAlignment.Left, 6)
		bonus.Text = "+0%"
		bonusStroke.Thickness = 5
		local bonusFill = Instance.new("UIGradient")
		bonusFill.Rotation = 90
		bonusFill.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 232, 110)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 185, 30)),
		})
		bonusFill.Parent = bonus
		meter.bonusDepth = bonusDepth
		bonusDepth:FindFirstChildOfClass("UIScale"):Destroy()
		-- The word STARDUST: the supplied picture, trimmed to its letters.
		local bonusLabel = Instance.new("Frame")
		bonusLabel.Name = "BonusCaption"
		bonusLabel.BackgroundTransparency = 1
		place(bonusLabel, L.BonusLabel)
		bonusLabel.ZIndex = 6
		bonusLabel.Parent = root
		UIAssets.WordImage(bonusLabel, HUD_ART.StardustWord, GEO.StardustWord, 6)

		-- The COMBO RANK letter (C / B / A / S / S+), top-middle of the panel.
		local R = L.Rank or { 0.40, 0.25, 0.36 }
		local rank = Instance.new("ImageLabel")
		rank.Name = "ComboRank"
		rank.AnchorPoint = Vector2.new(0.5, 0.5)
		rank.Position = UDim2.fromScale(R[1], R[2])
		rank.SizeConstraint = Enum.SizeConstraint.RelativeYY   -- square, a share of the panel height
		rank.Size = UDim2.fromScale(R[3], R[3])
		rank.BackgroundTransparency = 1
		rank.Image = ""
		rank.ScaleType = Enum.ScaleType.Fit
		rank.Visible = false
		rank.ZIndex = 7
		rank.Parent = root
		local rankScale = Instance.new("UIScale")
		rankScale.Parent = rank
		meter.rank, meter.rankScale = rank, rankScale

		-- RANK-UP BURST pieces, made once and reused: two rings and a few
		-- stars around the letter (existing star art only).
		meter.rings, meter.stars = {}, {}
		for i = 1, 2 do
			local ring = Instance.new("Frame")
			ring.Name = "RankRing" .. i
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = rank.Position
			ring.SizeConstraint = Enum.SizeConstraint.RelativeYY
			ring.BackgroundTransparency = 1
			ring.Visible = false
			ring.ZIndex = 6
			ring.Parent = root
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = ring
			local st = Instance.new("UIStroke")
			st.Thickness = 4
			st.Parent = ring
			meter.rings[i] = { frame = ring, stroke = st }
		end
		for i = 1, 10 do
			local st = Instance.new("ImageLabel")
			st.Name = "RankStar" .. i
			st.AnchorPoint = Vector2.new(0.5, 0.5)
			st.SizeConstraint = Enum.SizeConstraint.RelativeYY
			st.BackgroundTransparency = 1
			st.Image = (UIAssets.CurrencyHUD and UIAssets.CurrencyHUD.GoldStar) or ""
			st.ScaleType = Enum.ScaleType.Fit
			st.Visible = false
			st.ZIndex = 8
			st.Parent = root
			meter.stars[i] = st
		end

		-- Letters must never pop in blank: download all of them now, and keep
		-- each one drawn (2x2 px, almost invisible, outside the hidden meter)
		-- so its texture stays in memory and a rank change shows instantly.
		do
			-- Every picture the meter uses (so its first appearance is instant
			-- and the entrance animation plays smoothly, not stalled on loading).
			local ids = { HUD_ART.ComboBackground, HUD_ART.ComboTitle, HUD_ART.StardustWord, star.Image }
			for _, r in ipairs(HUD_ART.ComboRanks or {}) do table.insert(ids, r.Image) end
			for i, image in ipairs(ids) do
				local r = { Image = image }
				local warm = Instance.new("ImageLabel")
				warm.Name = "Warm" .. i
				warm.Size = UDim2.fromOffset(2, 2)
				warm.Position = UDim2.fromOffset(0, 0)
				warm.BackgroundTransparency = 1
				warm.ImageTransparency = 0.98
				warm.Image = r.Image
				warm.Active = false
				warm.Parent = gui
			end
			task.spawn(function()
				pcall(function() game:GetService("ContentProvider"):PreloadAsync(ids) end)
			end)
		end

		-- ONLY the moving fill. The area it lives in is invisible - the dark
		-- track under it is the painted one.
		local fillArea = Instance.new("Frame")
		fillArea.Name = "FillArea"
		fillArea.BackgroundTransparency = 1
		fillArea.ZIndex = 3
		fillArea.Parent = root
		local function placeTrack(t)
			fillArea.Position = UDim2.fromScale(t[1], t[2])
			fillArea.Size = UDim2.fromScale(t[3] - t[1], t[4] - t[2])
		end
		placeTrack(L.Track)
		local timerFill = Instance.new("Frame")
		timerFill.Name = "ProgressFill"
		timerFill.AnchorPoint = Vector2.new(0, 0.5)
		timerFill.Position = UDim2.fromScale(0, 0.5)
		timerFill.Size = UDim2.fromScale(1, 1)
		timerFill.BackgroundColor3 = Color3.new(1, 1, 1)
		timerFill.BorderSizePixel = 0
		timerFill.ZIndex = 3
		timerFill.Parent = fillArea
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0.5, 0)
		fillCorner.Parent = timerFill
		local fillGrad = Instance.new("UIGradient")
		fillGrad.Rotation = 90
		fillGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 248, 150)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 220, 40)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(245, 170, 20)),
		})
		fillGrad.Parent = timerFill
		-- A small highlight along the top of the fill (inside it, not a track).
		local fillShine = Instance.new("Frame")
		fillShine.Name = "Shine"
		fillShine.AnchorPoint = Vector2.new(0.5, 0)
		fillShine.Position = UDim2.fromScale(0.5, 0.12)
		fillShine.Size = UDim2.new(1, -6, 0.32, 0)
		fillShine.BackgroundColor3 = Color3.new(1, 1, 1)
		fillShine.BackgroundTransparency = 0.5
		fillShine.BorderSizePixel = 0
		fillShine.ZIndex = 3
		fillShine.Parent = timerFill
		local shineCorner = Instance.new("UICorner")
		shineCorner.CornerRadius = UDim.new(0.5, 0)
		shineCorner.Parent = fillShine

		-- The picture placed so its panel body fills the frame (measured from the PNG).
		UIAssets.FitArt(art, GEO.Combo.Body)

		meter.root, meter.scale, meter.count, meter.countScale = root, rootScale, count, countScale
		meter.countDepth, meter.countDepthScale = countDepth, countDepthScale
		meter.bonus, meter.bonusScale, meter.timerFill, meter.star = bonus, bonusScale, timerFill, star
		meter.fading = false

		-- Everything that fades, with its own resting transparency.
		meter.fade = {}
		for _, object in ipairs(root:GetDescendants()) do
			local property = if object:IsA("TextLabel") then "TextTransparency"
				elseif object:IsA("ImageLabel") then "ImageTransparency"
				elseif object:IsA("UIStroke") then "Transparency"
				elseif object:IsA("Frame") then "BackgroundTransparency"
				else nil
			if property then
				table.insert(meter.fade, { object = object, property = property, rest = object[property] })
			end
		end
	end

	local function meterShown()
		return meter.root.Visible and not meter.fading
	end

	local function restoreMeter()
		-- A new tween on the same property cancels a fade-out still running,
		-- so nothing can finish fading AFTER the meter came back.
		local info = TweenInfo.new(0.05)
		for _, item in ipairs(meter.fade) do
			item.object[item.property] = item.rest
			TweenService:Create(item.object, info, { [item.property] = item.rest }):Play()
		end
	end

	-- SPRINGS: bouncy motion driven every frame by the feedback loop (step).
	-- spring(obj, prop, from, to) kicks a value and lets it wobble to rest.
	local springs = {}
	local function spring(obj, prop, from, to, stiffness, damping)
		springs[obj] = springs[obj] or {}
		springs[obj][prop] = { v = from, vel = 0, t = to, k = stiffness or 260, d = damping or 14 }
		obj[prop] = from
	end
	local function stepSprings(dt)
		dt = math.min(dt, 1 / 30)
		for obj, props in pairs(springs) do
			for prop, sp in pairs(props) do
				sp.vel += (sp.k * (sp.t - sp.v) - sp.d * sp.vel) * dt
				sp.v += sp.vel * dt
				if math.abs(sp.t - sp.v) < 0.001 and math.abs(sp.vel) < 0.01 then
					sp.v = sp.t
					props[prop] = nil
				end
				obj[prop] = sp.v
			end
			if next(props) == nil then springs[obj] = nil end
		end
	end

	local function tweenTo(object, seconds, goal, style, direction)
		local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
		t:Play()
		return t
	end

	-- xN pop: 1 -> 1.10 -> 1 on each step, 1 -> 1.16 -> 1 on milestones.
	local function popMeter(big)
		-- A clear kick on every pickup; milestones kick harder and tilt.
		local peak = if big then 1.18 else 1.12
		for _, sc in ipairs({ meter.countScale, meter.countDepthScale }) do
			if sc then spring(sc, "Scale", peak, 1, if big then 220 else 320, if big then 11 else 16) end
		end
	end

	-- In: 0.88 -> 1.06 -> 1.00.
	-- Colours per rank (1 C .. 5 S+): the burst's ring/stars and the xN fill.
	local function seq(a, b) return ColorSequence.new(a, b) end
	local RANK_STYLE = {
		{ ring = Color3.fromRGB(255, 170, 40), fill = seq(Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 150, 30)) },
		{ ring = Color3.fromRGB(80, 220, 255), fill = seq(Color3.fromRGB(210, 250, 255), Color3.fromRGB(40, 170, 255)) },
		{ ring = Color3.fromRGB(190, 110, 255), fill = seq(Color3.fromRGB(240, 210, 255), Color3.fromRGB(160, 80, 255)) },
		{ ring = Color3.fromRGB(255, 90, 150), fill = seq(Color3.fromRGB(255, 215, 230), Color3.fromRGB(255, 60, 110)) },
		{ ring = Color3.fromRGB(255, 255, 255), fill = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 110, 110)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 210, 90)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(120, 255, 150)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(100, 200, 255)),
			ColorSequenceKeypoint.new(0.8, Color3.fromRGB(200, 120, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 110, 110)),
		}) },
	}
	local RAINBOW = { Color3.fromRGB(255, 110, 110), Color3.fromRGB(255, 210, 90), Color3.fromRGB(120, 255, 150),
		Color3.fromRGB(100, 200, 255), Color3.fromRGB(200, 120, 255) }

	-- The rank-up burst: expanding ring(s), stars flying out, fill flash and a
	-- bonus pulse. Stronger for higher ranks; S+ gets a double rainbow ring.
	local function rankBurst(index)
		local style = RANK_STYLE[index]
		local center = meter.rank.Position
		for i, r in ipairs(meter.rings) do
			if i == 1 or index >= 5 then
				local f, st = r.frame, r.stroke
				f.Position = center
				f.Size = UDim2.fromScale(0.3, 0.3)
				f.Visible = true
				st.Color = if index >= 5 then RAINBOW[(i * 2) % #RAINBOW + 1] else style.ring
				st.Transparency = 0
				st.Thickness = 3 + index
				local size = 0.9 + index * 0.18 + (i - 1) * 0.35
				local t = 0.35 + index * 0.04 + (i - 1) * 0.1
				tweenTo(f, t, { Size = UDim2.fromScale(size, size) }, Enum.EasingStyle.Quad)
				tweenTo(st, t, { Transparency = 1, Thickness = 1 }, Enum.EasingStyle.Quad)
				task.delay(t, function() f.Visible = false end)
			end
		end
		local count = math.min(2 + index + (if index >= 5 then 3 else 0), #meter.stars)
		for i = 1, count do
			local st = meter.stars[i]
			local a = (i / count) * math.pi * 2 + math.random() * 0.5
			local d = 0.10 + index * 0.012
			st.Position = center
			st.Size = UDim2.fromScale(0.16, 0.16)
			st.Rotation = 0
			st.ImageColor3 = if index >= 5 then RAINBOW[i % #RAINBOW + 1] else style.ring:Lerp(Color3.new(1, 1, 1), 0.4)
			st.ImageTransparency = 0
			st.Visible = true
			tweenTo(st, 0.5, {
				Position = center + UDim2.fromScale(math.cos(a) * d, math.sin(a) * d * 3.6),
				Size = UDim2.fromScale(0.06, 0.06), Rotation = 180, ImageTransparency = 1,
			}, Enum.EasingStyle.Quad)
			task.delay(0.5, function() st.Visible = false end)
		end
		-- Fill flash + bonus pulse.
		local shine = meter.timerFill:FindFirstChild("Shine")
		if shine then
			shine.BackgroundTransparency = 0
			tweenTo(shine, 0.4, { BackgroundTransparency = 0.5 })
		end
		spring(meter.bonusScale, "Scale", 1.18 + index * 0.03, 1, 320, 14)
	end

	local setRank   -- defined below (the COMBO RANK letter)
	local function showMeter()
		if streak < Config.Meter.ShowFrom then return end
		if not meterShown() then
			meter.fading = false
			meter.root.Visible = true
			restoreMeter()
			meter.fillShown = 0
			spring(meter.scale, "Scale", 0.5, 1, 200, 13)       -- bounces in
			spring(meter.root, "Rotation", -6, 0, 180, 12)
		end
		meter.count.Text = "x" .. streak
		setRank(streak)
		meter.countDepth.Text = meter.count.Text
	end

	-- Bonus: 1 -> 1.08 -> 1 and a warm flash when it goes up.
	local BONUS_REST = Color3.new(1, 1, 1)   -- the gradient carries the gold
	local function setBonus(value)
		local percent = math.floor(value * 100 + 0.5)
		local textValue = "+" .. percent .. "%"
		if meter.bonus.Text ~= textValue then
			meter.bonus.Text = textValue
			if meter.bonusDepth then meter.bonusDepth.Text = textValue end
			if percent > 0 then
				spring(meter.bonusScale, "Scale", 1.12, 1, 380, 18)
				meter.bonus.TextColor3 = Color3.fromRGB(255, 248, 200)
				tweenTo(meter.bonus, 0.4, { TextColor3 = BONUS_REST })
			end
		end
	end

	-- COMBO RANK: the letter for the current streak (UIAssets.HudArt.ComboRanks).
	-- A change pops: the old letter shrinks away, the new one pops in.
	local RANKS = (UIAssets.HudArt and UIAssets.HudArt.ComboRanks) or {}
	local currentRank = 0
	local rankToken = 0
	local function rankFor(n)
		local found = 0
		for i, r in ipairs(RANKS) do
			if n >= r.MinCombo then found = i end
		end
		return found
	end
	function setRank(n)
		local index = rankFor(n)
		if index == currentRank then
			-- Safeguard: the right rank but no letter showing -> show it.
			if index > 0 and (not meter.rank.Visible or meter.rank.Image ~= RANKS[index].Image) then
				meter.rank.Image = RANKS[index].Image
				meter.rank.ImageTransparency = 0
				meter.rank.Visible = true
			end
			return
		end
		local rising = index > currentRank
		currentRank = index
		rankToken += 1
		local token = rankToken
		local rank, s = meter.rank, meter.rankScale
		if index == 0 then
			rank.Visible = false
			return
		end
		local function popIn()
			if token ~= rankToken then return end
			rank.Image = RANKS[index].Image
			rank.Visible = true
			-- Overrides the old letter's fade-out even if it hasn't finished.
			rank.ImageTransparency = 0
			tweenTo(rank, 0.05, { ImageTransparency = 0 })
			rank.Rotation = 0
			tweenTo(rank, 0.01, { Rotation = 0 })   -- upright, whatever was running
			spring(s, "Scale", 0.7, 1, 420, 20)            -- 0.7 -> ~1.15 -> 1.0 in ~0.2 s
		end
		if rank.Visible and rank.Image ~= "" then
			tweenTo(s, 0.1, { Scale = 0.75 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tweenTo(rank, 0.1, { ImageTransparency = 1 })
			task.delay(0.1, popIn)
		else
			popIn()
		end
		meter.rankIndex = index
		-- xN takes the rank's colour (S+ gets a slow rainbow, see step).
		meter.countFill.Color = RANK_STYLE[index].fill
		meter.countFill.Offset = Vector2.zero
		if rising and index > 1 then
			-- A small bright ping, a little higher for each rank; once per change.
			play(Config.Sounds.Bright, Config.Priority.Milestone, 1.1 + index * 0.06, 1.3)
			sparkle(4 + index)
		end
		if rising then rankBurst(index) end
	end

	-- Out: 1.00 -> 1.04 -> 0.88 while fading.
	local function hideMeter()
		if not meter.root.Visible or meter.fading then return end
		meter.fading = true
		springs[meter.scale] = nil   -- the exit tween takes over
		springs[meter.root] = nil
		meter.root.Rotation = 0
		local up = tweenTo(meter.scale, 0.09, { Scale = 1.03 })
		up.Completed:Connect(function()
			tweenTo(meter.scale, 0.22, { Scale = 0.86 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			for _, item in ipairs(meter.fade) do
				TweenService:Create(item.object, info, { [item.property] = 1 }):Play()
			end
		end)
		task.delay(0.32, function()
			if meter.fading then
				meter.root.Visible = false
				meter.fading = false
			end
		end)
	end

	-- ===================== MAGNET STREAM LOOP =====================
	local streamHandle = nil
	local streamVolume = 0

	local function levelFor(levels, n)
		local value = 0
		for _, pair in ipairs(levels) do
			if n >= pair[1] then value = pair[2] end
		end
		return value
	end

	local function updateStream(dt)
		local target = if inFlight > 0 and not reduceMotion() then levelFor(Config.MagnetStream.Levels, inFlight) else 0
		if Settings and Settings.Get and Settings.Get("Particles") == false then target = math.min(target, 0.6) end
		local rate = if target > 0 then 1 / 0.15 else 1 / Config.MagnetStream.FadeOut
		streamVolume += math.clamp(target - streamVolume, -rate * dt, rate * dt)
		if streamVolume > 0.01 and not streamHandle and Sounds then
			local ok, handle = pcall(Sounds.Play, Config.Sounds.MagnetStream)
			streamHandle = if ok then handle else nil
		end
		if streamHandle then
			if streamHandle.Done then
				streamHandle = nil
			elseif streamHandle.Status == "playing" then
				streamHandle.Entry.sound.Volume = (streamHandle.TargetVolume or 0.1) * streamVolume
			end
			if streamVolume <= 0.01 and streamHandle then
				pcall(Sounds.Stop, streamHandle)
				streamHandle = nil
			end
		end

		-- Particles flowing in, only while plenty are flying.
		local root = rootPart()
		local particles = if reduceMotion() or (Settings and Settings.Get and Settings.Get("Particles") == false) then 0
			else levelFor(Config.MagnetStream.ParticleLevels, inFlight)
		streamEmitter.Rate = particles
		if particles > 0 and root then
			streamPart.CFrame = root.CFrame
		end
	end

	-- ===================== BEATS =====================
	local function pitch()
		local p = math.min(Config.BasePitch + Config.PitchStep * beatIndex, Config.MaxPitch)
		return p + (math.random() * 2 - 1) * Config.PitchJitter
	end

	local function playBeat()
		local now = os.clock()
		if now - lastBeat > Config.PitchRelaxAfter then
			beatIndex = math.floor(beatIndex * 0.5)   -- a pause relaxes the ladder
		end
		lastBeat = now
		local speed = pitch()
		local kinds = pending.kinds
		local tier = tierOf(streak)

		if kinds.mega then
			play(Config.Sounds.Mega, Config.Priority.Mega, 1.05, 0.8)
			sparkle(22)
			hudPulse(Config.HUDPulse.Big, true)
			haptic(Config.Haptics.Big)
		elseif kinds.gem then
			-- Heavier: a low body under a bright top.
			play(Config.Sounds.Soft, Config.Priority.Beat, speed * 0.82, 1.2)
			play(Config.Sounds.Bright, Config.Priority.Beat, speed * 1.05, 1.1)
		else
			-- Soft ticks are the base; the bright variant is the accent (every
			-- 4th beat, every 3rd in a big streak) or a Stardust Bar.
			local every = if tier >= 4 then math.max(Config.AccentEvery - 1, 2) else Config.AccentEvery
			local accent = beatIndex % every == every - 1
			local bright = accent or kinds.bar
			local tiny = pending.count == 1 and not accent and not kinds.bar
			play(if bright then Config.Sounds.Bright else Config.Sounds.Soft,
				if tiny then Config.Priority.Tiny else Config.Priority.Beat,
				speed, if accent then 1.1 else 1)
		end

		-- A cluster of magnet coins arriving together adds a small shimmer.
		if pending.magnet >= Config.MagnetStream.ClusterChime and now - lastClusterChime > 0.5 then
			lastClusterChime = now
			play(Config.Sounds.Bright, Config.Priority.Beat, math.min(speed * 1.25, 1.45), 0.7)
		end
		beatIndex += 1

		-- HUD: bigger streaks pulse the counter a little more.
		if tier >= 4 then
			hudPulse(Config.HUDPulse.Big, tier >= 5)
		elseif tier >= 2 then
			hudPulse(Config.HUDPulse.Normal, false)
		end

		pending.count, pending.weight, pending.magnet = 0, 0, 0
		table.clear(pending.kinds)
	end

	local function milestone(n)
		local m = Config.Milestones[n]
		if not m or milestonesHit[n] then return end
		milestonesHit[n] = true
		play(m.Slot, Config.Priority.Milestone, m.Speed, m.Volume)
		sparkle(m.Sparkles or 8)
		hudPulse(Config.HUDPulse.Big, true)
		popMeter(true)
		cameraPulse(m.Camera)
		if n >= 50 then haptic(Config.Haptics.Major) elseif n >= 25 then haptic(Config.Haptics.Big) end
	end

	local function endStreak()
		if streak >= Config.FinisherMinimumStreak then
			for _, f in ipairs(Config.Finishers) do
				if streak >= f.From then
					play(f.Slot, Config.Priority.Finisher, f.Speed, f.Volume)
					sparkle(if streak >= 100 then 18 else 10)
					break
				end
			end
		end
		streak = 0
		beatIndex = 0
		streakValue = 0
		table.clear(milestonesHit)
		setBonus(0)
		setRank(0)
		hideMeter()
		hideGain()
	end

	-- ===================== LOOP (only while something is going on) =====================
	local loop = nil
	local function step(dt)
		stepSprings(dt)
		-- S+: the xN rainbow drifts slowly (premium, not flashing).
		if meter.rankIndex == 5 and meter.root.Visible then
			meter.countFill.Offset = Vector2.new(math.sin(os.clock() * 0.9) * 0.5, 0)
		end
		local now = os.clock()
		local interval = if streak >= Config.BusyFrom then Config.BusyInterval else Config.SoundInterval
		if pending.count > 0 and now - lastBeat >= interval then
			playBeat()
		end
		if streak > 0 then
			local left = 1 - (now - lastPickup) / Config.ComboResetTime
			-- Eased, so a refill glides up and the drain is silky, never a jump.
			meter.fillShown = (meter.fillShown or 0) + (math.clamp(left, 0, 1) - (meter.fillShown or 0)) * math.min(1, dt * 14)
			meter.timerFill.Size = UDim2.fromScale(meter.fillShown, 1)
			meter.timerFill.Visible = left > 0.03   -- never a squashed dot at the very end
			if left <= 0 then endStreak() end
		end
		if gain.dirty and now - gain.lastUpdate >= Config.GainText.UpdateEvery then
			showGain()
		end
		updateStream(dt)
		if streak == 0 and pending.count == 0 and inFlight == 0 and streamVolume <= 0.01 and not streamHandle and next(springs) == nil then
			streamEmitter.Rate = 0
			loop:Disconnect()
			loop = nil
		end
	end
	local function ensureLoop()
		if not loop then loop = RunService.Heartbeat:Connect(step) end
	end

	-- ===================== API =====================
	-- A piece reached you (called the moment it arrives, before the server's
	-- confirmation - it is feedback, not payment).
	function Feedback.Collected(kind, viaMagnet)
		local now = os.clock()
		if streak > 0 and now - lastPickup > Config.ComboResetTime then
			endStreak()
		end
		streak += 1
		lastPickup = now
		pending.count += 1
		pending.weight += Config.KindWeight[kind] or 1
		pending.kinds[kind or "coin"] = true
		if viaMagnet then pending.magnet += 1 end
		if streak % Config.SparkleEvery == 0 then sparkle(4) end
		if Config.Milestones[streak] then milestone(streak) end
		showMeter()
		if streak == 5 then
			popMeter(true)
			sparkle(5)
		elseif streak >= Config.Meter.ShowFrom and not Config.Milestones[streak] and meterShown() then
			popMeter(false)
		end
		ensureLoop()
	end

	-- How many of your pieces are flying towards you right now.
	function Feedback.SetInFlight(count)
		if count > 0 and inFlight == 0 and os.clock() - lastPullAt > Config.MagnetStream.WhooshQuietTime then
			play(Config.Sounds.MagnetWhoosh, Config.Priority.Tiny)
		end
		if count > 0 then lastPullAt = os.clock() end
		inFlight = count
		if count > 0 then ensureLoop() end
	end

	-- The server's confirmation: Stardust actually paid (bonus included), and
	-- the server's combo and bonus. Drives the gain label and the meter's bonus.
	function Feedback.ServerCollected(total, combo, bonus)
		serverCombo = tonumber(combo) or serverCombo
		serverBonus = tonumber(bonus) or 0
		setBonus(serverBonus)
		if (tonumber(total) or 0) > 0 then
			streakValue += total
			gain.dirty = true
			ensureLoop()
		end
	end

	function Feedback.Streak()
		return streak
	end

	player.CharacterAdded:Connect(function()
		gain.billboard.Adornee = nil
	end)

	return Feedback
end)()
print("[StardustDropClient] collection feedback ready (sounds, combo meter, gain label).")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("BlackHoleRemotes")
local dropCollected = remotes:WaitForChild("DropCollected", 30)

local TAG = "StardustDrop"
local FONT = Enum.Font.FredokaOne
local OUTLINE = Color3.fromRGB(14, 12, 30)
local GOLD = Color3.fromRGB(255, 196, 36)
local GOLD_LIGHT = Color3.fromRGB(255, 232, 120)
local GOLD_DARK = Color3.fromRGB(214, 138, 18)
local GOLD_FACE = Color3.fromRGB(255, 206, 52)
local CRYSTAL = Color3.fromRGB(255, 200, 50)
local CRYSTAL_LIGHT = Color3.fromRGB(255, 246, 190)
local GLINT = Color3.fromRGB(255, 255, 240)
local CYAN = Color3.fromRGB(90, 230, 255)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FAR = CFrame.new(0, -5000, 0)

-- ===================== TUNING =====================
local MAGNET = (UpgradeConfig and UpgradeConfig.Magnet) or { BaseRange = 16, CarryRangeMultiplier = 1.2, SoftRangeMultiplier = 1.3 }
local PULL = {
	NoticeSeconds = 0.08,     -- the pop before it moves
	StartSpeed = 8,           -- studs/s
	Acceleration = 70,        -- studs/s^2 (more with Currency Magnet levels)
	UpgradeAccelBonus = 0.25, -- +25% acceleration at max magnet level
	MaxSpeed = 90,
	SnapDistance = 2.6,       -- inside this it whips in and shrinks
	CurveAmplitude = 2.4,     -- sideways swing, shrinking as it arrives
	CurveFrequency = 8,
	SoftDrift = 1.4,          -- studs a piece leans towards you in the soft range
}
local LAND_SECONDS = 0.8          -- the arc out of the black hole
local SERVER_LAND_SECONDS = 0.9   -- the server won't collect before this
local UNCONFIRMED_SECONDS = 1.5

local function reduceMotion()
	return Settings ~= nil and Settings.Get ~= nil and Settings.Get("ReduceMotion") == true
end

-- Fewer pieces drawn on lower graphics; rewards are identical.
local function maxVisible()
	if Settings and Settings.Get then
		if Settings.Get("ReduceMotion") == true then return 70 end
		if Settings.Get("Particles") == false then return 120 end
	end
	return 180
end

local function sfx(slot, speed)
	if Sounds then pcall(Sounds.Play, slot, if speed then { speed = speed } else nil) end
end

local function abbreviate(n)
	if Format and Format.Abbreviate then return Format.Abbreviate(n) end
	return tostring(math.floor(n))
end

local function magnetLevel()
	return tonumber(player:GetAttribute("Upgrade_CurrencyMagnet")) or 0
end

local folder = Instance.new("Folder")
folder.Name = "StardustDropVisuals"
folder.Parent = workspace

-- ===================== PIECES (pooled) =====================
local function newPart(shape, size, color, material, transparency)
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = FAR
	part.Parent = folder
	return part
end

-- A star emblem printed on a face (SurfaceGui on an invisible thin part).
local function emblem(size, face, color)
	local plate = newPart(Enum.PartType.Block, size, GOLD, Enum.Material.SmoothPlastic, 1)
	plate.Name = "Emblem"
	local surface = Instance.new("SurfaceGui")
	surface.Face = face
	surface.LightInfluence = 0
	surface.PixelsPerStud = 50
	surface.Parent = plate
	local star = Instance.new("TextLabel")
	star.BackgroundTransparency = 1
	star.Size = UDim2.fromScale(1, 1)
	star.Font = FONT
	star.Text = "★"
	star.TextScaled = true
	star.TextColor3 = color
	star.Parent = surface
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(150, 90, 10)
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = star
	return plate
end

local SIZE = { coin = 1, bar = 1, gem = 1, mega = 2 }

local function buildPiece(kind)
	local parts = {}
	local function add(part, offset)
		table.insert(parts, { part = part, offset = offset, baseSize = part.Size, baseTransparency = part.Transparency })
	end
	if kind == "bar" then
		add(newPart(Enum.PartType.Block, Vector3.new(2.2, 0.8, 1.1), GOLD_DARK), CFrame.new())
		add(newPart(Enum.PartType.Block, Vector3.new(1.75, 0.34, 0.78), GOLD_FACE), CFrame.new(0, 0.56, 0))
		add(newPart(Enum.PartType.Block, Vector3.new(1.3, 0.06, 0.12), GLINT, Enum.Material.Neon, 0.25), CFrame.new(0, 0.74, -0.24))
		add(emblem(Vector3.new(0.9, 0.04, 0.6), Enum.NormalId.Top, GOLD_DARK), CFrame.new(0, 0.74, 0.04))
	elseif kind == "gem" or kind == "mega" then
		-- Star Crystal (Stardust): a tall gold crystal with a glowing core and a ★.
		local turn = CFrame.Angles(0, math.rad(45), 0)
		add(newPart(Enum.PartType.Block, Vector3.new(1.05, 1.9, 1.05), GOLD_DARK), turn)
		add(newPart(Enum.PartType.Block, Vector3.new(0.9, 1.7, 0.9), CRYSTAL), turn * CFrame.Angles(0, math.rad(10), 0))
		add(newPart(Enum.PartType.Block, Vector3.new(0.5, 1.2, 0.5), CRYSTAL_LIGHT, Enum.Material.Neon, 0.1), turn)
		add(emblem(Vector3.new(0.02, 0.9, 0.9), Enum.NormalId.Right, GOLD_DARK), CFrame.new(0.5, 0, 0))
		add(emblem(Vector3.new(0.02, 0.9, 0.9), Enum.NormalId.Left, GOLD_DARK), CFrame.new(-0.5, 0, 0))
		add(newPart(Enum.PartType.Ball, Vector3.one * 0.24, GLINT, Enum.Material.Neon, 0.1), CFrame.new(-0.2, 0.7, -0.45))
		if kind == "mega" then
			-- A soft golden aura and real light around the Mega piece.
			local aura = newPart(Enum.PartType.Ball, Vector3.one * 2.4, GOLD_LIGHT, Enum.Material.Neon, 0.72)
			local light = Instance.new("PointLight")
			light.Color = GOLD_LIGHT
			light.Range = 12
			light.Brightness = 2
			light.Parent = aura
			add(aura, CFrame.new())
		end
	else
		-- Coin standing on its edge: dark rim, bright face, star on both sides.
		add(newPart(Enum.PartType.Cylinder, Vector3.new(0.42, 2.2, 2.2), GOLD_DARK), CFrame.new())
		add(newPart(Enum.PartType.Cylinder, Vector3.new(0.48, 1.8, 1.8), GOLD_FACE), CFrame.new())
		add(emblem(Vector3.new(0.02, 1.3, 1.3), Enum.NormalId.Right, GOLD_DARK), CFrame.new(0.25, 0, 0))
		add(emblem(Vector3.new(0.02, 1.3, 1.3), Enum.NormalId.Left, GOLD_DARK), CFrame.new(-0.25, 0, 0))
		add(newPart(Enum.PartType.Ball, Vector3.one * 0.26, GLINT, Enum.Material.Neon, 0.15), CFrame.new(0.27, 0.5, -0.45))
	end
	-- A short glowing trail, only switched on while the piece is pulled in.
	local carrier = parts[1].part
	local width = if kind == "mega" then 0.9 else 0.45
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width, 0)
	a0.Parent = carrier
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width, 0)
	a1.Parent = carrier
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.18
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 0.8
	trail.LightInfluence = 0
	trail.WidthScale = NumberSequence.new(1, 0.05)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Color = ColorSequence.new(GOLD_LIGHT, GOLD)
	trail.Enabled = false
	trail.Parent = carrier
	return { kind = kind, parts = parts, trail = trail, scale = SIZE[kind] or 1 }
end

local pools = {}
local function acquire(kind)
	local pool = pools[kind]
	local piece = pool and table.remove(pool)
	if not piece then piece = buildPiece(kind) end
	for _, item in ipairs(piece.parts) do item.part.LocalTransparencyModifier = 0 end
	return piece
end

local function release(piece)
	if not piece then return end
	piece.trail.Enabled = false
	piece.trail:Clear()
	for _, item in ipairs(piece.parts) do
		item.part.CFrame = FAR
		item.part.LocalTransparencyModifier = 1
	end
	pools[piece.kind] = pools[piece.kind] or {}
	table.insert(pools[piece.kind], piece)
end

local function place(piece, cframe, scale)
	scale = math.max(scale * piece.scale, 0.02)
	for _, item in ipairs(piece.parts) do
		local size = item.baseSize * scale
		if item.part.Size ~= size then item.part.Size = size end
		item.part.CFrame = cframe * CFrame.new(item.offset.Position * scale) * item.offset.Rotation
	end
end

local function fade(piece, alpha)
	for _, item in ipairs(piece.parts) do item.part.LocalTransparencyModifier = alpha end
end

-- One pooled sparkle emitter, moved to wherever a pickup happens.
local sparklePart = newPart(Enum.PartType.Block, Vector3.one * 0.2, GOLD, Enum.Material.SmoothPlastic, 1)
sparklePart.Name = "PickupSparkle"
local sparkles = Instance.new("ParticleEmitter")
sparkles.Texture = SPARKLE
sparkles.Enabled = false
sparkles.LightEmission = 1
sparkles.LightInfluence = 0
sparkles.SpreadAngle = Vector2.new(180, 180)
sparkles.Speed = NumberRange.new(4, 8)
sparkles.Drag = 8
sparkles.Lifetime = NumberRange.new(0.3, 0.5)
sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
sparkles.Color = ColorSequence.new(GOLD_LIGHT, Color3.new(1, 1, 1))
sparkles.Parent = sparklePart

-- ===================== COSMETICS =====================
local function equipped(slot)
	local id = player:GetAttribute("Equipped_" .. slot)
	return if GemsConfig and type(id) == "string" and id ~= "" then GemsConfig.Get(id) else nil
end

-- Big streaks (tier 4+) get brighter, longer trails.
local function hotStreak()
	return Feedback ~= nil and Feedback.Tier() >= 4
end

local function styleTrail(piece)
	local item = equipped("Trail")
	local trail = piece.trail
	if item then
		trail.Color = if item.Rainbow then GemsConfig.Rainbow else ColorSequence.new(item.Color:Lerp(Color3.new(1, 1, 1), 0.35), item.Color)
	elseif piece.kind == "mega" then
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), GOLD)
	else
		trail.Color = ColorSequence.new(GOLD_LIGHT, GOLD)
	end
	trail.LightEmission = if hotStreak() then 1 else 0.8
	trail.Lifetime = if Feedback then Feedback.TrailLifetime(0, false) else 0.18
	trail.Enabled = true
end

local function burst(position, count)
	local item = equipped("Sparkle")
	sparklePart.CFrame = CFrame.new(position)
	if item then
		sparkles.Color = ColorSequence.new(item.Color, Color3.new(1, 1, 1))
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, item.Size or 0.6), NumberSequenceKeypoint.new(1, 0) })
		sparkles:Emit(item.Count or count or 6)
	else
		sparkles.Color = ColorSequence.new(GOLD_LIGHT, Color3.new(1, 1, 1))
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
		sparkles:Emit(count or 6)
	end
end

-- Whether you're carrying a black hole (the server collects from further away then).
local carrying, carryCheckedAt = false, 0
local function isCarrying()
	local now = os.clock()
	if now - carryCheckedAt > 0.25 then
		carryCheckedAt = now
		carrying = false
		for _, hole in ipairs(CollectionService:GetTagged("BlackHole")) do
			if hole:GetAttribute("HeldBy") == player.UserId then
				carrying = true
				break
			end
		end
	end
	return carrying
end

local function hardRange()
	if UpgradeConfig and UpgradeConfig.GetMagnetRange then
		return UpgradeConfig.GetMagnetRange(magnetLevel(), isCarrying())
	end
	return MAGNET.BaseRange
end

-- ===================== MAGNET RANGE RING =====================
-- Buying Currency Magnet shows your new range as a ring on the ground.
local function rangeRing(radius)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, CYAN, Enum.Material.SmoothPlastic, 1)
	anchor.Name = "MagnetRangeRing"
	anchor.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.7, 0)) * CFrame.Angles(math.rad(90), 0, 0)
	for i, spec in ipairs({ { Color3.fromRGB(110, 245, 255), 0.6 }, { Color3.fromRGB(120, 255, 170), 0.3 } }) do
		local ring = Instance.new("CylinderHandleAdornment")
		ring.Adornee = anchor
		ring.Color3 = spec[1]
		ring.Height = 0.2
		ring.Radius = radius * 0.35
		ring.InnerRadius = radius * 0.35 - spec[2]
		ring.Transparency = 0.15
		ring.ZIndex = i
		ring.Parent = anchor
		TweenService:Create(ring, TweenInfo.new(1 + i * 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Radius = radius, InnerRadius = radius - spec[2], Transparency = 1,
		}):Play()
	end
	-- A faint disc fills the range for a moment.
	local disc = Instance.new("CylinderHandleAdornment")
	disc.Adornee = anchor
	disc.Color3 = CYAN
	disc.Height = 0.05
	disc.Radius = radius
	disc.Transparency = 0.8
	disc.Parent = anchor
	TweenService:Create(disc, TweenInfo.new(1), { Transparency = 1 }):Play()
	Debris:AddItem(anchor, 1.4)
end

do
	local lastLevel = player:GetAttribute("Upgrade_CurrencyMagnet")
	player:GetAttributeChangedSignal("Upgrade_CurrencyMagnet"):Connect(function()
		local level = player:GetAttribute("Upgrade_CurrencyMagnet")
		if lastLevel ~= nil and tonumber(level) and tonumber(level) > (tonumber(lastLevel) or 0)
			and player:GetAttribute("UpgradeDataReady") == true then
			rangeRing(hardRange())
			sfx("BOOST_START_ID", 1.2)
		end
		lastLevel = level
	end)
end

-- A value tag, only on the Mega piece (showers would be a wall of numbers).
local function makeTag(anchorPart, value)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DropValue"
	billboard.Adornee = anchorPart
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.Size = UDim2.fromOffset(120, 32)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.Parent = folder
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = FONT
	label.Text = "MEGA ★" .. abbreviate(value)
	label.TextScaled = true
	label.TextColor3 = CRYSTAL_LIGHT
	label.Parent = billboard
	local st = Instance.new("UIStroke")
	st.Color = OUTLINE
	st.Thickness = 2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Parent = label
	return billboard
end

-- ===================== TRACKING =====================
local visuals = {}       -- [serverPart] = visual, sitting on the base
local pulling = {}       -- visuals being pulled into you
local leaving = {}       -- visuals whose server part went without us (expired / someone else's)
local recentlyArrived = {} -- predicted pieces waiting for the server's confirmation
local connection = nil
local step

local function ensureLoop()
	if not connection then
		connection = RunService.RenderStepped:Connect(step)
	end
end

local function drawnCount()
	local n = #pulling + #leaving
	for _ in pairs(visuals) do n += 1 end
	return n
end

local function dropVisual(visual)
	if visual.piece then release(visual.piece) end
	visual.piece = nil
	if visual.tag then visual.tag:Destroy() visual.tag = nil end
	if visual.anchor then visual.anchor:Destroy() visual.anchor = nil end
end

local function add(serverPart, silent)
	if not serverPart:IsA("BasePart") or visuals[serverPart] then return end
	serverPart.LocalTransparencyModifier = 1   -- the server's marker stays hidden
	local kind = tostring(serverPart:GetAttribute("Kind") or "coin")
	local value = tonumber(serverPart:GetAttribute("Value")) or 0
	local mine = serverPart:GetAttribute("OwnerUserId") == player.UserId
	local from = serverPart:GetAttribute("BurstFrom")
	local delay = tonumber(serverPart:GetAttribute("BurstDelay")) or 0
	local home = serverPart.Position + Vector3.new(0, 0.7, 0)

	local visual = {
		serverPart = serverPart, kind = kind, value = value, mine = mine, home = home,
		from = if typeof(from) == "Vector3" and not silent then from + Vector3.new(0, 1.5, 0) else nil,
		delay = if silent then 0 else delay, born = os.clock() - (if silent then 1 else 0),
		seed = math.random() * 6.28, spin = (if math.random() < 0.5 then -1 else 1) * (1.2 + math.random()),
		drift = Vector3.zero, arc = 1.5 + math.random() * 2.5,
	}
	-- Pieces fly across the whole base now: longer throws arc higher.
	if visual.from then
		local distance = (Vector3.new(home.X, 0, home.Z) - Vector3.new(visual.from.X, 0, visual.from.Z)).Magnitude
		visual.arc = math.clamp(distance * 0.3, 1.5, 12) * (0.8 + math.random() * 0.4)
	end
	-- Past the drawing budget the piece still counts; it just isn't drawn.
	if drawnCount() < maxVisible() or kind == "mega" then
		visual.piece = acquire(kind)
		place(visual.piece, CFrame.new(visual.from or home), 0.02)
	end
	if kind == "mega" and mine and visual.piece then
		local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.1, GOLD, Enum.Material.SmoothPlastic, 1)
		anchor.Name = "MegaAnchor"
		anchor.CFrame = CFrame.new(home)
		visual.anchor = anchor
		visual.tag = makeTag(anchor, value)
		if not silent then sfx("LEGENDARY_REVEAL_ID", 1.3) end
	end
	-- Ordinary drops land silently (no coin-drop sound).
	visuals[serverPart] = visual

	serverPart.Destroying:Connect(function()
		visual.serverGone = true
		if visuals[serverPart] == visual then
			visuals[serverPart] = nil
			visual.goneAt = os.clock()
			table.insert(leaving, visual)
			ensureLoop()
		end
	end)
	ensureLoop()
end

-- Starts the pull: pop (notice), then accelerate into you.
local function startPull(visual, position, predicted)
	visual.pullStart = os.clock()
	visual.pos = position or visual.current or visual.home
	visual.speed = PULL.StartSpeed
	visual.startDist = nil
	visual.predicted = predicted
	visual.magnet = true
	if visual.piece then styleTrail(visual.piece) end
	if visual.tag then visual.tag.Enabled = false end
	table.insert(pulling, visual)
	ensureLoop()
end

local function arrive(visual, target)
	-- A small flash on arrival; the sound, streak and meter are one beat in
	-- CurrencyFeedback (never one sound per coin).
	burst(target, if visual.kind == "mega" then 16 else 3)
	if Feedback then Feedback.Collected(visual.kind, visual.magnet == true) end
	dropVisual(visual)
	if visual.predicted and not visual.confirmed then
		-- Keep watching: if the server never confirms, bring the piece back.
		table.insert(recentlyArrived, visual)
		task.delay(UNCONFIRMED_SECONDS, function()
			local at = table.find(recentlyArrived, visual)
			if at then table.remove(recentlyArrived, at) end
			local part = visual.serverPart
			if not visual.confirmed and not visual.serverGone and part and part.Parent and not visuals[part] then
				pcall(add, part, true)
			end
		end)
	end
end

-- ===================== MOTION =====================
local function easeOutBack(t)
	local c1, c3 = 1.4, 2.4
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

function step(dt)
	local now = os.clock()
	local calm = reduceMotion()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local ready = player:GetAttribute("StardustDataReady") == true
	local hard = hardRange()
	local soft = hard * (MAGNET.SoftRangeMultiplier or 1.3)
	local target = rootPart and (rootPart.Position + Vector3.new(0, 1, 0))

	-- Pieces on the base: arc out, land, bob; lean in (soft); start the pull (hard).
	for part, visual in pairs(visuals) do
		local age = now - visual.born - visual.delay
		local position
		if age < 0 then
			position = visual.from or visual.home
		elseif age < LAND_SECONDS and visual.from and not calm then
			local t = age / LAND_SECONDS
			position = visual.from:Lerp(visual.home, t) + Vector3.new(0, math.sin(math.pi * t) * visual.arc, 0)
		else
			local bob = if calm then 0 else math.sin(now * 2.2 + visual.seed) * 0.15
			position = visual.home + Vector3.new(0, bob, 0)
		end

		if visual.mine and rootPart and ready and age >= LAND_SECONDS then
			local offset = rootPart.Position - visual.home
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local distance = flat.Magnitude
			local lean = Vector3.zero
			if distance <= soft and distance > 0.01 and not calm then
				local strength = math.clamp((soft - distance) / math.max(soft - hard, 0.1), 0, 1)
				lean = flat.Unit * PULL.SoftDrift * strength
			end
			visual.drift = visual.drift:Lerp(lean, math.min(dt * 6, 1))
			position += visual.drift
			if distance <= hard and math.abs(offset.Y) <= 12 and now - visual.born - visual.delay >= SERVER_LAND_SECONDS - 0.05 then
				visuals[part] = nil
				visual.current = position
				startPull(visual, position, true)
				continue
			end
		end

		visual.current = position
		if visual.piece then
			local grow = if age < 0 then 0.02 else math.clamp(age / 0.2, 0.02, 1)
			local spinSpeed = if visual.kind == "mega" then 0.6 else 1
			local rotation = CFrame.Angles(0, if calm then 0 else now * visual.spin * spinSpeed + visual.seed, 0)
			place(visual.piece, CFrame.new(position) * rotation, grow)
		end
		if visual.anchor then visual.anchor.CFrame = CFrame.new(position) end
	end

	-- Pieces being pulled in: NOTICE -> PULL (accelerating, curving) -> SNAP.
	for index = #pulling, 1, -1 do
		local visual = pulling[index]
		local elapsed = now - visual.pullStart
		if not target then
			dropVisual(visual)
			table.remove(pulling, index)
			continue
		end
		local scale = 1
		local renderPosition = visual.pos
		if elapsed < PULL.NoticeSeconds and not calm then
			-- Notice: a quick pop, leaning towards you.
			scale = 1 + 0.25 * math.sin(elapsed / PULL.NoticeSeconds * math.pi)
		else
			local toTarget = target - visual.pos
			local distance = toTarget.Magnitude
			visual.startDist = visual.startDist or math.max(distance, 0.1)
			local snapping = distance < PULL.SnapDistance
			local accel = PULL.Acceleration * (1 + math.clamp(magnetLevel() / 30, 0, 1) * PULL.UpgradeAccelBonus)
			visual.speed = math.min(PULL.MaxSpeed * (if snapping then 1.6 else 1), visual.speed + accel * dt * (if snapping then 3 else 1))
			if distance > 0.001 then
				visual.pos += toTarget.Unit * math.min(distance, visual.speed * dt)
			end
			distance = (target - visual.pos).Magnitude
			-- The sideways swing: wide at first, gone by the time it arrives.
			if not calm and distance > 0.3 then
				local side = toTarget:Cross(Vector3.yAxis)
				if side.Magnitude > 0.001 then
					local amount = math.sin(elapsed * PULL.CurveFrequency + visual.seed) * PULL.CurveAmplitude
						* math.clamp(distance / visual.startDist, 0, 1)
					renderPosition = visual.pos + side.Unit * amount + Vector3.new(0, math.sin(elapsed * 5 + visual.seed) * 0.4, 0)
				end
			else
				renderPosition = visual.pos
			end
			-- Snap: 1 -> ~0.75 halfway -> almost nothing as it lands.
			if snapping then
				scale = math.clamp(distance / PULL.SnapDistance, 0, 1) ^ 0.45
			end
			-- Trail stretches as it speeds up, then contracts right at you.
			if visual.piece and Feedback then
				visual.piece.trail.Lifetime = Feedback.TrailLifetime(1 - distance / visual.startDist, snapping)
			end
			if distance <= 0.35 or elapsed > 2 then
				table.remove(pulling, index)
				arrive(visual, target)
				continue
			end
		end
		if visual.piece then
			local facing = if (target - renderPosition).Magnitude > 0.01 then CFrame.lookAt(renderPosition, target) else CFrame.new(renderPosition)
			place(visual.piece, facing * CFrame.Angles(0, now * 12, 0), scale)
		end
	end

	-- Gone without us (expired, or someone else's): shrink away.
	for index = #leaving, 1, -1 do
		local visual = leaving[index]
		local t = math.clamp((now - visual.goneAt) / 0.3, 0, 1)
		if visual.piece then
			place(visual.piece, CFrame.new(visual.current or visual.home), 1 - t)
			fade(visual.piece, t)
		end
		if visual.tag then visual.tag.Enabled = false end
		if t >= 1 then
			dropVisual(visual)
			table.remove(leaving, index)
		end
	end

	if Feedback then Feedback.SetInFlight(#pulling) end

	if next(visuals) == nil and #pulling == 0 and #leaving == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- ===================== EVENTS =====================
CollectionService:GetInstanceAddedSignal(TAG):Connect(function(part) add(part) end)
for _, part in ipairs(CollectionService:GetTagged(TAG)) do
	add(part, true)
end

-- The server's confirmation (a batch per tick). Matched by position, since
-- the server part may already be gone.
local function confirm(entry)
	if typeof(entry.position) ~= "Vector3" then return 0 end
	local best, bestDistance = nil, 1.2
	local function consider(visual)
		if visual.confirmed then return end
		local distance = (visual.home - (entry.position + Vector3.new(0, 0.7, 0))).Magnitude
		if distance < bestDistance then best, bestDistance = visual, distance end
	end
	for _, visual in pairs(visuals) do consider(visual) end
	for _, visual in ipairs(pulling) do consider(visual) end
	for _, visual in ipairs(leaving) do consider(visual) end
	for _, visual in ipairs(recentlyArrived) do consider(visual) end
	if best then
		best.confirmed = true
		local at = table.find(recentlyArrived, best)
		if at then table.remove(recentlyArrived, at) end
		if not best.pullStart then
			-- Not predicted (e.g. range just changed): pull it in now.
			for part, visual in pairs(visuals) do
				if visual == best then visuals[part] = nil break end
			end
			local leavingAt = table.find(leaving, best)
			if leavingAt then table.remove(leaving, leavingAt) end
			startPull(best, best.current, false)
		end
	end
	return tonumber(entry.value) or 0
end

if dropCollected then
	dropCollected.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		local total = 0
		if type(payload.batch) == "table" then
			for _, entry in ipairs(payload.batch) do
				if type(entry) == "table" then total += confirm(entry) or 0 end
			end
		else
			total += confirm(payload) or 0   -- older single-piece message
		end
		-- What the server actually paid (combo bonus included) and its combo.
		if Feedback then Feedback.ServerCollected(total, payload.combo, payload.bonus) end
	end)
else
	warn("[StardustDropClient] BlackHoleRemotes.DropCollected is missing: update BlackHoleSystemServer.")
end


