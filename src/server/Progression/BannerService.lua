--!strict
-- BannerService
-- The banner logic SummonService uses (reworked 2026-10-08, weapons first):
--   Normal Banner     "main": WEAPONS ONLY -- every set's weapon, always in
--                     the pool; rarity weights from RarityConfig + luck;
--                     pity: a Legendary+ within SummonConfig.PityThreshold
--   set unlocks       owning a set's weapon (ever -- ProgressionData
--                     doc.obtained, so auto-sold and traded weapons count
--                     too) unlocks that set for the Selection Banner
--   Selection Banner  "selection": choose ONE unlocked Legendary+ set
--                     (doc.selectedSet). One pull = the set's grand prize (a
--                     random non-weapon piece) at BannerConfig.Selection
--                     .prizes[tier].chance, otherwise a Common-Epic piece of
--                     any set. Price per pull by the set's tier. No pity.
--   costs             Normal 10 Tokens per pull, VIP -20% on both, up to 10
--                     per summon (50 with the More Summon gamepass)
--   odds              Describe sends every banner's exact odds (each rarity,
--                     each item, the pity pull) for the window's Odds Details,
--                     built from the same tables the rolls use

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GearRegistry = require(ReplicatedStorage.GearSystem.GearRegistry)
local RarityConfig = require(ReplicatedStorage.GearSystem.RarityConfig)
local SetRegistry = require(ReplicatedStorage.GearSystem.SetRegistry)
local BannerConfig = require(ReplicatedStorage.Progression.BannerConfig)
local SummonConfig = require(ReplicatedStorage.GearSystem.SummonConfig)
local ProgressionData = require(script.Parent.ProgressionData)
local RemoteRouter = require(script.Parent.RemoteRouter)
local LuckService = require(script.Parent.LuckService)

local BannerService = {}

BannerService.HasPass = function(_player: Player, _key: string): boolean return false end -- MonetizationService

local PRIZE = "Prize" -- the Selection Banner's grand-prize outcome in its weight table
local SEL = BannerConfig.Selection

