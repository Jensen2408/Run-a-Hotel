--!nonstrict
--[[
	NpcRigs: default Roblox R15 characters for guests and the shopkeeper,
	dressed from a fixed list of outfits (marketplace items by community
	creators: classic shirt/pants, face accessory, hair; found with
	AvatarEditorService:SearchCatalog).

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

-- Marketplace (UGC) items by community creators, picked for a casual
-- road-trip crowd; no brand names or licensed characters. Faces are face
-- accessories, so the classic face decal is removed from the head.
local HAIR = {
	coolBoy = 5644883846, -- Cool Boy Hair (genkroco)
	curlyPonytail = 6005308235, -- Blonde Aesthetic Curly High Ponytail (Archi_tecture)
	blackAfro = 11748367474, -- Black Curly Afro (HYPSAL)
	wavyBlonde = 11597599236, -- Lush Wavy Hair (Blonde) (auroriies)
	shortParted = 4875445470, -- Black Short Parted Hair (Homemade_Meal)
	braidedPonytail = 13251161977, -- Braided Ponytail(Brown) (DIDIgamedev)
	fluffyMessy = 14892162637, -- Fluffy Messy Hair(Black) (DIDIgamedev)
	orangeAfro = 12143093583, -- Orange Curly Afro (Zartania)
	blackSwept = 6413085241, -- Black Swept Hair (antilique)
}
local FACE = {
	bigSmile = 12409796490, -- Big Smile Face (3D) (Headpets)
	blushSmile = 12064732367, -- Blushing Big Smile Face (3D) (Headpets)
	cuteBlush = 13253018587, -- Cute Blush Face (Blizzei)
	kawaiiBlush = 14077508293, -- Kawaii Cutie Blush Face (VireDero)
	bored = 12162793732, -- White Simple Bored Face (Empyror)
	sideEye = 106622059771618, -- Side Eye Face (AW FACES)
	simpleBlush = 71577948938042, -- Simple Cute Blush (CH!BI)
	grumpy = 17448541918, -- Intimidating Face - Light (Evaeko)
}
local SHIRT = {
	redFlannel = 1431276681, -- MU Red Flannel w/ Black Tee (Moda Unica)
	blueFlannel = 1434248701, -- MU Blue & Black Flannel w/ Black Tee (Moda Unica)
	tropical = 7008020566, -- (B) Tropical Flannel (HairyClub)
	rainbowHoodie = 7136156284, -- Cartoony Rainbow Hoodie (Coarse)
	beigePlaid = 4015873542, -- beige plaid flannel w white shirt (Aesthetic Vibe)
	redJacket = 12499718918, -- Crimson Red Shirt + Black Jacket (DiligentVUK's Fan group)
	simpleFlannel = 6582350831, -- simple flannel w/ top (vinty)
	brownFlannel = 9069617976, -- brown flannel jacket plaid (j194cm)
	apron = 7467445048, -- Apron (+) (Eden's Bar)
}
local PANTS = {
	blackJeansSneakers = 1174596088, -- Ripped Black Jeans w/ MU White Sneakers (Moda Unica)
	denimShorts = 8828281142, -- cute denim shorts (Pink Potato Clothing)
	greyCargo = 12598481285, -- cargo pants grey (AFTER WORLD)
	rippedJeans = 5197702014, -- Cute ripped Jeans (uaeu)
	allBlack = 7189083561, -- all black pants (#AMS)
	white = 117436666145142, -- White pants (calm_fITZ)
}
local SKIN = {
	Color3.fromRGB(255, 220, 185),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(160, 106, 72),
	Color3.fromRGB(105, 70, 50),
}

export type Outfit = {
	hair: number,
	face: number, -- face accessory
	shirt: number,
	pants: number,
	skin: Color3,
}

local function outfit(hair, face, shirt, pants, skin): Outfit
	return { hair = hair, face = face, shirt = shirt, pants = pants, skin = skin }
end

-- Guest outfits; guest id picks one (Visuals).
NpcRigs.OUTFITS = {
	outfit(HAIR.coolBoy, FACE.bigSmile, SHIRT.redFlannel, PANTS.blackJeansSneakers, SKIN[2]),
	outfit(HAIR.curlyPonytail, FACE.cuteBlush, SHIRT.tropical, PANTS.denimShorts, SKIN[1]),
	outfit(HAIR.blackAfro, FACE.bored, SHIRT.rainbowHoodie, PANTS.greyCargo, SKIN[5]),
	outfit(HAIR.wavyBlonde, FACE.kawaiiBlush, SHIRT.beigePlaid, PANTS.rippedJeans, SKIN[1]),
	outfit(HAIR.shortParted, FACE.sideEye, SHIRT.redJacket, PANTS.allBlack, SKIN[3]),
	outfit(HAIR.braidedPonytail, FACE.simpleBlush, SHIRT.simpleFlannel, PANTS.white, SKIN[4]),
	outfit(HAIR.fluffyMessy, FACE.blushSmile, SHIRT.blueFlannel, PANTS.greyCargo, SKIN[2]),
	outfit(HAIR.orangeAfro, FACE.grumpy, SHIRT.brownFlannel, PANTS.allBlack, SKIN[3]),
}

NpcRigs.SHOPKEEPER = outfit(HAIR.blackSwept, FACE.bigSmile, SHIRT.apron, PANTS.allBlack, SKIN[4])

-- Default R15 animations (Roblox).
local WALK_ANIM = "rbxassetid://507777826"
local IDLE_ANIM = "rbxassetid://507766388"

local function description(outfit: Outfit): HumanoidDescription
	local d = Instance.new("HumanoidDescription")
	d.HairAccessory = tostring(outfit.hair)
	d.FaceAccessory = tostring(outfit.face)
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
	-- The face accessory replaces the classic face decal.
	local head = model:FindFirstChild("Head")
	local decal = head and head:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
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
