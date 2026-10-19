--!strict
-- KitUtil
-- Location: ServerScriptService.WeaponKits.KitUtil (ModuleScript)
-- Shared helpers for the signature weapon kits:
--   targets   Enemies / Nearest / Cone / Line / Circle (living, targetable, nearest first)
--   damage    Power(player, kind, power, template) -- the weapon's scaling x the preset %
--             (CombatScalingConfig, same numbers as the generic kits), and Hit() --
--             one hit through CombatService.DealHit (crit, passives, elemental, defenses,
--             damage numbers): there is still only one damage pipeline
--   self      Buff (StatService.AddBuff), SetInvulnerable / ClearInvulnerable
--             (character attribute "Invulnerable", read by DodgeService.IsInvulnerable,
--             which every enemy attack checks)
--   fx        Fx(run, kit, kind, data) -> every client of the run (channel "WFx",
--             drawn by StarterPlayerScripts.WeaponFxClient)
-- CombatService is looked up through ServiceRegistry when needed: it requires
-- WeaponKitService, so requiring it here would be circular.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ServiceRegistry = require(ServerScriptService.ServiceRegistry)
local RemoteRouter = require(ServerScriptService.Progression:WaitForChild("RemoteRouter"))
local StatService = require(ServerScriptService.Progression:WaitForChild("StatService"))
local CombatScalingConfig = require(ReplicatedStorage.Progression.CombatScalingConfig)

local KitUtil = {}

export type Target = { model: Model, root: BasePart, dist: number }

function KitUtil.Flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

-- Half the enemy's footprint, so big enemies count as soon as their edge is in reach.
local function radiusOf(root: BasePart): number
	return math.max(root.Size.X, root.Size.Z) / 2
end

-- Every living, targetable enemy of the run within `range` of `from`, nearest first.
function KitUtil.Enemies(run: any, from: Vector3, range: number?): {Target}
	local out: {Target} = {}
	local r = range or math.huge
	for _, child in run.arenaFolder:GetChildren() do
		if child:IsA("Model") and not child:GetAttribute("Spawning") then
			local hum = child:FindFirstChildOfClass("Humanoid")
			local root = child.PrimaryPart
			if hum and root and hum.Health > 0 then
				local d = (root.Position - from).Magnitude
				if d - radiusOf(root) <= r then table.insert(out, { model = child, root = root, dist = d }) end
			end
		end
	end
	table.sort(out, function(a, b) return a.dist < b.dist end)
	return out
end

function KitUtil.Nearest(run: any, from: Vector3, range: number?): Target?
	return KitUtil.Enemies(run, from, range)[1]
end

function KitUtil.Circle(run: any, center: Vector3, radius: number): {Target}
	return KitUtil.Enemies(run, center, radius)
end

-- Flat cone in front of `origin` (angle = full width in degrees). Enemies
-- hugging the player (within `hug` studs) always count, like a real swing.
function KitUtil.Cone(run: any, origin: Vector3, dir: Vector3, range: number, angle: number, hug: number?): {Target}
	local look = KitUtil.Flat(dir)
	local cosHalf = math.cos(math.rad(angle / 2))
	local out: {Target} = {}
	for _, e in KitUtil.Enemies(run, origin, range) do
		local rel = e.root.Position - origin
		local flatRel = Vector3.new(rel.X, 0, rel.Z)
		if flatRel.Magnitude < (hug or 3) + radiusOf(e.root) or KitUtil.Flat(flatRel):Dot(look) >= cosHalf then
			table.insert(out, e)
		end
	end
	return out
end

-- Flat rectangle from `origin` along `dir`.
function KitUtil.Line(run: any, origin: Vector3, dir: Vector3, length: number, width: number): {Target}
	local look = KitUtil.Flat(dir)
	local half = width / 2
	local out: {Target} = {}
	for _, e in KitUtil.Enemies(run, origin, length) do
		local rel = e.root.Position - origin
		local along = rel:Dot(look)
		local side = (Vector3.new(rel.X, 0, rel.Z) - look * along).Magnitude - radiusOf(e.root)
		if along >= -radiusOf(e.root) and along <= length and side <= half then table.insert(out, e) end
	end
	return out
end

-- Damage per hit before crit: the weapon's scaling stats x the preset % for
-- `kind` ("Basic" | "Ability" | "Ultimate") x `power`.
function KitUtil.Power(player: Player, kind: string, power: number, template: any): number
	local stats = StatService.GetStats(player)
	local sum = 0
	for stat, w in CombatScalingConfig.ScalingFor(template) do sum += (stats[stat] or 0) * w end
	if sum <= 0 then sum = CombatScalingConfig.UnarmedDamage end
	return sum * CombatScalingConfig.Percent(kind, template.rarity) / 100 * power
end

-- One hit through the shared pipeline. Basic attacks carry the weapon's own
-- element, skills its pair element (the game's two-elements-per-kit rule).
function KitUtil.Hit(player: Player, run: any, target: any, raw: number, template: any, opts: {basic: boolean?, element: string?}?)
	local combat = ServiceRegistry.Get("Combat")
	if not combat then return end
	local model: Model = if typeof(target) == "Instance" then target else target.model
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local o = opts or {}
	local element = o.element or (if o.basic then template.element else CombatScalingConfig.AbilityElement(template))
	combat.DealHit(player, model, run, raw, element, template.damageType, o.basic == true)
end

-- ===== the caster =====
function KitUtil.Buff(player: Player, id: string, flat: {[string]: number}?, pct: {[string]: number}?, seconds: number)
	StatService.AddBuff(player, id, flat, pct, seconds)
end

local invuln: {[Player]: {[string]: number}} = {}

local function refreshInvuln(player: Player)
	local now = os.clock()
	local on = false
	local list = invuln[player]
	if list then
		for id, t in list do
			if t > now then on = true else list[id] = nil end
		end
	end
	local character = player.Character
	if character then character:SetAttribute("Invulnerable", if on then true else nil) end
end

-- I-frames from one source; overlapping sources don't cancel each other.
-- seconds = nil keeps it until ClearInvulnerable(player, id).
function KitUtil.SetInvulnerable(player: Player, id: string, seconds: number?)
	invuln[player] = invuln[player] or {}
	invuln[player][id] = if seconds then os.clock() + seconds else math.huge
	refreshInvuln(player)
	if seconds then task.delay(seconds + 0.02, function() refreshInvuln(player) end) end
end

function KitUtil.ClearInvulnerable(player: Player, id: string)
	local list = invuln[player]
	if list then list[id] = nil end
	refreshInvuln(player)
end

function KitUtil.ForgetPlayer(player: Player)
	invuln[player] = nil
end

-- ===== effects =====
function KitUtil.Fx(run: any, kit: string, kind: string, data: {[string]: any})
	data.kit = kit
	data.kind = kind
	for _, p in run.players do RemoteRouter.Push(p, "WFx", data) end
end

-- Ground height under a point (ignores characters, enemies and effects).
function KitUtil.GroundY(at: Vector3, ignore: {Instance}): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(at + Vector3.new(0, 12, 0), Vector3.new(0, -60, 0), params)
	return hit and hit.Position.Y
end

return KitUtil
