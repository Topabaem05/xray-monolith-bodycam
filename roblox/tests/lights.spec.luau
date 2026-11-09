-- Lights: the flash curve, the muzzle flash, the weapon light with its bounce, lamps
-- that can be shot out, and night vision, on the mock client.
return function(T)
	local Env = T.require(T.Tests.mocks.RobloxEnv)
	local Fake = T.require(T.Tests.mocks.FakeInstances)

	local function load()
		local env = Env.new()
		env.install()
		local require = T.isolatedRequire()
		return env, require(T.Src.Lights)
	end

	T.test("the flash rises in milliseconds and dies away", function()
		local _, Lights = load()
		local F = Lights.FlashCurve
		local s = F.defaultSettings()
		T.equal(F.value(-1, s), 0, "nothing before the shot")
		T.near(F.value(s.attack / 2, s), 0.5, 1e-9, "rising")
		T.near(F.value(s.attack, s), 1, 1e-9, "peak")
		T.near(F.value(s.attack + s.decay, s), math.exp(-1), 1e-9, "falls by 1/e per decay time")
		T.near(F.value(F.duration(s), s), 0.01, 1e-9, "1 % at the duration")
		T.truthy(F.duration(s) < 0.2, "a flash is short")
	end)

	T.test("a shot lights the room and tells the camera's exposure", function()
		local env, Lights = load()
		local muzzle = CFrame.new(1, 5, -3)
		local flashes = {}
		local flash = Lights.muzzleFlash().new({
			getMuzzleCFrame = function()
				return muzzle
			end,
			screen = { notifyFlash = function(_, luminance)
				table.insert(flashes, luminance)
			end },
			random = function()
				return 0.5 -- no jitter
			end,
		})
		flash:start()
		T.equal(flash.light.Enabled, false, "dark until a shot")
		T.equal(flash.light.Shadows, true, "casts shadows")
		flash:fire()
		T.equal(#flashes, 1, "exposure notified")
		env.step(1 / 240)
		env.step(1 / 240)
		T.truthy(flash.light.Enabled, "lit")
		T.near(flash.light.Brightness, flash.settings.brightness * (1 / 240) / flash.settings.attack, 1e-6, "rising")
		T.equal(flash.part.CFrame, muzzle, "at the muzzle")
		local peak = 0
		for _ = 1, 60 do
			env.step(1 / 240)
			peak = math.max(peak, flash.light.Brightness)
		end
		T.truthy(peak > flash.settings.brightness * 0.6, "near full brightness: " .. peak)
		T.equal(flash.light.Enabled, false, "out after the flash")
		T.equal(flash.light.Brightness, 0, "no light left")
		flash:stop()
		T.equal(#env.bound, 0, "render step unbound")
	end)

	T.test("the weapon light trails the weapon and bounces off what it hits", function()
		local env, Lights = load()
		local beam = CFrame.new(0, 5, 0)
		local light = Lights.flashlight().new({ getBeamCFrame = function()
			return beam
		end })
		light:start()
		T.equal(light.beam.Enabled, false, "off at first")
		T.equal(light:toggle(), true, "toggled on")
		T.truthy(light.beam.Enabled, "beam on")
		env.step(1 / 60)
		T.equal(light.bounce.Enabled, false, "nothing to bounce off")

		-- A red wall 20 studs ahead (camera forward is -Z).
		local wall = Fake.new("Part", "Wall", { Color = Color3.new(1, 0.2, 0.2) })
		table.insert(env.walls, function(origin, direction)
			if direction.Z < 0 and origin.Z > -20 then
				local t = (-20 - origin.Z) / direction.Z
				if t <= 1 then
					return { Position = origin + direction * t, Normal = Vector3.new(0, 0, 1), Instance = wall }
				end
			end
			return nil
		end)
		env.step(1 / 60)
		T.truthy(light.bounce.Enabled, "bounce light on")
		T.near(light.bouncePart.CFrame.Position.Z, -20 + light.settings.bounceOffset, 1e-6, "just off the wall")
		T.truthy(light.bounce.Color.G < light.bounce.Color.R * 0.3, "tinted by the red wall")
		T.truthy(light.bounce.Brightness < light.settings.brightness * light.settings.bounceShare, "weaker with distance")

		-- A sudden 40 degree turn: the beam follows over a few frames.
		beam = CFrame.new(0, 5, 0) * CFrame.Angles(0, math.rad(40), 0)
		env.step(1 / 60)
		local look = light.part.CFrame.LookVector
		local turned = math.deg(math.atan2(-look.X, -look.Z))
		T.truthy(turned > 5 and turned < 35, "lagging: " .. turned)
		for _ = 1, 30 do
			env.step(1 / 60)
		end
		look = light.part.CFrame.LookVector
		T.near(math.deg(math.atan2(-look.X, -look.Z)), 40, 0.1, "caught up")

		light:setEnabled(false)
		T.equal(light.bounce.Enabled, false, "bounce off with the beam")
		light:stop()
	end)

	T.test("a tagged lamp goes out when shot, once", function()
		local _, Lights = load()
		local Shootable = Lights.shootableLights()
		local lamp = Fake.new("Model", "CeilingLamp", { tags = { [Shootable.TAG] = true } })
		local bulb = Fake.add(lamp, "Part", "Bulb", { Material = Enum.Material.Neon })
		local point = Fake.add(bulb, "PointLight", "Light", { Enabled = true })
		local cover = Fake.add(lamp, "Part", "Cover", { Material = Enum.Material.Metal })
		local crate = Fake.new("Part", "Crate")

		T.equal(Shootable.shoot(crate), nil, "untagged things are not lamps")
		T.equal(Shootable.find(cover), lamp, "any part of the lamp finds it")
		T.equal(Shootable.shoot(cover), lamp, "shot out")
		T.equal(point.Enabled, false, "light off")
		T.equal(bulb.Material, Enum.Material.Glass, "the glowing bulb goes dull")
		T.equal(cover.Material, Enum.Material.Metal, "other parts unchanged")
		T.equal(lamp:GetAttribute(Shootable.BROKEN), true, "marked broken")
		T.equal(Shootable.shoot(bulb), nil, "already broken")
	end)

	T.test("night vision tints, raises exposure and adds noise; off restores", function()
		local env, Lights = load()
		local screen = { offset = 0, gain = 1 }
		function screen:setExposureOffset(ev)
			self.offset = ev
		end
		function screen:setGrainGain(gain)
			self.gain = gain
		end
		local nv = Lights.nightVision().new({ screen = screen })
		T.equal(nv:toggle(), true, "on")
		local effect = nv.effect
		T.equal(effect.ClassName, "ColorCorrectionEffect", "a colour correction")
		T.equal(effect.Parent, env.Lighting, "in Lighting")
		T.equal(effect.Saturation, -1, "monochrome")
		T.equal(screen.offset, nv.settings.exposure, "exposure raised")
		T.equal(screen.gain, nv.settings.grainGain, "noise raised")
		nv:setEnabled(false)
		T.truthy(effect.destroyed, "effect removed")
		T.equal(screen.offset, 0, "exposure restored")
		T.equal(screen.gain, 1, "noise restored")
	end)
end
