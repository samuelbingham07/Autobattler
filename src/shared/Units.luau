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
		attackSpeed = 0.6,
		traits = { "Guardian" },
		ability = { name = "Shield Up", mana = 50, kind = "healSelf", power = 150 },
	},
	{
		name = "Archer",
		cost = 1,
		health = 450,
		damage = 50,
		attackSpeed = 0.75,
		traits = { "Ranger" },
		ability = { name = "Volley", mana = 60, kind = "damageAll", power = 70 },
	},
	{
		name = "Acolyte",
		cost = 1,
		health = 500,
		damage = 35,
		attackSpeed = 0.7,
		traits = { "Mystic" },
		ability = { name = "Blessing", mana = 60, kind = "healAllies", power = 70 },
	},

	-- 2-cost
	{
		name = "Knight",
		cost = 2,
		health = 850,
		damage = 60,
		attackSpeed = 0.65,
		traits = { "Guardian", "Noble" },
		ability = { name = "Rally", mana = 80, kind = "healAllies", power = 100 },
	},
	{
		name = "Rogue",
		cost = 2,
		health = 600,
		damage = 70,
		attackSpeed = 0.85,
		traits = { "Ranger" },
		ability = { name = "Backstab", mana = 50, kind = "damageBack", power = 180 },
	},
	{
		name = "Mage",
		cost = 2,
		health = 550,
		damage = 45,
		attackSpeed = 0.7,
		traits = { "Mystic" },
		ability = { name = "Firestorm", mana = 60, kind = "damageAll", power = 110 },
	},

	-- 3-cost
	{
		name = "Warlord",
		cost = 3,
		health = 1000,
		damage = 80,
		attackSpeed = 0.8,
		traits = { "Noble" },
		ability = { name = "Cleave", mana = 70, kind = "damageFront", power = 160, count = 2 },
	},
	{
		name = "Sentinel",
		cost = 3,
		health = 1150,
		damage = 60,
		attackSpeed = 0.65,
		traits = { "Guardian", "Mystic" },
		ability = { name = "Stone Skin", mana = 60, kind = "healSelf", power = 350 },
	},

	-- 4-cost
	{
		name = "Paladin",
		cost = 4,
		health = 1300,
		damage = 85,
		attackSpeed = 0.75,
		traits = { "Guardian", "Noble" },
		ability = { name = "Divine Light", mana = 80, kind = "healAllies", power = 220 },
	},
	{
		name = "Sniper",
		cost = 4,
		health = 800,
		damage = 120,
		attackSpeed = 0.8,
		traits = { "Ranger", "Mystic" },
		ability = { name = "Headshot", mana = 60, kind = "damageBack", power = 450 },
	},

	-- 5-cost
	{
		name = "Dragon",
		cost = 5,
		health = 1800,
		damage = 110,
		attackSpeed = 0.8,
		traits = { "Mystic", "Noble" },
		ability = { name = "Inferno", mana = 90, kind = "damageAll", power = 300 },
	},
}

return Units
