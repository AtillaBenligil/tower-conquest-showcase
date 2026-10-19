--!nonstrict
-- SevenVerities (client effects)
-- Location: ReplicatedStorage.WeaponKits.Fx.SevenVerities (ModuleScript)
-- Effects of the Blade of Seven Verities (server kit: ServerScriptService.WeaponKits.Kits.SevenVerities),
-- run by StarterPlayerScripts.WeaponFxClient on every client of the run.
-- Each handler gets (data, env); env = { caster, character, root, mine }.
--   Swing         blade trail + a crescent slash wave out to the swing's reach, sparks on hits
--   StatDrop      passive: the stat's icon flies from the enemy into the player, "+1% <stat>"
--   Coin          Lucky Coin: digital gold coin(s) flip above the head; after 1 s each lands,
--                 shows its boost and dives into the player; gold glitter while boosted
--   Laser         Mastered Magic: the sword is raised, three red magic gates open where the
--                 player faces and a red laser (dark core, glowing red edges, crawling
--                 lightning) comes out of them for 5 s, following the player's facing and
--                 stopping at walls
--   Nightmare     Nightmare Form: time stops (grey-violet grade) and the caster gets a
--                 cinematic -- the sword turns black, then the player -- title card, shockwave
--                 (the black/purple looks themselves are made by the server, so they replicate)
--   Moonlight     dash in Nightmare Form: afterimage where you were, golden Moonlight Slash
--   NightmareEnd  the form fades
-- Animations: ReplicatedStorage.WeaponKits.Anims.SevenVerities.<Hold | Swing1 | Swing2 | CoinToss |
-- MagicRaise | Nightmare | Moonlight> (sources: WeaponKits.AnimSources.SevenVerities). Until one is
-- published the sword is posed in code. Sounds: SFX below (Roblox's licensed library).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponKits = ReplicatedStorage:WaitForChild("WeaponKits")
local Fx = require(WeaponKits:WaitForChild("FxUtil"))
local Tex = require(WeaponKits:WaitForChild("TextureIds"))

local M = {}
M.id = "seven_verities"
M.Always = { StatDrop = true } -- tells you what you just got: shown even with Ability Effects off
M.AnimKit = "SevenVerities" -- WeaponFxClient runs Presence / Equip for weapon models with this AnimKit

local KIT = "SevenVerities"
local player = Players.LocalPlayer

local WHITE = Color3.new(1, 1, 1)
local PALE = Color3.fromRGB(255, 240, 205)
local GOLD = Color3.fromRGB(255, 200, 80)
local RED = Color3.fromRGB(255, 35, 45)
local PURPLE = Color3.fromRGB(170, 70, 255)
local MAGENTA = Color3.fromRGB(255, 45, 220)

-- Sounds: Roblox's licensed library (Pro Sound Effects / APM Music, free to use in experiences)
local SFX = {
	Swish = { 9126014082, 9126013811, 9126013382, 9119699577, 9119698772, 9119699897, 9119700022 },
	WhooshBy = 9120715547, -- whoosh, fast swish by
	Electric = 9116278351, -- lightning flash, quick electrical burst
	CoinFlick = 9113849910, -- single coin throw
	CoinLand = 9113849827,
	Chime = 9114369623, -- fairy dust, light ringing chimes
	DeepHit = 9125484367, -- deep hit, big reverberant boom
	EvilPulse = 9126084278, -- synth tone, constant big pulsing, low, evil (looped)
	Dramatic = 9039693350, -- APM "Dramatic Whoosh": a swell to a sudden cinematic stop
	Suck = 9039693523, -- APM "Tutti Suck": a swell to a quick suck-out
}
local function sid(n: number): string
	return "rbxassetid://" .. tostring(n)
end
local function vol(env, v: number): number
	return if env.mine then v else v * 0.6 -- other players' skills a little quieter
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function easeOutBack(a: number): number
	local c = 1.70158
	return 1 + (c + 1) * (a - 1) ^ 3 + c * (a - 1) ^ 2
end

-- ===================================================================== basic swing
local function bladeTrail(character)
	local weapon = Fx.Weapon(character)
	local blade = weapon and weapon:FindFirstChild("SOST_Blade")
	if not blade then return nil end
	local trail = blade:FindFirstChild("SV_Trail")
	if trail then return trail end
	local half = blade.Size.Z / 2 -- the blade runs along its Z, tip at -Z
	local a0 = Instance.new("Attachment")
	a0.Name = "SV_TrailBase"
	a0.Position = Vector3.new(0, 0, half * 0.7)
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Name = "SV_TrailTip"
	a1.Position = Vector3.new(0, 0, -half)
	a1.Parent = blade
	trail = Instance.new("Trail")
	trail.Name = "SV_Trail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.16
	trail.MinLength = 0.02
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Brightness = 2
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(0.4, PALE), ColorSequenceKeypoint.new(1, RED),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.5) })
	trail.Enabled = false
	trail.Parent = blade
	return trail
end

-- Combo: the server counts the steps (data.n = 1..4, 4 = finisher) and resets the chain after a
-- pause. Each step has its own animation and its own crescent (FxUtil.Slash); the finisher is a
-- full 360 spin that hits all around.
--   yaw = head of the crescent relative to forward (+ = left); roll/tilt = plane of the cut
local COMBO = {
	{ anim = "Swing1", mirror = false, roll = 8, tilt = 26, yaw = 0, from = -115, to = 78, lift = 1.0 }, -- right to left
	{ anim = "Swing2", mirror = true, roll = -10, tilt = 30, yaw = 0, from = 115, to = -78, lift = 0.6 }, -- backhand
	{ anim = "Swing3", mirror = true, roll = 0, tilt = 78, yaw = 0, from = 150, to = -60, lift = 1.2 }, -- overhead: stood up, facing the camera
	{ anim = "Spin", mirror = false, roll = 0, tilt = 10, yaw = 0, from = -200, to = 205, lift = 0.9, spin = true }, -- finisher
}

local function impacts(env, dir, range, angle, scale)
	local root = env.root
	if not root or not root.Parent then return end
	local from = root.Position
	local cosHalf = math.cos(math.rad(angle / 2))
	for _, e in Fx.Enemies(from, range) do
		local rel = Vector3.new(e.root.Position.X - from.X, 0, e.root.Position.Z - from.Z)
		local radius = math.max(e.root.Size.X, e.root.Size.Z) / 2
		if angle >= 360 or rel.Magnitude < 3 + radius or Fx.Flat(rel):Dot(dir) >= cosHalf then
			local out = Fx.Flat(rel)
			Fx.Impact(e.root.Position + Vector3.new(0, 0.8, 0) - out * radius * 0.5, {
				star = Tex.ImpactStar, burst = Tex.HitBurst, color = GOLD, scale = scale, sparks = 7,
			})
		end
	end
end

