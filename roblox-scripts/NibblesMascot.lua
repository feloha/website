-- NibblesMascot (ModuleScript)
-- Put in: ReplicatedStorage > NibblesMascot
--
-- Nibbles as an image-driven mascot: emotions, talking, blinking and a
-- gentle idle, all from the uploaded pictures. No loops or tweens of its
-- own: the owner calls :Update(now, talking, calm) every frame while
-- Nibbles is on screen, so nothing keeps running when it's hidden, nothing
-- can double up, and :Destroy() leaves nothing behind.
--
--   local m = NibblesMascot.new(parent, sizePx, zIndex)
--   m:SetEmotion("Playful")        -- the line's expression (fades in, little boing)
--   m:React("Amazed", 1.2)         -- a short reaction, then back to the line's emotion
--   m:Update(os.clock(), isTyping, reduceMotion)   -- every frame while shown
--   m:Destroy()
--
-- Talking: while isTyping is true Nibbles talks. On a Neutral line the mouth
-- pictures cycle at a natural, uneven pace. On an emotional line the
-- emotion shows first for a beat, then the mouth pictures take over, and
-- the emotion comes back when the line finishes. Strong emotions (angry,
-- upset, shocked, eyes closed) keep their face and "talk" with a small
-- bounce instead, so the expression never gets lost.
--
-- Blinking: every 2.5-5 s (sometimes a double blink), only on the neutral
-- face, because the eyes-closed picture is the neutral face.
--
-- Every picture is assumed to be the full Nibbles with the same framing.

local ContentProvider = game:GetService("ContentProvider")

local NibblesMascot = {}
NibblesMascot.__index = NibblesMascot

-- The picture ids live in ReplicatedStorage.UIAssets (UIAssets.Nibbles).
local UIAssets = require(game:GetService("ReplicatedStorage"):WaitForChild("UIAssets"))
NibblesMascot.Images = UIAssets.Nibbles
local IMG = NibblesMascot.Images

-- ===== TUNING =====
local FADE = 0.12                 -- seconds for an emotion crossfade
local EMOTION_LEAD = 0.55         -- emotional line: show the emotion this long before talking
local BLINK_MIN, BLINK_MAX = 2.5, 5
local BLINK_TIME = 0.11
local DOUBLE_BLINK = 0.15         -- chance a blink is a double blink
-- Mouth frames: the next frame is never the same as the last; open frames
-- hold a little longer than the closed one, and now and then there's a
-- short pause on the closed mouth, like between words.
local MOUTH_TIME = { Mouth1 = { 0.06, 0.10 }, Mouth2 = { 0.07, 0.12 }, Mouth3 = { 0.08, 0.13 } }
local WORD_PAUSE = { chance = 0.14, min = 0.14, max = 0.24 }
-- Emotions that keep their own face while talking (bounce instead of mouths).
NibblesMascot.KeepFaceWhileTalking = { Angry = true, Upset = true, Shocked = true, EyesClosed = true }

-- Preload once for every Nibbles.
local preloaded = false
local function preload()
	if preloaded then return end
	preloaded = true
	local list = {}
	for _, id in pairs(IMG) do table.insert(list, id) end
	task.spawn(function() pcall(ContentProvider.PreloadAsync, ContentProvider, list) end)
end

local function image(name, parent, z)
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.ScaleType = Enum.ScaleType.Fit
	label.ZIndex = z
	label.Parent = parent
	return label
end

