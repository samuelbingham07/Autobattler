--!strict
-- The fixed enemy board for each round, front to back.
-- Beat the last round to win the run.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stars = require(ReplicatedStorage.Shared.Stars)

type StarredUnit = Stars.StarredUnit

-- Each entry is { unit name, star level }.
local ROUNDS: { { { any } } } = {
	{ { "Squire", 1 } },
	{ { "Squire", 1 }, { "Archer", 1 } },
	{ { "Knight", 1 }, { "Archer", 1 } },
	{ { "Knight", 1 }, { "Squire", 1 }, { "Archer", 1 } },
	{ { "Knight", 1 }, { "Rogue", 1 }, { "Archer", 1 } },
	{ { "Squire", 2 }, { "Rogue", 1 }, { "Archer", 2 } },
	{ { "Knight", 2 }, { "Warlord", 1 }, { "Rogue", 1 } },
	{ { "Knight", 2 }, { "Warlord", 2 }, { "Archer", 2 } }, -- boss
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
