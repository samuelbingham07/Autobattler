--!strict
-- Traits: field enough *different* units that share a trait and they get a bonus.
-- Shared so the client can show which traits are active.

local Stars = require(script.Parent.Stars)

type StarredUnit = Stars.StarredUnit

export type TraitInfo = {
	name: string,
	count: number, -- different units on the team with this trait
	required: number,
	active: boolean,
	description: string,
}

local GUARDIAN_HEALTH = 250
local RANGER_ATTACK_SPEED = 1.35
local NOBLE_DAMAGE = 1.15

local TRAITS: { [string]: { required: number, description: string } } = {
	Guardian = { required = 2, description = `Guardians gain +{GUARDIAN_HEALTH} health` },
	Ranger = { required = 2, description = "Rangers attack 35% faster" },
	Noble = { required = 2, description = "Whole team deals +15% attack damage" },
}

-- Alphabetical, so the UI lists traits in a stable order.
local TRAIT_ORDER = { "Guardian", "Noble", "Ranger" }

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

-- Every trait present on the team, for display.
function Traits.summary(units: { StarredUnit }): { TraitInfo }
	local counts = countTraits(units)
	local list = {}
	for _, name in TRAIT_ORDER do
		local count = counts[name]
		if count then
			local def = TRAITS[name]
			table.insert(list, {
				name = name,
				count = count,
				required = def.required,
				active = count >= def.required,
				description = def.description,
			})
		end
	end
	return list
end

local function hasTrait(unit: StarredUnit, trait: string): boolean
	return table.find(unit.traits, trait) ~= nil
end

-- Copies of the units with active trait bonuses applied. Use these for
-- both drawing and fighting so health bars match the real numbers.
function Traits.apply(units: { StarredUnit }): { StarredUnit }
	local counts = countTraits(units)
	local function active(name: string): boolean
		return (counts[name] or 0) >= TRAITS[name].required
	end

	local buffed = {}
	for _, unit in units do
		local copy = table.clone(unit)
		if active("Guardian") and hasTrait(unit, "Guardian") then
			copy.health += GUARDIAN_HEALTH
		end
		if active("Ranger") and hasTrait(unit, "Ranger") then
			copy.attackSpeed *= RANGER_ATTACK_SPEED
		end
		if active("Noble") then
			copy.damage = math.round(copy.damage * NOBLE_DAMAGE)
		end
		table.insert(buffed, copy)
	end
	return buffed
end

return Traits