function M.Swing(data, env)
	local character, root = env.character, env.root
	if not character or not root then return end
	local dir = Fx.Flat(if typeof(data.dir) == "Vector3" then data.dir else root.CFrame.LookVector)
	local range = tonumber(data.range) or 13
	local angle = tonumber(data.angle) or 120
	local step = math.clamp(math.floor(tonumber(data.n) or 1), 1, #COMBO)
	local c = COMBO[step]
	local finisher = c.spin == true
	local swing = math.clamp((tonumber(data.interval) or 0.8) * 0.3, 0.12, 0.2) * (if finisher then 1.8 else 1)
	local nightmare = data.form == true
	local edgeColor = if nightmare then MAGENTA else Color3.fromRGB(255, 165, 30)

	Fx.Sound(sid(SFX.Swish[math.random(1, #SFX.Swish)]), root, { volume = vol(env, 0.34), pitch = 0.9 + math.random() * 0.2 })
	if finisher then
		Fx.Sound(sid(SFX.WhooshBy), root, { volume = vol(env, 0.4), pitch = 1.1 })
	end

	if env.mine then Fx.PlayAnim(KIT, c.anim, { speed = math.clamp(0.2 / swing, 0.8, 1.8) }) end
	if not Fx.Animation(KIT, c.anim) then
		-- stand-in until the animation is published: the wrist whips the blade through the cut
		local side = if c.mirror then -1 else 1
		Fx.Pose(character, swing + 0.05, 1, function(t)
			local k = Fx.EaseOut(clamp01(t / swing))
			if finisher then
				return CFrame.Angles(math.rad(10), math.rad(-70 + 400 * k), math.rad(-20))
			end
			return CFrame.Angles(math.rad(15 + c.roll * 0.4), math.rad(side * (-70 + 135 * k)), math.rad(side * -20))
		end, 0.14)
	end

	local trail = bladeTrail(character)
	if trail then
		local untilT = os.clock() + swing + 0.06
		trail:SetAttribute("Until", untilT)
		trail.Enabled = true
		task.delay(swing + 0.06, function()
			if trail.Parent and os.clock() >= (trail:GetAttribute("Until") or 0) - 0.01 then trail.Enabled = false end
		end)
	end

	-- the crescent(s)
	local origin = root.Position + Vector3.new(0, c.lift - 0.4, 0)
	-- about the size of the character's reach (the hit reaches the full range anyway)
	local radius = math.clamp(range * (if finisher then 0.62 else 0.5), 5, if finisher then 9.5 else 8)
	local opts = {
		ring = if c.mirror then Tex.SlashRingM else Tex.SlashRing,
		edge = if c.mirror then Tex.SlashEdgeM else Tex.SlashEdge,
		radius = radius, roll = c.roll, tilt = c.tilt, yaw = c.yaw, from = c.from, to = c.to,
		seconds = swing, fade = if finisher then 0.3 else 0.2,
		color = if nightmare then Color3.fromRGB(235, 215, 255) else Color3.fromRGB(255, 236, 190), edgeColor = edgeColor, brightness = 3,
	}
	Fx.Slash(origin, dir, opts)
	if finisher then
		-- a second, wider ring a beat later, a ground shockwave and a gold flash
		task.delay(0.05, function()
			if not root.Parent then return end
			local o2 = table.clone(opts)
			o2.radius = radius * 1.18
			o2.tilt = -6
			o2.color = Color3.new(1, 1, 1)
			Fx.Slash(root.Position + Vector3.new(0, 1.4, 0), dir, o2)
		end)
		task.delay(swing * 0.6, function()
			if not root.Parent then return end
			local feet = Vector3.new(root.Position.X, Fx.FeetY(character, root) + 0.15, root.Position.Z)
			Fx.Ring(CFrame.new(feet), 2, radius * 1.3, GOLD, 0.35, 10)
			Fx.Light(feet + Vector3.new(0, 2, 0), GOLD, radius * 1.5, 3, 0.35)
			Fx.Burst(feet, {
				texture = Fx.SMOKE, color = PALE, count = 14, speed = NumberRange.new(10, 18), life = NumberRange.new(0.3, 0.5),
				size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 2.6) }),
				transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
				spread = 90, drag = 6, emission = 0.3, dir = Vector3.yAxis,
			})
			if env.mine then pcall(Fx.Shake, 0.35, 0.18) end
			Fx.Sound(sid(SFX.DeepHit), root, { volume = vol(env, 0.22), pitch = 1.3 })
		end)
	end

	-- impact flashes on what the blade catches
	task.delay(swing * 0.45, function()
		impacts(env, dir, range, if finisher then 360 else angle, if finisher then 1.35 else 1)
	end)
end

-- ===================================================================== passive: stat drop
local STATS = {
	speed = { name = "Move Speed", color = Color3.fromRGB(110, 255, 170) },
	attackSpeed = { name = "Attack Speed", color = Color3.fromRGB(255, 215, 80) },
	range = { name = "Range", color = Color3.fromRGB(110, 200, 255) },
	damage = { name = "Damage", color = Color3.fromRGB(255, 95, 85) },
	critChance = { name = "Crit Chance", color = Color3.fromRGB(255, 140, 235) },
}

function M.StatDrop(data, env)
	local character, root = env.character, env.root
	if not root then return end
	local info = STATS[data.stat] or { name = tostring(data.stat), color = GOLD }
	local per = tonumber(data.per) or 1
	local stacks = tonumber(data.stacks) or 1
	local from = (if typeof(data.from) == "Vector3" then data.from else root.Position) + Vector3.new(0, 1.5, 0)

	local p = Fx.Part({ CFrame = CFrame.new(from) })
	local gui, img = Fx.Billboard(p, 1.7, Tex.StatIcons[data.stat] or "", { color = WHITE, brightness = 2 })
	img.Size = UDim2.fromScale(0.62, 0.62)
	img.ZIndex = 2
	local disc = Instance.new("Frame")
	disc.BackgroundColor3 = info.color
	disc.BackgroundTransparency = 0.2
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(0.95, 0.95)
	disc.ZIndex = 1
	disc.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = disc
	local ring = Instance.new("UIStroke")
	ring.Color = WHITE
	ring.Thickness = 2
	ring.Parent = disc
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.3, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.3, 0)
	a1.Parent = p
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	trail.Lifetime = 0.22
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(info.color)
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = p

	local flight = 0.55
	local sideways = if math.random() < 0.5 then -1 else 1
	Fx.Every(flight, function(_, a)
		if not root.Parent then return false end
		local target = root.Position + Vector3.new(0, 0.6, 0)
		local mid = (from + target) / 2 + Vector3.new(0, 4 + (from - target).Magnitude * 0.12, 0) + root.CFrame.RightVector * sideways * 1.5
		local k = a * a -- speeds up into the player
		p.CFrame = CFrame.new(from:Lerp(mid, k):Lerp(mid:Lerp(target, k), k))
		local s = 1.7 - 0.6 * a
		gui.Size = UDim2.fromScale(s, s)
		return nil
	end)
	task.delay(flight, function()
		p:Destroy()
		if not root.Parent then return end
		local chest = root.Position + Vector3.new(0, 0.6, 0)
		Fx.Sound(sid(SFX.Chime), root, { volume = vol(env, 0.4), pitch = 1.6, duration = 0.9, fadeOut = 0.4 })
		Fx.Burst(chest, { color = info.color, count = 16, speed = NumberRange.new(5, 11), life = NumberRange.new(0.25, 0.45), size = 0.4, drag = 3 })
		Fx.Ring(CFrame.new(root.Position.X, Fx.FeetY(character, root) + 0.15, root.Position.Z), 0.6, 3.4, info.color, 0.4)
		Fx.Label(root, string.format("+%d%% %s", per, info.name), info.color, {
			sub = string.format("+%d%% this run", per * stacks), offset = Vector3.new(0, 3.4, 0),
		})
	end)
end

-- ===================================================================== skill 1: Lucky Coin
local BOOSTS = {
	damage = { fmt = "+%d%% Damage", color = Color3.fromRGB(255, 95, 85) },
	range = { fmt = "+%d%% Range", color = Color3.fromRGB(110, 200, 255) },
	speed = { fmt = "+%d%% Move Speed", color = Color3.fromRGB(110, 255, 170) },
	regen = { fmt = "+%d%% HP/s Regen", color = Color3.fromRGB(120, 255, 120) },
	attackSpeed = { fmt = "+%d%% Attack Speed", color = Color3.fromRGB(255, 215, 80) },
	critDamage = { fmt = "+%d%% Crit Damage", color = Color3.fromRGB(255, 140, 235) },
}
local COIN_SIZE = Vector3.new(0.14, 1.5, 1.5)

local function makeCoin()
	local coin = Fx.Part({
		Shape = Enum.PartType.Cylinder, Size = COIN_SIZE, Transparency = 0,
		Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 186, 50),
	})
	local faces = {
		Fx.Sprite(coin, Enum.NormalId.Right, Tex.CoinFace, { brightness = 1.3 }),
		Fx.Sprite(coin, Enum.NormalId.Left, Tex.CoinFace, { brightness = 1.3 }),
	}
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 7
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = coin
	return coin, faces
