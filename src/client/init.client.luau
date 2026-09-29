-- Game UI. Draws whatever state the server sends and turns clicks and drags
-- into requests on the Action remote. No game rules live here.
--
-- Layout:
--   top bar      round, health, gold, level, streak, help
--   right panel  enemy this round, your traits, leaderboard
--   bottom panel your team, bench, shop (drag and drop between them)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Stars = require(Shared:WaitForChild("Stars"))
local Traits = require(Shared:WaitForChild("Traits"))
local Levels = require(Shared:WaitForChild("Levels"))
local Economy = require(Shared:WaitForChild("Economy"))
local Widgets = require(script.Widgets)
local Describe = require(script.Describe)
local Drag = require(script.Drag)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("Action")
local stateRemote = remotes:WaitForChild("State")

local C = Widgets.COLORS
local create = Widgets.create
local localPlayer = Players.LocalPlayer

local PANEL_WIDTH = 900
local INNER_WIDTH = PANEL_WIDTH - 20
local SHOP_CARD_WIDTH = 124

local lastState = nil
local helpSeen = false

local gui = create("ScreenGui", {
	Name = "AutobattlerUI",
	ResetOnSpawn = false, -- keep the UI if your character respawns
	Parent = localPlayer:WaitForChild("PlayerGui"),
})

local function send(...)
	actionRemote:FireServer(...)
end

-- Top bar ------------------------------------------------------------------

local topBar = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(0, 48),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Parent = gui,
})
Widgets.list(topBar, true, 8, true)

-- A rounded box with a title and either a small subtitle (sub) or a progress bar (fill).
local function pill(order: number, width: number, withBar: boolean)
	local frame = create("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(width, 48),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		Parent = topBar,
	})
	Widgets.corner(frame)
	local title = Widgets.label(frame, "", 15, {
		Position = UDim2.fromOffset(10, 5),
		Size = UDim2.new(1, -20, 0, 20),
	})
	if withBar then
		local bar = create("Frame", {
			Position = UDim2.new(0, 10, 1, -16),
			Size = UDim2.new(1, -20, 0, 8),
			BackgroundColor3 = Color3.fromRGB(50, 52, 62),
			BorderSizePixel = 0,
			Parent = frame,
		})
		Widgets.corner(bar, 4)
		local fill = create("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = bar })
		Widgets.corner(fill, 4)
		return { title = title, fill = fill }
	end
	local sub = Widgets.label(frame, "", 12, {
		Position = UDim2.fromOffset(10, 25),
		Size = UDim2.new(1, -20, 0, 16),
		TextColor3 = C.muted,
		Font = Enum.Font.Gotham,
	})
	return { title = title, sub = sub }
end

local roundPill = pill(1, 140, false)
local healthPill = pill(2, 170, true)
local goldPill = pill(3, 190, false)
local levelPill = pill(4, 180, true)
local streakPill = pill(5, 150, false)

local helpFrame -- defined below
local helpButton = Widgets.button(topBar, "?", C.button, UDim2.fromOffset(48, 48), true, function()
	helpFrame.Visible = not helpFrame.Visible
end)
helpButton.LayoutOrder = 6
helpButton.TextSize = 22

-- Right panel --------------------------------------------------------------

local sidePanel = create("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 64),
	Size = UDim2.fromOffset(250, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = C.panel,
	BackgroundTransparency = 0.1,
	Parent = gui,
})
Widgets.corner(sidePanel)
Widgets.padding(sidePanel, 10)
Widgets.list(sidePanel, false, 4)

-- A titled section whose content is rebuilt on every update.
local function section(order: number, title: string): Frame
	Widgets.label(sidePanel, title, 12, { LayoutOrder = order * 2 - 1, TextColor3 = C.muted })
	local content = create("Frame", {
		LayoutOrder = order * 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = sidePanel,
	})
	Widgets.list(content, false, 2)
	return content
end

local enemySection = section(1, "ENEMY THIS ROUND")
local traitsSection = section(2, "YOUR TRAITS")
local leaderboardSection = section(3, "LEADERBOARD")

-- Bottom panel -------------------------------------------------------------

local bottom = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(PANEL_WIDTH, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = C.panel,
	BackgroundTransparency = 0.1,
	Parent = gui,
})
Widgets.corner(bottom, 10)
Widgets.padding(bottom, 10)
Widgets.list(bottom, false, 5)

local messageLabel = Widgets.label(bottom, "", 15, {
	LayoutOrder = 1,
	TextColor3 = C.accent,
	TextXAlignment = Enum.TextXAlignment.Center,
})

