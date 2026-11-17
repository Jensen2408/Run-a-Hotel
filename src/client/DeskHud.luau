--!nonstrict
--[[
	DeskHud: the front desk terminal (receptionist HUD).

	Display only. The server owns the session and every rule; this panel
	shows `state.desk` (MotelCore:deskView) and sends the player's choices:
	mode, reservation code, room, payment method, and the change notes on
	confirm. Code digits and change notes are composed locally and checked
	by the server.

	  header       FRONT DESK ribbon, night, queue, close
	  guest card   name, what the guest says, code, patience
	  steps        Start (Booking / Walk-in) -> Code -> Room -> Payment
	  states       No Guests Waiting, Front Desk Busy, Power Out, Guest Left,
	               Room No Longer Available, closed / not open yet
]]

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UiKit = require(script.Parent:WaitForChild("UiKit"))
local Icons = require(script.Parent:WaitForChild("Icons"))

local DeskHud = {}
DeskHud.__index = DeskHud

local PANEL = Vector2.new(880, 580)
local LEFT_W = 250
local RIGHT_X = 290
local RIGHT_W = PANEL.X - RIGHT_X - 20
local CONTENT_Y = 140

local STATUS_TEXT = {
	NoGuests = { "No Guests Waiting", "The next guest will show up here.", "guests" },
	PowerOut = { "Power Out", "Reset the breaker in the lobby, then come back.", "plug" },
	NotOpen = { "Desk Not Open Yet", "Check-in opens at Night. Get the rooms ready!", "moon" },
	Closed = { "Desk Closed", "Closing time: no new check-ins.", "moon" },
	Busy = { "Front Desk Busy", "", "people" },
}

local ROOM_COLORS = {
	Ready = UiKit.GREEN,
	Occupied = UiKit.BLUE,
	Dirty = UiKit.ORANGE,
	["Out of Order"] = UiKit.RED,
}
local ROOM_ICONS = { Ready = "bed", Occupied = "sleep", Dirty = "broom", ["Out of Order"] = "wrench" }

local function text(parent, props)
	props.Parent = parent
	if props.TextColor3 == nil then
		props.TextColor3 = UiKit.TEXT_DARK
		if props.Stroke == nil then
			props.Stroke = 0
		end
	end
	return UiKit.label(props)
end

local function frame(parent, props)
	props.Parent = parent
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = 1
	end
	props.BorderSizePixel = 0
	return UiKit.make("Frame", props)
end

-- A white rounded strip used for value boxes and cards.
local function strip(parent, size: UDim2, pos: UDim2, transparency: number?)
	local f = frame(parent, {
		BackgroundColor3 = UiKit.WHITE,
		BackgroundTransparency = transparency or 0.25,
		Size = size,
		Position = pos,
	})
	UiKit.corner(f, UDim.new(0, 14))
	return f
end

function DeskHud.new(playerGui: PlayerGui, callbacks)
	local self = setmetatable({}, DeskHud)
	self.callbacks = callbacks -- send(kind, payload)
	self.view = nil
	self.mode = nil -- "owner" | "busy" | nil
	self.sawOpen = false
	self.code = ""
	self.change = {}
	self.changeKey = nil
	self.pendingTx = nil
	self.txCounter = 0
	self.lastSeq = 0
	self.patienceTotals = {}

	local screen = UiKit.screen(playerGui, "FrontDesk", 8)
	self.screen = screen
	local panel, body = screen:modal("FrontDesk", PANEL, "FRONT DESK", "bell")
	self.panel = panel
	self.body = body
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.Visible then
			self:onClosed()
		end
	end)

	self:buildHeader()
	self:buildGuestCard()
	self:buildMessage()
	self:buildStatus()
	self:buildStart()
	self:buildCode()
	self:buildRooms()
	self:buildPayment()
	self:bindKeyboard()
	return self
end

------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------

