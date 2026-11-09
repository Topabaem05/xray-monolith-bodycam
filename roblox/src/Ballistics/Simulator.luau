-- Simulator: flies Projectiles through the world. Each step it raycasts the segment a
-- bullet flew; at a surface it measures the thickness and lets Penetration decide.
-- Runs on a client (own shots at once, other players' shots for sound and tracers) or
-- on a server. Guide code, written for this project.
--
-- A bullet that hits something continues from the far side (or the ricochet point) on
-- the next step; the rest of that step's travel is dropped, which at 60 Hz is under a
-- frame of flight.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Materials = require(script.Parent.Materials)
local Penetration = require(script.Parent.Penetration)
local Projectile = require(script.Parent.Projectile)

local Simulator = {}
Simulator.__index = Simulator

local EXIT_GAP = 0.02 -- studs past a surface a bullet restarts from

-- options:
--   getParams     fn(projectile) -> RaycastParams? for the bullet's raycasts
--                 (exclude the shooter's character and the viewmodel)
--   onSegment     fn(projectile, from, to) each step, before the hit test
--   onImpact      fn(projectile, hit, outcome, humanoid?) at every surface; `outcome`
--                 is Penetration.resolve's result; `humanoid` when a character was hit
--   onEnd         fn(projectile) when a bullet is dropped
--   maxHits       surfaces a bullet may meet (default 5)
--   maxThickness  studs searched for a far side (default 12)
--   random        fn() -> [0, 1)
function Simulator.new(options)
	local self = setmetatable({}, Simulator)
	self.options = options or {}
	self.projectiles = {}
	self.connection = nil
	return self
end

function Simulator:start()
	if not self.connection then
		self.connection = RunService.Heartbeat:Connect(function(dt)
			self:update(dt)
		end)
	end
end

function Simulator:stop()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	self.projectiles = {}
end

-- Fires a bullet. `spec` is a Projectile spec (a Catalog entry); `data` is kept on the
-- projectile as `projectile.data` (shooter, weapon name, shot id).
function Simulator:fire(spec, origin: Vector3, direction: Vector3, data)
	local projectile = Projectile.new(spec, origin, direction)
	projectile.data = data
	table.insert(self.projectiles, projectile)
	return projectile
end

-- Studs from a hit to the far side of the part along `direction`, or nil when the
-- part is thicker than `reach`.
function Simulator.thickness(hit, direction: Vector3, reach: number): number?
	local only = RaycastParams.new()
	only.FilterType = Enum.RaycastFilterType.Include
	only.FilterDescendantsInstances = { hit.Instance }
	local back = Workspace:Raycast(hit.Position + direction * reach, -direction * reach, only)
	if not back then
		return nil
	end
	return (back.Position - hit.Position).Magnitude
end

-- The humanoid a hit part belongs to, if any.
function Simulator.humanoidOf(instance: Instance?)
	local model = instance and instance:FindFirstAncestorOfClass("Model")
	return model and model:FindFirstChildOfClass("Humanoid")
end

-- The penetration power a straight path from `from` to `to` costs (math.huge when a
-- wall is too thick). For a server checking that a claimed hit was reachable.
function Simulator.costBetween(from: Vector3, to: Vector3, params: RaycastParams?, maxThickness: number?): number
	local reach = maxThickness or 12
	local cost = 0
	local origin = from
	for _ = 1, 8 do
		local offset = to - origin
		if offset.Magnitude < 0.05 then
			break
		end
		local hit = Workspace:Raycast(origin, offset, params)
		if not hit then
			break
		end
		local direction = offset.Unit
		local through = Simulator.thickness(hit, direction, reach)
		if not through then
			return math.huge
		end
		cost += through * Materials.get(hit.Material.Name).hardness
		origin = hit.Position + direction * (through + EXIT_GAP)
	end
	return cost
end

function Simulator:_step(projectile, dt: number)
	local options = self.options
	local from, to = projectile:step(dt)
	local offset = to - from
	if offset.Magnitude < 1e-4 then
		return
	end
	local direction = offset.Unit
	local params = if options.getParams then options.getParams(projectile) else nil
	local hit = Workspace:Raycast(from, offset, params)
	if options.onSegment then
		options.onSegment(projectile, from, if hit then hit.Position else to)
	end
	if not hit then
		return
	end
	local humanoid = Simulator.humanoidOf(hit.Instance)
	local through = Simulator.thickness(hit, direction, options.maxThickness or 12)
	local outcome = Penetration.resolve({
		speed = projectile:speed(),
		power = projectile.power,
		direction = direction,
		normal = hit.Normal,
		material = if humanoid then "Flesh" else hit.Material.Name,
		thickness = through,
		random = options.random,
	})
	if options.onImpact then
		options.onImpact(projectile, hit, outcome, humanoid)
	end
	if outcome.kind == Penetration.Kind.Stop or projectile.hits + 1 >= (options.maxHits or 5) then
		projectile.position = hit.Position
		projectile.alive = false
	elseif outcome.kind == Penetration.Kind.Ricochet then
		projectile:redirect(hit.Position + hit.Normal * EXIT_GAP, outcome.direction, outcome.speed, outcome.power)
	else
		projectile:redirect(hit.Position + direction * (through + EXIT_GAP), direction, outcome.speed, outcome.power)
	end
end

function Simulator:update(dt: number)
	local list = self.projectiles
	for i = #list, 1, -1 do
		local projectile = list[i]
		self:_step(projectile, dt)
		if not projectile.alive then
			table.remove(list, i)
			if self.options.onEnd then
				self.options.onEnd(projectile)
			end
		end
	end
end

return Simulator
