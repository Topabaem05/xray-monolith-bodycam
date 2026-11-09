-- PositionHistory: where things were a moment ago, for lag compensation. A server
-- records each character's position every step and looks up where a target was when
-- a shot was fired. Vector3 arithmetic only. Written for this project.

local PositionHistory = {}
PositionHistory.__index = PositionHistory

function PositionHistory.new(maxAge: number?)
	local self = setmetatable({}, PositionHistory)
	self.maxAge = maxAge or 1
	self.tracks = {} -- key -> { { time, position }, ... } oldest first
	return self
end

function PositionHistory:record(key, time: number, position: Vector3)
	local track = self.tracks[key]
	if not track then
		track = {}
		self.tracks[key] = track
	end
	table.insert(track, { time, position })
	local oldest = time - self.maxAge
	while #track > 2 and track[2][1] <= oldest do
		table.remove(track, 1)
	end
end

function PositionHistory:forget(key)
	self.tracks[key] = nil
end

-- The position at `time`, interpolated; clamped to the recorded span. nil when the
-- key was never recorded.
function PositionHistory:sample(key, time: number): Vector3?
	local track = self.tracks[key]
	if not track or #track == 0 then
		return nil
	end
	if time <= track[1][1] then
		return track[1][2]
	end
	for i = #track, 1, -1 do
		local sample = track[i]
		if time >= sample[1] then
			local next = track[i + 1]
			if not next then
				return sample[2]
			end
			local alpha = (time - sample[1]) / (next[1] - sample[1])
			return sample[2] + (next[2] - sample[2]) * alpha
		end
	end
	return track[1][2]
end

return PositionHistory