end

function M.Coin(data, env)
	local character, root = env.character, env.root
	if not character or not root then return end
	local rolls = if type(data.rolls) == "table" then data.rolls else {}
	local n = math.max(1, #rolls)
	local toss = tonumber(data.toss) or 1
	local amounts = if type(data.amounts) == "table" then data.amounts else {}
	if env.mine then Fx.PlayAnim(KIT, "CoinToss") end

	local head = character:FindFirstChild("Head")
	local hand = character:FindFirstChild("LeftHand") or root
	local coins = {}
	for i = 1, n do
		local coin, faces = makeCoin()
		coins[i] = { part = coin, faces = faces }
	end
	Fx.Burst(hand.Position, { color = GOLD, count = 8, speed = NumberRange.new(3, 6), life = NumberRange.new(0.2, 0.35), size = 0.3 })
	Fx.Sound(sid(SFX.CoinFlick), hand, { volume = vol(env, 0.5), pitch = 1.3 })

	local PEAK, REST, SPINS = 5.2, 2.0, 3
	local nextBits = 0
	Fx.Every(toss, function(t)
		if not root.Parent then return false end
		local cam = workspace.CurrentCamera
		local top = if head then head.Position + Vector3.new(0, head.Size.Y / 2, 0) else root.Position + Vector3.new(0, 2.5, 0)
		local right = Fx.Flat(cam.CFrame.RightVector)
		local bits = os.clock() >= nextBits
		if bits then nextBits = os.clock() + 0.12 end
		for i, c in coins do
			local lag = (i - 1) * 0.06
			local ta = clamp01((t - lag) / math.max(0.2, toss - lag))
			local h = if ta < 0.45 then PEAK * (1 - (1 - ta / 0.45) ^ 2) else PEAK - (PEAK - REST) * ((ta - 0.45) / 0.55) ^ 2
			local spread
			if n <= 5 then
				spread = right * ((i - (n + 1) / 2) * 1.8)
			else
				local ang = i / n * math.pi * 2
				spread = Vector3.new(math.cos(ang), 0, math.sin(ang)) * (1 + n * 0.28)
			end
			local pos = top + spread * Fx.EaseOut(ta) + Vector3.new(0, h, 0)
			local flip = SPINS * 2 * math.pi * Fx.EaseOut(ta) -- lands face-on to the camera
			c.part.CFrame = CFrame.lookAt(pos, cam.CFrame.Position) * CFrame.Angles(flip, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
			-- digital: a flicker now and then, little bits trailing off
			local flicker = if math.random() < 0.07 then 0.55 else 0
			for _, f in c.faces do f.ImageTransparency = flicker end
			c.part.Transparency = flicker
			if bits then Fx.Pixels(pos, GOLD, 1, 1.2, 0.4) end
		end
		return nil
	end)

	task.delay(toss, function()
		if not root.Parent then
			for _, c in coins do c.part:Destroy() end
			return
		end
		Fx.Sound(sid(SFX.Chime), root, { volume = vol(env, 0.5), pitch = 1.2, duration = 1.6, fadeOut = 0.6 })
		Fx.Sound(sid(SFX.CoinLand), root, { volume = vol(env, 0.35), pitch = 1.5 })
		local order, count = {}, {}
		for _, k in rolls do
			if not count[k] then
				count[k] = 0
				table.insert(order, k)
			end
			count[k] += 1
		end
		for i, c in coins do
			local info = BOOSTS[rolls[i]] or { color = GOLD }
			local coin = c.part
			local pos = coin.Position
			Fx.Burst(pos, { color = ColorSequence.new(WHITE, info.color), count = 18, speed = NumberRange.new(4, 10), life = NumberRange.new(0.3, 0.55), size = 0.35, drag = 3 })
			Fx.Pixels(pos, info.color, 8, 2.2, 0.5)
			Fx.Light(pos, info.color, 10, 3, 0.4)
			coin.Transparency = 0
			for _, f in c.faces do f.ImageTransparency = 0 end
			coin.Color = info.color
			local spin = coin.CFrame - coin.Position
			Fx.Every(0.3, function(_, a)
				if not root.Parent then return false end
				local target = root.Position + Vector3.new(0, 0.8, 0)
				coin.CFrame = CFrame.new(pos:Lerp(target, a * a)) * spin
				coin.Size = COIN_SIZE * (1 - 0.75 * a)
				return nil
			end)
			Debris:AddItem(coin, 0.32)
		end
		for j, k in order do
			local info = BOOSTS[k]
			local text = if info and amounts[k] then string.format(info.fmt, amounts[k] * count[k]) else ("+" .. tostring(k))
			Fx.Label(root, text, if info then info.color else GOLD, {
				offset = Vector3.new(0, 3.3 + (j - 1) * 1.15, 0), seconds = 1.8, delay = 0.05 * j,
			})
		end
		-- boosted: gold glitter around the player while it lasts
		local glitter = Instance.new("ParticleEmitter")
		glitter.Name = "SV_LuckyGlitter"
		glitter.Texture = Fx.SPARK
		glitter.Color = ColorSequence.new(GOLD, PALE)
		glitter.Rate = 14
		glitter.Lifetime = NumberRange.new(0.6, 1)
		glitter.Speed = NumberRange.new(1, 2.5)
		glitter.SpreadAngle = Vector2.new(25, 25)
		glitter.Acceleration = Vector3.new(0, 2, 0)
		glitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) })
		glitter.LightEmission = 1
		glitter.LightInfluence = 0
		glitter.Parent = root
		Debris:AddItem(glitter, tonumber(data.duration) or 5)
	end)
