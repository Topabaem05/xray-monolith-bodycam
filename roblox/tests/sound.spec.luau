-- Sound: acoustics numbers, the microphone's automatic gain, ringing ears, enclosure,
-- and the SoundDirector on the mock client.
return function(T)
	local Env = T.require(T.Tests.mocks.RobloxEnv)
	local Fake = T.require(T.Tests.mocks.FakeInstances)

	local function load()
		local env = Env.new()
		env.install()
		local require = T.isolatedRequire()
		return env, require(T.Src.Sound), require
	end

	T.test("walls cut the volume and cut the treble more", function()
		local _, Sound = load()
		local A = Sound.Acoustics
		local s = A.defaultSettings()
		local v0, h0, m0 = A.occlusion(0, 0, s)
		T.equal(v0 + h0 + m0, 0, "open air")
		local v1, h1, m1 = A.occlusion(1, 1, s)
		T.truthy(v1 < 0 and h1 < v1, "treble falls faster than volume")
		T.truthy(m1 < 0 and m1 > h1, "mids fall less than treble")
		local v2 = A.occlusion(2, 2, s)
		T.truthy(v2 < v1, "two walls are quieter")
		local v9, h9 = A.occlusion(9, 40, s)
		T.equal(v9, s.occlusion.maxDb, "volume loss is capped")
		T.equal(h9, s.occlusion.maxHighDb, "treble loss is capped")
		T.near(A.dbToGain(-6), 0.501, 1e-3, "-6 dB halves the amplitude")
	end)

	T.test("distance crossfades the recordings at equal power and delays the sound", function()
		local _, Sound = load()
		local A = Sound.Acoustics
		local s = A.defaultSettings()
		local c, m, f = A.layerWeights(0, s)
		T.equal(c, 1, "close up: the close recording")
		T.equal(m + f, 0, "only")
		for _, distance in { 10, 50, 65, 200, 300, 400, 1000 } do
			c, m, f = A.layerWeights(distance, s)
			T.near(c * c + m * m + f * f, 1, 1e-9, "equal power at " .. distance)
		end
		c, m, f = A.layerWeights(1000, s)
		T.near(f, 1, 1e-9, "far away: the far recording")
		T.equal(select("#", A.layerWeights(5000, s)), 3, "three weights")
		T.equal(A.layerWeights(5000, s), 0, "silent beyond the maximum")
		T.near(A.delay(343 * s.studsPerMetre, s), 1, 1e-9, "343 m takes a second")
		T.truthy(A.isSupersonic(2500, s) and not A.isSupersonic(1000, s), "rifle bullets crack, slow ones do not")
	end)

	T.test("rooms ring longer than open ground, big rooms longest", function()
		local _, Sound = load()
		local A = Sound.Acoustics
		local s = A.defaultSettings()
		local outdoor = A.reverb({ indoor = 0, size = 120 }, s)
		local closet = A.reverb({ indoor = 1, size = 4 }, s)
		local hall = A.reverb({ indoor = 1, size = 50 }, s)
		T.truthy(hall.decay > closet.decay, "hall rings longer than a closet")
		T.truthy(closet.wetDb > outdoor.wetDb, "indoors is wetter")
		T.near(outdoor.decay, s.reverb.outdoorDecay, 1e-9, "outdoor slap")
		T.truthy(hall.decay <= s.reverb.maxIndoorDecay, "capped")
	end)

	T.test("near miss geometry", function()
		local _, Sound = load()
		local A = Sound.Acoustics
		-- A bullet flying along +X from the origin for 100 studs; listener 3 studs beside x = 40.
		local distance, along = A.nearMiss(0, 0, 0, 1, 0, 0, 100, 40, 3, 0)
		T.near(distance, 3, 1e-9, "passing distance")
		T.near(along, 40, 1e-9, "where along the path")
		distance, along = A.nearMiss(0, 0, 0, 1, 0, 0, 100, -20, 0, 0)
		T.equal(along, 0, "behind the muzzle clamps to the start")
		T.near(distance, 20, 1e-9, "distance to the start")
	end)

	T.test("the microphone ducks at once, holds, and recovers slowly", function()
		local _, Sound = load()
		local agc = Sound.MicAgc.new()
		agc:hit(0.2)
		T.equal(agc.gainDb, 0, "quiet sounds do not duck")
		agc:hit(1)
		local gain, clip = agc:update(1 / 60)
		T.near(gain, agc.settings.maxDuckDb, 1e-9, "full duck, held")
		T.truthy(clip > 0.5, "overloaded")
		for _ = 1, 30 do
			gain, clip = agc:update(1 / 60)
		end
		T.truthy(gain > agc.settings.maxDuckDb and gain < -5, "recovering after half a second: " .. gain)
		T.truthy(clip < 0.01, "overload gone")
		for _ = 1, 600 do
			gain = agc:update(1 / 60)
		end
		T.equal(gain, 0, "back to full gain")

		-- The recovery does not depend on the frame rate.
		local a, b = Sound.MicAgc.new(), Sound.MicAgc.new()
		a:hit(1)
		b:hit(1)
		for _ = 1, 60 do
			a:update(1 / 60)
		end
		for _ = 1, 240 do
			b:update(1 / 240)
		end
		T.near(a.gainDb, b.gainDb, 0.3, "60 Hz and 240 Hz agree")
	end)

	T.test("ears ring after enough exposure and recover", function()
		local _, Sound = load()
		local hearing = Sound.Hearing.new()
		hearing:expose(0.12)
		local ring, high = hearing:update(1 / 60)
		T.equal(ring, 0, "one shot does not ring")
		T.truthy(high < 0, "but dulls the treble a little")
		for _ = 1, 5 do
			hearing:expose(0.12)
		end
		ring, high = hearing:update(1 / 60)
		T.truthy(ring > 0.2, "a burst rings: " .. ring)
		T.truthy(high < -10, "and dulls more")
		for _ = 1, 60 * 30 do
			ring, high = hearing:update(1 / 60)
		end
		T.equal(ring, 0, "ringing fades")
		T.equal(high, 0, "hearing recovers")
	end)

	T.test("enclosure: a ceiling counts double", function()
		local env, Sound = load()
		local Enclosure = Sound.enclosure()
		local open = Enclosure.summarise({}, 9, 120)
		T.equal(open.indoor, 0, "open sky")
		T.equal(open.size, 120, "nothing near")
		local roofOnly = Enclosure.summarise({ 8 }, 9, 120)
		T.near(roofOnly.indoor, 2 / 10, 1e-9, "roof weight 2 of 10")
		local room = {}
		for i = 1, 9 do
			room[i] = 10
		end
		local closed = Enclosure.summarise(room, 9, 120)
		T.equal(closed.indoor, 1, "closed room")
		T.equal(closed.size, 10, "mean distance")
		-- probe() through the mock: every ray hits 6 studs away.
		table.insert(env.walls, function(origin, direction)
			return { Position = origin + direction.Unit * 6 }
		end)
		local probed = Enclosure.probe(Vector3.new(0, 5, 0))
		T.equal(probed.indoor, 1, "probe: indoors")
		T.near(probed.size, 6, 1e-9, "probe: size")
	end)

	-- A 2-stud concrete wall across x = 10..12.
	local function slab(env)
		local part = Fake.new("Part", "Wall")
		table.insert(env.walls, function(origin, direction)
			local endX = origin.X + direction.X
			local face
			if origin.X < 10 and endX > 10 then
				face = 10
			elseif origin.X > 12 and endX < 12 then
				face = 12
			else
				return nil
			end
			local t = (face - origin.X) / direction.X
			return {
				Position = origin + direction * t,
				Normal = Vector3.new(if face == 10 then -1 else 1, 0, 0),
				Instance = part,
				Material = { Name = "Concrete" },
			}
		end)
		return part
	end

	T.test("the director plays own shots at once and ducks the microphone", function()
		local env, Sound = load()
		env.camera.CFrame = CFrame.new(0, 5, 0)
		local Director = Sound.director()
		local library = Director.defaultSounds()
		library.gunshots.Rifle.close = "rbxassetid://1"
		library.gunshots.Rifle.mid = "rbxassetid://2"
		library.gunshots.Rifle.far = "rbxassetid://3"
		library.gunshots.Rifle.outdoorTail = "rbxassetid://4"
		local director = Director.new({ sounds = library })
		director:start()
		T.equal(director.world.Parent, director.master, "world group inside the microphone group")
		local before = #env.created
		director:playGunshot("Rifle", Vector3.new(0, 5, 0), { own = true })
		local played = {}
		for i = before + 1, #env.created do
			local inst = env.created[i]
			if inst.ClassName == "Sound" then
				played[inst.SoundId] = inst
			end
		end
		T.truthy(played["rbxassetid://1"] and played["rbxassetid://1"].plays == 1, "close recording plays at once")
		T.equal(played["rbxassetid://2"], nil, "no mid layer at the muzzle")
		T.truthy(played["rbxassetid://4"], "outdoor tail under open sky")
		env.step(1 / 60)
		T.truthy(director.master.Volume < 0.3, "microphone ducked: " .. director.master.Volume)
		T.truthy(director.distortion.Level > 0.2, "and overloaded")
		for _ = 1, 600 do
			env.step(1 / 60)
		end
		T.near(director.master.Volume, 1, 1e-6, "gain recovered")
		director:stop()
		T.truthy(director.master.destroyed, "groups removed")
	end)

	T.test("a distant shot behind a wall arrives late, quieter and duller", function()
		local env, Sound = load()
		env.camera.CFrame = CFrame.new(0, 5, 0)
		slab(env)
		local Director = Sound.director()
		local library = Director.defaultSounds()
		library.gunshots.Rifle.mid = "rbxassetid://2"
		local director = Director.new({ sounds = library })
		director:start()
		local walls, thickness = director:wallsBetween(Vector3.new(200, 5, 0), Vector3.new(0, 5, 0))
		T.equal(walls, 1, "one wall")
		T.near(thickness, 2, 1e-6, "two studs thick")

		local before = #env.created
		director:playGunshot("Rifle", Vector3.new(200, 5, 0))
		local function find()
			for i = before + 1, #env.created do
				if env.created[i].ClassName == "Sound" then
					return env.created[i], env.created[i + 1]
				end
			end
			return nil
		end
		T.equal(find(), nil, "not heard yet: sound takes time")
		T.near(env.delayed[1].seconds, 200 / (343 / 0.28), 1e-6, "speed-of-sound delay")
		env.runDelayed()
		local sound, effect = find()
		T.truthy(sound, "heard after the delay")
		local _, expectedHigh = Sound.Acoustics.occlusion(1, 2, director.acoustics)
		T.truthy(sound.Volume < 0.5, "quieter through the wall: " .. sound.Volume)
		T.equal(effect.ClassName, "EqualizerSoundEffect", "muffled")
		T.near(effect.HighGain, expectedHigh, 1e-9, "treble cut for one 2-stud wall")
		director:stop()
	end)

	T.test("a bullet passing close cracks and reports the near miss", function()
		local env, Sound = load()
		env.camera.CFrame = CFrame.new(0, 5, 0)
		local Director = Sound.director()
		local library = Director.defaultSounds()
		library.crack = "rbxassetid://9"
		local misses = {}
		local director = Director.new({ sounds = library, onNearMiss = function(distance)
			table.insert(misses, distance)
		end })
		director:start()
		-- Flying along +X, 4 studs above the listener.
		local distance = director:bulletPassed(Vector3.new(-100, 9, 0), Vector3.new(1, 0, 0), 200, 2500)
		T.near(distance, 4, 1e-9, "passing distance")
		T.equal(#misses, 1, "near miss reported")
		local before = #env.created
		env.runDelayed()
		local crack
		for i = before + 1, #env.created do
			if env.created[i].SoundId == "rbxassetid://9" then
				crack = env.created[i]
			end
		end
		T.truthy(crack and crack.Volume > 0.5, "crack played, loud when close")
		-- Far away: nothing.
		director:bulletPassed(Vector3.new(-100, 80, 0), Vector3.new(1, 0, 0), 200, 2500)
		T.equal(#misses, 1, "a distant bullet is not a near miss")
		director:stop()
	end)
end
