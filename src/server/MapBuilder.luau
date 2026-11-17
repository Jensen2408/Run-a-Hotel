--!nonstrict
--[[
	Builds the placeholder blockout under Workspace.Motel so a fresh
	`rojo build` is playable on its own:

	  Workspace.Motel
	    Map           static geometry (floors, walls, furniture)
	    Waypoints     invisible anchor parts used for NPC routes
	    Interactables parts that hold ProximityPrompts (Action / RoomId attributes)
	    Runtime       cars and guests (cleared on restart)

	Final art can replace the Map folder later; keep the Waypoints and
	Interactables names so the server code keeps working.
]]

local Workspace = game:GetService("Workspace")

local MapBuilder = {}

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

local function label(parent: Instance, text: string, offsetY: number, size: UDim2?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = size or UDim2.fromOffset(200, 50)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local tl = Instance.new("TextLabel")
	tl.Name = "Text"
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	tl.BackgroundTransparency = 0.25
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBold
	tl.Text = text
	tl.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = tl
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = tl
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

local function light(parent: Instance, range: number, brightness: number)
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

	-- Ground, road, parking -------------------------------------------------
	part({
		Name = "Ground",
		Size = Vector3.new(240, 1, 200),
		Position = Vector3.new(10, -0.5, -10),
		Color = Color3.fromRGB(92, 140, 76),
		Material = Enum.Material.Grass,
		Parent = map,
	})
	part({
		Name = "Road",
		Size = Vector3.new(240, 0.2, 14),
		Position = Vector3.new(10, 0.1, -64),
		Color = Color3.fromRGB(50, 50, 55),
		Material = Enum.Material.Asphalt,
		Parent = map,
	})
	part({
		Name = "ParkingLot",
		Size = Vector3.new(52, 0.2, 16),
		Position = Vector3.new(-6, 0.1, -48),
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
			Size = Vector3.new(0.4, 0.22, 10),
			Position = Vector3.new(x + 4, 0.12, -48),
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
	part({
		Name = "LobbyBackWall",
		Size = Vector3.new(1, 10, 26),
		Position = Vector3.new(4, 5, -19),
		Color = Color3.fromRGB(230, 220, 200),
		Parent = map,
	})
	part({
		Name = "LobbySign",
		Size = Vector3.new(20, 4, 1),
		Position = Vector3.new(26, 13, -32),
		Color = Color3.fromRGB(200, 40, 60),
		Material = Enum.Material.Neon,
		Parent = map,
	})
	label(map:FindFirstChild("LobbySign"), "RUN A MOTEL", 3, UDim2.fromOffset(260, 50))

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
	label(desk, "FRONT DESK", 4, UDim2.fromOffset(160, 36))
	local deskLamp = part({
		Name = "DeskLamp",
		Size = Vector3.new(1, 1, 1),
		Shape = Enum.PartType.Ball,
		Position = Vector3.new(29, 5, -14),
		Color = Color3.fromRGB(255, 220, 140),
		Material = Enum.Material.Neon,
		Parent = map,
	})
	table.insert(layout.powerLights, { part = deskLamp, light = light(deskLamp, 18, 1.5) })
	local ceiling = part({
		Name = "LobbyLamp",
		Size = Vector3.new(2, 0.5, 2),
		Position = Vector3.new(22, 11, -20),
		Color = Color3.fromRGB(255, 240, 200),
		Material = Enum.Material.Neon,
		Parent = map,
	})
	table.insert(layout.powerLights, { part = ceiling, light = light(ceiling, 30, 2) })

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
	layout.breakerLabel = label(breaker, "BREAKER", 3, UDim2.fromOffset(140, 32))

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
	label(shop, "SUPPLY SHOP", 4, UDim2.fromOffset(160, 36))

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
			Size = Vector3.new(14, 9, 1),
			Position = Vector3.new(cx, 4.5, 20),
			Color = wallColor,
			Parent = roomFolder,
		})
		part({
			Name = "LeftWall",
			Size = Vector3.new(1, 9, 16),
			Position = Vector3.new(cx - 7, 4.5, 12),
			Color = wallColor,
			Parent = roomFolder,
		})
		part({
			Name = "RightWall",
			Size = Vector3.new(1, 9, 16),
			Position = Vector3.new(cx + 7, 4.5, 12),
			Color = wallColor,
			Parent = roomFolder,
		})
		part({
			Name = "FrontWallL",
			Size = Vector3.new(5, 9, 1),
			Position = Vector3.new(cx - 4.5, 4.5, 4),
			Color = wallColor,
			Parent = roomFolder,
		})
		part({
			Name = "FrontWallR",
			Size = Vector3.new(5, 9, 1),
			Position = Vector3.new(cx + 4.5, 4.5, 4),
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
			Size = Vector3.new(2, 1.6, 1.6), -- cylinder axis is X, rotated upright
			Position = Vector3.new(cx - 5, 1.4, 7),
			Color = Color3.fromRGB(60, 60, 60),
			Shape = Enum.PartType.Cylinder,
			Orientation = Vector3.new(0, 0, 90),
			Parent = interact,
		})
		local trashBag = part({
			Name = "TrashBag",
			Size = Vector3.new(1.6, 1.6, 1.6),
			Shape = Enum.PartType.Ball,
			Position = Vector3.new(cx - 5, 3, 7),
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
			Position = Vector3.new(cx, 8.6, 12),
			Color = Color3.fromRGB(255, 240, 200),
			Material = Enum.Material.Neon,
			Parent = roomFolder,
		})
		table.insert(layout.powerLights, { part = lamp, light = light(lamp, 16, 1) })

		local signPost = part({
			Name = "Room" .. i .. "Sign",
			Size = Vector3.new(0.5, 0.5, 0.5),
			Position = Vector3.new(cx, 10.5, 4),
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
			sign = label(signPost, "Room " .. i, 0, UDim2.fromOffset(220, 46)),
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
	layout.linenLabel = label(shelf, "LINEN", 4.5, UDim2.fromOffset(200, 40))

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
	label(dumpster, "DUMPSTER", 3.5, UDim2.fromOffset(150, 34))

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

	root.Parent = Workspace
	return layout
end

return MapBuilder
