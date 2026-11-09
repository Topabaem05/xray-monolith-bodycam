-- Lights: gunfire and lamps that light the scene (guide code).
--
--   FlashCurve       muzzle flash brightness over time (pure)
--   MuzzleFlash      a shadow-casting light per shot, and the exposure dip after it
--   Flashlight       weapon light with lag and a fake bounce light
--   ShootableLights  tagged lamps that go out when shot
--   NightVision      green monochrome, raised exposure, sensor noise
-- Written for this project.

local Lights = {
	FlashCurve = require(script.FlashCurve),
}

function Lights.muzzleFlash()
	return require(script.MuzzleFlash)
end

function Lights.flashlight()
	return require(script.Flashlight)
end

function Lights.shootableLights()
	return require(script.ShootableLights)
end

function Lights.nightVision()
	return require(script.NightVision)
end

return Lights
