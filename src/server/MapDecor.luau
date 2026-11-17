--!nonstrict
--[[
	MapDecor: the low-poly scenery around the motel.

	Pure decoration. Gameplay parts (desk, beds, prompts, waypoints) live
	in MapBuilder and keep their positions; nothing here sits on an NPC
	route or blocks a prompt.

	Attributes read by other scripts:
	  PowerLight = true   lamp with a Light child, switched off in an outage (server)
	  Bulb = true         neon without a light, dimmed in an outage (client Ambience)
	  Chase = n           marquee bulb index, animated by the client
	  Blink = period      slow twinkle, animated by the client
	  Flicker = base      PointLight brightness that flickers (fire)
	  Fireflies = true    ParticleEmitter enabled at night by the client

	Geometry notes (measured in Studio):
	  WedgePart       high edge at local +Z, low edge at local -Z.
	  CornerWedgePart peak at the local (+X, -Z) corner.
	  Cylinder        axis along local X.
]]

local MapDecor = {}

-- The room block, pool, dumpster yard and the garden behind the rooms are
-- authored next to the office and then moved this far north (+Z) by
-- MapBuilder.shiftRoomArea. The courtyard in between is built here.
MapDecor.ROOM_SHIFT = 18
local SHIFT = MapDecor.ROOM_SHIFT

------------------------------------------------------------------------
-- Palette
------------------------------------------------------------------------

local WOOD = Color3.fromRGB(150, 102, 64)
local WOOD_DARK = Color3.fromRGB(98, 66, 44)
local WALL = Color3.fromRGB(232, 216, 190)
local WALL_SHADE = Color3.fromRGB(206, 188, 160)
local TRIM = Color3.fromRGB(64, 132, 128) -- teal retro trim
local ACCENT = Color3.fromRGB(212, 76, 64)
local CREAM = Color3.fromRGB(250, 246, 236)
local ROOF = Color3.fromRGB(196, 74, 58)
local ROOF_LINE = Color3.fromRGB(150, 54, 44)
local ROOF_DARK = Color3.fromRGB(110, 46, 40)
local GLASS = Color3.fromRGB(150, 205, 235)
local GRASS = Color3.fromRGB(112, 156, 80)
local LAMP_WARM = Color3.fromRGB(255, 222, 150)
local ROCK = Color3.fromRGB(132, 132, 138)
local CONCRETE = Color3.fromRGB(184, 178, 168)
local METAL_DARK = Color3.fromRGB(46, 50, 58)

-- Building wall heights. Gameplay room walls in MapBuilder match ROOM_H.
local LOBBY_H = 14
local ROOM_H = 12
local SHED_H = 12

local BULB_COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 210, 80),
	Color3.fromRGB(90, 220, 140),
	Color3.fromRGB(90, 170, 255),
	Color3.fromRGB(240, 120, 230),
}

------------------------------------------------------------------------
-- Primitives
------------------------------------------------------------------------

local function new(className: string, props)
	local p = Instance.new(className)
	if p:IsA("BasePart") then
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.SmoothPlastic
	end
	for k, v in pairs(props) do
		if k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

-- Non-colliding, non-queryable detail (cheap for physics).
local DETAIL = { CanCollide = false, CanQuery = false, CanTouch = false }

local function merge(a, b)
	local out = table.clone(a)
	if b then
		for k, v in pairs(b) do
			out[k] = v
		end
	end
	return out
end

-- where: Vector3 position or CFrame.
local function block(parent, name, size, where, color, extra)
	local props = { Name = name, Size = size, Color = color, Parent = parent }
	if typeof(where) == "CFrame" then
		props.CFrame = where
	else
		props.Position = where
	end
	return new("Part", merge(props, extra))
end

local function detail(parent, name, size, where, color, extra)
	return block(parent, name, size, where, color, merge(DETAIL, extra))
end

local function ball(parent, name, d, pos, color, extra)
	return block(parent, name, Vector3.new(d, d, d), pos, color, merge({ Shape = Enum.PartType.Ball }, extra))
end

-- Vertical cylinder centred on pos.
local function cylY(parent, name, height, diameter, pos, color, extra)
	return block(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		merge({ Shape = Enum.PartType.Cylinder }, extra)
	)
end

-- Cylinder whose axis points along world Z (a disc facing ±Z).
local function cylZ(parent, name, length, diameter, pos, color, extra)
	return block(
		parent,
		name,
		Vector3.new(length, diameter, diameter),
		CFrame.new(pos) * CFrame.Angles(0, math.pi / 2, 0),
		color,
		merge({ Shape = Enum.PartType.Cylinder }, extra)
	)
end

local function neonBulb(parent, pos, color, size, attrs)
	local b = ball(parent, "Bulb", size or 0.55, pos, color, merge(DETAIL, { Material = Enum.Material.Neon }))
	b:SetAttribute("Bulb", true)
	for k, v in pairs(attrs or {}) do
		b:SetAttribute(k, v)
	end
	return b
end

local function pointLight(parent, range, brightness, color)
	parent:SetAttribute("PowerLight", true)
	return new("PointLight", { Range = range, Brightness = brightness, Color = color or LAMP_WARM, Parent = parent })
end

------------------------------------------------------------------------
-- Building helpers
------------------------------------------------------------------------

-- Doorway openings stay this tall; taller walls get a bigger lintel.
local DOOR_TOP = 9

local function segments(a, b, gaps)
	local out = {}
	local cursor = a
	for _, g in ipairs(gaps or {}) do
		table.insert(out, { cursor, g[1] })
		cursor = g[2]
	end
	table.insert(out, { cursor, b })
	return out
end

-- Wall along X (at z) or along Z (at x), with door gaps and lintels.
local function wallX(parent, name, x1, x2, z, height, gaps, color)
	for i, s in ipairs(segments(x1, x2, gaps)) do
		if s[2] - s[1] > 0.05 then
			block(
				parent,
				name .. i,
				Vector3.new(s[2] - s[1], height, 1),
				Vector3.new((s[1] + s[2]) / 2, height / 2, z),
				color or WALL
			)
		end
	end
	for i, g in ipairs(gaps or {}) do
		block(
			parent,
			name .. "Lintel" .. i,
			Vector3.new(g[2] - g[1], height - math.min(DOOR_TOP, height - 1), 1),
			Vector3.new((g[1] + g[2]) / 2, (height + math.min(DOOR_TOP, height - 1)) / 2, z),
			color or WALL
		)
	end
end

local function wallZ(parent, name, z1, z2, x, height, gaps, color)
	for i, s in ipairs(segments(z1, z2, gaps)) do
		if s[2] - s[1] > 0.05 then
			block(
				parent,
				name .. i,
				Vector3.new(1, height, s[2] - s[1]),
				Vector3.new(x, height / 2, (s[1] + s[2]) / 2),
				color or WALL
			)
		end
	end
	for i, g in ipairs(gaps or {}) do
		block(
			parent,
			name .. "Lintel" .. i,
			Vector3.new(1, height - math.min(DOOR_TOP, height - 1), g[2] - g[1]),
			Vector3.new(x, (height + math.min(DOOR_TOP, height - 1)) / 2, (g[1] + g[2]) / 2),
			color or WALL
		)
	end
end

-- Horizontal siding lines + base trim on the outside of a wall along X.
local function sidingX(parent, x1, x2, z, outward, height, gaps)
	for _, y in ipairs({ 2.5, 4.5, 6.5, 8.5, 10.5, 12.5 }) do
		if y < height - 1 then
			for _, s in ipairs(segments(x1, x2, gaps)) do
				if s[2] - s[1] > 0.5 then
					detail(
						parent,
						"Siding",
						Vector3.new(s[2] - s[1], 0.14, 0.14),
						Vector3.new((s[1] + s[2]) / 2, y, z + outward * 0.56),
						WALL_SHADE
					)
				end
			end
		end
	end
	for _, s in ipairs(segments(x1, x2, gaps)) do
		if s[2] - s[1] > 0.5 then
			detail(
				parent,
				"BaseTrim",
				Vector3.new(s[2] - s[1], 1, 0.3),
				Vector3.new((s[1] + s[2]) / 2, 0.6, z + outward * 0.62),
				TRIM
			)
		end
	end
end

