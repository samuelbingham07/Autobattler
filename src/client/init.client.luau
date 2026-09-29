-- Shop, board and bench UI. Draws whatever state the server sends and turns
-- button clicks into requests on the Action remote. No game logic lives here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Stars = require(Shared:WaitForChild("Stars"))
local Traits = require(Shared:WaitForChild("Traits"))
local Levels = require(Shared:WaitForChild("Levels"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("Action")
local stateRemote = remotes:WaitForChild("State")

local TIER_COLORS = {
	[1] = Color3.fromRGB(110, 110, 125),
	[2] = Color3.fromRGB(55, 145, 80),
	[3] = Color3.fromRGB(60, 105, 200),
}
local BOARD_COLOR = Color3.fromRGB(70, 130, 230)
local BENCH_COLOR = Color3.fromRGB(60, 85, 130)
local ACTION_COLOR = Color3.fromRGB(90, 90, 105)
local XP_COLOR = Color3.fromRGB(120, 80, 170)
local SELL_COLOR = Color3.fromRGB(190, 150, 40)
local FIGHT_COLOR = Color3.fromRGB(215, 115, 40)
local EMPTY_COLOR = Color3.fromRGB(45, 45, 55)
local ACTIVE_TRAIT_COLOR = Color3.fromRGB(140, 230, 150)
local INACTIVE_TRAIT_COLOR = Color3.fromRGB(170, 170, 180)

-- Client-only UI state
local lastState = nil
local selected = nil -- { zone = "board" | "bench", index = number } or nil

-- Layout -------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "AutobattlerUI"
gui.ResetOnSpawn = false -- keep the UI if your character respawns
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -12)
panel.Size = UDim2.fromOffset(880, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
panel.BackgroundTransparency = 0.15
panel.Parent = gui
Instance.new("UICorner").Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = panel

local panelLayout = Instance.new("UIListLayout")
panelLayout.Padding = UDim.new(0, 6)
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Parent = panel

local function makeLabel(order: number, height: number, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = panel
	return label
end

local function makeRow(order: number, height: number): Frame
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, height)
	row.BackgroundTransparency = 1
	row.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	return row
end

local statusLabel = makeLabel(1, 22, 16)
local messageLabel = makeLabel(2, 18, 14)
messageLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
local enemyLabel = makeLabel(3, 16, 13)
enemyLabel.TextColor3 = Color3.fromRGB(255, 140, 140)
local traitsLabel = makeLabel(4, 16, 13)
traitsLabel.TextWrapped = true
traitsLabel.AutomaticSize = Enum.AutomaticSize.Y -- grow to a second line if needed
makeLabel(5, 16, 13).Text = "BOARD (front to back, fights)"
local boardRow = makeRow(6, 48)
makeLabel(7, 16, 13).Text = "BENCH (storage, doesn't fight)"
local benchRow = makeRow(8, 44)
local actionRow = makeRow(9, 32)
local detailLabel = makeLabel(10, 16, 13)
detailLabel.TextColor3 = Color3.fromRGB(200, 210, 255)
detailLabel.TextWrapped = true
detailLabel.AutomaticSize = Enum.AutomaticSize.Y
local oddsLabel = makeLabel(11, 16, 13)
local shopRow = makeRow(12, 76)

-- Text helpers -------------------------------------------------------------

local function statLine(unit): string
	local dps = unit.damage * unit.attackSpeed
	return `{unit.health} HP · {string.format("%.0f", dps)} DPS`
end

local function abilityText(ability): string
	local power = ability.power
	if ability.kind == "healSelf" then
		return `heals itself for {power}`
	elseif ability.kind == "healAllies" then
		return `heals the whole team for {power}`
	elseif ability.kind == "damageAll" then
		return `hits every enemy for {power}`
	elseif ability.kind == "damageBack" then
		return `hits the back-most enemy for {power}`
	elseif ability.kind == "damageFront" then
		return `hits the front {ability.count or 1} enemies for {power}`
	end
	return ""
end

local function makeUnits(list)
	local units = {}
	for _, entry in list do
		table.insert(units, Stars.make(entry.name, entry.stars))
	end
	return units
end

local function unitNames(list): string
	local names = {}
	for _, unit in makeUnits(list) do
		table.insert(names, Stars.displayName(unit))
	end
	return table.concat(names, ", ")
end

local function traitsText(list): (string, boolean)
	local parts = {}
	local anyActive = false
	for _, info in Traits.summary(makeUnits(list)) do
		if info.active then
			anyActive = true
			table.insert(parts, `{info.name} {info.count}/{info.required} ✓ ({info.description})`)
		else
			table.insert(parts, `{info.name} {info.count}/{info.required}`)
		end
	end
	if #parts == 0 then
		return "Traits: none yet. Field 2 different units that share a trait.", false
	end
	return `Traits: {table.concat(parts, "   ·   ")}`, anyActive
end

-- Buttons ------------------------------------------------------------------

local function makeButton(
	row: Frame,
	width: number,
	text: string,
	color: Color3,
	enabled: boolean,
	onClick: () -> ()
): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, width, 1, 0)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = if enabled then 0 else 0.6
	button.AutoButtonColor = enabled
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextTransparency = if enabled then 0 else 0.4
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextWrapped = true
	button.Parent = row
	Instance.new("UICorner").Parent = button
	if enabled then
		button.Activated:Connect(onClick)
	end
	return button
end

local function clearButtons(row: Frame)
	for _, child in row:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
end

local render -- defined below; unit buttons call it to show a new selection

-- One row of owned units (board or bench).
-- Click a unit to select it. With a unit selected: click it again to deselect,
-- click another unit to swap the two, or click an empty slot on the other row
-- to move it there.
local function renderUnits(row: Frame, zone: string, list, size: number, width: number, color: Color3, planning: boolean)
	clearButtons(row)
	for index = 1, size do
		local entry = list[index]
		local isSelected = selected and selected.zone == zone and selected.index == index
		if entry then
			local unit = Stars.make(entry.name, entry.stars)
			local button = makeButton(row, width, `{Stars.displayName(unit)}\n{statLine(unit)}`, color, planning, function()
				if not selected then
					selected = { zone = zone, index = index }
					render(lastState)
				elseif isSelected then
					selected = nil
					render(lastState)
				else
					actionRemote:FireServer("swap", selected.zone, selected.index, zone, index)
				end
			end)
			if isSelected then
				local stroke = Instance.new("UIStroke")
				stroke.Color = Color3.new(1, 1, 1)
				stroke.Thickness = 3
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = button
			end
		else
			-- Units always fill from the front, so "move here" means "move to this row".
			local canMoveHere = planning and selected ~= nil and selected.zone ~= zone
			makeButton(row, width, if canMoveHere then "move here" else "empty", EMPTY_COLOR, canMoveHere, function()
				actionRemote:FireServer("move", selected.zone, selected.index)
			end)
		end
	end
end

local function renderActions(state, planning: boolean)
	clearButtons(actionRow)
	detailLabel.Text = ""

	if state.phase == "gameover" or state.phase == "won" then
		makeButton(actionRow, 200, "NEW RUN", FIGHT_COLOR, true, function()
			actionRemote:FireServer("newrun")
		end)
		return
	end

	local list = if selected then state[selected.zone] else nil
	local entry = if list then list[selected.index] else nil
	if not planning or not entry then
		makeButton(actionRow, 300, "Click a unit to select it", EMPTY_COLOR, false, function() end)
		return
	end

	local unit = Stars.make(entry.name, entry.stars)
	local ability = unit.ability
	detailLabel.Text = `{Stars.displayName(unit)}  [{table.concat(unit.traits, ", ")}]   {ability.name} ({ability.mana} mana): {abilityText(ability)}.`
		.. "   Click another unit to swap places."

	local zone, index = selected.zone, selected.index
	local moveText = if zone == "board" then "Move to bench" else "Move to board"
	makeButton(actionRow, 150, moveText, ACTION_COLOR, true, function()
		actionRemote:FireServer("move", zone, index)
	end)
	makeButton(actionRow, 150, `Sell (+{Stars.sellValue(unit)}g)`, SELL_COLOR, true, function()
		actionRemote:FireServer("sell", zone, index)
	end)
	makeButton(actionRow, 90, "Cancel", EMPTY_COLOR, true, function()
		selected = nil
		render(lastState)
	end)
end

local function renderShop(state, planning: boolean)
	local odds = Levels.shopOdds(state.level)
	local function percent(chance: number): string
		return `{math.round(chance * 100)}%` -- round away float noise like 55.00000000000001
	end
	oddsLabel.Text = `SHOP (click to buy)   ·   odds at level {state.level}: 1g {percent(odds[1])}  ·  2g {percent(odds[2])}  ·  3g {percent(odds[3])}`

	clearButtons(shopRow)
	for slot, name in state.offers do
		if name then
			local unit = Stars.make(name, 1)
			local button = makeButton(
				shopRow,
				100,
				`{name} ({unit.cost}g)\n{statLine(unit)}\n{table.concat(unit.traits, "/")}\n{unit.ability.name}`,
				TIER_COLORS[unit.cost],
				planning and state.gold >= unit.cost,
				function()
					actionRemote:FireServer("buy", slot)
				end
			)
			button.TextSize = 12
		else
			makeButton(shopRow, 100, "Sold", EMPTY_COLOR, false, function() end)
		end
	end

	makeButton(shopRow, 84, `Reroll\n{state.rerollCost}g`, ACTION_COLOR, planning and state.gold >= state.rerollCost, function()
		actionRemote:FireServer("reroll")
	end)
	local canLevel = state.xpToNext ~= false
	makeButton(
		shopRow,
		84,
		if canLevel then `Buy {Levels.XP_PER_BUY} XP\n{Levels.XP_BUY_COST}g` else "Max\nlevel",
		XP_COLOR,
		planning and canLevel and state.gold >= Levels.XP_BUY_COST,
		function()
			actionRemote:FireServer("buyxp")
		end
	)
	makeButton(shopRow, 96, "FIGHT", FIGHT_COLOR, planning and #state.board > 0, function()
		actionRemote:FireServer("fight")
	end)
end

-- Redraw everything from a server snapshot.
function render(state)
	local planning = state.phase == "planning"
	local phaseText = ({
		planning = "Planning",
		fighting = "Fighting...",
		gameover = "Game over",
		won = "Victory!",
	})[state.phase]
	local levelText = if state.xpToNext then `Level {state.level} ({state.xp}/{state.xpToNext} XP)` else `Level {state.level} (max)`
	local bestText = if state.best == 0
		then "none yet"
		elseif state.best > state.totalRounds then "won!"
		else `round {state.best}`

	statusLabel.Text = table.concat({
		`Round {state.round}/{state.totalRounds}`,
		`Health {state.health}`,
		`{state.gold} gold`,
		levelText,
		phaseText,
		`Best: {bestText}`,
	}, "  ·  ")
	messageLabel.Text = state.message
	enemyLabel.Text = `Enemy this round: {unitNames(state.enemy)}`

	local text, anyActive = traitsText(state.board)
	traitsLabel.Text = text
	traitsLabel.TextColor3 = if anyActive then ACTIVE_TRAIT_COLOR else INACTIVE_TRAIT_COLOR

	renderUnits(boardRow, "board", state.board, state.boardSize, 160, BOARD_COLOR, planning)
	renderUnits(benchRow, "bench", state.bench, state.benchSize, 140, BENCH_COLOR, planning)
	renderActions(state, planning)
	renderShop(state, planning)
end

stateRemote.OnClientEvent:Connect(function(state)
	-- Indexes can shift after any change (units move up to fill gaps), so drop the selection.
	selected = nil
	lastState = state
	render(state)
end)
actionRemote:FireServer("sync")
