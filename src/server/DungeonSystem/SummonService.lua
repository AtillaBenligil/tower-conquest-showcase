--!strict
-- SummonService
-- The token-funded gacha. Rewritten 2026-10-03 for the Changes & Additions
-- design (5.3); the old version is in ServerStorage.Backup_PreIntegration_2026-10-03.
--
-- Banners (logic in ServerScriptService.Progression.BannerService; reworked
-- 2026-10-08, weapons first):
--   * Normal Banner (bannerId "main"): WEAPONS ONLY -- every set's weapon.
--     Pity: a Legendary+ within SummonConfig.PityThreshold pulls. Pulling a
--     weapon unlocks its set for the Selection Banner.
--   * Selection Banner ("selection"): the player's chosen unlocked
--     Legendary+ set is the grand prize (BannerConfig.Selection.prizes:
--     chance + price per pull by tier), everything else is Common-Epic set
--     gear. No pity.
-- Costs: Normal 10 Tokens per pull, VIP -20%, up to 10 per summon or 50 with
-- the More Summon gamepass. Luck (gear + Luck Index + Luck passes) raises the
-- rare outcomes through LuckService.
--
-- Each pull, in order:
--   1. Auto-Sell ON for that rarity -> converts to Tokens
--   2. otherwise RewardService.GrantGear: a DUPLICATE refunds Tokens instead
--      of stacking; a new item lands in the inventory
--   Both pay the item's token value (SummonConfig.TokenValue, Common 1 ...
--   Superior 750), balanced so a pull gives back well under its price.
--   3. ItemObtained / Summoned events -> Index, Luck Index, battle pass XP,
--      set unlocks (ProgressionData doc.obtained)
-- Summon Plaza rules are unchanged: you must stand at an altar
-- (AltarRegistry), and every summon goes to SummonBroadcaster for the altar
-- burst + Mythic / Superior global announcements. SummonOverrides (admin
-- /forcepull) still forces a rarity.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GearRegistry = require(ReplicatedStorage.GearSystem.GearRegistry)
local SetRegistry = require(ReplicatedStorage.GearSystem.SetRegistry)
local SummonConfig = require(ReplicatedStorage.GearSystem.SummonConfig)
local BannerConfig = require(ReplicatedStorage.Progression.BannerConfig)
local InventoryManager = require(game.ServerScriptService.GearSystem.InventoryManager)
local AutoSellSettings = require(game.ServerScriptService.GearSystem.AutoSellSettings)
local ServiceRegistry = require(game.ServerScriptService.ServiceRegistry)
local RateLimiter = require(game.ServerScriptService.RateLimiter)
local DataStoreManager = require(game.ServerScriptService.DataStoreManager)
local SummonPlazaConfig = require(ReplicatedStorage.SummonPlaza.SummonPlazaConfig)
local AltarRegistry = require(game.ServerScriptService.SummonPlaza.AltarRegistry)
local SummonBroadcaster = require(game.ServerScriptService.SummonPlaza.SummonBroadcaster)
local SummonOverrides = require(game.ServerScriptService.SummonPlaza.SummonOverrides)
local ProgressionFolder = game.ServerScriptService:WaitForChild("Progression")
local BannerService = require(ProgressionFolder:WaitForChild("BannerService"))
local RewardService = require(ProgressionFolder:WaitForChild("RewardService"))
local ProgressionEvents = require(ProgressionFolder:WaitForChild("ProgressionEvents"))
local LuckService = require(ProgressionFolder:WaitForChild("LuckService"))

local DungeonRemotes = ReplicatedStorage.DungeonSystem.Remotes
local SummonRequest = DungeonRemotes.SummonRequest :: RemoteEvent
local SummonResult = DungeonRemotes.SummonResult :: RemoteEvent
local GetSetBanners = DungeonRemotes.GetSetBanners :: RemoteFunction

local GearRemotes = ReplicatedStorage.GearSystem.Remotes
local InventoryUpdate = GearRemotes.InventoryUpdate :: RemoteEvent

