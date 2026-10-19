--!strict
-- WeaponKitService
-- Location: ServerScriptService.WeaponKits.WeaponKitService (ModuleScript, started by
-- Progression.ProgressionBoot)
-- Signature weapon kits (the remade Superior weapons). A weapon whose gearId
-- has a module in ./Kits replaces the generic weapon-type kit with its own:
--   basic attack   AutoCombatService asks Basic(player) for every swing
--   skills 1 / 2   ability slots 1 and 2 (default keys E / R)
--   ultimate       slot "U" (key F): the weapon's own -- no set collection needed
--   hooks          OnKill (passives), OnDash (the dash key, Q), StatMods (StatService
--                  source "WeaponKit"), EndRun (clean-up)
-- Per-run state ("until the gamemode ends") is dropped as soon as the player's
-- run changes or ends (RunRegistry run / player attribute InRun).
-- CombatService, AutoCombatService and DodgeService call into this module;
-- kits never require those back (KitUtil reaches CombatService via ServiceRegistry).
--
-- Kit module contract (see Kits/SevenVerities):
--   id, gearId, displayName, weaponType, passive = { name, description }?
--   slots = { ["1"] = def, ["2"] = def, U = def }   def = { id, name, description, cooldown,
--           power?, hits?, kind? ("Ability"/"Ultimate") }
--   NewState(state)?, Basic(ctx) -> seconds, Cast(ctx, slot) -> boolean (false = not used,
--   no cooldown), OnKill(ctx, model, template)?, OnDash(ctx) -> boolean (true = handled),
--   StatMods(ctx) -> (flat, pct)?, EndRun(player, state)?
-- ctx = { player, character, humanoid, root, run, template, kit, state, util, service }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GearRegistry = require(ReplicatedStorage.GearSystem.GearRegistry)
local CombatScalingConfig = require(ReplicatedStorage.Progression.CombatScalingConfig)
local InventoryManager = require(ServerScriptService.GearSystem:WaitForChild("InventoryManager"))
local RunRegistry = require(ServerScriptService.DungeonSystem:WaitForChild("RunRegistry"))
local EnemyController = require(ServerScriptService.DungeonSystem:WaitForChild("EnemyController"))
local DodgeService = require(ServerScriptService.DungeonSystem:WaitForChild("DodgeService"))
local RemoteRouter = require(ServerScriptService.Progression:WaitForChild("RemoteRouter"))
local StatService = require(ServerScriptService.Progression:WaitForChild("StatService"))
local KitUtil = require(script.Parent.KitUtil)

local WeaponKitService = {}

-- ===== kit registry =====
local byGear: {[string]: any} = {}
local byId: {[string]: any} = {}
for _, m in script.Parent:WaitForChild("Kits"):GetChildren() do
	if m:IsA("ModuleScript") then
		local ok, kit = pcall(require, m)
		if ok and type(kit) == "table" and kit.gearId and kit.id then
			byGear[kit.gearId] = kit
			byId[kit.id] = kit
		else
			warn("[WeaponKits] " .. m.Name .. " failed to load: " .. tostring(kit))
		end
	end
end

function WeaponKitService.KitFor(player: Player): (any?, any?)
	local inst = InventoryManager.GetEquippedItem(player, "Weapon")
	local template = inst and GearRegistry.Get(inst.gearId)
	return template and byGear[template.id], template
end

function WeaponKitService.Owns(player: Player): boolean
	return (WeaponKitService.KitFor(player)) ~= nil
end

-- ===== per-run state =====
type Root = { run: any, kits: {[string]: {[string]: any}}, cd: {[string]: number} }
local roots: {[Player]: Root} = {}

local function root(player: Player): Root
	local run = RunRegistry.GetRun(player)
	local r = roots[player]
	if not r or r.run ~= run then
		r = { run = run, kits = {}, cd = {} }
		roots[player] = r
	end
	return r
end

function WeaponKitService.State(player: Player, kit: any): {[string]: any}
	local r = root(player)
	local s = r.kits[kit.id]
	if not s then
		s = {}
		r.kits[kit.id] = s
		if kit.NewState then kit.NewState(s) end
	end
	return s
end

function WeaponKitService.Context(player: Player, kit: any, template: any)
	local character = player.Character
	return {
		player = player,
		character = character,
		humanoid = character and character:FindFirstChildOfClass("Humanoid"),
		root = character and character:FindFirstChild("HumanoidRootPart"),
		run = RunRegistry.GetRun(player),
		template = template,
		kit = kit,
		state = WeaponKitService.State(player, kit),
		util = KitUtil,
		service = WeaponKitService,
	}
end

-- ===== cooldowns =====
local function cdr(player: Player): number
	return math.clamp(StatService.GetStats(player).cooldownReduction or 0, 0, 90) / 100
end

function WeaponKitService.SetCooldown(player: Player, slot: string, seconds: number)
	root(player).cd[slot] = os.clock() + seconds
	RemoteRouter.Push(player, "Cooldown", { slot = slot, duration = seconds })
end

function WeaponKitService.Ready(player: Player, slot: string): boolean
	return (root(player).cd[slot] or 0) <= os.clock()
end

-- The tower's floor refresh (CombatService.ResetCooldowns calls this too).
function WeaponKitService.ResetCooldowns(player: Player)
	local r = roots[player]
	if r then r.cd = {} end
end

