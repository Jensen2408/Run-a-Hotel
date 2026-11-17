--!nonstrict
--[[
	HUD for Run a Motel. Display only: every number comes from the server
	snapshot. Layout is authored for 1280x720 and scaled with UIScale so it
	stays usable on phones (big buttons, nothing in the thumbstick / jump
	corners).
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Hud = {}
Hud.__index = Hud

local FONT = Enum.Font.GothamBold
local FONT_BODY = Enum.Font.Gotham
local BG = Color3.fromRGB(22, 22, 30)
local GREEN = Color3.fromRGB(46, 160, 80)
local AMBER = Color3.fromRGB(215, 150, 35)
local RED = Color3.fromRGB(200, 55, 55)
local BLUE = Color3.fromRGB(55, 100, 185)
local GREY = Color3.fromRGB(70, 70, 82)

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = parent
end

local function pad(parent, px)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.Parent = parent
end

local function frame(props)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = BG
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	for k, v in pairs(props) do
		if k ~= "Parent" then
			f[k] = v
		end
	end
	f.Parent = props.Parent
	return f
end

local function text(props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Font = FONT
	t.TextSize = 18
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextWrapped = true
	for k, v in pairs(props) do
		if k ~= "Parent" then
			t[k] = v
		end
	end
	t.Parent = props.Parent
	return t
end

local function button(props)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = GREEN
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = FONT
	b.TextSize = 20
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	for k, v in pairs(props) do
		if k ~= "Parent" then
			b[k] = v
		end
	end
	corner(b, 10)
	b.Parent = props.Parent
	return b
end

local function list(parent, direction, paddingPx)
	local l = Instance.new("UIListLayout")
	l.FillDirection = direction or Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, paddingPx or 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

local function fmtTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

function Hud.new(playerGui: PlayerGui, config, callbacks)
	local self = setmetatable({}, Hud)
	local roomCount = config.roomCount
	self.rent = config.economy.rent
	self.callbacks = callbacks
	self.state = nil
	self.roomCount = roomCount

	local gui = Instance.new("ScreenGui")
	gui.Name = "MotelHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	self.gui = gui

	-- Scale everything from a 1280x720 design.
	local root = frame({
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = root
	local function rescale()
		local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		local s = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.55, 1.3)
		uiScale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	rescale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	self.root = root

	-- Top bar ----------------------------------------------------------------
	local top = frame({
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(900, 52),
		Parent = root,
	})
	corner(top, 12)
	pad(top, 8)
	list(top, Enum.FillDirection.Horizontal, 8).VerticalAlignment = Enum.VerticalAlignment.Center
	local function chip(name, width, order)
		local c = frame({
			Name = name,
			Size = UDim2.fromOffset(width, 36),
			BackgroundColor3 = GREY,
			BackgroundTransparency = 0,
			LayoutOrder = order,
			Parent = top,
		})
		corner(c, 8)
		local t = text({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 18,
			Text = "",
			Parent = c,
		})
		return c, t
	end
	self.phaseChip, self.phaseText = chip("Phase", 220, 1)
	self.nightChip, self.nightText = chip("Night", 110, 2)
	self.cashChip, self.cashText = chip("Cash", 120, 3)
	self.billChip, self.billText = chip("Bill", 120, 4)
	self.stockChip, self.stockText = chip("Stock", 170, 5)
	self.powerChip, self.powerText = chip("Power", 110, 6)

	-- Preparation / info panel under the top bar --------------------------------
	local info = frame({
		Name = "Info",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(640, 64),
		Parent = root,
	})
	corner(info, 10)
	pad(info, 8)
	self.info = info
	self.infoText = text({
		Size = UDim2.new(1, -150, 1, 0),
		TextSize = 16,
		Font = FONT_BODY,
		Text = "",
		Parent = info,
	})
	self.readyButton = button({
		Name = "Ready",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(140, 46),
		Text = "Ready",
		Parent = info,
	})
	self.readyButton.Activated:Connect(function()
		self.callbacks.onReady()
	end)

	-- Rooms panel (left) ---------------------------------------------------------
	local rooms = frame({
		Name = "Rooms",
		Position = UDim2.fromOffset(10, 140),
		Size = UDim2.fromOffset(270, 40 + 44 * roomCount),
		Parent = root,
	})
	corner(rooms, 10)
	pad(rooms, 8)
	list(rooms, Enum.FillDirection.Vertical, 6)
	text({ Size = UDim2.new(1, 0, 0, 22), Text = "ROOMS", TextSize = 18, LayoutOrder = 0, Parent = rooms })
	self.roomRows = {}
	for i = 1, roomCount do
		local row = frame({
			Name = "Room" .. i,
			Size = UDim2.new(1, 0, 0, 38),
			BackgroundColor3 = GREY,
			BackgroundTransparency = 0,
			LayoutOrder = i,
			Parent = rooms,
		})
		corner(row, 8)
		pad(row, 6)
		self.roomRows[i] = {
			frame = row,
			text = text({ Size = UDim2.fromScale(1, 1), TextSize = 15, Text = "Room " .. i, Parent = row }),
		}
	end

	-- Carry + queue panel ---------------------------------------------------------
	local status = frame({
		Name = "Status",
		Position = UDim2.fromOffset(10, 150 + 40 + 44 * roomCount),
		Size = UDim2.fromOffset(270, 92),
		Parent = root,
	})
	corner(status, 10)
	pad(status, 8)
	list(status, Enum.FillDirection.Vertical, 4)
	self.carryText = text({ Size = UDim2.new(1, 0, 0, 24), TextSize = 16, Text = "", LayoutOrder = 1, Parent = status })
	self.queueText = text({ Size = UDim2.new(1, 0, 0, 24), TextSize = 16, Text = "", LayoutOrder = 2, Parent = status })
	self.teamText = text({
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 14,
		Font = FONT_BODY,
		Text = "",
		LayoutOrder = 3,
		Parent = status,
	})

	-- Alert banner ----------------------------------------------------------------
	self.alert = text({
		Name = "Alert",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 140),
		Size = UDim2.fromOffset(520, 44),
		BackgroundColor3 = RED,
		BackgroundTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 22,
		Text = "",
		Visible = false,
		Parent = root,
	})
	corner(self.alert, 10)

	-- Toasts (bottom centre, above mobile controls) ----------------------------------
	local toasts = frame({
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(560, 200),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local tl = list(toasts, Enum.FillDirection.Vertical, 6)
	tl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	self.toasts = toasts
	self.toastOrder = 0

	-- Check-in room picker -------------------------------------------------------------
	local picker = frame({
		Name = "CheckInPicker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 140 + 62 * roomCount),
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = root,
	})
	corner(picker, 14)
	pad(picker, 12)
	list(picker, Enum.FillDirection.Vertical, 8)
	self.pickerTitle = text({
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Assign a room",
		LayoutOrder = 0,
		Parent = picker,
	})
	self.pickerSub = text({
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 16,
		Font = FONT_BODY,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		LayoutOrder = 1,
		Parent = picker,
	})
	self.pickerButtons = {}
	for i = 1, roomCount do
		local b = button({
			Name = "Room" .. i,
			Size = UDim2.new(1, 0, 0, 54),
			Text = "Room " .. i,
			LayoutOrder = 1 + i,
			Parent = picker,
		})
		b.Activated:Connect(function()
			local s = self.state
			if s and s.rooms[i] and s.rooms[i].ready then
				self.callbacks.onCheckIn(i)
				self:closePicker()
			end
		end)
		self.pickerButtons[i] = b
	end
	local cancel = button({
		Name = "Cancel",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = GREY,
		Text = "Cancel",
		LayoutOrder = 100,
		Parent = picker,
	})
	cancel.Activated:Connect(function()
		self:closePicker()
	end)
	self.picker = picker

	-- Report / run-ended modal -------------------------------------------------------------
	local report = frame({
		Name = "Report",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 420),
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = root,
	})
	corner(report, 14)
	pad(report, 14)
	self.reportTitle = text({
		Size = UDim2.new(1, 0, 0, 34),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		Parent = report,
	})
	self.reportBody = text({
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 1, -110),
		TextSize = 18,
		Font = FONT_BODY,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = true,
		Text = "",
		Parent = report,
	})
	self.restartButton = button({
		Name = "Restart",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(240, 54),
		Text = "Restart Run",
		Visible = false,
		Parent = report,
	})
	self.restartButton.Activated:Connect(function()
		self.callbacks.onRestart()
	end)
	self.report = report

	return self
end

function Hud:toast(message: string, kind: string?)
	local color = BG
	if kind == "ok" then
		color = GREEN
	elseif kind == "error" then
		color = RED
	elseif kind == "alert" then
		color = AMBER
	end
	self.toastOrder += 1
	local t = text({
		Size = UDim2.fromOffset(540, 34),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 18,
		Text = message,
		LayoutOrder = self.toastOrder,
		Parent = self.toasts,
	})
	corner(t, 8)
	local children = {}
	for _, c in ipairs(self.toasts:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(children, c)
		end
	end
	table.sort(children, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #children > 4 do
		local oldest = table.remove(children, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(3.5, function()
		if t.Parent then
			local tween =
				TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			t:Destroy()
		end
	end)
end

function Hud:openPicker()
	self.picker.Visible = true
	self:renderPicker()
end

function Hud:closePicker()
	self.picker.Visible = false
end

function Hud:renderPicker()
	local s = self.state
	if not s or not self.picker.Visible then
		return
	end
	if s.phase ~= "Night" then
		self:closePicker()
		return
	end
	local anyReady = false
	for i, b in ipairs(self.pickerButtons) do
		local r = s.rooms[i]
		if r then
			if r.ready then
				anyReady = true
				b.Text = ("Room %d  READY  (+$%d)"):format(i, self.rent)
				b.BackgroundColor3 = GREEN
				b.AutoButtonColor = true
			else
				local why = {}
				if r.occupied then
					table.insert(why, "occupied")
				end
				if r.trash then
					table.insert(why, "trash")
				end
				if r.sheetsDirty then
					table.insert(why, "sheets")
				end
				if r.acBroken then
					table.insert(why, "AC broken")
				end
				b.Text = ("Room %d  (%s)"):format(i, table.concat(why, ", "))
				b.BackgroundColor3 = GREY
				b.AutoButtonColor = false
			end
		end
	end
	self.pickerSub.Text = if anyReady
		then "Pick a ready room for the next guest."
		else "No room is ready. Clean one first!"
end

function Hud:setState(s)
	self.state = s
	local P = s.phase

	-- Top bar
	self.nightText.Text = ("Night %d/%d"):format(s.night, s.totalNights)
	self.cashText.Text = ("$%d"):format(s.cash)
	self.cashChip.BackgroundColor3 = if s.cash >= s.bill then GREEN else AMBER
	self.billText.Text = ("Bill $%d"):format(s.bill)
	self.stockText.Text = ("Sheets %d  Towels %d"):format(s.stock.Sheet, s.stock.Towel)
	self.stockChip.BackgroundColor3 = if s.stock.Sheet == 0 then RED else GREY
	self.powerText.Text = if not s.power then "POWER OUT" elseif s.rain then "Rain" else "Power OK"
	self.powerChip.BackgroundColor3 = if not s.power then RED elseif s.rain then BLUE else GREY

	-- Info panel
	if P == "Preparation" then
		self.info.Visible = true
		self.readyButton.Visible = true
		self.readyButton.Text = if s.isReady then ("Ready %d/%d"):format(s.readyCount, s.playerCount) else "Ready"
		self.readyButton.BackgroundColor3 = if s.isReady then GREY else GREEN
		local scaleNote = if s.planPlayers > 1 then (" (%d players)"):format(s.planPlayers) else ""
		self.infoText.Text = ("PREP for Night %d%s: ~%d guests, bill $%d.\n%s"):format(
			s.night,
			scaleNote,
			s.plannedGuests,
			s.bill,
			s.forecast
		)
	elseif P == "Night" or P == "Closing" then
		self.info.Visible = true
		self.readyButton.Visible = false
		local ns = s.nightStats
		self.infoText.Text = ("%s  Guests %d/%d   Rent $%d  Tips $%d   Walkouts %d"):format(
			if P == "Closing" then "CLOSING: finish up!" else "NIGHT",
			ns.arrivals,
			s.plannedGuests,
			ns.rent,
			ns.tips,
			ns.walkouts
		)
	else
		self.info.Visible = false
	end

	-- Rooms
	for i, row in ipairs(self.roomRows) do
		local r = s.rooms[i]
		if r then
			if r.ready then
				row.text.Text = ("Room %d: READY"):format(i)
				row.frame.BackgroundColor3 = GREEN
			elseif r.occupied then
				row.text.Text = ("Room %d: Occupied%s"):format(i, if r.towelRequest then " - wants TOWEL" else "")
				row.frame.BackgroundColor3 = if r.towelRequest then AMBER else BLUE
			else
				local todo = {}
				if r.trash then
					table.insert(todo, "trash")
				end
				if r.sheetsDirty then
					table.insert(todo, "sheets")
				end
				if r.acBroken then
					table.insert(todo, "fix AC")
				end
				row.text.Text = ("Room %d: %s"):format(i, table.concat(todo, ", "))
				row.frame.BackgroundColor3 = if r.acBroken then RED else AMBER
			end
		end
	end

	-- Carry / queue / team
	local carry = if #s.carry > 0 then table.concat(s.carry, ", ") else "nothing"
	self.carryText.Text = ("Carrying (%d/%d): %s"):format(#s.carry, s.carryCapacity, carry)
	self.queueText.Text = ("Queue: %d waiting"):format(s.queueLength)
	self.teamText.Text = ("Players %d   Trolley: %s   Best: %d nights"):format(
		s.playerCount,
		if s.trolley then "yes" else "no",
		s.bestNights
	)

	-- Alert banner
	if not s.power and (P == "Night" or P == "Closing" or P == "Preparation") then
		self.alert.Text = "POWER OUT - reset the breaker (lobby)"
		self.alert.Visible = true
	else
		self.alert.Visible = false
	end

	-- Report / RunEnded
	if (P == "Report" or P == "RunEnded") and s.report then
		local r = s.report
		self.report.Visible = true
		local result
		if r.passed then
			result = ('<font color="#5fd77f">Bill paid. Nights survived: %d</font>'):format(r.nightsSurvived)
		else
			result = ('<font color="#ff6b6b">Short by $%d. The motel closes.</font>'):format(r.shortfall)
		end
		self.reportBody.Text = table.concat({
			("Rent: <b>$%d</b>"):format(r.rent),
			("Tips: <b>$%d</b>"):format(r.tips),
			("Purchases: <b>-$%d</b>"):format(r.purchases),
			("Bill: <b>-$%d</b>"):format(r.bill),
			("Cash before bill: $%d   after: <b>$%d</b>"):format(r.cashBefore, r.cashAfter),
			("Guests served %d / planned %d"):format(r.served, r.guestsPlanned),
			("Walkouts %d   Unserved %d   Missed towels %d"):format(r.walkouts, r.unserved, r.missedTowels),
			"",
			result,
		}, "\n")
		if P == "RunEnded" then
			if s.complete then
				self.reportTitle.Text = "PROTOTYPE COMPLETE!"
			else
				self.reportTitle.Text = ("Run over - %d night(s) survived"):format(s.nightsSurvived)
			end
			self.restartButton.Visible = true
		else
			self.reportTitle.Text = ("Night %d Report"):format(r.night)
			self.restartButton.Visible = false
		end
	else
		self.report.Visible = false
	end

	self:renderPicker()
end

-- Called every frame for the countdown.
function Hud:tick()
	local s = self.state
	if not s then
		return
	end
	local label = s.phase
	if s.phase == "RunEnded" then
		label = if s.complete then "Complete" else "Run Over"
	end
	if s.phaseEndsAt then
		local left = s.phaseEndsAt - Workspace:GetServerTimeNow()
		self.phaseText.Text = ("%s  %s"):format(label, fmtTime(left))
		self.phaseChip.BackgroundColor3 = if s.phase == "Night" and left < 30 then AMBER else GREY
	else
		self.phaseText.Text = label
	end
	if self.picker.Visible and s.frontPatienceEndsAt then
		local left = s.frontPatienceEndsAt - Workspace:GetServerTimeNow()
		self.pickerTitle.Text = ("Assign a room  (guest waits %ds)"):format(math.max(0, math.ceil(left)))
	end
end

return Hud
