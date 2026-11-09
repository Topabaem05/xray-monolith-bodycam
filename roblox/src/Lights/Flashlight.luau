-- Flashlight: a weapon light. A shadow-casting SpotLight that follows the weapon with
-- a little lag, and a weak second light where the beam lands, tinted by the surface,
-- as a cheap stand-in for bounced light (Roblox has no real-time global illumination).
-- Guide code, written for this project.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Flashlight = {}
Flashlight.__index = Flashlight

local nextId = 0

function Flashlight.defaultSettings()
	return {
		brightness = 5,
		range = 90, -- studs
		angle = 50, -- degrees
		color = Color3.fromRGB(235, 240, 255),
		shadows = true,
		lag = 0.05, -- seconds the beam trails the weapon's turn
		bounce = true,
		bounceShare = 0.2, -- of the beam's brightness, right at the lamp
		bounceRange = 18,
		bounceOffset = 0.6, -- studs off the surface
	}
end

-- options:
--   getBeamCFrame  fn() -> CFrame? where the lamp is and points (required)
--   settings       table shaped like defaultSettings()
--   rayParams      RaycastParams for the beam (default: no filter)
function Flashlight.new(options)
	assert(options and options.getBeamCFrame, "Flashlight needs getBeamCFrame")
	local self = setmetatable({}, Flashlight)
	self.options = options
	local settings = Flashlight.defaultSettings()
	for key, value in options.settings or {} do
		settings[key] = value
	end
	self.settings = settings
	self.enabled = false
	self.rotation = nil
	nextId += 1
	self.bindName = "Flashlight" .. nextId
	return self
end

local function holder(name: string)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.05, 0.05, 0.05)
	return part
end

function Flashlight:start()
	if self.part then
		return
	end
	local s = self.settings
	local camera = Workspace.CurrentCamera
	self.part = holder("Flashlight")
	local beam = Instance.new("SpotLight")
	beam.Face = Enum.NormalId.Front
	beam.Brightness = s.brightness
	beam.Range = s.range
	beam.Angle = s.angle
	beam.Color = s.color
	beam.Shadows = s.shadows
	beam.Enabled = self.enabled
	beam.Parent = self.part
	self.beam = beam
	self.bouncePart = holder("FlashlightBounce")
	local bounce = Instance.new("PointLight")
	bounce.Range = s.bounceRange
	bounce.Shadows = false
	bounce.Enabled = false
	bounce.Parent = self.bouncePart
	self.bounce = bounce
	self.part.Parent = camera
	self.bouncePart.Parent = camera
	RunService:BindToRenderStep(self.bindName, Enum.RenderPriority.Camera.Value + 3, function(dt)
		self:update(dt)
	end)
end

function Flashlight:stop()
	if not self.part then
		return
	end
	RunService:UnbindFromRenderStep(self.bindName)
	self.part:Destroy()
	self.bouncePart:Destroy()
	self.part, self.beam, self.bouncePart, self.bounce = nil, nil, nil, nil
	self.rotation = nil
end

function Flashlight:setEnabled(enabled: boolean)
	self.enabled = enabled
	if self.beam then
		self.beam.Enabled = enabled
		if not enabled then
			self.bounce.Enabled = false
		end
	end
end

function Flashlight:toggle(): boolean
	self:setEnabled(not self.enabled)
	return self.enabled
end

function Flashlight:isEnabled(): boolean
	return self.enabled
end

function Flashlight:update(dt: number)
	if not (self.part and self.enabled) then
		return
	end
	local target = self.options.getBeamCFrame()
	if not target then
		return
	end
	local s = self.settings
	local rotation = target.Rotation
	if self.rotation and s.lag > 0 then
		rotation = self.rotation:Lerp(rotation, 1 - math.exp(-dt / s.lag))
	end
	self.rotation = rotation
	local cframe = CFrame.new(target.Position) * rotation
	self.part.CFrame = cframe

	if not s.bounce then
		self.bounce.Enabled = false
		return
	end
	local hit = Workspace:Raycast(cframe.Position, cframe.LookVector * s.range, self.options.rayParams)
	if not hit then
		self.bounce.Enabled = false
		return
	end
	local distance = (hit.Position - cframe.Position).Magnitude
	local falloff = math.clamp(1 - distance / s.range, 0, 1)
	self.bouncePart.CFrame = CFrame.new(hit.Position + (hit.Normal or Vector3.yAxis) * s.bounceOffset)
	self.bounce.Brightness = s.brightness * s.bounceShare * falloff
	local surface = hit.Instance and hit.Instance.Color
	if surface then
		-- The surface colours what it reflects.
		self.bounce.Color = Color3.new(s.color.R * surface.R, s.color.G * surface.G, s.color.B * surface.B)
	else
		self.bounce.Color = s.color
	end
	self.bounce.Enabled = self.bounce.Brightness > 0.01
end

return Flashlight
