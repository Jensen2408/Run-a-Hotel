--!nonstrict
--[[
	Builds the placeholder blockout under Workspace.Motel so a fresh
	`rojo build` is playable on its own:

	  Workspace.Motel
	    Map           static geometry (floors, walls, furniture)
	    Waypoints     invisible anchor parts used for NPC routes
	    Interactables parts that hold ProximityPrompts (Action / RoomId attributes)
	    Runtime       cars and guests (cleared on restart)

	Map/Decor holds the low-poly scenery (see MapDecor).

	Final art can replace the Map folder later; keep the Waypoints and
	Interactables names so the server code keeps working.

	Edit-mode preview: run MapBuilder.build(Config) from the Studio command
	bar (or via MCP). The server reuses that map when its MapVersion
	attribute matches, so you can see the motel before pressing Play.
]]

local Workspace = game:GetService("Workspace")

local MapDecor = require(script.Parent:WaitForChild("MapDecor"))
local LightingFX = require(script.Parent:WaitForChild("LightingFX"))

local MapBuilder = {}

-- Bump when the layout changes so stale saved maps are rebuilt.
MapBuilder.VERSION = 5

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		if k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

-- World label in the HUD style: small outlined Fredoka text, no background.
-- Sized in studs so it shrinks with distance, and not AlwaysOnTop so walls
-- and roofs hide it instead of it covering the scene.
local function label(parent: Instance, text: string, offsetY: number, widthStuds: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromScale(widthStuds or 4.5, 1)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	local tl = Instance.new("TextLabel")
	tl.Name = "Text"
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.TextScaled = true
	tl.Font = Enum.Font.FredokaOne
	tl.Text = text
	tl.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(46, 32, 22)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = tl
	gui.Parent = parent
	return tl
end

local function prompt(parent: Instance, config, opts)
	local holder = parent
	if opts.offset then
		local att = Instance.new("Attachment")
		att.Name = opts.action .. "Attachment"
		att.Position = opts.offset
		att.Parent = parent
		holder = att
	end
	local pp = Instance.new("ProximityPrompt")
	pp.Name = opts.action
	pp.ActionText = opts.actionText
	pp.ObjectText = opts.objectText or ""
	pp.KeyboardKeyCode = opts.key or Enum.KeyCode.E
	pp.GamepadKeyCode = opts.gamepadKey or Enum.KeyCode.ButtonX
	pp.HoldDuration = opts.hold or 0
	pp.MaxActivationDistance = config.interaction.promptRange
	pp.RequiresLineOfSight = false
	pp:SetAttribute("Action", opts.action)
	if opts.roomId then
		pp:SetAttribute("RoomId", opts.roomId)
	end
	pp.Parent = holder
	return pp
end

local function waypoint(folder: Instance, name: string, pos: Vector3)
	return part({
		Name = name,
		Size = Vector3.new(1, 1, 1),
		Position = pos,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = folder,
	})
end

-- Lights with the PowerLight attribute go dark during a power outage.
local function light(parent: Instance, range: number, brightness: number)
	parent:SetAttribute("PowerLight", true)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = Color3.fromRGB(255, 236, 200)
	l.Parent = parent
	return l
end

function MapBuilder.build(config)
	local old = Workspace:FindFirstChild("Motel")
	if old then
		old:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "Motel"
	local map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = root
	local wpFolder = Instance.new("Folder")
	wpFolder.Name = "Waypoints"
	wpFolder.Parent = root
	local interact = Instance.new("Folder")
	interact.Name = "Interactables"
	interact.Parent = root
	local runtime = Instance.new("Folder")
	runtime.Name = "Runtime"
	runtime.Parent = root

	local layout = {
		root = root,
		runtime = runtime,
		rooms = {},
		powerLights = {},
		prompts = {},
		parkingSlots = {},
	}

	-- Parking (ground, road and scenery are built by MapDecor) ------------------
	part({
		Name = "ParkingLot",
		Size = Vector3.new(52, 0.24, 15),
		Position = Vector3.new(-6, 0.12, -47.5),
		Color = Color3.fromRGB(70, 70, 76),
		Material = Enum.Material.Asphalt,
		Parent = map,
	})
	part({
		Name = "Path",
		Size = Vector3.new(6, 0.25, 18),
		Position = Vector3.new(26, 0.12, -40),
		Color = Color3.fromRGB(170, 160, 140),
		Material = Enum.Material.Concrete,
		Parent = map,
	})
	local slotXs = { -26, -18, -10, -2, 6, 14 }
	for i, x in ipairs(slotXs) do
		part({
			Name = "SlotLine" .. i,
			Size = Vector3.new(0.4, 0.04, 10),
			Position = Vector3.new(x + 4, 0.25, -48),
			Color = Color3.new(1, 1, 1),
			Parent = map,
		})
		layout.parkingSlots[i] = waypoint(wpFolder, "ParkingSlot" .. i, Vector3.new(x, 1, -48)).Position
	end
	layout.roadIn = waypoint(wpFolder, "RoadIn", Vector3.new(-80, 1, -66)).Position
	layout.roadOut = waypoint(wpFolder, "RoadOut", Vector3.new(90, 1, -62)).Position
	layout.roadInZ = -66
	layout.roadOutZ = -62

	-- Lobby ------------------------------------------------------------------
	part({
		Name = "LobbyFloor",
		Size = Vector3.new(36, 0.4, 26),
		Position = Vector3.new(22, 0.2, -19),
		Color = Color3.fromRGB(196, 176, 150),
		Material = Enum.Material.WoodPlanks,
		Parent = map,
	})
	local desk = part({
		Name = "Desk",
		Size = Vector3.new(10, 4, 2),
		Position = Vector3.new(26, 2.4, -14),
		Color = Color3.fromRGB(120, 72, 40),
		Material = Enum.Material.Wood,
		Parent = interact,
	})
	layout.deskPosition = desk.Position
	layout.prompts.desk = prompt(desk, config, {
		action = "OpenCheckIn",
		actionText = "Check In Guest",
		objectText = "Front Desk",
		offset = Vector3.new(0, 1.5, -1.2),
	})
	label(desk, "FRONT DESK", 3.2, 4)
	local deskLamp = part({
		Name = "DeskLamp",
		Size = Vector3.new(1, 1, 1),
		Shape = Enum.PartType.Ball,
		Position = Vector3.new(29, 5, -14),
		Color = Color3.fromRGB(255, 220, 140),
		Material = Enum.Material.Neon,
		Parent = map,
	})
	light(deskLamp, 14, 1)
	local ceiling = part({
		Name = "LobbyLamp",
		Size = Vector3.new(2, 0.5, 2),
		Position = Vector3.new(22, 13.4, -20),
		Color = Color3.fromRGB(255, 240, 200),
		Material = Enum.Material.Neon,
		Parent = map,
	})
	light(ceiling, 26, 0.9)

	-- Queue: slot 1 is in front of the desk, the line grows toward the entrance.
	layout.queueSlots = {}
	for k = 1, 10 do
		layout.queueSlots[k] = waypoint(wpFolder, "QueueSlot" .. k, Vector3.new(26, 1, -18 - 3.5 * (k - 1))).Position
	end
	layout.entrance = waypoint(wpFolder, "LobbyEntrance", Vector3.new(26, 1, -36)).Position
	layout.deskSide = waypoint(wpFolder, "DeskSide", Vector3.new(16, 1, -18)).Position
	layout.hallMain = waypoint(wpFolder, "HallMain", Vector3.new(16, 1, -3)).Position

	-- Breaker panel (maintenance).
	local breaker = part({
		Name = "BreakerPanel",
		Size = Vector3.new(1, 4, 3),
		Position = Vector3.new(5, 4, -10),
		Color = Color3.fromRGB(110, 110, 120),
		Material = Enum.Material.Metal,
		Parent = interact,
	})
	layout.breakerPart = breaker
	layout.prompts.breaker = prompt(breaker, config, {
		action = "ResetBreaker",
		actionText = "Reset Breaker",
		objectText = "Breaker Panel",
		hold = config.interaction.breakerHoldDuration,
		offset = Vector3.new(1, 0, 0),
	})
	layout.breakerLabel = label(breaker, "BREAKER", 3, 3.5)

	-- Supply shop kiosk.
	local shop = part({
		Name = "SupplyShop",
		Size = Vector3.new(4, 5, 3),
		Position = Vector3.new(36, 2.9, -26),
		Color = Color3.fromRGB(40, 110, 170),
		Parent = interact,
	})
	layout.prompts.refill = prompt(shop, config, {
		action = "BuyRefill",
		actionText = ("Buy Refill ($%d)"):format(config.supplies.refillCost),
		objectText = ("+%d sheets, +%d towels"):format(config.supplies.refillSheets, config.supplies.refillTowels),
		key = Enum.KeyCode.E,
		gamepadKey = Enum.KeyCode.ButtonX,
		offset = Vector3.new(-2.2, 0.8, 0),
	})
	layout.prompts.trolley = prompt(shop, config, {
		action = "BuyTrolley",
		actionText = ("Buy Trolley ($%d)"):format(config.supplies.trolleyCost),
		objectText = ("Team carry %d -> %d"):format(
			config.supplies.baseCarryCapacity,
			config.supplies.trolleyCarryCapacity
		),
		key = Enum.KeyCode.F,
		gamepadKey = Enum.KeyCode.ButtonY,
		offset = Vector3.new(-2.2, -0.8, 0),
	})
	label(shop, "SUPPLY SHOP", 3.6, 4.5)

	-- Hallway ---------------------------------------------------------------
	part({
		Name = "Hallway",
		Size = Vector3.new(66, 0.3, 6),
		Position = Vector3.new(24, 0.15, -3),
		Color = Color3.fromRGB(170, 160, 140),
		Material = Enum.Material.Concrete,
		Parent = map,
	})

	-- Rooms -----------------------------------------------------------------
	local roomCenters = { 2, 20, 38, 56 }
	for i = 1, config.roomCount do
		local cx = roomCenters[i] or (2 + 18 * (i - 1))
		local roomFolder = Instance.new("Folder")
		roomFolder.Name = "Room" .. i
		roomFolder.Parent = map
		local wallColor = Color3.fromRGB(235, 225, 205)
		part({
			Name = "Floor",
			Size = Vector3.new(14, 0.4, 16),
			Position = Vector3.new(cx, 0.2, 12),
			Color = Color3.fromRGB(150, 120, 100),
			Material = Enum.Material.Carpet,
			Parent = roomFolder,
		})
		part({
			Name = "BackWall",
			Size = Vector3.new(14, 12, 1),
			Position = Vector3.new(cx, 6, 20),
			Color = wallColor,
			Parent = roomFolder,
		})
		part({
			Name = "LeftWall",
			Size = Vector3.new(1, 12, 16),
			Position = Vector3.new(cx - 7, 6, 12),
			Color = wallColor,
			Parent = roomFolder,
		})
		part({
			Name = "RightWall",
			Size = Vector3.new(1, 12, 16),
			Position = Vector3.new(cx + 7, 6, 12),
			Color = wallColor,
			Parent = roomFolder,
		})
		part({
			Name = "FrontWallL",
			Size = Vector3.new(5, 12, 1),
			Position = Vector3.new(cx - 4.5, 6, 4),
			Color = wallColor,
			Parent = roomFolder,
		})
		part({
			Name = "FrontWallR",
			Size = Vector3.new(5, 12, 1),
			Position = Vector3.new(cx + 4.5, 6, 4),
			Color = wallColor,
			Parent = roomFolder,
		})
		-- Lintel above the doorway (door opening stays 7.6 studs tall).
		part({
			Name = "DoorLintel",
			Size = Vector3.new(4, 4.4, 1),
			Position = Vector3.new(cx, 9.8, 4),
			Color = wallColor,
			Parent = roomFolder,
		})

		local door = part({
			Name = "Room" .. i .. "Door",
			Size = Vector3.new(4, 0.3, 2),
			Position = Vector3.new(cx, 0.3, 3),
			Color = Color3.fromRGB(90, 70, 50),
			Parent = interact,
		})
		local bed = part({
			Name = "Room" .. i .. "Bed",
			Size = Vector3.new(5, 1.6, 7),
			Position = Vector3.new(cx + 3, 1.2, 15),
			Color = Color3.fromRGB(245, 245, 245),
			Material = Enum.Material.Fabric,
			Parent = interact,
		})
		local bin = part({
			Name = "Room" .. i .. "TrashBin",
			Size = Vector3.new(3, 2.2, 2.2), -- cylinder axis is X, rotated upright (3 studs tall)
			Position = Vector3.new(cx - 5, 1.9, 7),
			Color = Color3.fromRGB(60, 60, 60),
			Shape = Enum.PartType.Cylinder,
			Orientation = Vector3.new(0, 0, 90),
			Parent = interact,
		})
		local trashBag = part({
			Name = "TrashBag",
			Size = Vector3.new(1.8, 1.8, 1.8),
			Shape = Enum.PartType.Ball,
			Position = Vector3.new(cx - 5, 4, 7),
			Color = Color3.fromRGB(20, 20, 20),
			CanCollide = false,
			Transparency = 1,
			Parent = roomFolder,
		})
		local ac = part({
			Name = "Room" .. i .. "AC",
			Size = Vector3.new(4, 2, 1),
			Position = Vector3.new(cx - 2, 6, 19.4),
			Color = Color3.fromRGB(210, 215, 220),
			Material = Enum.Material.Metal,
			Parent = interact,
		})
		local lamp = part({
			Name = "Lamp",
			Size = Vector3.new(1.5, 0.4, 1.5),
			Position = Vector3.new(cx, 11.4, 12),
			Color = Color3.fromRGB(255, 240, 200),
			Material = Enum.Material.Neon,
			Parent = roomFolder,
		})
		light(lamp, 14, 0.8)

		local signPost = part({
			Name = "Room" .. i .. "Sign",
			Size = Vector3.new(0.5, 0.5, 0.5),
			Position = Vector3.new(cx, 9.4, 2.9),
			Transparency = 1,
			CanCollide = false,
			Parent = roomFolder,
		})

		local room = {
			id = i,
			center = Vector3.new(cx, 1, 12),
			door = door,
			bed = bed,
			bin = bin,
			trashBag = trashBag,
			ac = ac,
			sign = label(signPost, "Room " .. i, 0, 7),
			hall = waypoint(wpFolder, "Room" .. i .. "Hall", Vector3.new(cx, 1, -3)).Position,
			doorPoint = waypoint(wpFolder, "Room" .. i .. "DoorPoint", Vector3.new(cx, 1, 2)).Position,
			inside = waypoint(wpFolder, "Room" .. i .. "Inside", Vector3.new(cx - 1.5, 1, 11)).Position,
			prompts = {
				changeSheets = prompt(bed, config, {
					action = "ChangeSheets",
					actionText = "Change Sheets",
					objectText = "Room " .. i .. " Bed",
					roomId = i,
				}),
				collectTrash = prompt(bin, config, {
					action = "CollectTrash",
					actionText = "Collect Trash",
					objectText = "Room " .. i,
					roomId = i,
					-- Bin is rotated 90deg on Z, so local +X is world up: raise the prompt to eye level.
					offset = Vector3.new(2.5, 0, 0),
				}),
				deliverTowel = prompt(door, config, {
					action = "DeliverTowel",
					actionText = "Deliver Towel",
					objectText = "Room " .. i,
					roomId = i,
				}),
				repairAC = prompt(ac, config, {
					action = "RepairAC",
					actionText = "Repair AC",
					objectText = "Room " .. i,
					roomId = i,
					hold = config.interaction.repairHoldDuration,
				}),
			},
		}
		layout.rooms[i] = room
	end

	-- Linen room (housekeeping) ----------------------------------------------
	part({
		Name = "LinenFloor",
		Size = Vector3.new(14, 0.4, 14),
		Position = Vector3.new(60, 0.2, -16),
		Color = Color3.fromRGB(200, 200, 210),
		Material = Enum.Material.Concrete,
		Parent = map,
	})
	local shelf = part({
		Name = "LinenShelf",
		Size = Vector3.new(8, 6, 2),
		Position = Vector3.new(60, 3.2, -22),
		Color = Color3.fromRGB(150, 110, 70),
		Material = Enum.Material.Wood,
		Parent = interact,
	})
	layout.prompts.takeSheet = prompt(shelf, config, {
		action = "TakeSheet",
		actionText = "Take Sheet",
		objectText = "Linen Shelf",
		key = Enum.KeyCode.E,
		gamepadKey = Enum.KeyCode.ButtonX,
		offset = Vector3.new(-2.5, 0, 1.2),
	})
	layout.prompts.takeTowel = prompt(shelf, config, {
		action = "TakeTowel",
		actionText = "Take Towel",
		objectText = "Linen Shelf",
		key = Enum.KeyCode.F,
		gamepadKey = Enum.KeyCode.ButtonY,
		offset = Vector3.new(0, 0, 1.2),
	})
	layout.prompts.returnSupplies = prompt(shelf, config, {
		action = "ReturnSupplies",
		actionText = "Return Supplies",
		objectText = "Linen Shelf",
		key = Enum.KeyCode.R,
		gamepadKey = Enum.KeyCode.ButtonB,
		offset = Vector3.new(2.5, 0, 1.2),
	})
	layout.linenLabel = label(shelf, "LINEN", 4, 7)

	-- Dumpster ---------------------------------------------------------------
	local dumpster = part({
		Name = "Dumpster",
		Size = Vector3.new(6, 4, 4),
		Position = Vector3.new(64, 2, 6),
		Color = Color3.fromRGB(40, 100, 60),
		Material = Enum.Material.Metal,
		Parent = interact,
	})
	layout.prompts.dumpTrash = prompt(dumpster, config, {
		action = "DumpTrash",
		actionText = "Dump Trash",
		objectText = "Dumpster",
	})
	label(dumpster, "DUMPSTER", 3.2, 4)

	-- Rain emitter (enabled by the server on rainy nights) ----------------------
	local rainPart = part({
		Name = "RainEmitter",
		Size = Vector3.new(200, 1, 160),
		Position = Vector3.new(20, 70, -15),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = map,
	})
	local rain = Instance.new("ParticleEmitter")
	rain.Name = "Rain"
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Speed = NumberRange.new(70, 90)
	rain.Lifetime = NumberRange.new(1, 1.2)
	rain.Rate = 0
	rain.Size = NumberSequence.new(0.15)
	rain.Transparency = NumberSequence.new(0.4)
	rain.Color = ColorSequence.new(Color3.fromRGB(180, 200, 230))
	rain.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	rain.Squash = NumberSequence.new(3)
	rain.Parent = rainPart
	layout.rain = rain

	-- Player spawn -------------------------------------------------------------
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MotelSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.Position = Vector3.new(20, 0.45, -24)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(196, 176, 150)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = map

	-- Parent the small gameplay tree first, then add scenery incrementally
	-- (MapDecor yields between batches so Studio stays responsive).
	root:SetAttribute("MapVersion", MapBuilder.VERSION)
	root:SetAttribute("RoomCount", config.roomCount)
	root.Parent = Workspace
	LightingFX.apply()
	MapDecor.build(map)
	return MapBuilder.collect(root, config)
end

------------------------------------------------------------------------
-- Collect: rebuild the layout table from an existing Workspace.Motel by
-- instance names, so a map built in Edit mode (or saved in the place) is
-- reused at runtime instead of being rebuilt.
------------------------------------------------------------------------

local function must(parent: Instance, name: string): Instance
	local child = parent:FindFirstChild(name)
	assert(child, ("Motel map is missing %s.%s"):format(parent:GetFullName(), name))
	return child
end

local function promptIn(holder: Instance, name: string): ProximityPrompt
	local pp = holder:FindFirstChild(name, true)
	assert(pp and pp:IsA("ProximityPrompt"), ("Missing prompt %s under %s"):format(name, holder:GetFullName()))
	return pp
end

local function labelText(holder: Instance): TextLabel
	return must(must(holder, "Label"), "Text") :: TextLabel
end

function MapBuilder.collect(root: Instance, config)
	local map = must(root, "Map")
	local wp = must(root, "Waypoints")
	local interact = must(root, "Interactables")
	local runtime = root:FindFirstChild("Runtime")
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = "Runtime"
		runtime.Parent = root
	end
	runtime:ClearAllChildren()

	local function point(name: string): Vector3
		return (must(wp, name) :: BasePart).Position
	end

	local layout = {
		root = root,
		runtime = runtime,
		rooms = {},
		prompts = {},
		parkingSlots = {},
		queueSlots = {},
		powerLights = {},
	}

	local i = 1
	while wp:FindFirstChild("ParkingSlot" .. i) do
		layout.parkingSlots[i] = point("ParkingSlot" .. i)
		i += 1
	end
	i = 1
	while wp:FindFirstChild("QueueSlot" .. i) do
		layout.queueSlots[i] = point("QueueSlot" .. i)
		i += 1
	end
	layout.roadIn = point("RoadIn")
	layout.roadOut = point("RoadOut")
	layout.roadInZ = layout.roadIn.Z
	layout.roadOutZ = layout.roadOut.Z
	layout.entrance = point("LobbyEntrance")
	layout.deskSide = point("DeskSide")
	layout.hallMain = point("HallMain")

	local desk = must(interact, "Desk") :: BasePart
	layout.deskPosition = desk.Position
	layout.prompts.desk = promptIn(desk, "OpenCheckIn")

	local breaker = must(interact, "BreakerPanel")
	layout.breakerPart = breaker
	layout.prompts.breaker = promptIn(breaker, "ResetBreaker")
	layout.breakerLabel = labelText(breaker)

	local shop = must(interact, "SupplyShop")
	layout.prompts.refill = promptIn(shop, "BuyRefill")
	layout.prompts.trolley = promptIn(shop, "BuyTrolley")

	local shelf = must(interact, "LinenShelf")
	layout.prompts.takeSheet = promptIn(shelf, "TakeSheet")
	layout.prompts.takeTowel = promptIn(shelf, "TakeTowel")
	layout.prompts.returnSupplies = promptIn(shelf, "ReturnSupplies")
	layout.linenLabel = labelText(shelf)

	layout.prompts.dumpTrash = promptIn(must(interact, "Dumpster"), "DumpTrash")

	for r = 1, config.roomCount do
		local prefix = "Room" .. r
		local roomFolder = must(map, prefix)
		local door = must(interact, prefix .. "Door")
		local bed = must(interact, prefix .. "Bed")
		local bin = must(interact, prefix .. "TrashBin")
		local ac = must(interact, prefix .. "AC")
		layout.rooms[r] = {
			id = r,
			door = door,
			bed = bed,
			bin = bin,
			trashBag = must(roomFolder, "TrashBag"),
			ac = ac,
			sign = labelText(must(roomFolder, prefix .. "Sign")),
			hall = point(prefix .. "Hall"),
			doorPoint = point(prefix .. "DoorPoint"),
			inside = point(prefix .. "Inside"),
			prompts = {
				changeSheets = promptIn(bed, "ChangeSheets"),
				collectTrash = promptIn(bin, "CollectTrash"),
				deliverTowel = promptIn(door, "DeliverTowel"),
				repairAC = promptIn(ac, "RepairAC"),
			},
		}
	end

	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("PowerLight") then
			local l = d:FindFirstChildWhichIsA("Light")
			if l then
				table.insert(layout.powerLights, { part = d, light = l })
			end
		end
	end

	layout.rain = must(must(map, "RainEmitter"), "Rain")
	-- Optional scenery hooks.
	layout.vacancyLabel = map:FindFirstChild("VacancyText", true)
	return layout
end

-- Reuses Workspace.Motel when it was built by this MapBuilder version,
-- otherwise builds it from scratch.
function MapBuilder.ensure(config)
	local existing = Workspace:FindFirstChild("Motel")
	if
		existing
		and existing:GetAttribute("MapVersion") == MapBuilder.VERSION
		and existing:GetAttribute("RoomCount") == config.roomCount
	then
		local ok, layoutOrErr = pcall(MapBuilder.collect, existing, config)
		if ok then
			return layoutOrErr
		end
		warn("[Motel] Existing map is incomplete, rebuilding: " .. tostring(layoutOrErr))
	end
	return MapBuilder.build(config)
end

return MapBuilder
