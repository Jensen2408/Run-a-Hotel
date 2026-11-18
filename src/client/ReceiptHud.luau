--!nonstrict
--[[
	Receipt HUD (right middle of the screen): the front desk's guest tickets,
	drawn like a paper till receipt.

	PHONE   calls that still ring at the front desk (meal, towel, broken AC).
	        Shown to the receptionist (or everyone when nobody is one). At
	        the desk each ticket has a SEND button for the role that handles
	        it; the server accepts it only from near the desk.
	MY TASKS tickets the desk forwarded to my role (or to everyone when
	        nobody plays that role). Only forwarded jobs can be done.

	Rows are rebuilt when the ticket list changes; timers update every frame.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local UiKit = require(script.Parent:WaitForChild("UiKit"))
local Icons = require(script.Parent:WaitForChild("Icons"))

local make, label = UiKit.make, UiKit.label

local PAPER = Color3.fromRGB(255, 253, 244)
local INK = Color3.fromRGB(70, 60, 52)
local FADED = Color3.fromRGB(150, 138, 124)
local RED_INK = Color3.fromRGB(206, 56, 46)
local MONO = Enum.Font.RobotoMono
local WIDTH = 262

local ROLE_COLORS = {
	Chef = UiKit.ORANGE,
	Housekeeper = UiKit.TEAL,
	Maintenance = UiKit.BLUE,
}
local ROLE_ICONS = { Chef = "chefHat", Housekeeper = "broom", Maintenance = "wrench" }

local ReceiptHud = {}
ReceiptHud.__index = ReceiptHud

local function now(): number
	return Workspace:GetServerTimeNow()
end

local MONO_BOLD = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
local MAX_ROWS = 4 -- per section; the title shows the full count

local function mono(props)
	props.Font = MONO
	props.Stroke = 0
	props.TextColor3 = props.TextColor3 or INK
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	local t = label(props)
	t.FontFace = MONO_BOLD
	return t
end

-- Dashed separator line.
local function dashes(parent, order: number)
	local row = make("Frame", {
		Name = "Dashes",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 8),
		LayoutOrder = order,
		Parent = parent,
	})
	local n = 22
	for i = 0, n - 1 do
		make("Frame", {
			BackgroundColor3 = FADED,
			BorderSizePixel = 0,
			Position = UDim2.new(i / n, 1, 0.5, -1),
			Size = UDim2.new(0.5 / n, 0, 0, 2),
			Parent = row,
		})
	end
	return row
end

function ReceiptHud.new(playerGui: PlayerGui, deps, config)
	local self = setmetatable({}, ReceiptHud)
	self.send = deps.send
	self.config = config
	self.recipes = {}
	for _, r in ipairs(config.recipes or {}) do
		self.recipes[r.id] = r
	end
	self.state = nil
	self.key = nil
	self.rows = {}
	self.lastRinging = 0
	self.lastTasks = 0
	self.atDesk = false

	local screen = UiKit.screen(playerGui, "Receipt", 4, false)
	self.screen = screen
	local holder = make("Frame", {
		Name = "Receipt",
		BackgroundTransparency = 1,
		-- Right middle, under the tutorial / tip card.
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0.5, -46),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Rotation = 1.5,
		Visible = false,
		Parent = screen.root,
	})
	self.holder = holder
	local paper = make("Frame", {
		Name = "Paper",
		BackgroundColor3 = PAPER,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = holder,
	})
	UiKit.corner(paper, UDim.new(0, 6))
	UiKit.outline(paper, 3)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = paper,
	})
	make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = paper,
	})
	self.paper = paper

	-- Header.
	local head = make("Frame", {
		Name = "Head",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 1,
		Parent = paper,
	})
	Icons.create("bell", {
		Parent = head,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(0, 22, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
	})
	label({
		Parent = head,
		Size = UDim2.new(1, -40, 1, 0),
		Position = UDim2.fromOffset(40, 0),
		TextSize = 22,
		Text = "FRONT DESK",
		TextColor3 = INK,
		Stroke = 0,
	})
	mono({
		Parent = paper,
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = 2,
		TextSize = 12,
		TextColor3 = FADED,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "GUEST TICKETS",
	})
	dashes(paper, 3)

	-- Sections (rows go into these frames).
	local function section(name: string, order: number, title: string)
		local title_ = mono({
			Name = name .. "Title",
			Parent = paper,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = order,
			TextSize = 14,
			Text = title,
		})
		local list = make("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order + 1,
			Parent = paper,
		})
		make("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
			Parent = list,
		})
		return title_, list
	end
	self.phoneTitle, self.phoneList = section("Phone", 10, "PHONE")
	self.phoneSep = dashes(paper, 20)
	self.taskTitle, self.taskList = section("Tasks", 30, "MY TASKS")
	self.taskSep = dashes(paper, 40)
	self.footer = mono({
		Parent = paper,
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = 50,
		TextSize = 11,
		TextColor3 = FADED,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "THANK YOU FOR STAYING!",
	})

	-- Torn (zigzag) bottom edge: diamonds behind the paper's bottom edge,
	-- only their lower halves show.
	paper.ZIndex = 2
	local teeth = make("Frame", {
		Name = "Teeth",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 10),
		Parent = holder,
	})
	local tooth = 14
	for i = 0, math.floor(WIDTH / tooth) do
		local t = make("Frame", {
			BackgroundColor3 = PAPER,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(i * tooth + tooth / 2 - 1, -2),
			Size = UDim2.fromOffset(tooth * 0.72, tooth * 0.72),
			Rotation = 45,
			ZIndex = 1,
			Parent = teeth,
		})
		make("UIStroke", { Thickness = 2, Color = UiKit.OUTLINE, Parent = t })
	end
	return self
