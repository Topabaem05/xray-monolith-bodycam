-- FlashCurve: a muzzle flash's brightness over time: a few milliseconds up, then an
-- exponential fall. Pure Luau. Written for this project.

local FlashCurve = {}

function FlashCurve.defaultSettings()
	return {
		attack = 0.008, -- seconds to full brightness
		decay = 0.03, -- seconds time constant of the fall
		brightness = 9, -- PointLight.Brightness at the peak
		range = 30, -- PointLight.Range in studs
		jitter = 0.25, -- shot-to-shot brightness spread (+-)
		flashLuminance = 0.9, -- what the camera's auto exposure sees at the peak (0..1)
	}
end

-- Brightness share 0..1 at `t` seconds after the shot.
function FlashCurve.value(t: number, settings): number
	if t < 0 then
		return 0
	elseif t < settings.attack then
		return t / settings.attack
	end
	return math.exp(-(t - settings.attack) / settings.decay)
end

-- Seconds until the flash is below 1 % of its peak.
function FlashCurve.duration(settings): number
	return settings.attack + settings.decay * math.log(100)
end

return FlashCurve
