--!strict
-- Draws both boards on the baseplate: a pad per slot, a character per unit,
-- and a floating name, health bar and mana bar over each unit.
-- Also replays fights from Combat, with damage numbers and sounds.
--
-- Each player gets their own arena: a folder in Workspace and an origin point
-- on the baseplate (see Session). Layout around the origin, seen from above (z axis):
--   enemy slot ... 2, 1  |  origin  |  your slot 1, 2 ...
-- Slot 1 on each side is the frontline, closest to the middle.
-- Characters face the middle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Stars = require(ReplicatedStorage.Shared.Stars)
local Combat = require(script.Parent.Combat)
local UnitModels = require(script.Parent.UnitModels)

type Unit = Stars.StarredUnit
type Side = "player" | "enemy"

local FRONT_OFFSET = 6 -- studs from the center line to each side's slot 1
local SLOT_SPACING = 6 -- studs between slots
local PAD_SIZE = 5

local TEAM_COLORS: { [Side]: Color3 } = {
	player = Color3.fromRGB(70, 130, 230),
	enemy = Color3.fromRGB(220, 70, 70),
}

-- Pricier units are bigger, and each extra star adds a bit more.
local SCALE_BY_COST: { [number]: number } = {
	[1] = 1,
	[2] = 1.1,
	[3] = 1.2,
	[4] = 1.3,
	[5] = 1.45,
}
local SCALE_PER_STAR = 0.15

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
local DAMAGE_TEXT = Color3.fromRGB(255, 235, 235)
local HEAL_TEXT = Color3.fromRGB(120, 255, 140)

-- Built-in Roblox sounds (they ship with Studio and the client, so no upload needed).
-- Swap in any sound asset id, e.g. "rbxassetid://123456", to change them.
local SOUNDS = {
	attack = { id = "rbxasset://sounds/swordslash.wav", volume = 0.25 },
	cast = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5 },
	death = { id = "rbxasset://sounds/uuhhh.mp3", volume = 0.5 },
}

export type UnitView = {
	model: Model,
	body: BasePart, -- the model's PrimaryPart; move this to move the character
	fill: Frame,
	hpLabel: TextLabel,
	manaFill: Frame,
	maxHealth: number,
	maxMana: number,
	top: number, -- studs from body center to top of head
	color: Color3,
	home: CFrame, -- resting CFrame, so attack lunges always return to the same spot
	side: Side,
}

-- Unit views are in the same order as the unit lists passed to Render,
-- which is also the order Combat uses. That lets combat events map to views.
export type ArenaView = {
	folder: Folder,
	player: { UnitView },
	enemy: { UnitView },
}

local function slotPosition(origin: Vector3, side: Side, index: number): Vector3
	local direction = if side == "player" then 1 else -1
	return origin + Vector3.new(0, 0, direction * (FRONT_OFFSET + (index - 1) * SLOT_SPACING))
end

local function makePad(parent: Instance, origin: Vector3, side: Side, index: number)
	local pad = Instance.new("Part")
	pad.Name = `{side}Pad{index}`
	pad.Anchored = true
	pad.Size = Vector3.new(PAD_SIZE, 0.2, PAD_SIZE)
	pad.Position = slotPosition(origin, side, index) + Vector3.new(0, 0.1, 0)
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

local function playSound(parent: Instance, sound: { id: string, volume: number })
	local instance = Instance.new("Sound")
	instance.SoundId = sound.id
	instance.Volume = sound.volume
	instance.Parent = parent
	instance:Play()
	Debris:AddItem(instance, 3) -- clean up after it finishes
end

local Arena = {}

function Arena.SetHealth(view: UnitView, health: number)
	local fraction = math.clamp(health / view.maxHealth, 0, 1)
	view.fill.Size = UDim2.fromScale(fraction, 1)
	view.fill.BackgroundColor3 = HEALTH_EMPTY:Lerp(HEALTH_FULL, fraction)
	view.hpLabel.Text = `{health}/{view.maxHealth}`
	if health <= 0 then
		for _, part in view.model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency = 0.8
			end
		end
	end
end

function Arena.SetMana(view: UnitView, mana: number)
	view.manaFill.Size = UDim2.fromScale(math.clamp(mana / view.maxMana, 0, 1), 1)
end

