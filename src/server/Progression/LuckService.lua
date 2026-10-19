--!strict
-- LuckService
-- One place that turns a player's luck into odds (Integration blueprint 7.1).
--   GetBreakdown(player) -> { gear, index, passes, multiplier, sources = {...} }
--   Multiplier(player)   -> final luck multiplier (1 = no luck)
--   AdjustWeights(weights, commonKey, mult) -> new weights: every outcome
--       except the most common one is multiplied, the common one absorbs it
--   RollWeighted(weights, mult, rng?) -> key
--   Odds(weights, mult) -> {[key] = percent}: the exact odds RollWeighted
--       uses (shown to players -- paid random items must show their odds)
--   RollChance(player, baseChance) -> bool (e.g. Champion drops)
-- Applies ONLY to summons, trait rolls, stat rolls and Champion drops
-- (design 5.6). Combine rule and cap: LuckConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LuckConfig = require(ReplicatedStorage.Progression.LuckConfig)
local StatService = require(script.Parent.StatService)

local LuckService = {}

-- Filled by other services (no circular requires):
LuckService.IndexLuck = function(_player: Player): (number, {any}) return 0, {} end -- IndexService (Luck Index)
LuckService.PassMultiplier = function(_player: Player): (number, {string}) return 1, {} end -- MonetizationService

function LuckService.GetBreakdown(player: Player)
	local gear = StatService.GetStats(player).luck or 0 -- gear + passives + set bonuses (percent)
	local index, indexSources = LuckService.IndexLuck(player)
	local passMult, passNames = LuckService.PassMultiplier(player)
	local mult
	if LuckConfig.Combine == "AllMultiplicative" then
		mult = (1 + gear / 100) * (1 + index / 100) * passMult
	else
		mult = (1 + (gear + index) / 100) * passMult
	end
	if LuckConfig.Cap then mult = math.min(mult, LuckConfig.Cap) end
	mult = math.max(mult, 0.01)
	return {
		gear = gear,
		index = index,
		passes = passMult,
		passNames = passNames,
		multiplier = mult,
		sources = indexSources,
	}
end

function LuckService.Multiplier(player: Player): number
	return LuckService.GetBreakdown(player).multiplier
end

-- weights: {[key] = number}; commonKey = the outcome that absorbs the
-- difference (usually the most common). Returns a NEW table.
function LuckService.AdjustWeights(weights: {[any]: number}, commonKey: any, mult: number): {[any]: number}
	local total = 0
	for _, w in weights do total += w end
	if total <= 0 then return table.clone(weights) end
	local out = {}
	local rareTotal = 0
	for k, w in weights do
		if k ~= commonKey then
			out[k] = w / total * mult
			rareTotal += out[k]
		end
	end
	local minCommon = if weights[commonKey] then LuckConfig.MinCommonShare else 0
	if rareTotal > 1 - minCommon then
		-- normalize the rare outcomes down so the table stays valid
		local scale = (1 - minCommon) / rareTotal
		for k in out do out[k] *= scale end
		rareTotal = 1 - minCommon
	end
	if weights[commonKey] then out[commonKey] = 1 - rareTotal end
	return out
end

-- Most common key of a weight table.
function LuckService.CommonKey(weights: {[any]: number}): any
	local best, bestW = nil, -math.huge
	for k, w in weights do
		if w > bestW then best, bestW = k, w end
	end
	return best
end

function LuckService.RollWeighted(weights: {[any]: number}, mult: number?, order: {any}?): any
	local w = weights
	if mult and mult ~= 1 then w = LuckService.AdjustWeights(weights, LuckService.CommonKey(weights), mult) end
	local total = 0
	for _, v in w do total += v end
	if total <= 0 then return nil end
	local roll = math.random() * total
	-- deterministic iteration order when given (stable results for tests)
	if order then
		for _, k in order do
			local v = w[k]
			if v then
				roll -= v
				if roll <= 0 then return k end
			end
		end
	end
	local last = nil
	for k, v in w do
		last = k
		roll -= v
		if roll <= 0 then return k end
	end
	return last
end

-- Percent odds of every outcome after luck: the same table RollWeighted rolls on.
function LuckService.Odds(weights: {[any]: number}, mult: number?): {[any]: number}
	local w = weights
	if mult and mult ~= 1 then w = LuckService.AdjustWeights(weights, LuckService.CommonKey(weights), mult) end
	local total = 0
	for _, v in w do total += v end
	local out = {}
	for k, v in w do out[k] = if total > 0 then v / total * 100 else 0 end
	return out
end

-- A single yes/no chance with luck applied (capped at 100%).
function LuckService.RollChance(player: Player, baseChance: number): boolean
	local chance = math.min(1, baseChance * LuckService.Multiplier(player))
	return math.random() < chance
end

return LuckService
