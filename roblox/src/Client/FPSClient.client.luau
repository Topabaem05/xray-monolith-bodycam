-- Example client: bodycam + FPSys + FPSController on the local character.
--
-- Keys: WASD move, Left Shift sprint, C crouch, Z prone, Left Ctrl slide (while
-- sprinting), Space jump (stands up from crouch/prone), right mouse aim, left mouse
-- fire, R reload, V fire mode, T next scope (while aiming), 1/2 weapons, Q/E lean,
-- Left Alt hold breath (steadies the sway while aiming), H bodycam / helmet camera,
-- F next player to spectate (after death), L weapon light, N night vision.
-- Shots are simulated bullets (Ballistics); BallisticsServer checks them and applies damage.
-- Sounds: fill in the asset ids of Sound.director().defaultSounds() (none are included).
-- Viewmodels: put rigs in ReplicatedStorage.Viewmodels and name one in a weapon
-- config's `viewmodel`; Animation instances in the rig's "Animations" folder load by
-- name (Idle loops; Equip, Reload, Fire play on those events).
-- Replace onFire with your game's hit detection (validate hits on the server).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Bodycam = require(ReplicatedStorage:WaitForChild("Bodycam"))
local FPSys = require(ReplicatedStorage:WaitForChild("FPSys"))
local FPSController = require(ReplicatedStorage:WaitForChild("FPSController"))
local Presentation = require(ReplicatedStorage:WaitForChild("Presentation"))
local Ballistics = require(ReplicatedStorage:WaitForChild("Ballistics"))
local Lights = require(ReplicatedStorage:WaitForChild("Lights"))
local Sound = require(ReplicatedStorage:WaitForChild("Sound"))

local player = Players.LocalPlayer
player.CameraMode = Enum.CameraMode.LockFirstPerson

local movement, weapons

local controller = Bodycam.controller().new({
	walkSpeed = 16,
	sprintSpeed = 25.6,
	isSprinting = function()
		return movement:isSprinting()
	end,
	isCrouching = function()
		return movement:isCrouching()
	end,
	isLeaning = function()
		return weapons:getLean() ~= 0
	end,
})

local fpsys = FPSys.new({
	controller = controller,
	getLean = function()
		return weapons:getLean()
	end,
})

movement = FPSController.movement().new({ controller = controller })

-- Breathing, pulse, tremor, drift and inertia on the weapon; free aim; wall pull-back.
local holdingBreath = false
local presenter = Presentation.weaponPresenter().new({
	controller = controller,
	getWeightKg = function()
		return weapons:current().config.weightKg
	end,
	isHoldingBreath = function()
		return holdingBreath
	end,
})

-- Bodycam (eye) and helmet camera (head mount, wide lens, own body in view).
local viewmodel -- the current weapon's Presentation Viewmodel, if it has one
local headcam = Presentation.headcam().new({
	controller = controller,
	onModeChanged = function(mode)
		-- In the helmet camera the character's own arms hold the weapon.
		if viewmodel then
			viewmodel:Cull(mode == "Headcam")
		end
	end,
})

-- Grain, vignette, eye adaptation, colour grade and the bodycam HUD.
local screen = Presentation.screenEffects().new({
	getViewCFrame = function()
		return controller:getViewCFrame()
	end,
})

-- Gunfire through the bodycam microphone: distance layers, walls, room reverb,
-- ducking after loud shots, ringing ears, cracks from bullets passing close.
local sounds = Sound.director().new({
	onNearMiss = function(distance)
		presenter:onNearMiss(distance)
	end,
	getExertion = function()
		return presenter.director.state.exertion
	end,
})

-- Where the muzzle is: the rig's "Muzzle" attachment, or a point ahead of the weapon.
local function muzzleCFrame()
	local attachment = viewmodel and not viewmodel.Culled and viewmodel.Instance:FindFirstChild("Muzzle", true)
	if attachment and attachment:IsA("Attachment") then
		return attachment.WorldCFrame
	end
	local hud = controller:getHudCFrame()
	return hud and hud * presenter:getFireRotation() * CFrame.new(0.25, -0.2, -2.5)
end

local muzzleFlash = Lights.muzzleFlash().new({ getMuzzleCFrame = muzzleCFrame, screen = screen })
local flashlight = Lights.flashlight().new({ getBeamCFrame = muzzleCFrame })
local nightVision = Lights.nightVision().new({ screen = screen })