function NibblesMascot.new(parent, size, z)
	preload()
	local self = setmetatable({}, NibblesMascot)
	z = z or 1

	-- holder: placed by the owner. body: the owner's pop (UIScale). face:
	-- this module's own motion (bob, sway, squash), so the two never fight.
	local holder = Instance.new("Frame")
	holder.Name = "Nibbles"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	holder.ZIndex = z
	holder.Parent = parent

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromScale(1, 1)
	body.BackgroundTransparency = 1
	body.ZIndex = z
	body.Parent = holder
	local pop = Instance.new("UIScale")
	pop.Parent = body

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundTransparency = 1
	face.ZIndex = z
	face.Parent = body

	-- Two stacked layers: back holds the old picture while front fades in.
	self.back = image("Back", face, z + 1)
	self.front = image("Front", face, z + 2)
	self.back.Image, self.front.Image = IMG.Neutral, IMG.Neutral

	-- Every picture kept warm (nearly invisible, 2x2) so swaps never flash blank.
	local warm = Instance.new("Frame")
	warm.Name = "Warm"
	warm.BackgroundTransparency = 1
	warm.Size = UDim2.fromOffset(2, 2)
	warm.ZIndex = z
	warm.Parent = holder
	for key, id in pairs(IMG) do
		local w = image(key, warm, z)
		w.ImageTransparency = 0.98
		w.Image = id
	end

	self.holder, self.body, self.pop, self.face, self.z = holder, body, pop, face, z
	self.size = size
	self.look = Vector2.zero            -- owner may set: where Nibbles is looking (-1..1)
	self.emotion = "Neutral"            -- the line's emotion
	self.react, self.reactUntil = nil, 0
	self.shown = "Neutral"              -- the picture on screen now
	self.fadeFrom = -1                  -- when the current fade started (-1 = none)
	self.boingAt = -10                  -- last emotion change (squash & stretch)
	self.talking, self.talkStarted = false, 0
	self.mouth, self.mouthUntil = "Mouth1", 0
	self.nextBlink, self.blinkUntil, self.blinksLeft = 0, 0, 0
	self.lastUpdate = 0
	return self
end

-- ===== EMOTIONS =====
local function valid(name)
	return name ~= nil and IMG[name] ~= nil and not string.match(name, "^Mouth")
end

function NibblesMascot:SetEmotion(name)
	if not valid(name) then name = "Neutral" end
	if name == self.emotion and self.react == nil then return end
	self.emotion = name
	self.react = nil
	self.boingAt = os.clock()
	if self.talking then self.talkStarted = os.clock() end   -- lead with the new face
end

function NibblesMascot:React(name, seconds)
	if not valid(name) then return end
	self.react, self.reactUntil = name, os.clock() + (seconds or 1.2)
	self.boingAt = os.clock()
end

function NibblesMascot:GetEmotion()
	return self.react or self.emotion
end

-- ===== PICTURE SWAPS =====
function NibblesMascot:_show(key, now, fade)
	if key == self.shown then return end
	local id = IMG[key]
	if fade then
		-- Old picture stays on the back layer while the new one fades in.
		self.back.Image = self.front.Image
		self.back.ImageTransparency = 0
		self.front.Image = id
		self.front.ImageTransparency = 1
		self.fadeFrom = now
	else
		-- Blinks and mouth frames swap instantly (a fade would ghost).
		self.front.Image = id
		self.front.ImageTransparency = 0
		self.back.Image = id
		self.fadeFrom = -1
	end
	self.shown = key
end

local function pick(range) return range[1] + math.random() * (range[2] - range[1]) end

