-- Penetration: what happens when a bullet meets a surface: it stops, goes through
-- (slower), or glances off. Uses Vector3 arithmetic only. Written for this project.

local Materials = require(script.Parent.Materials)

local Penetration = {}

Penetration.Kind = table.freeze({ Stop = "Stop", Penetrate = "Penetrate", Ricochet = "Ricochet" })
local Kind = Penetration.Kind

-- input:
--   speed      studs/s at the surface
--   power      penetration left: studs of hardness-1 material the bullet can still cross
--   direction  unit Vector3 of travel
--   normal     unit Vector3 of the surface (facing the bullet)
--   material   Enum.Material name, or "Flesh"
--   thickness  studs to the far side along the path; nil when no far side was found
--   random     fn() -> [0, 1)
-- Returns { kind, speed, power, direction }.
function Penetration.resolve(input)
	local material = Materials.get(input.material)
	local direction, normal = input.direction, input.normal
	local intoSurface = math.clamp(-direction:Dot(normal), 0, 1)
	local grazing = math.deg(math.asin(intoSurface)) -- 90 = head-on, 0 = along the surface

	if material.ricochetAngle > 0 and grazing < material.ricochetAngle then
		local chance = material.ricochetChance * (1 - grazing / material.ricochetAngle)
		if (input.random or math.random)() < chance then
			-- Mirror the path, then flatten it: ricochets leave shallower than they came.
			local reflected = direction + normal * (2 * intoSurface)
			local flattened = reflected - normal * (0.5 * reflected:Dot(normal))
			return {
				kind = Kind.Ricochet,
				speed = input.speed * material.ricochetKeep,
				power = input.power * material.ricochetKeep,
				direction = flattened.Unit,
			}
		end
	end

	local thickness = input.thickness
	if thickness == nil then
		return { kind = Kind.Stop, speed = 0, power = 0, direction = direction }
	end
	local cost = thickness * material.hardness
	if cost >= input.power then
		return { kind = Kind.Stop, speed = 0, power = 0, direction = direction }
	end
	-- The cost is taken from the bullet's energy, so the speed falls by its root.
	local share = 1 - cost / input.power
	return {
		kind = Kind.Penetrate,
		speed = input.speed * math.sqrt(share),
		power = input.power - cost,
		direction = direction,
	}
end

return Penetration
