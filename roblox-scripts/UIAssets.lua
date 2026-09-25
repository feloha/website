-- UIAssets (ModuleScript in ReplicatedStorage)  -- NEW
-- The one place image asset IDs live. Nothing else in the game should hold a
-- raw store/currency image id: require this module and read a field.
--
--   local UIAssets = require(ReplicatedStorage:WaitForChild("UIAssets"))
--   icon.Image = UIAssets.Stardust
--   art.Image  = UIAssets.CardArt[item.Key] or UIAssets.Stardust
--   UIAssets.Preload("Primary")
--
-- These are IMAGE ids. They are never game pass ids or developer product ids:
-- those stay in StoreConfig / MutationConfig / ThievingTimeConfig and are not
-- touched by this module.
--
-- Every id here is an IMAGE asset (type 1), resolved from the Decal you
-- uploaded. A decal only wraps an image, and ImageLabel.Image needs the image
-- itself, which is why the decal ids rendered blank. If you upload more art,
-- run ResolveDecals in the command bar again and paste the numbers it prints.

local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local UIAssets = {}

-- ===================== SECRET STORE =====================
UIAssets.SecretStore = "rbxassetid://123895222264336"   -- "Secret Store" logo lettering
UIAssets.Shop = "rbxassetid://83316284173612"          -- big cart + star, store header
UIAssets.SmallStoreCart = "rbxassetid://122002324615343" -- compact cart, HUD / small accents

UIAssets.Gift = "rbxassetid://74259272595957"
UIAssets.Close = "rbxassetid://133520535721772"
UIAssets.Buy = "rbxassetid://70533342004042"
UIAssets.Info = "rbxassetid://106868908533108"

-- ===================== GAME PASS ART =====================
UIAssets.AutoMerge = "rbxassetid://93261776801518"
UIAssets.DoubleSpawn = "rbxassetid://121203440564239"
UIAssets.DoubleHealth = "rbxassetid://95179354421379"
UIAssets.LaunchCooldown = "rbxassetid://94499867719554"
UIAssets.ProtectionCooldown = "rbxassetid://110453136853552"

-- StoreConfig.Key -> artwork. Keys must match StoreConfig exactly.
UIAssets.CardArt = {
	AutoMerge = UIAssets.AutoMerge,
	X2Spawn = UIAssets.DoubleSpawn,
	X2BlackHoleHP = UIAssets.DoubleHealth,
	QuickerProtectionCooldown = UIAssets.ProtectionCooldown,
	QuickerLaunchCooldown = UIAssets.LaunchCooldown,
}

-- ===================== SIDE MENU ICONS =====================
-- One artwork per navigation button. MainHUD reads this map, so the icon for
-- a button is changed here and nowhere else.
UIAssets.NavStore = UIAssets.SmallStoreCart
UIAssets.NavLeaderboards = "rbxassetid://86490020256477"   -- podium, 1st / 2nd / 3rd
UIAssets.NavIndex = "rbxassetid://75428035958138"           -- collection book
UIAssets.NavRebirth = "rbxassetid://103972029992761"         -- rebirth arrows
UIAssets.NavInventory = "rbxassetid://130558862254177"       -- treasure chest

UIAssets.NavIcons = {
	Store = UIAssets.NavStore,
	Leaderboards = UIAssets.NavLeaderboards,
	Index = UIAssets.NavIndex,
	Rebirth = UIAssets.NavRebirth,
	Inventory = UIAssets.NavInventory,
}

-- ===================== TOP ACTION BUTTONS =====================
-- The two controls at the top of the HUD. Each is a finished button (face,
-- icon, wording, outline), so MainHUD draws nothing on top of them except the
-- live protection timer, which is never baked into the art.
--   Upgrade    the green UPGRADE button
--   LockBase   the red LOCK BASE button, shown while the base is unprotected
--   Protected  the blue PROTECTED button, shown in the same place while the
--              server says the base is protected
UIAssets.TopButtons = {
	Upgrade = "rbxassetid://107921295698478",
	LockBase = "rbxassetid://93561466501948",
	Protected = "rbxassetid://82767066336756",
}

-- ===================== PAINTED BACKGROUNDS =====================
-- Image ids, not decal ids. A decal only wraps an image and can never render
-- in an ImageLabel, which is what kept these blank.
UIAssets.StoreBackground = "rbxassetid://123727857172492"   -- Secret Store interior
UIAssets.CodeIcon = "rbxassetid://93617937032122"           -- code field icon

UIAssets.OfflineClock = "rbxassetid://99827121647352"       -- 2x offline time icon

-- The whole Playtime Awards button as one graphic. Paste its IMAGE id between
-- the quotes and MainHUD swaps the drawn button for it; left empty, the drawn
-- button stays exactly as it is.
UIAssets.PlaytimeButton = "rbxassetid://124105198585397"

-- The "you have something to collect" badge on the Playtime Awards button.
UIAssets.PlaytimeAlert = "rbxassetid://135785875501572"

-- ===================== PLAYTIME REWARD ARTWORK =====================
-- One entry per reward kind. The keys match RewardIcons' own kind names
-- exactly, so that module can look artwork up by kind and fall back to its
-- drawn version when an entry is missing.
UIAssets.RewardArt = {
	stardust = "rbxassetid://130390523658949",
	xp = "rbxassetid://117919184371851",
	gems = "rbxassetid://123977876638754",
	damage = "rbxassetid://132449769800646",
	spawn = "rbxassetid://122903172998652",
	shield = "rbxassetid://108881699814665",
	luck = "rbxassetid://110033730777438",
	jackpot = "rbxassetid://84745703568604",

	-- Boost artwork. The kind names come from ProgressionConfig.Boosts:
	-- WarpSpeed.Icon = "speed", RapidLaunch.Icon = "cooldown". Adding them here
	-- retires the drawn arrow and the drawn stopwatch that stood in for them.
	speed = "rbxassetid://134412886131412",
	cooldown = "rbxassetid://136782107876685",
}