local PITY_THRESHOLD = SummonConfig.PityThreshold
local PITY_RARITIES = SummonConfig.PityRarities
local MAIN_BANNER_KEY = SummonConfig.MainBannerKey
local AUTO_SELL_VALUE = SummonConfig.AutoSellValue
local SELECTION_KEY = BannerConfig.Selection.id

local SAVE_NOW_RARITIES = { Mythic = true, Superior = true }

local PITY_STORE = "SummonPity_v1"
local SAVE_KEY_PREFIX = "player_"

local summonLimiter = RateLimiter.new(SummonConfig.RateLimitSeconds)

-- pityCount[player][bannerKey] = pulls since that banner's last Legendary+
local pityCount: {[Player]: {[string]: number}} = {}
local pityLoadOk: {[Player]: boolean} = {}

local function getBannerPity(player: Player, bannerKey: string): number
	local playerPity = pityCount[player]
	if not playerPity then return 0 end
	return playerPity[bannerKey] or 0
end

local function setBannerPity(player: Player, bannerKey: string, value: number)
	if not pityCount[player] then
		pityCount[player] = {}
	end
	pityCount[player][bannerKey] = value
end

-- Never saves pity we failed to load (it would reset the real counter).
local function savePityData(player: Player)
	local playerPity = pityCount[player]
	if not playerPity or not pityLoadOk[player] then return end
	local key = SAVE_KEY_PREFIX .. tostring(player.UserId)
	local snapshot = table.clone(playerPity)
	task.spawn(function()
		DataStoreManager.Save(PITY_STORE, key, snapshot)
	end)
end

local function loadPityData(player: Player)
	local key = SAVE_KEY_PREFIX .. tostring(player.UserId)
	task.spawn(function()
		local saved, success = DataStoreManager.Load(PITY_STORE, key)
		if success and saved and type(saved) == "table" then
			-- keep any pulls made while loading
			local live = pityCount[player] or {}
			for k, v in saved do
				if type(v) == "number" then live[k] = math.max(v, live[k] or 0) end
			end
			pityCount[player] = live
		end
		if success then pityLoadOk[player] = true end
	end)
end

local function syncInventory(player: Player)
	local gs = ServiceRegistry.Get("GearSystem")
	if gs and gs.SyncInventory then
		gs.SyncInventory(player)
		return
	end
	local inv = InventoryManager.GetInventory(player)
	if not inv then return end
	local items = {}
	for _, item in ipairs(inv.items) do
		local template = GearRegistry.Get(item.gearId)
		table.insert(items, {
			instanceId = item.instanceId, gearId = item.gearId,
			name = template and template.name or item.gearId,
			description = template and template.description or "",
			category = template and template.category or "Misc",
			rarity = item.rarity, stats = item.stats, abilityId = item.abilityId,
			serialNumber = item.serialNumber, enhanceLevel = item.enhanceLevel,
			starLevel = item.starLevel, count = item.count, failedUpgrades = item.failedUpgrades,
		})
	end
	local equipped = {}
	for slot, item in pairs(inv.equipped) do
		if item then equipped[slot] = item.instanceId end
	end
	InventoryUpdate:FireClient(player, { items = items, equipped = equipped })
end

-- One rarity roll: an admin-forced rarity (SummonDebug /forcepull) or the
-- luck-adjusted roll.
local function naturalRarity(player: Player, luckMult: number): string?
	local forced = SummonOverrides.Take(player)
	if forced and #GearRegistry.GetByRarity(forced) > 0 then return forced end
	return BannerService.RollRarity(player, luckMult)
end

