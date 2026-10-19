--!strict
-- BannerConfig
-- The two summon banners. Reworked 2026-10-08 (weapons first):
--   * Normal Banner  -- WEAPONS ONLY: every set's weapon, all of them in the
--     pool all the time (no hourly rotation any more). Pulling a set's weapon
--     UNLOCKS that set for the Selection Banner.
--   * Selection Banner -- you choose ONE unlocked Legendary+ set. Its pieces
--     are the banner's grand prize (chance per pull below, by the set's tier);
--     every other pull is a Common-Epic piece from any set. No other
--     Legendary+ gear can drop there. Price per pull by the set's tier.
-- Shared by server and client (the window shows these numbers).

local BannerConfig = {}

-- ===== NORMAL BANNER (open from the start) =====
BannerConfig.Normal = {
	id = "main", -- same id as the old Main Banner, so its pity carries over
	name = "Normal Banner",
	-- Only these categories can drop, and only items that belong to a set
	-- (the 19 old set-less items stay out of summons).
	categories = { Weapon = true },
}

-- ===== SELECTION BANNER (choose one unlocked set) =====
BannerConfig.Selection = {
	id = "selection",
	name = "Selection Banner",
	-- Set tiers that can be chosen, with the grand-prize chance of ONE pull
	-- (0.10 = 10%) and the Token price per pull. Luck multiplies the prize
	-- chance like every other rare outcome.
	prizes = {
		Legendary = { chance = 0.10, cost = 50 },
		Mythic = { chance = 0.02, cost = 200 },
		Superior = { chance = 0.00001, cost = 1000 }, -- 0.001%
	},
	-- Every pull that isn't the prize: a piece (any slot) of a set of one of
	-- these rarities, with the normal rarity weights between them.
	fillerRarities = { "Common", "Uncommon", "Rare", "Epic" },
	-- Prize pieces = the set's pieces except its weapon (you already own it).
	prizeExcludesWeapon = true,
}

-- ===== PULLS / COST =====
BannerConfig.TokensPerPull = 10 -- Normal Banner; same as SummonConfig.TokensPerPull
BannerConfig.PullOptions = { 1, 10 } -- 50 is added for owners of the More Summon gamepass
BannerConfig.MoreSummonPulls = 50
BannerConfig.VipDiscount = 0.20 -- VIP: 20% cheaper summons

-- ===== ANNOUNCEMENTS =====
-- Rare pulls already get the plaza effects + global announcement
-- (SummonBroadcaster: Mythic server-wide, Superior cross-server).
BannerConfig.AnnounceMinRarity = "Mythic"

-- Is this set one the Selection Banner can feature (its tier has a prize row)?
function BannerConfig.IsSelectableRarity(rarity: string?): boolean
	return rarity ~= nil and BannerConfig.Selection.prizes[rarity] ~= nil
end

-- The Normal Banner pool: {[rarity] = {gearId}} sorted. Set weapons only.
function BannerConfig.BuildPool(GearRegistry: any, RarityConfig: any, SetRegistry: any): {[string]: {string}}
	local cfg = BannerConfig.Normal
	local pool: {[string]: {string}} = {}
	for id, t in GearRegistry.GetAll() do
		local tier = RarityConfig.GetTier(t.rarity)
		if tier and tier.weight > 0 and cfg.categories[t.category] and not t.adminOnly and SetRegistry.GetSetForGearId(id) then
			pool[t.rarity] = pool[t.rarity] or {}
			table.insert(pool[t.rarity], id)
		end
	end
	for _, ids in pool do table.sort(ids) end
	return pool
end

return BannerConfig