-- Playtime Rewards button artwork. Each of the four is a finished button with
-- its own wording, so nothing is drawn or labelled on top of them.
--   Claim / Claimed  belong on an individual reward card.
--   ClaimAll / AllClaimed belong on the progress strip, and only there.
UIAssets.PlaytimeButtons = {
	Claim = "rbxassetid://74942876685859",
	Claimed = "rbxassetid://129832600316409",
	ClaimAll = "rbxassetid://138868484219249",
	AllClaimed = "rbxassetid://88112779333588",
}

-- ===================== PODIUM ARTWORK =====================
-- Painted pedestals. Each one already carries its own number, its base glow,
-- and - on first place - the crown, so the leaderboard draws nothing on top
-- of them.
UIAssets.Podium1 = "rbxassetid://101174544455202"   -- gold, crowned
UIAssets.Podium2 = "rbxassetid://75548246301451"    -- icy silver
UIAssets.Podium3 = "rbxassetid://74771437305163"    -- bronze

-- Standalone halo rings. One per leaderboard category, and the blue one again
-- as the platform the whole window floats on.
UIAssets.HaloBlue = "rbxassetid://106939122701651"
UIAssets.HaloPink = "rbxassetid://78887331230742"
UIAssets.HaloGold = "rbxassetid://84889842940788"

-- ===================== LEADERBOARD TABS =====================
UIAssets.TabDaily = "rbxassetid://129318916252207"
UIAssets.TabWeekly = "rbxassetid://95687656073445"

-- The "New day in" pill on Playtime Rewards reuses the Weekly artwork on
-- purpose. It points at the entry above rather than repeating the number, so
-- the id still has exactly one definition - and it has to come after it,
-- because a table field that is read before it is written is simply nil.
UIAssets.PlaytimeCalendar = UIAssets.TabWeekly

-- ===================== LEADERBOARD ICONS =====================
-- Category icons for the Elites board. Top Stardust deliberately uses the
-- Stardust coin above, not a gem.
UIAssets.Stopwatch = "rbxassetid://105653177829681"  -- Time Played
UIAssets.Swords = "rbxassetid://97191963985901"      -- Most Attacks
UIAssets.Globe = "rbxassetid://73942702249998"       -- Elites header accent

-- ===================== CURRENCY =====================
UIAssets.Stardust = "rbxassetid://89369557479017"              -- general Stardust icon
UIAssets.WelcomeBackStardust = "rbxassetid://134976592390975"    -- offline reward medallion only
UIAssets.Gems = "rbxassetid://79278647871266"

-- ===================== BADGES =====================
UIAssets.NewTag = "rbxassetid://124914741767565"    -- only when store data says New
UIAssets.Sale = "rbxassetid://104080170617087"       -- only when store data says Sale
UIAssets.Crown = "rbxassetid://135705526747671"      -- premium / VIP content only

-- ===================== DECORATION =====================
UIAssets.Planet = "rbxassetid://135076445992920"
UIAssets.Galaxy = "rbxassetid://93969542914175"
UIAssets.YellowGalaxy = "rbxassetid://93833999038081"
UIAssets.BlueEnergyRing = "rbxassetid://119658072258382"
UIAssets.PinkCometRing = "rbxassetid://72328160938475"
UIAssets.Cloud = "rbxassetid://88723520468139"
UIAssets.Lightning = "rbxassetid://121834893329509"
UIAssets.BlueSpeed = "rbxassetid://109448628829235"
UIAssets.CyanStar = "rbxassetid://135225365902753"
UIAssets.StarVariant1 = "rbxassetid://78712430901142"
UIAssets.StarVariant2 = "rbxassetid://136222286155499"

-- ===================== CURRENCY HUD =====================
-- The Stardust + Gems counters (MainHUD). The three stars are decoration
-- only - never a currency.
UIAssets.CurrencyHUD = {
	Stardust = UIAssets.Stardust,                    -- rbxassetid://89369557479017
	Gems = UIAssets.Gems,                            -- the game's existing gem
	GoldStar = "rbxassetid://78712430901142",
	BlueStar = "rbxassetid://135225365902753",
	PurpleStar = "rbxassetid://136222286155499",
}

