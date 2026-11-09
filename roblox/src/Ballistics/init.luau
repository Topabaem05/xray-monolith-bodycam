-- Ballistics: bullets with travel time, drop, drag, penetration and ricochet, and the
-- server's checks on what clients claim (guide code).
--
-- Pure (Vector3 only): Materials, Penetration, Projectile, PositionHistory,
--                      ShotValidator, Catalog
-- Roblox:              Simulator (raycasts), Impacts (bullet holes)
-- Server example:      src/Server/BallisticsServer.server.luau
-- Written for this project.

local Ballistics = {
	Materials = require(script.Materials),
	Penetration = require(script.Penetration),
	Projectile = require(script.Projectile),
	PositionHistory = require(script.PositionHistory),
	ShotValidator = require(script.ShotValidator),
	Catalog = require(script.Catalog),
	-- Remotes the server example creates under ReplicatedStorage.
	REMOTES = "BallisticsRemotes",
}

function Ballistics.simulator()
	return require(script.Simulator)
end

function Ballistics.impacts()
	return require(script.Impacts)
end

return Ballistics
