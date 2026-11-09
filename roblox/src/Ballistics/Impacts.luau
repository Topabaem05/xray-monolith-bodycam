-- Impacts: bullet holes on static surfaces, recycled from a fixed pool. Guide code:
-- the hole texture id is empty (a dark disc is used instead); particles and sounds per
-- material are left to the game. Written for this project.

local Workspace = game:GetService("Workspace")

local Impacts = {}
Impacts.__index = Impacts

-- options:
--   texture  decal asset id for the hole ("" for a plain dark disc)
--   size     studs across (default 0.25)
--   max      holes kept (default 64)
--   parent   default Workspace.Terrain
function Impacts.new(options)
	local self = setmetatable({}, Impacts)
	self.options = options or {}
	self.holes = {}
	self.next = 1
	return self
end

-- Marks a hit (a RaycastResult). Moving parts are skipped: the hole would hang in air.
function Impacts:add(hit)
	local instance = hit.Instance
	if not (instance and instance.Anchored) then
		return nil
	end
	local options = self.options
	local max = options.max or 64
	local hole = self.holes[self.next]
	if not hole then
		local size = options.size or 0.25
		hole = Instance.new("Part")
		hole.Name = "BulletHole"
		hole.Anchored = true
		hole.CanCollide = false
		hole.CanQuery = false
		hole.CanTouch = false
		hole.CastShadow = false
		hole.Size = Vector3.new(size, size, 0.02)
		if (options.texture or "") ~= "" then
			hole.Transparency = 1
			local decal = Instance.new("Decal")
			decal.Texture = options.texture
			decal.Face = Enum.NormalId.Front
			decal.Parent = hole
		else
			hole.Shape = Enum.PartType.Cylinder
			hole.Color = Color3.new(0.05, 0.05, 0.05)
			hole.Material = Enum.Material.SmoothPlastic
		end
		hole.Parent = options.parent or Workspace.Terrain or Workspace
		self.holes[self.next] = hole
	end
	-- Facing out of the surface, just above it.
	hole.CFrame = CFrame.lookAt(hit.Position + hit.Normal * 0.01, hit.Position + hit.Normal)
	self.next = self.next % max + 1
	return hole
end

function Impacts:clear()
	for _, hole in self.holes do
		hole:Destroy()
	end
	self.holes = {}
	self.next = 1
end

return Impacts