-- ===== entry points =====
function WeaponKitService.Cast(player: Player, slot: any)
	local kit, template = WeaponKitService.KitFor(player)
	if not kit or not kit.Cast then return end
	local key = tostring(slot)
	local def = kit.slots[key]
	if not def then return end
	local run = RunRegistry.GetRun(player)
	if not run or not run.active then return end
	local ctx = WeaponKitService.Context(player, kit, template)
	if not ctx.root or not ctx.humanoid or ctx.humanoid.Health <= 0 then return end
	if not WeaponKitService.Ready(player, key) then return end
	if ctx.state.busy then return end -- mid-cutscene
	local ok, used = pcall(kit.Cast, ctx, key)
	if not ok then
		warn("[WeaponKits] " .. kit.id .. " slot " .. key .. ": " .. tostring(used))
		return
	end
	if used ~= false then
		WeaponKitService.SetCooldown(player, key, def.cooldown * (1 - cdr(player)))
	end
end

-- One basic attack. Returns the seconds until the next one, or nil when the
-- equipped weapon has no signature kit (AutoCombatService then does its own).
function WeaponKitService.Basic(player: Player): number?
	local kit, template = WeaponKitService.KitFor(player)
	if not kit or not kit.Basic then return nil end
	local ctx = WeaponKitService.Context(player, kit, template)
	if not ctx.run or not ctx.root then return 0.5 end
	local ok, wait = pcall(kit.Basic, ctx)
	if not ok then
		warn("[WeaponKits] " .. kit.id .. " basic: " .. tostring(wait))
		return 0.8
	end
	return if type(wait) == "number" then wait else 0.8
end

-- The dash key (DodgeService). True when the kit turned the dash into its own move.
function WeaponKitService.OnDash(player: Player): boolean
	local kit, template = WeaponKitService.KitFor(player)
	if not kit or not kit.OnDash then return false end
	local ctx = WeaponKitService.Context(player, kit, template)
	if not ctx.run or not ctx.root then return false end
	local ok, handled = pcall(kit.OnDash, ctx)
	if not ok then warn("[WeaponKits] " .. kit.id .. " dash: " .. tostring(handled)) return false end
	return handled == true
end

-- Kit info for the ability bar / Profile (same shape as CombatService.GetKit).
function WeaponKitService.Describe(player: Player): any?
	local kit, template = WeaponKitService.KitFor(player)
	if not kit then return nil end
	local c = cdr(player)
	local ability = CombatScalingConfig.AbilityElement(template)
	local function entry(key: string, def: any)
		local kind = def.kind or (if key == "U" then "Ultimate" else "Ability")
		return {
			slot = if key == "U" then "U" else tonumber(key), id = def.id, name = def.name, description = def.description,
			cooldown = def.cooldown * (1 - c), baseCooldown = def.cooldown,
			powerPct = math.floor(CombatScalingConfig.Percent(kind, template.rarity) * (def.power or 1) + 0.5),
			hits = def.hits or 1,
			damagePerHit = math.floor(KitUtil.Power(player, kind, def.power or 1, template) + 0.5),
			element = ability,
		}
	end
	local list = {}
	if kit.slots["1"] then list[1] = entry("1", kit.slots["1"]) end
	if kit.slots["2"] then list[2] = entry("2", kit.slots["2"]) end
	local combat = require(ServerScriptService.ServiceRegistry).Get("Combat")
	return {
		weaponName = kit.displayName or template.name, weaponType = kit.weaponType or "Signature", rarity = template.rarity,
		scaling = CombatScalingConfig.ScalingFor(template),
		basicPct = CombatScalingConfig.Percent("Basic", template.rarity),
		basicDamage = math.floor(KitUtil.Power(player, "Basic", 1, template) + 0.5),
		element = template.element, abilityElement = ability, damageType = template.damageType,
		abilities = list, ultimate = if kit.slots.U then entry("U", kit.slots.U) else nil,
		interval = if combat then combat.GetAttack(player).interval else 0.8,
		signature = true, kitId = kit.id, passive = kit.passive,
	}
end

-- Run over (left, died out, finished): let the kit tidy up, drop the state.
function WeaponKitService.EndRun(player: Player)
	local r = roots[player]
	roots[player] = nil
	if r then
		for kitId, s in r.kits do
			local kit = byId[kitId]
			if kit and kit.EndRun then pcall(kit.EndRun, player, s) end
		end
	end
	if player.Parent then pcall(StatService.Refresh, player) end
end

function WeaponKitService.Init()
	-- run-long stat stacks + kit stat changes (not a buff: the floor refresh keeps them)
	StatService.AddSource("WeaponKit", 70, function(player: Player)
		local kit, template = WeaponKitService.KitFor(player)
		if not kit or not kit.StatMods or not RunRegistry.IsInRun(player) then return nil, nil end
		return kit.StatMods(WeaponKitService.Context(player, kit, template))
	end)

	-- kills (with the enemy model, for effects that start where it died)
	local previous = EnemyController.OnEnemyKilled
	EnemyController.OnEnemyKilled = function(player: Player, model: Model, template: any, run: any)
		if previous then previous(player, model, template, run) end
		local kit, weapon = WeaponKitService.KitFor(player)
		if kit and kit.OnKill and RunRegistry.GetRun(player) == run then
			local ok, err = pcall(kit.OnKill, WeaponKitService.Context(player, kit, weapon), model, template)
			if not ok then warn("[WeaponKits] " .. kit.id .. " kill: " .. tostring(err)) end
		end
	end

	-- the dash key
	DodgeService.KitHook = WeaponKitService.OnDash

	local function watch(player: Player)
		player:GetAttributeChangedSignal("InRun"):Connect(function()
			if player:GetAttribute("InRun") == nil then WeaponKitService.EndRun(player) end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do watch(p) end
	Players.PlayerRemoving:Connect(function(p)
		WeaponKitService.EndRun(p)
		KitUtil.ForgetPlayer(p)
	end)

	local names = {}
	for id in byId do table.insert(names, id) end
	print("[WeaponKits] ready: " .. (if #names > 0 then table.concat(names, ", ") else "no kits"))
end

return WeaponKitService