local function makeUnit(parent: Instance, origin: Vector3, unit: Unit, side: Side, index: number): UnitView
	local scale = (SCALE_BY_COST[unit.cost] or 1) * (1 + SCALE_PER_STAR * (unit.stars - 1))

	local model = UnitModels.build(unit.name, TEAM_COLORS[side])
	model.Name = Stars.displayName(unit)
	model:ScaleTo(scale)

	-- Stand on the pad, facing the middle of the arena.
	local position = slotPosition(origin, side, index) + Vector3.new(0, 0.2 + UnitModels.BOTTOM * scale, 0)
	local facing = if side == "player" then Vector3.new(0, 0, -1) else Vector3.new(0, 0, 1)
	model:PivotTo(CFrame.lookAt(position, position + facing))
	model.Parent = parent

	local body = model.PrimaryPart :: BasePart
	local top = UnitModels.TOP * scale

	-- Floating label. Size is in studs, so it shrinks with distance like the model does.
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(5, 0, 1.9, 0)
	gui.StudsOffset = Vector3.new(0, top + 1.2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = body

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
		model = model,
		body = body,
		fill = fill,
		hpLabel = hpLabel,
		manaFill = manaFill,
		maxHealth = unit.health,
		maxMana = unit.ability.mana,
		top = top,
		color = body.Color,
		home = body.CFrame,
		side = side,
	}
	Arena.SetHealth(view, unit.health)
	Arena.SetMana(view, unit.startingMana)
	return view
end

-- Draw both boards into `folder` around `origin`, replacing whatever was drawn there before.
-- playerSlots is your board size, so empty slots still get a pad.
function Arena.Render(
	folder: Folder,
	origin: Vector3,
	playerUnits: { Unit },
	enemyUnits: { Unit },
	playerSlots: number
): ArenaView
	folder:ClearAllChildren()

	for index = 1, math.max(playerSlots, #playerUnits) do
		makePad(folder, origin, "player", index)
	end
	for index = 1, #enemyUnits do
		makePad(folder, origin, "enemy", index)
	end

	local view: ArenaView = { folder = folder, player = {}, enemy = {} }
	for index, unit in playerUnits do
		table.insert(view.player, makeUnit(folder, origin, unit, "player", index))
	end
	for index, unit in enemyUnits do
		table.insert(view.enemy, makeUnit(folder, origin, unit, "enemy", index))
	end
	return view
end

local function sideViews(view: ArenaView, side: Side): { UnitView }
	return if side == "player" then view.player else view.enemy
end

-- Attacker steps forward (its own -Z, which faces the enemy) and back.
local function lunge(view: UnitView)
	view.body.CFrame = view.home
	local target = view.home * CFrame.new(0, 0, -LUNGE_DISTANCE)
	TweenService:Create(view.body, LUNGE_TWEEN, { CFrame = target }):Play()
end

-- Body flashes a color, then fades back to its team color.
local function flash(view: UnitView, color: Color3)
	view.body.Color = color
	TweenService:Create(view.body, FLASH_TWEEN, { Color = view.color }):Play()
end

-- Text that floats up from a unit and fades out: ability names, damage, heals.
-- Damage numbers get a little sideways jitter so rapid hits don't stack exactly.
local function popText(view: UnitView, text: string, color: Color3, height: number, jitter: boolean)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(6, 0, height, 0)
	local x = if jitter then (math.random() - 0.5) * 2 else 0
	gui.StudsOffset = Vector3.new(x, view.top + 3.4, 0)
	gui.AlwaysOnTop = true
	gui.Parent = view.body

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
			popText(actor, `{event.abilityName}!`, CAST_TEXT, 1.2, false)
			playSound(actor.body, SOUNDS.cast)
		else
			lunge(actor)
			playSound(actor.body, SOUNDS.attack)
		end
		Arena.SetMana(actor, event.mana)

		for _, effect in event.effects do
			local target = sideViews(view, effect.side)[effect.index]
			if effect.heal then
				flash(target, HEAL_FLASH)
				popText(target, `+{effect.amount}`, HEAL_TEXT, 0.9, true)
			else
				flash(target, HIT_FLASH)
				popText(target, `-{effect.amount}`, DAMAGE_TEXT, 0.9, true)
			end
			Arena.SetHealth(target, effect.health)
			Arena.SetMana(target, effect.mana)
			if effect.health <= 0 then
				playSound(target.body, SOUNDS.death)
				print(`{target.model.Name} ({effect.side}) dies at {string.format("%.1f", event.time)}s`)
			end
		end
	end
end

return Arena
