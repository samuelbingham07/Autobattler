--!strict
-- Traits: field enough *different* units that share a trait and they get a bonus.
-- Each trait has tiers; reaching a higher count replaces the lower tier's bonus.
-- Shared so the client can show which traits are active.

local Stars = require(script.Parent.Stars)

type StarredUnit = Stars.StarredUnit

type Tier = {
	count: number, -- different units needed
	value: number, -- size of the bonus; what it means depends on the trait
	description: string,
}

export type TraitInfo = {
	name: string,
	count: number, -- different units on the team with this trait
	tiers: { Tier },
	activeTier: number, -- 0 if not active
	nextCount: number?, -- units needed for the next tier, nil at the top
}

local TRAITS: { [string]: { Tier } } = {
	Guardian = {
		{ count = 2, value = 250, description = "Guardians +250 health" },
		{ count = 4, value = 600, description = "Guardians +600 health" },
	},
	Mystic = {
		{ count = 2, value = 20, description = "Mystics start with 20 mana" },
		{ count = 4, value = 45, description = "Mystics start with 45 mana" },
	},
	Noble = {
		{ count = 2, value = 1.15, description = "Whole team +15% attack damage" },
		{ count = 4, value = 1.35, description = "Whole team +35% attack damage" },
	},
	Ranger = {
		{ count = 2, value = 1.35, description = "Rangers attack 35% faster" },
		{ count = 3, value = 1.7, description = "Rangers attack 70% faster" },
	},
}

-- Alphabetical, so the UI lists traits in a stable order.
local TRAIT_ORDER = { "Guardian", "Mystic", "Noble", "Ranger" }

local Traits = {}

-- How many different units have each trait. Two copies of the same unit count once, like TFT.
local function countTraits(units: { StarredUnit }): { [string]: number }
	local counts = {}
	local seen = {}
	for _, unit in units do
		if not seen[unit.name] then
			seen[unit.name] = true
			for _, trait in unit.traits do
				counts[trait] = (counts[trait] or 0) + 1
			end
		end
	end
	return counts
end

-- The highest tier reached (0 = none) and that tier's data.
local function activeTier(name: string, count: number): (number, Tier?)
	local reached, tierData = 0, nil
	for index, tier in TRAITS[name] do
		if count >= tier.count then
			reached, tierData = index, tier
		end
	end
	return reached, tierData
end

-- Every trait present on the team, for display.
function Traits.summary(units: { StarredUnit }): { TraitInfo }
	local counts = countTraits(units)
	local list = {}
	for _, name in TRAIT_ORDER do
		local count = counts[name]
		if count then
			local tiers = TRAITS[name]
			local reached = activeTier(name, count)
			local nextTier = tiers[reached + 1]
			table.insert(list, {
				name = name,
				count = count,
				tiers = tiers,
				activeTier = reached,
				nextCount = if nextTier then nextTier.count else nil,
			})
		end
	end
	return list
end

-- Copies of the units with active trait bonuses applied. Use these for
-- both drawing and fighting so health bars match the real numbers.
function Traits.apply(units: { StarredUnit }): { StarredUnit }
	local counts = countTraits(units)
	local bonus: { [string]: number? } = {}
	for name in TRAITS do
		local _, tier = activeTier(name, counts[name] or 0)
		bonus[name] = if tier then tier.value else nil
	end

	local buffed = {}
	for _, unit in units do
		local copy = table.clone(unit)
		local has = function(trait: string): boolean
			return table.find(unit.traits, trait) ~= nil
		end
		local guardian, mystic, noble, ranger = bonus.Guardian, bonus.Mystic, bonus.Noble, bonus.Ranger
		if guardian and has("Guardian") then
			copy.health += guardian
		end
		if mystic and has("Mystic") then
			copy.startingMana = math.min(copy.ability.mana, mystic)
		end
		if noble then
			copy.damage = math.round(copy.damage * noble)
		end
		if ranger and has("Ranger") then
			copy.attackSpeed *= ranger
		end
		table.insert(buffed, copy)
	end
	return buffed
end

return Traits