end

-- ===================================================================== skill 2: Mastered Magic
-- three gates along the facing, each bigger than the last: the laser grows through them
local GATES = {
	{ d = 3.0, size = 4.4, spin = 70 },
	{ d = 5.4, size = 6.6, spin = -55 },
	{ d = 8.0, size = 9.2, spin = 40 },
}

function M.Laser(data, env)
	local character, root = env.character, env.root
	if not character or not root then return end
	local duration = tonumber(data.duration) or 5
	local open = tonumber(data.open) or 0.35
	local width = tonumber(data.width) or 7
	local maxLen = tonumber(data.length) or 400
	local total = open + duration
	local CLOSE = 0.35

	if env.mine then Fx.PlayAnim(KIT, "MagicRaise", { fade = 0.12 }) end
	if not Fx.Animation(KIT, "MagicRaise") then
		Fx.Pose(character, total, 5, function(t)
			local k = Fx.EaseOut(clamp01(t / 0.2))
			return CFrame.Angles(math.rad(100) * k, 0, 0) -- blade up
		end, 0.25)
	end

	local stuff = {}
	local function keep(i)
		table.insert(stuff, i)
		return i
	end

	local gates = {}
	for i, g in GATES do
		local part = keep(Fx.Part({ Size = Vector3.new(0.1, 0.1, 0.05) }))
		local imgs = {
			Fx.Sprite(part, Enum.NormalId.Back, Tex.Gate, { brightness = 2.2, canvas = Vector2.new(512, 512), transparency = 1 }),
			Fx.Sprite(part, Enum.NormalId.Front, Tex.Gate, { brightness = 2.2, canvas = Vector2.new(512, 512), transparency = 1 }),
		}
		local light = Instance.new("PointLight")
		light.Color = RED
		light.Range = g.size * 1.6
		light.Brightness = 0
		light.Shadows = false
		light.Parent = part
		gates[i] = { part = part, imgs = imgs, light = light, def = g, rot = math.random(0, 359) }
	end

	-- the beam: two segments (first gate -> last gate widening, then full width to the wall)
	local rig = keep(Fx.Part({ CFrame = CFrame.identity }))
	local function att()
		local a = Instance.new("Attachment")
		a.Parent = rig
		return a
	end
	local aStart, aMid, aEnd = att(), att(), att()
	local function beam(a0, a1, props)
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.FaceCamera = true
		b.LightInfluence = 0
		b.Segments = 1
		b.Width0 = 0
		b.Width1 = 0
		for k, v in props do b[k] = v end
		b.Parent = rig
		return b
	end
	local core, glow = {}, {}
	for _, seg in { { aStart, aMid }, { aMid, aEnd } } do
		-- dark core with red rims (alpha blended, so the middle stays dark)
		table.insert(core, beam(seg[1], seg[2], {
			Texture = Tex.LaserCore, TextureMode = Enum.TextureMode.Wrap, TextureLength = 14, TextureSpeed = 3,
			LightEmission = 0, Color = ColorSequence.new(Color3.fromRGB(255, 70, 70)), ZOffset = 0,
		}))
		-- the glowing edges on top (additive, see-through middle: the core stays dark)
		table.insert(glow, beam(seg[1], seg[2], {
			Texture = Tex.LaserGlow, TextureMode = Enum.TextureMode.Wrap, TextureLength = 14, TextureSpeed = 3,
			LightEmission = 1, Brightness = 2.5, Color = ColorSequence.new(Color3.fromRGB(255, 60, 60)),
			Transparency = NumberSequence.new(0.15), ZOffset = 0.1,
		}))
	end
	local bolts = {}
	for i = 1, 3 do
		local a0, a1 = att(), att()
		local b = beam(a0, a1, {
			Texture = Tex.LaserBolt, TextureMode = Enum.TextureMode.Wrap, TextureLength = 16 + i * 4,
			TextureSpeed = (if i % 2 == 0 then -1 else 1) * (2 + i), LightEmission = 1, Brightness = 2.5,
			Color = ColorSequence.new(Color3.fromRGB(255, 120, 120)), Width0 = 2.6, Width1 = 2.6, Segments = 24, ZOffset = 0.2,
		})
		bolts[i] = { beam = b, a0 = a0, a1 = a1, off0 = 0, off1 = 0, nextAt = 0 }
	end

	-- sparks along the beam, a burning point where it hits the wall, a flare at the gate
	local sparkPart = keep(Fx.Part({ Size = Vector3.new(1, 1, 1) }))
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = Fx.SPARK
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 110, 80), RED)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.25, 0.5)
	sparks.Speed = NumberRange.new(2, 7)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 2
	sparks.Shape = Enum.ParticleEmitterShape.Box
	sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	sparks.Rate = 0
	sparks.Parent = sparkPart

	local impact = keep(Fx.Part({ Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 70, 55), Transparency = 1 }))
	local impactLight = Instance.new("PointLight")
	impactLight.Color = RED
	impactLight.Range = 18
	impactLight.Brightness = 0
	impactLight.Shadows = false
	impactLight.Parent = impact
	local splash = Instance.new("ParticleEmitter")
	splash.Texture = Fx.SPARK
	splash.Color = ColorSequence.new(Color3.fromRGB(255, 160, 120), RED)
	splash.LightEmission = 1
	splash.LightInfluence = 0
	splash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	splash.Lifetime = NumberRange.new(0.2, 0.45)
	splash.Speed = NumberRange.new(8, 18)
	splash.SpreadAngle = Vector2.new(70, 70)
	splash.Drag = 3
	splash.Rate = 0
	splash.Parent = impact

	local flare = keep(Fx.Part({ Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 120, 110), Transparency = 1 }))

	if env.mine then
		task.delay(open, function() Fx.Quake(0.12, duration) end)
	end
	Fx.Sound(sid(SFX.Electric), root, { volume = vol(env, 0.5), pitch = 0.8 })
	local stopHum: ((number?) -> ())? = nil
	task.delay(open, function()
		if not root.Parent then return end
		Fx.Sound(sid(SFX.DeepHit), root, { volume = vol(env, 0.5), pitch = 1.15, duration = 2.5, fadeOut = 1 })
		local _, stop = Fx.Sound(sid(SFX.EvilPulse), root, { volume = vol(env, 0.55), looped = true, from = 1, fadeIn = 0.15 })
		stopHum = stop
	end)
	local nextCrackle = os.clock() + open + 0.8

	Fx.Every(total + CLOSE, function(t, _, dt)
		if not root.Parent then return false end
		local look = Fx.Flat(root.CFrame.LookVector)
		local chest = root.Position + Vector3.new(0, 1.1, 0)

		-- gates: pop open one after another, spin, close at the end
		for i, g in gates do
			local k
			if t < total then
				k = easeOutBack(clamp01((t - (i - 1) * 0.07) / open))
			else
				k = 1 - clamp01((t - total) / (CLOSE - 0.05))
			end
			local size = math.max(0.05, g.def.size * k)
			local center = chest + look * g.def.d
			g.part.Size = Vector3.new(size, size, 0.05)
			g.part.CFrame = CFrame.lookAt(center, center + look)
			g.rot = (g.rot + g.def.spin * dt * (if t < total then 1 else 4)) % 360
			for _, img in g.imgs do
				img.Rotation = g.rot
				img.ImageTransparency = 1 - clamp01(k)
			end
			g.light.Brightness = 2.5 * clamp01(k)
		end

		-- beam strength: 0 until the gates are open, a quick swell, a slight shimmer, a fast fade
		local w
		if t < open then
			w = 0
		elseif t < open + 0.12 then
			w = (t - open) / 0.12
		elseif t < total then
			w = 1 + 0.05 * math.sin(t * 45)
		else
			w = math.max(0, 1 - (t - total) / 0.2)
		end
		local origin = chest + look * GATES[1].d
		local len = Fx.WallDistance(origin, look, maxLen)
		local endPos = origin + look * len
		local midPos = if len > GATES[3].d - GATES[1].d then chest + look * GATES[3].d else endPos
		aStart.WorldPosition = origin
		aMid.WorldPosition = midPos
		aEnd.WorldPosition = endPos
		local wStart, wFull = width * 0.42 * w, width * w
		core[1].Width0, core[1].Width1 = wStart * 0.8, wFull * 0.8
		core[2].Width0, core[2].Width1 = wFull * 0.8, wFull * 0.8
		glow[1].Width0, glow[1].Width1 = wStart, wFull
		glow[2].Width0, glow[2].Width1 = wFull, wFull

		local cam = workspace.CurrentCamera
		local perp = look:Cross(cam.CFrame.Position - (origin + endPos) / 2)
		perp = if perp.Magnitude > 1e-3 then perp.Unit else Vector3.yAxis
		local now = os.clock()
		for _, b in bolts do
			if now >= b.nextAt then
				b.nextAt = now + 0.05 + math.random() * 0.06
				b.off0 = (math.random() - 0.5) * width * 0.5
				b.off1 = (math.random() - 0.5) * width * 0.7
				b.beam.Transparency = NumberSequence.new(math.random() * 0.5)
				b.beam.CurveSize0 = (math.random() - 0.5) * 6
				b.beam.CurveSize1 = (math.random() - 0.5) * 6
			end
			b.a0.WorldPosition = origin + perp * b.off0 * w
			b.a1.WorldPosition = endPos + perp * b.off1 * w
			b.beam.Enabled = w > 0.05
		end

		local on = w > 0.05
		if on and now >= nextCrackle then
			nextCrackle = now + 1.1 + math.random() * 0.5
			Fx.Sound(sid(SFX.Electric), root, { volume = vol(env, 0.22), pitch = 1 + math.random() * 0.3 })
		end
		sparkPart.CFrame = CFrame.lookAt((origin + endPos) / 2, endPos)
		sparkPart.Size = Vector3.new(width * 0.45, width * 0.45, math.max(1, len))
		sparks.Rate = if on then math.clamp(len * 0.5, 20, 140) else 0
		local wall = len < maxLen - 0.5
		local hitAt = endPos - look * 0.6
		impact.CFrame = CFrame.lookAt(hitAt, hitAt - look) * CFrame.Angles(-math.pi / 2, 0, 0) -- splash flies back off the wall
		impact.Transparency = if on and wall then 0.35 + 0.15 * math.sin(t * 30) else 1
		impact.Size = Vector3.one * (3.2 + 0.6 * math.sin(t * 23)) * math.min(1, w)
		impactLight.Brightness = if on then 3 * math.min(1, w) else 0
		splash.Rate = if on and wall then 70 else 0
		flare.CFrame = CFrame.new(origin)
		flare.Transparency = if on then 0.25 + 0.1 * math.sin(t * 37) else 1
		flare.Size = Vector3.one * 2.6 * math.min(1, w)
		return nil
	end)
	task.delay(total, function()
		if stopHum then stopHum(0.35) end
	end)
	task.delay(total + CLOSE + 0.05, function()
		if stopHum then stopHum(0.05) end
		for _, i in stuff do i:Destroy() end
	end)
