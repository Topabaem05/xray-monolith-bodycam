-- Hearing: what unprotected gunfire does to the ears. Exposure builds a ringing and
-- dulls the treble; both fade over seconds. Pure Luau. Written for this project.

local Hearing = {}
Hearing.__index = Hearing

function Hearing.defaultSettings()
	return {
		recovery = 4, -- seconds time constant
		ringAt = 0.35, -- exposure where the ringing starts
		maxHighDb = -24, -- treble cut at full exposure
		maxVolumeDb = -8, -- world volume at full exposure
	}
end

function Hearing.new(settings)
	local self = setmetatable({}, Hearing)
	self.settings = settings or Hearing.defaultSettings()
	self.exposure = 0
	return self
end

-- Adds exposure 0..1: about 0.15 for an own rifle shot indoors, 1 for a blast nearby.
function Hearing:expose(amount: number)
	self.exposure = math.clamp(self.exposure + math.max(amount, 0), 0, 1)
end

-- Returns the ring volume 0..1, the treble cut and the volume cut (dB, <= 0).
function Hearing:update(dt: number): (number, number, number)
	local s = self.settings
	self.exposure *= math.exp(-dt / s.recovery)
	if self.exposure < 1e-3 then
		self.exposure = 0
	end
	local e = self.exposure
	local ring = math.clamp((e - s.ringAt) / (1 - s.ringAt), 0, 1)
	return ring, s.maxHighDb * e, s.maxVolumeDb * e
end

return Hearing
