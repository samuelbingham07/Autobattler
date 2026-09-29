--!strict
-- Unit definitions. Higher cost = better raw stats, TFT-style.
-- DPS = damage * attackSpeed

export type Unit = {
	name: string,
	cost: number,
	health: number,
	damage: number,
	attackSpeed: number,
}

local Units: { Unit } = {
	-- 1-cost
	{ name = "Squire", cost = 1, health = 650, damage = 45, attackSpeed = 0.6 }, -- tank, 27 DPS
	{ name = "Archer", cost = 1, health = 450, damage = 50, attackSpeed = 0.75 }, -- carry, 37.5 DPS

	-- 2-cost
	{ name = "Knight", cost = 2, health = 850, damage = 60, attackSpeed = 0.65 }, -- tank, 39 DPS
	{ name = "Rogue", cost = 2, health = 600, damage = 70, attackSpeed = 0.85 }, -- carry, 59.5 DPS

	-- 3-cost
	{ name = "Warlord", cost = 3, health = 1000, damage = 80, attackSpeed = 0.8 }, -- 64 DPS
}

return Units
