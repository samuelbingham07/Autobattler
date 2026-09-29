--!strict
-- Everything the player owns: the board (fights) and the bench (storage).
-- Handles placing new units, moving between board and bench, selling,
-- and combining 3 copies into a higher star level.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stars = require(ReplicatedStorage.Shared.Stars)
local Board = require(script.Parent.Board)

type StarredUnit = Stars.StarredUnit
type Board = Board.Board

local BENCH_SIZE = 5

export type Zone = "board" | "bench"

type Location = { zone: Board, index: number }

local Roster = {}
Roster.__index = Roster
Roster.BENCH_SIZE = BENCH_SIZE

type RosterData = {
	board: Board,
	bench: Board,
}

export type Roster = typeof(setmetatable({} :: RosterData, Roster))

function Roster.new(): Roster
	return setmetatable({ board = Board.new(), bench = Board.new(BENCH_SIZE) }, Roster)
end

function Roster.GetZone(self: Roster, zone: Zone): Board
	return if zone == "board" then self.board else self.bench
end

function Roster.HasSpace(self: Roster): boolean
	return not self.board:IsFull() or not self.bench:IsFull()
end

-- Every copy of a unit at a given star level, board first, then bench.
local function locate(self: Roster, name: string, stars: number): { Location }
	local found = {}
	for _, zone in { self.board, self.bench } do
		for index, unit in zone:GetUnits() do
			if unit.name == name and unit.stars == stars then
				table.insert(found, { zone = zone, index = index })
			end
		end
	end
	return found
end

-- Upgrade the unit at locations[1] by one star and remove the rest.
-- locations[1] is always the first copy found, so any other copies in the same
-- zone sit at higher indexes and removing them doesn't shift the kept one.
local function merge(locations: { Location }, name: string, stars: number): StarredUnit
	local upgraded = Stars.make(name, stars + 1)
	local keep = locations[1]
	keep.zone:Set(keep.index, upgraded)

	local rest = table.move(locations, 2, #locations, 1, {})
	table.sort(rest, function(a, b)
		return a.index > b.index -- highest first, so earlier removals don't shift later ones
	end)
	for _, location in rest do
		location.zone:Remove(location.index)
	end
	return upgraded
end

-- Keep merging until no set of 3 is left (three 2-stars can appear after a merge).
local function mergeAll(self: Roster, upgrades: { StarredUnit })
	local merged = true
	while merged do
		merged = false
		local owned = self.board:GetUnits()
		for _, unit in self.bench:GetUnits() do
			table.insert(owned, unit)
		end
		for _, unit in owned do
			if unit.stars < Stars.MAX then
				local copies = locate(self, unit.name, unit.stars)
				if #copies >= Stars.COPIES_TO_UPGRADE then
					local set = table.move(copies, 1, Stars.COPIES_TO_UPGRADE, 1, {})
					table.insert(upgrades, merge(set, unit.name, unit.stars))
					merged = true
					break
				end
			end
		end
	end
end

-- True if buying this 1-star unit would complete a set, so it needs no free slot.
function Roster.WouldUpgrade(self: Roster, name: string): boolean
	return #locate(self, name, 1) >= Stars.COPIES_TO_UPGRADE - 1
end

-- Add a newly bought unit: to the board if there's room, else the bench.
-- Caller must check HasSpace() or WouldUpgrade() first.
-- Returns any units that were created by star-ups.
function Roster.Add(self: Roster, unit: StarredUnit): { StarredUnit }
	local upgrades = {}
	local copies = locate(self, unit.name, unit.stars)
	if unit.stars < Stars.MAX and #copies >= Stars.COPIES_TO_UPGRADE - 1 then
		-- The new unit completes a set: merge it straight in instead of taking a slot.
		local set = table.move(copies, 1, Stars.COPIES_TO_UPGRADE - 1, 1, {})
		table.insert(upgrades, merge(set, unit.name, unit.stars))
	else
		local zone = if self.board:IsFull() then self.bench else self.board
		zone:Add(unit)
	end
	mergeAll(self, upgrades)
	return upgrades
end

-- Move a unit between board and bench. Returns false plus a reason on failure.
function Roster.Move(self: Roster, from: Zone, index: number): (boolean, string?)
	local source = self:GetZone(from)
	local destination = if from == "board" then self.bench else self.board
	local unit = source:Get(index)
	if not unit then
		return false, "that slot is empty"
	end
	if destination:IsFull() then
		return false, if from == "board" then "bench is full" else "board is full"
	end
	source:Remove(index)
	destination:Add(unit)
	return true, nil
end

function Roster.Sell(self: Roster, zone: Zone, index: number): StarredUnit?
	return self:GetZone(zone):Remove(index)
end

return Roster
