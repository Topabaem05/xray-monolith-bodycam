-- MicAgc: the automatic gain of a small body-worn microphone. A loud sound overloads
-- it (clipping), the gain drops at once, holds, and comes back slowly, so the world
-- goes quiet after gunfire. Pure Luau. Written for this project.

local MicAgc = {}
MicAgc.__index = MicAgc

function MicAgc.defaultSettings()
	return {
		threshold = 0.25, -- loudness (0..1) the mic takes without ducking
		maxDuckDb = -18, -- gain at loudness 1
		hold = 0.12, -- seconds at the ducked gain
		release = 0.9, -- seconds time constant back to full gain
		clipDecay = 0.08, -- seconds time constant of the overload distortion
	}
end

function MicAgc.new(settings)
	local self = setmetatable({}, MicAgc)
	self.settings = settings or MicAgc.defaultSettings()
	self.gainDb = 0
	self.clip = 0
	self.holdLeft = 0
	return self
end

-- A sound of `loudness` 0..1 at the microphone (after distance and walls).
function MicAgc:hit(loudness: number)
	local s = self.settings
	loudness = math.clamp(loudness, 0, 1)
	if loudness <= s.threshold then
		return
	end
	local over = (loudness - s.threshold) / (1 - s.threshold)
	local duck = s.maxDuckDb * over
	if duck < self.gainDb then
		self.gainDb = duck
	end
	self.holdLeft = s.hold
	self.clip = math.max(self.clip, over)
end

-- Returns the gain (dB, <= 0) and the overload 0..1.
function MicAgc:update(dt: number): (number, number)
	local s = self.settings
	if self.holdLeft > 0 then
		self.holdLeft -= dt
	else
		self.gainDb *= math.exp(-dt / s.release)
		if self.gainDb > -0.01 then
			self.gainDb = 0
		end
	end
	self.clip *= math.exp(-dt / s.clipDecay)
	if self.clip < 1e-3 then
		self.clip = 0
	end
	return self.gainDb, self.clip
end

return MicAgc
