--!strict
-- OddsFormat
-- Odds text for paid random items, shared by every window that shows odds
-- (Summon, Traits, Upgrades). Roblox's paid random items policy: odds are
-- shown as percentages; long decimals may be rounded to at least four places
-- past the first non-zero digit, with a disclaimer that the shown values may
-- not add up to exactly 100%.

local OddsFormat = {}

OddsFormat.Disclaimer = "Probabilities are rounded; total of displayed individual probabilities may not equal 100%."
OddsFormat.ShortDisclaimer = "rounded, may not add up to exactly 100%"

-- Decimal places for a percentage: four past its first non-zero digit,
-- never fewer than four (55.5442%, 0.27772%, 0.0019441%).
function OddsFormat.Places(p: number): number
	if p <= 0 then return 0 end
	return math.max(4, 4 - math.floor(math.log10(p)))
end

-- True when Pct(p) is not the exact value (show the disclaimer).
function OddsFormat.IsRounded(p: number): boolean
	local scaled = p * 10 ^ OddsFormat.Places(p)
	return math.abs(scaled - math.round(scaled)) > 1e-6
end

-- "55.5448%", "11.1090%", "0.019441%"; exact values lose their trailing
-- zeros ("40%", "12.5%"), rounded ones keep every place.
function OddsFormat.Pct(p: number): string
	local s = string.format("%." .. OddsFormat.Places(p) .. "f", math.max(p, 0))
	if string.find(s, ".", 1, true) and not OddsFormat.IsRounded(p) then
		s = s:gsub("0+$", ""):gsub("%.$", "")
	end
	return s .. "%"
end

-- "1.25", "1.875", "2" for a luck multiplier
function OddsFormat.Mult(m: number): string
	local s = string.format("%.3f", m):gsub("0+$", ""):gsub("%.$", "")
	return s
end

return OddsFormat