end

-- ===================================================================== ultimate: Nightmare Form
local function letterbox(seconds)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SV_Cinematic"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ResetOnSpawn = false
	local bars = {}
	for _, top in { true, false } do
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0, if top then 0 else 1)
		f.Position = UDim2.fromScale(0, if top then 0 else 1)
		f.Size = UDim2.fromScale(1, 0)
		f.Parent = gui
		table.insert(bars, f)
	end
	gui.Parent = player:WaitForChild("PlayerGui")
	for _, b in bars do Fx.Tween(b, 0.25, { Size = UDim2.fromScale(1, 0.11) }) end
	task.delay(math.max(0, seconds - 0.25), function()
		for _, b in bars do Fx.Tween(b, 0.25, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end
		Debris:AddItem(gui, 0.3)
	end)
	return gui
end

local function titleCard(gui, at, hold)
	task.delay(at, function()
		if not gui.Parent then return end
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, 0.79)
		t.Size = UDim2.fromScale(0.7, 0.08)
		t.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
		t.Text = "NIGHTMARE FORM"
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(245, 235, 255)
		t.TextTransparency = 1
		t.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = PURPLE
		stroke.Thickness = 2.5
		stroke.Transparency = 1
		stroke.Parent = t
		local scale = Instance.new("UIScale")
		scale.Scale = 1.25
		scale.Parent = t
		Fx.Tween(t, 0.18, { TextTransparency = 0 })
		Fx.Tween(stroke, 0.18, { Transparency = 0 })
		Fx.Tween(scale, 0.5, { Scale = 1 })
		task.delay(hold, function()
			Fx.Tween(t, 0.2, { TextTransparency = 1 })
			Fx.Tween(stroke, 0.2, { Transparency = 1 })
		end)
	end)
