--!nonstrict
--[[
	Surfaces: tiling textures and decals from the generated texture sheet
	(images owned by the experience's community, groups/556114983)
	(assets/textures/motel_sheets.png, sliced by tools/slice_texture_sheet.py).

	Runs after MapBuilder has built and scaled the map: texture sizes are in
	final studs, decal hosts are placed from scale-1 coordinates times the
	map scale.

	Ground surfaces use MaterialVariants (MaterialService.Motel_*) made from
	the same images: Roblox stops drawing Texture / Decal objects at a
	distance, but materials render at any zoom. When a variant cannot be
	created, the surface falls back to a Texture on its top face.
]]

local MaterialService = game:GetService("MaterialService")

local Surfaces = {}

local TEX = {
	asphalt = "rbxassetid://72318672945290",
	concrete = "rbxassetid://112390650345913",
	grass = "rbxassetid://70920523238186",
	wood = "rbxassetid://72277939586139",
	carpet = "rbxassetid://96728838875988",
	checker = "rbxassetid://127628666130291",
	water = "rbxassetid://140076838754757",
	gravel = "rbxassetid://110870592453496",
}

local DECAL = {
	welcome = "rbxassetid://110641451677167",
	pineLake = "rbxassetid://79303140864026",
	logo = "rbxassetid://114612760438669",
	menu = "rbxassetid://95837547860178",
	supplies = "rbxassetid://111430138854445",
	poolRules = "rbxassetid://130419018669279",
	noSmoking = "rbxassetid://117184576385937",
	manhole = "rbxassetid://71939509266990",
}

-- MaterialVariant per texture: base material (physics / footsteps) and
-- studs per tile at scale 1 (one size per image).
local VARIANT = {
	asphalt = { Enum.Material.Asphalt, 10 },
	concrete = { Enum.Material.Concrete, 6 },
	grass = { Enum.Material.Grass, 10 },
	gravel = { Enum.Material.Pebble, 6 },
	wood = { Enum.Material.WoodPlanks, 6 },
	carpet = { Enum.Material.Fabric, 5 },
	checker = { Enum.Material.Marble, 16 }, -- 8 x 8 tiles of 2 studs
	water = { Enum.Material.SmoothPlastic, 8 },
}

-- {path under Motel.Map, texture, studs per tile at scale 1 (Texture fallback)}
local TEXTURED = {
	{ "Decor.Road.Asphalt", "asphalt", 10 },
	{ "ParkingLot", "asphalt", 10 },
	{ "Decor.Road.SidewalkSouth", "concrete", 6 },
	{ "Decor.Road.SidewalkNorthW", "concrete", 6 },
	{ "Decor.Road.SidewalkNorthE", "concrete", 6 },
	{ "Decor.Road.SidewalkNorthMid", "concrete", 6 },
	{ "Decor.Ground.MotelLot", "concrete", 8 },
	{ "Hallway", "concrete", 6 },
	{ "LinenFloor", "concrete", 6 },
	{ "Decor.RoomYard.DumpsterPad", "concrete", 5 },
	{ "Decor.SupplyShopBuilding.FrontPad", "concrete", 6 },
	{ "Decor.Pool.Deck", "concrete", 5 },
	{ "Decor.Ground.Grass", "grass", 10 },
	{ "Decor.Courtyard.LawnWest", "grass", 8 },
	{ "Decor.Courtyard.LawnEast", "grass", 8 },
	{ "Path", "gravel", 6 },
	{ "Decor.Courtyard.Path", "gravel", 6 },
	{ "Decor.LinenShed.Path", "gravel", 6 },
	{ "Decor.SupplyShopBuilding.Path", "gravel", 6 },
	{ "Decor.KitchenBuilding.DoorPath", "gravel", 6 },
	{ "LobbyFloor", "wood", 6 },
	{ "Decor.SupplyShopBuilding.Floor", "wood", 6 },
	{ "Decor.KitchenBuilding.Floor", "checker", 16 }, -- 8 x 8 tiles of 2 studs (as before)
	{ "Decor.Pool.Water", "water", 8 },
	{ "Room1.Floor", "carpet", 5 },
	{ "Room2.Floor", "carpet", 5 },
	{ "Room3.Floor", "carpet", 5 },
}

-- MaterialService.Motel_<key>, created once (kept if the place is saved).
local function variant(key: string, scale: number): MaterialVariant?
	local name = "Motel_" .. key
	local v = MaterialService:FindFirstChild(name)
	if v and v:IsA("MaterialVariant") then
		return v
	end
	local spec = VARIANT[key]
	local made
	local ok = pcall(function()
		made = Instance.new("MaterialVariant")
		made.Name = name
		made.BaseMaterial = spec[1]
		made.ColorMap = TEX[key]
		made.StudsPerTile = spec[2] * scale
		made.Parent = MaterialService
	end)
	if not ok then
		if made then
			made:Destroy()
		end
		return nil
	end
	return made
end

local function find(map: Instance, path: string): Instance?
	local node = map
	for name in path:gmatch("[^%.]+") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function texture(part: BasePart, id: string, studs: number)
	local t = part:FindFirstChild("SurfaceTexture") or Instance.new("Texture")
	t.Name = "SurfaceTexture"
	t.Face = Enum.NormalId.Top
	t.Texture = id
	t.StudsPerTileU = studs
	t.StudsPerTileV = studs
	t.Parent = part
	part.Material = Enum.Material.SmoothPlastic
end

--[[
	Decal on an invisible host part. spec (scale 1): pos, size (w, h of the
	image), face ("Top", "Front" = -Z, "Back" = +Z, "Left" = -X, "Right" = +X),
	yaw (degrees, Top decals only), board (visible backing colour, optional).
]]
local function decal(folder: Instance, name: string, id: string, spec, scale: number)
	local w, h = spec.size[1], spec.size[2]
	local face = spec.face
	local size
	if face == "Top" then
		size = Vector3.new(w, 0.05, h)
	elseif face == "Front" or face == "Back" then
		size = Vector3.new(w, h, if spec.board then 0.2 else 0.05)
	else
		size = Vector3.new(if spec.board then 0.2 else 0.05, h, w)
	end
	local host = Instance.new("Part")
	host.Name = name
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.Size = size * scale
	host.CFrame = CFrame.new(spec.pos * scale) * CFrame.Angles(0, math.rad(spec.yaw or 0), 0)
	if spec.board then
		host.Color = spec.board
		host.Material = Enum.Material.SmoothPlastic
	else
		host.Transparency = 1
	end
	local d = Instance.new("Decal")
	d.Texture = id
	d.Face = Enum.NormalId[face]
	d.Parent = host
	host.Parent = folder
	return host
end

function Surfaces.apply(root: Instance, scale: number)
	local map = root:FindFirstChild("Map")
	if not map then
		return
	end
	for _, item in ipairs(TEXTURED) do
		local part = find(map, item[1])
		if part and part:IsA("BasePart") then
			local v = variant(item[2], scale)
			if v then
				-- Material variant: visible at any distance; the image is
				-- tinted by the part colour, so the part goes white.
				local old = part:FindFirstChild("SurfaceTexture")
				if old then
					old:Destroy()
				end
				part.Material = v.BaseMaterial
				part.MaterialVariant = v.Name
				part.Color = Color3.new(1, 1, 1)
			else
				texture(part, TEX[item[2]], item[3] * scale)
			end
		end
	end
	-- The checker texture replaces the kitchen's red tile parts.
	local kitchen = find(map, "Decor.KitchenBuilding")
	if kitchen then
		for _, c in ipairs(kitchen:GetChildren()) do
			if c.Name == "Tile" then
				c:Destroy()
			end
		end
	end

	local decor = map:FindFirstChild("Decor")
	if not decor then
		return
	end
	local folder = decor:FindFirstChild("Decals") or Instance.new("Folder")
	folder.Name = "Decals"
	folder:ClearAllChildren()
	folder.Parent = decor
	local SHIFT = 18 -- MapDecor.ROOM_SHIFT (the pool moved north with the rooms)
	-- Office porch mat, lobby walls (east poster, logo over the front door,
	-- no-smoking by the couch), kitchen menu between the south windows, shop
	-- poster on its road-facing wall, pool rules on the pool fence, manhole.
	decal(
		folder,
		"WelcomeMat",
		DECAL.welcome,
		{ pos = Vector3.new(22, 0.52, -33.4), size = { 4.2, 2.4 }, face = "Top", yaw = 0 },
		scale
	)
	decal(
		folder,
		"PinePoster",
		DECAL.pineLake,
		{ pos = Vector3.new(39.45, 7, -10), size = { 2.5, 3.0 }, face = "Left" },
		scale
	)
	decal(
		folder,
		"MotelLogo",
		DECAL.logo,
		{ pos = Vector3.new(22, 11, -31.45), size = { 2.6, 2.6 }, face = "Back" },
		scale
	)
	decal(
		folder,
		"NoSmoking",
		DECAL.noSmoking,
		{ pos = Vector3.new(4.55, 7.5, -29.5), size = { 1.6, 1.68 }, face = "Right" },
		scale
	)
	decal(
		folder,
		"MenuBoard",
		DECAL.menu,
		{ pos = Vector3.new(-1, 5.2, -1.45), size = { 2.0, 1.96 }, face = "Back" },
		scale
	)
	decal(
		folder,
		"SuppliesPoster",
		DECAL.supplies,
		{ pos = Vector3.new(94, 4.6, -44.55), size = { 2.6, 2.9 }, face = "Front" },
		scale
	)
	decal(folder, "PoolRules", DECAL.poolRules, {
		pos = Vector3.new(-16, 2.4, -1 + SHIFT - 0.3),
		size = { 2.5, 2.7 },
		face = "Front",
		board = Color3.fromRGB(250, 246, 236),
	}, scale)
	decal(
		folder,
		"Manhole",
		DECAL.manhole,
		{ pos = Vector3.new(46, 0.32, -60.5), size = { 2.4, 2.5 }, face = "Top" },
		scale
	)
end

return Surfaces
