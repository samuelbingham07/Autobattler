--!strict
-- Draws both boards on the baseplate: a pad per slot, a block per unit,
-- and a floating name, health bar and mana bar over each unit.
-- Also replays fights from Combat.
--
-- Layout, seen from above (z axis):
--   enemy slot ... 2, 1  |  center  |  your slot 1, 2 ...
-- Slot 1 on each side is the frontline, closest to the middle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Stars = require(ReplicatedStorage.Shared.Stars)
local Combat = require(script.Parent.Combat)

type Unit = Stars.StarredUnit
type Side = "player" | "enemy"

local ARENA_NAME = "Arena"
local FRONT_OFFSET = 6 -- studs from the center line to each side's slot 1
local SLOT_SPACING = 6 -- studs between slots
local PAD_SIZE = 5

local TEAM_COLORS: { [Side]: Color3 } = {
	player = Color3.fromRGB(70, 130, 230),
	enemy = Color3.fromRGB(220, 70, 70),
}

-- Pricier units are bigger blocks, and each extra star adds a bit more.
local UNIT_SIZE_BY_COST: { [number]: number } = {
	[1] = 3,
	[2] = 3.75,
	[3] = 4.5,
}
local SIZE_PER_STAR = 0.15

local LUNGE_DISTANCE = 1.5
-- Out and back (reverses = true), quick enough to finish before the unit's next attack.
local LUNGE_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
local FLASH_TWEEN = TweenInfo.new(0.25)
local POP_TWEEN = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local HEALTH_FULL = Color3.fromRGB(80, 200, 90)
local HEALTH_EMPTY = Color3.fromRGB(220, 60, 60)
local MANA_COLOR = Color3.fromRGB(80, 160, 255)
local HIT_FLASH = Color3.new(1, 1, 1)
local HEAL_FLASH = Color3.fromRGB(120, 255, 140)
local CAST_TEXT = Color3.fromRGB(255, 220, 90)

export type UnitView = {
	part: Part,
	fill: Frame,
	hpLabel: TextLabel,
	manaFill: Frame,
	maxHealth: number,
	maxMana: number,
	size: number,
	color: Color3,
	home: Vector3, -- resting position, so attack lunges always return to the same spot
	side: Side,
}

-- Unit views are in the same order as the unit lists passed to Render,
-- which is also the order Combat uses. That lets combat events map to views.
export type ArenaView = {
	folder: Folder,
	player: { UnitView },
	enemy: { UnitView },
}

local function slotPosition(side: Side, index: number): Vector3
	local direction = if side == "player" then 1 else -1
	return Vector3.new(0, 0, direction * (FRONT_OFFSET + (index - 1) * SLOT_SPACING))
end

local function makePad(parent: Instance, side: Side, index: number)
	local pad = Instance.new("Part")
	pad.Name = `{side}Pad{index}`
	pad.Anchored = true
	pad.Size = Vector3.new(PAD_SIZE, 0.2, PAD_SIZE)
	pad.Position = slotPosition(side, index) + Vector3.new(0, 0.1, 0)
	pad.Color = TEAM_COLORS[side]:Lerp(Color3.new(1, 1, 1), 0.6)
	pad.Material = Enum.Material.SmoothPlastic
	pad.Parent = parent
end

