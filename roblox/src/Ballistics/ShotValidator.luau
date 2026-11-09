-- ShotValidator: the server's plausibility checks on a client's shot and hit claims.
-- Geometry and timing only; the caller supplies positions from PositionHistory and
-- does the world raycasts. Vector3 arithmetic only. Written for this project.
--
-- A check returns true, or false and a reason (for logging; do not send it back).

local ShotValidator = {}
ShotValidator.__index = ShotValidator

function ShotValidator.defaultSettings()
	return {
		maxRewind = 0.4, -- seconds a shot may lie in the past (caps lag compensation)
		maxFuture = 0.05, -- seconds of clock error allowed ahead
		maxOriginError = 7, -- studs between the claimed muzzle and the server's head
		rateTolerance = 1.15, -- shots may come this much faster than the weapon's rpm
		burst = 3, -- shots that may arrive at once after a network stall
		maxLineError = 3, -- studs a hit may lie off the shot's line (plus bullet drop)
		maxTargetError = 6, -- studs between a hit and the target's rewound position
	}
end

function ShotValidator.new(settings)
	local self = setmetatable({}, ShotValidator)
	self.settings = settings or ShotValidator.defaultSettings()
	self.states = {} -- key -> { tokens, time }
	return self
end

function ShotValidator:forget(key)
	self.states[key] = nil
end

local function finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e7 and math.abs(v.Y) < 1e7 and math.abs(v.Z) < 1e7
end

-- shot: { time, origin, direction }. rpm is the weapon's rate; serverOrigin is where
-- the server had the shooter's head at shot.time; now is the server clock.
function ShotValidator:checkShot(key, shot, rpm: number, serverOrigin: Vector3, now: number): (boolean, string?)
	local s = self.settings
	if type(shot.time) ~= "number" or shot.time ~= shot.time then
		return false, "Time"
	end
	if not (finite(shot.origin) and finite(shot.direction)) then
		return false, "Number"
	end
	if math.abs(shot.direction.Magnitude - 1) > 0.01 then
		return false, "Direction"
	end
	if shot.time < now - s.maxRewind or shot.time > now + s.maxFuture then
		return false, "Time"
	end
	if (shot.origin - serverOrigin).Magnitude > s.maxOriginError then
		return false, "Origin"
	end
	-- Fire rate: a token bucket refilled at the weapon's rate.
	local state = self.states[key]
	if not state then
		state = { tokens = s.burst, time = now }
		self.states[key] = state
	end
	local rate = rpm / 60 * s.rateTolerance
	state.tokens = math.min(s.burst, state.tokens + (now - state.time) * rate)
	state.time = now
	if state.tokens < 1 then
		return false, "Rate"
	end
	state.tokens -= 1
	return true, nil
end

-- A claimed hit at `position` on a target the server had at `targetPosition` when the
-- shot was fired. `drop` is the bullet drop allowed at that distance (studs).
function ShotValidator:checkHit(
	shot,
	position: Vector3,
	targetPosition: Vector3?,
	maxRange: number,
	drop: number?
): (boolean, string?)
	local s = self.settings
	if not finite(position) then
		return false, "Number"
	end
	local offset = position - shot.origin
	local along = offset:Dot(shot.direction)
	if along < 0 or along > maxRange then
		return false, "Range"
	end
	local off = (offset - shot.direction * along).Magnitude
	if off > s.maxLineError + (drop or 0) then
		return false, "Line"
	end
	if targetPosition and (position - targetPosition).Magnitude > s.maxTargetError then
		return false, "Target"
	end
	return true, nil
end

return ShotValidator
