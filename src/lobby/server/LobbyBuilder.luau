--!nonstrict
--[[
	LobbyBuilder: the lobby hall, built from code under Workspace.Lobby.

	Authored at scale 1 (like the motel) and enlarged by Config.mapScale.

	  back wall (+Z)   four room doors 1..4 with floor pads and status signs,
	                   neon "RUN A MOTEL" sign
	  left wall (-X)   TOP NIGHTS leaderboard (server SurfaceGui)
	  right wall (+X)  profile board (filled per player on the client) and
	                   HOW TO PLAY board
	  front (-Z)       wide opening to the forest, spawn inside

	With the Blender kit (batch "lobby": LobbyHall, LobbyTitle, LobbyDoor,
	LobbyPad, LobbyBoardL/M/W + batch 4 furniture) the hall is drawn by the
	meshes: walls / floor / lintel stay as invisible colliders, the boards and
	plaques stay as SurfaceGui hosts, the neon pads stay for the room colour.
	Without the kit the old part-built hall is used.

	Server-built boards only use icon sheets 1 and 2 (the server cannot show
	the client-side emoji fallback for a sheet that is not uploaded yet).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local UiAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiAssets"))
-- Blender kit (meshes in ServerStorage.MotelKit); the game server's module.
local Kit = require(game:GetService("ServerScriptService"):WaitForChild("Server"):WaitForChild("Kit"))

local LobbyBuilder = {}

local WALL = Color3.fromRGB(236, 222, 196)
local TRIM = Color3.fromRGB(64, 132, 128)
local WOOD_DARK = Color3.fromRGB(98, 66, 44)
local OUTLINE = Color3.fromRGB(46, 32, 22)
local LAMP = Color3.fromRGB(255, 222, 150)

-- Room 1 is on the left when facing the doors (+Z).
LobbyBuilder.ROOM_X = { 24, 8, -8, -24 }
LobbyBuilder.PAD_Z = 17
LobbyBuilder.PAD_RADIUS = 4.5
LobbyBuilder.ROOM_COLORS = {
	Color3.fromRGB(110, 210, 120),
	Color3.fromRGB(110, 170, 255),
	Color3.fromRGB(190, 130, 255),
	Color3.fromRGB(255, 160, 80),
}
LobbyBuilder.ROOM_NAMES = { "SOLO", "DUO", "TRIO", "SQUAD" }

local function part(props)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "ClassName" then
			p[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function block(parent, name, size, pos, color, extra)
	local props = { Name = name, Size = size, Color = color, Parent = parent }
	if typeof(pos) == "CFrame" then
		props.CFrame = pos
	else
		props.Position = pos
	end
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	return part(props)
end

local function cylY(parent, name, height, diameter, pos, color, extra)
	return block(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		(function()
			local e = { Shape = Enum.PartType.Cylinder }
			for k, v in pairs(extra or {}) do
				e[k] = v
			end
			return e
		end)()
	)
end

local function text(parent, props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	for k, v in pairs(props) do
		if k ~= "Stroke" then
			t[k] = v
		end
	end
	if props.Stroke ~= 0 then
		local s = Instance.new("UIStroke")
		s.Thickness = props.Stroke or 3
		s.Color = OUTLINE
		s.Parent = t
	end
	t.Parent = parent
	return t
end

local function icon(parent, name, props)
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	for k, v in pairs(props) do
		img[k] = v
	end
	UiAssets.applyTo(img, name)
	img.Parent = parent
	return img
end

local function surface(part_, face, ppu)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppu or 40
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.Parent = part_
	return gui
end

local function wall(parent, name, size, pos)
	return block(parent, name, size, pos, WALL)
end

local function lamp(parent, pos, range)
	local head =
		block(parent, "Lamp", Vector3.new(3, 0.5, 3), pos, LAMP, { Material = Enum.Material.Neon, CanCollide = false })
	local l = Instance.new("PointLight")
	l.Range = range or 30
	l.Brightness = 0.5
	l.Color = LAMP
	l.Parent = head
end

------------------------------------------------------------------------

function LobbyBuilder.build(scale: number)
	local old = Workspace:FindFirstChild("Lobby")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Lobby"
	local map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = root
	local boards = Instance.new("Folder")
	boards.Name = "Boards"
	boards.Parent = root
	local pads = Instance.new("Folder")
	pads.Name = "Pads"
	pads.Parent = root

	Kit.load()
	local kit = Kit.has("LobbyHall")
	-- Kit hall: the shell parts only collide (the meshes draw the hall).
	local hidden = if kit then { Transparency = 1, CastShadow = false } else nil

	-- Ground and hall shell ---------------------------------------------------
	block(map, "Grass", Vector3.new(500, 1, 500), Vector3.new(0, -0.38, 0), Color3.fromRGB(112, 156, 80))
	local floorProps = { Material = Enum.Material.WoodPlanks }
	if kit then
		floorProps = hidden
	end
	block(map, "Floor", Vector3.new(82, 0.4, 56), Vector3.new(0, 0.2, 0), Color3.fromRGB(196, 170, 130), floorProps)
	local H = 16
	local function shell(name, size, pos)
		local w = wall(map, name, size, pos)
		if kit then
			w.Transparency = 1
			w.CastShadow = false
		end
		return w
	end
	shell("BackWall", Vector3.new(82, H, 1), Vector3.new(0, H / 2, 28))
	shell("LeftWall", Vector3.new(1, H, 56), Vector3.new(-41, H / 2, 0))
	shell("RightWall", Vector3.new(1, H, 56), Vector3.new(41, H / 2, 0))
	shell("FrontWallL", Vector3.new(24, H, 1), Vector3.new(-29, H / 2, -28))
	shell("FrontWallR", Vector3.new(24, H, 1), Vector3.new(29, H / 2, -28))
	shell("FrontLintel", Vector3.new(34, H - 10, 1), Vector3.new(0, 10 + (H - 10) / 2, -28))

	if kit then
		-- Hall, title sign, rug, ceiling lamps under the beams.
		Kit.place("LobbyHall", map, CFrame.new())
		Kit.place("LobbyTitle", map, CFrame.new())
		Kit.place("LobbyRug", map, CFrame.new(0, 0.4, -6), { scale = 1.95 })
		for _, x in ipairs({ -30, -15, 0, 15, 30 }) do
			for _, z in ipairs({ -12, 8 }) do
				Kit.place("CeilingLamp", map, CFrame.new(x, H - 0.9, z), { scale = 1.3 })
				local anchor = block(map, "LampLight", Vector3.new(0.4, 0.4, 0.4), Vector3.new(x, H - 2.2, z), LAMP, {
					Transparency = 1,
					CanCollide = false,
					CanQuery = false,
				})
				local l = Instance.new("PointLight")
				l.Range = 24
				l.Brightness = 0.6
				l.Color = LAMP
				l.Parent = anchor
			end
		end
		-- Wall sconces between the room doors.
		for _, x in ipairs({ -32, -16, 0, 16, 32 }) do
			if x ~= 0 then
				Kit.place("WallSconce", map, CFrame.new(x, 6.4, 27.5), { scale = 1.3 })
			end
		end
	else
		block(map, "Rug", Vector3.new(18, 0.05, 26), Vector3.new(0, 0.43, -6), Color3.fromRGB(170, 54, 60))
		block(map, "RugBorder", Vector3.new(19.4, 0.04, 27.4), Vector3.new(0, 0.42, -6), Color3.fromRGB(230, 190, 90))
		block(map, "Ceiling", Vector3.new(82, 0.4, 56), Vector3.new(0, H + 0.2, 0), Color3.fromRGB(246, 240, 226))
		block(map, "Roof", Vector3.new(86, 1.2, 60), Vector3.new(0, H + 1, 0), Color3.fromRGB(176, 66, 54))
		for _, x in ipairs({ -41, 41 }) do
			block(map, "BaseTrim", Vector3.new(1.2, 1, 56), Vector3.new(x, 0.9, 0), TRIM)
		end
		block(map, "BaseTrimBack", Vector3.new(82, 1, 1.2), Vector3.new(0, 0.9, 27.5), TRIM)
		for _, x in ipairs({ -30, -15, 0, 15, 30 }) do
			for _, z in ipairs({ -12, 8 }) do
				lamp(map, Vector3.new(x, H - 0.4, z), 24)
			end
		end

		-- Neon title sign on the back wall.
		local title =
			block(map, "TitleSign", Vector3.new(36, 5, 0.6), Vector3.new(0, 13, 27.3), Color3.fromRGB(46, 58, 70))
		local tg = surface(title, Enum.NormalId.Front, 30)
		text(tg, {
			Size = UDim2.fromScale(1, 1),
			Text = "RUN A MOTEL",
			TextColor3 = Color3.fromRGB(255, 120, 190),
			Stroke = 6,
		})
		for k = 0, 17 do
			local b = block(map, "Bulb", Vector3.new(0.6, 0.6, 0.6), Vector3.new(-17 + k * 2, 15.8, 26.8), LAMP, {
				Shape = Enum.PartType.Ball,
				Material = Enum.Material.Neon,
				CanCollide = false,
			})
			b:SetAttribute("Chase", k + 1)
		end
	end

	-- Room doors + pads ------------------------------------------------------------
	for i, x in ipairs(LobbyBuilder.ROOM_X) do
		local color = LobbyBuilder.ROOM_COLORS[i]
		local plaque
		if kit then
			-- Kit double door (leaves in the room colour), brass number plate
			-- on the seam between the portholes.
			local door = Kit.place("LobbyDoor", map, CFrame.new(x, 0.4, 27.5))
			if door and door.SM_Bld_LobbyDoor_Leaf then
				door.SM_Bld_LobbyDoor_Leaf.Color = color:Lerp(Color3.new(1, 1, 1), 0.15)
			end
			plaque = block(
				map,
				"Plaque" .. i,
				Vector3.new(1.7, 1.7, 0.2),
				Vector3.new(x, 6.1, 26.92),
				Color3.fromRGB(240, 200, 80),
				{ Material = Enum.Material.Metal }
			)
		else
			-- Door in the back wall.
			block(
				map,
				"Door" .. i,
				Vector3.new(7, 11, 0.4),
				Vector3.new(x, 5.9, 27.3),
				color:Lerp(Color3.new(0, 0, 0), 0.25)
			)
			for _, dx in ipairs({ -4, 4 }) do
				block(map, "DoorFrame", Vector3.new(1, 12, 0.8), Vector3.new(x + dx, 6.2, 27.2), TRIM)
			end
			block(map, "DoorTop", Vector3.new(9, 1, 0.8), Vector3.new(x, 12.4, 27.2), TRIM)
			block(
				map,
				"DoorKnob",
				Vector3.new(0.5, 0.5, 0.4),
				Vector3.new(x + 2.3, 5.6, 27),
				Color3.fromRGB(240, 200, 80)
			)
			plaque =
				block(map, "Plaque" .. i, Vector3.new(3, 3, 0.3), Vector3.new(x, 9, 27), Color3.fromRGB(240, 200, 80), {
					Material = Enum.Material.Metal,
				})
		end
		local pg = surface(plaque, Enum.NormalId.Front, 60)
		text(
			pg,
			{ Size = UDim2.fromScale(1, 1), Text = tostring(i), TextColor3 = Color3.fromRGB(70, 40, 20), Stroke = 0 }
		)

		-- Pad on the floor in front of the door (on the kit pad base: wooden
		-- disc with a brass ring and rim bulbs).
		local padY = if kit and Kit.has("LobbyPad") then 0.82 else 0.55
		local pad =
			cylY(pads, "Pad" .. i, 0.24, LobbyBuilder.PAD_RADIUS * 2, Vector3.new(x, padY, LobbyBuilder.PAD_Z), color, {
				Material = Enum.Material.Neon,
				Transparency = 0.25,
				CanCollide = false,
			})
		pad:SetAttribute("Room", i)
		if padY > 0.55 then
			Kit.place("LobbyPad", pads, CFrame.new(x, 0.4, LobbyBuilder.PAD_Z))
		else
			cylY(
				pads,
				"PadRim",
				0.25,
				LobbyBuilder.PAD_RADIUS * 2 + 1,
				Vector3.new(x, 0.5, LobbyBuilder.PAD_Z),
				Color3.fromRGB(60, 50, 44),
				{
					CanCollide = false,
				}
			)
		end
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 14
		light.Brightness = 1.4
		light.Parent = pad

		-- Status sign above the pad (server updates the text).
		local signPost = block(
			pads,
			"Sign" .. i,
			Vector3.new(0.5, 0.5, 0.5),
			Vector3.new(x, 7.5, LobbyBuilder.PAD_Z),
			Color3.new(),
			{
				Transparency = 1,
				CanCollide = false,
			}
		)
		local bb = Instance.new("BillboardGui")
		bb.Name = "Status"
		bb.Size = UDim2.fromScale(9, 3.6)
		bb.LightInfluence = 0
		bb.MaxDistance = 120
		bb.Parent = signPost
		icon(bb, "guests", { Name = "Icon", Size = UDim2.fromScale(0.3, 0.55), Position = UDim2.fromScale(0, 0) })
		text(bb, {
			Name = "Title",
			Size = UDim2.fromScale(0.7, 0.55),
			Position = UDim2.fromScale(0.3, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = ("ROOM %d"):format(i),
			TextColor3 = color,
		})
		text(bb, {
			Name = "Count",
			Size = UDim2.fromScale(1, 0.45),
			Position = UDim2.fromScale(0, 0.55),
			Text = ("%s  0/%d"):format(LobbyBuilder.ROOM_NAMES[i], i),
		})
	end

	-- Boards ---------------------------------------------------------------------------
	-- Kit frames face into the hall: front (-Z) turned to +X / -X.
	local function frame(group, partName, size, pos, facing: number)
		if kit and Kit.has(group) then
			Kit.place(
				group,
				boards,
				CFrame.new(pos.X + facing * 0.3, pos.Y, pos.Z) * CFrame.Angles(0, -facing * math.pi / 2, 0)
			)
		else
			block(boards, partName, size, Vector3.new(pos.X - facing * 0.2, pos.Y, pos.Z), WOOD_DARK)
		end
	end
	local leaderboard =
		block(boards, "Leaderboard", Vector3.new(0.6, 14, 24), Vector3.new(-40.3, 8, 0), Color3.fromRGB(46, 58, 70))
	frame("LobbyBoardL", "LeaderboardFrame", Vector3.new(0.5, 15, 25), Vector3.new(-40.3, 8, 0), 1)
	LobbyBuilder.buildLeaderboardGui(leaderboard)

	local profile =
		block(boards, "ProfileBoard", Vector3.new(0.6, 11, 15), Vector3.new(40.3, 8, 15), Color3.fromRGB(46, 70, 66))
	frame("LobbyBoardM", "ProfileFrame", Vector3.new(0.5, 12, 16), Vector3.new(40.3, 8, 15), -1)
	profile:SetAttribute("ProfileBoard", true)

	local howto =
		block(boards, "HowToPlay", Vector3.new(0.6, 13, 22), Vector3.new(40.3, 8, -10), Color3.fromRGB(70, 56, 46))
	frame("LobbyBoardW", "HowToFrame", Vector3.new(0.5, 14, 23), Vector3.new(40.3, 8, -10), -1)
	LobbyBuilder.buildHowToGui(howto)

	-- Decor: couches, plants, pillars ----------------------------------------------------
	if kit then
		-- Kit furniture (batch 4): couches facing the room doors with coffee
		-- tables, potted plants in the corners, coffee bar by the entrance,
		-- flower beds and bushes along the front.
		for _, z in ipairs({ -18, 4 }) do
			Kit.place("Couch", map, CFrame.new(-28, 0.4, z) * CFrame.Angles(0, math.pi, 0))
			Kit.place("CoffeeTable", map, CFrame.new(-28, 0.4, z + 4))
		end
		for _, p in ipairs({
			Vector3.new(-38, 0.4, -25),
			Vector3.new(38, 0.4, -25),
			Vector3.new(-38, 0.4, 25),
			Vector3.new(38, 0.4, 25),
		}) do
			Kit.place("PottedPlant", map, CFrame.new(p), { scale = 1.4 })
		end
		Kit.place("CoffeeBar", map, CFrame.new(-37.6, 0.4, -18) * CFrame.Angles(0, -math.pi / 2, 0), { scale = 1.2 })
		for _, x in ipairs({ -29, 29 }) do
			Kit.place("FlowerBed", map, CFrame.new(x, 0, -31.2))
		end
		for _, x in ipairs({ -21.5, 21.5, -38, 38 }) do
			Kit.place("FlowerBush", map, CFrame.new(x, 0, -30.5))
		end
	end
	for _, z in ipairs(if kit then {} else { -18, 4 }) do
		block(map, "CouchSeat", Vector3.new(7, 1.4, 2.8), Vector3.new(-28, 1.1, z), Color3.fromRGB(70, 120, 150))
		block(map, "CouchBack", Vector3.new(7, 2.6, 0.8), Vector3.new(-28, 1.7, z - 1.4), Color3.fromRGB(60, 104, 132))
	end
	for _, p in
		ipairs(if kit
			then {}
			else {
				Vector3.new(-38, 0, -25),
				Vector3.new(38, 0, -25),
				Vector3.new(-38, 0, 25),
				Vector3.new(38, 0, 25),
			})
	do
		cylY(map, "Pot", 2, 2.4, p + Vector3.new(0, 1.2, 0), Color3.fromRGB(196, 110, 70))
		for k = 0, 2 do
			block(
				map,
				"Leaf",
				Vector3.new(2.4, 2.4, 2.4),
				p + Vector3.new(math.sin(k * 2) * 0.6, 3 + k * 0.6, math.cos(k * 2) * 0.6),
				Color3.fromRGB(80, 150, 80),
				{
					Shape = Enum.PartType.Ball,
					CanCollide = false,
				}
			)
		end
	end
	if not kit then
		for _, x in ipairs({ -17, 17 }) do
			cylY(map, "Pillar", H, 1.6, Vector3.new(x, H / 2, -27), WALL)
		end
		block(map, "Welcome", Vector3.new(14, 2, 0.5), Vector3.new(0, 11.5, -27.4), Color3.fromRGB(120, 40, 40))
		local wg = surface(map:FindFirstChild("Welcome"), Enum.NormalId.Back, 40)
		text(wg, { Size = UDim2.fromScale(1, 1), Text = "WELCOME", TextColor3 = Color3.fromRGB(255, 232, 140) })
	end

	-- Outside: a ring of pines through the front opening (the Blender pine
	-- when the kit is available, else a trunk + wedge).
	local rng = Random.new(77)
	local kitPines = Kit.has("PineTree")
	for k = 1, 40 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(70, 130)
		local x, z = math.cos(a) * r, math.sin(a) * r
		local h = rng:NextNumber(22, 34)
		if kitPines then
			Kit.place(
				"PineTree",
				map,
				CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				{ scale = h / 23.9 }
			)
			continue
		end
		block(map, "Trunk", Vector3.new(1.6, h * 0.25, 1.6), Vector3.new(x, h * 0.125, z), Color3.fromRGB(104, 72, 50))
		block(
			map,
			"Pine",
			Vector3.new(h * 0.5, h * 0.75, h * 0.5),
			CFrame.new(x, h * 0.25 + h * 0.375, z) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
			Color3.fromRGB(58, 112, 64):Lerp(Color3.fromRGB(86, 140, 72), rng:NextNumber()),
			{
				ClassName = "WedgePart",
				CanCollide = false,
			}
		)
		if k % 10 == 0 then
			task.wait()
		end
	end

	-- Spawn.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.Position = Vector3.new(0, 0.45, -16)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = map

	root.Parent = Workspace
	LobbyBuilder.scale(root, scale)
	return root
end

-- Uniform scale about the origin (same rules as MapBuilder.scale).
function LobbyBuilder.scale(root: Instance, factor: number)
	if factor == 1 then
		return
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			d.Size *= factor
			d.CFrame = CFrame.new(cf.Position * factor) * cf.Rotation
		elseif d:IsA("Light") then
			d.Range = math.min(60, d.Range * factor)
		end
	end
end

------------------------------------------------------------------------
-- Boards
------------------------------------------------------------------------

function LobbyBuilder.buildLeaderboardGui(board: BasePart)
	local gui = surface(board, Enum.NormalId.Right, 30)
	gui.Name = "LeaderboardGui"
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.fromScale(1, 0.14)
	header.Parent = gui
	icon(header, "trophy", { Size = UDim2.fromScale(0.14, 0.9), Position = UDim2.fromScale(0.08, 0.05) })
	text(header, {
		Size = UDim2.fromScale(0.72, 0.9),
		Position = UDim2.fromScale(0.22, 0.05),
		Text = "TOP NIGHTS",
		TextColor3 = Color3.fromRGB(255, 226, 120),
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = 5,
	})
	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(0.92, 0.82)
	list.Position = UDim2.fromScale(0.04, 0.16)
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0.008, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local status = text(gui, {
		Name = "Status",
		Size = UDim2.fromScale(0.9, 0.08),
		Position = UDim2.fromScale(0.05, 0.5),
		Text = "Loading...",
		TextColor3 = Color3.fromRGB(220, 220, 230),
		Stroke = 3,
	})
	status.ZIndex = 2
end

local RANK_COLORS = {
	Color3.fromRGB(255, 214, 64),
	Color3.fromRGB(210, 220, 235),
	Color3.fromRGB(230, 150, 90),
}

-- entries: { { userId, name, nights } } or nil when the DataStore is offline.
function LobbyBuilder.fillLeaderboard(board: BasePart, entries)
	local gui = board:FindFirstChild("LeaderboardGui")
	if not gui then
		return
	end
	local rows = gui.Rows
	for _, c in ipairs(rows:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	if entries == nil then
		gui.Status.Text = "Leaderboard offline"
		gui.Status.Visible = true
		return
	end
	if #entries == 0 then
		gui.Status.Text = "No runs yet. Be the first!"
		gui.Status.Visible = true
		return
	end
	gui.Status.Visible = false
	for i, e in ipairs(entries) do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.fromScale(1, 0.092)
		row.BackgroundColor3 = if i % 2 == 1 then Color3.fromRGB(64, 78, 92) else Color3.fromRGB(54, 66, 80)
		row.BorderSizePixel = 0
		row.Parent = rows
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.25, 0)
		c.Parent = row
		text(row, {
			Size = UDim2.fromScale(0.1, 0.9),
			Position = UDim2.fromScale(0.01, 0.05),
			Text = tostring(i),
			TextColor3 = RANK_COLORS[i] or Color3.new(1, 1, 1),
		})
		local head = Instance.new("ImageLabel")
		head.BackgroundColor3 = Color3.fromRGB(230, 230, 236)
		head.Size = UDim2.fromScale(0.09, 0.86)
		head.Position = UDim2.fromScale(0.12, 0.07)
		head.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(e.userId)
		head.Parent = row
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(1, 0)
		hc.Parent = head
		text(row, {
			Size = UDim2.fromScale(0.5, 0.7),
			Position = UDim2.fromScale(0.24, 0.15),
			Text = e.name,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if i <= 3 then RANK_COLORS[i] else Color3.new(1, 1, 1),
		})
		icon(row, "moon", { Size = UDim2.fromScale(0.08, 0.8), Position = UDim2.fromScale(0.76, 0.1) })
		text(row, {
			Size = UDim2.fromScale(0.14, 0.8),
			Position = UDim2.fromScale(0.85, 0.1),
			Text = tostring(e.nights),
			TextColor3 = Color3.fromRGB(255, 226, 120),
		})
	end
end

local HOWTO = {
	{ "bell", "Check guests in at the FRONT DESK" },
	{ "broom", "Clean rooms: trash out, fresh sheets" },
	{ "towel", "Bring towels when guests ask = tips" },
	{ "wrench", "Fix broken AC, reset the breaker" },
	{ "trolley", "Buy supplies at the SUPPLY SHOP" },
	{ "coin", "Pay the bill at dawn. Survive as long as you can!" },
}

function LobbyBuilder.buildHowToGui(board: BasePart)
	local gui = surface(board, Enum.NormalId.Left, 30)
	text(gui, {
		Size = UDim2.fromScale(0.9, 0.12),
		Position = UDim2.fromScale(0.05, 0.03),
		Text = "HOW TO PLAY",
		TextColor3 = Color3.fromRGB(255, 226, 120),
		Stroke = 5,
	})
	for i, step in ipairs(HOWTO) do
		local y = 0.18 + (i - 1) * 0.135
		local medal = Instance.new("Frame")
		medal.BackgroundColor3 = Color3.fromRGB(255, 240, 200)
		medal.Size = UDim2.fromScale(0.1, 0.115)
		medal.Position = UDim2.fromScale(0.05, y)
		medal.Parent = gui
		local mc = Instance.new("UICorner")
		mc.CornerRadius = UDim.new(0.25, 0)
		mc.Parent = medal
		icon(medal, step[1], { Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05) })
		text(gui, {
			Size = UDim2.fromScale(0.78, 0.1),
			Position = UDim2.fromScale(0.18, y + 0.008),
			Text = step[2],
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
end

return LobbyBuilder
