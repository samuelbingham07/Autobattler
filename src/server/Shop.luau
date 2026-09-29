--!strict
-- TFT-style shop: offers a row of random units, weighted by cost tier.
-- The tier odds depend on the player's level (see Levels).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Units = require(ReplicatedStorage.Shared.Units)
local Stars = require(ReplicatedStorage.Shared.Stars)
local Levels = require(ReplicatedStorage.Shared.Levels)

type Unit = Units.Unit
type StarredUnit = Stars.StarredUnit

local SHOP_SIZE = 5
local REROLL_COST = 2
local STARTING_GOLD = 10

-- Group units by cost once, so a roll can pick a tier and then a unit within it.
local unitsByCost: { [number]: { Unit } } = {}
for _, unit in Units do
	local tier = unitsByCost[unit.cost]
	if not tier then
		tier = {}
		unitsByCost[unit.cost] = tier
	end
	table.insert(tier, unit)
end

local Shop = {}
Shop.__index = Shop
Shop.SIZE = SHOP_SIZE
Shop.REROLL_COST = REROLL_COST

type ShopData = {
	gold: number,
	level: number, -- player level; sets the tier odds. Set it before rolling.
	offers: { [number]: Unit }, -- slot -> unit; nil once bought
	rng: Random,
}

export type Shop = typeof(setmetatable({} :: ShopData, Shop))

-- Pass a seed to get the same rolls every run (handy for testing).
function Shop.new(seed: number?): Shop
	local self = setmetatable({
		gold = STARTING_GOLD,
		level = 1,
		offers = {},
		rng = if seed then Random.new(seed) else Random.new(),
	}, Shop)
	self:Roll()
	return self
end

local function rollTier(rng: Random, odds: { number }): number
	local r = rng:NextNumber()
	local cumulative = 0
	for cost, chance in odds do
		cumulative += chance
		if r < cumulative then
			return cost
		end
	end
	return 1 -- float rounding fallback
end

-- Fill every slot with a fresh offer. Free; use Reroll to spend gold.
function Shop.Roll(self: Shop)
	local odds = Levels.shopOdds(self.level)
	for slot = 1, SHOP_SIZE do
		local tier = unitsByCost[rollTier(self.rng, odds)]
		self.offers[slot] = tier[self.rng:NextInteger(1, #tier)]
	end
end

-- Spend gold to roll a new shop. Returns false if you can't afford it.
function Shop.Reroll(self: Shop): boolean
	if self.gold < REROLL_COST then
		return false
	end
	self.gold -= REROLL_COST
	self:Roll()
	return true
end

-- Buy the unit in a slot. Returns a new 1-star unit, or nil plus a reason.
function Shop.Buy(self: Shop, slot: number): (StarredUnit?, string?)
	local offer = self.offers[slot]
	if not offer then
		return nil, "slot is empty"
	end
	if self.gold < offer.cost then
		return nil, "not enough gold"
	end
	self.gold -= offer.cost
	self.offers[slot] = nil
	return Stars.make(offer.name, 1), nil
end

function Shop.Print(self: Shop)
	local parts = {}
	for slot = 1, SHOP_SIZE do
		local offer = self.offers[slot]
		local label = if offer then `{offer.name} ({offer.cost}g)` else "(sold)"
		table.insert(parts, `[{slot}] {label}`)
	end
	print(`Shop | gold: {self.gold} | {table.concat(parts, "  ")}`)
end

return Shop