local function makeLabel(parent: Instance, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.Parent = parent
	return label
end

-- A bar with a background and a fill, at a vertical position inside a BillboardGui.
local function makeBar(parent: Instance, y: number, height: number, fillColor: Color3): (Frame, Frame)
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromScale(0, y)
	bar.Size = UDim2.fromScale(1, height)
	bar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bar.BorderSizePixel = 0
	bar.Parent = parent

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Parent = bar
	return bar, fill
end

local Arena = {}

function Arena.SetHealth(view: UnitView, health: number)
	local fraction = math.clamp(health / view.maxHealth, 0, 1)
	view.fill.Size = UDim2.fromScale(fraction, 1)
	view.fill.BackgroundColor3 = HEALTH_EMPTY:Lerp(HEALTH_FULL, fraction)
	view.hpLabel.Text = `{health}/{view.maxHealth}`
	if health <= 0 then
		view.part.Transparency = 0.8
	end
end

function Arena.SetMana(view: UnitView, mana: number)
	view.manaFill.Size = UDim2.fromScale(math.clamp(mana / view.maxMana, 0, 1), 1)
end

local function makeUnit(parent: Instance, unit: Unit, side: Side, index: number): UnitView
	local size = (UNIT_SIZE_BY_COST[unit.cost] or 3) * (1 + SIZE_PER_STAR * (unit.stars - 1))

	local part = Instance.new("Part")
	part.Name = Stars.displayName(unit)
	part.Anchored = true
	part.Size = Vector3.new(size, size, size)
	part.Position = slotPosition(side, index) + Vector3.new(0, 0.2 + size / 2, 0)
	part.Color = TEAM_COLORS[side]
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent

	-- Floating label. Size is in studs, so it shrinks with distance like the block does.
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(5, 0, 1.9, 0)
	gui.StudsOffset = Vector3.new(0, size / 2 + 1.6, 0)
	gui.AlwaysOnTop = true
	gui.Parent = part

	local nameArea = Instance.new("Frame")
	nameArea.BackgroundTransparency = 1
	nameArea.Size = UDim2.fromScale(1, 0.45)
	nameArea.Parent = gui
	makeLabel(nameArea, Stars.displayName(unit))

	local healthBar, fill = makeBar(gui, 0.5, 0.32, HEALTH_FULL)
	local hpLabel = makeLabel(healthBar, "")
	hpLabel.ZIndex = 2

	local _, manaFill = makeBar(gui, 0.86, 0.14, MANA_COLOR)

	local view: UnitView = {
		part = part,
		fill = fill,
		hpLabel = hpLabel,
		manaFill = manaFill,
		maxHealth = unit.health,
		maxMana = unit.ability.mana,
		size = size,
		color = part.Color,
		home = part.Position,
		side = side,
	}
	Arena.SetHealth(view, unit.health)
	Arena.SetMana(view, 0)
	return view
end

-- Draw both boards, replacing whatever was drawn before.
-- playerSlots is your board size, so empty slots still get a pad.
function Arena.Render(playerUnits: { Unit }, enemyUnits: { Unit }, playerSlots: number): ArenaView
	local old = workspace:FindFirstChild(ARENA_NAME)
	if old then
		old:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = ARENA_NAME
	folder.Parent = workspace

	for index = 1, math.max(playerSlots, #playerUnits) do
		makePad(folder, "player", index)
	end
	for index = 1, #enemyUnits do
		makePad(folder, "enemy", index)
	end

	local view: ArenaView = { folder = folder, player = {}, enemy = {} }
	for index, unit in playerUnits do
		table.insert(view.player, makeUnit(folder, unit, "player", index))
	end
	for index, unit in enemyUnits do
		table.insert(view.enemy, makeUnit(folder, unit, "enemy", index))
	end
	return view
end

local function sideViews(view: ArenaView, side: Side): { UnitView }
	return if side == "player" then view.player else view.enemy
end

-- Attacker hops toward the enemy side and back.
local function lunge(view: UnitView)
	local direction = if view.side == "player" then -1 else 1
	local target = view.home + Vector3.new(0, 0, direction * LUNGE_DISTANCE)
	view.part.Position = view.home
	TweenService:Create(view.part, LUNGE_TWEEN, { Position = target }):Play()
end

-- Unit flashes a color, then fades back to its team color.
local function flash(view: UnitView, color: Color3)
	view.part.Color = color
	TweenService:Create(view.part, FLASH_TWEEN, { Color = view.color }):Play()
end

-- Text that floats up from a unit and fades out, e.g. an ability name.
local function popText(view: UnitView, text: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(6, 0, 1.2, 0)
	gui.StudsOffset = Vector3.new(0, view.size / 2 + 3.8, 0)
	gui.AlwaysOnTop = true
	gui.Parent = view.part

	local label = makeLabel(gui, text)
	label.TextColor3 = color

	TweenService:Create(gui, POP_TWEEN, { StudsOffset = gui.StudsOffset + Vector3.new(0, 2, 0) }):Play()
	local fade = TweenService:Create(label, POP_TWEEN, { TextTransparency = 1, TextStrokeTransparency = 1 })
	fade.Completed:Connect(function()
		gui:Destroy()
	end)
	fade:Play()
end

-- Play back a fight from Combat.Fight on an arena drawn by Render.
-- Yields until the fight is over. Speed 2 plays twice as fast.
function Arena.Replay(view: ArenaView, events: { Combat.CombatEvent }, speed: number?)
	local playbackSpeed = speed or 1
	local now = 0
	for _, event in events do
		task.wait((event.time - now) / playbackSpeed)
		now = event.time

		local actor = sideViews(view, event.side)[event.index]
		if event.kind == "cast" then
			popText(actor, `{event.abilityName}!`, CAST_TEXT)
		else
			lunge(actor)
		end
		Arena.SetMana(actor, event.mana)

		for _, effect in event.effects do
			local target = sideViews(view, effect.side)[effect.index]
			flash(target, if effect.heal then HEAL_FLASH else HIT_FLASH)
			Arena.SetHealth(target, effect.health)
			Arena.SetMana(target, effect.mana)
			if effect.health <= 0 then
				print(`{target.part.Name} ({effect.side}) dies at {string.format("%.1f", event.time)}s`)
			end
		end
	end
end

return Arena
