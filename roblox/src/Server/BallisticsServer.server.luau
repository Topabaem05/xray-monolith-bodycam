-- Example server for Ballistics: takes the clients' shot and hit claims, checks them,
-- applies damage, breaks shot lamps and tells the other clients about each shot.
-- Guide code, written for this project. Add your game's rules where marked.
--
-- Remotes (ReplicatedStorage.BallisticsRemotes):
--   Fire  client -> server  (shotId, time, origin, direction, weaponName)
--   Hit   client -> server  (shotId, instance, position): what the client's own
--         simulated bullet hit
--   Shot  server -> other clients, unreliable  (shooter, origin, direction, weaponName):
--         for their sound, flash and near-miss simulation
--
-- The server trusts none of the numbers:
--   * fire rate, clock and muzzle position are checked (ShotValidator.checkShot)
--   * a hit must lie on the shot's line (allowing bullet drop), near where the target
--     was when the shot was fired (PositionHistory, capped rewind), and the walls on the
--     way must cost less than the weapon's penetration (Simulator.costBetween)
--   * damage comes from the server's Catalog, never from the client

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Ballistics = require(ReplicatedStorage:WaitForChild("Ballistics"))
local Lights = require(ReplicatedStorage:WaitForChild("Lights"))
local Simulator = Ballistics.simulator()
local ShootableLights = Lights.shootableLights()

local SHOT_MEMORY = 3 -- seconds a shot waits for its hit claim
local HITS_PER_SHOT = 1

local folder = Instance.new("Folder")
folder.Name = Ballistics.REMOTES
local fireRemote = Instance.new("RemoteEvent")
fireRemote.Name = "Fire"
fireRemote.Parent = folder
local hitRemote = Instance.new("RemoteEvent")
hitRemote.Name = "Hit"
hitRemote.Parent = folder
local shotRemote = Instance.new("UnreliableRemoteEvent")
shotRemote.Name = "Shot"
shotRemote.Parent = folder
folder.Parent = ReplicatedStorage

local heads = Ballistics.PositionHistory.new(1)
local roots = Ballistics.PositionHistory.new(1)
local validator = Ballistics.ShotValidator.new()
local shots = {} -- player -> { [shotId] = shot }

local function aliveCharacter(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return character, humanoid
	end
	return nil, nil
end

RunService.Heartbeat:Connect(function()
	local now = Workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		local character = aliveCharacter(player)
		local head = character and character:FindFirstChild("Head")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if head and root then
			heads:record(player, now, head.Position)
			roots:record(player, now, root.Position)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	heads:forget(player)
	roots:forget(player)
	validator:forget(player)
	shots[player] = nil
end)

-- Raycasts that see the world but no characters.
local function worldParams(): RaycastParams
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characters
	return params
end

fireRemote.OnServerEvent:Connect(function(player, shotId, time, origin, direction, weaponName)
	if
		type(shotId) ~= "number"
		or type(time) ~= "number"
		or typeof(origin) ~= "Vector3"
		or typeof(direction) ~= "Vector3"
		or type(weaponName) ~= "string"
	then
		return
	end
	local stats = Ballistics.Catalog.get(weaponName)
	if not (stats and aliveCharacter(player)) then
		return
	end
	-- Add your rules here: does the player hold this weapon, and has it ammunition?
	local now = Workspace:GetServerTimeNow()
	local serverOrigin = heads:sample(player, time)
	if not serverOrigin then
		return
	end
	local shot = { time = time, origin = origin, direction = direction, stats = stats, expires = now + SHOT_MEMORY, hits = 0 }
	if not validator:checkShot(player, shot, stats.rpm, serverOrigin, now) then
		return
	end
	local mine = shots[player]
	if not mine then
		mine = {}
		shots[player] = mine
	end
	for id, old in mine do
		if old.expires < now then
			mine[id] = nil
		end
	end
	mine[shotId] = shot
	for _, other in Players:GetPlayers() do
		if other ~= player then
			shotRemote:FireClient(other, player, origin, direction, weaponName)
		end
	end
end)

hitRemote.OnServerEvent:Connect(function(player, shotId, instance, position)
	if type(shotId) ~= "number" or typeof(instance) ~= "Instance" or typeof(position) ~= "Vector3" then
		return
	end
	local shot = shots[player] and shots[player][shotId]
	if not shot or shot.hits >= HITS_PER_SHOT or not instance:IsDescendantOf(Workspace) then
		return
	end
	local stats = shot.stats
	local distance = (position - shot.origin).Magnitude
	local drop = Ballistics.Projectile.drop(distance, stats.speed, stats.gravity)
	local humanoid = Simulator.humanoidOf(instance)
	local victim = humanoid and Players:GetPlayerFromCharacter(humanoid.Parent)
	if victim == player then
		return
	end
	-- Where the target was when the shot was fired (players only; other things are
	-- taken where they are now).
	local targetPosition = if victim then roots:sample(victim, shot.time) elseif instance:IsA("BasePart") then instance.Position else nil
	if not validator:checkHit(shot, position, targetPosition, stats.maxRange, drop) then
		return
	end
	-- The walls on the way must be within the weapon's penetration.
	local short = position - shot.direction * 0.2
	local cost = Simulator.costBetween(shot.origin, short, worldParams())
	if cost >= stats.power then
		return
	end
	shot.hits += 1
	if humanoid then
		if humanoid.Health <= 0 then
			return
		end
		-- Add your rules here: teams, friendly fire, armour.
		local speedShare = math.sqrt(1 - cost / stats.power) * math.exp(-stats.drag * distance)
		humanoid:TakeDamage(Ballistics.Catalog.damage(stats, distance, instance.Name, speedShare))
	else
		ShootableLights.shoot(instance)
	end
end)