--[[
	Gable roof, ridge along X, covering x1..x2 / z1..z2 with eaves at baseY.
	Adds shingle lines, a ridge cap, gable infill and eave trim.
]]
local function gableRoof(parent, name, x1, x2, z1, z2, baseY, rise)
	local length = x2 - x1
	local cx = (x1 + x2) / 2
	local zc = (z1 + z2) / 2
	local d = (z2 - z1) / 2
	local y = baseY + rise / 2
	local frontCF = CFrame.new(cx, y, zc - d / 2)
	local backCF = CFrame.new(cx, y, zc + d / 2) * CFrame.Angles(0, math.pi, 0)
	local slope = math.atan2(rise, d)
	for _, cf in ipairs({ frontCF, backCF }) do
		new(
			"WedgePart",
			{ Name = name .. "Slope", Size = Vector3.new(length, rise, d), CFrame = cf, Color = ROOF, Parent = parent }
		)
		-- Shingle lines along the slope surface (local space of the wedge).
		local lines = math.max(2, math.floor(d / 1.6))
		for k = 1, lines - 1 do
			local t = k / lines
			local onSurface = CFrame.new(0, -rise / 2 + t * rise, -d / 2 + t * d)
			local lift = CFrame.new(0, math.cos(slope) * 0.12, -math.sin(slope) * 0.12)
			detail(
				parent,
				"Shingle",
				Vector3.new(length + 0.2, 0.18, 0.5),
				cf * onSurface * lift * CFrame.Angles(-slope, 0, 0),
				ROOF_LINE
			)
		end
	end
	for _, ex in ipairs({ x1 + 0.7, x2 - 0.7 }) do
		for _, cf in ipairs({ frontCF, backCF }) do
			new("WedgePart", {
				Name = name .. "Gable",
				Size = Vector3.new(0.9, rise - 0.3, d - 0.5),
				CFrame = CFrame.new(ex, cf.Position.Y - 0.15, cf.Position.Z) * cf.Rotation,
				Color = WALL,
				Parent = parent,
			})
		end
	end
	detail(
		parent,
		name .. "Ridge",
		Vector3.new(length + 0.4, 0.6, 1.1),
		Vector3.new(cx, baseY + rise + 0.1, zc),
		ROOF_DARK
	)
	detail(parent, name .. "EaveFront", Vector3.new(length + 0.4, 0.6, 0.6), Vector3.new(cx, baseY, z1), ROOF_DARK)
	detail(parent, name .. "EaveBack", Vector3.new(length + 0.4, 0.6, 0.6), Vector3.new(cx, baseY, z2), ROOF_DARK)
end

local function chimney(parent, pos: Vector3, height: number)
	block(
		parent,
		"Chimney",
		Vector3.new(3, height, 3),
		pos + Vector3.new(0, height / 2, 0),
		Color3.fromRGB(150, 84, 66)
	)
	local cap = detail(
		parent,
		"ChimneyCap",
		Vector3.new(3.6, 0.6, 3.6),
		pos + Vector3.new(0, height + 0.3, 0),
		Color3.fromRGB(80, 70, 70)
	)
	new("Smoke", {
		Color = Color3.fromRGB(205, 205, 210),
		Opacity = 0.12,
		RiseVelocity = 4,
		Size = 2.5,
		TimeScale = 0.6,
		Parent = cap,
	})
end

-- Striped awning sticking out (toward -Z) from a wall at z.
local function awning(parent, cx, width, y, z)
	local n = math.floor(width)
	for k = 0, n - 1 do
		local color = if k % 2 == 0 then ACCENT else CREAM
		new("WedgePart", {
			Name = "Awning",
			Size = Vector3.new(1, 1.4, 2.6),
			CFrame = CFrame.new(cx - width / 2 + 0.5 + k, y, z - 1.3),
			Color = color,
			CanCollide = false,
			CanQuery = false,
			Parent = parent,
		})
		detail(
			parent,
			"Valance",
			Vector3.new(1, 0.5, 0.15),
			Vector3.new(cx - width / 2 + 0.5 + k, y - 0.95, z - 2.6),
			color
		)
	end
end

local function surfaceText(part, face, lines, opts)
	opts = opts or {}
	local gui = new("SurfaceGui", {
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = opts.ppu or 40,
		LightInfluence = opts.lightInfluence or 0,
		Brightness = opts.brightness or 1.5,
		Parent = part,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
		Parent = gui,
	})
	for i, line in ipairs(lines) do
		local t = new("TextLabel", {
			Name = line.name or ("Line" .. i),
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -16, line.scale or 0.3, 0),
			Font = Enum.Font.FredokaOne,
			TextScaled = true,
			Text = line.text,
			TextColor3 = line.color or Color3.new(1, 1, 1),
			LayoutOrder = i,
			Parent = gui,
		})
		if line.stroke ~= 0 then
			new("UIStroke", {
				Thickness = line.stroke or 3,
				Color = line.strokeColor or Color3.fromRGB(30, 20, 20),
				Parent = t,
			})
		end
	end
	return gui
end

local function lampPost(parent, pos: Vector3, heightArg: number?)
	local height: number = heightArg or 12
	cylY(parent, "LampPole", height, 0.7, pos + Vector3.new(0, height / 2, 0), METAL_DARK)
	cylY(parent, "LampBase", 1, 1.4, pos + Vector3.new(0, 0.5, 0), METAL_DARK)
	detail(parent, "LampArm", Vector3.new(0.4, 0.4, 2.6), pos + Vector3.new(0, height - 0.2, 1.1), METAL_DARK)
	detail(parent, "LampHood", Vector3.new(2, 0.5, 2), pos + Vector3.new(0, height - 0.3, 2.3), METAL_DARK)
	local head = detail(
		parent,
		"LampHead",
		Vector3.new(1.4, 0.4, 1.4),
		pos + Vector3.new(0, height - 0.7, 2.3),
		LAMP_WARM,
		{ Material = Enum.Material.Neon }
	)
	pointLight(head, 24, 0.9)
	return head
end

-- Wall-mounted lamp; facing = +1 or -1 along Z (or X when alongX).
local function wallLamp(parent, pos: Vector3, facing: number, alongX: boolean?)
	local dir = if alongX then Vector3.new(facing, 0, 0) else Vector3.new(0, 0, facing)
	detail(parent, "WallLampBack", Vector3.new(0.8, 1.2, 0.8), pos, METAL_DARK)
	local bulb = detail(
		parent,
		"WallLamp",
		Vector3.new(0.6, 0.8, 0.6),
		pos + dir * 0.6,
		LAMP_WARM,
		{ Material = Enum.Material.Neon }
	)
	pointLight(bulb, 10, 0.5)
end