-- ===================== ILLUSTRATED HUD PANELS =====================
-- The Stardust / Gems counters (MainHUD) and the COMBO meter
-- (StardustDropClient) are these pictures, with only the live icon, numbers
-- and the combo bar's moving fill placed on top. The pictures already carry
-- their borders, gloss, sparkles and (combo) the bar track - nothing of that
-- is redrawn in code.
UIAssets.HudArt = {
	StardustBackground = "rbxassetid://77156951478290",
	GemsBackground = "rbxassetid://87071070786550",
	ComboBackground = "rbxassetid://104569952486705",
	ComboTitle = "rbxassetid://91816350219790",
	StardustWord = "rbxassetid://110132748863072",   -- the word STARDUST (counter + combo bonus)

	-- COMBO RANK: the letter shown on the combo meter. A rank applies from
	-- MinCombo pieces in a streak up to the next rank. Tune here only.
	ComboRanks = {
		{ MinCombo = 1, Rank = "C", Image = "rbxassetid://104528681758299" },
		{ MinCombo = 15, Rank = "B", Image = "rbxassetid://117698059499772" },
		{ MinCombo = 40, Rank = "A", Image = "rbxassetid://103134191590240" },
		{ MinCombo = 80, Rank = "S", Image = "rbxassetid://87563099967316" },
		{ MinCombo = 150, Rank = "S+", Image = "rbxassetid://130351499085257" },
	},

	-- Design height of the Stardust and Gems panels (1280x720 design,
	-- scaled to the screen by MainHUD). The width follows each picture.
	CurrencyHeight = 74,

	-- Measured from the supplied PNG files (nothing is measured in game):
	--   Image  the picture's width / height
	--   Body   where the painted panel sits inside the picture, as shares
	--          { left, top, right, bottom } - the transparent margin and any
	--          sparkles poking out are outside it.
	--   Content (title) where the letters sit.
	Geometry = {
		Stardust = { Image = 2000 / 667, Body = { 0.0370, 0.0990, 0.9630, 0.8846 } },
		Gems = { Image = 1774 / 887, Body = { 0.0575, 0.1736, 0.9436, 0.8095 } },
		Combo = { Image = 2000 / 667, Body = { 0.0260, 0.1139, 0.9750, 0.8966 } },
		ComboTitle = { Image = 1774 / 887, Content = { 0.0755, 0.2864, 0.9250, 0.7644 } },
		StardustWord = { Image = 2000 / 667, Content = { 0.0160, 0.2189, 0.9870, 0.8126 } },
	},

	-- Where things sit, as shares of the PAINTED PANEL BODY.
	--   Icon  = { centre x, centre y, size as a share of the panel height }
	--   boxes = { left, top, width, height }
	-- Placed clear of the sparkles painted into each picture.
	Layout = {
		Stardust = {
			Icon = { 0.17, 0.53, 0.66 },           -- centred in the left zone, clear of every edge
			Amount = { 0.29, 0.15, 0.56, 0.44 },
			Label = { 0.29, 0.585, 0.56, 0.20 },   -- the STARDUST word picture, centred under the amount
		},
		Gems = {
			Icon = { 0.25, 0.505, 0.60 },
			Amount = { 0.39, 0.215, 0.46, 0.60 },
		},
		Combo = {
			Title = { 0.065, 0.11, 0.23, 0.23 },       -- medium prominence
			Count = { 0.075, 0.31, 0.30, 0.41 },       -- xN, strongest on the left; clear of the bar
			Star = { 0.625, 0.37, 0.34 },
			Bonus = { 0.69, 0.19, 0.22, 0.36 },         -- +N%, strongest on the right
			BonusLabel = { 0.60, 0.58, 0.26, 0.14 },   -- the STARDUST word picture (supporting)
			Rank = { 0.40, 0.45, 0.58 },                -- the rank letter: centre x, centre y, size (share of height)
			-- The moving fill sits INSIDE the painted track: { left, top, right, bottom }.
			Track = { 0.0935, 0.7790, 0.9054, 0.8705 },
		},
	},
}

-- ===== NIBBLES (tutorial mascot, NibblesMascot) =====
-- Every picture is the whole of Nibbles with the same framing. Neutral is the
-- closed-mouth talking frame.
UIAssets.Nibbles = {
	Blushing = "rbxassetid://70691878126737",
	Upset = "rbxassetid://122404952866972",
	Shocked = "rbxassetid://85130285540390",
	Playful = "rbxassetid://70995287574810",
	Angry = "rbxassetid://126709772551918",
	EyesClosed = "rbxassetid://84548029673100",
	Amazed = "rbxassetid://132229487162843",
	Mouth1 = "rbxassetid://131213893431491",
	Mouth2 = "rbxassetid://139922076393726",
	Mouth3 = "rbxassetid://131127521848463",
}
UIAssets.Nibbles.Neutral = UIAssets.Nibbles.Mouth1

-- ===== TUTORIAL DIALOG (TutorialClient) =====
-- Geometry: where the artwork sits inside each picture, as { left, top,
-- right, bottom } shares of the image (measured from the PNGs); Aspect is
-- the artwork's own width / height.
UIAssets.TutorialArt = {
	GalaxyBackground = "rbxassetid://113502671964481",
	LetsGoButton = "rbxassetid://127222506770828",
	NibblesBadge = "rbxassetid://121888844240070",
	SkipTutorial = "rbxassetid://99037494730667",
	SkipStep = "rbxassetid://130889779859380",
	YouMadeIt = "rbxassetid://129021587359341",   -- celebration when the tutorial is done
	-- Illustrated objective banners, shown instead of the plain hint text.
	Objectives = {
		WatchStardust = "rbxassetid://86877161326333",
		WalkIntoBlackHole = "rbxassetid://122237836602451",
		PickUpBlackHole = "rbxassetid://82625798312711",
		MergeBlackHoles = "rbxassetid://94795140270939",   -- tier-agnostic on purpose
		AttackTarget = "rbxassetid://134145967170116",
		CanAffordUpgrade = "rbxassetid://113562780091772",
		LockBase = "rbxassetid://91883066832989",
	},
	-- Shown when a step is completed; never the same one twice in a row.
	Success = {
		"rbxassetid://122637358375013",   -- Awesome
		"rbxassetid://128928422091057",   -- Stellar
		"rbxassetid://133659847875947",   -- Exclesoir
		"rbxassetid://101439079799905",   -- Amazing
	},
	Geometry = {
		Panel = { Rect = { 0.054, 0.054, 0.909, 0.909 }, Aspect = 3.0 },   -- the visible border inside a 3:1 picture (measured in game)
		Badge = { Rect = { 0.221, 0.219, 0.7785, 0.778 }, Aspect = 2.99 },
		LetsGo = { Rect = { 0.128, 0.105, 0.8715, 0.886 }, Aspect = 2.854 },
		Skip = { Rect = { 0.045, 0.12, 0.956, 0.85 }, Aspect = 3.74 },
		SkipStep = { Rect = { 0.027, 0.066, 0.976, 0.907 }, Aspect = 3.38 },
		YouMadeIt = { Rect = { 0.063, 0.174, 0.942, 0.817 }, Aspect = 4.1 },
		-- Measured from "Watch your Stardust climb"; the other banners share its framing.
		Objective = { Rect = { 0.014, 0.156, 0.987, 0.85 }, Aspect = 4.2 },
		-- Awesome / Stellar / Exclesoir / Amazing: not measured yet, whole picture shown.
		Success = { Rect = { 0, 0, 1, 1 }, Aspect = 3 },
	},
}