end

function ReceiptHud:kindText(c): string
	if c.kind == "Meal" then
		local r = self.recipes[c.recipe]
		return (r and r.name or "MEAL"):upper()
	elseif c.kind == "Towel" then
		return "TOWEL"
	end
	return "AC BROKEN"
end

function ReceiptHud:kindIcon(c): string
	if c.kind == "Meal" then
		local r = self.recipes[c.recipe]
		return r and r.icon or "tray"
	elseif c.kind == "Towel" then
		return "towel"
	end
	return "snowflake"
end

-- One ticket row; phone rows get a SEND button.
function ReceiptHud:makeRow(parent, c, order: number, phone: boolean)
	local row = make("Frame", {
		Name = ("%s_%d_%s"):format(if phone then "Call" else "Task", c.roomId, c.kind),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, if phone then 66 else 34),
		LayoutOrder = order,
		Parent = parent,
	})
	local icon = Icons.create(self:kindIcon(c), {
		Parent = row,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(0, 3),
	})
	mono({
		Parent = row,
		Size = UDim2.new(1, -90, 0, 17),
		Position = UDim2.fromOffset(34, 1),
		TextSize = 16,
		Font = MONO,
		Text = ("ROOM %d"):format(c.number),
	})
	mono({
		Parent = row,
		Size = UDim2.new(1, -90, 0, 15),
		Position = UDim2.fromOffset(34, 18),
		TextSize = 14,
		TextColor3 = INK,
		Text = self:kindText(c),
	})
	local timer = mono({
		Parent = row,
		Size = UDim2.fromOffset(52, 18),
		Position = UDim2.new(1, -52, 0, 8),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	})
	local entry = { frame = row, call = c, timer = timer, icon = icon }
	if phone then
		local colors = ROLE_COLORS[c.role] or UiKit.GREEN
		local holder, body, grad = UiKit.chunk({
			Name = "Send",
			Parent = row,
			Size = UDim2.new(1, 0, 0, 28),
			Position = UDim2.fromOffset(0, 36),
			Colors = colors,
			Radius = UDim.new(0, 8),
			Button = true,
			ShadowDepth = 3,
			Stroke = 2,
		})
		local roleIcon = Icons.create(ROLE_ICONS[c.role] or "bell", {
			Parent = body,
			Size = UDim2.fromOffset(22, 22),
			Position = UDim2.new(0, 6, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = 2,
		})
		local text = label({
			Parent = body,
			Size = UDim2.new(1, -34, 1, 0),
			Position = UDim2.fromOffset(30, 0),
			TextSize = 15,
			Text = ("SEND TO %s"):format(c.role:upper()),
		})
		entry.button = { holder = holder, body = body, grad = grad, text = text, colors = colors, icon = roleIcon }
		UiKit.pressable(holder, body, function()
			if not self.atDesk then
				UiKit.play("error")
				UiKit.wiggle(holder, 5, 0.3)
				return
			end
			self.send({ kind = "ForwardCall", roomId = c.roomId, call = c.kind })
		end)
	end
	return entry
end

function ReceiptHud:setState(s)
	self.state = s
	local active = s.phase == "Preparation" or s.phase == "Night" or s.phase == "Closing"
	local phone, tasks = {}, {}
	for _, c in ipairs(s.calls or {}) do
		if not c.sent then
			if s.phoneForMe ~= false then
				table.insert(phone, c)
			end
		elseif c.forMe then
			table.insert(tasks, c)
		end
	end
	if not active then
		phone, tasks = {}, {}
	end
	-- Rebuild rows only when the ticket list changed.
	local parts = {}
	for _, c in ipairs(phone) do
		table.insert(parts, ("P%d%s%s"):format(c.roomId, c.kind, c.recipe or ""))
	end
	for _, c in ipairs(tasks) do
		table.insert(parts, ("T%d%s%s"):format(c.roomId, c.kind, c.recipe or ""))
	end
	local key = table.concat(parts, "|")
	if key ~= self.key then
		local old = {}
		for _, e in ipairs(self.rows) do
			old[e.frame.Name] = true
			e.frame:Destroy()
		end
		self.rows = {}
		for i, c in ipairs(phone) do
			if i > MAX_ROWS then
				break
			end
			local e = self:makeRow(self.phoneList, c, i, true)
			table.insert(self.rows, e)
			if self.key ~= nil and not old[e.frame.Name] then
				UiKit.pop(e.frame, 0.2)
			end
		end
		for i, c in ipairs(tasks) do
			if i > MAX_ROWS then
				break
			end
			local e = self:makeRow(self.taskList, c, i, false)
			table.insert(self.rows, e)
			if self.key ~= nil and not old[e.frame.Name] then
				UiKit.pop(e.frame, 0.2)
			end
		end
		self.key = key
		-- Ring for new calls, chime for new tasks.
		if #phone > self.lastRinging then
			UiKit.play("notify")
		elseif #tasks > self.lastTasks then
			UiKit.play("sweep")
		end
		self.lastRinging, self.lastTasks = #phone, #tasks
		local showPhone = #phone > 0
		local showTasks = #tasks > 0
		self.phoneTitle.Visible = showPhone
		self.phoneList.Visible = showPhone
		self.phoneSep.Visible = showPhone and showTasks
		self.taskTitle.Visible = showTasks
		self.taskList.Visible = showTasks
		self.taskSep.Visible = showTasks or showPhone
		self.phoneTitle.Text = ("PHONE (%d)"):format(#phone)
		self.taskTitle.Text = ("MY TASKS (%d)"):format(#tasks)
		local visible = showPhone or showTasks
		if visible and not self.holder.Visible then
			self.holder.Visible = true
			UiKit.pop(self.holder, 0.15)
		elseif not visible then
			self.holder.Visible = false
		end
	end
	self:tick()
end

function ReceiptHud:deskDistanceOk(): boolean
	local hrp = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local motel = Workspace:FindFirstChild("Motel")
	local interact = motel and motel:FindFirstChild("Interactables")
	local desk = interact and interact:FindFirstChild("Desk")
	if not (hrp and desk) then
		return false
	end
	local range = self.config.interaction.deskRange * (self.config.mapScale or 1)
	return (hrp.Position - desk.Position).Magnitude <= range
end

function ReceiptHud:tick()
	if not self.holder.Visible then
		return
	end
	local atDesk = self:deskDistanceOk()
	local t = now()
	for _, e in ipairs(self.rows) do
		local c = e.call
		if c.expiresAt then
			local left = math.max(0, c.expiresAt - t)
			e.timer.Text = ("%d:%02d"):format(left // 60, math.floor(left % 60))
			e.timer.TextColor3 = if left < 10 then RED_INK else INK
		else
			local waited = math.max(0, t - (c.at or t))
			e.timer.Text = ("%d:%02d"):format(waited // 60, math.floor(waited % 60))
			e.timer.TextColor3 = if waited > 30 then RED_INK else FADED
		end
		local b = e.button
		if b and (b.atDesk ~= atDesk) then
			b.atDesk = atDesk
			UiKit.setColors(b.grad, if atDesk then b.colors else UiKit.GREY)
			b.text.Text = if atDesk then ("SEND TO %s"):format(c.role:upper()) else "ANSWER AT DESK"
		end
	end
	self.atDesk = atDesk
end

return ReceiptHud
