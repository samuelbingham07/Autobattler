--!strict
-- Player levels: more board slots and better shop odds as you level up.
-- Shared so the client can show odds and XP progress.

local Levels = {}

Levels.MAX = 5
Levels.XP_PER_ROUND = 2
Levels.XP_BUY_COST = 4 -- gold
Levels.XP_PER_BUY = 4

-- XP needed to go from level n to level n + 1.
local XP_TO_NEXT: { [number]: number } = {
	[1] = 2,
	[2] = 6,
	[3] = 10,
	[4] = 20,
}

-- Chance of each cost tier per shop slot, by level: { 1-cost, 2-cost, 3-cost, 4-cost, 5-cost }.
-- Each row must add up to 1.
local SHOP_ODDS: { [number]: { number } } = {
	[1] = { 0.75, 0.25, 0.00, 0.00, 0.00 },
	[2] = { 0.55, 0.30, 0.15, 0.00, 0.00 },
	[3] = { 0.40, 0.33, 0.20, 0.07, 0.00 },
	[4] = { 0.25, 0.30, 0.28, 0.14, 0.03 },
	[5] = { 0.15, 0.22, 0.30, 0.23, 0.10 },
}

function Levels.boardSize(level: number): number
	return level + 1
end

-- nil at max level.
function Levels.xpToNext(level: number): number?
	return XP_TO_NEXT[level]
end

function Levels.shopOdds(level: number): { number }
	return SHOP_ODDS[level]
end

return Levels