-- Fits a picture into `frame` so that `rect` (shares of the picture, e.g. its
-- Body) fills the frame exactly: the rest hangs outside, nothing is stretched.
-- Returns the body's width / height, which the frame should have.
function UIAssets.FitArt(art, rect)
	local w, h = rect[3] - rect[1], rect[4] - rect[2]
	art.Size = UDim2.fromScale(1 / w, 1 / h)
	art.Position = UDim2.fromScale(-rect[1] / w, -rect[2] / h)
end
-- A word/title picture trimmed to its letters inside `box`: keeps its own
-- shape (never stretched), centred in the box. Returns the ImageLabel.
function UIAssets.WordImage(box, image, geometry, z)
	local shape = Instance.new("UIAspectRatioConstraint")
	shape.AspectRatio = UIAssets.BodyAspect(geometry, "Content")
	local holder = Instance.new("Frame")
	holder.Name = "Word"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.ZIndex = z or 1
	shape.Parent = holder
	holder.Parent = box
	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.Image = image or ""
	art.ScaleType = Enum.ScaleType.Fit
	art.ZIndex = z or 1
	art.Parent = holder
	UIAssets.FitArt(art, geometry.Content)
	return art
end
function UIAssets.BodyAspect(geometry, key)
	local rect = geometry[key or "Body"]
	return geometry.Image * (rect[3] - rect[1]) / (rect[4] - rect[2])
end

-- Reads a picture's own pixels once (EditableImage) to find:
--   Size     its size in pixels
--   Content  everything not transparent, as shares of the picture
--            { x0, y0, x1, y1 } (used for the COMBO title letters)
--   Body     the solid panel itself - sparkles sticking out past it are
--            ignored - as shares of the picture (used for the panels)
--   Track    (findTrack) the inner area of the dark bar track in the lower
--            part of the panel, as shares of Body { x0, y0, x1, y1 }
-- The callback gets that table, or nil when the pixels can't be read (then
-- the Layout numbers above are used as they are). Never yields the caller.
local measuredArt = {}
local measureWaiting = {}
function UIAssets.MeasureArt(id, findTrack, callback)
	local key = tostring(id) .. (if findTrack then "|track" else "")
	if measuredArt[key] ~= nil then
		task.spawn(callback, measuredArt[key] or nil)
		return
	end
	if measureWaiting[key] then
		table.insert(measureWaiting[key], callback)
		return
	end
	measureWaiting[key] = { callback }
	task.spawn(function()
		local info = false
		local ok, err = pcall(function()
			local image = game:GetService("AssetService"):CreateEditableImageAsync(Content.fromUri(id))
			local size = image.Size
			local w, h = math.floor(size.X), math.floor(size.Y)
			local pixels = image:ReadPixelsBuffer(Vector2.zero, size)
			image:Destroy()
			local function at(x, y)
				local i = (y * w + x) * 4
				return buffer.readu8(pixels, i), buffer.readu8(pixels, i + 1), buffer.readu8(pixels, i + 2), buffer.readu8(pixels, i + 3)
			end

			-- Everything not transparent (Content), and how much of each column
			-- and row is solid: the panel body is where most of it is, so a
			-- sparkle poking out past the edge doesn't count.
			local step = math.max(1, math.floor(math.min(w, h) / 320))
			local x0, y0, x1, y1 = w, h, -1, -1
			local columns, rows = {}, {}
			for y = 0, h - 1, step do
				for x = 0, w - 1, step do
					local _, _, _, a = at(x, y)
					if a > 60 then
						if x < x0 then x0 = x end
						if x > x1 then x1 = x end
						if y < y0 then y0 = y end
						if y > y1 then y1 = y end
						columns[x] = (columns[x] or 0) + 1
						rows[y] = (rows[y] or 0) + 1
					end
				end
			end
			if x1 < 0 then error("the picture is empty") end
			local maxColumn, maxRow = 0, 0
			for _, n in pairs(columns) do maxColumn = math.max(maxColumn, n) end
			for _, n in pairs(rows) do maxRow = math.max(maxRow, n) end
			local bx0, bx1, by0, by1 = w, -1, h, -1
			for x, n in pairs(columns) do
				if n >= maxColumn * 0.3 then
					bx0 = math.min(bx0, x)
					bx1 = math.max(bx1, x)
				end
			end
			for y, n in pairs(rows) do
				if n >= maxRow * 0.3 then
					by0 = math.min(by0, y)
					by1 = math.max(by1, y)
				end
			end
			bx1 = math.min(bx1 + step, w)
			by1 = math.min(by1 + step, h)
			x1 = math.min(x1 + step, w)
			y1 = math.min(y1 + step, h)
			info = {
				Size = size,
				Content = { x0 / w, y0 / h, x1 / w, y1 / h },
				Body = { bx0 / w, by0 / h, bx1 / w, by1 / h },
			}

			if findTrack then
				-- The track: rows in the lower part of the body with a long run
				-- of dark navy (about RGB 2,22,90 in the art; the surface around
				-- it is lighter, the outer border lower and excluded).
				local cw, ch = bx1 - bx0, by1 - by0
				local band = {}
				for y = by0 + math.floor(ch * 0.5), by0 + math.floor(ch * 0.92) do
					local best, bestStart, run, runStart = 0, 0, 0, 0
					for x = bx0, bx1 - 1, 2 do
						local r, g, b, a = at(x, y)
						if a > 200 and r + g + b < 140 and b < 118 then
							if run == 0 then runStart = x end
							run += 2
							if run > best then best, bestStart = run, runStart end
						else
							run = 0
						end
					end
					if best >= cw * 0.4 then
						table.insert(band, { y = y, x0 = bestStart, x1 = bestStart + best })
					end
				end
				-- The longest stretch of consecutive rows is the track.
				local bestFrom, bestTo, from = 1, 0, 1
				for i = 2, #band + 1 do
					if i > #band or band[i].y ~= band[i - 1].y + 1 then
						if i - from > bestTo - bestFrom + 1 then bestFrom, bestTo = from, i - 1 end
						from = i
					end
				end
				if bestTo - bestFrom >= 3 then
					local tx0, tx1 = math.huge, -math.huge
					for i = bestFrom, bestTo do
						tx0 = math.min(tx0, band[i].x0)
						tx1 = math.max(tx1, band[i].x1)
					end
					local ty0, ty1 = band[bestFrom].y, band[bestTo].y + 1
					-- A small inset, so the fill sits inside the dark groove.
					local inset = (ty1 - ty0) * 0.14
					info.Track = {
						(tx0 + inset - bx0) / cw, (ty0 + inset - by0) / ch,
						(tx1 - inset - bx0) / cw, (ty1 - inset - by0) / ch,
					}
				end
			end
		end)
		if not ok and RunService:IsStudio() then
			warn(("[UIAssets] Couldn't read the pixels of %s (%s). The HUD uses the Layout numbers in UIAssets.HudArt instead.")
				:format(tostring(id), tostring(err)))
		elseif ok and RunService:IsStudio() then
			local c = info.Body
			print(("[UIAssets] %s: %dx%d, panel body %.3f,%.3f -> %.3f,%.3f (%.2f:1)%s"):format(tostring(id), info.Size.X, info.Size.Y,
				c[1], c[2], c[3], c[4], ((c[3] - c[1]) * info.Size.X) / math.max((c[4] - c[2]) * info.Size.Y, 1),
				if info.Track then (" | bar track %.3f,%.3f -> %.3f,%.3f"):format(table.unpack(info.Track))
					elseif findTrack then " | bar track NOT found, using Layout.Combo.Track" else ""))
		end
		measuredArt[key] = info
		local waiting = measureWaiting[key]
		measureWaiting[key] = nil
		for _, fn in ipairs(waiting) do task.spawn(fn, info or nil) end
	end)
