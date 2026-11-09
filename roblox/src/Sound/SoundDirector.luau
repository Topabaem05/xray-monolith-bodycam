-- SoundDirector: positional gunfire through a bodycam microphone. Guide code: the
-- structure and the numbers are here; the sound assets are not (every id in
-- defaultSounds() is empty, and an empty id plays nothing).
--
--   * Gunshots: close / mid / far recordings crossfaded by distance, heard after the
--     speed-of-sound delay, quieter and duller through walls, with an indoor or
--     outdoor tail.
--   * Bullets passing close: a crack (supersonic) or a whiz, and onNearMiss(distance).
--   * The microphone: a master SoundGroup with a compressor, an equaliser and
--     overload distortion; loud sounds duck its gain (MicAgc).
--   * The ears: own unsuppressed fire indoors dulls the treble and starts a ringing.
--   * The room: a reverb that follows how closed-in the listener is (Enclosure).
--
-- Uses Sound, SoundGroup and the SoundEffect classes. Roblox's newer Audio API
-- (AudioFilter low-pass per emitter) would muffle more convincingly than the
-- equaliser used here; see roblox/README.md.
-- Written for this project.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Acoustics = require(script.Parent.Acoustics)
local Enclosure = require(script.Parent.Enclosure)
local Hearing = require(script.Parent.Hearing)
local MicAgc = require(script.Parent.MicAgc)

local SoundDirector = {}
SoundDirector.__index = SoundDirector

local MAX_WALLS = 4
local MAX_WALL_THICKNESS = 12 -- studs searched for a wall's far side
local SOUND_LIFETIME = 8 -- seconds before a one-shot is removed

local function gunshot(loudness: number)
	return { close = "", mid = "", far = "", indoorTail = "", outdoorTail = "", loudness = loudness, volume = 1 }
end

-- Asset ids ("rbxassetid://...") to fill in. Keys of `gunshots` are weapon names.
function SoundDirector.defaultSounds()
	return {
		gunshots = { Rifle = gunshot(1), Pistol = gunshot(0.8) },
		crack = "", -- supersonic bullet passing
		whiz = "", -- subsonic bullet passing
		tinnitus = "", -- looped ringing tone
		breathing = "", -- looped breathing
	}
end

function SoundDirector.defaultMix()
	return {
		micLowDb = -6, -- a small microphone has little bass
		micHighDb = -3,
		compressorThreshold = -22,
		compressorRatio = 8,
		maxDistortion = 0.45, -- DistortionSoundEffect.Level at full overload
		nearMissRadius = 25, -- studs
		enclosureRate = 2, -- probes per second
		reverbSmoothing = 0.4, -- seconds
		ownIndoorExposure = 0.12, -- Hearing exposure per own unsuppressed shot indoors
		suppressedLoudness = 0.3,
		loudnessFalloff = 30, -- studs where a shot is half as loud to the microphone
	}
end

-- options:
--   sounds        table shaped like defaultSounds()
--   acoustics     Acoustics settings
--   mix           table shaped like defaultMix()
--   getListener   fn() -> Vector3 (default the camera position)
--   rayParams     RaycastParams for walls (default excludes the local character)
--   onNearMiss    fn(distance in studs), e.g. presenter:onNearMiss
--   getExertion   fn() -> 0..1 for the breathing loop
--   parent        where one-shot sounds are put (default Workspace.Terrain)
function SoundDirector.new(options)
	options = options or {}
	local self = setmetatable({}, SoundDirector)
	self.options = options
	self.sounds = options.sounds or SoundDirector.defaultSounds()
	self.acoustics = options.acoustics or Acoustics.defaultSettings()
	self.mix = options.mix or SoundDirector.defaultMix()
	self.agc = MicAgc.new(options.agc)
	self.hearing = Hearing.new(options.hearing)
	self.enclosure = { indoor = 0, size = 120 }
	self.reverbNow = Acoustics.reverb(self.enclosure, self.acoustics)
	self.probeIn = 0
	self.instances = {}
	self.started = false
	return self
end

function SoundDirector:_make(className: string, parent, properties)
	local instance = Instance.new(className)
	for key, value in properties or {} do
		instance[key] = value
	end
	instance.Parent = parent
	table.insert(self.instances, instance)
	return instance
end

