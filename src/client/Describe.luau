-- Plain-language descriptions of units and abilities for the UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stars = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Stars"))

local Describe = {}

function Describe.ability(ability): string
	local power = ability.power
	if ability.kind == "healSelf" then
		return `Heals itself for {power}`
	elseif ability.kind == "healAllies" then
		return `Heals the whole team for {power}`
	elseif ability.kind == "damageAll" then
		return `Hits every enemy for {power}`
	elseif ability.kind == "damageBack" then
		return `Hits the enemy furthest back for {power}`
	elseif ability.kind == "damageFront" then
		return `Hits the front {ability.count or 1} enemies for {power}`
	end
	return ""
end

function Describe.dps(unit): number
	return math.round(unit.damage * unit.attackSpeed)
end

-- Multi-line tooltip text for a unit.
function Describe.tooltip(unit, forSale: boolean): string
	local ability = unit.ability
	local lines = {
		`{Stars.displayName(unit)}   ({unit.cost} gold)`,
		`{unit.health} health  ·  {unit.damage} damage  ·  {Describe.dps(unit)} DPS`,
		`Traits: {table.concat(unit.traits, ", ")}`,
		`{ability.name} ({ability.mana} mana): {Describe.ability(ability)}`,
	}
	if forSale then
		table.insert(lines, "Click to buy, or drag onto your team or bench.")
	else
		table.insert(lines, `Drag to rearrange. Drop on the shop to sell for {Stars.sellValue(unit)} gold.`)
	end
	return table.concat(lines, "\n")
end

return Describe
