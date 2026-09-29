--!strict
-- One player's run, as pure game logic: shop, roster, gold, health, level,
-- rounds. No 3D, remotes or saving, so the balance simulator can drive it
-- exactly the way a real player's Session does.
--
-- A round goes: planning actions -> StartFight -> FinishFight -> NextRound.
-- Actions set `message` to tell the player what happened.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shop = require(script.Parent.Shop)
local Roster = require(script.Parent.Roster)
local Enemies = require(script.Parent.Enemies)
local Combat = require(script.Parent.Combat)
local Stars = require(ReplicatedStorage.Shared.Stars)
local Traits = require(ReplicatedStorage.Shared.Traits)
local Levels = require(ReplicatedStorage.Shared.Levels)
local Economy = require(ReplicatedStorage.Shared.Economy)

type StarredUnit = Stars.StarredUnit

local STARTING_HEALTH = 20
-- Losing a round costs this much health, plus 1 per enemy unit still standing.
local LOSS_BASE_DAMAGE = 2

export type Phase = "planning" | "fighting" | "gameover" | "won"

export type Fight = {
	playerUnits: { StarredUnit }, -- with trait bonuses, as they fought
	enemyUnits: { StarredUnit },
	result: Combat.Result,
	events: { Combat.CombatEvent },
	enemySurvivors: number,
}

local Game = {}
Game.__index = Game
Game.STARTING_HEALTH = STARTING_HEALTH

type GameData = {
	shop: Shop.Shop,
	roster: Roster.Roster,
	round: number,
	health: number,
	level: number,
	xp: number,
	streak: number, -- +N for N wins in a row, -N for N losses in a row
	phase: Phase,
	message: string,
}

export type Game = typeof(setmetatable({} :: GameData, Game))

-- Pass a seed for repeatable shops (the simulator uses this).
function Game.new(seed: number?): Game
	return setmetatable({
		shop = Shop.new(seed),
		roster = Roster.new(Levels.boardSize(1)),
		round = 1,
		health = STARTING_HEALTH,
		level = 1,
		xp = 0,
		streak = 0,
		phase = "planning" :: Phase,
		message = "Drag units from the shop onto your team, then press Fight!",
	}, Game)
end

-- Trait-buffed copies of both teams, as they'd fight right now.
function Game.Teams(self: Game): ({ StarredUnit }, { StarredUnit })
	return Traits.apply(self.roster.board:GetUnits()), Traits.apply(Enemies.forRound(self.round))
end

-- Add XP and level up as many times as it covers. Returns true if the level went up.
function Game.GainXp(self: Game, amount: number): boolean
	local leveled = false
	self.xp += amount
	local needed = Levels.xpToNext(self.level)
	while needed and self.xp >= needed do
		self.xp -= needed
		self.level += 1
		leveled = true
		needed = Levels.xpToNext(self.level)
	end
	if not needed then
		self.xp = 0 -- max level
	end
	if leveled then
		self.roster.board:SetSize(Levels.boardSize(self.level))
		self.shop.level = self.level
	end
	return leveled
end

-- Planning actions ---------------------------------------------------------
-- Each returns true if something changed, and sets `message` either way.

-- Buy a shop slot. If `zone` is given (the player dropped it on the board or
-- bench), try to put it there; otherwise board first, then bench.
function Game.Buy(self: Game, slot: number, zone: Roster.Zone?): boolean
	local offer = self.shop.offers[slot]
	if offer and not self.roster:HasSpace() and not self.roster:WouldUpgrade(offer.name) then
		self.message = "Your team and bench are full. Sell a unit first."
		return false
	end
	local unit, err = self.shop:Buy(slot)
	if not unit then
		self.message = `Can't buy: {err}`
		return false
	end
	local upgrades = self.roster:Add(unit, zone)
	self.message = `Bought {unit.name}`
	for _, upgraded in upgrades do
		self.message ..= `  ->  {Stars.displayName(upgraded)}!`
	end
	return true
end

function Game.Sell(self: Game, zone: Roster.Zone, index: number): boolean
	local unit = self.roster:Sell(zone, index)
	if not unit then
		return false
	end
	local value = Stars.sellValue(unit)
	self.shop.gold += value
	self.message = `Sold {Stars.displayName(unit)} for {value} gold`
	return true
end

function Game.Move(self: Game, zone: Roster.Zone, index: number): boolean
	local ok, err = self.roster:Move(zone, index)
	self.message = if ok then "Moved" else `Can't move: {err}`
	return ok
end

function Game.Swap(self: Game, zoneA: Roster.Zone, indexA: number, zoneB: Roster.Zone, indexB: number): boolean
	local ok, err = self.roster:Swap(zoneA, indexA, zoneB, indexB)
	self.message = if ok then "Swapped" else `Can't swap: {err}`
	return ok