local function chip(parent, pos: UDim2, iconName: string, colors)
	local holder, body = UiKit.chunk({
		Parent = parent,
		Size = UDim2.fromOffset(150, 40),
		Position = pos,
		Colors = colors,
		Radius = UDim.new(1, 0),
		ShadowDepth = 3,
		Stroke = 3,
	})
	Icons.create(iconName, {
		Parent = body,
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(0, 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 2,
	})
	local l = UiKit.label({
		Parent = body,
		Size = UDim2.new(1, -46, 1, 0),
		Position = UDim2.fromOffset(40, 0),
		TextSize = 20,
		Text = "",
	})
	return holder, l
end

function DeskHud:buildHeader()
	local _, night = chip(self.body, UDim2.fromOffset(20, 40), "moon", UiKit.PURPLE)
	local _, queue = chip(self.body, UDim2.fromOffset(180, 40), "guests", UiKit.BLUE)
	self.nightText = night
	self.queueText = queue
end

function DeskHud:buildGuestCard()
	local holder, body = UiKit.chunk({
		Name = "GuestCard",
		Parent = self.body,
		Size = UDim2.fromOffset(LEFT_W, PANEL.Y - 110),
		Position = UDim2.fromOffset(20, 92),
		Colors = UiKit.CARD,
		Radius = UDim.new(0, 18),
		Shine = false,
	})
	self.guestCard = holder
	local avatar = frame(body, {
		BackgroundColor3 = Color3.fromRGB(255, 236, 190),
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(90, 90),
		Position = UDim2.new(0.5, 0, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 2,
	})
	UiKit.corner(avatar, UDim.new(1, 0))
	UiKit.outline(avatar, 3)
	Icons.create("guests", {
		Parent = avatar,
		Size = UDim2.fromOffset(64, 64),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 3,
	})
	self.guestName = text(body, {
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 110),
		TextSize = 24,
		Text = "",
		ZIndex = 2,
	})
	-- Speech bubble.
	local bubble = strip(body, UDim2.new(1, -24, 0, 120), UDim2.fromOffset(12, 148), 0)
	bubble.ZIndex = 2
	UiKit.outline(bubble, 2)
	self.guestLine = text(bubble, {
		Size = UDim2.new(1, -20, 1, -14),
		Position = UDim2.fromOffset(10, 7),
		TextSize = 20,
		Text = "",
		ZIndex = 3,
	})
	-- Code chip (bookings).
	local codeHolder, codeBody = UiKit.chunk({
		Parent = body,
		Size = UDim2.new(1, -40, 0, 46),
		Position = UDim2.fromOffset(20, 282),
		Colors = UiKit.GOLD,
		Radius = UDim.new(0, 14),
		ZIndex = 2,
	})
	self.codeChip = codeHolder
	Icons.create("key", {
		Parent = codeBody,
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 3,
	})
	self.codeText = UiKit.label({
		Parent = codeBody,
		Size = UDim2.new(1, -50, 1, 0),
		Position = UDim2.fromOffset(46, 0),
		TextSize = 26,
		Text = "",
		ZIndex = 3,
	})
	-- Patience.
	self.patienceIcon = Icons.create("hourglass", {
		Parent = body,
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(14, 348),
		ZIndex = 2,
	})
	self.patienceText = text(body, {
		Size = UDim2.new(1, -60, 0, 30),
		Position = UDim2.fromOffset(50, 348),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		ZIndex = 2,
	})
	local barBack = frame(body, {
		BackgroundColor3 = Color3.fromRGB(80, 60, 44),
		BackgroundTransparency = 0.6,
		Size = UDim2.new(1, -28, 0, 22),
		Position = UDim2.fromOffset(14, 386),
		ZIndex = 2,
	})
	UiKit.corner(barBack, UDim.new(1, 0))
	UiKit.outline(barBack, 2)
	local fill = frame(barBack, {
		BackgroundColor3 = UiKit.WHITE,
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	})
	UiKit.corner(fill, UDim.new(1, 0))
	self.patienceFill = fill
	self.patienceGrad = UiKit.gradient(fill, UiKit.GREEN)
	self.noGuestText = text(body, {
		Size = UDim2.new(1, -20, 0, 60),
		Position = UDim2.fromOffset(10, 150),
		TextSize = 20,
		Text = "Nobody at the desk.",
		ZIndex = 2,
	})
end

function DeskHud:buildMessage()
	local holder, body, grad = UiKit.chunk({
		Name = "Message",
		Parent = self.body,
		Size = UDim2.fromOffset(RIGHT_W, 40),
		Position = UDim2.fromOffset(RIGHT_X, 92),
		Colors = UiKit.RED,
		Radius = UDim.new(0, 12),
		ShadowDepth = 3,
		Stroke = 3,
		Visible = false,
	})
	self.msgHolder = holder
	self.msgGrad = grad
	self.msgIcon = Icons.create("warning", {
		Parent = body,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(0, 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 2,
	})
	self.msgText = UiKit.label({
		Parent = body,
		Size = UDim2.new(1, -48, 1, 0),
		Position = UDim2.fromOffset(42, 0),
		TextSize = 18,
		Text = "",
		ZIndex = 2,
	})
end

-- Area for one step (right column).
function DeskHud:stepFrame(name: string)
	return frame(self.body, {
		Name = name,
		Size = UDim2.fromOffset(RIGHT_W, PANEL.Y - CONTENT_Y - 20),
		Position = UDim2.fromOffset(RIGHT_X, CONTENT_Y),
		Visible = false,
	})
end

function DeskHud:buildStatus()
	local f = frame(self.body, {
		Name = "Status",
		Size = UDim2.fromOffset(RIGHT_W, PANEL.Y - 112),
		Position = UDim2.fromOffset(RIGHT_X, 92),
		Visible = false,
	})
	self.statusFrame = f
	self.statusIcon = Icons.create("guests", {
		Parent = f,
		Size = UDim2.fromOffset(120, 120),
		Position = UDim2.new(0.5, 0, 0, 60),
		AnchorPoint = Vector2.new(0.5, 0),
	})
	self.statusTitle = text(f, {
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.fromOffset(0, 196),
		TextSize = 36,
		Text = "",
	})
	self.statusSub = text(f, {
		Size = UDim2.new(1, -40, 0, 60),
		Position = UDim2.fromOffset(20, 250),
		TextSize = 22,
		Text = "",
	})
end

function DeskHud:buildStart()
	local f = self:stepFrame("Start")
	self.startFrame = f
	text(f, {
		Size = UDim2.new(1, 0, 0, 36),
		TextSize = 26,
		Text = "How is this guest checking in?",
	})
	local w = (RIGHT_W - 30) / 2
	local booking = UiKit.button(
		f,
		"Booking",
		UDim2.fromOffset(w, 150),
		UDim2.fromOffset(0, 60),
		UiKit.BLUE,
		"BOOKING",
		function()
			self:send("DeskMode", { mode = "Booking" })
		end,
		"key"
	)
	local walkin = UiKit.button(
		f,
		"WalkIn",
		UDim2.fromOffset(w, 150),
		UDim2.fromOffset(w + 30, 60),
		UiKit.GREEN,
		"WALK-IN",
		function()
			self:send("DeskMode", { mode = "WalkIn" })
		end,
		"door"
	)
	for _, b in ipairs({ booking, walkin }) do
		b.label.TextSize = 30
	end
	text(f, {
		Size = UDim2.new(1, -20, 0, 70),
		Position = UDim2.fromOffset(10, 240),
		TextSize = 20,
		Text = "Listen to the guest: a reservation code means BOOKING, no code means WALK-IN.",
	})
end

function DeskHud:buildCode()
	local f = self:stepFrame("Code")
	self.codeFrame = f
	text(f, { Size = UDim2.new(1, 0, 0, 34), TextSize = 26, Text = "Enter the reservation code" })
	self.digitBoxes = {}
	for i = 1, 4 do
		local box = strip(f, UDim2.fromOffset(64, 70), UDim2.fromOffset(RIGHT_W / 2 - 146 + (i - 1) * 74, 44), 0)
		UiKit.outline(box, 3)
		self.digitBoxes[i] = text(box, { Size = UDim2.fromScale(1, 1), TextSize = 40, Text = "" })
	end
	local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "CLR", "0", "DEL" }
	local kw, kh, gap = 92, 46, 8
	local left = RIGHT_W / 2 - (kw * 3 + gap * 2) / 2
	for i, k in ipairs(keys) do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local colors = if k == "CLR" then UiKit.RED elseif k == "DEL" then UiKit.ORANGE else UiKit.CARD
		local b = UiKit.button(
			f,
			"Key" .. k,
			UDim2.fromOffset(kw, kh),
			UDim2.fromOffset(left + col * (kw + gap), 124 + row * (kh + gap)),
			colors,
			k,
			function()
				self:keypad(k)
			end
		)
		b.label.TextSize = 26
		if colors == UiKit.CARD then
			b.label.TextColor3 = UiKit.TEXT_DARK
		end
	end
	self:backButton(f)
	UiKit.button(f, "Verify", UDim2.fromOffset(180, 56), UDim2.new(1, -180, 1, -60), UiKit.GREEN, "VERIFY", function()
		self:verify()
	end, "check")
end

function DeskHud:backButton(parent)
	local b = UiKit.button(
		parent,
		"Back",
		UDim2.fromOffset(140, 56),
		UDim2.new(0, 0, 1, -60),
		UiKit.GREY,
		"BACK",
		function()
			self:send("DeskBack", {})
		end,
		"arrowRight"
	)
	if b.icon then
		b.icon.frame.Rotation = 180
	end
	return b
end

function DeskHud:buildRooms()
	local f = self:stepFrame("Room")
	self.roomFrame = f
	self.roomTitle = text(f, { Size = UDim2.new(1, 0, 0, 32), TextSize = 26, Text = "Pick a ready room" })
	-- Reservation summary (bookings).
	local res = strip(f, UDim2.new(1, 0, 0, 74), UDim2.fromOffset(0, 38))
	self.resCard = res
	self.resLine1 = text(res, {
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.fromOffset(10, 4),
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	self.resLine2 = text(res, {
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 38),
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	local grid = frame(f, {
		Name = "Grid",
		Size = UDim2.new(1, 0, 0, 200),
		Position = UDim2.fromOffset(0, 122),
	})
	UiKit.make("UIGridLayout", {
		CellSize = UDim2.fromOffset(170, 190),
		CellPadding = UDim2.fromOffset(12, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	self.roomGrid = grid
	self.roomCards = {}
	self.noMatch = text(f, {
		Size = UDim2.new(1, -150, 0, 56),
		Position = UDim2.new(0, 150, 1, -62),
		TextSize = 19,
		TextColor3 = Color3.fromRGB(200, 60, 40),
		Text = "",
	})
	self:backButton(f)
end

function DeskHud:roomCard(i: number)
	local card = self.roomCards[i]
	if card then
		return card
	end
	local holder, body, grad = UiKit.chunk({
		Name = "Room" .. i,
		Parent = self.roomGrid,
		Size = UDim2.fromScale(1, 1),
		Colors = UiKit.GREEN,
		Radius = UDim.new(0, 18),
		Button = true,
		LayoutOrder = i,
	})
	local icon = Icons.create("bed", {
		Parent = body,
		Size = UDim2.fromOffset(50, 50),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 2,
	})
	local title = UiKit.label({
		Parent = body,
		Size = UDim2.new(1, -10, 0, 32),
		Position = UDim2.fromOffset(5, 62),
		TextSize = 26,
		Text = "",
		ZIndex = 2,
	})
	local sub = UiKit.label({
		Parent = body,
		Size = UDim2.new(1, -10, 0, 26),
		Position = UDim2.fromOffset(5, 94),
		TextSize = 20,
		Text = "",
		ZIndex = 2,
	})
	local status = UiKit.label({
		Parent = body,
		Size = UDim2.new(1, -10, 0, 30),
		Position = UDim2.fromOffset(5, 140),
		TextSize = 21,
		Text = "",
		ZIndex = 2,
	})
	card = { holder = holder, body = body, grad = grad, icon = icon, title = title, sub = sub, status = status }
	UiKit.pressable(holder, body, function()
		local r = card.room
		if r and r.selectable then
			self:send("DeskRoom", { roomId = r.id })
		else
			UiKit.play("error")
			UiKit.wiggle(holder, 4, 0.3)
		end
	end)
	self.roomCards[i] = card
	return card
end

function DeskHud:buildPayment()
	local f = self:stepFrame("Payment")
	self.payFrame = f
	-- Summary.
	local sum = strip(f, UDim2.new(1, 0, 0, 50), UDim2.fromOffset(0, 0))
	self.paySummary = text(sum, {
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	-- Method tabs.
	self.cashTab = UiKit.button(
		f,
		"Cash",
		UDim2.fromOffset(150, 48),
		UDim2.fromOffset(0, 60),
		UiKit.GREEN,
		"CASH",
		function()
			self:send("DeskMethod", { method = "Cash" })
		end,
		"coin"
	)
	self.cardTab = UiKit.button(
		f,
		"Card",
		UDim2.fromOffset(150, 48),
		UDim2.fromOffset(162, 60),
		UiKit.BLUE,
		"CARD",
		function()
			self:send("DeskMethod", { method = "Card" })
		end,
		"sparkle"
	)

	-- Cash register.
	local cash = frame(f, { Name = "Register", Size = UDim2.new(1, 0, 1, -118), Position = UDim2.fromOffset(0, 118) })
	self.cashFrame = cash
	local vw = (RIGHT_W - 20) / 3
	local function valueBox(i, caption)
		local box = strip(cash, UDim2.fromOffset(vw, 66), UDim2.fromOffset((i - 1) * (vw + 10), 0))
		text(box, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 4), TextSize = 17, Text = caption })
		return text(
			box,
			{ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 26), TextSize = 30, Text = "" }
		)
	end
	self.dueText = valueBox(1, "Amount Due")
	self.givesText = valueBox(2, "Guest Gives")
	self.changeText = valueBox(3, "Change Selected")
	self.changeList = text(cash, {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 70),
		TextSize = 18,
		Text = "",
	})
	self.noteButtons = {}
	local nw = (RIGHT_W - 30) / 4
	for i = 1, 4 do
		local b = UiKit.button(
			cash,
			"Note" .. i,
			UDim2.fromOffset(nw, 52),
			UDim2.fromOffset((i - 1) * (nw + 10), 98),
			UiKit.GREEN,
			"",
			function()
				self:addNote(i)
			end
		)
		b.label.TextSize = 26
		self.noteButtons[i] = b
	end
	local tw = (RIGHT_W - 20) / 3
	UiKit.button(cash, "Undo", UDim2.fromOffset(tw, 44), UDim2.fromOffset(0, 160), UiKit.ORANGE, "UNDO", function()
		table.remove(self.change)
		self:renderChange()
	end, "arrowRight").icon.frame.Rotation =
		180
	UiKit.button(cash, "Clear", UDim2.fromOffset(tw, 44), UDim2.fromOffset(tw + 10, 160), UiKit.RED, "CLEAR", function()
		self.change = {}
		self:renderChange()
	end, "cross")
	UiKit.button(
		cash,
		"NoChange",
		UDim2.fromOffset(tw, 44),
		UDim2.fromOffset(2 * (tw + 10), 160),
		UiKit.PURPLE,
		"NO CHANGE",
		function()
			self.change = {}
			self:renderChange()
			self:confirm()
		end,
		"check"
	).label.TextSize =
		18
	self.hintText = text(cash, {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 208),
		TextSize = 17,
		TextColor3 = Color3.fromRGB(40, 120, 60),
		Text = "",
	})

	-- Card / online info (replaces the register).
	self.payInfo = text(f, {
		Size = UDim2.new(1, -20, 0, 120),
		Position = UDim2.fromOffset(10, 150),
		TextSize = 28,
		Text = "",
	})

	self:backButton(f)
	self.confirmButton = UiKit.button(
		f,
		"Confirm",
		UDim2.new(1, -150, 0, 56),
		UDim2.new(0, 150, 1, -60),
		UiKit.GOLD,
		"GIVE CHANGE & ISSUE KEY",
		function()
			self:confirm()
		end,
		"key"
	)
	self.confirmButton.label.TextSize = 21
end

function DeskHud:bindKeyboard()
	local digits = {}
	local names = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
	for i, name in ipairs(names) do
		digits[Enum.KeyCode[name]] = tostring(i - 1)
	end
	local kp = {
		KeypadZero = "0",
		KeypadOne = "1",
		KeypadTwo = "2",
		KeypadThree = "3",
		KeypadFour = "4",
		KeypadFive = "5",
		KeypadSix = "6",
		KeypadSeven = "7",
		KeypadEight = "8",
		KeypadNine = "9",
	}
	for name, d in pairs(kp) do
		digits[Enum.KeyCode[name]] = d
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not self.panel.Visible or not self.codeFrame.Visible then
			return
		end
		local d = digits[input.KeyCode]
		if d then
			self:keypad(d)
		elseif input.KeyCode == Enum.KeyCode.Backspace then
			self:keypad("DEL")
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			self:verify()
		end
	end)
end

------------------------------------------------------------------------
-- Input
------------------------------------------------------------------------

function DeskHud:send(kind: string, payload)
	payload.kind = kind
	self.callbacks.send(payload)
end

function DeskHud:localMessage(msg: string)
	self:showMessage(msg, "error")
	UiKit.play("error")
end

function DeskHud:keypad(k: string)
	if k == "CLR" then
		self.code = ""
	elseif k == "DEL" then
		self.code = self.code:sub(1, -2)
	elseif #self.code < 4 then
		self.code ..= k
		UiKit.play("click")
	end
	self:renderCode()
end

function DeskHud:verify()
	if #self.code ~= 4 then
		self:localMessage("Enter all 4 digits.")
		return
	end
	self:send("DeskVerify", { code = self.code })
end

function DeskHud:addNote(i: number)
	local v = self.view
	local notes = v and v.denominations
	if not notes or not notes[i] then
		return
	end
	if #self.change >= 20 then
		return
	end
	table.insert(self.change, notes[i])
	UiKit.play("coin")
	UiKit.pop(self.noteButtons[i].holder, 0.1)
	self:renderChange()
end

function DeskHud:confirm()
	local v = self.view
	if not v or v.step ~= "Payment" then
		return
	end
	if v.method == "Cash" and v.given and v.due and v.given < v.due then
		self:localMessage(("The guest is $%d short. Try Card."):format(v.due - v.given))
		return
	end
	-- One transaction id per attempt; a double click resends the same id.
	if not self.pendingTx then
		self.txCounter += 1
		self.pendingTx = os.time() * 1000 + self.txCounter
	end
	self:send("DeskConfirm", { txId = self.pendingTx, change = table.clone(self.change) })
end

------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------

function DeskHud:open(info)
	info = info or {}
	self.mode = if info.busy then "busy" else "owner"
	self.busyBy = info.by
	self.sawOpen = false
	self.code = ""
	self.change = {}
	self.pendingTx = nil
	self.lastSeq = (self.view and self.view.message and self.view.message.seq) or self.lastSeq
	self.screen:open(self.panel)
	self:render()
end

function DeskHud:close()
	if self.panel.Visible then
		self.screen:close(self.panel)
	end
end

function DeskHud:onClosed()
	if self.mode == "owner" then
		self:send("DeskClose", {})
	end
	self.mode = nil
end

function DeskHud:isOpen(): boolean
	return self.panel.Visible
end

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

function DeskHud:showMessage(msg: string?, kind: string?)
	if not msg or msg == "" then
		self.msgHolder.Visible = false
		return
	end
	self.msgHolder.Visible = true
	self.msgText.Text = msg
	local ok = kind == "ok"
	UiKit.setColors(self.msgGrad, if ok then UiKit.GREEN elseif kind == "info" then UiKit.BLUE else UiKit.RED)
	self.msgIcon:set(if ok then "check" elseif kind == "info" then "bell" else "warning")
	UiKit.pop(self.msgHolder, 0.06)
end

function DeskHud:setState(s)
	local v = s and s.desk
	self.view = v
	if not self:isOpen() then
		return
	end
	if self.mode == "owner" then
		if v and v.open then
			self.sawOpen = true
		elseif self.sawOpen then
			-- The server released the desk (walked away, timeout, closing).
			self:close()
			return
		end
	elseif self.mode == "busy" and v and v.open then
		self.mode = "owner"
	end
	self:render()
end

local function showOnly(self, which)
	for _, f in ipairs({ self.statusFrame, self.startFrame, self.codeFrame, self.roomFrame, self.payFrame }) do
		f.Visible = f == which
	end
end

function DeskHud:renderStatus(key: string, subOverride: string?)
	local t = STATUS_TEXT[key]
	self.statusTitle.Text = t[1]
	self.statusSub.Text = subOverride or t[2]
	self.statusIcon:set(t[3])
	showOnly(self, self.statusFrame)
end

function DeskHud:render()
	local v = self.view
	if self.mode == "busy" or (v and v.busy and not v.open) then
		self.nightText.Text = ("NIGHT %d"):format(v and v.night or 1)
		self.queueText.Text = ("QUEUE %d"):format(v and v.queueLength or 0)
		self.guestCard.Visible = false
		self.msgHolder.Visible = false
		self:renderStatus(
			"Busy",
			("%s is using the front desk. Help with rooms meanwhile!"):format(self.busyBy or "Someone")
		)
		return
	end
	if not v or not v.open then
		showOnly(self, nil)
		return
	end
	self.nightText.Text = ("NIGHT %d"):format(v.night)
	self.queueText.Text = ("QUEUE %d"):format(v.queueLength)

	-- Guest card.
	local g = v.guest
	self.guestCard.Visible = true
	local hasGuest = g ~= nil and v.status == "Active"
	self.guestName.Text = if hasGuest then g.name else ""
	self.guestLine.Parent.Visible = hasGuest
	self.guestLine.Text = if hasGuest then ('"%s"'):format(g.line) else ""
	self.codeChip.Visible = hasGuest and g.code ~= nil
	self.codeText.Text = if hasGuest and g.code then g.code else ""
	self.noGuestText.Visible = not hasGuest
	self.patienceFill.Parent.Visible = hasGuest
	self.patienceText.Visible = hasGuest
	self.patienceIcon.frame.Visible = hasGuest

	-- Message line (server message first, then notices).
	local msg = v.message
	if msg and msg.seq ~= self.lastSeq then
		self.lastSeq = msg.seq
		self.pendingTx = nil -- the server answered the last attempt
		self:showMessage(msg.text, msg.kind)
		UiKit.play(if msg.kind == "ok" then "success" else "error")
		if msg.kind == "ok" then
			self.change = {}
			self.code = ""
		end
	elseif not msg then
		if v.notice == "GuestLeft" then
			self:showMessage("The guest left. Their transaction was cancelled.", "info")
		elseif v.notice == "RoomUnavailable" then
			self:showMessage("Room no longer available. Pick another room.", "error")
		else
			self.msgHolder.Visible = false
		end
	end

	if v.status ~= "Active" then
		self:renderStatus(v.status)
		return
	end

	if v.step == "Start" then
		showOnly(self, self.startFrame)
		self.code = ""
	elseif v.step == "Code" then
		showOnly(self, self.codeFrame)
		self:renderCode()
	elseif v.step == "Room" then
		showOnly(self, self.roomFrame)
		self:renderRooms(v)
	elseif v.step == "Payment" then
		showOnly(self, self.payFrame)
		self:renderPayment(v)
	end
end

function DeskHud:renderCode()
	for i, box in ipairs(self.digitBoxes) do
		box.Text = self.code:sub(i, i)
	end
end

function DeskHud:renderRooms(v)
	local r = v.reservation
	self.resCard.Visible = r ~= nil
	if r then
		self.resLine1.Text = ("%s  ·  %s room  ·  %s"):format(r.name, r.roomType, r.payment)
		self.resLine2.Text = ("Total $%d   Paid $%d   Due $%d"):format(r.total, r.paid, r.remaining)
		self.roomTitle.Text = "Reservation found! Pick a ready room"
		self.roomGrid.Position = UDim2.fromOffset(0, 122)
	else
		self.roomTitle.Text = "Pick a ready room and rate"
		self.roomGrid.Position = UDim2.fromOffset(0, 46)
	end
	for i, room in ipairs(v.rooms or {}) do
		local card = self:roomCard(i)
		card.room = room
		card.title.Text = ("Room %d"):format(room.number)
		card.sub.Text = ("%s  ·  $%d"):format(room.type, room.rate)
		card.status.Text = room.status:upper()
		card.icon:set(ROOM_ICONS[room.status] or "bed")
		local colors = if room.selectable then UiKit.GREEN else (ROOM_COLORS[room.status] or UiKit.GREY)
		if not room.selectable and room.status == "Ready" then
			colors = UiKit.GREY -- ready, but the wrong type for this booking
			card.status.Text = "WRONG TYPE"
		end
		UiKit.setColors(card.grad, colors)
		card.holder.Visible = true
	end
	if v.noMatch then
		self.noMatch.Text = if r
			then ("No matching room ready. Clean a %s room, then come back."):format(r.roomType)
			else "No matching room ready. Clean a room, then come back."
	else
		self.noMatch.Text = ""
	end
end

function DeskHud:renderPayment(v)
	local key = ("%s:%s:%s"):format(tostring(v.guest and v.guest.id), tostring(v.roomId), tostring(v.method))
	if key ~= self.changeKey then
		self.changeKey = key
		self.change = {}
		self.pendingTx = nil
	end
	local room = nil
	for _, r in ipairs(v.rooms or {}) do
		if r.id == v.roomId then
			room = r
		end
	end
	self.paySummary.Text = ("Room %d  ·  %s  ·  Amount Due $%d"):format(
		room and room.number or 0,
		room and room.type or "",
		v.due or 0
	)
	local methods = v.guest and v.guest.methods or {}
	local paid = (v.due or 0) <= 0
	local hasCash, hasCard = table.find(methods, "Cash") ~= nil, table.find(methods, "Card") ~= nil
	self.cashTab.holder.Visible = not paid and hasCash
	self.cardTab.holder.Visible = not paid and hasCard
	UiKit.setColors(self.cashTab.grad, if v.method == "Cash" then UiKit.GREEN else UiKit.GREY)
	UiKit.setColors(self.cardTab.grad, if v.method == "Card" then UiKit.BLUE else UiKit.GREY)

	local notes = v.denominations or {}
	for i, b in ipairs(self.noteButtons) do
		b.label.Text = if notes[i] then ("$%d"):format(notes[i]) else ""
	end

	if paid then
		self.cashFrame.Visible = false
		self.payInfo.Visible = true
		self.payInfo.Text = "PAID ONLINE\nNothing to collect. Hand over the key!"
		self.confirmButton.label.Text = "ISSUE KEY"
	elseif v.method == "Card" then
		self.cashFrame.Visible = false
		self.payInfo.Visible = true
		self.payInfo.Text = ("Card payment: $%d\nTap to charge the card."):format(v.due)
		self.confirmButton.label.Text = "CHARGE CARD & ISSUE KEY"
	else
		self.cashFrame.Visible = true
		self.payInfo.Visible = false
		self.confirmButton.label.Text = "GIVE CHANGE & ISSUE KEY"
		self.dueText.Text = ("$%d"):format(v.due or 0)
		self.givesText.Text = ("$%d"):format(v.given or 0)
		if v.given and v.due and v.given < v.due then
			self.hintText.TextColor3 = Color3.fromRGB(200, 60, 40)
			self.hintText.Text = if hasCard
				then ("The guest is $%d short. Switch to CARD."):format(v.due - v.given)
				else ("The guest is $%d short."):format(v.due - v.given)
		elseif v.changeHint then
			self.hintText.TextColor3 = Color3.fromRGB(40, 120, 60)
			self.hintText.Text = ("Tip: change = Guest Gives - Amount Due = $%d"):format(v.changeHint)
		else
			self.hintText.Text = ""
		end
		self:renderChange()
	end
end

function DeskHud:renderChange()
	local sum = 0
	local parts = {}
	for _, n in ipairs(self.change) do
		sum += n
		table.insert(parts, "$" .. n)
	end
	self.changeText.Text = ("$%d"):format(sum)
	self.changeList.Text = if #parts > 0 then table.concat(parts, " + ") else "No change selected"
end

-- Patience bar, every frame.
function DeskHud:tick()
	if not self:isOpen() then
		return
	end
	local v = self.view
	local g = v and v.guest
	if not (g and g.patienceEndsAt) then
		return
	end
	local left = math.max(0, g.patienceEndsAt - Workspace:GetServerTimeNow())
	local total = g.patienceTotal
	if not total then
		total = self.patienceTotals[g.id]
		if not total or left > total then
			total = math.max(left, 1)
			self.patienceTotals[g.id] = total
		end
	end
	local frac = math.clamp(left / total, 0, 1)
	self.patienceFill.Size = UDim2.fromScale(frac, 1)
	UiKit.setColors(self.patienceGrad, if frac > 0.5 then UiKit.GREEN elseif frac > 0.25 then UiKit.GOLD else UiKit.RED)
	self.patienceText.Text = ("Leaves in %ds"):format(math.ceil(left))
end

return DeskHud
