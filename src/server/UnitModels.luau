--!strict
-- Builds a simple character Model for a unit out of Parts: a body, a head
-- with eyes, and gear that fits the unit (shield, bow, daggers...).
--
-- How it holds together: the Body is the model's PrimaryPart and the only
-- anchored part. Every other part is welded to it with a WeldConstraint, so
-- moving the Body's CFrame (or tweening it) carries the whole character along.
--
-- Parts are laid out in the Body's local space, with the character facing -Z.

type GearPiece = {
	name: string,
	size: Vector3,
	offset: Vector3, -- from the Body's center
	color: Color3,
	material: Enum.Material,
}

local WOOD = Color3.fromRGB(120, 80, 45)
local STEEL = Color3.fromRGB(170, 175, 185)
local GOLD = Color3.fromRGB(230, 185, 60)
local DARK = Color3.fromRGB(35, 35, 40)
local HOOD_GREEN = Color3.fromRGB(50, 95, 55)

-- Gear per unit name. Units not listed here just get a body and head.
local GEAR: { [string]: { GearPiece } } = {
	Squire = {
		{ name = "Shield", size = Vector3.new(0.2, 1.6, 1.2), offset = Vector3.new(-1.15, 0, -0.2), color = WOOD, material = Enum.Material.Wood },
	},
	Knight = {
		{ name = "Shield", size = Vector3.new(0.2, 1.9, 1.5), offset = Vector3.new(-1.15, 0, -0.2), color = STEEL, material = Enum.Material.Metal },
		{ name = "Plume", size = Vector3.new(0.2, 0.5, 0.9), offset = Vector3.new(0, 2.65, 0), color = GOLD, material = Enum.Material.SmoothPlastic },
	},
	Archer = {
		{ name = "Bow", size = Vector3.new(0.15, 2.6, 0.15), offset = Vector3.new(1.2, 0.2, -0.4), color = WOOD, material = Enum.Material.Wood },
		{ name = "Hood", size = Vector3.new(1.3, 0.4, 1.3), offset = Vector3.new(0, 2.5, 0), color = HOOD_GREEN, material = Enum.Material.Fabric },
	},
	Rogue = {
		{ name = "DaggerRight", size = Vector3.new(0.15, 0.15, 1.0), offset = Vector3.new(1.15, -0.3, -0.6), color = STEEL, material = Enum.Material.Metal },
		{ name = "DaggerLeft", size = Vector3.new(0.15, 0.15, 1.0), offset = Vector3.new(-1.15, -0.3, -0.6), color = STEEL, material = Enum.Material.Metal },
		{ name = "Mask", size = Vector3.new(1.25, 0.3, 1.25), offset = Vector3.new(0, 1.65, 0), color = DARK, material = Enum.Material.Fabric },
	},
	Warlord = {
		{ name = "Sword", size = Vector3.new(0.25, 3.2, 0.5), offset = Vector3.new(1.25, 0.8, -0.3), color = STEEL, material = Enum.Material.Metal },
		{ name = "Crown", size = Vector3.new(1.3, 0.35, 1.3), offset = Vector3.new(0, 2.55, 0), color = GOLD, material = Enum.Material.Metal },
	},
}

-- Unscaled measurements, used by Arena to place the model and its labels.
local UnitModels = {}
UnitModels.BOTTOM = 1.2 -- Body center to feet
UnitModels.TOP = 2.4 -- Body center to top of head

local function addPart(model: Model, body: BasePart, name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = body.CFrame * CFrame.new(offset)
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.Massless = true
	part.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = part
	weld.Parent = part
	return part
end

-- Build the model at the world origin. Arena scales and moves it into place.
function UnitModels.build(unitName: string, teamColor: Color3): Model
	local model = Instance.new("Model")
	model.Name = unitName

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 2.4, 1.2)
	body.CFrame = CFrame.new()
	body.Color = teamColor
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.Parent = model
	model.PrimaryPart = body

	local skin = teamColor:Lerp(Color3.new(1, 1, 1), 0.45)
	addPart(model, body, "Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.8, 0), skin, Enum.Material.SmoothPlastic)
	addPart(model, body, "EyeLeft", Vector3.new(0.2, 0.25, 0.05), Vector3.new(-0.25, 1.9, -0.62), DARK, Enum.Material.SmoothPlastic)
	addPart(model, body, "EyeRight", Vector3.new(0.2, 0.25, 0.05), Vector3.new(0.25, 1.9, -0.62), DARK, Enum.Material.SmoothPlastic)

	for _, piece in GEAR[unitName] or {} do
		addPart(model, body, piece.name, piece.size, piece.offset, piece.color, piece.material)
	end

	return model
end

return UnitModels