end

-- The caster's camera: the sword turning black, the whole body, then a low shot on the face.
local function cinematic(character, root, cut)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local savedType, savedFov, savedCF = cam.CameraType, cam.FieldOfView, cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable
	-- the HUDs step aside for the cinematic (each one put back unless something else changed it)
	local hidden = {}
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, g in pg:GetChildren() do
			if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "SV_Cinematic" then
				g.Enabled = false
				table.insert(hidden, g)
			end
		end
	end
	local gui = letterbox(cut)
	titleCard(gui, cut * 0.68, cut * 0.24)
	local rcf = root.CFrame
	local weapon = Fx.Weapon(character)
	local blade = weapon and weapon:FindFirstChild("SOST_Blade")
	local head = character:FindFirstChild("Head")
	local function rel(x, y, z)
		return rcf:PointToWorldSpace(Vector3.new(x, y, z))
	end
	local s1, s2 = cut * 0.34, cut * 0.68
	local stopShots = Fx.Every(cut, function(t)
		if not root.Parent or cam.CameraType ~= Enum.CameraType.Scriptable then return false end
		local pos, focus, fov
		if t < s1 then
			local k = Fx.Smooth(t / s1)
			pos = rel(4.2, 0.6, -4.0):Lerp(rel(3.4, 0.9, -3.2), k) -- from the sword's side, so the body is behind it
			focus = if blade and blade.Parent then blade.Position else rel(0.8, 0.5, -1)
			fov = 55
		elseif t < s2 then
			local k = Fx.Smooth((t - s1) / (s2 - s1))
			pos = rel(-1.5, 0.2, -10):Lerp(rel(-0.8, 0.6, -8.2), k)
			focus = rel(0, 0.6, 0)
			fov = 50
		else
			local k = Fx.Smooth((t - s2) / (cut - s2))
			pos = rel(0.9, 0.8, -5.4):Lerp(rel(0.6, 1.1, -4.4), k)
			focus = if head and head.Parent then head.Position else rel(0, 1.6, 0)
			fov = 50 - 6 * k
		end
		cam.CFrame = CFrame.lookAt(pos, focus)
		cam.FieldOfView = fov
		return nil
	end)
	task.delay(cut, function()
		stopShots() -- its last frame must not land after the restore
		cam.FieldOfView = savedFov
		cam.CFrame = savedCF -- the follow camera picks up from where it was
		cam.CameraType = if savedType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedType
		for _, g in hidden do
			if g.Parent and not g.Enabled then g.Enabled = true end
		end
	end)
end

function M.Nightmare(data, env)
	local character, root = env.character, env.root
	if not character or not root then return end
	local cut = tonumber(data.cutscene) or 2.4

	-- the swell lands its stop as time starts again; crackle as the body turns black
	Fx.Sound(sid(SFX.Dramatic), if env.mine then nil else root, { volume = vol(env, 0.85), from = 0.3 })
	task.delay(0.8, function()
		if root.Parent then Fx.Sound(sid(SFX.Electric), root, { volume = vol(env, 0.55), pitch = 0.7 }) end
	end)

	-- time stops (everyone in the run sees it)
	Fx.Grade({ Saturation = -0.8, Contrast = 0.25, Brightness = -0.05, TintColor = Color3.fromRGB(222, 205, 255) }, 0.2, math.max(0.1, cut - 0.5), 0.35)
	local ground = CFrame.new(root.Position.X, Fx.FeetY(character, root) + 0.1, root.Position.Z)
	Fx.Ring(ground, 1, 9, PURPLE, 0.6, 10)
	Fx.Burst(root.Position, {
		texture = Tex.BlackBolt, color = WHITE, count = 10, speed = NumberRange.new(2, 6), life = NumberRange.new(0.15, 0.3),
		size = NumberSequence.new(1.6, 2.6), emission = 0,
	})

	if env.mine then
		Fx.PlayAnim(KIT, "Nightmare", { fade = 0.1 })
		cinematic(character, root, cut)
	end
	if not Fx.Animation(KIT, "Nightmare") then
		-- stand-in: the sword held up before the face while it turns black
		Fx.Pose(character, cut, 10, function(t)
			local k = Fx.EaseOut(clamp01(t / 0.3))
			return CFrame.Angles(math.rad(95) * k, math.rad(-20) * k, 0)
		end, 0.3)
	end

	-- the form bursts out as time starts again
	task.delay(math.max(0, cut - 0.12), function()
		if not root.Parent then return end
		local pos = root.Position
		local g = CFrame.new(pos.X, Fx.FeetY(character, root) + 0.15, pos.Z)
		Fx.Ring(g, 2, 34, PURPLE, 0.7, 12)
		Fx.Ring(g, 1, 22, MAGENTA, 0.5, 8)
		Fx.Burst(pos, {
			texture = Tex.BlackBolt, color = WHITE, count = 24, speed = NumberRange.new(10, 26), life = NumberRange.new(0.2, 0.4),
			size = NumberSequence.new(2, 3.5), emission = 0, drag = 3,
		})
		Fx.Burst(pos, { color = ColorSequence.new(PURPLE, MAGENTA), count = 40, speed = NumberRange.new(12, 30), life = NumberRange.new(0.3, 0.6), size = 0.5, drag = 2 })
		Fx.Light(pos, PURPLE, 30, 6, 0.6)
		Fx.Shake(0.6, 0.5, pos)
		Fx.Sound(sid(SFX.DeepHit), root, { volume = vol(env, 0.75), duration = 3, fadeOut = 1.5 })
		Fx.Sound(sid(SFX.Electric), root, { volume = vol(env, 0.5) })
	end)
end

local fovBase, fovUntil = nil, 0
local function fovPunch(amount, seconds)
	local cam = workspace.CurrentCamera
	if not cam or cam.CameraType == Enum.CameraType.Scriptable then return end
	if os.clock() > fovUntil or not fovBase then fovBase = cam.FieldOfView end
	fovUntil = os.clock() + seconds
	cam.FieldOfView = fovBase + amount
	Fx.Tween(cam, seconds, { FieldOfView = fovBase })
end