end

-- ===================== UPGRADE WINDOW =====================
-- Artwork for the Upgrade window (MainHUD). The window waits for these
-- before it opens. Any entry left "" (or that fails to load) is drawn in
-- code instead, so a missing picture never leaves a hole.
UIAssets.UpgradeArt = {
	Title = "rbxassetid://96699644959066",           -- "Upgrade" lettering
	HeaderArrow = "rbxassetid://90686940818886",     -- big green arrow in the header
	Maxed = "rbxassetid://109772945126483",          -- the MAXED button, lettering included
	Close = "rbxassetid://133520535721772",          -- the window's X button
	Background = "rbxassetid://126061295065393",     -- the whole window picture (frame included)
	BackgroundScaleType = "Stretch",                 -- "Stretch" = window size exactly, "Fit" = keep the picture's shape

	-- One finished hero picture per card, keyed by UpgradeConfig id
	-- (CoinDropRate is the Cosmic Fortune card).
	Icons = {
		SpawnTier = "rbxassetid://96805522026672",
		MaxSpawn = "rbxassetid://92273374788724",
		LockBase = "rbxassetid://124265326446840",       -- the card's shield, not the HUD button
		CoinDropRate = "rbxassetid://111525965250803",   -- Cosmic Fortune
		CurrencyMagnet = "rbxassetid://78464863449136",
	},
	-- Every hero picture is fitted to its card's art area. Raise this (e.g.
	-- 1.15) if the uploads have wide transparent margins and look small.
	HeroScale = 1,

	-- One finished pink name label per card (lettering included), keyed the
	-- same way. It replaces the drawn pink title bar on that card.
	Labels = {
		SpawnTier = "rbxassetid://102625574329107",
		MaxSpawn = "rbxassetid://113444394452750",
		LockBase = "rbxassetid://90521207487151",
		CoinDropRate = "rbxassetid://96766773062692",    -- Cosmic Fortune
		CurrencyMagnet = "rbxassetid://106006795757663",
	},

	Planet = "",                             -- "" = drawn purple ringed planet
	Cloud = "",                              -- "" = drawn cloud banks
	GoldStar = UIAssets.StarVariant1,        -- large stars on the frame edge

	-- Pieces the drawn fallbacks use if a hero picture cannot load.
	Galaxy = UIAssets.Galaxy,                -- Spawn Tier vortex
	Shield = UIAssets.RewardArt.shield,      -- Lock Base shield
	DrawLockOnShield = true,                 -- false if the shield art has its own lock
	FortuneStar = UIAssets.StarVariant1,     -- Cosmic Fortune star
	Coin = UIAssets.Stardust,                -- coins by the magnet
}

-- ===================== REBIRTH WINDOW =====================
-- Artwork for the Rebirth window. Every entry is optional: "" means
-- RebirthClient draws that piece itself. Paste IMAGE ids as they come in.
UIAssets.RebirthArt = {
	HeaderVortex = "",        -- swirling vortex, top-left of the header
	Planet = "",              -- ringed planet, top-right of the header
	CounterRing = "",         -- the glowing black hole the rebirth count sits in
	ButtonIcon = "",          -- circular arrows on the REBIRTH button
	Cloud = "",               -- cloud banks at the bottom corners
	GoldStar = UIAssets.StarVariant1,

	-- One icon per reward row.
	RewardIcons = {
		Income = UIAssets.Stardust,   -- Stardust income
		SpawnSpeed = "",              -- spawn speed (drawn spiral when empty)
		UpgradeCaps = "",             -- upgrade caps (drawn green arrow when empty)
		StartingTier = "",            -- starting tier (drawn chevrons when empty)
	},

	-- One icon per requirement kind (RebirthConfig.GetRequirements).
	RequirementIcons = {
		Tier = "",                    -- drawn gauge when empty
		Stardust = UIAssets.Stardust,
		BlackHoles = "",              -- drawn ring when empty
		UpgradesAtCap = "",           -- drawn padlock when empty
	},
}

