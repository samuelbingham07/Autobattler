--!strict
-- Star levels. Every unit you own or fight is a StarredUnit: a unit
-- definition from Units with its stats scaled up by its star level.
-- Shared so the client can show the same stats the server uses.

local Units = require(script.Parent.Units)

type Unit = Units.Unit

export type StarredUnit = {
	name: string,
	cost: number, -- base cost of a 1-star copy
	health: number,
	damage: number,
	attackSpeed: number,
	traits: { string },
	ability: Units.Ability,
	stars: number,
	startingMana: number, -- mana at the start of a fight (Mystic trait raises it)
}

local Stars = {}

Stars.MAX = 3
Stars.COPIES_TO_UPGRADE = 3

-- Each star multiplies health, damage and ability power by this.
-- Attack speed and mana cost stay the same.
local STAT_MULTIPLIER = 1.8

local unitsByName: { [string]: Unit } = {}
for _, unit in Units do
	unitsByName[unit.name] = unit
end

function Stars.make(name: string, stars: number): StarredUnit
	local base = unitsByName[name]
	assert(base, `No unit named {name}`)
	local scale = STAT_MULTIPLIER ^ (stars - 1)

	local ability = table.clone(base.ability)
	ability.power = math.round(ability.power * scale)

	return {
		name = base.name,
		cost = base.cost,
		health = math.round(base.health * scale),
		damage = math.round(base.damage * scale),
		attackSpeed = base.attackSpeed,
		traits = base.traits,
		ability = ability,
		stars = stars,
		startingMana = 0,
	}
end

-- A unit sells for the total cost of the 1-star copies that went into it.
function Stars.sellValue(unit: StarredUnit): number
	return unit.cost * Stars.COPIES_TO_UPGRADE ^ (unit.stars - 1)
end

function Stars.displayName(unit: StarredUnit): string
	return `{unit.name} {string.rep("★", unit.stars)}`
end

return Stars
