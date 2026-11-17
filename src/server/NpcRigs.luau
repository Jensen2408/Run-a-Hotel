--!nonstrict
--[[
	NpcRigs: default Roblox R15 characters for guests and the shopkeeper,
	dressed from a fixed list of outfits (catalog items made by Roblox:
	classic shirt/pants, face, hair; IDs checked with GetProductInfo).

	Building a rig downloads assets (Players:CreateHumanoidModelFromDescription
	yields), so every outfit is built once in the background at startup and
	guests are clones of those templates. Until a template is ready,
	NpcRigs.clone returns nil and Visuals keeps using its blocky rig.

	Rigs are posed by moving the anchored HumanoidRootPart; the other parts
	hang on it through the rig's joints. Walk/idle use the default R15
	animations.
]]

local Players = game:GetService("Players")

local NpcRigs = {}

-- Catalog asset IDs (all created by Roblox).
local HAIR = {
	pal = 63690008, -- Pal Hair
	lavenderUpdo = 451220849, -- Lavender Updo
	brownCharmer = 376548738, -- Brown Charmer Hair
	blondeSpiked = 376524487, -- Blonde Spiked Hair
	brown = 62234425, -- Brown Hair
	trueBlue = 451221329, -- True Blue Hair
	straightBlonde = 376526888, -- Straight Blonde Hair
	stylishBrown = 62743701, -- Stylish Brown Hair
}
local HAT = {
	robloxCap = 607702162, -- Roblox Baseball Cap
}
local FACE = {
	smile = 144075659, -- Smile
	chill = 7074764, -- Chill
	sillyFun = 7699174, -- Silly Fun
	freckles = 12145366, -- Freckles
	checkIt = 7074786, -- Check It
	meh = 7075469, -- :-/
	stare = 8560971, -- Stare
	glee = 7074729, -- Glee
}
local SHIRT = {
	motorcycle = 144076358, -- Blue and Black Motorcycle Shirt
	denimStriped = 144076436, -- Grey Striped Shirt with Denim Jacket
	robloxJacket = 607785314, -- ROBLOX Jacket
	denimHoodie = 398633584, -- Denim Jacket with White Hoodie
	greenJersey = 382538059, -- Green Jersey
	guitarTee = 382538295, -- Guitar Tee with Black Jacket
	pizza = 382537085, -- I <3 Pizza Shirt
	teal = 382537702, -- Teal Shirt
}
local PANTS = {
	pinkJeans = 144076512, -- Pink Jeans
	darkGreenJeans = 144076760, -- Dark Green Jeans
	blackJeans = 382537569, -- Black Jeans
	blackJeansSneakers = 382538503, -- Black Jeans with Sneakers
	skater = 398635338, -- Ripped Skater Pants
}
local SKIN = {
	Color3.fromRGB(255, 220, 185),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(160, 106, 72),
	Color3.fromRGB(105, 70, 50),
}

export type Outfit = {
	hair: { number },
	face: number,
	shirt: number,
	pants: number,
	skin: Color3,
}

-- Guest outfits; guest id picks one (Visuals).
NpcRigs.OUTFITS = {
	{
		hair = { HAIR.brownCharmer },
		face = FACE.smile,
		shirt = SHIRT.denimStriped,
		pants = PANTS.blackJeans,
		skin = SKIN[2],
	},
	{ hair = { HAIR.lavenderUpdo }, face = FACE.freckles, shirt = SHIRT.teal, pants = PANTS.pinkJeans, skin = SKIN[1] },
	{
		hair = { HAIR.pal },
		face = FACE.checkIt,
		shirt = SHIRT.greenJersey,
		pants = PANTS.darkGreenJeans,
		skin = SKIN[4],
	},
	{ hair = { HAIR.trueBlue }, face = FACE.sillyFun, shirt = SHIRT.pizza, pants = PANTS.skater, skin = SKIN[3] },
	{
		hair = { HAIR.blondeSpiked },
		face = FACE.chill,
		shirt = SHIRT.guitarTee,
		pants = PANTS.blackJeansSneakers,
		skin = SKIN[1],
	},
	{
		hair = { HAIR.straightBlonde },
		face = FACE.glee,
		shirt = SHIRT.denimHoodie,
		pants = PANTS.blackJeans,
		skin = SKIN[5],
	},
	{
		hair = { HAIR.brown, HAT.robloxCap },
		face = FACE.meh,
		shirt = SHIRT.motorcycle,
		pants = PANTS.darkGreenJeans,
		skin = SKIN[2],
	},
	{
		hair = { HAIR.stylishBrown },
		face = FACE.stare,
		shirt = SHIRT.robloxJacket,
		pants = PANTS.skater,
		skin = SKIN[4],
	},
}