-- ===================== PRELOADING =====================
-- Primary: everything the Store shows the moment it opens.
UIAssets.Primary = {
	UIAssets.StoreBackground,
	UIAssets.SecretStore, UIAssets.Shop, UIAssets.Gift, UIAssets.Close, UIAssets.Buy,
	UIAssets.AutoMerge, UIAssets.DoubleSpawn, UIAssets.DoubleHealth,
	UIAssets.LaunchCooldown, UIAssets.ProtectionCooldown,
	UIAssets.Stardust, UIAssets.CodeIcon, UIAssets.OfflineClock,
	UIAssets.Planet, UIAssets.StarVariant1, UIAssets.StarVariant2, UIAssets.CyanStar,
	UIAssets.WelcomeBackStardust, UIAssets.Gems,
	UIAssets.Stopwatch, UIAssets.Swords, UIAssets.Globe,
	UIAssets.Podium1, UIAssets.Podium2, UIAssets.Podium3,
	UIAssets.HaloBlue, UIAssets.HaloPink, UIAssets.HaloGold,
}

-- Nav: the side menu icons, on screen from the moment the player joins.
UIAssets.Nav = {
	UIAssets.NavStore, UIAssets.NavLeaderboards,
	UIAssets.NavIndex, UIAssets.NavRebirth, UIAssets.NavInventory,
	UIAssets.PlaytimeButton, UIAssets.PlaytimeAlert,
}

-- Secondary: decoration. Never worth blocking on.
UIAssets.Secondary = {
	UIAssets.Planet, UIAssets.Galaxy, UIAssets.YellowGalaxy,
	UIAssets.BlueEnergyRing, UIAssets.PinkCometRing, UIAssets.Cloud,
	UIAssets.Lightning, UIAssets.BlueSpeed,
}

-- Did this image actually load? An id that is a Decal, unmoderated or simply
-- wrong still sets Image fine and then draws nothing, so anything with a drawn
-- fallback asks here first and keeps its fallback when the answer is no.
-- Never yields the caller: the answer arrives in the callback.
function UIAssets.WhenReady(id, callback)
	if type(id) ~= "string" or id == "" then
		task.spawn(callback, false)
		return
	end

	task.spawn(function()
		local loaded = false
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ id }, function(_, status)
				loaded = status == Enum.AssetFetchStatus.Success
			end)
		end)
		callback(ok and loaded)
	end)
end

-- Turns a button artwork id into something an ImageLabel can actually draw.
-- An IMAGE id is used as it is. A DECAL id cannot be drawn directly (it only
-- wraps an image), so when the plain id does not load, the decal's thumbnail
-- is used instead: Roblox renders a decal's thumbnail as its image, fitted
-- into a 420x420 square. The callback gets (url, square):
--   url     what to put in ImageLabel.Image, or nil if neither form loaded
--   square  true when url is the square thumbnail, so the caller can size it
-- Never yields the caller.
function UIAssets.ResolveButtonArt(id, callback)
	local number = type(id) == "string" and id:match("%d+") or nil
	if not number then
		task.spawn(callback, nil, false)
		return
	end

	local direct = "rbxassetid://" .. number
	UIAssets.WhenReady(direct, function(ok)
		if ok then
			callback(direct, false)
			return
		end

		local thumb = ("rbxthumb://type=Asset&id=%s&w=420&h=420"):format(number)
		UIAssets.WhenReady(thumb, function(thumbOk)
			if thumbOk then
				warn(("[UIAssets] %s is not an image id (probably a Decal id); drawing it from its thumbnail instead.")
					:format(number))
				callback(thumb, true)
			else
				warn(("[UIAssets] %s did not load as an image or as a decal. Check the id and that the upload was approved.")
					:format(number))
				callback(nil, false)
			end
		end)
	end)
end