-- A row of cards with an outline that lights up while dragging.
local function cardRow(order: number, height: number): (Frame, UIStroke)
	local row = create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	Widgets.list(row, true, 8)
	local glow = Widgets.stroke(row, C.accent, 2)
	glow.Transparency = 1
	return row, glow
end

Widgets.label(bottom, "YOUR TEAM  ·  these fight, front (left) to back (right)", 12, { LayoutOrder = 2, TextColor3 = C.muted })
local teamRow, teamGlow = cardRow(3, 64)
Widgets.label(bottom, "BENCH  ·  spare units, they don't fight", 12, { LayoutOrder = 4, TextColor3 = C.muted })
local benchRow, benchGlow = cardRow(5, 58)
local shopHeader = Widgets.label(bottom, "", 12, { LayoutOrder = 6, TextColor3 = C.muted })

-- The shop area holds the cards and buttons, with a "sell" overlay on top
-- that appears while you drag one of your units.
local shopWrap = create("Frame", {
	LayoutOrder = 7,
	Size = UDim2.new(1, 0, 0, 88),
	BackgroundTransparency = 1,
	Parent = bottom,
})
local shopCards = create("Frame", {
	Size = UDim2.new(0, 5 * SHOP_CARD_WIDTH + 4 * 8, 1, 0),
	BackgroundTransparency = 1,
	Parent = shopWrap,
})
Widgets.list(shopCards, true, 8)
local shopButtons = create("Frame", {
	Position = UDim2.new(0, 5 * SHOP_CARD_WIDTH + 5 * 8, 0, 0),
	Size = UDim2.new(1, -(5 * SHOP_CARD_WIDTH + 5 * 8), 1, 0),
	BackgroundTransparency = 1,
	Parent = shopWrap,
})
local sellOverlay = create("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(120, 40, 40),
	BackgroundTransparency = 0.1,
	Text = "",
	TextColor3 = C.text,
	TextSize = 20,
	Font = Enum.Font.GothamBold,
	Visible = false,
	ZIndex = 10,
	Parent = shopWrap,
})
Widgets.corner(sellOverlay)

-- Tooltip ------------------------------------------------------------------

local tooltip = create("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Size = UDim2.fromOffset(320, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = Color3.fromRGB(15, 16, 22),
	BackgroundTransparency = 0.05,
	Visible = false,
	ZIndex = 50,
	Parent = gui,
})
Widgets.corner(tooltip)
Widgets.padding(tooltip, 8)
Widgets.stroke(tooltip, C.muted, 1)
local tooltipLabel = Widgets.label(tooltip, "", 13, {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Font = Enum.Font.Gotham,
	ZIndex = 51,
})

local function showTooltip(anchor: GuiObject, text: string)
	tooltipLabel.Text = text
	local x = math.min(anchor.AbsolutePosition.X, gui.AbsoluteSize.X - 330)
	tooltip.Position = UDim2.fromOffset(x, anchor.AbsolutePosition.Y - 6)
	tooltip.Visible = true
end

local function hideTooltip()
	tooltip.Visible = false
end

-- Help and end-of-run overlays ---------------------------------------------

local function centeredPanel(width: number): Frame
	local frame = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	Widgets.corner(frame, 12)
	Widgets.padding(frame, 18)
	Widgets.stroke(frame, C.accent, 2)
	Widgets.list(frame, false, 8)
	return frame
end

helpFrame = centeredPanel(560)
Widgets.label(helpFrame, "How to play", 22, { LayoutOrder = 1, ZIndex = 21 })
Widgets.label(helpFrame, table.concat({
	"•  Buy units: click a shop card, or drag it onto your Team or Bench.",
	"•  Your Team fights; the Bench is storage. Drag units onto each other to swap them.",
	"•  Sell a unit by dragging it onto the shop.",
	"•  3 copies of the same unit combine into a stronger ★★ version.",
	"•  Units that share a trait give bonuses. See Your Traits, top right.",
	"•  Units fill their blue mana bar by attacking and cast their ability when it's full.",
	"•  Press FIGHT. Losing costs health. Survive all 12 rounds to win!",
	"•  Gold: +5 each round, +1 per 10 gold you save (up to 5), and streak bonuses.",
	"•  Buy XP to level up: more team slots and better shop odds.",
	"•  Hover over any unit to see what it does.",
}, "\n"), 15, {
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Font = Enum.Font.Gotham,
	ZIndex = 21,
})
local helpClose = Widgets.button(helpFrame, "Got it", C.fight, UDim2.fromOffset(140, 40), true, function()
	helpFrame.Visible = false
end)
helpClose.LayoutOrder = 3
helpClose.ZIndex = 21

