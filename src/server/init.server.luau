-- Game loop: plan (buy/sell/move/reroll) -> fight this round's enemy -> repeat.
-- Lose rounds and you lose health; hit 0 and the run is over. Beat the last
-- round to win.
--
-- The server owns all game state. Clients only send requests through the Action
-- remote and draw whatever the State remote tells them.
--
-- Single-player: there is one game per server, shared by everyone in it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shop = require(script.Shop)
local Board = require(script.Board)
local Roster = require(script.Roster)
local Enemies = require(script.Enemies)
local Combat = require(script.Combat)
local Arena = require(script.Arena)
local Stars = require(ReplicatedStorage.Shared.Stars)

local STARTING_HEALTH = 20
local ROUND_INCOME = 5
-- Losing a round costs this much health, plus 1 per enemy unit still standing.
local LOSS_BASE_DAMAGE = 2

-- Remotes. Clients wait for these with WaitForChild.
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local actionRemote = Instance.new("RemoteEvent") -- client -> server: (action, ...)
actionRemote.Name = "Action"
actionRemote.Parent = remotes

local stateRemote = Instance.new("RemoteEvent") -- server -> client: state snapshot
stateRemote.Name = "State"
stateRemote.Parent = remotes

-- Game state. Set by newRun().
local shop
local roster
local round
local health
local phase -- "planning", "fighting", "gameover" or "won"
local message

local function describe(units)
	local list = {}
	for index, unit in units do
		list[index] = { name = unit.name, stars = unit.stars }
	end
	return list
end

-- Everything a client needs to draw the UI. Units are sent as name + stars;
-- the client rebuilds stats with the shared Stars module. Sold shop slots are
-- `false`, because nil holes don't survive being sent through a remote.
local function snapshot()
	local offers = {}
	for slot = 1, Shop.SIZE do
		local offer = shop.offers[slot]
		offers[slot] = if offer then offer.name else false
	end

	return {
		round = round,
		totalRounds = Enemies.COUNT,
		health = health,
		gold = shop.gold,
		phase = phase,
		message = message,
		offers = offers,
		board = describe(roster.board:GetUnits()),
		boardSize = Board.SIZE,
		bench = describe(roster.bench:GetUnits()),
		benchSize = Roster.BENCH_SIZE,
		enemy = describe(Enemies.forRound(round)),
		rerollCost = Shop.REROLL_COST,
	}
end

local function broadcast()
	stateRemote:FireAllClients(snapshot())
end

local function redraw()
	Arena.Render(roster.board:GetUnits(), Enemies.forRound(round))
end

local function newRun()
	shop = Shop.new()
	roster = Roster.new()
	round = 1
	health = STARTING_HEALTH
	phase = "planning"
	message = "Buy units, then press Fight. 3 copies make a 2-star!"
	redraw()
end

-- Never trust values from the client: check it's a whole number in range.
local function isIndex(value: any, max: number): boolean
	return typeof(value) == "number" and value % 1 == 0 and value >= 1 and value <= max
end

local function isZone(value: any): boolean
	return value == "board" or value == "bench"
end

local function zoneSize(zone: string): number
	return if zone == "board" then Board.SIZE else Roster.BENCH_SIZE
end

local function fight()
	local playerUnits = roster.board:GetUnits()
	if #playerUnits == 0 then
		message = "Put at least one unit on your board first"
		return
	end

	phase = "fighting"
	message = `Round {round}: fight!`
	broadcast()

	local enemyUnits = Enemies.forRound(round)
	local arenaView = Arena.Render(playerUnits, enemyUnits)
	local result, events, enemySurvivors = Combat.Fight(playerUnits, enemyUnits, false)
	task.wait(1)
	Arena.Replay(arenaView, events)
	print(`Round {round}: {result}`)

	if result == "Victory" then
		if round >= Enemies.COUNT then
			phase = "won"
			message = `You beat all {Enemies.COUNT} rounds with {health} health left. You win!`
			return
		end
		message = `Round {round}: Victory! +{ROUND_INCOME} gold`
	else
		local damage = LOSS_BASE_DAMAGE + enemySurvivors
		health = math.max(0, health - damage)
		if health == 0 then
			phase = "gameover"
			message = `Knocked out in round {round}. Game over.`
			return
		end
		message = `Round {round}: {result}. You lose {damage} health. +{ROUND_INCOME} gold`
	end
	broadcast()
	task.wait(2) -- let the result sink in before the board resets

	round += 1
	shop.gold += ROUND_INCOME
	shop:Roll() -- free new shop each round, like TFT
	phase = "planning"
	redraw()
end

local function buy(slot: number)
	local offer = shop.offers[slot]
	if offer and not roster:HasSpace() and not roster:WouldUpgrade(offer.name) then
		message = "Board and bench are full. Sell something first."
		return
	end
	local unit, err = shop:Buy(slot)
	if not unit then
		message = `Can't buy: {err}`
		return
	end
	local upgrades = roster:Add(unit)
	message = `Bought {unit.name}`
	for _, upgraded in upgrades do
		message ..= `  ->  {Stars.displayName(upgraded)}!`
	end
	redraw()
end

actionRemote.OnServerEvent:Connect(function(player, action, arg1, arg2)
	-- A client asks for the current state when its UI first loads.
	if action == "sync" then
		stateRemote:FireClient(player, snapshot())
		return
	end

	if action == "newrun" and (phase == "gameover" or phase == "won") then
		newRun()
		broadcast()
		return
	end

	if phase ~= "planning" then
		return
	end

	if action == "buy" and isIndex(arg1, Shop.SIZE) then
		buy(arg1)
	elseif action == "sell" and isZone(arg1) and isIndex(arg2, zoneSize(arg1)) then
		local unit = roster:Sell(arg1, arg2)
		if unit then
			local value = Stars.sellValue(unit)
			shop.gold += value
			message = `Sold {Stars.displayName(unit)} for {value} gold`
			redraw()
		end
	elseif action == "move" and isZone(arg1) and isIndex(arg2, zoneSize(arg1)) then
		local ok, err = roster:Move(arg1, arg2)
		message = if ok then "Moved" else `Can't move: {err}`
		redraw()
	elseif action == "reroll" then
		message = if shop:Reroll() then "Rerolled" else "Not enough gold to reroll"
	elseif action == "fight" then
		fight()
	else
		return -- unknown or malformed request
	end

	broadcast()
end)

newRun()