-- ===================== ASSET GROUPS =====================
-- One place that says which artwork belongs to which interface, split into
-- what a window genuinely cannot open without ("Critical") and what it is
-- merely nicer with. A window waits for its critical group only, so one
-- decorative sparkle can never hold the Store shut.
UIAssets.Groups = {
	-- Priority 0: the top action buttons stay hidden until all three are
	-- cached, so Lock Base -> Protected can never swap onto a blank image.
	TopActions = {
		UIAssets.TopButtons.Upgrade, UIAssets.TopButtons.LockBase,
		UIAssets.TopButtons.Protected,
	},

	-- Priority 1: on screen from the moment the player joins.
	Hud = {
		UIAssets.NavStore, UIAssets.NavLeaderboards, UIAssets.NavIndex,
		UIAssets.NavRebirth, UIAssets.NavInventory, UIAssets.PlaytimeButton,
		UIAssets.PlaytimeAlert, UIAssets.Stardust, UIAssets.Gems,
		UIAssets.CurrencyHUD.GoldStar, UIAssets.CurrencyHUD.BlueStar, UIAssets.CurrencyHUD.PurpleStar,
		UIAssets.HudArt.StardustBackground, UIAssets.HudArt.GemsBackground,
		UIAssets.HudArt.ComboBackground, UIAssets.HudArt.ComboTitle, UIAssets.HudArt.StardustWord,
		UIAssets.HudArt.ComboRanks[1].Image, UIAssets.HudArt.ComboRanks[2].Image, UIAssets.HudArt.ComboRanks[3].Image,
		UIAssets.HudArt.ComboRanks[4].Image, UIAssets.HudArt.ComboRanks[5].Image,
	},

	-- Priority 2: the Store is the window that most obviously breaks when its
	-- artwork is late, so it warms straight after the HUD.
	SecretStore = {
		UIAssets.StoreBackground, UIAssets.SecretStore, UIAssets.Shop,
		UIAssets.Gift, UIAssets.Close, UIAssets.Buy,
		UIAssets.AutoMerge, UIAssets.DoubleSpawn, UIAssets.DoubleHealth,
		UIAssets.LaunchCooldown, UIAssets.ProtectionCooldown,
		UIAssets.CodeIcon, UIAssets.Stardust,
	},

	-- Priority 3
	Leaderboards = {
		UIAssets.TabDaily, UIAssets.TabWeekly, UIAssets.Crown,
		UIAssets.Stardust, UIAssets.Swords, UIAssets.Stopwatch, UIAssets.Globe,
		UIAssets.Podium1, UIAssets.Podium2, UIAssets.Podium3,
		UIAssets.HaloBlue, UIAssets.HaloPink, UIAssets.HaloGold,
		UIAssets.Planet,
	},

	-- Priority 4
	WelcomeBack = {
		UIAssets.WelcomeBackStardust, UIAssets.OfflineClock, UIAssets.Stardust,
	},

	PlaytimeAwards = {
		UIAssets.RewardArt.jackpot, UIAssets.RewardArt.stardust,
		UIAssets.RewardArt.xp, UIAssets.RewardArt.gems,
		UIAssets.RewardArt.damage, UIAssets.RewardArt.spawn,
		UIAssets.RewardArt.shield, UIAssets.RewardArt.luck,
		UIAssets.RewardArt.speed, UIAssets.RewardArt.cooldown,
		UIAssets.PlaytimeButtons.Claim, UIAssets.PlaytimeButtons.Claimed,
		UIAssets.PlaytimeButtons.ClaimAll, UIAssets.PlaytimeButtons.AllClaimed,
		UIAssets.PlaytimeCalendar, UIAssets.Stopwatch, UIAssets.Planet,
	},

	-- Priority 5: never worth blocking anything on.
	Decoration = {
		UIAssets.Planet, UIAssets.Galaxy, UIAssets.YellowGalaxy,
		UIAssets.BlueEnergyRing, UIAssets.PinkCometRing, UIAssets.Cloud,
		UIAssets.Lightning, UIAssets.BlueSpeed, UIAssets.CyanStar,
		UIAssets.StarVariant1, UIAssets.StarVariant2,
		UIAssets.NewTag, UIAssets.Sale, UIAssets.Info, UIAssets.SmallStoreCart,
	},

	-- The Upgrade window, warmed right after the HUD.
	Upgrade = {
		UIAssets.UpgradeArt.Icons.SpawnTier, UIAssets.UpgradeArt.Icons.MaxSpawn,
		UIAssets.UpgradeArt.Icons.LockBase, UIAssets.UpgradeArt.Icons.CoinDropRate,
		UIAssets.UpgradeArt.Icons.CurrencyMagnet, UIAssets.UpgradeArt.HeaderArrow,
		UIAssets.UpgradeArt.Title, UIAssets.UpgradeArt.Maxed,
		UIAssets.UpgradeArt.Close, UIAssets.UpgradeArt.Background,
		UIAssets.UpgradeArt.Labels.SpawnTier, UIAssets.UpgradeArt.Labels.MaxSpawn,
		UIAssets.UpgradeArt.Labels.LockBase, UIAssets.UpgradeArt.Labels.CoinDropRate,
		UIAssets.UpgradeArt.Labels.CurrencyMagnet,
		UIAssets.UpgradeArt.Planet, UIAssets.UpgradeArt.Cloud, UIAssets.UpgradeArt.GoldStar,
		UIAssets.UpgradeArt.Galaxy, UIAssets.UpgradeArt.Shield,
		UIAssets.UpgradeArt.FortuneStar, UIAssets.UpgradeArt.Coin,
	},

	-- The Rebirth window.
	Rebirth = {
		UIAssets.RebirthArt.HeaderVortex, UIAssets.RebirthArt.Planet,
		UIAssets.RebirthArt.CounterRing, UIAssets.RebirthArt.ButtonIcon,
		UIAssets.RebirthArt.Cloud, UIAssets.RebirthArt.GoldStar,
		UIAssets.RebirthArt.RewardIcons.Income, UIAssets.RebirthArt.RewardIcons.SpawnSpeed,
		UIAssets.RebirthArt.RewardIcons.UpgradeCaps, UIAssets.RebirthArt.RewardIcons.StartingTier,
		UIAssets.RebirthArt.RequirementIcons.Tier, UIAssets.RebirthArt.RequirementIcons.Stardust,
		UIAssets.RebirthArt.RequirementIcons.BlackHoles, UIAssets.RebirthArt.RequirementIcons.UpgradesAtCap,
	},

	-- The tutorial dialog and every Nibbles picture.
	Tutorial = {
		UIAssets.TutorialArt.GalaxyBackground, UIAssets.TutorialArt.LetsGoButton,
		UIAssets.TutorialArt.NibblesBadge, UIAssets.TutorialArt.SkipTutorial, UIAssets.TutorialArt.SkipStep,
		UIAssets.TutorialArt.Success[1], UIAssets.TutorialArt.Success[2],
		UIAssets.TutorialArt.Success[3], UIAssets.TutorialArt.Success[4],
		UIAssets.TutorialArt.YouMadeIt,
		UIAssets.TutorialArt.Objectives.WatchStardust, UIAssets.TutorialArt.Objectives.WalkIntoBlackHole,
		UIAssets.TutorialArt.Objectives.PickUpBlackHole, UIAssets.TutorialArt.Objectives.MergeBlackHoles,
		UIAssets.TutorialArt.Objectives.AttackTarget, UIAssets.TutorialArt.Objectives.CanAffordUpgrade,
		UIAssets.TutorialArt.Objectives.LockBase,
		UIAssets.Nibbles.Blushing, UIAssets.Nibbles.Upset, UIAssets.Nibbles.Shocked,
		UIAssets.Nibbles.Playful, UIAssets.Nibbles.Angry, UIAssets.Nibbles.EyesClosed,
		UIAssets.Nibbles.Amazed, UIAssets.Nibbles.Mouth1, UIAssets.Nibbles.Mouth2, UIAssets.Nibbles.Mouth3,
	},

	-- Kept so the older Preload("Primary") calls still mean something.
	Primary = UIAssets.Primary,
	Nav = UIAssets.Nav,
	Secondary = UIAssets.Secondary,
}