function M.Moonlight(data, env)
	local character, root = env.character, env.root
	local from, to, target = data.from, data.to, data.target
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or typeof(target) ~= "Vector3" then return end
	if env.mine then Fx.PlayAnim(KIT, "Moonlight", { fade = 0.03 }) end

	-- where you were: a dark afterimage and black lightning
	if character and root then Fx.Ghost(character, Color3.fromRGB(35, 0, 60), 0.45, 0.25, from - root.Position) end
	Fx.Burst(from, {
		texture = Tex.BlackBolt, color = WHITE, count = 6, speed = NumberRange.new(2, 5), life = NumberRange.new(0.12, 0.25),
		size = NumberSequence.new(1.4, 2.2), emission = 0,
	})
	local dist = (to - from).Magnitude
	if dist > 0.5 then
		local streak = Fx.Part({
			Size = Vector3.new(0.35, 0.35, dist), CFrame = CFrame.lookAt((from + to) / 2, to),
			Material = Enum.Material.Neon, Color = Color3.fromRGB(150, 60, 255), Transparency = 0.15,
		})
		Fx.Tween(streak, 0.22, { Transparency = 1, Size = Vector3.new(0.05, 0.05, dist) })
		Debris:AddItem(streak, 0.3)
	end

	-- the Moonlight Slash: a golden jagged crescent across the enemy
	local at = target + Vector3.new(0, 1, 0)
	Fx.Sound(sid(SFX.WhooshBy), to, { volume = vol(env, 0.45), pitch = 1.5, duration = 0.7, fadeOut = 0.3 })
	Fx.Sound(sid(SFX.Swish[math.random(1, #SFX.Swish)]), at, { volume = vol(env, 0.5), pitch = 0.85 })
	Fx.Sound(sid(SFX.Electric), at, { volume = vol(env, 0.45), pitch = 1.25 })
	local holder = Fx.Part({ CFrame = CFrame.new(at) })
	local size = 13
	local rot = math.random(-40, 40) + (if math.random() < 0.5 then 180 else 0)
	local gui, img = Fx.Billboard(holder, size * 0.35, Tex.MoonSlash, { brightness = 3, rotation = rot })
	Fx.Tween(gui, 0.07, { Size = UDim2.fromScale(size, size) }, Enum.EasingStyle.Back)
	task.delay(0.12, function()
		Fx.Tween(gui, 0.3, { Size = UDim2.fromScale(size * 1.15, size * 1.15) })
		Fx.Tween(img, 0.3, { ImageTransparency = 1 })
	end)
	Debris:AddItem(holder, 0.5)
	Fx.Burst(at, { color = ColorSequence.new(WHITE, GOLD), count = 30, speed = NumberRange.new(10, 26), life = NumberRange.new(0.2, 0.45), size = 0.5, drag = 3 })
	Fx.Light(at, GOLD, 22, 5, 0.35)
	-- arriving in black lightning
	Fx.Burst(to, {
		texture = Tex.BlackBolt, color = WHITE, count = 8, speed = NumberRange.new(3, 8), life = NumberRange.new(0.12, 0.25),
		size = NumberSequence.new(1.6, 2.4), emission = 0,
	})
	Fx.Burst(to, { color = ColorSequence.new(PURPLE, MAGENTA), count = 12, speed = NumberRange.new(4, 10), life = NumberRange.new(0.2, 0.4), size = 0.35 })
	if env.mine then
		Fx.Shake(0.4, 0.25)
		fovPunch(-7, 0.25)
	end
end

function M.NightmareEnd(_, env)
	local root = env.root
	if not root then return end
	Fx.Sound(sid(SFX.Suck), root, { volume = vol(env, 0.45) })
	Fx.Burst(root.Position, {
		texture = Fx.SMOKE, color = Color3.fromRGB(40, 10, 60), count = 14, speed = NumberRange.new(2, 5),
		life = NumberRange.new(0.6, 1), size = NumberSequence.new(2, 4), emission = 0, transparency = NumberSequence.new(0.4, 1), drag = 2,
	})
	Fx.Burst(root.Position, { color = PURPLE, count = 20, speed = NumberRange.new(3, 8), life = NumberRange.new(0.3, 0.6), size = 0.3 })
end

-- ===================================================================== presence (always on)
-- While the sword is equipped (lobby and runs) the BLADE itself burns: licking golden flames over
-- its whole length, a soft gold light sheath, gold + purple lightning crackling along the edge
-- (crawling arcs + short bolt flashes), sparks and twinkles drifting off it, a glint that runs up
-- it and a flickering gold light. Nothing on the ground.
-- Called by WeaponFxClient with (character, model, env); returns a cleanup function.
-- env.far = true when the viewer is far away (the small particles are skipped, the flames thin out).
local LIGHTNING_PURPLE = Color3.fromRGB(190, 110, 255)

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in props do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

function M.Presence(character, model, env)
	local blade = model:FindFirstChild("SOST_Blade")
	if not blade or not blade:IsA("BasePart") then return nil end
	local made = {}
	local function own(inst)
		table.insert(made, inst)
		return inst
	end
	local half = blade.Size.Z / 2 -- the blade runs along its Z, tip at -Z
	local base = own(Instance.new("Attachment"))
	base.Name = "SV_Base"
	base.Position = Vector3.new(0, 0, half * 0.88)
	base.Parent = blade
	local tip = own(Instance.new("Attachment"))
	tip.Name = "SV_Tip"
	tip.Position = Vector3.new(0, 0, -half * 0.97)
	tip.Parent = blade

	-- golden flames licking up from the whole blade (they rise whatever way the blade points)
	local flames = own(emitter(blade, {
		Name = "SV_Flames", Texture = Tex.FlameGold,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2, FlipbookMode = Enum.ParticleFlipbookMode.Loop, FlipbookFramerate = NumberRange.new(10, 16),
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 150, 40)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.35, 1.2), NumberSequenceKeypoint.new(1, 0.35) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.65), NumberSequenceKeypoint.new(0.15, 0.15), NumberSequenceKeypoint.new(0.7, 0.45), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.3, 0.5), Speed = NumberRange.new(0.2, 1), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 5, 0), Drag = 2, Rotation = NumberRange.new(-15, 15), RotSpeed = NumberRange.new(-20, 20),
		Rate = 44, LightEmission = 1, Brightness = 1.6, ZOffset = 0.25,
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	}))
	-- soft gold sheath of light along the blade
	local sheath = own(Instance.new("Beam"))
	sheath.Name = "SV_Sheath"
	sheath.Attachment0, sheath.Attachment1 = base, tip
	sheath.Texture = Tex.GlowStrip
	sheath.TextureMode = Enum.TextureMode.Stretch
	sheath.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 170, 50))
	sheath.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 0.6) })
	sheath.Width0, sheath.Width1 = 1.2, 0.7
	sheath.LightEmission, sheath.LightInfluence, sheath.Brightness = 1, 0, 1.5
	sheath.FaceCamera = true
	sheath.Parent = blade
	-- crawling lightning along the edge: two beams whose path jumps every few frames
	local function arc(name, color, width)
		local b = own(Instance.new("Beam"))
		b.Name = name
		b.Attachment0, b.Attachment1 = base, tip
		b.Texture = Tex.BoltStrip
		b.TextureMode = Enum.TextureMode.Wrap
		b.TextureLength = 2.6
		b.TextureSpeed = 4
		b.Color = ColorSequence.new(color)
		b.Width0, b.Width1 = width, width * 0.7
		b.LightEmission, b.LightInfluence, b.Brightness = 1, 0, 3
		b.FaceCamera = true
		b.Segments = 14
		b.Parent = blade
		return b
	end
	local arcGold = arc("SV_ArcGold", Color3.fromRGB(255, 225, 110), 1.1)
	local arcPurple = arc("SV_ArcPurple", LIGHTNING_PURPLE, 0.9)
	-- short bolt flashes jumping off the blade
	local boltsGold = own(emitter(blade, {
		Name = "SV_BoltsGold", Texture = Tex.Bolts,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2, FlipbookMode = Enum.ParticleFlipbookMode.Random,
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 130)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 2.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.7) }),
		Lifetime = NumberRange.new(0.06, 0.12), Speed = NumberRange.new(0), Rotation = NumberRange.new(0, 360),
		Rate = 12, LightEmission = 1, Brightness = 3, ZOffset = 0.5,
	}))
	local boltsPurple = own(emitter(blade, {
		Name = "SV_BoltsPurple", Texture = Tex.Bolts,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2, FlipbookMode = Enum.ParticleFlipbookMode.Random,
		Color = ColorSequence.new(LIGHTNING_PURPLE),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.3), NumberSequenceKeypoint.new(1, 1.9) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.7) }),
		Lifetime = NumberRange.new(0.06, 0.12), Speed = NumberRange.new(0), Rotation = NumberRange.new(0, 360),
		Rate = 6, LightEmission = 1, Brightness = 3, ZOffset = 0.5,
	}))
	-- sparks + twinkles drifting off the blade
	local sparks = own(emitter(blade, {
		Name = "SV_Sparks", Texture = Tex.Spark,
		Color = ColorSequence.new(Color3.fromRGB(255, 236, 170), GOLD),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 1.1), Speed = NumberRange.new(0.6, 2.2), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 3, 0), Drag = 1.5, Rate = 26, LightEmission = 1, Brightness = 3, ZOffset = 0.4,
	}))
	local twinkle = own(emitter(blade, {
		Name = "SV_Twinkle", Texture = Tex.Flare,
		Color = ColorSequence.new(Color3.new(1, 1, 1), GOLD),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 1.2), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.22, 0.32), Speed = NumberRange.new(0), Rate = 4,
		LightEmission = 1, Brightness = 2.5, ZOffset = 0.6,
	}))
	local glow = own(Instance.new("PointLight"))
	glow.Name = "SV_Glow"
	glow.Color = GOLD
	glow.Range = 12
	glow.Brightness = 1.8
	glow.Shadows = false
	glow.Parent = blade

	-- the glint that runs up the blade
	local glintAt = own(Instance.new("Attachment"))
	glintAt.Name = "SV_Glint"
	glintAt.Parent = blade
	local glintGui, glintImg = Fx.Billboard(glintAt, 0.1, Tex.Flare, { color = Color3.fromRGB(255, 245, 215), brightness = 3 })
	glintImg.ImageTransparency = 1

	local alive = true
	local t, glintT, nextJump = 0, 0, 0
	local conn = game:GetService("RunService").RenderStepped:Connect(function(dt)
		if not blade.Parent then return end
		local far = env.far == true
		sparks.Enabled = not far
		twinkle.Enabled = not far
		boltsGold.Enabled = not far
		boltsPurple.Enabled = not far
		flames.Rate = if far then 18 else 44
		t += dt
		-- the arcs jump to a new path every few frames and flicker on / off
		if t >= nextJump then
			nextJump = t + 0.05 + math.random() * 0.05
			for _, b in { arcGold, arcPurple } do
				b.CurveSize0 = (math.random() - 0.5) * 1.6
				b.CurveSize1 = (math.random() - 0.5) * 1.6
			end
			local gOn = math.random() < 0.7
			local pOn = math.random() < (if far then 0.15 else 0.4)
			arcGold.Transparency = NumberSequence.new(if gOn then 0.05 else 1)
			arcPurple.Transparency = NumberSequence.new(if pOn then 0.1 else 1)
			glow.Brightness = 1.4 + (if gOn then 0.8 else 0) + math.random() * 0.4
			glow.Color = if pOn and not gOn then LIGHTNING_PURPLE else GOLD
		end
		-- glint: base -> tip in 0.45 s, every 2.6 s
		glintT += dt
		local g = glintT % 2.6
		if g < 0.45 then
			local a = g / 0.45
			glintAt.Position = Vector3.new(0, 0, half * 0.8 - a * half * 1.8)
			local s = 2.8 * math.sin(a * math.pi)
			glintGui.Size = UDim2.fromScale(s, s)
			glintImg.ImageTransparency = 1 - math.sin(a * math.pi)
		else
			glintImg.ImageTransparency = 1
		end
	end)
	return function()
		if not alive then return end
		alive = false
		conn:Disconnect()
		if glintGui then glintGui:Destroy() end
		for _, inst in made do inst:Destroy() end
	end
