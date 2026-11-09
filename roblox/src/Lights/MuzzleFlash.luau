-- MuzzleFlash: a shadow-casting light at the muzzle for each shot, so gunfire lights
-- the room, and a note to the screen's auto exposure, so the picture dips after a
-- flash in the dark as a camera's does. Guide code, written for this project.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FlashCurve = require(script.Parent.FlashCurve)

local MuzzleFlash = {}
MuzzleFlash.__index = MuzzleFlash

local nextId = 0

-- options:
--   getMuzzleCFrame  fn() -> CFrame? where the flash is (required)
--   settings         FlashCurve.defaultSettings() shape
--   color            Color3 (default a warm orange)
--   shadows          default true (costly on low-end devices)
--   screen           Presentation ScreenEffects, for notifyFlash (optional)
--   random           fn() -> [0, 1)
function MuzzleFlash.new(options)
	assert(options and options.getMuzzleCFrame, "MuzzleFlash needs getMuzzleCFrame")
	local self = setmetatable({}, MuzzleFlash)
	self.options = options
	self.settings = options.settings or FlashCurve.defaultSettings()
	self.random = options.random or math.random
	self.age = nil
	self.peak = 0
	nextId += 1
	self.bindName = "MuzzleFlash" .. nextId
	return self
end

function MuzzleFlash:start()
	if self.part then
		return
	end
	local part = Instance.new("Part")
	part.Name = "MuzzleFlash"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.05, 0.05, 0.05)
	local light = Instance.new("PointLight")
	light.Color = self.options.color or Color3.fromRGB(255, 190, 120)
	light.Range = self.settings.range
	light.Shadows = self.options.shadows ~= false
	light.Brightness = 0
	light.Enabled = false
	light.Parent = part
	part.Parent = Workspace.CurrentCamera
	self.part, self.light = part, light
	-- After the bodycam has placed the view and the viewmodel.
	RunService:BindToRenderStep(self.bindName, Enum.RenderPriority.Camera.Value + 3, function(dt)
		self:update(dt)
	end)
end

function MuzzleFlash:stop()
	if not self.part then
		return
	end
	RunService:UnbindFromRenderStep(self.bindName)
	self.part:Destroy()
	self.part, self.light = nil, nil
	self.age = nil
end

-- One shot. `scale` is the weapon's flash size (1 rifle; a suppressor about 0.1).
function MuzzleFlash:fire(scale: number?)
	local s = self.settings
	scale = scale or 1
	self.age = 0
	self.peak = s.brightness * scale * (1 + s.jitter * (self.random() * 2 - 1))
	local screen = self.options.screen
	if screen and screen.notifyFlash then
		screen:notifyFlash(s.flashLuminance * math.min(scale, 1))
	end
end

function MuzzleFlash:update(dt: number)
	if not (self.age and self.light) then
		return
	end
	local s = self.settings
	local value = FlashCurve.value(self.age, s)
	self.age += dt
	local muzzle = self.options.getMuzzleCFrame()
	if muzzle then
		self.part.CFrame = muzzle
	end
	self.light.Brightness = self.peak * value
	self.light.Enabled = true
	if self.age > FlashCurve.duration(s) then
		self.age = nil
		self.light.Enabled = false
		self.light.Brightness = 0
	end
end

return MuzzleFlash
