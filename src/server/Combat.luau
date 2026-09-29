--!strict
-- Resolves a fight between two lists of units, instantly (no waiting).
-- Units always attack the front-most living enemy, so board slot 1 is your frontline.
--
-- Mana: units gain mana when they attack and when they're hit. On a unit's turn,
-- if its mana is full it casts its ability instead of attacking, then drops to 0.
--
-- Returns the result plus a list of every action, which Arena can replay.
-- Pass in units that already have trait bonuses applied (Traits.apply).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stars = require(ReplicatedStorage.Shared.Stars)
local Units = require(ReplicatedStorage.Shared.Units)

type Unit = Stars.StarredUnit

-- Seconds of simulated fight time before it's called a draw.
local TIME_LIMIT = 30
local MANA_PER_ATTACK = 10
local MANA_PER_HIT_TAKEN = 5

export type Result = "Victory" | "Defeat" | "Draw"
export type Side = "player" | "enemy"

-- One unit's state after being hit or healed.
export type Effect = {
	side: Side,
	index: number,
	heal: boolean,
	amount: number,
	health: number, -- after the effect
	mana: number, -- after the effect
}

-- One action: a basic attack or an ability cast. Indexes are positions in the
-- unit lists passed to Fight.
export type CombatEvent = {
	time: number,
	kind: "attack" | "cast",
	side: Side,
	index: number,
	abilityName: string?, -- set for casts
	mana: number, -- the acting unit's mana after acting
	effects: { Effect },
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
	interval: number, -- seconds between actions
	nextAction: number, -- simulated time of this unit's next action
	mana: number,
	ability: Units.Ability,
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
			nextAction = interval,
			mana = 0,
			ability = unit.ability,
		})
	end
	return fighters
end

local function alive(fighters: { Fighter }): { Fighter }
	local living = {}
	for _, fighter in fighters do
		if fighter.health > 0 then
			table.insert(living, fighter)
		end
	end
	return living
end

local function label(fighter: Fighter): string
	return `{SIDE_LABELS[fighter.side]} {fighter.name}`
end

local function snapshotEffect(target: Fighter, heal: boolean, amount: number): Effect
	return {
		side = target.side,
		index = target.index,
		heal = heal,
		amount = amount,
		health = target.health,
		mana = target.mana,
	}
end

local function hit(target: Fighter, amount: number): Effect
	target.health = math.max(0, target.health - amount)
	if target.health > 0 then
		target.mana = math.min(target.ability.mana, target.mana + MANA_PER_HIT_TAKEN)
	end
	return snapshotEffect(target, false, amount)
end

local function heal(target: Fighter, amount: number): Effect
	target.health = math.min(target.maxHealth, target.health + amount)
	return snapshotEffect(target, true, amount)
end

-- Work out who an ability affects and apply it.
local function cast(caster: Fighter, allies: { Fighter }, foes: { Fighter }): { Effect }
	local ability = caster.ability
	local livingFoes = alive(foes)
	local effects = {}

	if ability.kind == "healSelf" then
		table.insert(effects, heal(caster, ability.power))
	elseif ability.kind == "healAllies" then
		for _, ally in alive(allies) do
			table.insert(effects, heal(ally, ability.power))
		end
	elseif ability.kind == "damageAll" then
		for _, foe in livingFoes do
			table.insert(effects, hit(foe, ability.power))
		end
	elseif ability.kind == "damageBack" then
		table.insert(effects, hit(livingFoes[#livingFoes], ability.power))
	elseif ability.kind == "damageFront" then
		for i = 1, math.min(ability.count or 1, #livingFoes) do
			table.insert(effects, hit(livingFoes[i], ability.power))
		end
	end
	return effects
end

local function printEvent(event: CombatEvent, actor: Fighter, player: { Fighter }, enemy: { Fighter })
	local what = if event.kind == "cast" then `casts {event.abilityName}` else "attacks"
	print(`[{string.format("%5.2f", event.time)}s] {label(actor)} {what}`)
	for _, effect in event.effects do
		local target = (if effect.side == "player" then player else enemy)[effect.index]
		local verb = if effect.heal then "healed" else "hit"
		print(`    {label(target)} {verb} for {effect.amount} ({effect.health}/{target.maxHealth})`)
		if effect.health == 0 then
			print(`    {label(target)} dies`)
		end
	end
end

local function printSurvivors(fighters: { Fighter })
	for _, fighter in alive(fighters) do
		print(`  {label(fighter)} survives ({fighter.health}/{fighter.maxHealth})`)
	end
end

local Combat = {}

-- Pass verbose = false to print nothing (e.g. when Arena will replay the fight instead).
-- Returns the result, every action in order, and how many enemy units survived.
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
		local playerAlive = #alive(player) > 0
		local enemyAlive = #alive(enemy) > 0
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

		-- Whoever's next action comes soonest goes next. On a tie, your units go first.
		local actor: Fighter? = nil
		for _, fighter in alive(player) do
			if not actor or fighter.nextAction < actor.nextAction then
				actor = fighter
			end
		end
		for _, fighter in alive(enemy) do
			if not actor or fighter.nextAction < actor.nextAction then
				actor = fighter
			end
		end
		if not actor then
			break -- unreachable: both sides have a living unit
		end

		local time = actor.nextAction
		if time > TIME_LIMIT then
			if show then
				print(`Time limit ({TIME_LIMIT}s) reached`)
			end
			result = "Draw"
			break
		end

		local allies = if actor.side == "player" then player else enemy
		local foes = if actor.side == "player" then enemy else player

		local event: CombatEvent
		if actor.mana >= actor.ability.mana then
			actor.mana = 0
			local effects = cast(actor, allies, foes)
			event = {
				time = time,
				kind = "cast",
				side = actor.side,
				index = actor.index,
				abilityName = actor.ability.name,
				mana = actor.mana,
				effects = effects,
			}
		else
			local target = alive(foes)[1]
			local effect = hit(target, actor.damage)
			actor.mana = math.min(actor.ability.mana, actor.mana + MANA_PER_ATTACK)
			event = {
				time = time,
				kind = "attack",
				side = actor.side,
				index = actor.index,
				mana = actor.mana,
				effects = { effect },
			}
		end
		actor.nextAction += actor.interval
		table.insert(events, event)

		if show then
			printEvent(event, actor, player, enemy)
		end
	end

	if show then
		print(`--- Result: {result} ---`)
		printSurvivors(player)
		printSurvivors(enemy)
	end
	return result, events, #alive(enemy)
end

return Combat
