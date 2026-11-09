-- ShootableLights: lamps that go out when shot. Tag a lamp (a part or a model) with
-- "ShootableLight" in Studio; call shoot(hitInstance) for each bullet impact. Run it
-- on the server so everyone sees the dark room. Guide code, written for this project.

local CollectionService = game:GetService("CollectionService")

local ShootableLights = {}

ShootableLights.TAG = "ShootableLight"
ShootableLights.BROKEN = "Broken" -- attribute set on a shot lamp

-- The tagged lamp an instance belongs to, if any.
function ShootableLights.find(instance: Instance?): Instance?
	local current = instance
	while current do
		if CollectionService:HasTag(current, ShootableLights.TAG) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function darken(obj: Instance)
	if obj:IsA("Light") then
		obj.Enabled = false
	elseif obj:IsA("BasePart") and obj.Material == Enum.Material.Neon then
		obj.Material = Enum.Material.Glass
	end
end

-- Breaks the lamp `instance` belongs to. Returns the lamp if this shot broke it.
function ShootableLights.shoot(instance: Instance?): Instance?
	local lamp = ShootableLights.find(instance)
	if not lamp or lamp:GetAttribute(ShootableLights.BROKEN) then
		return nil
	end
	lamp:SetAttribute(ShootableLights.BROKEN, true)
	darken(lamp)
	for _, obj in lamp:GetDescendants() do
		darken(obj)
	end
	return lamp
end

-- Repairing lamps between rounds is the map's job: clear the attribute and turn the
-- lights back on.

return ShootableLights