local endFrame = centeredPanel(440)
local endTitle = Widgets.label(endFrame, "", 28, { LayoutOrder = 1, ZIndex = 21, TextXAlignment = Enum.TextXAlignment.Center })
local endMessage = Widgets.label(endFrame, "", 15, {
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 21,
})
local endButton = Widgets.button(endFrame, "New run", C.fight, UDim2.new(1, 0, 0, 44), true, function()
	send("newrun")
end)
endButton.LayoutOrder = 3
endButton.ZIndex = 21

-- Cards --------------------------------------------------------------------

-- A unit card: name and stars, stats, traits (and ability, if tall enough).
local function unitCard(parent: Instance, unit, width: number, height: number, order: number, forSale: boolean, dim: boolean): TextButton
	local tierColor = Widgets.TIER_COLORS[unit.cost]
	local card = create("TextButton", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = C.card,
		BackgroundTransparency = if dim then 0.5 else 0,
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	})
	Widgets.corner(card)
	Widgets.stroke(card, tierColor, 2)

	local textTransparency = if dim then 0.5 else 0
	local function line(y: number, text: string, size: number, color: Color3)
		Widgets.label(card, text, size, {
			Position = UDim2.fromOffset(8, y),
			Size = UDim2.new(1, -16, 0, size + 3),
			TextColor3 = color,
			TextTransparency = textTransparency,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = if size >= 14 then Enum.Font.GothamBold else Enum.Font.Gotham,
		})
	end

	line(4, Stars.displayName(unit), 14, C.text)
	line(22, `{unit.health} HP · {Describe.dps(unit)} DPS`, 11, C.muted)
	line(37, table.concat(unit.traits, " · "), 11, tierColor)
	if height >= 80 then
		line(52, unit.ability.name, 11, C.text)
		line(67, `{unit.cost} gold`, 12, C.gold)
	end

	card.MouseEnter:Connect(function()
		card.BackgroundColor3 = C.cardHover
		showTooltip(card, Describe.tooltip(unit, forSale))
	end)
	card.MouseLeave:Connect(function()
		card.BackgroundColor3 = C.card
		hideTooltip()
	end)
	return card
end

local function emptySlot(parent: Instance, width: number, height: number, order: number, text: string): Frame
	local slot = create("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = C.empty,
		BackgroundTransparency = 0.3,
		Parent = parent,
	})
	Widgets.corner(slot)
	Widgets.stroke(slot, Color3.fromRGB(70, 72, 85), 1)
	Widgets.label(slot, text, 12, {
		Size = UDim2.fromScale(1, 1),
		TextColor3 = C.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.Gotham,
	})
	return slot
end

-- Drag and drop ------------------------------------------------------------
-- Sources: { kind = "shop", slot } or { kind = "unit", zone, index }
-- Targets: { kind = "slot", zone, index, occupied } / { kind = "row", zone } / { kind = "sell" }

local unitCards: { [string]: TextButton } = {}
local render -- defined below; drag handlers need it
local renderWaiting = false -- a state update arrived mid-drag

local drag = Drag.new(gui, {
	onClick = function(source)
		if source.kind == "shop" then
			send("buy", source.slot)
		else
			-- Tapping a unit shows its details (touch screens have no hover).
			local card = unitCards[`{source.zone}:{source.index}`]
			local entry = lastState and lastState[source.zone][source.index]
			if card and entry then
				showTooltip(card, Describe.tooltip(Stars.make(entry.name, entry.stars), false))
			end
		end
	end,

	onDrop = function(source, target)
		if source.kind == "shop" then
			if target.kind == "slot" or target.kind == "row" then
				send("buy", source.slot, target.zone)
			end
			return
		end
		if target.kind == "sell" then
			send("sell", source.zone, source.index)
		elseif target.kind == "slot" and target.occupied then
			if target.zone ~= source.zone or target.index ~= source.index then
				send("swap", source.zone, source.index, target.zone, target.index)
			end
		elseif target.zone ~= source.zone then
			-- Empty slot or open space on the other row: move there.
			send("move", source.zone, source.index)
		end
	end,

	onDragStart = function(source)
		hideTooltip()
		teamGlow.Transparency = 0
		benchGlow.Transparency = 0
		if source.kind == "unit" and lastState then
			local entry = lastState[source.zone][source.index]
			if entry then
				local value = Stars.sellValue(Stars.make(entry.name, entry.stars))
				sellOverlay.Text = `Drop here to sell for {value} gold`
				sellOverlay.Visible = true
			end
		end
	end,

	onDragEnd = function()
		teamGlow.Transparency = 1
		benchGlow.Transparency = 1
		sellOverlay.Visible = false
		if renderWaiting then
			renderWaiting = false
			task.defer(render, lastState)
		end
	end,
})

