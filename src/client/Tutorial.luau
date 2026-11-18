--!nonstrict
--[[
	First-night tutorial with on-screen guidance. Client only; it reads the
	server snapshot and never changes game state.

	Core steps run in order during the first run the player sees (night 1),
	advancing when the snapshot shows the action happened (or NEXT for info
	steps). Contextual hints (towel request, broken AC, power outage, out of
	sheets, closing, report) pop up the first time they happen on any night
	and take priority over the core steps.

	Guidance for the current target:
	  - bouncing outlined arrow above the object (BillboardGui, HUD style)
	  - yellow Highlight outline on the object
	  - edge-of-screen arrow + distance when the object is off screen
	  - bouncing arrow above the READY tile for UI targets
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Icons = require(script.Parent:WaitForChild("Icons"))
local Workspace = game:GetService("Workspace")

local Tutorial = {}
Tutorial.__index = Tutorial

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MAP_SCALE = Config.mapScale or 1

local function recipeName(id): string
	for _, r in ipairs(Config.recipes) do
		if r.id == id then
			return r.name
		end
	end
	return "food"
end

local YELLOW = Color3.fromRGB(255, 214, 64)
local OUTLINE = Color3.fromRGB(46, 32, 22)

------------------------------------------------------------------------
-- Snapshot helpers
------------------------------------------------------------------------

local function carrying(s, item: string): boolean
	for _, v in ipairs(s.carry or {}) do
		if v == item then
			return true
		end
	end
	return false
end

local function firstRoom(s, predicate): number?
	for i, r in ipairs(s.rooms or {}) do
		if predicate(r) then
			return i
		end
	end
	return nil
end

local function interactable(name: string): BasePart?
	local motel = Workspace:FindFirstChild("Motel")
	local folder = motel and motel:FindFirstChild("Interactables")
	local part = folder and folder:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

------------------------------------------------------------------------
-- Steps
--   text      string or function(s, ctx) -> string
--   target    function(s, ctx) -> BasePart | "Ready" | nil
--   when      function(s, ctx) -> boolean   (step may start)
--   done      function(s, ctx) -> boolean   (step finished)
--   info      true: shows NEXT; auto = seconds before it advances by itself
--   near      studs: reaching the target also completes the step
------------------------------------------------------------------------

local CORE = {
	{
		id = "welcome",
		info = true,
		text = "Welcome to your motel! Earn enough cash each night to pay the bill at dawn. How many nights can you last?",
	},
	{
		id = "hud",
		info = true,
		text = "Top: your cash and tonight's BILL. Left: room status. Keep the cash above the bill!",
	},
	{
		id = "linen",
		info = true,
		near = 12,
		text = "This is the LINEN CLOSET. Press E to open it and take clean sheets or towels. You can carry 1 item (2 with a trolley).",
		target = function()
			return interactable("LinenShelf")
		end,
	},
	{
		id = "shop",
		info = true,
		near = 10,
		text = "The SUPPLY SHOP is the store next to the motel. Press E at the counter to buy sheets, towels and the trolley.",
		target = function()
			return interactable("SupplyShop")
		end,
	},
	{
		id = "kitchen",
		info = true,
		near = 12,
		text = "This is the KITCHEN. Guests order room service during their stay: cook it at the stove (E), then carry it to their door.",
		target = function()
			return interactable("KitchenStove")
		end,
	},
	{
		id = "ready",
		text = "When you're set, press READY to open the motel for the night.",
		target = function(s)
			return if s.phase == "Preparation" then "Ready" else nil
		end,
		done = function(s)
			return s.phase ~= "Preparation"
		end,
	},
	{
		id = "desk",
		near = 14,
		text = "Guests are on the way! Go to the FRONT DESK.",
		target = function()
			return interactable("Desk")
		end,
		done = function(s)
			return (s.nightStats and s.nightStats.checkIns or 0) > 0
		end,
	},
	{
		id = "checkin",
		text = "Press E at the desk. A guest with a code = BOOKING, no code = WALK-IN. Pick a READY room, take the money, give the right change and hand over the key!",
		target = function()
			return interactable("Desk")
		end,
		done = function(s)
			return (s.nightStats and s.nightStats.checkIns or 0) > 0
		end,
	},
	{
		id = "wait",
		info = true,
		text = "Checked in! Guests stay about 30 seconds, then leave a mess. Keep serving new guests meanwhile.",
		done = function(s)
			return firstRoom(s, function(r)
				return not r.occupied and (r.trash or r.sheetsDirty)
			end) ~= nil
		end,
	},
	{
		id = "trash",
		text = function(_, ctx)
			return ("Room %d needs cleaning. Collect the trash from the bin inside (E)."):format(ctx.room or 1)
		end,
		when = function(s, ctx)
			ctx.room = ctx.room or firstRoom(s, function(r)
				return not r.occupied and r.trash
			end)
			return ctx.room ~= nil
		end,
		target = function(_, ctx)
			return interactable(("Room%dTrashBin"):format(ctx.room or 1))
		end,
		done = function(s, ctx)
			local r = ctx.room and s.rooms[ctx.room]
			return carrying(s, "Trash") or (r ~= nil and not r.trash)
		end,
	},
	{
		id = "dump",
		text = "Take the trash to the DUMPSTER (E).",
		target = function()
			return interactable("Dumpster")
		end,
		when = function(s)
			return carrying(s, "Trash")
		end,
		done = function(s)
			return not carrying(s, "Trash")
		end,
	},
	{
		id = "sheet",
		text = "Now open the LINEN CLOSET (E) and take a clean sheet.",
		target = function()
			return interactable("LinenShelf")
		end,
		when = function(s, ctx)
			local r = ctx.room and s.rooms[ctx.room]
			return r ~= nil and r.sheetsDirty
		end,
		done = function(s, ctx)
			local r = ctx.room and s.rooms[ctx.room]
			return carrying(s, "Sheet") or (r ~= nil and not r.sheetsDirty)
		end,
	},
	{
		id = "bed",
		text = function(_, ctx)
			return ("Change the sheets on the bed in Room %d (E). The room becomes READY again."):format(ctx.room or 1)
		end,
		target = function(_, ctx)
			return interactable(("Room%dBed"):format(ctx.room or 1))
		end,
		done = function(s, ctx)
			local r = ctx.room and s.rooms[ctx.room]
			return r ~= nil and not r.sheetsDirty
		end,
	},
	{
		id = "finish",
		info = true,
		auto = 10,
		text = "Great job! That's the loop: check in, clean, restock. Watch out for broken AC and power cuts on later nights.",
	},
}

local HINTS = {
	{
		id = "meal",
		when = function(s, ctx)
			ctx.mealRoom = firstRoom(s, function(r)
				return r.mealOrder ~= nil
			end)
			return ctx.mealRoom ~= nil
		end,
		text = function(s, ctx)
			local room = s.rooms[ctx.mealRoom or 1]
			local recipe = room and room.mealOrder and room.mealOrder.recipe or ""
			local number = room and room.number or 0
			if carrying(s, "Dish:" .. recipe) then
				return ("Deliver the %s at Room %d's door (E)."):format(recipeName(recipe), number)
			end
			for _, slot in ipairs(s.slots or {}) do
				if slot.recipe == recipe and slot.state == "Ready" then
					return ("The %s is ready! Open the stove (E) and PICK UP before it burns."):format(
						recipeName(recipe)
					)
				end
			end
			return ("Room %d ordered %s! Go to the KITCHEN and press E at the stove to cook it."):format(
				number,
				recipeName(recipe)
			)
		end,
		target = function(s, ctx)
			local room = s.rooms[ctx.mealRoom or 1]
			local recipe = room and room.mealOrder and room.mealOrder.recipe or ""
			if carrying(s, "Dish:" .. recipe) then
				return interactable(("Room%dDoor"):format(ctx.mealRoom or 1))
			end
			return interactable("KitchenStove")
		end,
		done = function(s, ctx)
			local r = ctx.mealRoom and s.rooms[ctx.mealRoom]
			return r == nil or r.mealOrder == nil
		end,
	},
	{
		id = "towel",
		when = function(s, ctx)
			ctx.towelRoom = firstRoom(s, function(r)
				return r.towelRequest
			end)
			return ctx.towelRoom ~= nil
		end,
		text = function(s, ctx)
			if carrying(s, "Towel") then
				return ("Deliver the towel at Room %d's door (E) for a $5 tip."):format(ctx.towelRoom or 1)
			end
			return ("Room %d wants a towel! Open the LINEN CLOSET (E) and take one."):format(ctx.towelRoom or 1)
		end,
		target = function(s, ctx)
			if carrying(s, "Towel") then
				return interactable(("Room%dDoor"):format(ctx.towelRoom or 1))
			end
			return interactable("LinenShelf")
		end,
		done = function(s, ctx)
			local r = ctx.towelRoom and s.rooms[ctx.towelRoom]
			return r == nil or not r.towelRequest
		end,
	},
	{
		id = "ac",
		when = function(s, ctx)
			ctx.acRoom = firstRoom(s, function(r)
				return r.acBroken
			end)
			return ctx.acRoom ~= nil
		end,
		text = function(_, ctx)
			return ("The AC in Room %d broke! Press E on the AC unit and connect the wires to fix it."):format(
				ctx.acRoom or 1
			)
		end,
		target = function(_, ctx)
			return interactable(("Room%dAC"):format(ctx.acRoom or 1))
		end,
		done = function(s, ctx)
			local r = ctx.acRoom and s.rooms[ctx.acRoom]
			return r == nil or not r.acBroken
		end,
	},
	{
		id = "power",
		when = function(s)
			return s.power == false and (s.phase == "Night" or s.phase == "Closing" or s.phase == "Preparation")
		end,
		text = "POWER OUTAGE! Nobody can check in. Press E at the BREAKER panel in the lobby and flip the switches.",
		target = function()
			return interactable("BreakerPanel")
		end,
		done = function(s)
			return s.power ~= false
		end,
	},
	{
		id = "stock",
		when = function(s)
			return s.stock and s.stock.Sheet == 0 and (s.phase == "Night" or s.phase == "Preparation")
		end,
		text = "Out of clean sheets! Buy more at the SUPPLY SHOP next to the motel.",
		target = function()
			return interactable("SupplyShop")
		end,
		done = function(s)
			return s.stock and s.stock.Sheet > 0
		end,
	},
	{
		id = "closing",
		info = true,
		auto = 6,
		when = function(s)
			return s.phase == "Closing"
		end,
		text = "Closing time: no new check-ins. Finish cleaning before the night ends!",
		done = function(s)
			return s.phase ~= "Closing"
		end,
	},
	{
		id = "report",
		info = true,
		auto = 8,
		when = function(s)
			return s.phase == "Report"
		end,
		text = "Dawn: the bill is paid from your cash. If you're short, the motel closes!",
		done = function(s)
			return s.phase ~= "Report"
		end,
	},
}

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------

function Tutorial.new(hud)
	local self = setmetatable({}, Tutorial)
	self.hud = hud
	self.player = Players.LocalPlayer
	self.coreIndex = 1
	self.coreRunId = nil
	self.coreFinished = false
	self.skipped = false
	self.hintsDone = {}
	self.ctx = {}
	self.current = nil
	self.stepStarted = 0
	self.state = nil

	hud.onTutorialNext = function()
		self:advance()
	end
	hud.onTutorialSkip = function()
		self.skipped = true
		self:show(nil)
	end

	local playerGui = self.player:WaitForChild("PlayerGui")

	-- 3D arrow above the target (HUD style: outlined, no background).
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TutorialArrow"
	billboard.Size = UDim2.fromOffset(80, 96)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Enabled = false
	Icons.create("arrowDown", {
		Parent = billboard,
		Size = UDim2.new(1, 0, 0, 64),
		FallbackColor = YELLOW,
	})
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = OUTLINE
	local dist = Instance.new("TextLabel")
	dist.Size = UDim2.new(1, 0, 0, 26)
	dist.Position = UDim2.fromOffset(0, 66)
	dist.BackgroundTransparency = 1
	dist.Font = Enum.Font.FredokaOne
	dist.TextSize = 20
	dist.TextColor3 = Color3.new(1, 1, 1)
	dist.Text = ""
	dist.Parent = billboard
	local stroke2 = stroke:Clone()
	stroke2.Thickness = 2
	stroke2.Parent = dist
	billboard.Parent = playerGui
	self.billboard = billboard
	self.distLabel = dist

	local highlight = Instance.new("Highlight")
	highlight.Name = "TutorialHighlight"
	highlight.FillColor = YELLOW
	highlight.FillTransparency = 0.8
	highlight.OutlineColor = YELLOW
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	-- Under the camera so it renders locally regardless of where the target lives.
	highlight.Parent = Workspace.CurrentCamera
	self.highlight = highlight

	-- Edge-of-screen pointer (raw pixels, so its own ScreenGui without UIScale).
	local edgeGui = Instance.new("ScreenGui")
	edgeGui.Name = "TutorialPointer"
	edgeGui.IgnoreGuiInset = true
	edgeGui.ResetOnSpawn = false
	edgeGui.DisplayOrder = 5
	edgeGui.Parent = playerGui
	local edge = Icons.create("arrowRight", {
		Animate = false, -- points at the target; keep its angle exact
		Parent = edgeGui,
		Size = UDim2.fromOffset(64, 64),
		AnchorPoint = Vector2.new(0.5, 0.5),
		FallbackColor = YELLOW,
	}).frame
	edge.Visible = false
	local edgeDist = dist:Clone()
	edgeDist.AnchorPoint = Vector2.new(0.5, 0)
	edgeDist.Position = UDim2.new(0.5, 0, 1, -4)
	edgeDist.Size = UDim2.fromOffset(80, 24)
	edgeDist.Parent = edge
	self.edge = edge
	self.edgeDist = edgeDist

	-- Bouncing arrow for the READY tile.
	local readyHolder = hud.readyTile and hud.readyTile.holder
	if readyHolder then
		local readyArrow = Icons.create("arrowDown", {
			Name = "TutorialReadyArrow",
			Parent = readyHolder,
			Size = UDim2.fromOffset(56, 56),
			Position = UDim2.new(0.5, 0, 0, -6),
			AnchorPoint = Vector2.new(0.5, 1),
			ZIndex = 5,
			FallbackColor = YELLOW,
		}).frame
		readyArrow.Visible = false
		self.readyArrow = readyArrow
	end
	return self
end

------------------------------------------------------------------------
-- Step selection
------------------------------------------------------------------------

local function evalText(step, s, ctx)
	if typeof(step.text) == "function" then
		return step.text(s, ctx)
	end
	return step.text
end

function Tutorial:coreActive(s): boolean
	if self.skipped or self.coreFinished then
		return false
	end
	if self.coreRunId == nil then
		-- Only start on the first night of a run.
		if s.night ~= 1 then
			return false
		end
		self.coreRunId = s.runId
	end
	return s.runId == self.coreRunId
end

function Tutorial:advance()
	local cur = self.current
	if not cur then
		return
	end
	if cur.kind == "core" then
		self.coreIndex += 1
		if self.coreIndex > #CORE then
			self.coreFinished = true
		end
	else
		self.hintsDone[cur.step.id] = true
	end
	self.current = nil
	self:refresh()
end

function Tutorial:pick(s)
	-- Contextual hints first (urgent).
	for _, h in ipairs(HINTS) do
		if not self.hintsDone[h.id] and h.when(s, self.ctx) then
			return { kind = "hint", step = h }
		end
	end
	if not self:coreActive(s) then
		return nil
	end
	-- Skip core steps that are already satisfied.
	while self.coreIndex <= #CORE do
		local step = CORE[self.coreIndex]
		if step.done and step.done(s, self.ctx) and not step.when then
			self.coreIndex += 1
		elseif step.when and not step.when(s, self.ctx) then
			-- Waiting for its precondition (e.g. a room to get dirty).
			if step.done and step.done(s, self.ctx) then
				self.coreIndex += 1
			else
				return nil
			end
		else
			return { kind = "core", step = step }
		end
	end
	self.coreFinished = true
	return nil
end

function Tutorial:update(s)
	self.state = s
	self:refresh()
end

function Tutorial:refresh()
	local s = self.state
	if not s or self.skipped then
		self:show(nil)
		return
	end
	-- Finish the current step when its condition is met.
	local cur = self.current
	if cur and cur.step.done and cur.step.done(s, self.ctx) then
		self:advance()
		return
	end
	if cur and cur.kind == "core" and not self:coreActive(s) then
		cur = nil
	end
	-- A new urgent hint pre-empts a core step.
	local next = self:pick(s)
	if next and (not cur or (next.kind == "hint" and cur.kind == "core") or next.step == cur.step) then
		if not cur or next.step ~= cur.step then
			self.stepStarted = os.clock()
		end
		cur = next
	elseif not cur then
		cur = next
	end
	self.current = cur
	self:show(cur)
end

function Tutorial:show(cur)
	if not cur then
		self.hud:setTutorial(nil)
		self.target = nil
		return
	end
	local s = self.state
	local step = cur.step
	local title
	if cur.kind == "core" then
		title = ("TUTORIAL %d/%d"):format(self.coreIndex, #CORE)
	else
		title = "TIP!"
	end
	self.hud:setTutorial({
		title = title,
		text = evalText(step, s, self.ctx),
		showNext = step.info == true,
		icon = if cur.kind == "core" then "star" else "bell",
	})
	self.target = if step.target then step.target(s, self.ctx) else nil
end

------------------------------------------------------------------------
-- Per-frame guidance
------------------------------------------------------------------------

function Tutorial:tick()
	local cur = self.current
	local target = self.target
	local s = self.state

	-- Re-resolve targets that may have streamed in.
	if cur and cur.step.target and (target == nil or (typeof(target) == "Instance" and not target.Parent)) then
		target = cur.step.target(s, self.ctx)
		self.target = target
	end

	-- Auto-advance timed info steps.
	if cur and cur.step.auto and os.clock() - self.stepStarted > cur.step.auto then
		self:advance()
		return
	end

	local bounce = math.abs(math.sin(os.clock() * 4))
	if self.readyArrow then
		self.readyArrow.Visible = target == "Ready"
		self.readyArrow.Position = UDim2.new(0.5, 0, 0, -6 - bounce * 12)
	end

	local part = if typeof(target) == "Instance" then target else nil
	if not part then
		self.billboard.Enabled = false
		self.highlight.Enabled = false
		self.edge.Visible = false
		return
	end

	local character = self.player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local distance = if hrp then (hrp.Position - part.Position).Magnitude else 0

	-- Reaching a location completes "go here" info steps.
	if cur and cur.step.near and hrp and distance <= cur.step.near * MAP_SCALE then
		self:advance()
		return
	end

	self.billboard.Adornee = part
	self.billboard.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 3.5 + bounce * 1.2, 0)
	self.billboard.Enabled = true
	self.distLabel.Text = if distance > 12 then ("%dm"):format(math.floor(distance)) else ""
	self.highlight.Adornee = part
	self.highlight.Enabled = true

	-- Edge pointer when the target is off screen.
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	local p, onScreen = cam:WorldToViewportPoint(part.Position)
	local inside = onScreen and p.X > 40 and p.X < vp.X - 40 and p.Y > 40 and p.Y < vp.Y - 40
	if inside then
		self.edge.Visible = false
		return
	end
	local center = vp / 2
	local dir = Vector2.new(p.X, p.Y) - center
	if p.Z < 0 then
		dir = -dir -- target is behind the camera
	end
	if dir.Magnitude < 1 then
		dir = Vector2.new(0, 1)
	end
	dir = dir.Unit
	local margin = 56
	local half = center - Vector2.new(margin, margin)
	local scale = math.min(
		if dir.X ~= 0 then half.X / math.abs(dir.X) else math.huge,
		if dir.Y ~= 0 then half.Y / math.abs(dir.Y) else math.huge
	)
	local pos = center + dir * scale
	self.edge.Position = UDim2.fromOffset(pos.X, pos.Y)
	self.edge.Rotation = math.deg(math.atan2(dir.Y, dir.X))
	self.edgeDist.Rotation = -self.edge.Rotation
	self.edgeDist.Text = ("%dm"):format(math.floor(distance))
	self.edge.Visible = true
end

return Tutorial