function SoundDirector:_loop(id: string, name: string)
	if id == "" then
		return nil
	end
	local sound = self:_make("Sound", self.master, { Name = name, SoundId = id, Looped = true, Volume = 0 })
	sound.SoundGroup = self.master
	sound:Play()
	return sound
end

function SoundDirector:start()
	if self.started then
		return
	end
	self.started = true
	local mix = self.mix
	-- Everything the microphone hears goes through `master`; the world (not the
	-- ringing in the ears) also through `world`.
	self.master = self:_make("SoundGroup", SoundService, { Name = "BodycamMic" })
	self.compressor = self:_make("CompressorSoundEffect", self.master, {
		Threshold = mix.compressorThreshold,
		Ratio = mix.compressorRatio,
		Attack = 0.003,
		Release = 0.25,
	})
	self.distortion = self:_make("DistortionSoundEffect", self.master, { Level = 0 })
	self:_make("EqualizerSoundEffect", self.master, { LowGain = mix.micLowDb, MidGain = 0, HighGain = mix.micHighDb })
	self.world = self:_make("SoundGroup", self.master, { Name = "World" })
	self.reverb = self:_make("ReverbSoundEffect", self.world, { DryLevel = 0 })
	self.ears = self:_make("EqualizerSoundEffect", self.world, { LowGain = 0, MidGain = 0, HighGain = 0 })
	self.tinnitus = self:_loop(self.sounds.tinnitus, "Tinnitus")
	self.breathing = self:_loop(self.sounds.breathing, "Breathing")
	self.connection = RunService.Heartbeat:Connect(function(dt)
		self:update(dt)
	end)
end

function SoundDirector:stop()
	if not self.started then
		return
	end
	self.started = false
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	for _, instance in self.instances do
		instance:Destroy()
	end
	self.instances = {}
end

function SoundDirector:_listener(): Vector3
	if self.options.getListener then
		return self.options.getListener()
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.zero
end

function SoundDirector:_rayParams()
	if self.options.rayParams then
		return self.options.rayParams
	end
	local params = self._params
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		self._params = params
	end
	local player = Players.LocalPlayer
	params.FilterDescendantsInstances = { player and player.Character }
	return params
end

-- Walls between two points: how many, and their total thickness in studs.
function SoundDirector:wallsBetween(from: Vector3, to: Vector3): (number, number)
	local params = self:_rayParams()
	local walls, thickness = 0, 0
	local origin = from
	local only = RaycastParams.new()
	only.FilterType = Enum.RaycastFilterType.Include
	while walls < MAX_WALLS do
		local offset = to - origin
		local length = offset.Magnitude
		if length < 0.05 then
			break
		end
		local hit = Workspace:Raycast(origin, offset, params)
		if not hit then
			break
		end
		walls += 1
		local direction = offset.Unit
		local reach = math.min(MAX_WALL_THICKNESS, (to - hit.Position).Magnitude)
		-- The far side: look back at the same part from beyond it.
		only.FilterDescendantsInstances = { hit.Instance }
		local back = Workspace:Raycast(hit.Position + direction * reach, -direction * reach, only)
		local through = if back then (back.Position - hit.Position).Magnitude else reach
		thickness += through
		origin = hit.Position + direction * (through + 0.05)
	end
	return walls, thickness
end

-- A one-shot at a world position. Returns the Sound, or nil for an empty id.
function SoundDirector:_emit(id: string, position: Vector3, volume: number, highDb: number, midDb: number)
	if id == "" or volume <= 0.001 then
		return nil
	end
	local parent = self.options.parent or Workspace.Terrain or Workspace
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = parent
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 20
	sound.RollOffMaxDistance = self.acoustics.layers.maxDistance
	sound.SoundGroup = self.world
	sound.Parent = attachment
	if highDb < 0 then
		local muffle = Instance.new("EqualizerSoundEffect")
		muffle.LowGain = 0
		muffle.MidGain = midDb
		muffle.HighGain = highDb
		muffle.Parent = sound
	end
	sound:Play()
	task.delay(SOUND_LIFETIME, function()
		attachment:Destroy()
	end)
	return sound
end

