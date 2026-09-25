-- CurrencyFeedbackConfig (ModuleScript)
-- Put in: ReplicatedStorage > CurrencyFeedbackConfig
--
-- Every tuning value for how collecting Stardust FEELS, in one place:
-- sound rhythm, pitch ladder, streak tiers, milestones, finishers, magnet
-- stream, HUD pulses, the combo meter and camera/haptic taps.
--
-- It also holds the COMBO REWARD (Combo.*). That part is read by the SERVER
-- (BlackHoleSystemServer), which counts the streak and pays the bonus. The
-- client only shows what the server reports, so nothing here lets a client
-- give itself Stardust.
--
-- Sound slots are GameSounds slot names. To give a moment its own audio,
-- paste a new id into that slot in GameSounds (or point it at another slot).

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
