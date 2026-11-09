-- Materials: how each Roblox material treats a bullet. Pure Luau (keys are
-- Enum.Material names). Written for this project; the values are gameplay choices,
-- not measurements.
--
--   hardness        penetration cost per stud of thickness (wood = 1)
--   ricochetAngle   degrees between the path and the surface below which the bullet
--                   can glance off (0 = never)
--   ricochetChance  0..1 at a very shallow angle, falling to 0 at ricochetAngle
--   ricochetKeep    share of the speed a ricochet keeps

local Materials = {}

local function entry(hardness: number, angle: number, chance: number, keep: number)
	return table.freeze({ hardness = hardness, ricochetAngle = angle, ricochetChance = chance, ricochetKeep = keep })
end

local SOFT = entry(0.25, 0, 0, 0)
local WOOD = entry(1, 6, 0.15, 0.4)
local PLASTIC = entry(1.3, 8, 0.2, 0.45)
local EARTH = entry(1.8, 8, 0.3, 0.4)
local STONE = entry(5, 18, 0.55, 0.55)
local METAL = entry(9, 25, 0.75, 0.65)

Materials.Default = PLASTIC
Materials.Flesh = entry(0.35, 0, 0, 0) -- character parts (the simulator's own name)

local GROUPS = {
	[SOFT] = { "Glass", "Fabric", "Carpet", "Cardboard", "Leather", "ForceField", "Neon", "Ice" },
	[WOOD] = { "Wood", "WoodPlanks", "Plaster", "RoofShingles" },
	[PLASTIC] = { "Plastic", "SmoothPlastic", "Rubber", "CeramicTiles", "ClayRoofTiles" },
	[EARTH] = { "Grass", "Ground", "LeafyGrass", "Sand", "Mud", "Snow", "Sandstone" },
	[STONE] = {
		"Concrete", "Brick", "Cobblestone", "Slate", "Granite", "Marble", "Rock", "Pavement", "Asphalt",
		"Basalt", "Limestone", "Pebble", "Salt", "CrackedLava", "Glacier",
	},
	[METAL] = { "Metal", "DiamondPlate", "CorrodedMetal", "Foil" },
}
local byName = { Flesh = Materials.Flesh }
for group, names in GROUPS do
	for _, name in names do
		byName[name] = group
	end
end

function Materials.get(name: string?)
	return byName[name or ""] or Materials.Default
end

-- Replaces or adds a material's values.
function Materials.set(name: string, hardness: number, angle: number, chance: number, keep: number)
	byName[name] = entry(hardness, angle, chance, keep)
end

return Materials
