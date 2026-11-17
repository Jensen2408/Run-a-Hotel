--!nonstrict
-- Post-processing and atmosphere for the motel. Idempotent: creates the
-- effects once (by name) and leaves everything else in Lighting alone.
-- Time of day and ambient colours are driven per phase by Visuals.

local Lighting = game:GetService("Lighting")

local LightingFX = {}

local function ensure(className: string, name: string, props)
	local inst = Lighting:FindFirstChild(name)
	if not inst then
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = Lighting
	end
	for k, v in pairs(props) do
		inst[k] = v
	end
	return inst
end

function LightingFX.apply()
	ensure("Atmosphere", "MotelAtmosphere", {
		Density = 0.32,
		Offset = 0.15,
		Color = Color3.fromRGB(205, 215, 230),
		Decay = Color3.fromRGB(110, 120, 150),
		Glare = 0.15,
		Haze = 1.4,
	})
	ensure("ColorCorrectionEffect", "MotelGrade", {
		Brightness = -0.02,
		Contrast = 0.1,
		Saturation = 0.18,
		TintColor = Color3.fromRGB(255, 248, 238),
	})
	ensure("BloomEffect", "MotelBloom", {
		Intensity = 0.3,
		Size = 22,
		Threshold = 0.985,
	})
	ensure("SunRaysEffect", "MotelSunRays", {
		Intensity = 0.06,
		Spread = 0.7,
	})
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.ShadowSoftness = 0.25
	Lighting.GeographicLatitude = 35
	-- Start in the same golden-hour look as Preparation (Visuals takes over per phase).
	Lighting.ClockTime = 17.6
	Lighting.Brightness = 2
	Lighting.ExposureCompensation = 0
	Lighting.Ambient = Color3.fromRGB(110, 100, 90)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 130, 120)
end

return LightingFX
