-- Catalog: each weapon's ballistics and damage, shared by client and server (the
-- server must not trust numbers from a client). Keys are Weapon config names.
-- Pure Luau. Written for this project; the values are gameplay choices.

local Projectile = require(script.Parent.Projectile)

local Catalog = {}

local function weapon(overrides)
	local stats = Projectile.defaultSpec()
	stats.rpm = 600
	stats.damage = 34 -- at the muzzle, to the torso
	stats.minDamage = 18 -- at falloffEnd and beyond
	stats.falloffStart = 300 -- studs
	stats.falloffEnd = 1500
	stats.headMultiplier = 2.5
	stats.limbMultiplier = 0.75
	for key, value in overrides or {} do
		stats[key] = value
	end
	return stats
end

Catalog.weapons = {
	Rifle = weapon(),
	Pistol = weapon({
		speed = 1250, -- about 350 m/s
		drag = 0.0006,
		power = 2.5,
		rpm = 450,
		damage = 24,
		minDamage = 10,
		falloffStart = 120,
		falloffEnd = 600,
	}),
}

function Catalog.get(name: string)
	return Catalog.weapons[name]
end

local LIMBS = { "Arm", "Hand", "Leg", "Foot" }

-- Damage for a hit on body part `partName` at `distance` studs. `speedShare` (0..1) is
-- the share of muzzle speed left after walls (default 1).
function Catalog.damage(stats, distance: number, partName: string?, speedShare: number?): number
	local t = math.clamp((distance - stats.falloffStart) / (stats.falloffEnd - stats.falloffStart), 0, 1)
	local damage = stats.damage + (stats.minDamage - stats.damage) * t
	if partName == "Head" then
		damage *= stats.headMultiplier
	elseif partName then
		for _, limb in LIMBS do
			if string.find(partName, limb, 1, true) then
				damage *= stats.limbMultiplier
				break
			end
		end
	end
	local share = math.clamp(speedShare or 1, 0, 1)
	return damage * share * share -- energy goes with the square of speed
end

return Catalog