-- Rolls one pull on a banner (pity included). Returns gearId, rarity, isPrize.
local function rollPull(player: Player, bannerKey: string, luckMult: number): (string?, string?, boolean)
	if bannerKey == SELECTION_KEY then
		return BannerService.RollSelection(player, luckMult, SummonOverrides.Take(player))
	end

	local gearId, rarity
	local previousPity = getBannerPity(player, bannerKey)
	local pity = previousPity + 1
	setBannerPity(player, bannerKey, pity)

	if pity >= PITY_THRESHOLD then
		local pityRarity = BannerService.RollPityRarity() -- same odds the window shows
		if pityRarity then
			rarity = pityRarity
			gearId = BannerService.PickItem(player, MAIN_BANNER_KEY, pityRarity)
		end
	end
	if not gearId then
		rarity = naturalRarity(player, luckMult)
		gearId = rarity and BannerService.PickItem(player, MAIN_BANNER_KEY, rarity)
	end
	if gearId and PITY_RARITIES[rarity] then
		setBannerPity(player, bannerKey, 0)
	end

	if not gearId then
		setBannerPity(player, bannerKey, previousPity)
	end
	return gearId, rarity, false
end

-- The set this weapon belongs to, if pulling it unlocks one for the
-- Selection Banner right now (Legendary+ sets: the only ones it offers).
local function unlocksSet(player: Player, gearId: string): string?
	local setId = SetRegistry.GetSetForGearId(gearId)
	if not setId or BannerService.IsUnlocked(player, setId) then return nil end
	local info = BannerService.SetInfo(setId)
	return if info and info.weapon == gearId and BannerConfig.IsSelectableRarity(info.rarity) then setId else nil
end

local function rollOne(player: Player, bannerKey: string, luckMult: number)
	local gearId, rarity, prize = rollPull(player, bannerKey, luckMult)
	if not gearId or not rarity then return nil end
	local template = GearRegistry.Get(gearId)
	local selected = prize
	local newSet = unlocksSet(player, gearId)
	local unlocked = if newSet then (BannerService.SetInfo(newSet) :: any).name else nil
	local setId = SetRegistry.GetSetForGearId(gearId)
	local setInfo = if setId then BannerService.SetInfo(setId) else nil
	local setName = if setInfo then setInfo.name else nil

	if AutoSellSettings.IsAutoSellOn(player, rarity) then
		local tokenValue = AUTO_SELL_VALUE[rarity] or 2
		local TokenService = ServiceRegistry.Get("TokenService")
		if TokenService then TokenService.AwardTokens(player, tokenValue) end
		ProgressionEvents.ItemObtained:Fire(player, {
			gearId = gearId, rarity = rarity, category = template and template.category, source = "summon", autoSold = true,
		})
		return {
			gearId = gearId,
			name = template and template.name or gearId,
			category = template and template.category or "Misc",
			rarity = rarity,
			autoSold = true,
			tokensAwarded = tokenValue,
			selected = selected,
			unlockedSet = unlocked,
			set = setName,
		}
	end

	local row = RewardService.GrantGear(player, gearId, "summon")
	if not row then return nil end
	return {
		instanceId = row.instanceId,
		gearId = gearId,
		name = row.name,
		category = row.category,
		rarity = rarity,
		serialNumber = row.serialNumber,
		dupe = row.dupe,
		refund = row.refund,
		selected = selected,
		unlockedSet = unlocked,
		set = setName,
	}
end