function NibblesMascot:_nextMouth(now)
	if self.mouth ~= "Mouth1" and math.random() < WORD_PAUSE.chance then
		self.mouth = "Mouth1"
		self.mouthUntil = now + WORD_PAUSE.min + math.random() * (WORD_PAUSE.max - WORD_PAUSE.min)
		return
	end
	local options = {}
	for _, key in ipairs({ "Mouth1", "Mouth2", "Mouth3" }) do
		if key ~= self.mouth then table.insert(options, key) end
	end
	self.mouth = options[math.random(#options)]
	self.mouthUntil = now + pick(MOUTH_TIME[self.mouth])
end

-- ===== EVERY FRAME =====
function NibblesMascot:Update(now, talking, calm)
	if not self.holder.Parent then return end

	-- Back after being hidden: restart the timers instead of catching up.
	if now - self.lastUpdate > 0.5 then
		self.nextBlink = now + BLINK_MIN + math.random() * (BLINK_MAX - BLINK_MIN)
		self.blinkUntil, self.blinksLeft = 0, 0
		self.mouthUntil = 0
	end
	self.lastUpdate = now

	if self.react and now >= self.reactUntil then
		self.react = nil
		self.boingAt = now
	end
	local emotion = self.react or self.emotion

	-- Talking starts and stops with the typing.
	talking = talking == true
	if talking ~= self.talking then
		self.talking = talking
		self.talkStarted = now
		self.mouth, self.mouthUntil = "Mouth1", 0
	end

	-- What the face should be right now.
	local keepFace = NibblesMascot.KeepFaceWhileTalking[emotion] == true
	local target, fade = emotion, true
	local mouthing = talking and not keepFace
		and (emotion == "Neutral" or now - self.talkStarted >= EMOTION_LEAD)
		and self.react == nil
	if mouthing then
		if now >= self.mouthUntil then self:_nextMouth(now) end
		target, fade = self.mouth, false
	end

	-- Blinks: only on the neutral face (the eyes-closed picture is neutral).
	local neutralFace = target == "Neutral" or string.match(target, "^Mouth") ~= nil
	if now >= self.nextBlink then
		if neutralFace then
			self.blinkUntil = now + BLINK_TIME
			if self.blinksLeft > 0 then
				self.blinksLeft -= 1
				self.nextBlink = now + BLINK_TIME + 0.09
			else
				self.blinksLeft = if math.random() < DOUBLE_BLINK then 1 else 0
				self.nextBlink = now + (if self.blinksLeft > 0 then BLINK_TIME + 0.09
					else BLINK_MIN + math.random() * (BLINK_MAX - BLINK_MIN))
			end
		else
			self.nextBlink = now + 0.4   -- try again soon, once the face is neutral
		end
	end
	if neutralFace and now < self.blinkUntil then
		target, fade = "EyesClosed", false
	end

	-- Coming out of a mouth frame or blink into an emotion still fades.
	if target == emotion and (string.match(self.shown, "^Mouth") or self.shown == "EyesClosed") and emotion ~= "Neutral" then
		fade = true
	elseif target == "Neutral" then
		fade = false   -- Neutral is Mouth1: same picture family, no fade needed
	end
	self:_show(target, now, fade and not calm)

	-- Crossfade progress.
	if self.fadeFrom >= 0 then
		local a = math.clamp((now - self.fadeFrom) / FADE, 0, 1)
		self.front.ImageTransparency = 1 - a
		if a >= 1 then
			self.back.Image = self.front.Image
			self.fadeFrom = -1
		end
	end

	-- Motion: a gentle bob and sway, a breath, a squash & stretch "boing" on
	-- every emotion change, a little bounce while talking, a lean toward
	-- whatever Nibbles is looking at.
	if calm then
		self.face.Position = UDim2.fromScale(0.5, 0.5)
		self.face.Rotation = 0
		self.face.Size = UDim2.fromScale(1, 1)
		return
	end
	local k = self.size / 120
	local look = self.look
	local bob = math.sin(now * 2.2) * 4 * k
	local sway = math.sin(now * 1.3) * 2.5 + look.X * 3
	local breath = math.sin(now * 2.2 + 0.6) * 0.015
	local t = now - self.boingAt
	local boing = if t < 0.6 then math.exp(-t * 7) * math.cos(t * 22) * 0.09 else 0
	local speak = if talking then math.abs(math.sin(now * 13)) * (if keepFace then 0.035 else 0.018) else 0
	local sx = 1 + breath + boing - speak * 0.5
	local sy = 1 - breath - boing + speak
	self.face.Position = UDim2.new(0.5, look.X * 3 * k, 0.5, bob + look.Y * 2 * k - (sy - 1) * self.size * 0.5)
	self.face.Rotation = sway
	self.face.Size = UDim2.fromScale(sx, sy)
end

function NibblesMascot:Destroy()
	if self.holder then self.holder:Destroy() end
end

return NibblesMascot
