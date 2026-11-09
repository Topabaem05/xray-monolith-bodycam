-- Projectile: one bullet in flight with gravity and drag. Uses Vector3 arithmetic
-- only, with the time step passed in. Written for this project.
--
-- Units: studs and seconds. With 1 stud = 0.28 m, 700 m/s is 2500 studs/s and
-- 9.81 m/s^2 is 35 studs/s^2 (not Workspace.Gravity, which is tuned for characters).

local Projectile = {}
Projectile.__index = Projectile

function Projectile.defaultSpec()
	return {
		speed = 2500, -- studs/s at the muzzle
		gravity = 35, -- studs/s^2 downward
		drag = 0.00027, -- 1/stud: speed falls as exp(-drag * distance)
		power = 6, -- penetration: studs of wood-like material
		maxRange = 6000, -- studs flown before the bullet is dropped
		minSpeed = 150, -- studs/s below which it is dropped
	}
end

function Projectile.new(spec, origin: Vector3, direction: Vector3)
	local self = setmetatable({}, Projectile)
	self.spec = spec
	self.position = origin
	self.velocity = direction.Unit * spec.speed
	self.power = spec.power
	self.travelled = 0
	self.time = 0
	self.hits = 0
	self.alive = true
	return self
end

function Projectile:speed(): number
	return self.velocity.Magnitude
end

function Projectile:direction(): Vector3
	return self.velocity.Unit
end

-- Advances by dt. Returns the segment flown (from, to).
function Projectile:step(dt: number): (Vector3, Vector3)
	local spec = self.spec
	local from = self.position
	local v0 = self.velocity
	local v1 = v0 + Vector3.new(0, -spec.gravity * dt, 0)
	-- Drag as dv/dt = -k v^2, solved exactly for the speed over the step.
	local speed = v1.Magnitude
	if spec.drag > 0 and speed > 0 then
		v1 = v1 * (1 / (1 + spec.drag * speed * dt))
	end
	local to = from + (v0 + v1) * (0.5 * dt)
	self.velocity = v1
	self.position = to
	self.travelled += (to - from).Magnitude
	self.time += dt
	if self.travelled >= spec.maxRange or v1.Magnitude < spec.minSpeed then
		self.alive = false
	end
	return from, to
end

-- Continues from a new place after a penetration or a ricochet.
function Projectile:redirect(position: Vector3, direction: Vector3, speed: number, power: number)
	self.position = position
	self.velocity = direction.Unit * speed
	self.power = power
	self.hits += 1
	if speed < self.spec.minSpeed then
		self.alive = false
	end
end

-- Drop in studs at a distance for a flat shot without drag (for sight zeroing and
-- for a server's tolerance on claimed hits).
function Projectile.drop(distance: number, speed: number, gravity: number): number
	local time = distance / speed
	return 0.5 * gravity * time * time
end

return Projectile
