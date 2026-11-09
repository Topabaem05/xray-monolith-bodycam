-- Acoustics: the numbers behind positional gunfire. Pure Luau (no Roblox API).
--
--   occlusion     walls between source and listener -> volume and tone loss (dB)
--   layerWeights  close / mid / far recordings crossfaded by distance
--   delay         the sound arrives later than the flash (speed of sound)
--   reverb        room size and openness -> reverb settings
--   nearMiss      how close a bullet's path passes the listener
-- Written for this project. Distances are studs unless a name says metres.

local Acoustics = {}

Acoustics.SPEED_OF_SOUND = 343 -- m/s

function Acoustics.defaultSettings()
	return {
		studsPerMetre = 1 / 0.28,
		occlusion = {
			wallDb = -7, -- volume per wall crossed
			studDb = -1.2, -- volume per stud of wall thickness
			maxDb = -30,
			wallHighDb = -12, -- treble per wall: walls pass the thump, not the crack
			studHighDb = -3,
			maxHighDb = -60,
			midShare = 0.35, -- share of the treble cut the mids take
		},
		layers = {
			closeEnd = 70, -- the close recording is gone by here
			midStart = 35,
			midEnd = 450,
			farStart = 250,
			maxDistance = 3000,
		},
		reverb = {
			outdoorDecay = 0.9, -- seconds: a short slap from far surfaces
			minIndoorDecay = 0.35,
			maxIndoorDecay = 2.4,
			decayPerStud = 0.035, -- bigger rooms ring longer
			outdoorWetDb = -16,
			indoorWetDb = -4,
		},
	}
end

function Acoustics.dbToGain(db: number): number
	return 10 ^ (db / 20)
end

-- Volume, treble and mid change (dB, <= 0) for `walls` crossed with a total
-- `thickness` in studs.
function Acoustics.occlusion(walls: number, thickness: number, settings): (number, number, number)
	local o = settings.occlusion
	if walls <= 0 then
		return 0, 0, 0
	end
	local volume = math.max(o.maxDb, walls * o.wallDb + thickness * o.studDb)
	local high = math.max(o.maxHighDb, walls * o.wallHighDb + thickness * o.studHighDb)
	return volume, high, high * o.midShare
end

local function fade(x: number, from: number, to: number): number
	if to <= from then
		return if x >= to then 1 else 0
	end
	return math.clamp((x - from) / (to - from), 0, 1)
end

-- Equal-power weights for the close, mid and far recordings at a distance.
function Acoustics.layerWeights(distance: number, settings): (number, number, number)
	local l = settings.layers
	if distance >= l.maxDistance then
		return 0, 0, 0
	end
	local toMid = fade(distance, l.midStart, l.closeEnd)
	local toFar = fade(distance, l.farStart, l.midEnd)
	local close = math.cos(toMid * math.pi / 2)
	local mid = math.sin(toMid * math.pi / 2) * math.cos(toFar * math.pi / 2)
	local far = math.sin(toFar * math.pi / 2)
	return close, mid, far
end

-- Seconds for sound to travel a distance in studs.
function Acoustics.delay(distance: number, settings): number
	return distance / (Acoustics.SPEED_OF_SOUND * settings.studsPerMetre)
end

function Acoustics.isSupersonic(speed: number, settings): boolean
	return speed > Acoustics.SPEED_OF_SOUND * settings.studsPerMetre
end

-- Reverb for an enclosure { indoor = 0..1, size = studs to the surfaces around }.
function Acoustics.reverb(enclosure, settings)
	local r = settings.reverb
	local indoor = math.clamp(enclosure.indoor, 0, 1)
	local roomDecay = math.clamp(r.minIndoorDecay + enclosure.size * r.decayPerStud, r.minIndoorDecay, r.maxIndoorDecay)
	return {
		decay = r.outdoorDecay + (roomDecay - r.outdoorDecay) * indoor,
		wetDb = r.outdoorWetDb + (r.indoorWetDb - r.outdoorWetDb) * indoor,
		density = 0.5 + 0.5 * indoor,
		diffusion = 0.6 + 0.4 * indoor,
	}
end

-- How a bullet path (origin, unit direction, length) passes a listener: the closest
-- distance and how far along the path that point is. Components, so no Vector3.
function Acoustics.nearMiss(
	ox: number, oy: number, oz: number,
	dx: number, dy: number, dz: number,
	length: number,
	lx: number, ly: number, lz: number
): (number, number)
	local rx, ry, rz = lx - ox, ly - oy, lz - oz
	local along = math.clamp(rx * dx + ry * dy + rz * dz, 0, length)
	local cx, cy, cz = ox + dx * along - lx, oy + dy * along - ly, oz + dz * along - lz
	return math.sqrt(cx * cx + cy * cy + cz * cz), along
end

return Acoustics
