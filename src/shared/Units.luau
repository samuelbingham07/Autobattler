--!strict
-- Unit definitions. Higher cost = better raw stats, TFT-style.
-- DPS = damage * attackSpeed

-- What an ability does when its caster's mana is full. See Combat for the effects.
export type AbilityKind =
	"healSelf" -- heal the caster
	| "healAllies" -- heal every living ally
	| "damageAll" -- hit every living enemy
	| "damageBack" -- hit the back-most living enemy
	| "damageFront" -- hit the front `count` living enemies

export type Ability = {
	name: string,
	mana: number, -- mana needed to cast
	kind: AbilityKind,
	power: number, -- damage or healing, before star scaling
	count: number?, -- targets, for damageFront
}

export type Unit = {
	name: string,
	cost: number,
	health: number,
	damage: number,
	attackSpeed: number,
	traits: { string }, -- see Traits
	ability: Ability,
}

local Units: { Unit } = {
	-- 1-cost
	{
		name = "Squire",
		cost = 1,
		health = 650,
		damage = 45,
		attackSpeed = 0.6, -- tank, 27 DPS
		traits = { "Guardian" },
		ability = { name = "Shield Up", mana = 50, kind = "healSelf", power = 150 },
	},
	{
		name = "Archer",
		cost = 1,
		health = 450,
		damage = 50,
		attackSpeed = 0.75, -- carry, 37.5 DPS
		traits = { "Ranger" },
		ability = { name = "Volley", mana = 60, kind = "damageAll", power = 70 },
	},

	-- 2-cost
	{
		name = "Knight",
		cost = 2,
		health = 850,
		damage = 60,
		attackSpeed = 0.65, -- tank, 39 DPS
		traits = { "Guardian", "Noble" },
		ability = { name = "Rally", mana = 80, kind = "healAllies", power = 100 },
	},
	{
		name = "Rogue",
		cost = 2,
		health = 600,
		damage = 70,
		attackSpeed = 0.85, -- carry, 59.5 DPS
		traits = { "Ranger" },
		ability = { name = "Backstab", mana = 50, kind = "damageBack", power = 180 },
	},

	-- 3-cost
	{
		name = "Warlord",
		cost = 3,
		health = 1000,
		damage = 80,
		attackSpeed = 0.8, -- 64 DPS
		traits = { "Noble" },
		ability = { name = "Cleave", mana = 70, kind = "damageFront", power = 160, count = 2 },
	},
}

return Units
