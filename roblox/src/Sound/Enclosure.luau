-- Enclosure: how closed-in a place is, from rays around a point. Feeds the reverb
-- (Acoustics.reverb) and tells an indoor gunshot from an outdoor one.
-- Written for this project.

local Workspace = game:GetService("Workspace")

local Enclosure = {}

-- Probe directions: straight up (a ceiling counts double) and a ring tilted upward.
local DIRECTIONS = { Vector3.new(0, 1, 0) }
for i = 0, 7 do
	local angle = i * math.pi / 4
	table.insert(DIRECTIONS, Vector3.new(math.cos(angle), 0.35, math.sin(angle)).Unit)
end
Enclosure.DIRECTIONS = DIRECTIONS

-- distances[i] is the hit distance of ray i, or nil for open sky. The first ray is
-- the one straight up. Pure.
function Enclosure.summarise(distances, count: number, reach: number)
	local blocked, weight, total = 0, 0, 0
	for i = 1, count do
		local w = if i == 1 then 2 else 1
		weight += w
		local distance = distances[i]
		if distance then
			blocked += w
			total += distance
		else
			total += reach
		end
	end
	return { indoor = blocked / weight, size = total / count }
end

function Enclosure.probe(position: Vector3, params: RaycastParams?, reach: number?)
	reach = reach or 120
	local distances = {}
	for i, direction in DIRECTIONS do
		local hit = Workspace:Raycast(position, direction * reach, params)
		distances[i] = if hit then (hit.Position - position).Magnitude else nil
	end
	return Enclosure.summarise(distances, #DIRECTIONS, reach)
end

return Enclosure
