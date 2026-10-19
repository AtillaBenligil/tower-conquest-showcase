--!strict
-- SummonConfig
-- Centralized balance values for the summon/gacha system.
-- All tunable values live here so designers can adjust without touching logic.

local SummonConfig = {}

-- Cost per single pull (in Tokens)
SummonConfig.TokensPerPull = 10

-- Pity system: guaranteed Legendary+ after this many pulls without one
SummonConfig.PityThreshold = 50

-- Rarities that reset the pity counter when rolled
SummonConfig.PityRarities = { Legendary = true, Mythic = true, Superior = true }

-- SET BANNERS are rate-up banners: each pull rolls rarity exactly like
-- the Main Banner (same odds, same luck). When the rolled rarity matches
-- the set's rarity, the item comes from the featured set instead of the
-- whole catalog. (They used to roll ONLY inside the set -- and every set
-- is a single rarity -- so a Superior set banner gave a Superior on every
-- single pull.)
-- Set-banner pity: after this many pulls without a featured-set piece,
-- the next pull is guaranteed one. Scaled by the set's rarity. nil = no
-- guarantee (Superior stays luck-only). Tune freely.
SummonConfig.SetBannerPity = {
	Common = 10,
	Uncommon = 20,
	Rare = 40,
	Epic = 60,
	Legendary = 90,
	Mythic = 150,
	Superior = nil,
}

-- Maximum pulls allowed in a single request (multi-pull cap)
SummonConfig.MaxPullsPerRequest = 10

-- Rate limiting: minimum seconds between summon requests per player
SummonConfig.RateLimitSeconds = 0.5

-- Banner key for the main banner (non-set)
SummonConfig.MainBannerKey = "main"

-- TOKEN VALUE of a piece of gear you don't keep. ONE table for all three:
--   * Auto-Sell (SummonService)
--   * a duplicate pull (RewardService, via GearProgressionConfig.DupeRefund)
--   * selling it from the inventory (GearEnhanceService, +8% per enhance level)
-- Balance rule: what a pull gives back must stay well under what it costs,
-- or summoning pays for itself and never ends. With these values a 10-token
-- pull gives back about 2.5 tokens on average even if EVERY pull were a
-- duplicate (about 4 with the best possible luck), so 1,000 tokens buys
-- roughly 120 pulls instead of 100 -- not infinitely many.
-- (Was: dupes Common 2 ... Superior 100,000 = ~84 tokens back per 10-token
-- pull, and Auto-Sell 3..300 = 66%, over 100% with luck passes.)
SummonConfig.TokenValue = {
	Starter = 1,
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 8,
	Legendary = 25,
	Mythic = 100,
	Superior = 750,
	Admin = 0,
}
-- old name, still read by SummonService
SummonConfig.AutoSellValue = SummonConfig.TokenValue

return SummonConfig