-- ===================== PRELOADER =====================
-- Why this exists: a window that becomes visible before its images have
-- arrived shows plain frames first and the artwork pops in afterwards. The
-- fix is not a longer wait, it is knowing when the artwork is actually ready.
--
--   UIAssets.WarmStartup()                  -- call once, early, on the client
--   UIAssets.EnsureGroup(name, onReady)     -- never yields; onReady(failures)
--   UIAssets.GroupStatus(name)              -- "idle" | "loading" | "ready"

-- A dead id must never hold a window shut. This is a safety net, not the
-- loading strategy: in the normal case the callback resolves long before it.
local WATCHDOG_SECONDS = 12

local groupState = {}      -- [name] = "loading" | "ready"
local groupFailures = {}   -- [name] = { id, ... }
local groupWaiting = {}    -- [name] = { callback, ... }
local reportedFailure = {} -- [id] = true, so each bad id is logged once

UIAssets.Debug = false

local function finishGroup(name)
	groupState[name] = "ready"
	local waiting = groupWaiting[name]
	groupWaiting[name] = nil

	if waiting then
		for _, callback in ipairs(waiting) do
			task.spawn(callback, groupFailures[name] or {})
		end
	end
end

function UIAssets.GroupStatus(name)
	return groupState[name] or "idle"
end

-- Asks for a group and calls back when it is ready. Safe to call from a
-- button: it never yields, and calling it five times in a row starts one
-- preload, not five.
function UIAssets.EnsureGroup(name, onReady)
	local list = UIAssets.Groups[name]

	if type(list) ~= "table" then
		warn("[UIAssets] Unknown asset group:", name)
		if onReady then task.spawn(onReady, {}) end
		return
	end

	if groupState[name] == "ready" then
		if onReady then task.spawn(onReady, groupFailures[name] or {}) end
		return
	end

	if onReady then
		groupWaiting[name] = groupWaiting[name] or {}
		table.insert(groupWaiting[name], onReady)
	end

	-- Already in flight: the caller joins the request that is running rather
	-- than starting a second one.
	if groupState[name] == "loading" then
		return
	end
	groupState[name] = "loading"

	task.spawn(function()
		local ids, seen = {}, {}
		for _, id in ipairs(list) do
			if type(id) == "string" and id ~= "" and not seen[id] then
				seen[id] = true
				table.insert(ids, id)
			end
		end

		if #ids == 0 then
			finishGroup(name)
			return
		end

		local started = os.clock()
		local failures = {}
		local settled = false

		if UIAssets.Debug then
			print(("[UIAssets] %s: preloading %d assets"):format(name, #ids))
		end

		task.delay(WATCHDOG_SECONDS, function()
			if settled then return end
			settled = true
			warn(("[UIAssets] %s: preload still running after %ds; continuing without it.")
				:format(name, WATCHDOG_SECONDS))
			groupFailures[name] = failures
			finishGroup(name)
		end)

		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(ids, function(id, status)
				if status == Enum.AssetFetchStatus.Success then
					if UIAssets.Debug then
						print(("[UIAssets] %s: %s ok"):format(name, tostring(id)))
					end
					return
				end

				table.insert(failures, id)
				if not reportedFailure[id] then
					reportedFailure[id] = true
					warn(("[UIAssets] %s: %s did not load (%s). A drawn fallback is used where one exists.")
						:format(name, tostring(id), tostring(status)))
				end
			end)
		end)

		if not ok then
			warn("[UIAssets] preload error in group " .. name .. ":", err)
		end

		if settled then return end
		settled = true
		groupFailures[name] = failures

		if UIAssets.Debug or #failures > 0 then
			print(("[UIAssets] %s: %d/%d loaded in %.1fs"):format(
				name, #ids - #failures, #ids, os.clock() - started))
		end

		finishGroup(name)
	end)
end

-- Warms the groups in priority order, one after another, so joining does not
-- fire one enormous request. Each group still has its own watchdog, so a slow
-- group delays the ones behind it but cannot stop them.
local WARM_ORDER = { "TopActions", "Hud", "Upgrade", "Rebirth", "SecretStore", "Leaderboards", "PlaytimeAwards", "WelcomeBack", "Decoration" }
local warmed = false

function UIAssets.WarmStartup()
	if warmed then return end
	warmed = true

	local index = 0
	local function step()
		index += 1
		local name = WARM_ORDER[index]
		if not name then
			if UIAssets.Debug then
				print("[UIAssets] startup warm complete")
			end
			return
		end
		UIAssets.EnsureGroup(name, step)
	end

	step()
end

-- Kept for the scripts that already call it. It goes through the same state
-- machine, so an id is never requested twice in a session.
--
-- The older names -- "Primary", "Nav" -- are flat lists on the module rather
-- than entries in Groups, and EnsureGroup only reads Groups. They used to fall
-- through to a group called "Primary" that does not exist, so the call warned
-- and preloaded nothing. A flat list is registered as a group on first use
-- instead, which makes every existing caller work.
function UIAssets.Preload(which)
	if type(which) ~= "string" then
		which = "Hud"
	end

	if UIAssets.Groups[which] == nil then
		local list = UIAssets[which]
		if type(list) == "table" and #list > 0 then
			UIAssets.Groups[which] = list
		else
			warn("[UIAssets] Preload: no group or list named", which, "- using Hud.")
			which = "Hud"
		end
	end

	UIAssets.EnsureGroup(which)
end

return UIAssets
