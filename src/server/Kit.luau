--!nonstrict
--[[
	Kit: the Blender motel kit (assets/models/kit, tools/blender/motel_kit.py)
	as MeshParts in the game.

	Templates come from ServerStorage.MotelKit (the imported FBX meshes, saved
	in the place). When a template is missing (e.g. a fresh `rojo build`), it
	is created from its mesh id with AssetService:CreateMeshPartAsync. If a
	mesh cannot be loaded, Kit.has() is false for its group and the builders
	keep the old part-based look, so the map always works.

	Frames: KitManifest gives each mesh's bbox centre `c` in its group's local
	frame (Roblox axes, origin = the group's pivot on the floor, front = -Z).
	The FBX importer turns every mesh 180 degrees around Y, so placed meshes
	get FLIP on top of their centre offset.

	Gameplay skins: Kit.skin() hangs meshes under a gameplay part (folder
	"Skin") and hides the part; Kit.set() forwards state colours from Visuals
	to the meshes marked Follow (e.g. sheet clean/dirty, AC broken).
]]

local AssetService = game:GetService("AssetService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local Manifest = require(script.Parent:WaitForChild("KitManifest"))

local Kit = {}

local FLIP = CFrame.Angles(0, math.pi, 0)
local WHITE = Color3.new(1, 1, 1)
local BASE = Color3.fromRGB(232, 232, 232)

local templates: { [string]: MeshPart } = {}
local groups: { [string]: { string } } = {}
for name, m in pairs(Manifest) do
	groups[m.group] = groups[m.group] or {}
	table.insert(groups[m.group], name)
end
for _, list in pairs(groups) do
	table.sort(list)
end

local loaded = false

function Kit.enabled(): boolean
	return Config.useMeshKit ~= false
end

-- Collects the templates (yields while creating missing ones, max ~20 s).
function Kit.load()
	if loaded or not Kit.enabled() then
		return
	end
	loaded = true
	local folder = ServerStorage:FindFirstChild("MotelKit")
	local pending = 0
	for name, m in pairs(Manifest) do
		local t = folder and folder:FindFirstChild(name)
		if t and t:IsA("MeshPart") then
			templates[name] = t
		elseif m.id then -- (meshes not imported yet have no id: group stays unavailable)
			pending += 1
			task.spawn(function()
				local ok, result = pcall(function()
					return AssetService:CreateMeshPartAsync(m.id, {
						CollisionFidelity = Enum.CollisionFidelity.Box,
						RenderFidelity = Enum.RenderFidelity.Automatic,
					})
				end)
				if ok and result then
					result.Name = name
					templates[name] = result
				else
					warn("[Kit] could not load mesh " .. name .. ": " .. tostring(result))
				end
				pending -= 1
			end)
		end
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 20 do
		task.wait()
	end
end

function Kit.has(group: string): boolean
	if not Kit.enabled() then
		return false
	end
	local list = groups[group]
	if not list then
		return false
	end
	for _, name in ipairs(list) do
		if not templates[name] then
			return false
		end
	end
	return true
end

--[[
	Places the meshes of `group` with the group pivot at `pivot`.
	opts:
	  only         { [meshName] = true }  place just these meshes
	  tint         { [meshName] = Color3 } colour for TINT meshes (default white)
	  scale        number                  uniform scale about the pivot
	  scaleX       number                  extra stretch along the group's X
	  transparency { [meshName] = number }
	Returns { [meshName] = MeshPart } or nil when the group is unavailable.
]]
function Kit.place(group: string, parent: Instance, pivot: CFrame, opts)
	if not Kit.has(group) then
		return nil
	end
	opts = opts or {}
	local k = opts.scale or 1
	local sx = opts.scaleX or 1 -- stretch along the group's X (fence sections)
	local out = {}
	for _, name in ipairs(groups[group]) do
		if opts.only == nil or opts.only[name] then
			local m = Manifest[name]
			local p = templates[name]:Clone()
			p.Name = name
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			if k ~= 1 or sx ~= 1 then
				p.Size = Vector3.new(p.Size.X * k * sx, p.Size.Y * k, p.Size.Z * k)
			end
			p.CFrame = pivot * CFrame.new(m.c[1] * k * sx, m.c[2] * k, m.c[3] * k) * FLIP
			-- Plain meshes sit just under white so the brightest painted
			-- highlights (cream trim) do not cross the bloom threshold at night.
			p.Color = (opts.tint and opts.tint[name]) or (if m.glow then WHITE else BASE)
			if m.glow then
				p.Material = Enum.Material.Neon
				p:SetAttribute("Bulb", true)
			elseif m.glass then
				p.Material = Enum.Material.Glass
				p.Transparency = 0.35
				p.CastShadow = false
			else
				p.Material = Enum.Material.SmoothPlastic
			end
			if opts.transparency and opts.transparency[name] then
				p.Transparency = opts.transparency[name]
				p.CastShadow = false
			end
			p.Parent = parent
			out[name] = p
		end
	end
	return out
end

--[[
	Hinged door (manifest groups with `hinge` / `swing`): a Model named after
	the group whose PrimaryPart "Hinge" (invisible, anchored) sits on the
	hinge line, with the leaf meshes as children. Rotating the model about
	its pivot opens the door: in Studio rotate the Model, in game the client
	DoorFX swings it (attributes KitDoor and Swing = degrees about +Y).
	buildingPivot is the pivot of the building the door belongs to.
]]
function Kit.door(group: string, parent: Instance, buildingPivot: CFrame)
	if not Kit.has(group) then
		return nil
	end
	local first = Manifest[groups[group][1]]
	local h = first.hinge
	local hingeCF = buildingPivot * CFrame.new(h[1], h[2], h[3])
	local model = Instance.new("Model")
	model.Name = group
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local hinge = Instance.new("Part")
	hinge.Name = "Hinge"
	hinge.Size = Vector3.new(0.3, 0.3, 0.3)
	hinge.Transparency = 1
	hinge.Anchored = true
	hinge.CanCollide = false
	hinge.CanQuery = false
	hinge.CanTouch = false
	hinge.CFrame = hingeCF
	hinge.Parent = model
	model.PrimaryPart = hinge
	Kit.place(group, model, hingeCF)
	model:SetAttribute("KitDoor", true)
	model:SetAttribute("Swing", first.swing or 90)
	model.Parent = parent
	return model
end

-- Pivot that puts the group's bbox bottom-centre at `cf` (for parts whose
-- footprint we know but whose mesh origin may differ).
function Kit.bottomPivot(group: string, cf: CFrame): CFrame
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, name in ipairs(groups[group] or {}) do
		local m = Manifest[name]
		local c = Vector3.new(m.c[1], m.c[2], m.c[3])
		local h = Vector3.new(m.s[1], m.s[2], m.s[3]) / 2
		lo = lo:Min(c - h)
		hi = hi:Max(c + h)
	end
	return cf * CFrame.new(-(lo.X + hi.X) / 2, -lo.Y, -(lo.Z + hi.Z) / 2)
end

local EFFECTS =
	{ "Light", "Fire", "Smoke", "ParticleEmitter", "Sparkles", "SurfaceGui", "BillboardGui", "ProximityPrompt" }

local function hasEffects(part: Instance): boolean
	for _, c in ipairs(part:GetChildren()) do
		for _, class in ipairs(EFFECTS) do
			if c:IsA(class) then
				return true
			end
		end
	end
	return false
end

--[[
	Retires an old part-built piece that a mesh now replaces:
	  * parts that collide or carry lights / fire / smoke / particles / text
	    stay, invisible (Retired = true; colliding ones Occluder = true so
	    WorldLabels still treats them as walls);
	  * plain visual details are destroyed.
	force = "destroy" removes it whatever it carries (old sign boards whose
	text the mesh now shows in 3D letters).
]]
function Kit.retire(inst: Instance, force: string?)
	if inst:IsA("Model") or inst:IsA("Folder") then
		for _, d in ipairs(inst:GetChildren()) do
			Kit.retire(d, force)
		end
		if #inst:GetChildren() == 0 then
			inst:Destroy()
		end
		return
	end
	if not inst:IsA("BasePart") then
		return
	end
	if force ~= "destroy" and (inst.CanCollide or hasEffects(inst)) then
		inst.Transparency = 1
		inst.CastShadow = false
		inst:SetAttribute("Retired", true)
		inst:SetAttribute("Bulb", nil)
		inst:SetAttribute("Chase", nil)
		inst:SetAttribute("Blink", nil)
		if inst.CanCollide then
			inst:SetAttribute("Occluder", true)
		end
		for _, c in ipairs(inst:GetChildren()) do
			if c:IsA("Decal") or c:IsA("Texture") then
				c:Destroy()
			end
		end
	else
		inst:Destroy()
	end
end

--[[
	Retires direct children of `folder` whose names match one of `patterns`
	(Lua patterns, anchored). destroyPatterns are removed outright.
]]
function Kit.retireNamed(folder: Instance, patterns: { string }, destroyPatterns: { string }?)
	local function matches(name, list)
		for _, p in ipairs(list or {}) do
			if name:match("^" .. p .. "$") then
				return true
			end
		end
		return false
	end
	for _, c in ipairs(folder:GetChildren()) do
		if matches(c.Name, destroyPatterns) then
			Kit.retire(c, "destroy")
		elseif matches(c.Name, patterns) then
			Kit.retire(c)
		end
	end
end

--[[
	Skins a gameplay part: places the group's meshes under part.Skin, hides
	the part (prompts, labels and collisions stay). follow = { [meshName] =
	true } marks meshes that take the part's state colour / material.
	Returns the meshes or nil (part left as it was).
]]
function Kit.skin(part: BasePart, group: string, pivot: CFrame, opts)
	if not Kit.has(group) then
		return nil
	end
	local folder = part:FindFirstChild("Skin") or Instance.new("Folder")
	folder.Name = "Skin"
	folder.Parent = part
	local meshes = Kit.place(group, folder, pivot, opts)
	for name, mesh in pairs(meshes) do
		if opts and opts.follow and opts.follow[name] then
			mesh:SetAttribute("Follow", true)
			mesh.Color = part.Color
		end
	end
	part.Transparency = 1
	part.CastShadow = false
	part:SetAttribute("Skinned", true)
	return meshes
end

--[[
	State visuals for gameplay parts (used by Visuals). On a skinned part:
	  Transparency  goes to every skin mesh (the part stays hidden);
	  Color         goes to Follow meshes;
	  Material      goes to Follow meshes (Neon / plastic only).
	On a plain part it is set directly.
]]
function Kit.set(part: BasePart, prop: string, value)
	local skin = part:GetAttribute("Skinned") and part:FindFirstChild("Skin")
	if not skin then
		part[prop] = value
		return
	end
	for _, mesh in ipairs(skin:GetChildren()) do
		if mesh:IsA("BasePart") then
			if prop == "Transparency" then
				mesh.Transparency = value
			elseif mesh:GetAttribute("Follow") then
				if prop == "Material" then
					mesh.Material = if value == Enum.Material.Neon then value else Enum.Material.SmoothPlastic
				else
					mesh[prop] = value
				end
			end
		end
	end
end

return Kit
