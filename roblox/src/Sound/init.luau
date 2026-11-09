-- Sound: positional gunfire heard through a bodycam microphone (guide code).
--
-- Pure modules: Acoustics (occlusion, distance layers, delay, reverb, near miss),
--               MicAgc (automatic gain and overload), Hearing (ringing ears)
-- Roblox:       Enclosure (how closed-in a place is), SoundDirector (the adapter)
-- Written for this project. Sound assets are not included.

local Sound = {
	Acoustics = require(script.Acoustics),
	MicAgc = require(script.MicAgc),
	Hearing = require(script.Hearing),
}

function Sound.enclosure()
	return require(script.Enclosure)
end

function Sound.director()
	return require(script.SoundDirector)
end

return Sound
