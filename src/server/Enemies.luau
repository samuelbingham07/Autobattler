--!strict
-- The fixed enemy board for each round, front to back.
-- Enemies get trait bonuses too, using the same rules as you.
-- Beat the last round to win the run.
--
-- Tune these with the balance simulator (Simulate.luau), which prints how
-- often a bot player beats each round.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stars = require(ReplicatedStorage.Shared.Stars)

type StarredUnit = Stars.StarredUnit

-- Each entry is { unit name, star level }.
local ROUNDS: { { { any } } } = {
	{ { "Squire", 1 } },
	{ { "Squire", 1 }, { "Archer", 1 } },
	{ { "Knight", 1 }, { "Squire", 1 }, { "Archer", 1 } }, -- Guardian
	{ { "Knight", 1 }, { "Rogue", 1 }, { "Archer", 1 } }, -- Ranger
	{ { "Knight", 1 }, { "Squire", 1 }, { "Mage", 1 }, { "Acolyte", 1 } }, -- Guardian + Mystic
	{ { "Squire", 2 }, { "Knight", 1 }, { "Rogue", 1 }, { "Archer", 2 } }, -- Guardian + Ranger
	{ { "Knight", 2 }, { "Warlord", 1 }, { "Rogue", 1 }, { "Archer", 2 } }, -- Noble + Ranger
	{ { "Sentinel", 1 }, { "Knight", 2 }, { "Mage", 2 }, { "Acolyte", 2 }, { "Archer", 1 } }, -- Mystic x3 + Guardian
	{ { "Paladin", 1 }, { "Knight", 2 }, { "Warlord", 1 }, { "Rogue", 2 }, { "Archer", 2 } }, -- Noble x3 + Ranger
	{ { "Sentinel", 2 }, { "Paladin", 1 }, { "Warlord", 2 }, { "Sniper", 1 }, { "Mage", 2 } }, -- Guardian + Noble + Mystic x3
	{ { "Paladin", 2 }, { "Knight", 2 }, { "Sentinel", 2 }, { "Warlord", 2 }, { "Sniper", 1 }, { "Rogue", 2 } },
	{ { "Paladin", 2 }, { "Sentinel", 2 }, { "Knight", 2 }, { "Dragon", 1 }, { "Sniper", 2 }, { "Mage", 2 } }, -- boss
}

local Enemies = {}

Enemies.COUNT = #ROUNDS

-- Rounds past the end reuse the last (boss) board.
function Enemies.forRound(round: number): { StarredUnit }
	local units = {}
	for _, entry in ROUNDS[math.min(round, #ROUNDS)] do
		table.insert(units, Stars.make(entry[1], entry[2]))
	end
	return units
end

return Enemies