-- Plays weapon `name`'s shot from `position`.
--   info.own         the local player's shot: no delay, no walls, the close recording
--   info.suppressed  quieter to the microphone and no ear exposure
function SoundDirector:playGunshot(name: string, position: Vector3, info)
	local def = self.sounds.gunshots[name]
	if not (def and self.started) then
		return
	end
	info = info or {}
	local mix = self.mix
	local listener = self:_listener()
	local distance = if info.own then 0 else (position - listener).Magnitude
	local close, mid, far = Acoustics.layerWeights(distance, self.acoustics)
	local volumeDb, highDb, midDb = 0, 0, 0
	if not info.own then
		local walls, thickness = self:wallsBetween(position, listener)
		volumeDb, highDb, midDb = Acoustics.occlusion(walls, thickness, self.acoustics)
	end
	local gain = def.volume * Acoustics.dbToGain(volumeDb)
	local indoor = self.enclosure.indoor
	local loudness = def.loudness * Acoustics.dbToGain(volumeDb) / (1 + distance / mix.loudnessFalloff)
	if info.suppressed then
		loudness *= mix.suppressedLoudness
	end
	local function play()
		if not self.started then
			return
		end
		self:_emit(def.close, position, gain * close, highDb, midDb)
		self:_emit(def.mid, position, gain * mid, highDb, midDb)
		self:_emit(def.far, position, gain * far, highDb, midDb)
		self:_emit(def.indoorTail, position, gain * indoor * math.max(close, mid), highDb, midDb)
		self:_emit(def.outdoorTail, position, gain * (1 - indoor), highDb, midDb)
		self.agc:hit(loudness)
		if info.own and not info.suppressed then
			self.hearing:expose(mix.ownIndoorExposure * indoor * def.loudness)
		end
	end
	local delay = Acoustics.delay(distance, self.acoustics)
	if delay < 1 / 60 then
		play()
	else
		task.delay(delay, play)
	end
end

-- A bullet flew from `origin` along unit `direction` for `length` studs at `speed`
-- studs/s. Plays the crack or whiz if it passed close. Returns the passing distance.
function SoundDirector:bulletPassed(origin: Vector3, direction: Vector3, length: number, speed: number): number
	local listener = self:_listener()
	local distance, along = Acoustics.nearMiss(
		origin.X, origin.Y, origin.Z,
		direction.X, direction.Y, direction.Z,
		length,
		listener.X, listener.Y, listener.Z
	)
	if distance > self.mix.nearMissRadius or along <= 0 or along >= length then
		return distance
	end
	local id = if Acoustics.isSupersonic(speed, self.acoustics) then self.sounds.crack else self.sounds.whiz
	local closeness = 1 - distance / self.mix.nearMissRadius
	local point = origin + direction * along
	task.delay(along / math.max(speed, 1), function()
		if self.started then
			self:_emit(id, point, closeness, 0, 0)
			self.agc:hit(0.5 * closeness)
		end
	end)
	if self.options.onNearMiss then
		self.options.onNearMiss(distance)
	end
	return distance
end

function SoundDirector:update(dt: number)
	local mix = self.mix
	self.probeIn -= dt
	if self.probeIn <= 0 then
		self.probeIn = 1 / mix.enclosureRate
		self.enclosure = Enclosure.probe(self:_listener(), self:_rayParams())
	end
	local target = Acoustics.reverb(self.enclosure, self.acoustics)
	local alpha = 1 - math.exp(-dt / mix.reverbSmoothing)
	local now = self.reverbNow
	for key, value in target do
		now[key] += (value - now[key]) * alpha
	end
	self.reverb.DecayTime = now.decay
	self.reverb.WetLevel = now.wetDb
	self.reverb.Density = now.density
	self.reverb.Diffusion = now.diffusion

	local gainDb, clip = self.agc:update(dt)
	local ring, earHighDb, earVolumeDb = self.hearing:update(dt)
	self.master.Volume = Acoustics.dbToGain(gainDb)
	self.distortion.Level = clip * mix.maxDistortion
	self.world.Volume = Acoustics.dbToGain(earVolumeDb)
	self.ears.HighGain = earHighDb
	if self.tinnitus then
		self.tinnitus.Volume = ring
	end
	if self.breathing then
		local exertion = if self.options.getExertion then math.clamp(self.options.getExertion(), 0, 1) else 0
		self.breathing.Volume = exertion * exertion
		self.breathing.PlaybackSpeed = 0.9 + 0.5 * exertion
	end
end

return SoundDirector
