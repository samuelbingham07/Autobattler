--!strict
-- A row of unit slots. Used for both the board (fights) and the bench (storage).
-- Units fill slots from 1 with no gaps, so on the board slot order is always
-- front-to-back fighting order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stars = require(ReplicatedStorage.Shared.Stars)

type StarredUnit = Stars.StarredUnit

local Board = {}
Board.__index = Board

type BoardData = {
	size: number,
	slots: { StarredUnit },
}

export type Board = typeof(setmetatable({} :: BoardData, Board))

function Board.new(size: number): Board
	return setmetatable({ size = size, slots = {} }, Board)
end

function Board.IsFull(self: Board): boolean
	return #self.slots >= self.size
end

-- Grow the row (the board gains a slot on level-up). Never shrinks below its units.
function Board.SetSize(self: Board, size: number)
	self.size = math.max(size, #self.slots)
end

function Board.Get(self: Board, slot: number): StarredUnit?
	return self.slots[slot]
end

-- Replace the unit in an occupied slot.
function Board.Set(self: Board, slot: number, unit: StarredUnit)
	assert(self.slots[slot], `Slot {slot} is empty`)
	self.slots[slot] = unit
end

-- Put a unit in the first empty slot. Returns the slot, or nil if full.
function Board.Add(self: Board, unit: StarredUnit): number?
	if self:IsFull() then
		return nil
	end
	table.insert(self.slots, unit)
	return #self.slots
end

-- Take the unit out of a slot; units behind it move up to close the gap.
-- Returns the unit, or nil if the slot was empty.
function Board.Remove(self: Board, slot: number): StarredUnit?
	if not self.slots[slot] then
		return nil
	end
	return table.remove(self.slots, slot)
end

-- The units in slot order. A copy, so callers can't break the no-gaps rule.
function Board.GetUnits(self: Board): { StarredUnit }
	return table.clone(self.slots)
end

return Board
