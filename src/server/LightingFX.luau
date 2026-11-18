--!nonstrict
--[[
	Post-processing, sky and lighting moods. Idempotent: creates the effects
	once (by name, "Motel*"), removes the place template's duplicate Bloom /
	SunRays / Atmosphere / Sky, leaves everything else in Lighting alone.

	Every mood sets the whole look together, so phases read as different
	times of day instead of one scene made darker:
	  clock, sun brightness, ambient (indoor) / outdoor ambient, warm or cool
	  colour shift, exposure, atmosphere (haze, colour, glare), colour grade,
	  bloom (neon and bulbs glow at night), sun rays, star count.

	Moods (game):  Preparation  golden hour, warm low sun, long shadows
	               Day          clear afternoon
	               Night        moonlit blue, bulbs and neon bloom
	               Closing      deep night before dawn
	               Blackout     power cut: dark, desaturated, cold
	               Report       pink dawn
	Moods (lobby): Lobby        warm dusk
	               LobbyXmas    snowy blue hour: cool snow, warm windows,
	                            string lights glow
	Rain (game) is an overlay: thicker grey haze, dimmer and less saturated.

	LightingFX.phase(kind, { rain = bool, instant = bool }) tweens to the
	mood (4 s; the clock always runs forward, so Preparation -> Night plays
	the sunset).

	Best result with Lighting.Technology = Future (a place setting: scripts
	cannot change it).
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

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

local function c(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local MOODS = {
	Preparation = {
		clock = 17.35,
		brightness = 2.1,
		ambient = c(92, 82, 78),
		outdoor = c(132, 116, 104),
		shiftTop = c(255, 206, 160),
		exposure = -0.05,
		atmos = {
			density = 0.27,
			offset = 0.12,
			color = c(255, 214, 178),
			decay = c(150, 108, 124),
			glare = 0.4,
			haze = 1.3,
		},
		grade = { brightness = 0, contrast = 0.14, saturation = 0.24, tint = c(255, 242, 226) },
		bloom = { intensity = 0.35, size = 24, threshold = 0.95 },
		rays = { intensity = 0.09, spread = 0.75 },
		stars = 500,
	},
	Day = {
		clock = 14,
		brightness = 2.4,
		ambient = c(100, 100, 108),
		outdoor = c(128, 128, 136),
		shiftTop = c(255, 248, 236),
		exposure = -0.1,
		atmos = {
			density = 0.22,
			offset = 0.1,
			color = c(200, 226, 242),
			decay = c(120, 150, 182),
			glare = 0.1,
			haze = 0.6,
		},
		grade = { brightness = 0, contrast = 0.1, saturation = 0.18, tint = c(255, 252, 246) },
		bloom = { intensity = 0.2, size = 18, threshold = 0.98 },
		rays = { intensity = 0.05, spread = 0.6 },
		stars = 0,
	},
	Night = {
		clock = 0.4,
		brightness = 0.9,
		ambient = c(58, 62, 92),
		outdoor = c(74, 84, 124),
		shiftTop = c(150, 172, 255),
		exposure = 0.05,
		atmos = { density = 0.34, offset = 0.18, color = c(92, 112, 166), decay = c(36, 46, 92), glare = 0, haze = 1.1 },
		grade = { brightness = 0.01, contrast = 0.18, saturation = 0.12, tint = c(222, 232, 255) },
		bloom = { intensity = 0.75, size = 28, threshold = 0.84 },
		rays = { intensity = 0, spread = 0.5 },
		stars = 3000,
	},
	Closing = {
		clock = 3,
		brightness = 0.75,
		ambient = c(50, 54, 84),
		outdoor = c(64, 72, 112),
		shiftTop = c(140, 160, 255),
		exposure = 0.05,
		atmos = { density = 0.37, offset = 0.18, color = c(80, 98, 150), decay = c(30, 38, 80), glare = 0, haze = 1.3 },
		grade = { brightness = 0.01, contrast = 0.2, saturation = 0.1, tint = c(216, 226, 255) },
		bloom = { intensity = 0.8, size = 28, threshold = 0.83 },
		rays = { intensity = 0, spread = 0.5 },
		stars = 3000,
	},
	Blackout = {
		clock = 0.4,
		brightness = 0.55,
		ambient = c(30, 32, 50),
		outdoor = c(42, 48, 72),
		shiftTop = c(130, 150, 230),
		exposure = 0,
		atmos = { density = 0.4, offset = 0.2, color = c(60, 72, 110), decay = c(20, 26, 56), glare = 0, haze = 1.6 },
		grade = { brightness = -0.02, contrast = 0.26, saturation = -0.15, tint = c(200, 212, 244) },
		bloom = { intensity = 0.9, size = 30, threshold = 0.8 },
		rays = { intensity = 0, spread = 0.5 },
		stars = 3000,
	},
	Report = {
		clock = 6.35,
		brightness = 1.6,
		ambient = c(96, 84, 96),
		outdoor = c(124, 106, 120),
		shiftTop = c(255, 176, 170),
		exposure = 0,
		atmos = {
			density = 0.3,
			offset = 0.14,
			color = c(255, 196, 206),
			decay = c(122, 100, 152),
			glare = 0.35,
			haze = 1.5,
		},
		grade = { brightness = 0, contrast = 0.12, saturation = 0.22, tint = c(255, 236, 236) },
		bloom = { intensity = 0.35, size = 24, threshold = 0.94 },
		rays = { intensity = 0.1, spread = 0.8 },
		stars = 800,
	},
	Lobby = {
		clock = 18.3,
		brightness = 1.5,
		ambient = c(92, 82, 84),
		outdoor = c(120, 108, 116),
		shiftTop = c(255, 190, 150),
		exposure = 0,
		atmos = {
			density = 0.28,
			offset = 0.14,
			color = c(255, 200, 186),
			decay = c(110, 92, 140),
			glare = 0.3,
			haze = 1.4,
		},
		grade = { brightness = 0, contrast = 0.14, saturation = 0.22, tint = c(255, 240, 232) },
		bloom = { intensity = 0.45, size = 24, threshold = 0.92 },
		rays = { intensity = 0.06, spread = 0.7 },
		stars = 1500,
	},
	LobbyXmas = {
		clock = 18.9,
		brightness = 1.1,
		ambient = c(84, 76, 92),
		outdoor = c(112, 126, 166),
		shiftTop = c(176, 196, 255),
		exposure = 0,
		atmos = {
			density = 0.3,
			offset = 0.16,
			color = c(172, 198, 238),
			decay = c(66, 86, 150),
			glare = 0.15,
			haze = 1.5,
		},
		grade = { brightness = 0.01, contrast = 0.15, saturation = 0.26, tint = c(238, 244, 255) },
		bloom = { intensity = 0.7, size = 30, threshold = 0.87 },
		rays = { intensity = 0, spread = 0.5 },
		stars = 3000,
	},
}
LightingFX.MOODS = MOODS

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
	for _, ch in ipairs(Lighting:GetChildren()) do
		local ours = ch.Name:sub(1, 5) == "Motel"
		if not ours and (ch:IsA("BloomEffect") or ch:IsA("SunRaysEffect") or ch:IsA("Atmosphere") or ch:IsA("Sky")) then
			ch:Destroy()
		end
	end
end

local fx = nil -- { sky, atmos, grade, bloom, rays }
local clockValue = nil -- NumberValue driving ClockTime (forward-only tween)
local current = nil

function LightingFX.apply(initial: string?)
	removeDuplicates()
	local sky = ensure("Sky", "MotelSky", SKY)
	sky.CelestialBodiesShown = true
	sky.MoonAngularSize = 14
	sky.SunAngularSize = 16
	fx = {
		sky = sky,
		atmos = ensure("Atmosphere", "MotelAtmosphere", {}),
		grade = ensure("ColorCorrectionEffect", "MotelGrade", {}),
		bloom = ensure("BloomEffect", "MotelBloom", {}),
		rays = ensure("SunRaysEffect", "MotelSunRays", {}),
	}
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.35
	Lighting.ShadowSoftness = 0.25
	Lighting.GeographicLatitude = 35
	Lighting.GlobalShadows = true
	Lighting.ColorShift_Bottom = Color3.fromRGB(70, 76, 110)
	if not clockValue then
		clockValue = Instance.new("NumberValue")
		clockValue.Value = Lighting.ClockTime
		clockValue.Changed:Connect(function(v)
			Lighting.ClockTime = v % 24
		end)
	end
	current = nil
	LightingFX.phase(initial or "Preparation", { instant = true })
end

local function tween(obj, props, t)
	if t <= 0 then
		for k, v in pairs(props) do
			obj[k] = v
		end
		return
	end
	TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), props):Play()
end

-- kind: one of MOODS. opts.rain darkens and hazes it; opts.instant skips
-- the transition.
function LightingFX.phase(kind: string, opts)
	opts = opts or {}
	if not fx then
		LightingFX.apply(kind)
		return
	end
	local m = MOODS[kind] or MOODS.Day
	local rain = opts.rain == true
	local key = kind .. (if rain then "+rain" else "")
	if key == current and not opts.instant then
		return
	end
	current = key
	local t = if opts.instant then 0 else 4

	-- Clock: always forward (17 -> 0.5 runs through the sunset).
	local from = clockValue.Value % 24
	local to = m.clock
	if to < from then
		to += 24
	end
	if t > 0 then
		clockValue.Value = from
		tween(clockValue, { Value = to }, t)
	else
		clockValue.Value = to
	end

	local k = if rain then 0.7 else 1
	tween(Lighting, {
		Brightness = m.brightness * k,
		Ambient = m.ambient,
		OutdoorAmbient = if rain then m.outdoor:Lerp(c(96, 100, 112), 0.4) else m.outdoor,
		ColorShift_Top = if rain then m.shiftTop:Lerp(c(190, 196, 210), 0.6) else m.shiftTop,
		ExposureCompensation = m.exposure,
	}, t)
	local a = m.atmos
	tween(fx.atmos, {
		Density = a.density + (if rain then 0.12 else 0),
		Offset = a.offset,
		Color = if rain then a.color:Lerp(c(140, 150, 166), 0.6) else a.color,
		Decay = if rain then a.decay:Lerp(c(70, 76, 92), 0.6) else a.decay,
		Glare = if rain then 0 else a.glare,
		Haze = a.haze + (if rain then 1.2 else 0),
	}, t)
	local g = m.grade
	tween(fx.grade, {
		Brightness = g.brightness,
		Contrast = g.contrast,
		Saturation = g.saturation - (if rain then 0.12 else 0),
		TintColor = g.tint,
	}, t)
	tween(fx.bloom, { Intensity = m.bloom.intensity, Size = m.bloom.size, Threshold = m.bloom.threshold }, t)
	tween(fx.rays, { Intensity = if rain then 0 else m.rays.intensity, Spread = m.rays.spread }, t)
	fx.sky.StarCount = m.stars
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