SummonRequest.OnServerEvent:Connect(function(player: Player, bannerId: any, pullCount: any)
	if not summonLimiter:Check(player) then
		SummonResult:FireClient(player, { success = false, reason = "Too many requests" })
		return
	end
	if type(bannerId) ~= "string" and bannerId ~= nil then
		SummonResult:FireClient(player, { success = false, reason = "Invalid banner" })
		return
	end

	local maxPulls = BannerService.MaxPulls(player)
	pullCount = math.clamp(math.floor(tonumber(pullCount) or 1), 1, maxPulls)

	if not InventoryManager.IsLoaded(player) then
		SummonResult:FireClient(player, { success = false, reason = "Your inventory is still loading -- try again in a moment" })
		return
	end
	if InventoryManager.FreeSlots(player) <= 0 then
		SummonResult:FireClient(player, { success = false, reason = "Inventory full -- sell some gear first" })
		return
	end

	local bannerKey
	if bannerId == nil or bannerId == MAIN_BANNER_KEY then
		bannerKey = MAIN_BANNER_KEY
	elseif bannerId == SELECTION_KEY then
		bannerKey = SELECTION_KEY
		if not BannerService.SelectedSet(player) then
			SummonResult:FireClient(player, { success = false, reason = "Choose one of your unlocked sets for the Selection Banner first" })
			return
		end
	else
		-- includes the old "set:<id>" banners (turned off 2026-10-05)
		SummonResult:FireClient(player, { success = false, reason = "Invalid banner" })
		return
	end

	local altar = AltarRegistry.FindAltarFor(player)
	if SummonPlazaConfig.RequireAltar and not altar then
		SummonResult:FireClient(player, { success = false, reason = "Stand at a summon altar in the plaza to summon" })
		return
	end

	local perPull = BannerService.CostPerPull(player, bannerKey)
	local cost = BannerService.Cost(player, bannerKey, pullCount)
	local TokenService = ServiceRegistry.Get("TokenService")
	if not perPull or not cost then
		SummonResult:FireClient(player, { success = false, reason = "Invalid banner" })
		return
	end
	if not (TokenService and TokenService.SpendTokens(player, cost)) then
		SummonResult:FireClient(player, { success = false, reason = "Not enough tokens" })
		return
	end

	local luckMult = LuckService.Multiplier(player)
	local results = {}
	local failedPulls = 0
	local pulledSomethingRare = false
	for _ = 1, pullCount do
		local ok, result = pcall(rollOne, player, bannerKey, luckMult)
		if ok and result then
			table.insert(results, result)
			if SAVE_NOW_RARITIES[result.rarity] and not result.autoSold then
				pulledSomethingRare = true
			end
		else
			if not ok then warn("[SummonService] pull failed: " .. tostring(result)) end
			failedPulls += 1
		end
	end

	-- Never keep tokens for a pull that produced nothing.
	if failedPulls > 0 then
		TokenService.AwardTokens(player, math.floor(failedPulls * perPull + 0.5))
	end

	syncInventory(player)
	InventoryManager.MarkDirty(player)
	if pulledSomethingRare then
		local GearSystem = ServiceRegistry.Get("GearSystem")
		if GearSystem and GearSystem.SaveNow then GearSystem.SaveNow(player) end
		if TokenService.SaveNow then TokenService.SaveNow(player) end
	end
	savePityData(player)

	local pityNow, pityMax -- the Selection Banner has no pity
	if bannerKey == MAIN_BANNER_KEY then
		pityNow, pityMax = getBannerPity(player, bannerKey), PITY_THRESHOLD
	end

	SummonResult:FireClient(player, {
		success = true,
		bannerId = bannerKey,
		results = results,
		pityCount = pityNow,
		pityThreshold = pityMax,
		refundedPulls = failedPulls > 0 and failedPulls or nil,
		spent = cost,
	})

	if #results > 0 then
		ProgressionEvents.Summoned:Fire(player, { bannerId = bannerKey, count = #results, results = results })
		task.spawn(SummonBroadcaster.OnSummon, player, altar, results)
	end
end)

-- Banner info for the summon window (kept on the old remote name).
GetSetBanners.OnServerInvoke = function(player: Player)
	return BannerService.Describe(player, getBannerPity(player, MAIN_BANNER_KEY), PITY_THRESHOLD)
end

Players.PlayerAdded:Connect(function(player)
	loadPityData(player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	loadPityData(player)
end

Players.PlayerRemoving:Connect(function(player)
	savePityData(player)
	pityCount[player] = nil
	pityLoadOk[player] = nil
	summonLimiter:Clear(player)
end)

DataStoreManager.RegisterSaveCallback(function(player)
	savePityData(player)
end)

print("[DungeonSystem] SummonService initialized.")