-- Bullets: own shots fly at once and report what they hit; other players' shots fly
-- for their sound and near misses only. The server decides the damage.
local remotes = ReplicatedStorage:WaitForChild(Ballistics.REMOTES, 10)
local fireRemote = remotes and remotes:WaitForChild("Fire", 5)
local hitRemote = remotes and remotes:WaitForChild("Hit", 5)
local shotRemote = remotes and remotes:WaitForChild("Shot", 5)
local impacts = Ballistics.impacts().new()
local shootableLights = Lights.shootableLights()
local bulletParams = RaycastParams.new()
bulletParams.FilterType = Enum.RaycastFilterType.Exclude
local nextShotId = 0
local simulator = Ballistics.simulator().new({
	getParams = function(projectile)
		local ignore = {}
		local shooter = projectile.data.shooter
		if shooter and shooter.Character then
			table.insert(ignore, shooter.Character)
		end
		if viewmodel then
			table.insert(ignore, viewmodel.Instance)
		end
		bulletParams.FilterDescendantsInstances = ignore
		return bulletParams
	end,
	onSegment = function(projectile, from, to)
		if not projectile.data.own then
			local offset = to - from
			if offset.Magnitude > 0.01 then
				sounds:bulletPassed(from, offset.Unit, offset.Magnitude, projectile:speed())
			end
		end
	end,
	onImpact = function(projectile, hit, _outcome, humanoid)
		if not humanoid then
			impacts:add(hit)
		end
		local data = projectile.data
		if data.own and not data.reported and hitRemote and (humanoid or shootableLights.find(hit.Instance)) then
			data.reported = true
			hitRemote:FireServer(data.id, hit.Instance, hit.Position)
		end
	end,
})
if shotRemote then
	shotRemote.OnClientEvent:Connect(function(shooter, origin, direction, name)
		local stats = type(name) == "string" and Ballistics.Catalog.get(name)
		if not stats or typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
			return
		end
		sounds:playGunshot(name, origin)
		simulator:fire(stats, origin, direction, { shooter = shooter })
	end)
end

local rifle = FPSController.Weapon.defaultConfig()
rifle.scopes = {
	{ name = "Red dot", zoom = 0.85, sensitivity = 0.85 },
	{ name = "4x", zoom = 0.3, sensitivity = 0.35 },
}

local pistol = FPSController.Weapon.defaultConfig()
pistol.name = "Pistol"
pistol.rpm = 450
pistol.modes = { "Semi" }
pistol.magazine = 15
pistol.reloadTime = 1.6
pistol.power = 0.6
pistol.shake = 0.6
pistol.recoil.pitch = { 0.9, 1.3 }
pistol.profile = { pos = { x = 0.02, y = -0.01, z = 0.03 }, rot = { x = 0, y = 1.5, z = 0 } }
pistol.weightKg = 1.0
rifle.viewmodel = "Rifle"
pistol.viewmodel = "Pistol"

-- One Viewmodel per rig name, made on first use.
local viewmodelFolder = ReplicatedStorage:FindFirstChild("Viewmodels")
local viewmodels = {}
local function viewmodelFor(name)
	if not (name and viewmodelFolder) then
		return nil
	end
	if viewmodels[name] == nil then
		local template = viewmodelFolder:FindFirstChild(name)
		viewmodels[name] = false
		if template and template:IsA("Model") then
			local rig = Presentation.viewmodel().new(template:Clone(), { Scale = 0.5 })
			local animations = rig.Instance:FindFirstChild("Animations")
			if animations then
				for _, animation in animations:GetChildren() do
					if animation:IsA("Animation") then
						rig:LoadAnimation(animation.Name, animation)
					end
				end
			end
			viewmodels[name] = rig
		end
	end
	return viewmodels[name] or nil
end

local function showViewmodel(config)
	local nextRig = viewmodelFor(config.viewmodel)
	if nextRig == viewmodel then
		return
	end
	if viewmodel then
		viewmodel:detach()
	end
	viewmodel = nextRig
	if viewmodel then
		viewmodel:attach(controller)
		viewmodel:Cull(headcam:getMode() == "Headcam")
		local idle = viewmodel:GetAnimation("Idle")
		if idle then
			idle.Looped = true
			idle:Play()
		end
	end
end

