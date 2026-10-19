--!strict
-- SevenVerities
-- Location: ServerScriptService.WeaponKits.Kits.SevenVerities (ModuleScript)
-- Blade of Seven Verities -- the Absolute God set's signature weapon. Spec: weapon 1 in
-- the Superior weapons design doc (every given number is kept as written;
-- values the spec leaves open are marked [AI]).
--   Basic    4-step combo toward the nearest enemy: right-to-left cut, backhand, overhead
--            diagonal (cone AoE each), then a 360 spin finisher that hits all around for 1.6x.
--            The chain resets after a short pause. Moderate damage, range, speed.
--   Passive  each kill with this weapon may grant a random stat until the run ends: Move
--            Speed / Attack Speed / Range / Damage / Crit Chance, +1% per stack. Chance 10%,
--            +10% after every kill that gives nothing, back to 10% after a drop. Granted at
--            once; an icon flies from the enemy into the player (client).
--   Skill 1  Lucky Coin (cd 10 s, boost 5 s): a digital coin tosses above the player; after
--            1 s it grants a random boost (damage, range, move speed, health regen, attack
--            speed, crit damage). Every 10 uses in a run add a coin (use 11 = 2 coins, use
--            21 = 3 ...). Duplicate boosts stack.
--   Skill 2  Mastered Magic (cd [AI] 16 s): sword raised, magic gates open in front, a red
--            continuous laser for 5 s across the whole field where the player faces --
--            steered by turning; small move-speed boost meanwhile. Moderate damage.
--   Ult      Nightmare Form (cd 80 s, 15 s): cutscene with every enemy frozen -- the sword
--            turns black, then the player (black, purple outlines), black electric aura on
--            both. Then every stat up, dash cooldown 0.5 s, and every dash teleports to the
--            nearest enemy in a very big reach and lands a Moonlight Slash (very huge
--            damage; no damage taken while doing it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ServiceRegistry = require(ServerScriptService.ServiceRegistry)
local StatService = require(ServerScriptService.Progression:WaitForChild("StatService"))
local EnemyStatus = require(script.Parent.Parent.EnemyStatus)
local TextureIds = require(ReplicatedStorage:WaitForChild("WeaponKits"):WaitForChild("TextureIds"))

local Kit = {}
Kit.id = "seven_verities"
Kit.gearId = "absolutegod_weapon"
Kit.displayName = "Blade of Seven Verities"
Kit.weaponType = "Sword"
Kit.passive = {
	name = "Seven Verities",
	description = "Kills can grant a random stat (+1% Move Speed, Attack Speed, Range, Damage or Crit Chance) for the rest of the run. 10% chance, +10% after every kill that gives nothing.",
}

-- ===== numbers =====
local BASIC = { range = 13, angle = 120, -- moderate reach; damage + speed = the weapon's normal basic attack
	steps = 4, reset = 1.6, finisherPower = 1.6, finisherTime = 1.35 } -- [AI] combo: 4th step = spin, a bit slower
local PASSIVE = { base = 10, step = 10, per = 1, stats = { "speed", "attackSpeed", "range", "damage", "critChance" } }
local COIN = {
	toss = 1.0, duration = 5, perCoin = 10,
	keys = { "damage", "range", "speed", "regen", "attackSpeed", "critDamage" },
	-- [AI] size of one boost (stacks per duplicate coin)
	damage = 30, range = 30, speed = 30, regenPctOfMax = 4, attackSpeed = 30, critDamage = 60,
}
local LASER = { duration = 5, open = 0.35, tick = 0.2, power = 0.12, length = 400, width = 7, speed = 15 }
local NIGHT = {
	cutscene = 2.4, duration = 15, dashCooldown = 0.5, reach = 160, power = 0.45, iframes = 0.4,
	-- [AI] "every stat boosted"
	pct = 30, attackSpeed = 30, critChance = 15, critDamage = 40, speed = 30, range = 30,
}

Kit.slots = {
	["1"] = { id = "lucky_coin", name = "Lucky Coin", cooldown = 10, power = 0,
		description = "Toss a digital coin: after 1 s it grants a random boost for 5 s (damage, range, move speed, health regen, attack speed or crit damage). Every 10 uses add a coin; duplicate boosts stack." },
	["2"] = { id = "mastered_magic", name = "Mastered Magic", cooldown = 16, power = LASER.power, hits = 23,
		description = "Raise the sword: magic gates fire a red laser across the whole field for 5 s. Turn to steer it. Small move-speed boost meanwhile." },
	U = { id = "nightmare_form", name = "Nightmare Form", cooldown = 80, power = NIGHT.power, kind = "Ultimate",
		description = "Transform for 15 s: every stat up and a 0.5 s dash. Every dash teleports you to the nearest enemy for a Moonlight Slash -- untouchable while you do it." },
}

local BLACK = Color3.new(0, 0, 0)
local PURPLE = Color3.fromRGB(170, 70, 255)
local MAGENTA = Color3.fromRGB(255, 45, 220)

function Kit.NewState(s: any)
	s.dropChance = PASSIVE.base
	s.stacks = { speed = 0, attackSpeed = 0, range = 0, damage = 0, critChance = 0 }
	s.coinUses = 0
	s.swing = 0
end

local function nightmareOn(s: any): boolean
	return (s.nightmareUntil or 0) > os.clock()
end

-- Range: passive stacks + an active coin + Nightmare Form.
function Kit.RangeMult(s: any): number
	local pct = s.stacks.range * PASSIVE.per
	if s.coinRange and s.coinRange.untilT > os.clock() then pct += s.coinRange.pct end
	if nightmareOn(s) then pct += NIGHT.range end
	return 1 + pct / 100
end

-- Passive stacks as stats (StatService source "WeaponKit"; Range is used by the kit itself).
function Kit.StatMods(ctx: any)
	local st = ctx.state.stacks
	return {
		attackSpeed = st.attackSpeed * PASSIVE.per,
		critChance = st.critChance * PASSIVE.per,
		walkSpeedPct = st.speed * PASSIVE.per,
	}, { damage = st.damage * PASSIVE.per }
end

-- ===== basic attack =====
function Kit.Basic(ctx: any): number
	local s = ctx.state
	if s.busy then return 0.2 end
	local combat = ServiceRegistry.Get("Combat")
	if not combat then return 0.8 end
	local attack = combat.GetAttack(ctx.player)
	local range = BASIC.range * Kit.RangeMult(s)
	local pos = ctx.root.Position
	local target = ctx.util.Nearest(ctx.run, pos, range)
	if not target then return 0.12 end -- swing as soon as something is in reach
	local dir = ctx.util.Flat(target.root.Position - pos)
	local now = os.clock()
	if now - (s.lastSwing or 0) > attack.interval + BASIC.reset then s.swing = 0 end -- paused: start over
	s.lastSwing = now
	s.swing = (s.swing % BASIC.steps) + 1
	local finisher = s.swing == BASIC.steps
	ctx.util.Fx(ctx.run, Kit.id, "Swing", {
		caster = ctx.player.UserId, dir = dir, range = range, angle = BASIC.angle, n = s.swing,
		interval = attack.interval, form = nightmareOn(s),
	})
	local hits = if finisher then ctx.util.Circle(ctx.run, pos, range) else ctx.util.Cone(ctx.run, pos, dir, range, BASIC.angle)
	local raw = if finisher then attack.damage * BASIC.finisherPower else attack.damage
	for _, e in hits do
		ctx.util.Hit(ctx.player, ctx.run, e, raw, ctx.template, { basic = true })
	end
	return if finisher then attack.interval * BASIC.finisherTime else attack.interval
end

-- ===== passive =====
function Kit.OnKill(ctx: any, model: Model, _template: any)
	local s = ctx.state
	if math.random() * 100 < s.dropChance then
		local stat = PASSIVE.stats[math.random(1, #PASSIVE.stats)]
		s.stacks[stat] += 1
		s.dropChance = PASSIVE.base
		StatService.Refresh(ctx.player)
		local from = if model.PrimaryPart then model.PrimaryPart.Position elseif ctx.root then ctx.root.Position else Vector3.zero
		ctx.util.Fx(ctx.run, Kit.id, "StatDrop", { caster = ctx.player.UserId, stat = stat, stacks = s.stacks[stat], per = PASSIVE.per, from = from })
	else
		s.dropChance = math.min(100, s.dropChance + PASSIVE.step)
	end
end

-- ===== skill 1: Lucky Coin =====
local function luckyCoin(ctx: any): boolean
	local s, player = ctx.state, ctx.player
	s.coinUses += 1
	local coins = 1 + math.floor((s.coinUses - 1) / COIN.perCoin)
	local rolls = {}
	for i = 1, coins do rolls[i] = COIN.keys[math.random(1, #COIN.keys)] end
	ctx.util.Fx(ctx.run, Kit.id, "Coin", {
		caster = player.UserId, rolls = rolls, toss = COIN.toss, duration = COIN.duration, use = s.coinUses,
		-- one coin's boost (% -- regen: % of max HP per second), for the labels
		amounts = { damage = COIN.damage, range = COIN.range, speed = COIN.speed, regen = COIN.regenPctOfMax, attackSpeed = COIN.attackSpeed, critDamage = COIN.critDamage },
	})
	task.delay(COIN.toss, function()
		local character = player.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		local n: {[string]: number} = {}
		for _, k in rolls do n[k] = (n[k] or 0) + 1 end
		local flat, pct = {}, {}
		if n.damage then pct.damage = COIN.damage * n.damage end
		if n.speed then flat.walkSpeedPct = COIN.speed * n.speed end
		if n.attackSpeed then flat.attackSpeed = COIN.attackSpeed * n.attackSpeed end
		if n.critDamage then flat.critDamage = COIN.critDamage * n.critDamage end
		if n.regen then flat.regen = hum.MaxHealth * COIN.regenPctOfMax / 100 * n.regen end
		s.coinRange = { pct = COIN.range * (n.range or 0), untilT = os.clock() + COIN.duration }
		ctx.util.Buff(player, "sv_lucky_coin", flat, pct, COIN.duration)
	end)
	return true
end

-- ===== skill 2: Mastered Magic =====
local function masteredMagic(ctx: any): boolean
	local s, player, run = ctx.state, ctx.player, ctx.run
	local raw = ctx.util.Power(player, "Ability", LASER.power, ctx.template)
	ctx.util.Buff(player, "sv_mastered_magic", { walkSpeedPct = LASER.speed }, nil, LASER.duration)
	ctx.util.Fx(run, Kit.id, "Laser", { caster = player.UserId, duration = LASER.duration, open = LASER.open, length = LASER.length, width = LASER.width })
	s.laserUntil = os.clock() + LASER.duration
	task.spawn(function()
		task.wait(LASER.open) -- the gates open first
		while os.clock() < (s.laserUntil or 0) and run.active do
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if not hrp or not hum or hum.Health <= 0 then break end
			local look = ctx.util.Flat(hrp.CFrame.LookVector)
			for _, e in ctx.util.Line(run, hrp.Position + look * 2, look, LASER.length, LASER.width) do
				ctx.util.Hit(player, run, e, raw, ctx.template)
			end
			task.wait(LASER.tick)
		end
	end)
	return true
end

-- ===== ultimate: Nightmare Form =====
local function weaponModel(character: Model): Model?
	local gv = character:FindFirstChild("GearVisuals")
	local w = gv and gv:FindFirstChild("Weapon")
	return w and w:FindFirstChildWhichIsA("Model")
end

local function neonPart(name: string, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Material = Enum.Material.Neon
	p.Color = color
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
	p.Massless = true
	return p
end

local function stick(part: BasePart, base: BasePart, offset: CFrame, parent: Instance)
	part.CFrame = base.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = part
	w.Parent = part
	part.Parent = parent
end

-- Black lightning + purple sparks crackling around a part (volume of the part).
local function crackle(part: BasePart, rate: number): {ParticleEmitter}
	local bolt = Instance.new("ParticleEmitter")
	bolt.Name = "NightmareBolts"
	bolt.Texture = if TextureIds.BlackBolt ~= "" then TextureIds.BlackBolt else TextureIds.Fallback.Spark
	bolt.Color = if TextureIds.BlackBolt ~= "" then ColorSequence.new(Color3.new(1, 1, 1)) else ColorSequence.new(Color3.fromRGB(40, 0, 60))
	bolt.Shape = Enum.ParticleEmitterShape.Box
	bolt.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	bolt.Rate = rate
	bolt.Lifetime = NumberRange.new(0.1, 0.22)
	bolt.Speed = NumberRange.new(0.5, 2.5)
	bolt.SpreadAngle = Vector2.new(180, 180)
	bolt.Rotation = NumberRange.new(0, 360)
	bolt.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 2.0) })
	bolt.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
	bolt.LightEmission = 0
	bolt.LightInfluence = 0
	bolt.ZOffset = 0.4
	bolt.Parent = part
	local spark = Instance.new("ParticleEmitter")
	spark.Name = "NightmareSparks"
	spark.Texture = TextureIds.Fallback.Spark
	spark.Color = ColorSequence.new(PURPLE, MAGENTA)
	spark.Shape = Enum.ParticleEmitterShape.Box
	spark.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	spark.Rate = rate * 0.6
	spark.Lifetime = NumberRange.new(0.25, 0.5)
	spark.Speed = NumberRange.new(2, 6)
	spark.SpreadAngle = Vector2.new(180, 180)
	spark.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	spark.LightEmission = 1
	spark.Parent = part
	return { bolt, spark }
end

local function clearNightmareVisuals(s: any)
	local v = s.nightmareFx
	s.nightmareFx = nil
	if not v then return end
	for _, inst in v.instances do
		if inst.Parent then inst:Destroy() end
	end
	if v.conn then v.conn:Disconnect() end
end

-- Everything that has to replicate and outlive the cutscene: highlights, aura, the
-- glowing details (forehead crest, white eyes, chest crack, belt orb). The details
-- live outside the character so the black fill doesn't cover them.
local function nightmareVisuals(player: Player, character: Model, s: any)
	clearNightmareVisuals(s)
	local list: {Instance} = {}
	local holder = Instance.new("Folder")
	holder.Name = "NightmareFx_" .. player.UserId
	holder.Parent = Workspace
	table.insert(list, holder)

	local sword = weaponModel(character)
	-- 1) the sword turns black
	if sword then
		local hs = Instance.new("Highlight")
		hs.Name = "NightmareSword"
		hs.Adornee = sword
		hs.FillColor = BLACK
		hs.OutlineColor = PURPLE
		hs.FillTransparency = 1
		hs.OutlineTransparency = 1
		hs.DepthMode = Enum.HighlightDepthMode.Occluded
		hs.Parent = holder
		TweenService:Create(hs, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { FillTransparency = 0, OutlineTransparency = 0.1 }):Play()
		local blade = sword:FindFirstChild("SOST_Blade") :: BasePart?
		if blade then
			task.delay(0.3, function()
				if blade.Parent then for _, e in crackle(blade, 30) do table.insert(list, e) end end
			end)
		end
	end

	-- 2) then the player: black with purple outlines
	task.delay(0.8, function()
		if not character.Parent or s.nightmareFx == nil then return end
		local hb = Instance.new("Highlight")
		hb.Name = "NightmareBody"
		hb.Adornee = character
		hb.FillColor = BLACK
		hb.OutlineColor = PURPLE
		hb.FillTransparency = 1
		hb.OutlineTransparency = 1
		hb.DepthMode = Enum.HighlightDepthMode.Occluded
		hb.Parent = holder
		TweenService:Create(hb, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { FillTransparency = 0, OutlineTransparency = 0 }):Play()

		for _, name in { "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftUpperLeg", "RightUpperLeg", "Head" } do
			local part = character:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				for _, e in crackle(part, if name == "UpperTorso" then 26 else 10) do table.insert(list, e) end
			end
		end

		local head = character:FindFirstChild("Head") :: BasePart?
		local chest = character:FindFirstChild("UpperTorso") :: BasePart?
		local waist = character:FindFirstChild("LowerTorso") :: BasePart?
		if head then
			local hs = head.Size
			local front = -hs.Z / 2 - 0.02
			-- magenta V crest on the forehead
			for _, side in { -1, 1 } do
				local arm = neonPart("Crest", Vector3.new(hs.X * 0.09, hs.Y * 0.34, 0.05), MAGENTA)
				stick(arm, head, CFrame.new(side * hs.X * 0.09, hs.Y * 0.3, front) * CFrame.Angles(0, 0, math.rad(side * 32)), holder)
			end
			local tip = neonPart("CrestTip", Vector3.new(hs.X * 0.1, hs.X * 0.1, 0.05), MAGENTA)
			stick(tip, head, CFrame.new(0, hs.Y * 0.16, front) * CFrame.Angles(0, 0, math.rad(45)), holder)
			-- glowing white eyes
			for _, side in { -1, 1 } do
				local eye = neonPart("Eye", Vector3.new(hs.X * 0.2, hs.Y * 0.07, 0.04), Color3.new(1, 1, 1))
				stick(eye, head, CFrame.new(side * hs.X * 0.18, hs.Y * 0.03, front) * CFrame.Angles(0, 0, math.rad(side * -10)), holder)
			end
		end
		if chest then
			local cs = chest.Size
			-- jagged lilac crack on the right chest
			local pts = { Vector2.new(0.10, 0.36), Vector2.new(0.22, 0.18), Vector2.new(0.14, 0.02), Vector2.new(0.28, -0.16), Vector2.new(0.20, -0.32) }
			for i = 1, #pts - 1 do
				local a = Vector3.new(pts[i].X * cs.X, pts[i].Y * cs.Y, -cs.Z / 2 - 0.03)
				local b = Vector3.new(pts[i + 1].X * cs.X, pts[i + 1].Y * cs.Y, -cs.Z / 2 - 0.03)
				local seg = neonPart("Crack", Vector3.new(0.07, (b - a).Magnitude + 0.04, 0.04), Color3.fromRGB(200, 150, 255))
				local mid = (a + b) / 2
				local ang = math.atan2(b.X - a.X, b.Y - a.Y)
				stick(seg, chest, CFrame.new(mid) * CFrame.Angles(0, 0, -ang), holder)
			end
			-- red marks on the other side
			for i = 0, 1 do
				local mark = neonPart("RedMark", Vector3.new(0.08, cs.Y * 0.22, 0.04), Color3.fromRGB(255, 40, 60))
				stick(mark, chest, CFrame.new(-cs.X * (0.26 + i * 0.07), cs.Y * 0.12, -cs.Z / 2 - 0.03), holder)
			end
		end
		if waist then
			local orb = neonPart("Orb", Vector3.new(0.34, 0.34, 0.34), Color3.fromRGB(215, 120, 255), Enum.PartType.Ball)
			stick(orb, waist, CFrame.new(0, 0, -waist.Size.Z / 2 - 0.08), holder)
			local light = Instance.new("PointLight")
			light.Color = PURPLE
			light.Range = 7
			light.Brightness = 2
			light.Parent = orb
		end
	end)

	local hum = character:FindFirstChildOfClass("Humanoid")
	s.nightmareFx = {
		instances = list,
		conn = if hum then hum.Died:Connect(function() clearNightmareVisuals(s) end) else nil,
	}
end

local function endNightmare(player: Player, s: any, force: boolean?)
	if not force and (s.nightmareUntil or 0) > os.clock() + 0.05 then return end -- re-cast meanwhile
	s.nightmareUntil = 0
	clearNightmareVisuals(s)
	if player.Parent then
		player:SetAttribute("DashCooldown", nil)
		player:SetAttribute("DashTeleport", nil)
		player:SetAttribute("NightmareUntil", nil)
	end
end

local function nightmareForm(ctx: any): boolean
	local s, player, run = ctx.state, ctx.player, ctx.run
	local character: Model, hrp: BasePart = ctx.character, ctx.root
	s.busy = true
	EnemyStatus.FreezeRun(run, NIGHT.cutscene)
	ctx.util.SetInvulnerable(player, "sv_nightmare_cutscene", NIGHT.cutscene + 0.1)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.Anchored = true
	ctx.util.Fx(run, Kit.id, "Nightmare", { caster = player.UserId, cutscene = NIGHT.cutscene, duration = NIGHT.duration })
	nightmareVisuals(player, character, s)
	task.delay(NIGHT.cutscene, function()
		s.busy = false
		if hrp.Parent then hrp.Anchored = false end
		local hum = character:FindFirstChildOfClass("Humanoid")
		if not player.Parent or not hum or hum.Health <= 0 then
			endNightmare(player, s, true)
			return
		end
		s.nightmareUntil = os.clock() + NIGHT.duration
		ctx.util.Buff(player, "sv_nightmare_form",
			{ attackSpeed = NIGHT.attackSpeed, critChance = NIGHT.critChance, critDamage = NIGHT.critDamage, walkSpeedPct = NIGHT.speed },
			{ health = NIGHT.pct, defense = NIGHT.pct, damage = NIGHT.pct, magicDamage = NIGHT.pct, elementalDamage = NIGHT.pct, regen = NIGHT.pct },
			NIGHT.duration)
		player:SetAttribute("DashCooldown", NIGHT.dashCooldown)
		player:SetAttribute("DashTeleport", true)
		player:SetAttribute("NightmareUntil", Workspace:GetServerTimeNow() + NIGHT.duration)
		task.delay(NIGHT.duration, function()
			if s.nightmareUntil ~= 0 and s.nightmareUntil <= os.clock() + 0.05 then
				endNightmare(player, s)
				if run.active then ctx.util.Fx(run, Kit.id, "NightmareEnd", { caster = player.UserId }) end
			end
		end)
	end)
	return true
end

-- Dash during Nightmare Form: teleport to the nearest enemy + Moonlight Slash.
function Kit.OnDash(ctx: any): boolean
	local s = ctx.state
	if s.busy or not nightmareOn(s) then return false end
	local player, run, hrp = ctx.player, ctx.run, ctx.root :: BasePart
	local from = hrp.Position
	local enemies = ctx.util.Enemies(run, from, NIGHT.reach)
	local target = enemies[1]
	if not target then return false end -- nothing in reach: an ordinary dash
	local tpos = target.root.Position
	local dir = ctx.util.Flat(tpos - from)
	local gap = math.max(target.root.Size.X, target.root.Size.Z) / 2 + 2.5
	local stand = tpos - dir * gap
	local ignore: {Instance} = { ctx.character }
	for _, e in enemies do table.insert(ignore, e.model) end
	local groundY = ctx.util.GroundY(stand, ignore)
	local hipToRoot = (if ctx.humanoid then ctx.humanoid.HipHeight else 2) + hrp.Size.Y / 2
	local y = if groundY then groundY + hipToRoot else from.Y
	local dest = Vector3.new(stand.X, y, stand.Z)
	ctx.util.SetInvulnerable(player, "sv_moonlight", NIGHT.iframes)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.CFrame = CFrame.lookAt(dest, Vector3.new(tpos.X, y, tpos.Z))
	ctx.util.Fx(run, Kit.id, "Moonlight", { caster = player.UserId, from = from, to = dest, target = tpos })
	local raw = ctx.util.Power(player, "Ultimate", NIGHT.power, ctx.template)
	task.delay(0.12, function()
		ctx.util.Hit(player, run, target, raw, ctx.template)
	end)
	return true
end

function Kit.Cast(ctx: any, slot: string): boolean
	if slot == "1" then return luckyCoin(ctx) end
	if slot == "2" then return masteredMagic(ctx) end
	if slot == "U" then return nightmareForm(ctx) end
	return false
end

function Kit.EndRun(player: Player, s: any)
	s.laserUntil = 0
	endNightmare(player, s, true)
end

local _ = Players
return Kit