-- Rendering ----------------------------------------------------------------

local function scoreText(score: number, totalRounds: number): string
	if score <= 0 then
		return "-"
	elseif score > totalRounds then
		return "Won!"
	end
	return `Round {score}`
end

local function renderTop(state)
	roundPill.title.Text = `Round {state.round} / {state.totalRounds}`
	roundPill.sub.Text = if state.phase == "fighting" then "Fighting..." else "Survive them all to win"

	local healthFraction = state.health / state.maxHealth
	healthPill.title.Text = `Health {state.health} / {state.maxHealth}`
	healthPill.fill.Size = UDim2.fromScale(healthFraction, 1)
	healthPill.fill.BackgroundColor3 = C.bad:Lerp(C.good, healthFraction)

	local income = Economy.income(state.gold, state.streak)
	goldPill.title.Text = `{state.gold} gold`
	goldPill.title.TextColor3 = C.gold
	local incomeText = `+{income.total} next round`
	if income.interest > 0 then
		incomeText ..= ` ({income.interest} interest)`
	end
	goldPill.sub.Text = incomeText

	local levelFill = levelPill.fill
	levelFill.BackgroundColor3 = C.xp
	if state.xpToNext then
		levelPill.title.Text = `Level {state.level}  ·  {state.xp}/{state.xpToNext} XP`
		levelFill.Size = UDim2.fromScale(state.xp / state.xpToNext, 1)
	else
		levelPill.title.Text = `Level {state.level} (max)`
		levelFill.Size = UDim2.fromScale(1, 1)
	end

	local streak = state.streak
	local bonus = Economy.streakBonus(streak)
	streakPill.title.Text = if streak > 0 then `Win streak {streak}` elseif streak < 0 then `Loss streak {-streak}` else "No streak"
	streakPill.title.TextColor3 = if streak > 0 then C.good elseif streak < 0 then C.bad else C.text
	streakPill.sub.Text = if bonus > 0 then `+{bonus} bonus gold` else "2+ in a row: bonus gold"
end

local function renderSide(state)
	Widgets.clear(enemySection)
	for _, entry in state.enemy do
		local unit = Stars.make(entry.name, entry.stars)
		Widgets.label(enemySection, Stars.displayName(unit), 13, { TextColor3 = Widgets.TIER_COLORS[unit.cost] })
	end

	Widgets.clear(traitsSection)
	local units = {}
	for _, entry in state.board do
		table.insert(units, Stars.make(entry.name, entry.stars))
	end
	local summary = Traits.summary(units)
	if #summary == 0 then
		Widgets.label(traitsSection, "Put 2 different units that share a trait on your team for a bonus.", 12, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextColor3 = C.muted,
			Font = Enum.Font.Gotham,
		})
	end
	for _, info in summary do
		local active = info.activeTier > 0
		local target = info.nextCount or info.tiers[#info.tiers].count
		Widgets.label(traitsSection, `{info.name}  {info.count} / {target}`, 14, {
			TextColor3 = if active then C.good else C.text,
		})
		local detail
		if active then
			detail = info.tiers[info.activeTier].description
			if info.nextCount then
				detail ..= `  (next at {info.nextCount})`
			end
		else
			detail = `At {info.nextCount}: {info.tiers[1].description}`
		end
		Widgets.label(traitsSection, detail, 11, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextColor3 = if active then C.text else C.muted,
			Font = Enum.Font.Gotham,
		})
	end

	Widgets.clear(leaderboardSection)
	Widgets.label(leaderboardSection, `Your best: {scoreText(state.best, state.totalRounds)}`, 13, { TextColor3 = C.accent })
	if #state.leaderboard == 0 then
		Widgets.label(leaderboardSection, "No results yet. Finish a run!", 12, { TextColor3 = C.muted, Font = Enum.Font.Gotham })
	end
	for rank, entry in state.leaderboard do
		local isMe = entry.name == localPlayer.Name
		Widgets.label(leaderboardSection, `{rank}. {entry.name}   {scoreText(entry.score, state.totalRounds)}`, 12, {
			TextColor3 = if isMe then C.accent else C.text,
			Font = if isMe then Enum.Font.GothamBold else Enum.Font.Gotham,
		})
	end
end

