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
local ROBE_WHITE = Color3.fromRGB(235, 230, 215)
local ARCANE = Color3.fromRGB(150, 90, 230)
local STONE = Color3.fromRGB(110, 115, 120)
local HOLY = Color3.fromRGB(255, 225, 120)
local BONE = Color3.fromRGB(225, 215, 190)

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
	Acolyte = {
		{ name = "Staff", size = Vector3.new(0.2, 3, 0.2), offset = Vector3.new(1.2, 0.5, -0.3), color = WOOD, material = Enum.Material.Wood },
		{ name = "Hood", size = Vector3.new(1.3, 0.4, 1.3), offset = Vector3.new(0, 2.5, 0), color = ROBE_WHITE, material = Enum.Material.Fabric },
	},
	Mage = {
		{ name = "HatBrim", size = Vector3.new(1.6, 0.15, 1.6), offset = Vector3.new(0, 2.45, 0), color = ARCANE, material = Enum.Material.Fabric },
		{ name = "HatTop", size = Vector3.new(0.8, 0.9, 0.8), offset = Vector3.new(0, 2.95, 0), color = ARCANE, material = Enum.Material.Fabric },
		{ name = "Staff", size = Vector3.new(0.2, 3, 0.2), offset = Vector3.new(1.2, 0.5, -0.3), color = WOOD, material = Enum.Material.Wood },
		{ name = "Orb", size = Vector3.new(0.5, 0.5, 0.5), offset = Vector3.new(1.2, 2.2, -0.3), color = ARCANE, material = Enum.Material.Neon },
	},
	Sentinel = {
		{ name = "ShoulderLeft", size = Vector3.new(0.8, 0.8, 1.4), offset = Vector3.new(-1.3, 0.9, 0), color = STONE, material = Enum.Material.Slate },
		{ name = "ShoulderRight", size = Vector3.new(0.8, 0.8, 1.4), offset = Vector3.new(1.3, 0.9, 0), color = STONE, material = Enum.Material.Slate },
		{ name = "Rune", size = Vector3.new(0.6, 0.6, 0.05), offset = Vector3.new(0, 0.2, -0.62), color = ARCANE, material = Enum.Material.Neon },
	},
	Paladin = {
		{ name = "Shield", size = Vector3.new(0.2, 2, 1.5), offset = Vector3.new(-1.15, 0, -0.2), color = GOLD, material = Enum.Material.Metal },
		{ name = "Hammer", size = Vector3.new(0.25, 2.6, 0.25), offset = Vector3.new(1.2, 0.4, -0.3), color = STEEL, material = Enum.Material.Metal },
		{ name = "Halo", size = Vector3.new(1.5, 0.1, 1.5), offset = Vector3.new(0, 2.9, 0), color = HOLY, material = Enum.Material.Neon },
	},
	Sniper = {
		{ name = "Rifle", size = Vector3.new(0.2, 0.25, 2.6), offset = Vector3.new(1.15, 0.3, -0.8), color = DARK, material = Enum.Material.Metal },
		{ name = "Scope", size = Vector3.new(0.15, 0.15, 0.6), offset = Vector3.new(1.15, 0.55, -0.6), color = STEEL, material = Enum.Material.Metal },
		{ name = "Cap", size = Vector3.new(1.3, 0.3, 1.5), offset = Vector3.new(0, 2.5, -0.1), color = HOOD_GREEN, material = Enum.Material.Fabric },
	},
	Dragon = {
		{ name = "WingLeft", size = Vector3.new(0.2, 2, 2.4), offset = Vector3.new(-1.2, 0.8, 0.8), color = DARK, material = Enum.Material.SmoothPlastic },
		{ name = "WingRight", size = Vector3.new(0.2, 2, 2.4), offset = Vector3.new(1.2, 0.8, 0.8), color = DARK, material = Enum.Material.SmoothPlastic },
		{ name = "HornLeft", size = Vector3.new(0.2, 0.6, 0.2), offset = Vector3.new(-0.4, 2.7, 0), color = BONE, material = Enum.Material.SmoothPlastic },
		{ name = "HornRight", size = Vector3.new(0.2, 0.6, 0.2), offset = Vector3.new(0.4, 2.7, 0), color = BONE, material = Enum.Material.SmoothPlastic },
		{ name = "Tail", size = Vector3.new(0.4, 0.4, 1.8), offset = Vector3.new(0, -0.8, 1.4), color = DARK, material = Enum.Material.SmoothPlastic },
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
