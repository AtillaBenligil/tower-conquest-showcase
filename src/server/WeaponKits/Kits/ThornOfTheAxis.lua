--!strict
-- ThornOfTheAxis
-- Location: ServerScriptService.WeaponKits.Kits.ThornOfTheAxis (ModuleScript)
-- Thorn of the Axis -- the Enryu set's signature weapon. Spec: weapon 2 in
-- the Superior weapons design doc (every given number is kept as written;
-- values the spec leaves open are marked [AI]). Not held in the hand: equipped, it is a
-- crimson aura (client Presence); in a run, 10 small red gates open in a half-ring behind the
-- back and every attack comes out of them.
--   Basic    a volley of thin laser-arrows (travel time, arrowhead, slightly wavering): up to
--            10 distinct enemies in range, one gate each. Fast, moderate damage, long range.
--            4-step gesture chain [AI]: point / sideways sweep (curving arrows) / both arms
--            forward (fast straight arrows) / finisher (gates flare, heavier spear-arrows x1.6).
--   Skill 1  Creator of Thorn (cd [AI] 25 s): one red thorn rises from the top gates and floats
--            behind the back for 10 s. Meanwhile: stronger aura, more damage + attack speed,
--            hit enemies bleed (DOT, 3 ticks; a new hit resets it, never stacks) and are slowed
--            30% for 0.5 s on every hit.
--   Skill 2  Miracle (cd [AI] 35 s, summons [AI] 15 s): crimson dogs (max 2), birds (max 2),
--            fish (max 4). Dogs + birds draw the enemies' aggro (EnemyController.NearestDecoy)
--            and fight -- dogs bite up close (high damage, high speed), birds shoot from range
--            (slower, harder). Fish (no aggro) orbit the players: one per player, lowest HP
--            first, each one heals + speeds up its player.
--   Ult      Red Rain (cd 80 s, rain 20 s): the ultimate animation (3.4 s, enemies frozen, the
--            caster locked + untouchable, cinematic camera on the caster's screen): he gathers,
--            lifts off ~12 studs while the roof of the field fills with gates; then red rain pours:
--            continuous massive DOT on every enemy of the field.
--            In the air the player moves freely, is invulnerable and keeps attacking. After
--            20 s the rain ends, the gates go and the player slowly descends.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ServiceRegistry = require(ServerScriptService.ServiceRegistry)
local StatService = require(ServerScriptService.Progression:WaitForChild("StatService"))
local EnemyController = require(ServerScriptService.DungeonSystem:WaitForChild("EnemyController"))
local EnemyStatus = require(script.Parent.Parent.EnemyStatus)

local Kit = {}
Kit.id = "thorn_axis"
Kit.gearId = "enryo_weapon"
Kit.displayName = "Thorn of the Axis"
Kit.weaponType = "Aura"
Kit.passive = {
	name = "Gates of the Axis",
	description = "In a gamemode, 10 red gates open behind you. Every basic attack is a volley of laser-arrows: one gate per enemy, up to 10 enemies at once.",
}

-- ===== numbers =====
local BASIC = {
	range = 62, maxTargets = 10,             -- long range; spec: up to 10 distinct enemies
	speedMult = 0.75, power = 1.0,           -- [AI] "fast attack speed, moderate damage": 25% quicker than the weapon's interval
	steps = 4, reset = 1.6, finisherPower = 1.6, finisherTime = 1.3,  -- [AI] gesture chain
	arrowSpeed = { 150, 140, 210, 125 },     -- studs/s per step (not instant); step 3 = fast arrows
}
local THORN = {
	duration = 10,                           -- spec
	damagePct = 25, attackSpeed = 35,        -- [AI] the boost
	bleedTicks = 3, bleedEvery = 1.0, bleedPct = 30, -- spec: 3 ticks, resets; [AI] tick = 30% of the hit
	slowPct = 30, slowTime = 0.5,            -- spec
}
local MIRACLE = {
	duration = 15,                           -- [AI]
	dogs = 2, birds = 2, fishCount = 4,      -- spec maxima
	dog = { hpPct = 35, speed = 30, reach = 3.2, every = 0.45, power = 0.2 },     -- close, high dmg + speed
	bird = { hpPct = 25, speed = 34, reach = 30, every = 1.35, power = 0.42, height = 4.5 }, -- ranged, slower, harder
	fish = { healPct = 2, speedPct = 20, radius = 3.4 },                        -- heal % max HP / s, + move speed
	tick = 0.1, aggro = 70,                  -- decoys pull enemies within this many studs
}
local RAIN = {
	duration = 20, height = 12, descend = 2.2, -- spec 20 s; [AI] ~12 studs, slow descent
	cutscene = 3.4, liftFrom = 0.75, liftTo = 2.9, -- [AI] the ultimate animation: gather, lift off, gates open (enemies frozen)
	tick = 0.5, power = 0.08,                -- [AI] "massive" DOT on every enemy of the field (Ultimate scaling)
}

Kit.slots = {
	["1"] = { id = "creator_of_thorn", name = "Creator of Thorn", cooldown = 25, power = 0,
		description = "A red thorn rises from your gates for 10 s: +25% damage, +35 attack speed, your hits make enemies bleed (3 ticks, resets) and slow them 30% for 0.5 s." },
	["2"] = { id = "miracle", name = "Miracle", cooldown = 35, power = MIRACLE.dog.power, hits = 2,
		description = "Summon crimson creatures for 15 s: 2 dogs (bite, draw aggro), 2 birds (shoot from range, draw aggro) and fish that orbit your party, healing and speeding them up." },
	U = { id = "red_rain", name = "Red Rain", cooldown = 80, power = RAIN.power, kind = "Ultimate", hits = 40,
		description = "Levitate: gates cover the roof and red rain pours for 20 s, dealing massive damage to every enemy of the field. In the air you move freely, can't be hurt and keep attacking." },
}

function Kit.NewState(s: any)
	s.swing = 0
	s.bleeds = {}
	s.summons = {}
end

local function thornOn(s: any): boolean
	return (s.thornUntil or 0) > os.clock()
end

-- ===== gates =====
-- Gate i (1..10) behind the back, on a half-ring standing in the back plane, top gates over the
-- head. The client draws them with the same numbers (Fx.ThornOfTheAxis.GateOffset).
local GATE = { n = 10, radius = 5.4, back = 2.6, up = 1.0, from = -95, to = 95 }
local function gateOffset(i: number): Vector3
	local a = math.rad(GATE.from + (GATE.to - GATE.from) * (i - 1) / (GATE.n - 1))
	return Vector3.new(math.sin(a) * GATE.radius, GATE.up + math.cos(a) * GATE.radius * 0.8, GATE.back)
end
Kit.GateOffset = gateOffset

local function gatePos(root: BasePart, i: number): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local cf = if flat.Magnitude > 1e-3 then CFrame.lookAt(root.Position, root.Position + flat) else CFrame.new(root.Position)
	return cf:PointToWorldSpace(gateOffset(i))
end

-- ===== bleed (Creator of Thorn) =====
local function bleed(ctx: any, model: Model, perTick: number)
	local s, player, run = ctx.state, ctx.player, ctx.run
	local b = s.bleeds[model]
	if b then
		b.left = THORN.bleedTicks -- reset, never stack
		b.dmg = math.max(b.dmg, perTick)
		return
	end
	b = { left = THORN.bleedTicks, dmg = perTick }
	s.bleeds[model] = b
	task.spawn(function()
		while b.left > 0 and run.active do
			task.wait(THORN.bleedEvery)
			local hum = model.Parent and model:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then break end
			b.left -= 1
			ctx.util.Hit(player, run, model, b.dmg, ctx.template)
			ctx.util.Fx(run, Kit.id, "Bleed", { caster = player.UserId, at = model.PrimaryPart and model.PrimaryPart.Position })
		end
		if s.bleeds[model] == b then s.bleeds[model] = nil end
	end)
end

-- ===== basic attack =====
function Kit.Basic(ctx: any): number
	local s = ctx.state
	if s.busy then return 0.2 end
	local combat = ServiceRegistry.Get("Combat")
	if not combat then return 0.8 end
	local attack = combat.GetAttack(ctx.player)
	local interval = attack.interval * BASIC.speedMult
	local root: BasePart = ctx.root
	local pos = root.Position
	local targets = ctx.util.Enemies(ctx.run, pos, BASIC.range)
	if #targets == 0 then return 0.12 end
	local now = os.clock()
	if now - (s.lastSwing or 0) > interval + BASIC.reset then s.swing = 0 end
	s.lastSwing = now
	s.swing = (s.swing % BASIC.steps) + 1
	local finisher = s.swing == BASIC.steps
	local speed = BASIC.arrowSpeed[s.swing]
	local raw = attack.damage * BASIC.power * (if finisher then BASIC.finisherPower else 1)
	local thorn = thornOn(s)

	-- one gate per enemy: nearest enemy gets the gate closest to it, and so on
	local shots = {}
	local free = {}
	for i = 1, GATE.n do free[i] = true end
	for k = 1, math.min(BASIC.maxTargets, #targets) do
		local e = targets[k]
		local best, bestD = 1, math.huge
		for i = 1, GATE.n do
			if free[i] then
				local d = (gatePos(root, i) - e.root.Position).Magnitude
				if d < bestD then best, bestD = i, d end
			end
		end
		free[best] = false
		table.insert(shots, { gate = best, target = e, travel = bestD / speed })
	end

	local fxShots = {}
	for _, sh in shots do
		table.insert(fxShots, { g = sh.gate, m = sh.target.model, t = sh.travel })
	end
	ctx.util.Fx(ctx.run, Kit.id, "Volley", {
		caster = ctx.player.UserId, n = s.swing, shots = fxShots, interval = interval, thorn = thorn,
	})
	for _, sh in shots do
		task.delay(sh.travel, function()
			local model: Model = sh.target.model
			local hum = model.Parent and model:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then return end
			ctx.util.Hit(ctx.player, ctx.run, sh.target, raw, ctx.template, { basic = true })
			if thornOn(s) then
				EnemyStatus.Slow(model, "toa_thorn", THORN.slowPct, THORN.slowTime)
				bleed(ctx, model, raw * THORN.bleedPct / 100)
			end
		end)
	end
	return if finisher then interval * BASIC.finisherTime else interval
end

-- ===== skill 1: Creator of Thorn =====
local function creatorOfThorn(ctx: any): boolean
	local s, player = ctx.state, ctx.player
	s.thornUntil = os.clock() + THORN.duration
	ctx.util.Buff(player, "toa_thorn", { attackSpeed = THORN.attackSpeed }, { damage = THORN.damagePct }, THORN.duration)
	player:SetAttribute("ThornUntil", Workspace:GetServerTimeNow() + THORN.duration)
	ctx.util.Fx(ctx.run, Kit.id, "Thorn", { caster = player.UserId, duration = THORN.duration })
	local mine = s.thornUntil
	task.delay(THORN.duration, function()
		if s.thornUntil == mine and player.Parent then player:SetAttribute("ThornUntil", nil) end
	end)
	return true
end

-- ===== skill 2: Miracle =====
-- Dogs and birds are invisible anchored "decoy" parts the server moves (workspace.WeaponSummons);
-- enemies target them through EnemyController.NearestDecoy, every client draws the crimson
-- creature on top (smoothed). Fish are drawn by the clients around the players they serve.
local summonFolder: Folder? = nil
local function folder(): Folder
	local f = summonFolder
	if f and f.Parent then return f end
	local found = Workspace:FindFirstChild("WeaponSummons")
	if found and found:IsA("Folder") then
		summonFolder = found
		return found
	end
	local nf = Instance.new("Folder")
	nf.Name = "WeaponSummons"
	nf.Parent = Workspace
	summonFolder = nf
	return nf
end

type Summon = {
	part: BasePart, kind: string, owner: Player, run: any, hp: number, maxHp: number,
	untilT: number, nextAttack: number, alive: boolean, slot: number,
}
local decoys: {[any]: {Summon}} = setmetatable({}, { __mode = "k" }) :: any -- run -> its decoys

local function vanish(sm: Summon, why: string)
	if not sm.alive then return end
	sm.alive = false
	local list = decoys[sm.run]
	if list then
		local i = table.find(list, sm)
		if i then table.remove(list, i) end
	end
	sm.part:SetAttribute("Gone", why)
	task.delay(0.6, function() sm.part:Destroy() end) -- clients play the vanish burst first
end

-- Enemy AI hook: the nearest living decoy of the run within reach of `from`.
local function nearestDecoy(run: any, from: Vector3, maxDist: number)
	local list = decoys[run]
	if not list then return nil end
	local best, bestD = nil, math.min(maxDist, MIRACLE.aggro)
	for _, sm in list do
		if sm.alive then
			local p = sm.part.Position
			local d = Vector3.new(p.X - from.X, 0, p.Z - from.Z).Magnitude
			if d < bestD then best, bestD = sm, d end
		end
	end
	if not best then return nil end
	local sm: Summon = best
	return {
		root = sm.part,
		radius = 1.2,
		alive = function() return sm.alive end,
		damage = function(amount: number)
			if not sm.alive then return end
			sm.hp -= amount
			sm.part:SetAttribute("HP", math.max(0, sm.hp))
			if sm.hp <= 0 then vanish(sm, "died") end
		end,
	}
end

local function groundAt(at: Vector3, ignore: {Instance}): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(at + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position.Y
end

local function stepSummon(ctx: any, sm: Summon, dt: number)
	local owner = sm.owner
	local character = owner.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local cfg = if sm.kind == "Dog" then MIRACLE.dog else MIRACLE.bird
	local pos = sm.part.Position
	local target = ctx.util.Nearest(sm.run, pos, 90)
	local goal: Vector3
	local face: Vector3? = nil
	if target then
		local tp = target.root.Position
		local away = Vector3.new(pos.X - tp.X, 0, pos.Z - tp.Z)
		if away.Magnitude < 1e-3 then away = Vector3.new(1, 0, 0) end
		local keep = if sm.kind == "Dog" then math.max(target.root.Size.X, target.root.Size.Z) / 2 + 1.6 else cfg.reach * 0.7
		-- each summon of a pair takes its own side of the target (no stacking)
		local spread = math.rad((if sm.slot == 1 then -1 else 1) * (if sm.kind == "Dog" then 40 else 55))
		local dir = CFrame.Angles(0, spread, 0):VectorToWorldSpace(away.Unit)
		goal = tp + dir * keep
		face = tp
		local edge = (Vector3.new(tp.X - pos.X, 0, tp.Z - pos.Z)).Magnitude - math.max(target.root.Size.X, target.root.Size.Z) / 2
		local now = os.clock()
		if edge <= cfg.reach and now >= sm.nextAttack then
			sm.nextAttack = now + cfg.every
			local raw = ctx.util.Power(owner, "Ability", cfg.power, ctx.template)
			if sm.kind == "Dog" then
				ctx.util.Fx(sm.run, Kit.id, "Bite", { caster = owner.UserId, from = sm.part.Name, at = tp })
				task.delay(0.12, function() ctx.util.Hit(owner, sm.run, target, raw, ctx.template) end)
			else
				local travel = (tp - pos).Magnitude / 90
				ctx.util.Fx(sm.run, Kit.id, "Peck", { caster = owner.UserId, from = sm.part.Name, m = target.model, t = travel })
				task.delay(travel, function() ctx.util.Hit(owner, sm.run, target, raw, ctx.template) end)
			end
		end
	else
		-- no enemy: stay by the owner (dogs at the sides, birds circling above)
		local a = os.clock() * 0.9 + sm.slot * math.pi
		local side = if sm.kind == "Dog" then Vector3.new(math.cos(sm.slot * math.pi) * 4, 0, 2.5) else Vector3.new(math.cos(a) * 5, 0, math.sin(a) * 5)
		goal = hrp.Position + side
		face = goal + (goal - pos)
	end
	-- move (flat), then stick to the ground / hover height
	local flat = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
	local step = math.min(flat.Magnitude, cfg.speed * dt)
	local nextPos = if flat.Magnitude > 1e-3 then pos + flat.Unit * step else pos
	local ignore: {Instance} = { folder() }
	for _, p in sm.run.players do if p.Character then table.insert(ignore, p.Character) end end
	local gy = groundAt(nextPos, ignore)
	local h = if sm.kind == "Dog" then 2.45 else MIRACLE.bird.height + math.sin(os.clock() * 2 + sm.slot) * 0.6
	local y = if gy then gy + h else nextPos.Y
	nextPos = Vector3.new(nextPos.X, y, nextPos.Z)
	local lookAt = face or (nextPos + (nextPos - pos))
	local lf = Vector3.new(lookAt.X - nextPos.X, 0, lookAt.Z - nextPos.Z)
	sm.part.CFrame = if lf.Magnitude > 1e-3 then CFrame.lookAt(nextPos, nextPos + lf) else CFrame.new(nextPos) * sm.part.CFrame.Rotation
end

local function makeDecoy(kind: string, owner: Player, at: Vector3, slot: number, maxHp: number): BasePart
	local p = Instance.new("Part")
	p.Name = ("TOA_%s_%d_%d"):format(kind, owner.UserId, slot)
	p.Size = Vector3.new(1.6, 1.6, 2.4)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.new(at)
	p:SetAttribute("Kit", "ThornOfTheAxis")
	p:SetAttribute("Kind", kind)
	p:SetAttribute("Owner", owner.UserId)
	p:SetAttribute("MaxHP", maxHp)
	p:SetAttribute("HP", maxHp)
	p.Parent = folder()
	return p
end

-- Fish: one per player of the run (max 4), lowest HP first.
local function fishTargets(run: any): {Player}
	local list = {}
	for _, p in run.players do
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then table.insert(list, { p = p, frac = hum.Health / math.max(1, hum.MaxHealth) }) end
	end
	table.sort(list, function(a, b) return a.frac < b.frac end)
	local out = {}
	for i = 1, math.min(MIRACLE.fishCount, #list) do out[i] = list[i].p end
	return out
end

local function miracle(ctx: any): boolean
	local s, player, run = ctx.state, ctx.player, ctx.run
	-- a re-cast replaces the previous summons
	for _, sm in s.summons do vanish(sm, "expired") end
	s.summons = {}
	local maxHp = ctx.humanoid.MaxHealth
	local root: BasePart = ctx.root
	local untilT = os.clock() + MIRACLE.duration
	decoys[run] = decoys[run] or {}
	local names = {}
	local function add(kind: string, slot: number, offset: Vector3, hpPct: number)
		local at = root.CFrame:PointToWorldSpace(offset)
		local hp = maxHp * hpPct / 100
		local part = makeDecoy(kind, player, at, slot, hp)
		local sm: Summon = { part = part, kind = kind, owner = player, run = run, hp = hp, maxHp = hp,
			untilT = untilT, nextAttack = os.clock() + 0.6, alive = true, slot = slot }
		table.insert(s.summons, sm)
		table.insert(decoys[run], sm)
		table.insert(names, part.Name)
	end
	for i = 1, MIRACLE.dogs do add("Dog", i, Vector3.new(if i == 1 then -3 else 3, -1.5, -2), MIRACLE.dog.hpPct) end
	for i = 1, MIRACLE.birds do add("Bird", i, Vector3.new(if i == 1 then -3.5 else 3.5, 3.5, 1), MIRACLE.bird.hpPct) end
	local fish = fishTargets(run)
	local fishIds = {}
	for i, p in fish do fishIds[i] = p.UserId end
	ctx.util.Fx(run, Kit.id, "Miracle", { caster = player.UserId, summons = names, fish = fishIds, duration = MIRACLE.duration })
	-- fish: heal + speed for the player each one orbits
	for _, p in fish do
		ctx.util.Buff(p, "toa_fish", { walkSpeedPct = MIRACLE.fish.speedPct }, nil, MIRACLE.duration)
	end
	local token = {}
	s.miracleToken = token
	task.spawn(function()
		local lastHeal = os.clock()
		local last = os.clock()
		while s.miracleToken == token and run.active and os.clock() < untilT do
			task.wait(MIRACLE.tick)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, sm in s.summons do
				if sm.alive then
					local ok, err = pcall(stepSummon, ctx, sm, dt)
					if not ok then warn("[WeaponKits] thorn_axis summon: " .. tostring(err)) end
				end
			end
			if now - lastHeal >= 1 then
				lastHeal = now
				for _, p in fish do
					local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * MIRACLE.fish.healPct / 100)
					end
				end
			end
		end
		if s.miracleToken == token then
			for _, sm in s.summons do vanish(sm, "expired") end
			s.summons = {}
		end
	end)
	return true
end

-- ===== ultimate: Red Rain =====
local function roomBox(run: any): (CFrame?, Vector3?)
	local room = run.arenaFolder and run.arenaFolder.Parent
	if room and room:IsA("Model") then
		local ok, cf, size = pcall(function() return room:GetBoundingBox() end)
		if ok then return cf, size end
	end
	return nil, nil
end

-- movement lock for the ultimate animation (StatService leaves WalkSpeed alone while SpeedLocked)
local function lockMove(player: Player, hum: Humanoid, on: boolean)
	local character = hum.Parent
	if not character then return end
	if on then
		character:SetAttribute("SpeedLocked", true)
		character:SetAttribute("TOA_JumpPower", hum.JumpPower)
		character:SetAttribute("TOA_JumpHeight", hum.JumpHeight)
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
	else
		if character:GetAttribute("SpeedLocked") then character:SetAttribute("SpeedLocked", nil) end
		local jp, jh = character:GetAttribute("TOA_JumpPower"), character:GetAttribute("TOA_JumpHeight")
		if type(jp) == "number" then hum.JumpPower = jp end
		if type(jh) == "number" then hum.JumpHeight = jh end
		character:SetAttribute("TOA_JumpPower", nil)
		character:SetAttribute("TOA_JumpHeight", nil)
		pcall(StatService.Refresh, player)
	end
end

local function endRain(player: Player, s: any, instant: boolean?)
	local r = s.rain
	s.rain = nil
	if not r then return end
	if r.locked then
		r.locked = false
		s.busy = false
		lockMove(player, r.hum, false)
	end
	if player.Parent then player:SetAttribute("RedRainUntil", nil) end
	local hum: Humanoid? = r.hum
	if hum and hum.Parent then
		if instant then
			hum.HipHeight = r.hip
		else
			-- slow descent
			local from = hum.HipHeight
			task.spawn(function()
				local t0 = os.clock()
				while hum.Parent and os.clock() - t0 < RAIN.descend do
					local a = (os.clock() - t0) / RAIN.descend
					hum.HipHeight = from + (r.hip - from) * (1 - (1 - a) * (1 - a))
					task.wait()
				end
				if hum.Parent then hum.HipHeight = r.hip end
			end)
		end
	end
	task.delay(if instant then 0 else RAIN.descend, function()
		r.util.ClearInvulnerable(player, "toa_red_rain")
	end)
end

local function redRain(ctx: any): boolean
	local s, player, run = ctx.state, ctx.player, ctx.run
	local hum: Humanoid = ctx.humanoid
	if s.rain then return false end
	local cut = RAIN.cutscene
	local r = { hum = hum, hip = hum.HipHeight, util = ctx.util, locked = true }
	s.rain = r
	-- the ultimate animation: everyone frozen, the caster locked in place and untouchable
	s.busy = true
	EnemyStatus.FreezeRun(run, cut)
	ctx.util.SetInvulnerable(player, "toa_red_rain", nil)
	lockMove(player, hum, true)
	ctx.root.AssemblyLinearVelocity = Vector3.zero
	local cf, size = roomBox(run)
	player:SetAttribute("RedRainUntil", Workspace:GetServerTimeNow() + cut + RAIN.duration)
	ctx.util.Fx(run, Kit.id, "RedRain", {
		caster = player.UserId, cutscene = cut, rise = cut, liftFrom = RAIN.liftFrom, liftTo = RAIN.liftTo,
		duration = RAIN.duration, descend = RAIN.descend, height = RAIN.height,
		roomCf = cf, roomSize = size, center = run.arenaCenter,
	})
	-- lift off (HipHeight: afterwards the character walks normally, just ~12 studs up)
	task.spawn(function()
		local t0 = os.clock()
		while s.rain == r and hum.Parent and os.clock() - t0 < RAIN.liftTo do
			local a = math.clamp((os.clock() - t0 - RAIN.liftFrom) / (RAIN.liftTo - RAIN.liftFrom), 0, 1)
			hum.HipHeight = r.hip + RAIN.height * (a * a * (3 - 2 * a))
			task.wait()
		end
		if s.rain == r and hum.Parent then hum.HipHeight = r.hip + RAIN.height end
	end)
	-- the animation is over: free in the air, the rain starts
	task.delay(cut, function()
		if s.rain ~= r then return end
		r.locked = false
		s.busy = false
		lockMove(player, hum, false)
		local stopAt = os.clock() + RAIN.duration
		while s.rain == r and run.active and os.clock() < stopAt do
			local raw = ctx.util.Power(player, "Ultimate", RAIN.power, ctx.template)
			for _, e in ctx.util.Enemies(run, ctx.root.Position) do
				ctx.util.Hit(player, run, e, raw, ctx.template)
			end
			task.wait(RAIN.tick)
		end
		if s.rain == r then
			endRain(player, s)
			if run.active then ctx.util.Fx(run, Kit.id, "RedRainEnd", { caster = player.UserId, descend = RAIN.descend }) end
		end
	end)
	-- died meanwhile: put everything back at once
	local conn: RBXScriptConnection
	conn = hum.Died:Connect(function()
		conn:Disconnect()
		if s.rain == r then endRain(player, s, true) end
	end)
	return true
end

function Kit.Cast(ctx: any, slot: string): boolean
	if slot == "1" then return creatorOfThorn(ctx) end
	if slot == "2" then return miracle(ctx) end
	if slot == "U" then return redRain(ctx) end
	return false
end

function Kit.EndRun(player: Player, s: any)
	s.thornUntil = 0
	s.miracleToken = nil
	for _, sm in s.summons or {} do vanish(sm, "expired") end
	s.summons = {}
	endRain(player, s, true)
	if player.Parent then
		player:SetAttribute("ThornUntil", nil)
		player:SetAttribute("RedRainUntil", nil)
	end
end

-- enemies look for decoys through EnemyController (several kits may add finders)
EnemyController.DecoyFinders = EnemyController.DecoyFinders or {}
EnemyController.DecoyFinders[Kit.id] = nearestDecoy

local _ = Players
return Kit