-- String of coloured bulbs hanging from a wire between two points.
local function stringLights(parent, a: Vector3, b: Vector3, count: number)
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	detail(parent, "Wire", Vector3.new(0.08, 0.08, length), CFrame.lookAt(mid, b), Color3.fromRGB(30, 30, 30))
	for i = 0, count - 1 do
		local t = (i + 0.5) / count
		local sag = math.sin(t * math.pi) * 0.4
		local p = a:Lerp(b, t) - Vector3.new(0, sag + 0.3, 0)
		neonBulb(parent, p, BULB_COLORS[i % #BULB_COLORS + 1], 0.5, { Blink = 1.6 + (i % 3) * 0.35 })
	end
end

local function fenceLine(parent, a: Vector3, b: Vector3, spacing: number?)
	spacing = spacing or 6
	local delta = b - a
	local length = delta.Magnitude
	local n = math.max(1, math.floor(length / spacing))
	for i = 0, n do
		local p = a + delta * (i / n)
		block(parent, "FencePost", Vector3.new(0.8, 4, 0.8), Vector3.new(p.X, 2, p.Z), WOOD_DARK)
		detail(parent, "PostCap", Vector3.new(1, 0.3, 1), Vector3.new(p.X, 4.1, p.Z), WOOD)
	end
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(b.X, 0, b.Z))
	for _, h in ipairs({ 1.5, 3.1 }) do
		new("Part", {
			Name = "FenceRail",
			Size = Vector3.new(0.35, 0.5, length),
			CFrame = cf + Vector3.new(0, h, 0),
			Color = WOOD,
			CanQuery = false,
			Parent = parent,
		})
	end
end

------------------------------------------------------------------------
-- Nature
------------------------------------------------------------------------

-- Square pyramid from four corner wedges, base centred at (x, y, z).
local QUADRANTS = {
	{ -1, 1, 0 },
	{ 1, 1, math.pi / 2 },
	{ 1, -1, math.pi },
	{ -1, -1, 3 * math.pi / 2 },
}
local function pyramid(parent, x, y, z, width, height, color, spin, colors)
	local r = width / 2
	local base = CFrame.new(x, y, z) * CFrame.Angles(0, spin or 0, 0)
	for i, q in ipairs(QUADRANTS) do
		new("CornerWedgePart", {
			Name = "Facet",
			Size = Vector3.new(r, height, r),
			CFrame = base * CFrame.new(q[1] * r / 2, height / 2, q[2] * r / 2) * CFrame.Angles(0, q[3], 0),
			Color = if colors then colors[(i - 1) % #colors + 1] else color,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = parent,
		})
	end
end

local PINE_GREENS = {
	Color3.fromRGB(52, 108, 64),
	Color3.fromRGB(66, 124, 68),
	Color3.fromRGB(44, 94, 62),
	Color3.fromRGB(80, 136, 72),
	Color3.fromRGB(58, 116, 84),
}

local function pine(parent, x: number, z: number, height: number, rng: Random, tiers: number)
	local model = Instance.new("Model")
	model.Name = "Pine"
	local trunkH = height * 0.24
	cylY(model, "Trunk", trunkH, height * 0.07, Vector3.new(x, trunkH / 2, z), Color3.fromRGB(104, 72, 50))
	local color = PINE_GREENS[rng:NextInteger(1, #PINE_GREENS)]
	local spin = rng:NextNumber(0, math.pi / 2)
	local width = height * rng:NextNumber(0.5, 0.62)
	local y = trunkH * 0.6
	local tierH = height * (if tiers == 1 then 0.82 else 0.5)
	for t = 1, tiers do
		local shade = color:Lerp(Color3.fromRGB(150, 200, 120), (t - 1) * 0.07)
		pyramid(model, x, y, z, width, tierH, shade, spin + t * 0.35)
		y += tierH * 0.48
		width *= 0.72
		tierH *= 0.82
	end
	model.Parent = parent
end

local AUTUMN = {
	Color3.fromRGB(236, 150, 50),
	Color3.fromRGB(244, 198, 72),
	Color3.fromRGB(214, 92, 50),
	Color3.fromRGB(190, 70, 60),
}
local function roundTree(parent, x: number, z: number, rng: Random, scale: number?)
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "RoundTree"
	local h = rng:NextNumber(9, 13) * s
	cylY(model, "Trunk", h, 1.4 * s, Vector3.new(x, h / 2, z), Color3.fromRGB(104, 72, 50))
	local color = AUTUMN[rng:NextInteger(1, #AUTUMN)]
	for _ = 1, 4 do
		local d = rng:NextNumber(5.5, 8.5) * s
		local p = Vector3.new(
			x + rng:NextNumber(-2.4, 2.4) * s,
			h + rng:NextNumber(-1, 2.5) * s,
			z + rng:NextNumber(-2.4, 2.4) * s
		)
		ball(model, "Leaves", d, p, color:Lerp(Color3.fromRGB(255, 232, 130), rng:NextNumber(0, 0.25)), DETAIL)
	end
	model.Parent = parent
end

local function birch(parent, x: number, z: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Birch"
	local h = rng:NextNumber(14, 20)
	cylY(model, "Trunk", h, 1.1, Vector3.new(x, h / 2, z), Color3.fromRGB(236, 232, 222))
	for k = 1, 4 do
		detail(model, "Mark", Vector3.new(1.15, 0.25, 0.5), Vector3.new(x, h * k / 5, z), Color3.fromRGB(50, 46, 44))
	end
	for _ = 1, 3 do
		local p = Vector3.new(x + rng:NextNumber(-1.8, 1.8), h + rng:NextNumber(-2, 1.5), z + rng:NextNumber(-1.8, 1.8))
		local c = Color3.fromRGB(250, 214, 90):Lerp(Color3.fromRGB(150, 196, 80), rng:NextNumber(0, 0.5))
		ball(model, "Leaves", rng:NextNumber(5, 7), p, c, DETAIL)
	end
	model.Parent = parent
end

local function bush(parent, pos: Vector3, rng: Random, flowers: boolean?)
	local base = Color3.fromRGB(62, 122, 58)
	for i = 1, 3 do
		local s = rng:NextNumber(2.2, 3.6)
		local p = pos + Vector3.new(rng:NextNumber(-1.4, 1.4), s * 0.35, rng:NextNumber(-1.4, 1.4))
		ball(
			parent,
			"Bush",
			s,
			p,
			base:Lerp(Color3.fromRGB(96, 156, 72), rng:NextNumber()),
			{ CanCollide = i == 1, CanQuery = false }
		)
	end
	if flowers then
		for _ = 1, 4 do
			local p = pos + Vector3.new(rng:NextNumber(-1.6, 1.6), rng:NextNumber(1.6, 2.6), rng:NextNumber(-1.6, 1.6))
			ball(parent, "Blossom", 0.6, p, BULB_COLORS[rng:NextInteger(1, #BULB_COLORS)], DETAIL)
		end
	end
end

local function rock(parent, pos: Vector3, size: number, rng: Random)
	for i = 1, rng:NextInteger(1, 3) do
		local s = size * rng:NextNumber(0.6, 1)
		local cf = CFrame.new(pos + Vector3.new(rng:NextNumber(-1, 1) * i, s * 0.2, rng:NextNumber(-1, 1) * i))
			* CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, math.pi), rng:NextNumber(-0.5, 0.5))
		detail(
			parent,
			"Rock",
			Vector3.new(s, s * 0.7, s * 0.9),
			cf,
			ROCK:Lerp(Color3.fromRGB(170, 166, 158), rng:NextNumber())
		)
	end
end

local function flowerPatch(parent, pos: Vector3, rng: Random)
	local color = BULB_COLORS[rng:NextInteger(1, #BULB_COLORS)]
	for _ = 1, 6 do
		local p = pos + Vector3.new(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5))
		detail(parent, "Stem", Vector3.new(0.15, 0.9, 0.15), p + Vector3.new(0, 0.55, 0), Color3.fromRGB(70, 130, 60))
		ball(parent, "Petal", 0.55, p + Vector3.new(0, 1.1, 0), color, DETAIL)
	end
end

local function mountain(parent, x, z, width, height, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Mountain"
	local spin = rng:NextNumber(0, math.pi / 2)
	local base = Color3.fromRGB(104, 124, 146):Lerp(Color3.fromRGB(130, 140, 160), rng:NextNumber())
	pyramid(model, x, -2, z, width, height, base, spin, { base, base:Lerp(Color3.new(0, 0, 0), 0.12) })
	-- Snow cap: a smaller pyramid sharing the same apex.
	local capH = height * 0.3
	local capW = width * capH / height
	pyramid(model, x, -2 + height - capH, z, capW + 1, capH + 0.4, Color3.fromRGB(246, 248, 252), spin)
	model.Parent = parent
end

------------------------------------------------------------------------
-- Furniture
------------------------------------------------------------------------

local function bench(parent, pos: Vector3, yaw: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	block(parent, "BenchSeat", Vector3.new(5, 0.4, 1.6), cf * CFrame.new(0, 1.6, 0), WOOD)
	detail(parent, "BenchBack", Vector3.new(5, 1.4, 0.3), cf * CFrame.new(0, 2.6, 0.75), WOOD)
	for _, x in ipairs({ -2.1, 2.1 }) do
		detail(parent, "BenchLeg", Vector3.new(0.3, 1.5, 1.4), cf * CFrame.new(x, 0.75, 0), METAL_DARK)
	end
end

local function pottedPlant(parent, pos: Vector3, rng: Random)
	cylY(parent, "Pot", 1.6, 1.8, pos + Vector3.new(0, 0.8, 0), Color3.fromRGB(196, 110, 70))
	for _ = 1, 3 do
		local p = pos + Vector3.new(rng:NextNumber(-0.5, 0.5), rng:NextNumber(2, 3), rng:NextNumber(-0.5, 0.5))
		ball(
			parent,
			"Leaf",
			rng:NextNumber(1.4, 2),
			p,
			Color3.fromRGB(70, 140, 70):Lerp(Color3.fromRGB(110, 170, 80), rng:NextNumber()),
			DETAIL
		)
	end
end

local function umbrella(parent, pos: Vector3)
	cylY(parent, "UmbrellaPole", 6, 0.3, pos + Vector3.new(0, 3, 0), Color3.fromRGB(230, 230, 230), DETAIL)
	pyramid(parent, pos.X, pos.Y + 5.2, pos.Z, 7, 1.8, nil, math.pi / 4, { ACCENT, CREAM })
end

------------------------------------------------------------------------
-- Build sections
------------------------------------------------------------------------

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function buildGroundAndRoad(decor)
	local ground = folder(decor, "Ground")
	-- Top at y = 0.12 so a default Baseplate texture (top at 0) cannot show through.
	block(ground, "Grass", Vector3.new(1200, 1, 1200), Vector3.new(10, -0.38, -10), GRASS)
	block(
		ground,
		"MotelLot",
		Vector3.new(120, 0.18, 70 + SHIFT),
		Vector3.new(20, 0.09, -6 + SHIFT / 2),
		Color3.fromRGB(176, 164, 140),
		{
			Material = Enum.Material.Concrete,
		}
	)
	detail(ground, "LotKerbW", Vector3.new(0.6, 0.35, 70 + SHIFT), Vector3.new(-40, 0.2, -6 + SHIFT / 2), CONCRETE)
	detail(ground, "LotKerbE", Vector3.new(0.6, 0.35, 70 + SHIFT), Vector3.new(80, 0.2, -6 + SHIFT / 2), CONCRETE)
	detail(ground, "LotKerbN", Vector3.new(120, 0.35, 0.6), Vector3.new(20, 0.2, 29 + SHIFT), CONCRETE)

	local road = folder(decor, "Road")
	block(road, "Asphalt", Vector3.new(1200, 0.2, 18), Vector3.new(10, 0.1, -64), Color3.fromRGB(70, 68, 76))
	for _, z in ipairs({ -63.7, -64.3 }) do
		detail(road, "CenterLine", Vector3.new(1200, 0.04, 0.3), Vector3.new(10, 0.22, z), Color3.fromRGB(244, 198, 60))
	end
	for _, z in ipairs({ -72.4, -55.6 }) do
		detail(road, "EdgeLine", Vector3.new(1200, 0.04, 0.35), Vector3.new(10, 0.22, z), Color3.fromRGB(240, 240, 240))
	end
	for k = 0, 5 do
		detail(
			road,
			"Crosswalk",
			Vector3.new(1.4, 0.04, 15),
			Vector3.new(21 + k * 2.2, 0.23, -64),
			Color3.fromRGB(245, 245, 245)
		)
	end
	for x = -300, 320, 16 do
		detail(
			road,
			"Reflector",
			Vector3.new(0.5, 0.12, 0.5),
			Vector3.new(x, 0.26, -64),
			Color3.fromRGB(255, 220, 90),
			{
				Material = Enum.Material.Neon,
			}
		)
	end
	block(road, "SidewalkSouth", Vector3.new(1200, 0.5, 5), Vector3.new(10, 0.25, -75.5), CONCRETE)
	block(road, "SidewalkNorthW", Vector3.new(560, 0.5, 4), Vector3.new(-312, 0.25, -53), CONCRETE)
	block(road, "SidewalkNorthE", Vector3.new(560, 0.5, 4), Vector3.new(312, 0.25, -53), CONCRETE)
	for x = -300, 320, 8 do
		detail(road, "RailPost", Vector3.new(0.4, 2, 0.4), Vector3.new(x, 1.5, -78.2), Color3.fromRGB(150, 150, 156))
	end
	detail(road, "GuardRail", Vector3.new(620, 0.8, 0.3), Vector3.new(10, 2.2, -78.4), Color3.fromRGB(196, 196, 204), {
		Material = Enum.Material.Metal,
	})

	-- Parking extras: wheel stops, lamps, mailbox.
	for _, x in ipairs({ -26, -18, -10, -2, 6, 14 }) do
		detail(
			road,
			"WheelStop",
			Vector3.new(3.6, 0.35, 0.7),
			Vector3.new(x, 0.42, -42.8),
			Color3.fromRGB(240, 200, 70)
		)
	end
	for _, x in ipairs({ -30, -14, 2, 18 }) do
		lampPost(decor, Vector3.new(x, 0, -57.5), 12)
	end
	block(road, "MailboxPost", Vector3.new(0.4, 3.5, 0.4), Vector3.new(31, 1.75, -54), WOOD_DARK)
	block(road, "Mailbox", Vector3.new(1.2, 1.2, 2), Vector3.new(31, 3.9, -54), Color3.fromRGB(60, 90, 160))
	detail(road, "MailFlag", Vector3.new(0.1, 0.9, 0.3), Vector3.new(31.7, 4.4, -53.6), ACCENT)
end

local function buildMotelSign(decor)
	local sign = folder(decor, "MotelSign")
	local sx, sz = -46, -50
	cylY(sign, "Pole", 30, 1.6, Vector3.new(sx, 15, sz), Color3.fromRGB(70, 74, 84))
	block(sign, "Footing", Vector3.new(4, 1, 4), Vector3.new(sx, 0.5, sz), CONCRETE)
	local board = block(sign, "Board", Vector3.new(16, 7, 1), Vector3.new(sx, 25, sz - 1), Color3.fromRGB(34, 60, 74))
	surfaceText(board, Enum.NormalId.Front, {
		{ text = "RUN A", color = Color3.fromRGB(255, 236, 150), scale = 0.28 },
		{
			text = "MOTEL",
			color = Color3.fromRGB(255, 110, 190),
			scale = 0.6,
			strokeColor = Color3.fromRGB(120, 0, 70),
		},
	})
	-- Marquee bulbs running around the board.
	local idx = 0
	local function chaseBulb(p)
		idx += 1
		neonBulb(sign, p, Color3.fromRGB(255, 236, 150), 0.6, { Chase = idx })
	end
	for k = 0, 15 do
		chaseBulb(Vector3.new(sx - 7.5 + k, 28.6, sz - 1.6))
	end
	for k = 0, 6 do
		chaseBulb(Vector3.new(sx + 8.1, 28.2 - k, sz - 1.6))
	end
	for k = 15, 0, -1 do
		chaseBulb(Vector3.new(sx - 7.5 + k, 21.4, sz - 1.6))
	end
	for k = 6, 0, -1 do
		chaseBulb(Vector3.new(sx - 8.1, 28.2 - k, sz - 1.6))
	end
	-- Arrow pointing at the lot.
	local arrowColor = Color3.fromRGB(255, 196, 60)
	block(sign, "ArrowShaft", Vector3.new(12, 1.6, 0.8), Vector3.new(sx + 4, 18.5, sz - 1), Color3.fromRGB(34, 60, 74))
	for k = 0, 9 do
		neonBulb(sign, Vector3.new(sx - 1 + k * 1.1, 18.5, sz - 1.5), arrowColor, 0.55, { Chase = 100 + k })
	end
	for _, dir in ipairs({ 1, -1 }) do
		local head = detail(
			sign,
			"ArrowHead",
			Vector3.new(3.6, 1, 0.8),
			CFrame.new(sx + 10.4, 18.5 + dir * 1, sz - 1) * CFrame.Angles(0, 0, -dir * math.rad(40)),
			arrowColor,
			{ Material = Enum.Material.Neon }
		)
		head:SetAttribute("Bulb", true)
	end
	local vacancy = block(
		sign,
		"VacancyBoard",
		Vector3.new(11, 2.6, 0.8),
		Vector3.new(sx, 15.2, sz - 1),
		Color3.fromRGB(24, 24, 30)
	)
	surfaceText(vacancy, Enum.NormalId.Front, {
		{
			name = "VacancyText",
			text = "VACANCY",
			color = Color3.fromRGB(110, 255, 150),
			scale = 0.9,
			strokeColor = Color3.fromRGB(0, 70, 30),
		},
	})
end

local function buildLobby(decor, rng)
	local lobby = folder(decor, "LobbyShell")
	wallZ(lobby, "WestWall", -32, -6, 4, LOBBY_H, nil)
	wallX(lobby, "NorthWall", 4, 40, -6, LOBBY_H, { { 10, 22 } })
	wallX(lobby, "SouthWall", 4, 40, -32, LOBBY_H, { { 19, 33 } })
	wallZ(lobby, "EastWall", -32, -6, 40, LOBBY_H, { { -24, -14 } })
	sidingX(lobby, 4, 40, -32, -1, LOBBY_H, { { 19, 33 } })
	for _, x in ipairs({ 10, 37 }) do
		block(lobby, "Window", Vector3.new(6, 4, 0.3), Vector3.new(x, 4.8, -32.6), GLASS, {
			Material = Enum.Material.Glass,
			Transparency = 0.3,
			CanCollide = false,
		})
		detail(lobby, "Sill", Vector3.new(6.8, 0.4, 0.8), Vector3.new(x, 2.6, -32.8), TRIM)
		for _, dx in ipairs({ -3.7, 3.7 }) do
			detail(lobby, "Shutter", Vector3.new(1, 4.4, 0.2), Vector3.new(x + dx, 4.8, -32.8), TRIM)
		end
		awning(lobby, x, 7, 7.9, -32.5)
	end
	for _, x in ipairs({ 18.6, 33.4 }) do
		detail(lobby, "DoorFrame", Vector3.new(0.8, DOOR_TOP, 0.8), Vector3.new(x, DOOR_TOP / 2, -32.6), TRIM)
	end
	gableRoof(lobby, "Roof", 2.5, 41.5, -33.5, -4.5, LOBBY_H, 7)
	block(
		lobby,
		"Ceiling",
		Vector3.new(36, 0.3, 26),
		Vector3.new(22, LOBBY_H + 0.05, -19),
		Color3.fromRGB(246, 240, 226)
	)
	chimney(lobby, Vector3.new(34, LOBBY_H + 1, -12), 7)

	-- OFFICE sign with marquee bulbs.
	local office = block(
		lobby,
		"OfficeSign",
		Vector3.new(14, 3.4, 0.6),
		Vector3.new(26, LOBBY_H + 2.4, -34.2),
		Color3.fromRGB(120, 40, 40)
	)
	surfaceText(
		office,
		Enum.NormalId.Front,
		{ { text = "OFFICE", color = Color3.fromRGB(255, 232, 140), scale = 0.85 } }
	)
	for k = 0, 12 do
		neonBulb(
			lobby,
			Vector3.new(19.5 + k, LOBBY_H + 4.4, -34.6),
			Color3.fromRGB(255, 236, 150),
			0.45,
			{ Chase = 200 + k }
		)
	end

	-- Entrance canopy with string lights, planters and a bench.
	block(lobby, "Canopy", Vector3.new(16, 0.6, 6), Vector3.new(26, 10, -35), ACCENT)
	detail(lobby, "CanopyTrim", Vector3.new(16.4, 0.4, 0.4), Vector3.new(26, 9.6, -38), CREAM)
	for _, x in ipairs({ 18.8, 33.2 }) do
		cylY(lobby, "CanopyPost", 9.8, 0.7, Vector3.new(x, 4.9, -37.5), WALL)
	end
	stringLights(lobby, Vector3.new(18.8, 9.4, -38), Vector3.new(33.2, 9.4, -38), 10)
	pottedPlant(lobby, Vector3.new(17, 0.2, -34.5), rng)
	pottedPlant(lobby, Vector3.new(35, 0.2, -34.5), rng)
	bench(lobby, Vector3.new(10, 0.2, -35.5), 0)

	-- Interior.
	detail(lobby, "RugBorder", Vector3.new(6.6, 0.04, 12.6), Vector3.new(26, 0.42, -24), Color3.fromRGB(230, 190, 90))
	detail(lobby, "Rug", Vector3.new(6, 0.05, 12), Vector3.new(26, 0.43, -24), Color3.fromRGB(160, 50, 56))
	block(lobby, "CouchSeat", Vector3.new(2.6, 1.4, 7), Vector3.new(6.4, 1.1, -24), Color3.fromRGB(70, 120, 150))
	block(lobby, "CouchBack", Vector3.new(0.8, 2.6, 7), Vector3.new(5.2, 1.7, -24), Color3.fromRGB(60, 104, 132))
	detail(lobby, "CoffeeTable", Vector3.new(2.4, 1, 3.6), Vector3.new(10, 0.9, -24), WOOD)
	detail(lobby, "Magazine", Vector3.new(1, 0.1, 1.4), Vector3.new(10, 1.45, -24.5), Color3.fromRGB(240, 90, 90))
	pottedPlant(lobby, Vector3.new(6.5, 0.4, -30), rng)
	pottedPlant(lobby, Vector3.new(38, 0.4, -8.5), rng)
	ball(
		lobby,
		"DeskBell",
		0.6,
		Vector3.new(23.5, 3.6, -14.2),
		Color3.fromRGB(240, 200, 80),
		merge(DETAIL, { Material = Enum.Material.Metal })
	)
	local rack = detail(lobby, "KeyRack", Vector3.new(6, 3, 0.3), Vector3.new(28, 7, -6.7), WOOD_DARK)
	for k = 0, 5 do
		detail(
			lobby,
			"Key",
			Vector3.new(0.3, 0.8, 0.1),
			rack.Position + Vector3.new(-2.5 + k, -0.2, -0.25),
			Color3.fromRGB(240, 200, 80)
		)
	end
	cylZ(lobby, "Clock", 0.2, 2, Vector3.new(19, 9, -6.6), Color3.fromRGB(250, 250, 245), DETAIL)
	detail(lobby, "ClockHand", Vector3.new(0.12, 0.8, 0.05), Vector3.new(19, 9.3, -6.75), METAL_DARK)
	detail(lobby, "CoffeeCounter", Vector3.new(2, 3, 5), Vector3.new(38.5, 1.9, -29), WOOD)
	detail(lobby, "CoffeeMachine", Vector3.new(1.2, 1.4, 1.2), Vector3.new(38.5, 4.1, -30), Color3.fromRGB(40, 40, 44))
	wallLamp(lobby, Vector3.new(4.6, 8, -16), 1, true)
end

local function buildRoomBlock(decor)
	local shell = folder(decor, "RoomBlockShell")
	gableRoof(shell, "Roof", -7, 46, -1, 21, ROOM_H, 6)
	for _, cx in ipairs({ 2, 20, 38 }) do
		block(
			shell,
			"Ceiling",
			Vector3.new(14, 0.3, 16),
			Vector3.new(cx, ROOM_H + 0.05, 12),
			Color3.fromRGB(246, 240, 226)
		)
	end
	chimney(shell, Vector3.new(4, ROOM_H + 3, 15), 4)
	chimney(shell, Vector3.new(36, ROOM_H + 3, 15), 4)
	for _, x in ipairs({ -6, 11, 29, 45 }) do
		cylY(shell, "WalkwayPost", ROOM_H, 0.8, Vector3.new(x, ROOM_H / 2, -0.6), WALL)
	end
	detail(shell, "WalkwayBeam", Vector3.new(52, 0.6, 0.6), Vector3.new(19.5, ROOM_H - 0.3, -0.6), TRIM)
	stringLights(shell, Vector3.new(-6, ROOM_H - 0.7, -0.9), Vector3.new(11, ROOM_H - 0.7, -0.9), 12)
	stringLights(shell, Vector3.new(11, ROOM_H - 0.7, -0.9), Vector3.new(29, ROOM_H - 0.7, -0.9), 12)
	stringLights(shell, Vector3.new(29, ROOM_H - 0.7, -0.9), Vector3.new(45, ROOM_H - 0.7, -0.9), 12)

	local doorColors = { Color3.fromRGB(64, 150, 146), Color3.fromRGB(230, 120, 70), Color3.fromRGB(110, 120, 200) }
	for i, cx in ipairs({ 2, 20, 38 }) do
		-- Facade.
		block(shell, "Window", Vector3.new(3, 3, 0.2), Vector3.new(cx - 4.5, 4.8, 3.4), GLASS, {
			Material = Enum.Material.Glass,
			Transparency = 0.3,
			CanCollide = false,
		})
		detail(
			shell,
			"Curtain",
			Vector3.new(1.2, 3, 0.1),
			Vector3.new(cx - 5.4, 4.8, 3.6),
			Color3.fromRGB(240, 220, 150)
		)
		detail(shell, "Planter", Vector3.new(3.4, 0.8, 1), Vector3.new(cx - 4.5, 2.8, 3), WOOD)
		for k = -1, 1 do
			ball(
				shell,
				"Flower",
				0.8,
				Vector3.new(cx - 4.5 + k, 3.4, 3),
				BULB_COLORS[(i + k) % #BULB_COLORS + 1],
				DETAIL
			)
		end
		detail(shell, "DoorFrameL", Vector3.new(0.5, 7.4, 0.4), Vector3.new(cx - 2.2, 3.7, 3.3), TRIM)
		detail(shell, "DoorFrameR", Vector3.new(0.5, 7.4, 0.4), Vector3.new(cx + 2.2, 3.7, 3.3), TRIM)
		detail(shell, "DoorFrameTop", Vector3.new(4.9, 0.5, 0.4), Vector3.new(cx, 7.2, 3.3), TRIM)
		-- Open door swung against the inside of the front wall (doorway stays clear).
		detail(shell, "Door", Vector3.new(0.3, 6.8, 3.8), Vector3.new(cx + 2.3, 3.6, 6.1), doorColors[i])
		detail(
			shell,
			"DoorKnob",
			Vector3.new(0.3, 0.3, 0.3),
			Vector3.new(cx + 2.05, 3.4, 7.6),
			Color3.fromRGB(240, 200, 80)
		)
		local plaque = detail(
			shell,
			"Plaque",
			Vector3.new(1.4, 1.4, 0.2),
			Vector3.new(cx + 3.2, 6, 3.35),
			Color3.fromRGB(240, 200, 80),
			{
				Material = Enum.Material.Metal,
			}
		)
		surfaceText(
			plaque,
			Enum.NormalId.Front,
			{ { text = tostring(i), color = Color3.fromRGB(60, 40, 20), scale = 0.9, stroke = 0 } },
			{ lightInfluence = 1, brightness = 1 }
		)
		wallLamp(shell, Vector3.new(cx - 2.9, 6.4, 3.4), -1)

		-- Interior.
		detail(shell, "Headboard", Vector3.new(5.6, 3.4, 0.4), Vector3.new(cx + 3, 1.9, 19.1), WOOD_DARK)
		for _, dx in ipairs({ -1.2, 1.2 }) do
			detail(
				shell,
				"Pillow",
				Vector3.new(1.8, 0.6, 1.2),
				Vector3.new(cx + 3 + dx, 2.3, 17.8),
				Color3.fromRGB(250, 250, 250)
			)
		end
		detail(shell, "Blanket", Vector3.new(5.2, 0.2, 3.6), Vector3.new(cx + 3, 2.08, 13.3), doorColors[i])
		detail(shell, "Nightstand", Vector3.new(1.8, 2, 1.8), Vector3.new(cx - 0.6, 1.4, 18.4), WOOD)
		local lamp = detail(
			shell,
			"BedsideLamp",
			Vector3.new(0.9, 1, 0.9),
			Vector3.new(cx - 0.6, 3, 18.4),
			Color3.fromRGB(255, 230, 170),
			{
				Material = Enum.Material.Neon,
			}
		)
		pointLight(lamp, 10, 0.6)
		detail(shell, "Rug", Vector3.new(4, 0.05, 3), Vector3.new(cx - 2.5, 0.43, 14), Color3.fromRGB(190, 160, 110))
		detail(shell, "Dresser", Vector3.new(1.4, 2.4, 4), Vector3.new(cx - 5.7, 1.6, 13), WOOD)
		detail(shell, "TV", Vector3.new(0.4, 1.8, 2.8), Vector3.new(cx - 5.8, 3.7, 13), Color3.fromRGB(30, 30, 34))
		local screen = detail(
			shell,
			"Screen",
			Vector3.new(0.05, 1.5, 2.5),
			Vector3.new(cx - 5.58, 3.7, 13),
			Color3.fromRGB(70, 120, 170),
			{
				Material = Enum.Material.Neon,
				Transparency = 0.3,
			}
		)
		screen:SetAttribute("Bulb", true)
		detail(
			shell,
			"Frame",
			Vector3.new(0.12, 2.8, 3.8),
			Vector3.new(cx + 6.45, 6.5, 11),
			Color3.fromRGB(220, 180, 90)
		)
		detail(shell, "Painting", Vector3.new(0.15, 2.4, 3.4), Vector3.new(cx + 6.4, 6.5, 11), doorColors[(i % 3) + 1])
	end

	-- Vending + ice machines at the end of the walkway.
	block(shell, "VendingMachine", Vector3.new(3, 6, 2.4), Vector3.new(48.5, 3, 1.5), Color3.fromRGB(200, 50, 50))
	local glow = detail(
		shell,
		"VendingGlow",
		Vector3.new(2.2, 3.5, 0.2),
		Vector3.new(48.5, 3.6, 0.2),
		Color3.fromRGB(255, 240, 200),
		{
			Material = Enum.Material.Neon,
		}
	)
	glow:SetAttribute("Bulb", true)
	block(shell, "IceMachine", Vector3.new(3, 5, 2.4), Vector3.new(52, 2.5, 1.5), Color3.fromRGB(60, 120, 200))
	local ice =
		detail(shell, "IceSign", Vector3.new(2.4, 1, 0.2), Vector3.new(52, 4.3, 0.2), Color3.fromRGB(240, 250, 255))
	surfaceText(
		ice,
		Enum.NormalId.Front,
		{ { text = "ICE", color = Color3.fromRGB(60, 120, 200), scale = 0.9, stroke = 0 } }
	)
end

local function buildShedAndYard(decor)
	local shed = folder(decor, "LinenShed")
	wallX(shed, "SouthWall", 53, 67, -23.5, SHED_H, nil)
	wallX(shed, "NorthWall", 53, 67, -8.5, SHED_H, nil)
	wallZ(shed, "EastWall", -23.5, -8.5, 67, SHED_H, nil)
	wallZ(shed, "WestWall", -23.5, -8.5, 53, SHED_H, { { -20, -12 } })
	gableRoof(shed, "Roof", 52, 68, -24.5, -7.5, SHED_H, 4.5)
	block(shed, "Ceiling", Vector3.new(14, 0.3, 15), Vector3.new(60, SHED_H + 0.05, -16), Color3.fromRGB(246, 240, 226))
	local laundry = block(shed, "LaundrySign", Vector3.new(0.4, 2, 7), Vector3.new(52.3, DOOR_TOP + 1.4, -16), TRIM)
	surfaceText(laundry, Enum.NormalId.Left, { { text = "LAUNDRY", color = Color3.new(1, 1, 1), scale = 0.9 } })
	for k = 0, 1 do
		block(
			shed,
			"Washer",
			Vector3.new(3, 3.4, 3),
			Vector3.new(56 + k * 3.4, 1.9, -10.6),
			Color3.fromRGB(236, 240, 244)
		)
		cylZ(shed, "WasherDoor", 0.1, 2, Vector3.new(56 + k * 3.4, 2, -12.15), Color3.fromRGB(120, 170, 210), DETAIL)
	end
	detail(shed, "LaundryCart", Vector3.new(2.4, 2, 3.4), Vector3.new(64.5, 1.4, -12), Color3.fromRGB(110, 120, 140))
	block(shed, "Path", Vector3.new(14, 0.25, 8), Vector3.new(46.5, 0.15, -16), Color3.fromRGB(176, 166, 146))
	lampPost(shed, Vector3.new(50, 0, -26), 10)

	local yard = decor:FindFirstChild("RoomYard") or folder(decor, "RoomYard")
	block(yard, "DumpsterPad", Vector3.new(12, 0.3, 9), Vector3.new(64, 0.15, 6), Color3.fromRGB(150, 150, 150))
	fenceLine(yard, Vector3.new(58, 0, 10.5), Vector3.new(70, 0, 10.5), 4)
	fenceLine(yard, Vector3.new(70, 0, 10.5), Vector3.new(70, 0, 1.5), 4)
	for k = 0, 1 do
		cylY(yard, "RecycleBin", 2.6, 1.8, Vector3.new(60 + k * 2.2, 1.6, 9.2), Color3.fromRGB(60, 120, 200))
	end
end

local function buildPool(decor)
	local pool = folder(decor, "Pool")
	block(pool, "Deck", Vector3.new(22, 0.4, 22), Vector3.new(-20, 0.2, 10), Color3.fromRGB(232, 222, 202))
	block(pool, "Water", Vector3.new(14, 0.3, 12), Vector3.new(-20, 0.34, 10), Color3.fromRGB(70, 190, 236), {
		Material = Enum.Material.Glass,
		Transparency = 0.12,
	})
	for _, c in ipairs({
		{ Vector3.new(15.6, 0.5, 0.8), Vector3.new(-20, 0.45, 3.6) },
		{ Vector3.new(15.6, 0.5, 0.8), Vector3.new(-20, 0.45, 16.4) },
		{ Vector3.new(0.8, 0.5, 12), Vector3.new(-27.4, 0.45, 10) },
		{ Vector3.new(0.8, 0.5, 12), Vector3.new(-12.6, 0.45, 10) },
	}) do
		block(pool, "Coping", c[1], c[2], Color3.fromRGB(250, 250, 248))
	end
	for _, x in ipairs({ -24, -16 }) do
		local pl =
			detail(pool, "PoolLight", Vector3.new(1, 0.1, 1), Vector3.new(x, 0.5, 10), Color3.fromRGB(120, 220, 255), {
				Material = Enum.Material.Neon,
				Transparency = 0.4,
			})
		pointLight(pl, 14, 1.2, Color3.fromRGB(110, 210, 255))
	end
	block(pool, "DivingBoard", Vector3.new(1.6, 0.25, 5), Vector3.new(-20, 1.3, 15.5), Color3.fromRGB(240, 240, 240))
	detail(pool, "BoardStand", Vector3.new(1.2, 1, 1.2), Vector3.new(-20, 0.8, 17.6), Color3.fromRGB(150, 150, 156))
	cylY(pool, "Floatie", 0.4, 2.6, Vector3.new(-17, 0.55, 8), Color3.fromRGB(255, 120, 170), DETAIL)
	cylY(pool, "FloatieHole", 0.42, 1.2, Vector3.new(-17, 0.55, 8), Color3.fromRGB(70, 190, 236), DETAIL)
	for i, z in ipairs({ 4, 10, 16 }) do
		local color = ({ Color3.fromRGB(240, 120, 90), Color3.fromRGB(90, 170, 230), Color3.fromRGB(250, 210, 80) })[i]
		block(pool, "Lounger", Vector3.new(2.4, 0.6, 5), Vector3.new(-29.4, 0.9, z), color)
		detail(
			pool,
			"LoungerBack",
			Vector3.new(2.4, 0.4, 2),
			CFrame.new(-29.4, 1.6, z + 2.4) * CFrame.Angles(math.rad(-40), 0, 0),
			color
		)
		detail(pool, "Towel", Vector3.new(2, 0.08, 2), Vector3.new(-29.4, 1.24, z - 0.6), Color3.fromRGB(250, 250, 250))
	end
	umbrella(pool, Vector3.new(-29.4, 0.4, 7))
	umbrella(pool, Vector3.new(-29.4, 0.4, 13))
	fenceLine(pool, Vector3.new(-31, 0, -1), Vector3.new(-9, 0, -1), 4)
	fenceLine(pool, Vector3.new(-31, 0, 21), Vector3.new(-9, 0, 21), 4)
	fenceLine(pool, Vector3.new(-31, 0, -1), Vector3.new(-31, 0, 21), 4)
	lampPost(pool, Vector3.new(-10, 0, 22.5), 10)
end

local function buildCampfire(decor, rng)
	local camp = folder(decor, "Campfire")
	local fx, fz = -26, -24
	cylY(camp, "FirePit", 0.4, 5, Vector3.new(fx, 0.3, fz), Color3.fromRGB(70, 60, 56))
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		rock(camp, Vector3.new(fx + math.cos(a) * 2.8, 0.1, fz + math.sin(a) * 2.8), 1.1, rng)
	end
	for k = 0, 2 do
		detail(
			camp,
			"Log",
			Vector3.new(3.4, 0.6, 0.6),
			CFrame.new(fx, 0.8, fz) * CFrame.Angles(0, k / 3 * math.pi, 0.25),
			WOOD_DARK
		)
	end
	local embers =
		detail(camp, "Embers", Vector3.new(1.6, 0.4, 1.6), Vector3.new(fx, 0.9, fz), Color3.fromRGB(255, 120, 40), {
			Material = Enum.Material.Neon,
		})
	new("Fire", {
		Heat = 6,
		Size = 4,
		Color = Color3.fromRGB(255, 140, 40),
		SecondaryColor = Color3.fromRGB(255, 60, 20),
		Parent = embers,
	})
	local fireLight = new(
		"PointLight",
		{ Range = 22, Brightness = 2, Color = Color3.fromRGB(255, 150, 70), Shadows = true, Parent = embers }
	)
	fireLight:SetAttribute("Flicker", 2)
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2 + 0.5
		local p = Vector3.new(fx + math.cos(a) * 7, 0.8, fz + math.sin(a) * 7)
		-- Cylinder axis (local X) tangent to the circle.
		block(camp, "LogSeat", Vector3.new(5, 1.4, 1.4), CFrame.new(p) * CFrame.Angles(0, -a + math.pi / 2, 0), WOOD, {
			Shape = Enum.PartType.Cylinder,
		})
	end
	block(camp, "PicnicTop", Vector3.new(7, 0.4, 3), Vector3.new(-16, 2.6, -32), WOOD)
	for _, dz in ipairs({ -2.2, 2.2 }) do
		block(camp, "PicnicBench", Vector3.new(7, 0.3, 1), Vector3.new(-16, 1.4, -32 + dz), WOOD)
	end
	for _, dx in ipairs({ -2.6, 2.6 }) do
		detail(camp, "PicnicLeg", Vector3.new(0.4, 2.4, 4.6), Vector3.new(-16 + dx, 1.2, -32), WOOD_DARK)
	end
	for _, p in ipairs({ Vector3.new(-36, 0, -34), Vector3.new(-14, 0, -16) }) do
		cylY(camp, "LightPole", 7.2, 0.5, p + Vector3.new(0, 3.6, 0), WOOD_DARK)
	end
	stringLights(camp, Vector3.new(-36, 7, -34), Vector3.new(-14, 7, -16), 16)
end

local function buildGreenery(decor, rng)
	local fence = folder(decor, "Fence")
	fenceLine(fence, Vector3.new(-40, 0, -42), Vector3.new(-40, 0, 28 + SHIFT))
	fenceLine(fence, Vector3.new(-40, 0, 28 + SHIFT), Vector3.new(76, 0, 28 + SHIFT))
	fenceLine(fence, Vector3.new(76, 0, 28 + SHIFT), Vector3.new(76, 0, -42))

	local green = folder(decor, "Greenery")
	local yard = decor:FindFirstChild("RoomYard") or folder(decor, "RoomYard")
	for _, p in ipairs({
		Vector3.new(6, 0, -35),
		Vector3.new(38, 0, -35.5),
		Vector3.new(-6, 0, 23),
		Vector3.new(14, 0, 23),
		Vector3.new(32, 0, 23),
		Vector3.new(-37, 0, -12),
		Vector3.new(73, 0, -30),
		Vector3.new(73, 0, 20),
		Vector3.new(44, 0, -36),
		Vector3.new(-37, 0, 2),
	}) do
		-- Bushes behind the rooms belong to the room yard (moved with it).
		bush(if p.Z >= 20 then yard else green, p, rng, rng:NextNumber() > 0.4)
	end
	for _, p in ipairs({ { -34, -38 }, { 70, -37 }, { 71, 24 }, { -35, 25 }, { 50, 24 }, { 2, 25 } }) do
		roundTree(if p[2] >= 20 then yard else green, p[1], p[2], rng)
	end
end

-- Courtyard between the office (north wall z = -6) and the moved room
-- walkway (south edge z = -6 + SHIFT): a path from the office's back door,
-- lawns, flower beds, benches, lamps and a fountain.
local function buildCourtyard(decor, rng)
	local yard = folder(decor, "Courtyard")
	local z1, z2 = -6, -6 + SHIFT
	local zc = (z1 + z2) / 2
	local depth = z2 - z1
	-- Path from the office back door (x 10..22) to the walkway.
	block(yard, "Path", Vector3.new(12, 0.26, depth), Vector3.new(16, 0.14, zc), Color3.fromRGB(196, 186, 166), {
		Material = Enum.Material.Concrete,
	})
	for k = 0, math.floor(depth / 3) - 1 do
		detail(
			yard,
			"PathJoint",
			Vector3.new(12, 0.04, 0.2),
			Vector3.new(16, 0.28, z1 + 1.5 + k * 3),
			Color3.fromRGB(170, 160, 140)
		)
	end
	-- Lawns either side of the path.
	block(yard, "LawnWest", Vector3.new(19, 0.22, depth - 2), Vector3.new(0.5, 0.12, zc), Color3.fromRGB(120, 168, 86))
	block(yard, "LawnEast", Vector3.new(34, 0.22, depth - 2), Vector3.new(39, 0.12, zc), Color3.fromRGB(120, 168, 86))
	-- Flower beds along the path.
	for _, x in ipairs({ 9, 23 }) do
		block(yard, "FlowerBed", Vector3.new(2, 0.6, depth - 6), Vector3.new(x, 0.35, zc), WOOD_DARK)
		for k = 0, math.floor((depth - 7) / 1.6) do
			ball(
				yard,
				"Blossom",
				0.9,
				Vector3.new(x + rng:NextNumber(-0.4, 0.4), 1.0, z1 + 3.5 + k * 1.6),
				BULB_COLORS[rng:NextInteger(1, #BULB_COLORS)],
				DETAIL
			)
		end
	end
	-- Benches facing the path and lamps.
	bench(yard, Vector3.new(4, 0.2, zc - 3), math.pi / 2)
	bench(yard, Vector3.new(28, 0.2, zc + 3), -math.pi / 2)
	lampPost(yard, Vector3.new(7, 0, z1 + 4), 10)
	lampPost(yard, Vector3.new(25, 0, z2 - 4), 10)
	-- Fountain on the east lawn.
	local fx, fz = 42, zc
	cylY(yard, "FountainBasin", 1.2, 10, Vector3.new(fx, 0.6, fz), Color3.fromRGB(214, 206, 192))
	cylY(yard, "FountainWater", 0.25, 8.6, Vector3.new(fx, 1.15, fz), Color3.fromRGB(80, 190, 236), {
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		CanCollide = false,
	})
	cylY(yard, "FountainColumn", 3.4, 1.2, Vector3.new(fx, 2.3, fz), Color3.fromRGB(214, 206, 192))
	local top = cylY(yard, "FountainTop", 0.5, 3.2, Vector3.new(fx, 4, fz), Color3.fromRGB(214, 206, 192))
	new("ParticleEmitter", {
		Rate = 40,
		Lifetime = NumberRange.new(0.8, 1.1),
		Speed = NumberRange.new(5, 7),
		SpreadAngle = Vector2.new(18, 18),
		Acceleration = Vector3.new(0, -18, 0),
		Size = NumberSequence.new(0.35, 0.15),
		Transparency = NumberSequence.new(0.2, 1),
		Color = ColorSequence.new(Color3.fromRGB(200, 235, 255)),
		LightEmission = 0.3,
		EmissionDirection = Enum.NormalId.Right, -- cylinder axis (local X) points up
		Parent = top,
	})
	-- A couple of autumn trees and bushes on the lawns.
	roundTree(yard, -4, zc + 2, rng, 0.9)
	roundTree(yard, 52, zc - 2, rng, 0.9)
	bush(yard, Vector3.new(-6, 0, zc - 4), rng, true)
	bush(yard, Vector3.new(32, 0, zc - 5), rng, true)
end

local function inLot(x, z)
	return x > -44 and x < 82 and z > -46 and z < 31 + SHIFT
end
local function onRoad(z)
	return z > -80 and z < -50
end

local function buildWild(decor, rng)
	local wild = folder(decor, "Wild")
	for _ = 1, 70 do
		local x, z = rng:NextNumber(-140, 170), rng:NextNumber(-150, 110)
		if not inLot(x, z) and not onRoad(z) then
			local d = rng:NextNumber(8, 26)
			cylY(
				wild,
				"GrassPatch",
				0.06,
				d,
				Vector3.new(x, 0.14, z),
				GRASS:Lerp(Color3.fromRGB(150, 180, 90), rng:NextNumber(0.1, 0.5)),
				DETAIL
			)
		end
	end
	for _ = 1, 26 do
		local x, z = rng:NextNumber(-90, 120), rng:NextNumber(-110, 70)
		if not inLot(x, z) and not onRoad(z) then
			flowerPatch(wild, Vector3.new(x, 0, z), rng)
		end
	end
	for _ = 1, 30 do
		local x, z = rng:NextNumber(-150, 180), rng:NextNumber(-160, 120)
		if not inLot(x, z) and not onRoad(z) then
			rock(wild, Vector3.new(x, 0, z), rng:NextNumber(1.5, 4), rng)
		end
	end
	-- Fireflies around the lot edge (enabled at night by the client).
	for _, p in ipairs({
		Vector3.new(-30, 3, -24),
		Vector3.new(-20, 3, 10),
		Vector3.new(60, 3, 18),
		Vector3.new(-50, 3, -10),
		Vector3.new(90, 3, 0),
	}) do
		local holder = detail(wild, "Fireflies", Vector3.new(30, 4, 30), p, Color3.new(1, 1, 1), { Transparency = 1 })
		local em = new("ParticleEmitter", {
			Rate = 5,
			Lifetime = NumberRange.new(4, 7),
			Speed = NumberRange.new(0.3, 1.2),
			SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.2, 0.25),
				NumberSequenceKeypoint.new(1, 0),
			}),
			LightEmission = 1,
			Brightness = 3,
			Color = ColorSequence.new(Color3.fromRGB(220, 255, 120)),
			Acceleration = Vector3.new(0, 0.2, 0),
			Enabled = false,
			Parent = holder,
		})
		em:SetAttribute("Fireflies", true)
	end
end

local function buildForest(decor, rng)
	local forest = folder(decor, "Forest")
	local function blocked(x, z)
		if x > -62 and x < 96 and z > -50 and z < 44 + SHIFT then
			return true
		end
		return z > -86 and z < -44
	end
	local count = 0
	local spacing = 19
	for gx = -270, 300, spacing do
		for gz = -290, 210, spacing do
			local x = gx + rng:NextNumber(-7, 7)
			local z = gz + rng:NextNumber(-7, 7)
			if not blocked(x, z) and rng:NextNumber() > 0.1 then
				local dist = Vector2.new(x - 15, z + 10).Magnitude
				local roll = rng:NextNumber()
				if dist < 140 and roll < 0.08 then
					roundTree(forest, x, z, rng, 1.3)
				elseif dist < 140 and roll < 0.14 then
					birch(forest, x, z, rng)
				else
					local height = rng:NextNumber(24, 38) + math.min(dist / 12, 16)
					local tiers = if dist < 110 then 3 elseif dist < 190 then 2 else 1
					pine(forest, x, z, height, rng, tiers)
				end
				count += 1
				if count % 30 == 0 then
					task.wait()
				end
			end
		end
	end
	for _ = 1, 24 do
		local a = rng:NextNumber(0, math.pi * 2)
		local x, z = 18 + math.cos(a) * rng:NextNumber(75, 95), -6 + math.sin(a) * rng:NextNumber(52, 62)
		if not onRoad(z) then
			bush(forest, Vector3.new(x, 0, z), rng, false)
		end
	end
end

local function buildHorizon(decor, rng)
	local horizon = folder(decor, "Horizon")
	for k = 0, 13 do
		local a = k / 14 * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local r = rng:NextNumber(330, 400)
		local c = Color3.fromRGB(78, 128, 74):Lerp(Color3.fromRGB(110, 150, 90), rng:NextNumber())
		pyramid(
			horizon,
			15 + math.cos(a) * r,
			-1,
			-10 + math.sin(a) * r,
			rng:NextNumber(110, 160),
			rng:NextNumber(18, 32),
			c,
			rng:NextNumber(0, math.pi)
		)
	end
	for k = 0, 15 do
		local a = k / 16 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local r = rng:NextNumber(470, 540)
		mountain(
			horizon,
			15 + math.cos(a) * r,
			-10 + math.sin(a) * r,
			rng:NextNumber(200, 300),
			rng:NextNumber(130, 210),
			rng
		)
		if k % 4 == 0 then
			task.wait()
		end
	end
end

------------------------------------------------------------------------

function MapDecor.build(mapFolder: Instance)
	local decor = folder(mapFolder, "Decor")
	local rng = Random.new(20261117)
	buildGroundAndRoad(decor)
	buildMotelSign(decor)
	buildLobby(decor, rng)
	buildRoomBlock(decor)
	buildShedAndYard(decor)
	task.wait()
	buildPool(decor)
	buildCampfire(decor, rng)
	buildGreenery(decor, rng)
	buildCourtyard(decor, rng)
	task.wait()
	buildWild(decor, rng)
	task.wait()
	buildForest(decor, rng)
	buildHorizon(decor, rng)
	return decor
end

return MapDecor