end

-- Equipping the sword: the blade ignites -- a burst of flames and lightning along it, a flash on
-- the blade, sparks flying off it, a gold light (and, for your own character, the equip flourish).
function M.Equip(character, model, env)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if env.mine then Fx.PlayAnim(KIT, "Equip", { fade = 0.1 }) end
	local blade = model:FindFirstChild("SOST_Blade")
	if not blade or not blade:IsA("BasePart") then return end
	task.delay(0.2, function()
		if not blade.Parent then return end
		local flare = blade:FindFirstChild("SV_Flames")
		if flare and flare:IsA("ParticleEmitter") then flare:Emit(40) end
		local b1 = blade:FindFirstChild("SV_BoltsGold")
		if b1 and b1:IsA("ParticleEmitter") then b1:Emit(10) end
		local b2 = blade:FindFirstChild("SV_BoltsPurple")
		if b2 and b2:IsA("ParticleEmitter") then b2:Emit(6) end
		Fx.Impact(blade.Position, { star = Tex.Flare, color = GOLD, scale = 2, sparks = 0 })
		Fx.Light(blade.Position, GOLD, 20, 5, 0.6)
		Fx.Burst(blade.Position, {
			texture = Tex.Spark, color = ColorSequence.new(Color3.new(1, 1, 1), GOLD), count = 30, speed = NumberRange.new(8, 20),
			life = NumberRange.new(0.4, 0.9), size = 0.5, spread = 180, drag = 3, accel = Vector3.new(0, -6, 0), box = blade.Size,
		})
		Fx.Sound(sid(SFX.Electric), blade, { volume = vol(env, 0.35), pitch = 1.1 })
	end)
	Fx.Sound(sid(SFX.Chime), root, { volume = vol(env, 0.45) })
	Fx.Sound(sid(SFX.WhooshBy), root, { volume = vol(env, 0.3), pitch = 0.8 })
end

return M
