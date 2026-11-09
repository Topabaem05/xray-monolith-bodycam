-- Ballistics: flight (drop, drag), penetration and ricochet, lag-compensation history,
-- the server's shot and hit checks, damage, and the Simulator on the mock world.
return function(T)
	local Env = T.require(T.Tests.mocks.RobloxEnv)
	local Fake = T.require(T.Tests.mocks.FakeInstances)

	local function load()
		local env = Env.new()
		env.install()
		local require = T.isolatedRequire()
		return env, require(T.Src.Ballistics)
	end

	T.test("a bullet drops with gravity and slows with drag", function()
		local _, B = load()
		local spec = B.Projectile.defaultSpec()
		spec.drag = 0
		local p = B.Projectile.new(spec, Vector3.new(0, 100, 0), Vector3.new(1, 0, 0))
		for _ = 1, 60 do
			p:step(1 / 120)
		end
		-- Half a second of flight.
		T.near(p.position.X, spec.speed * 0.5, 1e-6, "no drag: constant forward speed")
		T.near(100 - p.position.Y, 0.5 * spec.gravity * 0.25, 1e-6, "drop is half g t squared")
		T.near(B.Projectile.drop(spec.speed * 0.5, spec.speed, spec.gravity), 0.5 * spec.gravity * 0.25, 1e-9, "drop helper")

		local dragged = B.Projectile.defaultSpec()
		dragged.gravity = 0
		local q = B.Projectile.new(dragged, Vector3.zero, Vector3.new(1, 0, 0))
		while q.travelled < 1000 do
			q:step(1 / 120)
		end
		T.near(q:speed() / dragged.speed, math.exp(-dragged.drag * q.travelled), 0.01, "speed falls as exp(-drag * distance)")
	end)

	T.test("flight does not depend on the frame rate", function()
		local _, B = load()
		local spec = B.Projectile.defaultSpec()
		local a = B.Projectile.new(spec, Vector3.zero, Vector3.new(1, 0.02, 0))
		local b = B.Projectile.new(spec, Vector3.zero, Vector3.new(1, 0.02, 0))
		for _ = 1, 30 do
			a:step(1 / 30)
		end
		for _ = 1, 240 do
			b:step(1 / 240)
		end
		T.truthy((a.position - b.position).Magnitude < 2, "30 Hz and 240 Hz land within 2 studs after 1 s")
	end)

	T.test("a bullet is dropped at its range or when too slow", function()
		local _, B = load()
		local spec = B.Projectile.defaultSpec()
		spec.maxRange = 500
		local p = B.Projectile.new(spec, Vector3.zero, Vector3.new(1, 0, 0))
		local steps = 0
		while p.alive and steps < 1000 do
			p:step(1 / 60)
			steps += 1
		end
		T.truthy(not p.alive and p.travelled >= 500 and p.travelled < 560, "dropped just past the range")
		local q = B.Projectile.new(B.Projectile.defaultSpec(), Vector3.zero, Vector3.new(1, 0, 0))
		q:redirect(Vector3.zero, Vector3.new(1, 0, 0), 50, 1)
		T.truthy(not q.alive, "too slow after a wall")
	end)

	T.test("thin soft walls are crossed, thick hard ones stop the bullet", function()
		local _, B = load()
		local P = B.Penetration
		local base = { speed = 2500, power = 6, direction = Vector3.new(1, 0, 0), normal = Vector3.new(-1, 0, 0) }
		local function resolve(material, thickness)
			return P.resolve({
				speed = base.speed, power = base.power, direction = base.direction, normal = base.normal,
				material = material, thickness = thickness, random = function()
					return 0.99
				end,
			})
		end
		local wood = resolve("Wood", 1)
		T.equal(wood.kind, "Penetrate", "1 stud of wood")
		T.near(wood.power, 5, 1e-9, "costs 1 of 6")
		T.near(wood.speed, 2500 * math.sqrt(5 / 6), 1e-6, "energy loss: speed by the root")
		T.equal(resolve("Concrete", 2).kind, "Stop", "2 studs of concrete cost 10")
		T.equal(resolve("Wood", nil).kind, "Stop", "no far side found")
		T.equal(resolve("Glass", 0.2).kind, "Penetrate", "glass barely slows it")
		T.truthy(resolve("Flesh", 1).speed > resolve("Wood", 1).speed, "a body slows less than wood")
		T.equal(B.Materials.get("NoSuchMaterial"), B.Materials.Default, "unknown materials use the default")
	end)

	T.test("a grazing hit on metal glances off; a head-on hit never does", function()
		local _, B = load()
		local P = B.Penetration
		-- 5 degrees off a floor (normal +Y).
		local angle = math.rad(5)
		local direction = Vector3.new(math.cos(angle), -math.sin(angle), 0)
		local always = function()
			return 0
		end
		local out = P.resolve({
			speed = 2000, power = 6, direction = direction, normal = Vector3.new(0, 1, 0),
			material = "Metal", thickness = 1, random = always,
		})
		T.equal(out.kind, "Ricochet", "glances off")
		T.truthy(out.direction.Y > 0, "leaves the surface")
		T.truthy(out.direction.Y < math.sin(angle), "shallower than it came")
		T.near(out.direction.Magnitude, 1, 1e-9, "unit direction")
		T.near(out.speed, 2000 * B.Materials.get("Metal").ricochetKeep, 1e-9, "keeps part of its speed")
		local headOn = P.resolve({
			speed = 2000, power = 6, direction = Vector3.new(0, -1, 0), normal = Vector3.new(0, 1, 0),
			material = "Metal", thickness = 0.2, random = always,
		})
		T.equal(headOn.kind, "Penetrate", "head-on goes through thin metal")
		local glass = P.resolve({
			speed = 2000, power = 6, direction = direction, normal = Vector3.new(0, 1, 0),
			material = "Glass", thickness = 0.2, random = always,
		})
		T.equal(glass.kind, "Penetrate", "glass never ricochets")
	end)

	T.test("position history interpolates, clamps and forgets", function()
		local _, B = load()
		local history = B.PositionHistory.new(1)
		T.equal(history:sample("a", 0), nil, "unknown key")
		for i = 0, 10 do
			history:record("a", i * 0.1, Vector3.new(i, 0, 0))
		end
		T.near(history:sample("a", 0.55).X, 5.5, 1e-9, "between two samples")
		T.near(history:sample("a", 99).X, 10, 1e-9, "the future clamps to the newest")
		T.near(history:sample("a", -5).X, 0, 1e-9, "the past clamps to the oldest kept")
		for i = 11, 40 do
			history:record("a", i * 0.1, Vector3.new(i, 0, 0))
		end
		T.truthy(#history.tracks.a <= 12, "old samples are pruned: " .. #history.tracks.a)
		T.near(history:sample("a", 3.45).X, 34.5, 1e-9, "still exact inside the window")
		history:forget("a")
		T.equal(history:sample("a", 1), nil, "forgotten")
	end)

	T.test("the server accepts honest shots and refuses the rest", function()
		local _, B = load()
		local validator = B.ShotValidator.new()
		local head = Vector3.new(0, 5, 0)
		local function shot(overrides)
			local s = { time = 10, origin = Vector3.new(0.5, 5, 0), direction = Vector3.new(0, 0, -1) }
			for key, value in overrides or {} do
				s[key] = value
			end
			return s
		end
		local ok, reason = validator:checkShot("p", shot(), 600, head, 10.05)
		T.truthy(ok, "an honest shot: " .. tostring(reason))
		local function refused(overrides, now, expected)
			local good, why = B.ShotValidator.new():checkShot("p", shot(overrides), 600, head, now or 10.05)
			T.truthy(not good, expected .. " should be refused")
			T.equal(why, expected, "reason")
		end
		refused({ origin = Vector3.new(30, 5, 0) }, nil, "Origin")
		refused({ direction = Vector3.new(0, 0, -3) }, nil, "Direction")
		refused({ time = 9 }, nil, "Time")
		refused({ time = 11 }, nil, "Time")
		refused({ origin = Vector3.new(0 / 0, 5, 0) }, nil, "Number")
		refused({ time = "now" }, nil, "Time")

		-- Fire rate: 600 rpm is 10 shots a second.
		local honest = B.ShotValidator.new()
		local accepted = 0
		for i = 0, 29 do
			local now = 10 + i * 0.1
			if honest:checkShot("p", shot({ time = now }), 600, head, now) then
				accepted += 1
			end
		end
		T.equal(accepted, 30, "the weapon's own cadence passes")
		local cheat = B.ShotValidator.new()
		accepted = 0
		for i = 0, 59 do
			local now = 10 + i / 60 -- 60 shots in a second
			if cheat:checkShot("p", shot({ time = now }), 600, head, now) then
				accepted += 1
			end
		end
		T.truthy(accepted <= 15, "rapid fire is cut to the weapon's rate plus the burst: " .. accepted)
	end)

	T.test("a claimed hit must be on the line, in range and near the target", function()
		local _, B = load()
		local validator = B.ShotValidator.new()
		local s = { time = 10, origin = Vector3.new(0, 5, 0), direction = Vector3.new(0, 0, -1) }
		local target = Vector3.new(0, 3, -100)
		T.truthy(validator:checkHit(s, Vector3.new(0.5, 4.5, -100), target, 6000, 0), "a fair hit")
		local ok, why = validator:checkHit(s, Vector3.new(20, 5, -100), Vector3.new(20, 3, -100), 6000, 0)
		T.truthy(not ok and why == "Line", "off the line")
		ok, why = validator:checkHit(s, Vector3.new(0, 5, 100), nil, 6000, 0)
		T.truthy(not ok and why == "Range", "behind the muzzle")
		ok, why = validator:checkHit(s, Vector3.new(0, 5, -100), Vector3.new(0, 3, -130), 6000, 0)
		T.truthy(not ok and why == "Target", "the target was not there")
		-- Bullet drop is allowed for.
		local low = Vector3.new(0, 5 - 8, -2000)
		ok = validator:checkHit(s, low, nil, 6000, 0)
		T.truthy(not ok, "8 studs low without drop allowance")
		T.truthy(validator:checkHit(s, low, nil, 6000, B.Projectile.drop(2000, 2500, 35)), "allowed with the drop at 2000 studs")
	end)

	T.test("damage falls with distance, body part and lost speed", function()
		local _, B = load()
		local rifle = B.Catalog.get("Rifle")
		T.equal(B.Catalog.damage(rifle, 0, "UpperTorso"), rifle.damage, "muzzle, torso")
		T.equal(B.Catalog.damage(rifle, 99999, "UpperTorso"), rifle.minDamage, "far away")
		T.near(B.Catalog.damage(rifle, 0, "Head"), rifle.damage * rifle.headMultiplier, 1e-9, "head")
		T.near(B.Catalog.damage(rifle, 0, "LeftLowerArm"), rifle.damage * rifle.limbMultiplier, 1e-9, "limb")
		T.near(B.Catalog.damage(rifle, 0, "UpperTorso", 0.5), rifle.damage * 0.25, 1e-9, "half the speed, a quarter of the energy")
		T.truthy(B.Catalog.get("Pistol").power < rifle.power, "a pistol penetrates less")
	end)

	-- A slab across x = x0..x1 that rays cross from either side.
	local function slab(env, x0, x1, material, instance)
		table.insert(env.walls, function(origin, direction)
			local endX = origin.X + direction.X
			local face
			if origin.X < x0 and endX > x0 then
				face = x0
			elseif origin.X > x1 and endX < x1 then
				face = x1
			else
				return nil
			end
			local t = (face - origin.X) / direction.X
			return {
				Position = origin + direction * t,
				Normal = Vector3.new(if face == x0 then -1 else 1, 0, 0),
				Instance = instance,
				Material = { Name = material },
			}
		end)
	end

	T.test("the simulator flies a bullet through a wooden wall into a character", function()
		local env, B = load()
		local Simulator = B.simulator()
		local wall = Fake.new("Part", "Fence")
		local character = Fake.new("Model", "Enemy")
		Fake.add(character, "Humanoid", "Humanoid")
		local torso = Fake.add(character, "Part", "UpperTorso")
		slab(env, 50, 51, "Wood", wall)
		slab(env, 200, 201, "Plastic", torso)
		local impacts, segments, ended = {}, 0, 0
		local sim = Simulator.new({
			random = function()
				return 0.99
			end,
			onSegment = function()
				segments += 1
			end,
			onImpact = function(projectile, hit, outcome, humanoid)
				table.insert(impacts, { hit = hit, outcome = outcome, humanoid = humanoid, speed = projectile:speed() })
			end,
			onEnd = function()
				ended += 1
			end,
		})
		sim:start()
		local spec = B.Catalog.get("Rifle")
		local projectile = sim:fire(spec, Vector3.new(0, 5, 0), Vector3.new(1, 0, 0), { id = 7 })
		T.equal(projectile.data.id, 7, "data kept on the projectile")
		for _ = 1, 30 do
			env.step(1 / 60)
		end
		T.truthy(segments >= 3, "flew for several steps")
		T.equal(#impacts, 2, "fence, then the character")
		T.equal(impacts[1].hit.Instance, wall, "fence first")
		T.equal(impacts[1].outcome.kind, "Penetrate", "through 1 stud of wood")
		T.equal(impacts[1].humanoid, nil, "not a character")
		T.equal(impacts[2].hit.Instance, torso, "then the torso")
		T.truthy(impacts[2].humanoid ~= nil, "a character hit")
		T.truthy(impacts[2].speed < impacts[1].speed * 0.95, "slower after the fence")
		T.near(projectile.power, spec.power - 1 - 0.35, 1e-6, "wood cost 1, flesh 0.35")
		T.truthy(#sim.projectiles <= 1, "still flying or dropped")
		sim:stop()
		T.equal(#env.heartbeat.handlers, 0, "disconnected")
	end)

	T.test("a thick concrete wall stops the bullet, and costBetween prices the path", function()
		local env, B = load()
		local Simulator = B.simulator()
		local bunker = Fake.new("Part", "Bunker")
		slab(env, 30, 34, "Concrete", bunker)
		local outcomes, ended = {}, 0
		local sim = Simulator.new({
			onImpact = function(_, _, outcome)
				table.insert(outcomes, outcome.kind)
			end,
			onEnd = function()
				ended += 1
			end,
		})
		sim:fire(B.Catalog.get("Rifle"), Vector3.new(0, 5, 0), Vector3.new(1, 0, 0))
		for _ = 1, 10 do
			sim:update(1 / 60)
		end
		T.equal(outcomes[1], "Stop", "4 studs of concrete")
		T.equal(#outcomes, 1, "one impact")
		T.equal(ended, 1, "bullet dropped")
		T.equal(#sim.projectiles, 0, "nothing left flying")

		local stone = B.Materials.get("Concrete").hardness
		T.near(Simulator.costBetween(Vector3.new(0, 5, 0), Vector3.new(100, 5, 0)), 4 * stone, 1e-6, "4 studs of concrete")
		T.equal(Simulator.costBetween(Vector3.new(0, 5, 0), Vector3.new(20, 5, 0)), 0, "open path")
	end)
end
