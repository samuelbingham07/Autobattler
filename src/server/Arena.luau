--!strict
-- Draws both boards on the baseplate: a pad per slot, a block per unit,
-- and a floating name + health bar over each unit.
--
-- Layout, seen from above (z axis):
--   enemy slot 3, 2, 1  |  center  |  your slot 1, 2, 3
-- Slot 1 on each side is the frontline, closest to the middle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Stars = require(ReplicatedStorage.Shared.Stars)
local Board = require(script.Parent.Board)
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

local HEALTH_FULL = Color3.fromRGB(80, 200, 90)
local HEALTH_EMPTY = Color3.fromRGB(220, 60, 60)

export type UnitView = {
	part: Part,
	fill: Frame,
	hpLabel: TextLabel,
	maxHealth: number,
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
	gui.Size = UDim2.new(5, 0, 1.6, 0)
	gui.StudsOffset = Vector3.new(0, size / 2 + 1.5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = part

	local nameArea = Instance.new("Frame")
	nameArea.BackgroundTransparency = 1
	nameArea.Size = UDim2.fromScale(1, 0.5)
	nameArea.Parent = gui
	makeLabel(nameArea, Stars.displayName(unit))

	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromScale(0, 0.55)
	bar.Size = UDim2.fromScale(1, 0.45)
	bar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bar.BorderSizePixel = 0
	bar.Parent = gui

	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.Parent = bar

	local hpLabel = makeLabel(bar, "")
	hpLabel.ZIndex = 2

	local view: UnitView = {
		part = part,
		fill = fill,
		hpLabel = hpLabel,
		maxHealth = unit.health,
		color = part.Color,
		home = part.Position,
		side = side,
	}
	Arena.SetHealth(view, unit.health)
	return view
end

-- Draw both boards, replacing whatever was drawn before.
function Arena.Render(playerUnits: { Unit }, enemyUnits: { Unit }): ArenaView
	local old = workspace:FindFirstChild(ARENA_NAME)
	if old then
		old:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = ARENA_NAME
	folder.Parent = workspace

	for index = 1, Board.SIZE do
		makePad(folder, "player", index)
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

-- Target flashes white, then fades back to its team color.
local function flash(view: UnitView)
	view.part.Color = Color3.new(1, 1, 1)
	TweenService:Create(view.part, FLASH_TWEEN, { Color = view.color }):Play()
end

-- Play back a fight from Combat.Fight on an arena drawn by Render.
-- Yields until the fight is over. Speed 2 plays twice as fast.
function Arena.Replay(view: ArenaView, events: { Combat.CombatEvent }, speed: number?)
	local playbackSpeed = speed or 1
	local now = 0
	for _, event in events do
		task.wait((event.time - now) / playbackSpeed)
		now = event.time

		local attacker = sideViews(view, event.attackerSide)[event.attackerIndex]
		local target = sideViews(view, event.targetSide)[event.targetIndex]
		lunge(attacker)
		flash(target)
		Arena.SetHealth(target, event.targetHealth)

		if event.targetHealth <= 0 then
			print(`{target.part.Name} ({event.targetSide}) dies at {string.format("%.1f", event.time)}s`)
		end
	end
end

return Arena