NpcRigs.SHOPKEEPER = {
	hair = { HAIR.brownCharmer, HAT.robloxCap },
	face = FACE.glee,
	shirt = SHIRT.greenJersey,
	pants = PANTS.blackJeans,
	skin = SKIN[3],
}

-- Default R15 animations (Roblox).
local WALK_ANIM = "rbxassetid://507777826"
local IDLE_ANIM = "rbxassetid://507766388"

local function description(outfit: Outfit): HumanoidDescription
	local d = Instance.new("HumanoidDescription")
	local ids = {}
	for _, id in ipairs(outfit.hair) do
		table.insert(ids, tostring(id))
	end
	-- Hair and hats both go through HairAccessory/HatAccessory; split by list order.
	d.HairAccessory = ids[1] or ""
	d.HatAccessory = ids[2] or ""
	d.Face = outfit.face
	d.Shirt = outfit.shirt
	d.Pants = outfit.pants
	for _, prop in ipairs({
		"HeadColor",
		"TorsoColor",
		"LeftArmColor",
		"RightArmColor",
		"LeftLegColor",
		"RightLegColor",
	}) do
		d[prop] = outfit.skin
	end
	return d
end

-- Lowest sole of a rig as it stands in the world right now.
function NpcRigs.soleY(model: Model): number?
	local sole = nil
	for _, name in ipairs({ "LeftFoot", "RightFoot" }) do
		local foot = model:FindFirstChild(name)
		if foot then
			local y = foot.Position.Y - foot.Size.Y / 2
			sole = if sole then math.min(sole, y) else y
		end
	end
	return sole
end

-- Builds one rig (yields). Returns nil if the avatar service fails.
function NpcRigs.build(outfit: Outfit, scale: number): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description(outfit), Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[NpcRigs] Could not build a rig: " .. tostring(model))
		return nil
	end
	model.Name = "Npc"
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	if not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid
	end
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	root.Anchored = true
	model.PrimaryPart = root
	-- Height of the root above the soles in the rest pose. Joints only
	-- settle in the workspace, so measure there (far below the map) once.
	root.CFrame = CFrame.new(0, -400, 0)
	model.Parent = workspace
	task.wait()
	task.wait()
	local sole = NpcRigs.soleY(model)
	if not sole then
		local cf, size = model:GetBoundingBox()
		sole = cf.Position.Y - size.Y / 2
	end
	model:SetAttribute("RootHeight", root.Position.Y - sole)
	model.Parent = nil
	return model
end

------------------------------------------------------------------------
-- Templates
------------------------------------------------------------------------

local templates: { [number]: Model } = {}

-- Builds every guest outfit in the background (call once at startup).
function NpcRigs.preload(scale: number)
	task.spawn(function()
		local folder = Instance.new("Folder")
		folder.Name = "NpcTemplates"
		for i, outfit in ipairs(NpcRigs.OUTFITS) do
			local m = NpcRigs.build(outfit, scale)
			if m then
				m.Parent = folder -- kept outside the DataModel
				templates[i] = m
			end
		end
	end)
end

-- A fresh guest rig for this guest id, or nil while templates load.
function NpcRigs.clone(id: number): Model?
	local n = #NpcRigs.OUTFITS
	local t = templates[(id * 5) % n + 1]
	if not t then
		-- Any loaded outfit is better than the fallback.
		for i = 1, n do
			if templates[i] then
				t = templates[i]
				break
			end
		end
	end
	return if t then t:Clone() else nil
end

------------------------------------------------------------------------
-- Animation
------------------------------------------------------------------------

local tracks = setmetatable({}, { __mode = "k" })

local function load(model: Model)
	local t = tracks[model]
	if t then
		return t
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local function track(id, priority)
		local a = Instance.new("Animation")
		a.AnimationId = id
		local tr = animator:LoadAnimation(a)
		tr.Looped = true
		tr.Priority = priority
		return tr
	end
	t = {
		walk = track(WALK_ANIM, Enum.AnimationPriority.Movement),
		idle = track(IDLE_ANIM, Enum.AnimationPriority.Idle),
		moving = nil,
	}
	tracks[model] = t
	return t
end

-- Switches between walk and idle (no-op when unchanged). Call after the
-- model is parented to the workspace. walkRate scales the walk cycle so
-- feet keep up with the movement speed.
function NpcRigs.setMoving(model: Model, moving: boolean, walkRate: number?)
	local t = load(model)
	if not t or t.moving == moving then
		return
	end
	t.moving = moving
	if moving then
		t.idle:Stop(0.2)
		t.walk:Play(0.2, 1, walkRate or 1)
	else
		t.walk:Stop(0.2)
		t.idle:Play(0.2)
	end
end

return NpcRigs