end

function Game.Reroll(self: Game): boolean
	local ok = self.shop:Reroll()
	self.message = if ok then "Rerolled the shop" else "Not enough gold to reroll"
	return ok
end

function Game.BuyXp(self: Game): boolean
	if not Levels.xpToNext(self.level) then
		self.message = "Already at max level"
		return false
	elseif self.shop.gold < Levels.XP_BUY_COST then
		self.message = "Not enough gold to buy XP"
		return false
	end
	self.shop.gold -= Levels.XP_BUY_COST
	if self:GainXp(Levels.XP_PER_BUY) then
		self.message = `Level {self.level}! Your team can have {self.roster.board.size} units now.`
	else
		self.message = `+{Levels.XP_PER_BUY} XP`
	end
	return true
end

-- Rounds -------------------------------------------------------------------

-- Resolve this round's fight. Returns nil (and sets message) if you have no team.
-- The result is decided here; FinishFight applies it once the replay is shown.
function Game.StartFight(self: Game): Fight?
	if #self.roster.board:GetUnits() == 0 then
		self.message = "Put at least one unit on your team first"
		return nil
	end
	self.phase = "fighting"
	self.message = `Round {self.round}: fight!`

	local playerUnits, enemyUnits = self:Teams()
	local result, events, enemySurvivors = Combat.Fight(playerUnits, enemyUnits, false)
	return {
		playerUnits = playerUnits,
		enemyUnits = enemyUnits,
		result = result,
		events = events,
		enemySurvivors = enemySurvivors,
	}
end

-- Apply a fight's result: health, streak, and whether the run is over.
function Game.FinishFight(self: Game, fight: Fight)
	if fight.result == "Victory" then
		self.streak = math.max(self.streak, 0) + 1
		if self.round >= Enemies.COUNT then
			self.phase = "won"
			self.message = `You beat all {Enemies.COUNT} rounds with {self.health} health left. You win!`
			return
		end
		self.message = `Round {self.round}: Victory!`
	else
		self.streak = math.min(self.streak, 0) - 1
		local damage = LOSS_BASE_DAMAGE + fight.enemySurvivors
		self.health = math.max(0, self.health - damage)
		if self.health == 0 then
			self.phase = "gameover"
			self.message = `Knocked out in round {self.round}. Game over.`
			return
		end
		self.message = `Round {self.round}: {fight.result}. You lose {damage} health.`
	end
end

-- Move on to the next round: income, XP, a fresh shop. Only after FinishFight
-- left the run going.
function Game.NextRound(self: Game)
	local income = Economy.income(self.shop.gold, self.streak)
	self.shop.gold += income.total
	self.message ..= `  +{income.total} gold ({income.base} base`
	if income.interest > 0 then
		self.message ..= ` + {income.interest} interest`
	end
	if income.streak > 0 then
		self.message ..= ` + {income.streak} streak`
	end
	self.message ..= ")"

	self.round += 1
	if self:GainXp(Levels.XP_PER_ROUND) then
		self.message ..= `  Level {self.level}!`
	end
	self.shop:Roll() -- free new shop each round, like TFT
	self.phase = "planning"
end

-- The run's result as one number, for saving bests:
-- the round it ended on, or rounds + 1 for a full win.
function Game.Score(self: Game): number
	return if self.phase == "won" then Enemies.COUNT + 1 else self.round
end

-- Everything a client needs to draw the UI. Units are sent as name + stars;
-- the client rebuilds stats, traits and abilities with the shared modules.
-- Sold shop slots and "no next level" are `false`, because nil doesn't
-- survive being sent through a remote inside a table.
function Game.Snapshot(self: Game)
	local function describe(units: { StarredUnit })
		local list = {}
		for index, unit in units do
			list[index] = { name = unit.name, stars = unit.stars }
		end
		return list
	end

	local offers = {}
	for slot = 1, Shop.SIZE do
		local offer = self.shop.offers[slot]
		offers[slot] = if offer then offer.name else false
	end

	return {
		round = self.round,
		totalRounds = Enemies.COUNT,
		health = self.health,
		maxHealth = STARTING_HEALTH,
		gold = self.shop.gold,
		streak = self.streak,
		level = self.level,
		xp = self.xp,
		xpToNext = Levels.xpToNext(self.level) or false,
		phase = self.phase,
		message = self.message,
		offers = offers,
		board = describe(self.roster.board:GetUnits()),
		boardSize = self.roster.board.size,
		bench = describe(self.roster.bench:GetUnits()),
		benchSize = self.roster.bench.size,
		enemy = describe(Enemies.forRound(self.round)),
		rerollCost = Shop.REROLL_COST,
	}
end

return Game
