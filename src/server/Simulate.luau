--!strict
-- Balance simulator: a simple bot plays many full runs using the real Game
-- logic, then prints how often it beats each round. Use it to tune unit stats,
-- enemy boards and the economy without playing dozens of runs by hand.
--
-- Run it from Studio's command bar (works without pressing Play):
--   require(game.ServerScriptService.Server.Simulate).run(200)
--
-- The bot is deliberately average: it buys pairs and upgrades, saves some
-- interest, levels on a schedule and puts its strongest units in, tanks in
-- front. A real player should do a bit better than it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = require(script.Parent.Game)
local Shop = require(script.Parent.Shop)
local Enemies = require(script.Parent.Enemies)
local Stars = require(ReplicatedStorage.Shared.Stars)
local Levels = require(ReplicatedStorage.Shared.Levels)

type StarredUnit = Stars.StarredUnit
type Game = Game.Game

local MAX_REROLLS_PER_ROUND = 3

-- Roughly how strong a unit is: the gold that went into it.
local function power(unit: StarredUnit): number
	return Stars.sellValue(unit)
end

local function isTank(unit: StarredUnit): boolean
	return table.find(unit.traits, "Guardian") ~= nil or unit.ability.kind == "healSelf"
end

local function owned(g: Game): { StarredUnit }
	local all = g.roster.board:GetUnits()
	for _, unit in g.roster.bench:GetUnits() do
		table.insert(all, unit)
	end
	return all
end

local function copiesOf(g: Game, name: string, stars: number): number
	local count = 0
	for _, unit in owned(g) do
		if unit.name == name and unit.stars == stars then
			count += 1
		end
	end
	return count
end

-- The level the bot aims for by each round.
local function targetLevel(round: number): number
	if round <= 2 then
		return 2
	elseif round <= 4 then
		return 3
	elseif round <= 7 then
		return 4
	end
	return 5
end

-- Keep a free bench slot by selling the weakest unit that isn't part of a pair.
local function sellJunk(g: Game)
	local bench = g.roster.bench
	while #bench:GetUnits() >= bench.size - 1 do
		local worstIndex, worstPower = nil, math.huge
		for index, unit in bench:GetUnits() do
			if copiesOf(g, unit.name, unit.stars) == 1 and power(unit) < worstPower then
				worstIndex, worstPower = index, power(unit)
			end
		end
		if not worstIndex then
			return
		end
		g:Sell("bench", worstIndex)
	end
end

-- Strongest units on the team, tanks in front, then by health.
-- The bot sets the rows directly; a player would drag units around.
local function arrange(g: Game)
	local all = owned(g)
	table.sort(all, function(a, b)
		return power(a) > power(b)
	end)
	local team, rest = {}, {}
	for index, unit in all do
		table.insert(if index <= g.roster.board.size then team else rest, unit)
	end
	table.sort(team, function(a, b)
		if isTank(a) ~= isTank(b) then
			return isTank(a)
		end
		return a.health > b.health
	end)
	g.roster.board.slots = team
	g.roster.bench.slots = rest
end

local function plan(g: Game)
	-- Save 10 gold for interest in the middle of the run; spend everything early and at the end.
	local reserve = if g.round <= 2 or g.round >= Enemies.COUNT - 1 then 0 else 10

	sellJunk(g)

	while g.level < targetLevel(g.round) and g.shop.gold - Levels.XP_BUY_COST >= reserve do
		if not g:BuyXp() then
			break
		end
	end

	local rerolls = 0
	while true do
		local bought = false
		for slot = 1, Shop.SIZE do
			local offer = g.shop.offers[slot]
			if offer and g.shop.gold >= offer.cost then
				local upgrade = g.roster:WouldUpgrade(offer.name)
				local pair = copiesOf(g, offer.name, 1) > 0
				local keepsReserve = g.shop.gold - offer.cost >= reserve
				local hasSpace = g.roster:HasSpace() or upgrade
				if hasSpace and (upgrade or pair or keepsReserve) then
					if g:Buy(slot) then
						bought = true
					end
				end
			end
		end
		if not bought then
			local canReroll = rerolls < MAX_REROLLS_PER_ROUND
				and g.round >= 4
				and g.shop.gold - Shop.REROLL_COST >= reserve
			if canReroll then
				g:Reroll()
				rerolls += 1
			else
				break
			end
		end
	end

	arrange(g)
end

local Simulate = {}

function Simulate.run(runs: number?, seed: number?)
	local runCount = runs or 200
	local baseSeed = seed or 1
	local rounds = Enemies.COUNT

	local reached, wins, levelSum, goldSum = {}, {}, {}, {}
	for round = 1, rounds do
		reached[round], wins[round], levelSum[round], goldSum[round] = 0, 0, 0, 0
	end
	local runsWon, healthLeftSum = 0, 0

	local started = os.clock()
	for run = 1, runCount do
		local g = Game.new(baseSeed + run)
		while g.phase == "planning" do
			plan(g)
			local round = g.round
			reached[round] += 1
			levelSum[round] += g.level
			goldSum[round] += g.shop.gold

			local fight = g:StartFight()
			if not fight then
				break
			end
			if fight.result == "Victory" then
				wins[round] += 1
			end
			g:FinishFight(fight)
			if g.phase == "fighting" then
				g:NextRound()
			end
		end
		if g.phase == "won" then
			runsWon += 1
			healthLeftSum += g.health
		end
	end

	print(`=== Balance sim: {runCount} runs in {string.format("%.1f", os.clock() - started)}s ===`)
	print(`Runs won: {runsWon} ({math.round(runsWon / runCount * 100)}%)`
		.. if runsWon > 0 then `, avg health left {math.round(healthLeftSum / runsWon)}` else "")
	print("Round | reached | win rate | avg level | avg gold after buying")
	for round = 1, rounds do
		local n = reached[round]
		if n == 0 then
			print(string.format("%5d | %7d |        - |", round, 0))
		else
			local rate = wins[round] / n * 100
			local note = if rate < 35 then "  <- hard" elseif rate > 95 then "  <- easy" else ""
			print(string.format(
				"%5d | %7d | %7.0f%% | %9.1f | %5.1f%s",
				round,
				n,
				rate,
				levelSum[round] / n,
				goldSum[round] / n,
				note
			))
		end
	end
end

return Simulate