-- Draw one row of owned units and collect its drop targets.
local function renderOwned(row: Frame, zone: string, list, size: number, height: number, planning: boolean, targets)
	Widgets.clear(row)
	local width = math.min(170, math.floor((INNER_WIDTH - (size - 1) * 8) / size))
	for index = 1, size do
		local entry = list[index]
		if entry then
			local unit = Stars.make(entry.name, entry.stars)
			local card = unitCard(row, unit, width, height, index, false, false)
			unitCards[`{zone}:{index}`] = card
			if planning then
				drag:register(card, { kind = "unit", zone = zone, index = index }, Stars.displayName(unit), Widgets.TIER_COLORS[unit.cost])
			end
			table.insert(targets, { gui = card, target = { kind = "slot", zone = zone, index = index, occupied = true } })
		else
			local slot = emptySlot(row, width, height, index, if zone == "board" then "empty team slot" else "empty")
			table.insert(targets, { gui = slot, target = { kind = "slot", zone = zone, index = index, occupied = false } })
		end
	end
end

local function renderShop(state, planning: boolean)
	local odds = Levels.shopOdds(state.level)
	local parts = {}
	for cost, chance in odds do
		if chance > 0 then
			table.insert(parts, `{cost}g {math.round(chance * 100)}%`)
		end
	end
	shopHeader.Text = `SHOP  ·  click to buy or drag onto your team  ·  odds: {table.concat(parts, "  ")}`

	Widgets.clear(shopCards)
	for slot, name in state.offers do
		if name then
			local unit = Stars.make(name, 1)
			local affordable = state.gold >= unit.cost
			local card = unitCard(shopCards, unit, SHOP_CARD_WIDTH, 88, slot, true, not affordable)
			if planning and affordable then
				drag:register(card, { kind = "shop", slot = slot }, name, Widgets.TIER_COLORS[unit.cost])
			end
		else
			emptySlot(shopCards, SHOP_CARD_WIDTH, 88, slot, "sold")
		end
	end

	Widgets.clear(shopButtons)
	local reroll = Widgets.button(shopButtons, `Reroll  {state.rerollCost}g`, C.button, UDim2.new(0, 110, 0.5, -4),
		planning and state.gold >= state.rerollCost, function()
			send("reroll")
		end)
	reroll.TextSize = 14
	local canLevel = state.xpToNext ~= false
	local xp = Widgets.button(shopButtons, if canLevel then `Buy {Levels.XP_PER_BUY} XP  {Levels.XP_BUY_COST}g` else "Max level",
		C.xp, UDim2.new(0, 110, 0.5, -4), planning and canLevel and state.gold >= Levels.XP_BUY_COST, function()
			send("buyxp")
		end)
	xp.Position = UDim2.new(0, 0, 0.5, 4)
	xp.TextSize = 14
	local fightText = if state.phase == "fighting" then "Fighting..." else "FIGHT"
	local fight = Widgets.button(shopButtons, fightText, C.fight, UDim2.new(1, -118, 1, 0),
		planning and #state.board > 0, function()
			send("fight")
		end)
	fight.Position = UDim2.fromOffset(118, 0)
	fight.TextSize = 20
end

function render(state)
	drag:cancel() -- slot indexes may have changed
	hideTooltip()
	table.clear(unitCards)

	local planning = state.phase == "planning"
	messageLabel.Text = state.message

	renderTop(state)
	renderSide(state)

	local slotTargets = {}
	renderOwned(teamRow, "board", state.board, state.boardSize, 64, planning, slotTargets)
	renderOwned(benchRow, "bench", state.bench, state.benchSize, 58, planning, slotTargets)
	renderShop(state, planning)

	-- Specific slots first, then whole rows and the sell area as fallbacks.
	local targets = slotTargets
	table.insert(targets, { gui = teamRow, target = { kind = "row", zone = "board" } })
	table.insert(targets, { gui = benchRow, target = { kind = "row", zone = "bench" } })
	table.insert(targets, { gui = sellOverlay, target = { kind = "sell" } })
	drag:setTargets(targets)

	local over = state.phase == "gameover" or state.phase == "won"
	endFrame.Visible = over
	if over then
		endTitle.Text = if state.phase == "won" then "Victory!" else "Game over"
		endTitle.TextColor3 = if state.phase == "won" then C.good else C.bad
		endMessage.Text = `{state.message}\n\nYour best: {scoreText(state.best, state.totalRounds)}`
	end

	-- Show the help once, at the start of the first run.
	if not helpSeen and state.round == 1 and #state.board == 0 then
		helpSeen = true
		helpFrame.Visible = true
	end
end

stateRemote.OnClientEvent:Connect(function(state)
	lastState = state
	if drag:isDragging() then
		renderWaiting = true -- don't yank the card out from under the pointer
	else
		render(state)
	end
end)
send("sync")
