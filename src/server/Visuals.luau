--!nonstrict
--[[
	Visuals: mirrors MotelCore state into the world.

	The core owns the truth; this module only follows it. Cars and guests
	are placeholder models moved every Heartbeat toward the next waypoint
	(no tweens or threads to clean up). When the core's runId changes the
	whole Runtime folder is cleared, so a restart never leaves NPCs behind.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiAssets"))
local NpcRigs = require(script.Parent:WaitForChild("NpcRigs"))

local Visuals = {}
Visuals.__index = Visuals

local SKIN = {
	Color3.fromRGB(255, 220, 185),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(196, 140, 100),
	Color3.fromRGB(140, 96, 66),
	Color3.fromRGB(98, 66, 48),
}
local SHIRTS = {
	Color3.fromRGB(220, 90, 80),
	Color3.fromRGB(80, 140, 220),
	Color3.fromRGB(240, 190, 70),
	Color3.fromRGB(120, 200, 120),
	Color3.fromRGB(180, 110, 200),
	Color3.fromRGB(240, 140, 60),
	Color3.fromRGB(70, 170, 170),
	Color3.fromRGB(245, 245, 240),
}
local PANTS = {
	Color3.fromRGB(50, 64, 110),
	Color3.fromRGB(60, 60, 66),
	Color3.fromRGB(150, 120, 90),
	Color3.fromRGB(90, 110, 70),
}
local HAIR = {
	Color3.fromRGB(50, 34, 24),
	Color3.fromRGB(110, 70, 40),
	Color3.fromRGB(230, 200, 120),
	Color3.fromRGB(30, 30, 34),
	Color3.fromRGB(180, 80, 50),
}
local CAR_COLORS = {
	Color3.fromRGB(236, 120, 110),
	Color3.fromRGB(120, 190, 220),
	Color3.fromRGB(240, 210, 120),
	Color3.fromRGB(150, 200, 140),
	Color3.fromRGB(200, 150, 220),
	Color3.fromRGB(240, 240, 235),
	Color3.fromRGB(90, 110, 150),
	Color3.fromRGB(230, 150, 90),
}

-- Root pivot heights and NPC scale; Visuals.new sets them from Config.mapScale.
local GUEST_Y = 2.2
local CAR_Y = 1.2
local NPC_SCALE = 1

local function scaleCF(cf: CFrame, k: number): CFrame
	return CFrame.new(cf.Position * k) * cf.Rotation
end

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
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

-- Deterministic pick from a palette by guest id and a salt.
local function pick(list, id: number, salt: number)
	return list[(id * 7 + salt * 13) % #list + 1]
end

-- Mood label above a guest: icon + outlined text, sized in studs.
local function makeMood(offsetY: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Mood"
	gui.Size = UDim2.fromScale(4.4, 0.9) -- studs: shrinks with distance
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 55
	gui.LightInfluence = 0
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Size = UDim2.fromScale(0.27, 1.25)
	icon.Position = UDim2.fromScale(0, 0.5)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Parent = gui
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(0.7, 1)
	tl.Position = UDim2.fromScale(0.3, 0)
	tl.TextXAlignment = Enum.TextXAlignment.Left
	tl.BackgroundTransparency = 1
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.TextScaled = true
	tl.Font = Enum.Font.FredokaOne
	tl.Text = ""
	tl.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(46, 32, 22)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = tl
	return gui, icon, tl
end

--[[
	Blocky guest rig (fallback while R15 rigs load). Returns:
	  { model, root, label, statics = { {part, offset} }, limbs = { {joint, swing, parts} }, phase }
	All parts are anchored; poseGuest() places them every frame from a root CFrame.
]]
local function makeGuest(id: number, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Guest" .. id
	local skin = pick(SKIN, id, 1)
	local shirt = pick(SHIRTS, id, 2)
	local pants = pick(PANTS, id, 3)
	local hair = pick(HAIR, id, 4)

	local root = newPart({ Name = "Body", Size = Vector3.new(2, 4.4, 1), Transparency = 1, Parent = model })
	model.PrimaryPart = root
	local statics = {}
	local function static(name, size, offset, color, extra)
		local props = { Name = name, Size = size, Color = color, Parent = model }
		for k, v in pairs(extra or {}) do
			props[k] = v
		end
		table.insert(statics, { part = newPart(props), offset = offset })
	end
	static("Torso", Vector3.new(2, 1.9, 1), CFrame.new(0, 0.95, 0), shirt)
	static("Belt", Vector3.new(2.05, 0.25, 1.05), CFrame.new(0, 0.1, 0), pants:Lerp(Color3.new(0, 0, 0), 0.4))
	static("Head", Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, 2.6, 0), skin)
	for _, x in ipairs({ -0.3, 0.3 }) do
		static("Eye", Vector3.new(0.18, 0.26, 0.05), CFrame.new(x, 2.7, -0.66), Color3.fromRGB(30, 26, 26))
	end
	static("Smile", Vector3.new(0.5, 0.08, 0.05), CFrame.new(0, 2.32, -0.66), Color3.fromRGB(120, 60, 60))
	local style = id % 3
	if style == 0 then
		local capColor = pick(SHIRTS, id, 5)
		static("Cap", Vector3.new(1.4, 0.45, 1.4), CFrame.new(0, 3.38, 0), capColor)
		static("Brim", Vector3.new(1.2, 0.15, 0.8), CFrame.new(0, 3.2, -0.95), capColor)
	elseif style == 1 then
		static("Hair", Vector3.new(1.42, 0.4, 1.42), CFrame.new(0, 3.35, 0.02), hair)
		static("HairBack", Vector3.new(1.42, 1, 0.3), CFrame.new(0, 2.85, 0.6), hair)
	else
		static("Beanie", Vector3.new(1.42, 0.65, 1.42), CFrame.new(0, 3.4, 0), pick(SHIRTS, id, 6))
		static("Pom", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 3.85, 0), Color3.fromRGB(250, 250, 250), {
			Shape = Enum.PartType.Ball,
		})
	end

	local limbs = {}
	local function limb(joint: CFrame, swing: number, parts)
		local entry = { joint = joint, swing = swing, parts = {} }
		for _, p in ipairs(parts) do
			table.insert(entry.parts, {
				part = newPart({ Name = p[1], Size = p[2], Color = p[4], Parent = model }),
				offset = p[3],
			})
		end
		table.insert(limbs, entry)
	end
	local shoe = Color3.fromRGB(40, 36, 34)
	limb(CFrame.new(-0.5, 0, 0), 1, {
		{ "LeftLeg", Vector3.new(0.9, 1.8, 0.9), CFrame.new(0, -0.9, 0), pants },
		{ "LeftShoe", Vector3.new(0.95, 0.35, 1.15), CFrame.new(0, -1.95, -0.1), shoe },
	})
	limb(CFrame.new(0.5, 0, 0), -1, {
		{ "RightLeg", Vector3.new(0.9, 1.8, 0.9), CFrame.new(0, -0.9, 0), pants },
		{ "RightShoe", Vector3.new(0.95, 0.35, 1.15), CFrame.new(0, -1.95, -0.1), shoe },
	})
	limb(CFrame.new(-1.35, 1.8, 0), -1, {
		{ "LeftArm", Vector3.new(0.7, 1.4, 0.8), CFrame.new(0, -0.6, 0), shirt },
		{ "LeftHand", Vector3.new(0.65, 0.5, 0.75), CFrame.new(0, -1.5, 0), skin },
	})
	local caseColor = pick(SHIRTS, id, 7):Lerp(Color3.fromRGB(90, 60, 40), 0.5)
	limb(CFrame.new(1.35, 1.8, 0), 0.25, {
		{ "RightArm", Vector3.new(0.7, 1.4, 0.8), CFrame.new(0, -0.6, 0), shirt },
		{ "RightHand", Vector3.new(0.65, 0.5, 0.75), CFrame.new(0, -1.5, 0), skin },
		{ "Suitcase", Vector3.new(0.5, 1.3, 1.8), CFrame.new(0.3, -2.3, 0), caseColor },
		{ "Handle", Vector3.new(0.2, 0.3, 0.6), CFrame.new(0.3, -1.55, 0), Color3.fromRGB(40, 36, 34) },
	})

	local gui, icon, tl = makeMood(4)
	gui.Parent = root
	if NPC_SCALE ~= 1 then
		local k = NPC_SCALE
		root.Size *= k
		gui.StudsOffset *= k
		for _, st in ipairs(statics) do
			st.part.Size *= k
			st.offset = scaleCF(st.offset, k)
		end
		for _, l in ipairs(limbs) do
			l.joint = scaleCF(l.joint, k)
			for _, lp in ipairs(l.parts) do
				lp.part.Size *= k
				lp.offset = scaleCF(lp.offset, k)
			end
		end
	end
	model.Parent = parent
	return { model = model, root = root, label = tl, icon = icon, statics = statics, limbs = limbs, phase = 0 }
end

-- R15 guest (NpcRigs) with a suitcase in the right hand. Returns the same
-- shape as makeGuest plus r15 = true, or nil while templates load.
local function makeR15Guest(id: number, parent: Instance)
	local model = NpcRigs.clone(id)
	if not model then
		return nil
	end
	model.Name = "Guest" .. id
	local root = model.PrimaryPart
	local k = NPC_SCALE
	local hand = model:FindFirstChild("RightHand")
	if hand then
		local case = newPart({
			Name = "Suitcase",
			Size = Vector3.new(0.45, 1.2, 1.7) * k,
			Color = pick(SHIRTS, id, 7):Lerp(Color3.fromRGB(90, 60, 40), 0.5),
			Anchored = false,
			Massless = true,
			Parent = model,
		})
		case.CFrame = hand.CFrame * CFrame.new(0.15 * k, -0.75 * k, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = case
		weld.Parent = case
	end
	local head = model:FindFirstChild("Head")
	local gui, icon, tl = makeMood(1.9)
	gui.StudsOffset *= k
	gui.Size = UDim2.fromScale(4.4 * k, 0.9 * k)
	gui.Parent = head or root
	model.Parent = parent
	return {
		model = model,
		root = root,
		label = tl,
		icon = icon,
		r15 = true,
		rootHeight = model:GetAttribute("RootHeight") or 2.9 * k,
	}
end

-- Places every rig part from the root CFrame; limbs swing while walking.
local function poseGuest(rig, rootCF: CFrame, moving: boolean, dt: number)
	if rig.r15 then
		-- rootCF is at the blocky rig's root height; put the R15 soles on the
		-- floor (floors and paths sit ~0.35 studs above that rig's soles).
		local floorY = rootCF.Position.Y - 2.2 * NPC_SCALE + 0.35
		rig.root.CFrame = rootCF + Vector3.new(0, floorY + rig.rootHeight - rootCF.Position.Y, 0)
		NpcRigs.setMoving(rig.model, moving, rig.walkRate)
		return
	end
	if moving then
		rig.phase += dt * 9
	else
		rig.phase = 0
	end
	local swing = if moving then math.sin(rig.phase) * 0.7 else 0
	local bob = if moving then math.abs(math.sin(rig.phase)) * 0.15 else 0
	local base = rootCF * CFrame.new(0, bob, 0)
	rig.root.CFrame = rootCF
	for _, s in ipairs(rig.statics) do
		s.part.CFrame = base * s.offset
	end
	for _, l in ipairs(rig.limbs) do
		local j = base * l.joint * CFrame.Angles(swing * l.swing, 0, 0)
		for _, p in ipairs(l.parts) do
			p.part.CFrame = j * p.offset
		end
	end
end

local function makeCar(id: number, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Car" .. id
	local color = CAR_COLORS[(id * 5) % #CAR_COLORS + 1]
	local wagon = id % 3 == 1
	local function part(name, size, offset, c, extra)
		local props = { Name = name, Size = size, CFrame = CFrame.new(0, CAR_Y, 0) * offset, Color = c, Parent = model }
		for k, v in pairs(extra or {}) do
			props[k] = v
		end
		return newPart(props)
	end
	local body = part("Body", Vector3.new(4.6, 1.3, 9), CFrame.new(), color)
	model.PrimaryPart = body
	local cabinLen = if wagon then 6 else 4.8
	local cabinZ = if wagon then 1.4 else 0.8
	part("Cabin", Vector3.new(4.2, 1.5, cabinLen), CFrame.new(0, 1.35, cabinZ), color)
	part(
		"Roof",
		Vector3.new(4.3, 0.25, cabinLen + 0.2),
		CFrame.new(0, 2.2, cabinZ),
		color:Lerp(Color3.new(1, 1, 1), 0.25)
	)
	local glass = { Material = Enum.Material.Glass, Transparency = 0.15 }
	local glassColor = Color3.fromRGB(40, 54, 76)
	part(
		"Windshield",
		Vector3.new(3.8, 1.1, 0.15),
		CFrame.new(0, 1.35, cabinZ - cabinLen / 2 - 0.05),
		glassColor,
		glass
	)
	part(
		"RearWindow",
		Vector3.new(3.8, 1.1, 0.15),
		CFrame.new(0, 1.35, cabinZ + cabinLen / 2 + 0.05),
		glassColor,
		glass
	)
	for _, x in ipairs({ -2.13, 2.13 }) do
		part("SideWindow", Vector3.new(0.12, 1, cabinLen - 0.6), CFrame.new(x, 1.35, cabinZ), glassColor, glass)
		part("Stripe", Vector3.new(0.1, 0.3, 8.6), CFrame.new(x * 1.08, 0.1, 0), color:Lerp(Color3.new(1, 1, 1), 0.6))
	end
	local cyl = { Shape = Enum.PartType.Cylinder }
	for _, x in ipairs({ -2.2, 2.2 }) do
		for _, z in ipairs({ -2.9, 2.9 }) do
			part("Wheel", Vector3.new(0.8, 1.9, 1.9), CFrame.new(x, -0.25, z), Color3.fromRGB(28, 28, 30), cyl)
			part("Hub", Vector3.new(0.85, 0.9, 0.9), CFrame.new(x, -0.25, z), Color3.fromRGB(200, 200, 206), cyl)
		end
	end
	for _, z in ipairs({ -4.6, 4.6 }) do
		part("Bumper", Vector3.new(4.8, 0.35, 0.4), CFrame.new(0, -0.45, z), Color3.fromRGB(180, 180, 186))
	end
	local neon = { Material = Enum.Material.Neon }
	for _, x in ipairs({ -1.5, 1.5 }) do
		local head = part(
			"Headlight",
			Vector3.new(0.9, 0.5, 0.15),
			CFrame.new(x, 0.15, -4.55),
			Color3.fromRGB(255, 244, 210),
			neon
		)
		if x < 0 then
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Front
			spot.Range = 26
			spot.Angle = 70
			spot.Brightness = 2
			spot.Color = Color3.fromRGB(255, 240, 210)
			spot.Parent = head
		end
		part(
			"Taillight",
			Vector3.new(0.9, 0.4, 0.15),
			CFrame.new(x * 1.05, 0.2, 4.55),
			Color3.fromRGB(255, 60, 60),
			neon
		)
	end
	part("Grille", Vector3.new(1.8, 0.4, 0.12), CFrame.new(0, 0.1, -4.55), Color3.fromRGB(60, 60, 66))
	if NPC_SCALE ~= 1 then
		local pivot = CFrame.new(0, CAR_Y, 0)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local rel = pivot:ToObjectSpace(d.CFrame)
				d.Size *= NPC_SCALE
				d.CFrame = pivot * scaleCF(rel, NPC_SCALE)
			elseif d:IsA("SpotLight") then
				d.Range = math.min(60, d.Range * NPC_SCALE)
			end
		end
	end
	model.Parent = parent
	return model
end

-- Advances a CFrame toward path[1] at `speed`, popping reached waypoints.
-- Returns the new CFrame and whether it moved.
local function advance(cf: CFrame, path, speed: number, dt: number, y: number): (CFrame, boolean)
	local remaining = speed * dt
	local pos = cf.Position
	local start = pos
	while remaining > 0 and #path > 0 do
		local target = Vector3.new(path[1].X, y, path[1].Z)
		local delta = target - pos
		local dist = delta.Magnitude
		if dist <= remaining then
			pos = target
			remaining -= dist
			table.remove(path, 1)
		else
			pos += delta.Unit * remaining
			remaining = 0
		end
	end
	local moved = (pos - start).Magnitude > 1e-3
	local look = if #path > 0 then Vector3.new(path[1].X, y, path[1].Z) - pos else nil
	if look and look.Magnitude > 0.05 then
		return CFrame.lookAt(pos, pos + look), moved
	end
	return CFrame.new(pos) * cf.Rotation, moved
end

function Visuals.new(layout, config, constants, timeScale: number)
	local self = setmetatable({}, Visuals)
	-- NPCs scale with the map so guests match doors/furniture and cars match
	-- the parking slots. Pivot heights keep feet/wheels on the scaled floors.
	local k = config.mapScale or 1
	NPC_SCALE = k
	GUEST_Y = 2.2 * k + 0.2 * (k - 1)
	CAR_Y = 1.2 * k + 0.2 * (k - 1)
	self.layout = layout
	self.config = config
	self.C = constants
	self.timeScale = timeScale
	self.entries = {}
	self.runId = nil
	self.labelTimer = 0
	self.lightingKey = nil
	NpcRigs.preload(k)
	self:dressShopkeeper()
	return self
end

-- Swaps the blocky shopkeeper from MapDecor for an R15 one (background).
function Visuals:dressShopkeeper()
	local old = self.layout.root and self.layout.root:FindFirstChild("Shopkeeper", true)
	if not old then
		return
	end
	task.spawn(function()
		local rig = NpcRigs.build(NpcRigs.SHOPKEEPER, NPC_SCALE)
		if not rig or not old.Parent then
			return
		end
		local cf, size = old:GetBoundingBox()
		local floor = cf.Position - Vector3.new(0, size.Y / 2, 0)
		local pos = floor + Vector3.new(0, rig:GetAttribute("RootHeight"), 0)
		rig.Name = "Shopkeeper"
		rig.PrimaryPart.CFrame = CFrame.lookAt(pos, pos - Vector3.xAxis) -- faces the counter (west)
		rig.Parent = old.Parent
		old:Destroy()
		NpcRigs.setMoving(rig, false)
		task.wait(0.5)
		local sole = NpcRigs.soleY(rig)
		if sole then
			rig.PrimaryPart.CFrame += Vector3.new(0, floor.Y - sole, 0)
		end
	end)
end

function Visuals:clearAll()
	for _, e in pairs(self.entries) do
		self:destroyEntry(e)
	end
	self.entries = {}
	self.layout.runtime:ClearAllChildren()
end

function Visuals:destroyEntry(e)
	if e.guest then
		e.guest:Destroy()
	end
	if e.car then
		e.car:Destroy()
	end
end

function Visuals:slotPosition(index: number): Vector3
	local slots = self.layout.parkingSlots
	if index <= #slots then
		return slots[index]
	end
	-- Overflow parking further down the lot.
	local base = slots[1]
	return Vector3.new(base.X - 8 * (index - #slots), base.Y, base.Z)
end

function Visuals:freeSlot(): number
	local used = {}
	for _, e in pairs(self.entries) do
		used[e.slot] = true
	end
	local i = 1
	while used[i] do
		i += 1
	end
	return i
end

function Visuals:createEntry(g)
	local slot = self:freeSlot()
	local sp = self:slotPosition(slot)
	local car = makeCar(g.id, self.layout.runtime)
	car:PivotTo(CFrame.new(self.layout.roadIn.X, CAR_Y, self.layout.roadInZ))
	local e = {
		id = g.id,
		slot = slot,
		slotPos = sp,
		car = car,
		carPath = { Vector3.new(sp.X, CAR_Y, self.layout.roadInZ), sp },
		guest = nil,
		label = nil,
		guestPath = {},
		state = nil,
		queueIndex = nil,
		leaving = false,
		carLeaving = false,
	}
	self.entries[g.id] = e
	return e
end

function Visuals:sendCarAway(e)
	e.carLeaving = true
	e.carPath = {
		Vector3.new(e.slotPos.X, CAR_Y, self.layout.roadOutZ),
		self.layout.roadOut,
	}
end

function Visuals:queueSlot(index: number): Vector3
	local slots = self.layout.queueSlots
	return slots[math.clamp(index, 1, #slots)]
end

function Visuals:updateTargets(core, g, e)
	local GS = self.C.GuestState
	local layout = self.layout

	if not e.guest then
		if #e.carPath > 0 or e.carLeaving then
			return
		end
		if g.state == GS.Departed then
			self:sendCarAway(e)
			return
		end
		local rig = makeR15Guest(g.id, layout.runtime) or makeGuest(g.id, layout.runtime)
		rig.walkRate = self.config.npc.walkSpeed / self.timeScale / (16 * NPC_SCALE)
		e.rig = rig
		e.guest = rig.model
		e.label = rig.label
		e.labelIcon = rig.icon
		e.guestCF = CFrame.new(e.slotPos.X + 3, GUEST_Y, e.slotPos.Z)
		poseGuest(rig, e.guestCF, false, 0)
	end

	local qi = core:queuePosition(g.id)
	if g.state ~= e.state or (g.state == GS.Queued and qi ~= e.queueIndex) then
		local prev = e.state
		e.state = g.state
		e.queueIndex = qi
		if g.state == GS.Arriving then
			e.guestPath = { layout.entrance, self:queueSlot(#core.queue + 1) }
		elseif g.state == GS.Queued then
			local target = self:queueSlot(qi or 1)
			if prev == GS.Arriving and #e.guestPath > 0 then
				e.guestPath[#e.guestPath] = target
			else
				e.guestPath = { target }
			end
		elseif g.state == GS.Staying then
			local room = layout.rooms[g.roomId]
			e.guestPath = { layout.deskSide, layout.hallMain, room.hall, room.doorPoint, room.inside }
		elseif g.state == GS.Departed then
			e.leaving = true
			local room = layout.rooms[g.roomId or 0]
			if g.previousState == GS.Staying and room then
				e.guestPath = {
					room.doorPoint,
					room.hall,
					layout.hallMain,
					layout.deskSide,
					layout.entrance,
					e.slotPos,
				}
			else
				e.guestPath = { layout.entrance, e.slotPos }
			end
		end
	end

	if e.leaving and #e.guestPath == 0 and not e.carLeaving then
		e.guest:Destroy()
		e.guest = nil
		e.rig = nil
		e.label = nil
		e.labelIcon = nil
		self:sendCarAway(e)
	end
end

function Visuals:updateLabel(core, g, e, now: number)
	if not e.label then
		return
	end
	local GS = self.C.GuestState
	local text, color, iconName = "", Color3.new(1, 1, 1), "hourglass"
	if g.state == GS.Queued then
		local total = self.config.guests.patience * self.timeScale
		local left = math.max(0, g.patienceEndsAt - now)
		local frac = left / total
		local prefix = if e.queueIndex == 1 then "NEXT " else ""
		text = ("%s%ds"):format(prefix, math.ceil(left))
		if frac > 0.5 then
			color = Color3.fromRGB(120, 240, 140)
		elseif frac > 0.25 then
			color = Color3.fromRGB(255, 210, 80)
		else
			color = Color3.fromRGB(255, 110, 100)
		end
	elseif g.state == GS.Staying then
		local room = core.rooms[g.roomId]
		if room and room.towelRequest then
			text, color, iconName = "Towel please!", Color3.fromRGB(255, 210, 80), "towel"
		else
			text, iconName = "Room " .. tostring(g.roomId), "moon"
		end
	elseif g.state == GS.Departed then
		local reason = g.departReason
		if reason == "Walkout" then
			text, color, iconName = "Too slow!", Color3.fromRGB(255, 110, 100), "lightning"
		elseif reason == "Unserved" then
			text, color, iconName = "Closed?!", Color3.fromRGB(255, 160, 90), "moon"
		else
			text, color, iconName = "Thanks!", Color3.fromRGB(120, 240, 140), "check"
		end
	end
	e.label.Text = text
	e.label.TextColor3 = color
	e.label.Visible = text ~= ""
	if e.labelIcon then
		if e.labelIconName ~= iconName then
			e.labelIconName = iconName
			UiAssets.applyTo(e.labelIcon, iconName)
		end
		e.labelIcon.Visible = text ~= ""
	end
end

function Visuals:sync(core, now: number, dt: number)
	if core.runId ~= self.runId then
		self:clearAll()
		self.runId = core.runId
	end

	for id, g in pairs(core.guests) do
		local e = self.entries[id] or self:createEntry(g)
		self:updateTargets(core, g, e)
	end
	for id, e in pairs(self.entries) do
		if not core.guests[id] then
			self:destroyEntry(e)
			self.entries[id] = nil
		end
	end

	local walk = self.config.npc.walkSpeed / self.timeScale
	local drive = self.config.npc.carSpeed / self.timeScale
	for _, e in pairs(self.entries) do
		if e.car and #e.carPath > 0 then
			e.car:PivotTo((advance(e.car:GetPivot(), e.carPath, drive, dt, CAR_Y)))
		end
		if e.rig then
			local moving = false
			if #e.guestPath > 0 then
				e.guestCF, moving = advance(e.guestCF, e.guestPath, walk, dt, GUEST_Y)
			end
			-- Pose while walking, plus one frame to settle back to idle.
			if moving or e.wasMoving then
				poseGuest(e.rig, e.guestCF, moving, dt)
			end
			e.wasMoving = moving
		end
	end

	self.labelTimer -= dt
	if self.labelTimer <= 0 then
		self.labelTimer = 0.25
		for id, e in pairs(self.entries) do
			local g = core.guests[id]
			if g then
				self:updateLabel(core, g, e, now)
			end
		end
	end
end

------------------------------------------------------------------------
-- World state (signs, prompts, lights, weather)
------------------------------------------------------------------------

-- Text colours for world labels (outlined text, no background).
local GREEN = Color3.fromRGB(120, 240, 140)
local BLUE = Color3.fromRGB(140, 200, 255)
local AMBER = Color3.fromRGB(255, 210, 80)
local RED = Color3.fromRGB(255, 110, 100)

function Visuals:refreshWorld(core)
	local P = self.C.Phase
	local layout = self.layout
	local active = core.phase == P.Preparation or core.phase == P.Night or core.phase == P.Closing

	for i, room in ipairs(core.rooms) do
		local v = layout.rooms[i]
		local blockers = core:roomBlockers(room)
		local signIcon
		if core:isRoomReady(room) then
			v.sign.Text = ("Room %d  READY"):format(i)
			v.sign.TextColor3 = GREEN
			signIcon = "check"
		elseif room.occupant then
			local extra = if room.towelRequest then "  TOWEL!" else ""
			v.sign.Text = ("Room %d  OCCUPIED%s"):format(i, extra)
			v.sign.TextColor3 = if room.towelRequest then AMBER else BLUE
			signIcon = if room.towelRequest then "towel" else "moon"
		else
			v.sign.Text = ("Room %d: %s"):format(i, table.concat(blockers, ", "))
			v.sign.TextColor3 = if room.acBroken then RED else AMBER
			signIcon = if room.acBroken then "wrench" else "trash"
		end
		local signIconLabel = v.sign.Parent and v.sign.Parent:FindFirstChild("Icon")
		if signIconLabel then
			UiAssets.applyTo(signIconLabel, signIcon)
		end
		v.bed.Color = if room.sheetsDirty then Color3.fromRGB(150, 120, 80) else Color3.fromRGB(245, 245, 245)
		v.trashBag.Transparency = if room.trash then 0 else 1
		v.ac.Color = if room.acBroken then Color3.fromRGB(200, 60, 50) else Color3.fromRGB(210, 215, 220)
		local smoke = v.ac:FindFirstChild("Smoke")
		if room.acBroken and not smoke then
			smoke = Instance.new("Smoke")
			smoke.Name = "Smoke"
			smoke.Color = Color3.fromRGB(80, 80, 80)
			smoke.Size = 1
			smoke.RiseVelocity = 2
			smoke.Parent = v.ac
		elseif not room.acBroken and smoke then
			smoke:Destroy()
		end
		v.door.Color = if room.towelRequest then Color3.fromRGB(255, 200, 60) else Color3.fromRGB(90, 70, 50)
		v.door.Material = if room.towelRequest then Enum.Material.Neon else Enum.Material.SmoothPlastic

		v.prompts.changeSheets.Enabled = active and room.sheetsDirty and room.occupant == nil
		v.prompts.collectTrash.Enabled = active and room.trash
		v.prompts.deliverTowel.Enabled = active and room.towelRequest
		v.prompts.repairAC.Enabled = active and room.acBroken
	end

	layout.prompts.desk.Enabled = core.phase == P.Night or core.phase == P.Closing
	layout.prompts.breaker.Enabled = active and not core.power
	layout.prompts.shop.Enabled = active
	layout.prompts.linen.Enabled = active
	layout.prompts.dumpTrash.Enabled = active

	layout.breakerLabel.Text = if core.power then "BREAKER: OK" else "BREAKER: RESET!"
	layout.breakerLabel.TextColor3 = if core.power then Color3.new(1, 1, 1) else RED
	layout.linenLabel.Text = ("LINEN  Sheets %d | Towels %d"):format(core.stock.Sheet, core.stock.Towel)

	for _, l in ipairs(layout.powerLights) do
		l.light.Enabled = core.power
		l.part.Material = if core.power then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	layout.rain.Rate = if core.rain then 700 else 0
	-- Client Ambience reads this to dim neon bulbs during an outage.
	layout.root:SetAttribute("Powered", core.power)

	-- Retro sign: VACANCY while any room is ready, NO VACANCY otherwise.
	local vacancy = layout.vacancyLabel
	if vacancy then
		local anyReady = false
		for _, room in ipairs(core.rooms) do
			if core:isRoomReady(room) then
				anyReady = true
				break
			end
		end
		vacancy.Text = if anyReady then "VACANCY" else "NO VACANCY"
		vacancy.TextColor3 = if anyReady then Color3.fromRGB(110, 255, 150) else Color3.fromRGB(255, 90, 90)
		vacancy.TextTransparency = if core.power then 0 else 0.85
	end

	self:applyLighting(core)
end

function Visuals:applyLighting(core)
	local key = ("%s|%s|%s"):format(core.phase, tostring(core.power), tostring(core.rain))
	if key == self.lightingKey then
		return
	end
	self.lightingKey = key
	local P = self.C.Phase
	local nightLike = core.phase == P.Night or core.phase == P.Closing
	if core.phase == P.Preparation then
		Lighting.ClockTime = 17.6
		Lighting.Brightness = 2
		Lighting.Ambient = Color3.fromRGB(110, 100, 90)
		Lighting.OutdoorAmbient = Color3.fromRGB(140, 130, 120)
	elseif nightLike then
		Lighting.ClockTime = if core.phase == P.Night then 0.5 else 3
		Lighting.Brightness = 1
		if core.power then
			Lighting.Ambient = Color3.fromRGB(80, 80, 105)
			Lighting.OutdoorAmbient = Color3.fromRGB(95, 95, 125)
		else
			Lighting.Ambient = Color3.fromRGB(45, 45, 65)
			Lighting.OutdoorAmbient = Color3.fromRGB(60, 60, 85)
		end
	elseif core.phase == P.Report then
		Lighting.ClockTime = 5.8
		Lighting.Brightness = 1.5
		Lighting.Ambient = Color3.fromRGB(100, 95, 110)
		Lighting.OutdoorAmbient = Color3.fromRGB(120, 115, 130)
	else
		Lighting.ClockTime = 14
		Lighting.Brightness = 2
		Lighting.Ambient = Color3.fromRGB(120, 120, 120)
		Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 140)
	end
	if core.rain then
		Lighting.FogColor = Color3.fromRGB(60, 65, 80)
		Lighting.FogEnd = 260
	else
		Lighting.FogEnd = 100000
	end
end

return Visuals
