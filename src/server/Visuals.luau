--!nonstrict
--[[
	Visuals: mirrors MotelCore state into the world.

	The core owns the truth; this module only follows it. Cars and guests
	are placeholder models moved every Heartbeat toward the next waypoint
	(no tweens or threads to clean up). When the core's runId changes the
	whole Runtime folder is cleared, so a restart never leaves NPCs behind.
]]

local Lighting = game:GetService("Lighting")

local Visuals = {}
Visuals.__index = Visuals

local GUEST_COLORS = {
	Color3.fromRGB(220, 90, 80),
	Color3.fromRGB(80, 140, 220),
	Color3.fromRGB(240, 190, 70),
	Color3.fromRGB(120, 200, 120),
	Color3.fromRGB(180, 110, 200),
	Color3.fromRGB(240, 140, 60),
}
local CAR_COLORS = {
	Color3.fromRGB(200, 40, 40),
	Color3.fromRGB(40, 90, 180),
	Color3.fromRGB(230, 230, 230),
	Color3.fromRGB(30, 30, 30),
	Color3.fromRGB(60, 150, 90),
}

local GUEST_Y = 2.2
local CAR_Y = 1.2

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

local function makeGuest(id: number, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Guest" .. id
	local color = GUEST_COLORS[(id - 1) % #GUEST_COLORS + 1]
	local body = newPart({
		Name = "Body",
		Size = Vector3.new(2, 3, 1.2),
		CFrame = CFrame.new(0, GUEST_Y, 0),
		Color = color,
		Parent = model,
	})
	newPart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.5, 1.5, 1.5),
		CFrame = CFrame.new(0, GUEST_Y + 2.2, 0),
		Color = Color3.fromRGB(255, 220, 185),
		Parent = model,
	})
	newPart({
		Name = "Suitcase",
		Size = Vector3.new(0.6, 1.2, 1.6),
		CFrame = CFrame.new(1.4, GUEST_Y - 0.8, 0),
		Color = Color3.fromRGB(90, 60, 40),
		Parent = model,
	})
	model.PrimaryPart = body

	local gui = Instance.new("BillboardGui")
	gui.Name = "Mood"
	gui.Size = UDim2.fromOffset(110, 30)
	gui.StudsOffset = Vector3.new(0, 4.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 0.3
	tl.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBold
	tl.Text = ""
	tl.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = tl
	gui.Parent = body
	model.Parent = parent
	return model, tl
end

local function makeCar(id: number, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Car" .. id
	local color = CAR_COLORS[(id - 1) % #CAR_COLORS + 1]
	local body = newPart({
		Name = "Body",
		Size = Vector3.new(4.4, 1.6, 8),
		CFrame = CFrame.new(0, CAR_Y, 0),
		Color = color,
		Parent = model,
	})
	newPart({
		Name = "Cabin",
		Size = Vector3.new(4, 1.4, 4),
		CFrame = CFrame.new(0, CAR_Y + 1.5, 0.5),
		Color = Color3.fromRGB(170, 210, 230),
		Transparency = 0.2,
		Parent = model,
	})
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

-- Moves a model toward path[1] at `speed`, popping reached waypoints.
local function step(model: Model, path, speed: number, dt: number, y: number)
	local remaining = speed * dt
	local pos = model:GetPivot().Position
	while remaining > 0 and #path > 0 do
		local target = Vector3.new(path[1].X, y, path[1].Z)
		local delta = target - pos
		local dist = delta.Magnitude
		if dist <= remaining then
			pos = target
			remaining -= dist
			table.remove(path, 1)
		else
			local dir = delta.Unit
			pos += dir * remaining
			remaining = 0
		end
	end
	local look = if #path > 0 then Vector3.new(path[1].X, y, path[1].Z) - pos else nil
	if look and look.Magnitude > 0.05 then
		model:PivotTo(CFrame.lookAt(pos, pos + look))
	else
		model:PivotTo(CFrame.new(pos) * model:GetPivot().Rotation)
	end
end

function Visuals.new(layout, config, constants, timeScale: number)
	local self = setmetatable({}, Visuals)
	self.layout = layout
	self.config = config
	self.C = constants
	self.timeScale = timeScale
	self.entries = {}
	self.runId = nil
	self.labelTimer = 0
	self.lightingKey = nil
	return self
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
		e.guest, e.label = makeGuest(g.id, layout.runtime)
		e.guest:PivotTo(CFrame.new(e.slotPos.X + 3, GUEST_Y, e.slotPos.Z))
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
		e.label = nil
		self:sendCarAway(e)
	end
end

function Visuals:updateLabel(core, g, e, now: number)
	if not e.label then
		return
	end
	local GS = self.C.GuestState
	local text, color = "", Color3.fromRGB(20, 20, 28)
	if g.state == GS.Queued then
		local total = self.config.guests.patience * self.timeScale
		local left = math.max(0, g.patienceEndsAt - now)
		local frac = left / total
		local prefix = if e.queueIndex == 1 then "NEXT " else ""
		text = ("%s%ds"):format(prefix, math.ceil(left))
		if frac > 0.5 then
			color = Color3.fromRGB(40, 140, 70)
		elseif frac > 0.25 then
			color = Color3.fromRGB(200, 150, 30)
		else
			color = Color3.fromRGB(200, 50, 50)
		end
	elseif g.state == GS.Staying then
		local room = core.rooms[g.roomId]
		if room and room.towelRequest then
			text, color = "Towel please!", Color3.fromRGB(200, 150, 30)
		else
			text = "Room " .. tostring(g.roomId)
		end
	elseif g.state == GS.Departed then
		local reason = g.departReason
		if reason == "Walkout" then
			text, color = "Too slow!", Color3.fromRGB(200, 50, 50)
		elseif reason == "Unserved" then
			text, color = "Closed?!", Color3.fromRGB(200, 90, 50)
		else
			text, color = "Thanks!", Color3.fromRGB(40, 140, 70)
		end
	end
	e.label.Text = text
	e.label.BackgroundColor3 = color
	e.label.Visible = text ~= ""
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
			step(e.car, e.carPath, drive, dt, CAR_Y)
		end
		if e.guest and #e.guestPath > 0 then
			step(e.guest, e.guestPath, walk, dt, GUEST_Y)
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

local GREEN = Color3.fromRGB(40, 140, 70)
local BLUE = Color3.fromRGB(50, 90, 170)
local AMBER = Color3.fromRGB(200, 140, 30)
local RED = Color3.fromRGB(190, 50, 50)

function Visuals:refreshWorld(core)
	local P = self.C.Phase
	local layout = self.layout
	local active = core.phase == P.Preparation or core.phase == P.Night or core.phase == P.Closing

	for i, room in ipairs(core.rooms) do
		local v = layout.rooms[i]
		local blockers = core:roomBlockers(room)
		if core:isRoomReady(room) then
			v.sign.Text = ("Room %d  READY"):format(i)
			v.sign.BackgroundColor3 = GREEN
		elseif room.occupant then
			local extra = if room.towelRequest then "  TOWEL!" else ""
			v.sign.Text = ("Room %d  OCCUPIED%s"):format(i, extra)
			v.sign.BackgroundColor3 = if room.towelRequest then AMBER else BLUE
		else
			v.sign.Text = ("Room %d: %s"):format(i, table.concat(blockers, ", "))
			v.sign.BackgroundColor3 = if room.acBroken then RED else AMBER
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
	layout.prompts.refill.Enabled = active
	layout.prompts.trolley.Enabled = active and not core.trolley
	layout.prompts.takeSheet.Enabled = active
	layout.prompts.takeTowel.Enabled = active
	layout.prompts.returnSupplies.Enabled = active
	layout.prompts.dumpTrash.Enabled = active

	layout.breakerLabel.Text = if core.power then "BREAKER: OK" else "BREAKER: RESET!"
	layout.breakerLabel.BackgroundColor3 = if core.power then Color3.fromRGB(20, 20, 28) else RED
	layout.linenLabel.Text = ("LINEN  Sheets %d | Towels %d"):format(core.stock.Sheet, core.stock.Towel)

	for _, l in ipairs(layout.powerLights) do
		l.light.Enabled = core.power
		l.part.Material = if core.power then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	layout.rain.Rate = if core.rain then 700 else 0

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
