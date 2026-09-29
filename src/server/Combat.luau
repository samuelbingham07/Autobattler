--!strict
-- Resolves a fight between two lists of units, instantly (no waiting).
-- Units always attack the front-most living enemy, so board slot 1 is your frontline.
-- Returns the result plus a list of every attack, which Arena can replay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stars = require(ReplicatedStorage.Shared.Stars)

type Unit = Stars.StarredUnit

-- Seconds of simulated fight time before it's called a draw.
local TIME_LIMIT = 30

export type Result = "Victory" | "Defeat" | "Draw"
export type Side = "player" | "enemy"

-- One attack. Indexes are positions in the unit lists passed to Fight.
export type CombatEvent = {
	time: number,
	attackerSide: Side,
	attackerIndex: number,
	targetSide: Side,
	targetIndex: number,
	damage: number,
	targetHealth: number, -- health left after the hit
}

local SIDE_LABELS: { [Side]: string } = {
	player = "Your",
	enemy = "Enemy",
}

-- Per-fight copy of a unit, so combat never touches the unit on your board.
type Fighter = {
	name: string,
	side: Side,
	index: number,
	health: number,
	maxHealth: number,
	damage: number,
	interval: number, -- seconds between attacks
	nextAttack: number, -- simulated time of this unit's next attack
}

local function makeFighters(units: { Unit }, side: Side): { Fighter }
	local fighters = {}
	for index, unit in units do
		local interval = 1 / unit.attackSpeed
		table.insert(fighters, {
			name = Stars.displayName(unit),
			side = side,
			index = index,
			health = unit.health,
			maxHealth = unit.health,
			damage = unit.damage,
			interval = interval,
			nextAttack = interval,
		})
	end
	return fighters
end

local function firstAlive(fighters: { Fighter }): Fighter?
	for _, fighter in fighters do
		if fighter.health > 0 then
			return fighter
		end
	end
	return nil
end

local function label(fighter: Fighter): string
	return `{SIDE_LABELS[fighter.side]} {fighter.name}`
end

local function printSurvivors(fighters: { Fighter })
	for _, fighter in fighters do
		if fighter.health > 0 then
			print(`  {label(fighter)} survives ({fighter.health}/{fighter.maxHealth})`)
		end
	end
end

local Combat = {}

-- Pass verbose = false to print nothing (e.g. when Arena will replay the fight instead).
-- Returns the result, every attack in order, and how many enemy units survived.
function Combat.Fight(
	playerUnits: { Unit },
	enemyUnits: { Unit },
	verbose: boolean?
): (Result, { CombatEvent }, number)
	local show = verbose ~= false
	local player = makeFighters(playerUnits, "player")
	local enemy = makeFighters(enemyUnits, "enemy")
	local events: { CombatEvent } = {}

	if show then
		print(`--- Combat: {#player} vs {#enemy} ---`)
	end

	local result: Result = "Draw"
	while true do
		local playerAlive = firstAlive(player) ~= nil
		local enemyAlive = firstAlive(enemy) ~= nil
		if not playerAlive and not enemyAlive then
			result = "Draw"
			break
		elseif not enemyAlive then
			result = "Victory"
			break
		elseif not playerAlive then
			result = "Defeat"
			break
		end

		-- Whoever's next attack comes soonest goes next. On a tie, your units go first.
		local attacker: Fighter? = nil
		local foes: { Fighter } = enemy
		for _, fighter in player do
			if fighter.health > 0 and (not attacker or fighter.nextAttack < attacker.nextAttack) then
				attacker = fighter
				foes = enemy
			end
		end
		for _, fighter in enemy do
			if fighter.health > 0 and (not attacker or fighter.nextAttack < attacker.nextAttack) then
				attacker = fighter
				foes = player
			end
		end
		local target = firstAlive(foes)
		if not attacker or not target then
			break -- unreachable: both sides have a living unit
		end

		local time = attacker.nextAttack
		if time > TIME_LIMIT then
			if show then
				print(`Time limit ({TIME_LIMIT}s) reached`)
			end
			result = "Draw"
			break
		end

		target.health = math.max(0, target.health - attacker.damage)
		attacker.nextAttack += attacker.interval

		table.insert(events, {
			time = time,
			attackerSide = attacker.side,
			attackerIndex = attacker.index,
			targetSide = target.side,
			targetIndex = target.index,
			damage = attacker.damage,
			targetHealth = target.health,
		})

		if show then
			print(
				`[{string.format("%5.2f", time)}s] {label(attacker)} hits {label(target)}`
					.. ` for {attacker.damage} ({target.health}/{target.maxHealth})`
			)
			if target.health == 0 then
				print(`  {label(target)} dies`)
			end
		end
	end

	if show then
		print(`--- Result: {result} ---`)
		printSurvivors(player)
		printSurvivors(enemy)
	end

	local enemySurvivors = 0
	for _, fighter in enemy do
		if fighter.health > 0 then
			enemySurvivors += 1
		end
	end
	return result, events, enemySurvivors
end

return Combat
