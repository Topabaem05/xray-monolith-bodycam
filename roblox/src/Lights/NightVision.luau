-- NightVision: a simple image-intensifier look: green monochrome, raised exposure and
-- heavy sensor noise. Guide code, written for this project.

local Lighting = game:GetService("Lighting")

local NightVision = {}
NightVision.__index = NightVision

function NightVision.defaultSettings()
	return {
		tint = Color3.fromRGB(120, 255, 140),
		saturation = -1,
		contrast = 0.25,
		brightness = 0.06,
		exposure = 2.5, -- EV added through ScreenEffects:setExposureOffset
		grainGain = 3, -- ScreenEffects:setGrainGain
	}
end

-- options:
--   screen    Presentation ScreenEffects (optional: exposure and noise)
--   settings  table shaped like defaultSettings()
function NightVision.new(options)
	options = options or {}
	local self = setmetatable({}, NightVision)
	self.options = options
	local settings = NightVision.defaultSettings()
	for key, value in options.settings or {} do
		settings[key] = value
	end
	self.settings = settings
	self.enabled = false
	self.effect = nil
	return self
end

function NightVision:setEnabled(enabled: boolean)
	if enabled == self.enabled then
		return
	end
	self.enabled = enabled
	local s = self.settings
	local screen = self.options.screen
	if enabled then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "NightVision"
		effect.TintColor = s.tint
		effect.Saturation = s.saturation
		effect.Contrast = s.contrast
		effect.Brightness = s.brightness
		effect.Parent = Lighting
		self.effect = effect
	elseif self.effect then
		self.effect:Destroy()
		self.effect = nil
	end
	if screen then
		screen:setExposureOffset(if enabled then s.exposure else 0)
		screen:setGrainGain(if enabled then s.grainGain else 1)
	end
end

function NightVision:toggle(): boolean
	self:setEnabled(not self.enabled)
	return self.enabled
end

function NightVision:isEnabled(): boolean
	return self.enabled
end

return NightVision
