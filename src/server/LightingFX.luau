--!nonstrict
-- Post-processing, sky and per-phase lighting for the motel. Idempotent:
-- creates the effects once (by name), removes the place template's
-- duplicate Bloom / SunRays / Atmosphere / Sky (they doubled the glow and
-- haze), and leaves everything else in Lighting alone.
--
-- Look: cartoon skybox (clouds on a bright cyan sky), soft light, no
-- blown-out highlights. Visuals calls LightingFX.phase() when the game
-- phase, power or rain changes.

local Lighting = game:GetService("Lighting")

local LightingFX = {}

-- Cartoon skybox (Creator Store "Cartoon Sky", asset 9776643246).
local SKY = {
	SkyboxBk = "rbxassetid://528480826",
	SkyboxDn = "rbxassetid://528481890",
	SkyboxFt = "rbxassetid://528481964",
	SkyboxLf = "rbxassetid://528482047",
	SkyboxRt = "rbxassetid://528482365",
	SkyboxUp = "rbxassetid://528484371",
}

-- Indoor lamps (PointLights) are multiplied by this after the map is built.
LightingFX.LAMP_DIM = 0.65

-- Phase presets: clock, sun brightness, ambient (indoor) and outdoor ambient.
local PRESETS = {
	Preparation = { clock = 17.2, brightness = 1.35, ambient = { 82, 76, 72 }, outdoor = { 112, 106, 100 } },
	Day = { clock = 14, brightness = 1.45, ambient = { 88, 88, 92 }, outdoor = { 112, 112, 116 } },
	Report = { clock = 6.2, brightness = 1.1, ambient = { 78, 74, 86 }, outdoor = { 96, 92, 106 } },
	Night = { clock = 0.5, brightness = 0.55, ambient = { 56, 56, 76 }, outdoor = { 70, 70, 94 } },
	Closing = { clock = 3, brightness = 0.55, ambient = { 56, 56, 76 }, outdoor = { 70, 70, 94 } },
	Blackout = { clock = 0.5, brightness = 0.45, ambient = { 34, 34, 50 }, outdoor = { 46, 46, 64 } },
}

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

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

-- Removes template effects of the classes we manage (keeps ours, "Motel*").
local function removeDuplicates()
	for _, c in ipairs(Lighting:GetChildren()) do
		local ours = c.Name:sub(1, 5) == "Motel"
		if not ours and (c:IsA("BloomEffect") or c:IsA("SunRaysEffect") or c:IsA("Atmosphere") or c:IsA("Sky")) then
			c:Destroy()
		end
	end
end

function LightingFX.apply()
	removeDuplicates()
	local sky = ensure("Sky", "MotelSky", SKY)
	sky.CelestialBodiesShown = false
	sky.StarCount = 1500
	ensure("Atmosphere", "MotelAtmosphere", {
		Density = 0.22,
		Offset = 0.1,
		Color = Color3.fromRGB(200, 226, 240),
		Decay = Color3.fromRGB(120, 150, 180),
		Glare = 0,
		Haze = 0.4,
	})
	ensure("ColorCorrectionEffect", "MotelGrade", {
		Brightness = -0.05,
		Contrast = 0.12,
		Saturation = 0.15,
		TintColor = Color3.fromRGB(255, 250, 244),
	})
	ensure("BloomEffect", "MotelBloom", {
		Intensity = 0.18,
		Size = 18,
		Threshold = 0.99,
	})
	ensure("SunRaysEffect", "MotelSunRays", {
		Intensity = 0.03,
		Spread = 0.6,
	})
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.ShadowSoftness = 0.3
	Lighting.GeographicLatitude = 35
	Lighting.ExposureCompensation = -0.15
	LightingFX.phase("Preparation")
end

-- kind: Preparation | Day | Report | Night | Closing | Blackout
function LightingFX.phase(kind: string)
	local p = PRESETS[kind] or PRESETS.Day
	Lighting.ClockTime = p.clock
	Lighting.Brightness = p.brightness
	Lighting.Ambient = rgb(p.ambient)
	Lighting.OutdoorAmbient = rgb(p.outdoor)
end

-- Dims every PointLight / SpotLight / SurfaceLight under `root` once.
function LightingFX.dimLamps(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Light") and not d:GetAttribute("Dimmed") then
			d.Brightness *= LightingFX.LAMP_DIM
			d:SetAttribute("Dimmed", true)
			local flicker = d:GetAttribute("Flicker")
			if typeof(flicker) == "number" then
				d:SetAttribute("Flicker", flicker * LightingFX.LAMP_DIM)
			end
		end
	end
end

return LightingFX