-- ===== catalog tables (built once: the catalog doesn't change at runtime) =====
local normalPool: {[string]: {string}}? = nil
local setInfo: {[string]: { id: string, name: string, rarity: string, weapon: string?, pieces: {string} }} = {}
local fillerPool: {[string]: {string}} = {} -- [rarity] = every piece of every set of that rarity

local function setRarity(set: any): string?
	for _, id in set.gearIds do
		local t = GearRegistry.Get(id)
		if t then return t.rarity end
	end
	return nil
end

local function buildCatalog()
	if normalPool then return end
	normalPool = BannerConfig.BuildPool(GearRegistry, RarityConfig, SetRegistry)
	for key, set in SetRegistry.GetAll() do
		local setId = if type(set.id) == "string" then set.id else tostring(key) -- GetAll is keyed by number
		local rarity = setRarity(set)
		local tier = rarity and RarityConfig.GetTier(rarity)
		if rarity and tier and tier.weight > 0 then
			local info = { id = setId, name = set.name or setId, rarity = rarity, weapon = nil :: string?, pieces = {} }
			for _, id in set.gearIds do
				local t = GearRegistry.Get(id)
				if t and not t.adminOnly then
					if t.category == "Weapon" then info.weapon = id end
					if not (SEL.prizeExcludesWeapon and t.category == "Weapon") then table.insert(info.pieces, id) end
					if table.find(SEL.fillerRarities, t.rarity) then
						fillerPool[t.rarity] = fillerPool[t.rarity] or {}
						table.insert(fillerPool[t.rarity], id)
					end
				end
			end
			table.sort(info.pieces)
			setInfo[setId] = info
		end
	end
	for _, ids in fillerPool do table.sort(ids) end
end

function BannerService.CurrentPool(): {[string]: {string}}
	buildCatalog()
	return normalPool :: {[string]: {string}}
end

function BannerService.SetInfo(setId: string)
	buildCatalog()
	return setInfo[setId]
end

function BannerService.MaxPulls(player: Player): number
	return if BannerService.HasPass(player, "MoreSummon") then BannerConfig.MoreSummonPulls else 10
end

function BannerService.PullOptions(player: Player): {number}
	local list = table.clone(BannerConfig.PullOptions)
	if BannerService.HasPass(player, "MoreSummon") then table.insert(list, BannerConfig.MoreSummonPulls) end
	return list
end

-- ===== set unlocks + the chosen set =====
function BannerService.IsUnlocked(player: Player, setId: string): boolean
	local info = BannerService.SetInfo(setId)
	local doc = ProgressionData.Get(player)
	return info ~= nil and info.weapon ~= nil and doc ~= nil and doc.obtained[info.weapon] == true
end

-- Every set this player has unlocked, as setIds (rarest first, then by name).
function BannerService.UnlockedSets(player: Player): {string}
	buildCatalog()
	local out = {}
	for setId in setInfo do
		if BannerService.IsUnlocked(player, setId) then table.insert(out, setId) end
	end
	table.sort(out, function(a, b)
		local ia, ib = setInfo[a], setInfo[b]
		local ra, rb = table.find(RarityConfig.Order, ia.rarity) or 0, table.find(RarityConfig.Order, ib.rarity) or 0
		if ra ~= rb then return ra > rb end
		return ia.name < ib.name
	end)
	return out
end

-- The chosen set, if it's still valid (unlocked + a selectable tier).
function BannerService.SelectedSet(player: Player): string?
	local doc = ProgressionData.Get(player)
	local setId = doc and doc.selectedSet
	if type(setId) ~= "string" then return nil end
	local info = BannerService.SetInfo(setId)
	if not info or not BannerConfig.IsSelectableRarity(info.rarity) or not BannerService.IsUnlocked(player, setId) then return nil end
	return setId
end

function BannerService.CostPerPull(player: Player, bannerId: string): number?
	local cost: number
	if bannerId == SEL.id then
		local setId = BannerService.SelectedSet(player)
		local prize = setId and SEL.prizes[setInfo[setId].rarity]
		if not prize then return nil end
		cost = prize.cost
	else
		cost = BannerConfig.TokensPerPull
	end
	if BannerService.HasPass(player, "VIP") then cost *= (1 - BannerConfig.VipDiscount) end
	return cost
end

function BannerService.Cost(player: Player, bannerId: string, count: number): number?
	local per = BannerService.CostPerPull(player, bannerId)
	return if per then math.floor(per * count + 0.5) else nil
end

-- ===== Normal Banner rolls =====
-- Rarities the Normal Banner can roll (weight > 0 and weapons exist) with
-- their weights, in RarityConfig order; `only` limits them (the pity pull).
local function rarityWeights(only: {[string]: boolean}?): ({[string]: number}, {string})
	local pool = BannerService.CurrentPool()
	local weights, order = {}, {}
	for _, name in RarityConfig.Order do
		local tier = RarityConfig.GetTier(name)
		if tier and tier.weight > 0 and pool[name] and #pool[name] > 0 and (not only or only[name]) then
			weights[name] = tier.weight
			table.insert(order, name)
		end
	end
	return weights, order
end

-- Rarity roll with luck.
function BannerService.RollRarity(player: Player, mult: number?): string?
	local weights, order = rarityWeights()
	return LuckService.RollWeighted(weights, mult or LuckService.Multiplier(player), order)
end

-- Normal Banner pity pull: a Legendary or better by base weight (luck
-- doesn't apply).
function BannerService.RollPityRarity(): string?
	local weights, order = rarityWeights(SummonConfig.PityRarities)
	return LuckService.RollWeighted(weights, 1, order)
end

-- Items a Normal Banner pull of this rarity can give (each equally likely).
function BannerService.ItemsFor(_player: Player, _bannerId: string, rarity: string): {string}
	return BannerService.CurrentPool()[rarity] or {}
end

function BannerService.PickItem(player: Player, bannerId: string, rarity: string): string?
	local list = BannerService.ItemsFor(player, bannerId, rarity)
	return if #list > 0 then list[math.random(1, #list)] else nil
end

-- ===== Selection Banner rolls =====
-- Weight table of one Selection pull for a set: the prize at exactly its
-- chance, the filler rarities sharing the rest by their RarityConfig weights.
local function selectionWeights(setId: string): ({[string]: number}, {string})
	buildCatalog()
	local info = setInfo[setId]
	local prize = SEL.prizes[info.rarity]
	local fillTotal = 0
	for _, r in SEL.fillerRarities do
		local tier = RarityConfig.GetTier(r)
		if tier and fillerPool[r] and #fillerPool[r] > 0 then fillTotal += tier.weight end
	end
	local weights: {[string]: number} = {}
	local order: {string} = {}
	for _, r in SEL.fillerRarities do
		local tier = RarityConfig.GetTier(r)
		if tier and fillerPool[r] and #fillerPool[r] > 0 then
			weights[r] = (1 - prize.chance) * tier.weight / fillTotal
			table.insert(order, r)
		end
	end
	weights[PRIZE] = prize.chance
	table.insert(order, PRIZE)
	return weights, order
end

-- One Selection pull: (gearId, rarity, isPrize). Luck multiplies the prize
-- and the rarer filler rarities (Common absorbs it, like every summon).
function BannerService.RollSelection(player: Player, mult: number, forcedRarity: string?): (string?, string?, boolean)
	local setId = BannerService.SelectedSet(player)
	if not setId then return nil, nil, false end
	local info = setInfo[setId]
	local outcome
	if forcedRarity then
		-- admin /forcepull: the set's tier gives the prize, a filler tier its filler
		outcome = if forcedRarity == info.rarity then PRIZE elseif fillerPool[forcedRarity] then forcedRarity else nil
	end
	if not outcome then
		local weights, order = selectionWeights(setId)
		outcome = LuckService.RollWeighted(weights, mult, order)
	end
	if outcome == PRIZE then
		if #info.pieces == 0 then return nil, nil, false end
		return info.pieces[math.random(1, #info.pieces)], info.rarity, true
	end
	local list = outcome and fillerPool[outcome]
	if not list or #list == 0 then return nil, nil, false end
	return list[math.random(1, #list)], outcome, false
end

-- ===== odds (paid random items must show them before buying) =====
-- Exact odds of ONE pull per rarity, plus each item's share:
-- { rarity, pct, items, each, prize? }, in RarityConfig order (prize last).
local function oddsRows(weights: {[string]: number}, order: {string}, mult: number, itemsFor: (string) -> {string}, rarityOf: (string) -> string)
	local pct = LuckService.Odds(weights, mult)
	local rows = {}
	for _, key in order do
		local items = itemsFor(key)
		local p = pct[key] or 0
		table.insert(rows, { rarity = rarityOf(key), pct = p, items = items, each = if #items > 0 then p / #items else 0, prize = key == PRIZE or nil })
	end
	return rows
end

local function same(key: string): string return key end

-- Everything the window's Odds Details shows for one banner.
function BannerService.Odds(player: Player, bannerId: string, mult: number, pityPulls: number?)
	if bannerId == SEL.id then
		local setId = BannerService.SelectedSet(player)
		if not setId then return { luck = mult, rarities = {} } end
		local info = setInfo[setId]
		local weights, order = selectionWeights(setId)
		return {
			luck = mult,
			setName = info.name,
			rarities = oddsRows(weights, order, mult,
				function(key) return if key == PRIZE then info.pieces else fillerPool[key] or {} end,
				function(key) return if key == PRIZE then info.rarity else key end),
		}
	end
	local weights, order = rarityWeights()
	local pityWeights, pityOrder = rarityWeights(SummonConfig.PityRarities)
	local pool = BannerService.CurrentPool()
	local function items(r: string) return pool[r] or {} end
	return {
		luck = mult,
		rarities = oddsRows(weights, order, mult, items, same),
		pity = { pulls = pityPulls or SummonConfig.PityThreshold, rarities = oddsRows(pityWeights, pityOrder, 1, items, same) },
	}
end

-- One row per Legendary+ set for the window's set picker.
local function setRows(player: Player)
	buildCatalog()
	local doc = ProgressionData.Get(player)
	local owned = doc and doc.obtained or {}
	local rows = {}
	for setId, info in setInfo do
		local prize = SEL.prizes[info.rarity]
		if prize then
			local have = 0
			for _, id in info.pieces do if owned[id] then have += 1 end end
			table.insert(rows, {
				id = setId, name = info.name, rarity = info.rarity, weapon = info.weapon,
				unlocked = BannerService.IsUnlocked(player, setId), pieces = info.pieces, owned = have,
				chance = prize.chance * 100, cost = prize.cost,
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.unlocked ~= b.unlocked then return a.unlocked end
		local ra, rb = table.find(RarityConfig.Order, a.rarity) or 0, table.find(RarityConfig.Order, b.rarity) or 0
		if ra ~= rb then return ra > rb end
		return a.name < b.name
	end)
	return rows
end

-- Banner list for the summon window.
function BannerService.Describe(player: Player, mainPity: number, mainPityThreshold: number)
	local luck = LuckService.GetBreakdown(player)
	local selectedSet = BannerService.SelectedSet(player)
	return {
		banners = {
			{
				bannerId = BannerConfig.Normal.id, kind = "normal", name = BannerConfig.Normal.name,
				featured = BannerService.CurrentPool(), pityCount = mainPity, pityThreshold = mainPityThreshold,
				costPerPull = BannerService.CostPerPull(player, BannerConfig.Normal.id),
				odds = BannerService.Odds(player, BannerConfig.Normal.id, luck.multiplier, mainPityThreshold),
			},
			{
				bannerId = SEL.id, kind = "selection", name = SEL.name,
				selectedSet = selectedSet, sets = setRows(player),
				costPerPull = BannerService.CostPerPull(player, SEL.id),
				odds = BannerService.Odds(player, SEL.id, luck.multiplier),
			},
		},
		pullOptions = BannerService.PullOptions(player),
		vip = BannerService.HasPass(player, "VIP"),
		moreSummon = BannerService.HasPass(player, "MoreSummon"),
		luck = luck.multiplier,
	}
end

function BannerService.Init()
	RemoteRouter.Handle("Summon.SelectSet", function(player, payload)
		if type(payload) ~= "table" or type(payload.setId) ~= "string" then return RemoteRouter.Fail("bad request") end
		if not ProgressionData.IsReady(player) then return RemoteRouter.Fail("Still loading") end
		local info = BannerService.SetInfo(payload.setId)
		if not info or not BannerConfig.IsSelectableRarity(info.rarity) then return RemoteRouter.Fail("Only Legendary or better sets can be chosen") end
		if not BannerService.IsUnlocked(player, payload.setId) then return RemoteRouter.Fail("Pull this set's weapon on the Normal Banner to unlock it") end
		local doc = ProgressionData.Get(player)
		doc.selectedSet = payload.setId
		ProgressionData.MarkDirty(player)
		return { selectedSet = payload.setId }
	end, 0.5)

	local _ = Players
end

return BannerService