weapons = FPSController.weapons().new({
	controller = controller,
	fpsys = fpsys,
	movement = movement,
	presenter = presenter,
	weapons = { rifle, pistol },
	fovModifier = function(target, weapon)
		return headcam:fovFor(target, weapon.config.fov)
	end,
	onEvent = function(name, weapon)
		if name == "Unequipped" then
			-- Sent once the next weapon is current: switch rigs, then it equips.
			showViewmodel(weapon.config)
			if viewmodel then
				viewmodel:Play("Equip")
			end
		elseif name == "ReloadStarted" and viewmodel then
			viewmodel:Play("Reload")
		end
	end,
	onFire = function(fireCFrame, weapon)
		local name = weapon.config.name
		local stats = Ballistics.Catalog.get(name) or Ballistics.Catalog.get("Rifle")
		nextShotId += 1
		simulator:fire(stats, fireCFrame.Position, fireCFrame.LookVector, { own = true, shooter = player, id = nextShotId })
		if fireRemote then
			fireRemote:FireServer(nextShotId, Workspace:GetServerTimeNow(), fireCFrame.Position, fireCFrame.LookVector, name)
		end
		muzzleFlash:fire()
		sounds:playGunshot(name, fireCFrame.Position, { own = true })
		if viewmodel then
			viewmodel:Play("Fire")
		end
	end,
})

controller:start()
fpsys:start()
movement:start()
presenter:start()
weapons:start()
headcam:start()
screen:start()
sounds:start()
muzzleFlash:start()
flashlight:start()
simulator:start()
showViewmodel(weapons:current().config)

-- After death, watch the others through their helmet cameras until respawning.
local function spectateNext()
	local others = {}
	for _, other in Players:GetPlayers() do
		local humanoid = other ~= player and other.Character and other.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			table.insert(others, other)
		end
	end
	if #others == 0 then
		headcam:spectate(nil)
		return
	end
	local index = (table.find(others, headcam:getSpectating()) or 0) % #others + 1
	headcam:spectate(others[index])
end

-- Getting hurt frightens you: pulse, breathing and tremor rise (SPT-SWAY stress model).
local function watchHealth(character)
	local humanoid = character:WaitForChild("Humanoid")
	headcam:spectate(nil)
	humanoid.Died:Connect(function()
		task.wait(2)
		if humanoid.Health <= 0 then
			spectateNext()
		end
	end)
	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < last and humanoid.MaxHealth > 0 then
			presenter:onDamaged((last - health) / humanoid.MaxHealth)
		end
		last = health
	end)
end
if player.Character then
	task.spawn(watchHealth, player.Character)
end
player.CharacterAdded:Connect(watchHealth)

local leanLeft, leanRight = false, false
local function updateLean()
	weapons:setLean((if leanRight then 1 else 0) - (if leanLeft then 1 else 0))
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local key = input.KeyCode
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		weapons:pullTrigger()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		weapons:setAim(true)
	elseif key == Enum.KeyCode.LeftShift then
		movement:setSprint(true)
	elseif key == Enum.KeyCode.C then
		movement:toggleCrouch()
	elseif key == Enum.KeyCode.Z then
		movement:toggleProne()
	elseif key == Enum.KeyCode.LeftControl then
		movement:slide()
	elseif key == Enum.KeyCode.Space then
		movement:jump()
	elseif key == Enum.KeyCode.R then
		weapons:reload()
	elseif key == Enum.KeyCode.V then
		weapons:cycleFireMode()
	elseif key == Enum.KeyCode.T then
		weapons:cycleScope()
	elseif key == Enum.KeyCode.One then
		weapons:select(1)
	elseif key == Enum.KeyCode.Two then
		weapons:select(2)
	elseif key == Enum.KeyCode.Q then
		leanLeft = true
		updateLean()
	elseif key == Enum.KeyCode.E then
		leanRight = true
		updateLean()
	elseif key == Enum.KeyCode.LeftAlt then
		holdingBreath = true
	elseif key == Enum.KeyCode.H then
		headcam:toggle()
	elseif key == Enum.KeyCode.L then
		flashlight:toggle()
	elseif key == Enum.KeyCode.N then
		nightVision:toggle()
	elseif key == Enum.KeyCode.F and headcam:getSpectating() then
		spectateNext()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local key = input.KeyCode
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		weapons:releaseTrigger()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		weapons:setAim(false)
	elseif key == Enum.KeyCode.LeftShift then
		movement:setSprint(false)
	elseif key == Enum.KeyCode.Q then
		leanLeft = false
		updateLean()
	elseif key == Enum.KeyCode.E then
		leanRight = false
		updateLean()
	elseif key == Enum.KeyCode.LeftAlt then
		holdingBreath = false
	end
end)
