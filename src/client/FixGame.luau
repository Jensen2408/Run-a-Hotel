--!nonstrict
--[[
	Repair minigames, opened by the server (OpenFix remote) when a player
	uses a broken AC or the tripped breaker panel. The client only plays the
	game; the server applies the repair when the win arrives (FinishFix) for
	an open session that lasted long enough.

	AC: connect each loose wire to the socket of the same colour (tap the
	    wire, then the socket).
	Sheets: tap the 4 corners to pull off the dirty sheet, then tap the
	    wrinkles away on the clean one.
	Breaker: flip the tripped (red) switches up, then press PULL while the
	    needle is inside the green zone.

	The panel closes by itself when someone else fixed it, the phase ends or
	the player walks away.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UiKit = require(script.Parent:WaitForChild("UiKit"))
local Icons = require(script.Parent:WaitForChild("Icons"))

local make, label, chunk, tween = UiKit.make, UiKit.label, UiKit.chunk, UiKit.tween

local WIRE_COLORS = {
	{ name = "Red", c = Color3.fromRGB(232, 64, 56) },
	{ name = "Blue", c = Color3.fromRGB(52, 128, 230) },
	{ name = "Yellow", c = Color3.fromRGB(250, 206, 50) },
	{ name = "Green", c = Color3.fromRGB(70, 186, 70) },
}
local BOARD = Vector2.new(500, 250) -- play area inside the panel
local PANEL = Vector2.new(580, 392)
local WALK_AWAY = 22 -- studs from where the repair started

local FixGame = {}
FixGame.__index = FixGame

local function shuffled(list)
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = math.random(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

function FixGame.new(playerGui: PlayerGui, deps, config)
	local self = setmetatable({}, FixGame)
	self.send = deps.send
	self.config = config
	self.session = nil
	self.closing = false

	local screen = UiKit.screen(playerGui, "FixGame", 9, true)
	self.screen = screen
	local holder, body = screen:modal("Fix", PANEL, "REPAIR")
	self.panel = holder
	local ribbon = holder:FindFirstChild("Ribbon"):FindFirstChild("Body")
	self.title = ribbon:FindFirstChildOfClass("TextLabel")
	self.titleIcon = Icons.create("wrench", {
		Parent = ribbon,
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 2,
	})
	self.hint = label({
		Parent = body,
		Size = UDim2.new(1, -60, 0, 50),
		Position = UDim2.fromOffset(30, 34),
		TextSize = 20,
		TextColor3 = UiKit.TEXT_DARK,
		Stroke = 0,
		Text = "",
	})
	local boardHolder, board = chunk({
		Name = "Board",
		Parent = body,
		Size = UDim2.fromOffset(BOARD.X + 20, BOARD.Y + 20),
		Position = UDim2.new(0.5, 0, 0, 92),
		AnchorPoint = Vector2.new(0.5, 0),
		Colors = { Color3.fromRGB(86, 98, 112), Color3.fromRGB(58, 66, 78) },
		Shine = false,
		Radius = UDim.new(0, 16),
	})
	self.boardHolder = boardHolder
	self.area = make("Frame", {
		Name = "Area",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(BOARD.X, BOARD.Y),
		Position = UDim2.fromOffset(10, 10),
		Parent = board,
	})
	-- Win stamp over the board.
	self.stamp = label({
		Parent = body,
		Size = UDim2.fromOffset(360, 80),
		Position = UDim2.new(0.5, 0, 0, 200),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextSize = 54,
		Text = "FIXED!",
		TextColor3 = Color3.fromRGB(150, 232, 92),
		Stroke = 5,
		ZIndex = 20,
		Visible = false,
	})

	-- Closing the panel any way other than a win cancels the session.
	holder:GetPropertyChangedSignal("Visible"):Connect(function()
		if not holder.Visible and self.session then
			self:stop(true)
		end
	end)
	return self
end

function FixGame:isOpen(): boolean
	return self.session ~= nil
end

function FixGame:clearArea()
	if self.step then
		self.step:Disconnect()
		self.step = nil
	end
	for _, c in ipairs(self.area:GetChildren()) do
		c:Destroy()
	end
	self.stamp.Visible = false
end

-- Ends the session; cancel = tell the server the game was abandoned.
function FixGame:stop(cancel: boolean)
	local s = self.session
	if not s then
		return
	end
	self.session = nil
	if self.step then
		self.step:Disconnect()
		self.step = nil
	end
	if cancel then
		self.send({ kind = "CancelFix" })
	end
	if self.panel.Visible then
		self.screen:close(self.panel)
	end
end

function FixGame:open(info)
	if typeof(info) ~= "table" or (info.fix ~= "AC" and info.fix ~= "Breaker" and info.fix ~= "Sheets") then
		return
	end
	if self.session then
		self:stop(false) -- the server replaced the old session already
	end
	self:clearArea()
	local hrp = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	self.session = {
		fix = info.fix,
		roomId = info.roomId,
		easy = info.easy == true,
		openedAt = os.clock(),
		origin = hrp and hrp.Position,
		won = false,
	}
	if info.fix == "AC" then
		self.title.Text = "FIX THE AC"
		self.titleIcon:set("wrench")
		self:buildWires(self.session)
	elseif info.fix == "Sheets" then
		self.title.Text = "MAKE THE BED"
		self.titleIcon:set("bed")
		self:buildBed(self.session)
	else
		self.titleIcon:set("lightning")
		self.title.Text = "POWER PANEL"
		self:buildBreaker(self.session)
	end
	self.screen:open(self.panel)
end

-- Win: stamp, then report (never sooner than the server's minimum time).
function FixGame:win(s)
	if s.won or self.session ~= s then
		return
	end
	s.won = true
	UiKit.play("success")
	self.hint.Text = if s.fix == "AC"
		then "The AC is running again!"
		elseif s.fix == "Sheets" then "Fresh sheets, the bed is ready!"
		else "Power restored!"
	self.stamp.Text = if s.fix == "Sheets" then "CLEAN!" else "FIXED!"
	self.stamp.Visible = true
	local sc = UiKit.scaleOf(self.stamp)
	sc.Value = 0.3
	tween(sc, 0.35, { Value = 1 }, Enum.EasingStyle.Back)
	local minimum = (self.config.minigame.minSeconds or 0) + 0.15
	local delaySec = math.max(0.7, minimum - (os.clock() - s.openedAt))
	task.delay(delaySec, function()
		if self.session ~= s then
			return
		end
		self.send({ kind = "FinishFix", fix = s.fix, roomId = s.roomId })
		self.session = nil
		self.screen:close(self.panel)
	end)
end

local function miss(gui: GuiObject)
	UiKit.play("error")
	UiKit.wiggle(gui, 8, 0.35)
end

------------------------------------------------------------------------
-- AC: wires
------------------------------------------------------------------------

-- A straight wire (rounded bar) between two points of the play area.
local function wire(parent, a: Vector2, b: Vector2, color: Color3, z: number)
	local d = b - a
	local mid = (a + b) / 2
	local bar = make("Frame", {
		Name = "Wire",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(mid.X, mid.Y),
		Size = UDim2.fromOffset(d.Magnitude, 12),
		Rotation = math.deg(math.atan2(d.Y, d.X)),
		ZIndex = z,
		Parent = parent,
	})
	UiKit.corner(bar, UDim.new(1, 0))
	UiKit.outline(bar, 2)
	return bar
end

local function terminal(parent, pos: Vector2, color: Color3, socket: boolean)
	local b = make("TextButton", {
		Name = if socket then "Socket" else "Plug",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(pos.X, pos.Y),
		Size = UDim2.fromOffset(52, 52),
		ZIndex = 5,
		Parent = parent,
	})
	UiKit.corner(b, if socket then UDim.new(0, 10) else UDim.new(1, 0))
	UiKit.outline(b, 3)
	if socket then
		-- Dark hole in the socket.
		local hole = make("Frame", {
			BackgroundColor3 = UiKit.OUTLINE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(18, 18),
			ZIndex = 6,
			Parent = b,
		})
		UiKit.corner(hole, UDim.new(1, 0))
	end
	return b
end

function FixGame:buildWires(s)
	local cfg = self.config.minigame
	local n = if s.easy then cfg.wiresEasy else cfg.wires
	n = math.clamp(n, 2, #WIRE_COLORS)
	self.hint.Text = "Tap a loose wire, then the socket of the same colour."
	local colors = {}
	for i = 1, n do
		colors[i] = WIRE_COLORS[i]
	end
	local left, right = shuffled(colors), shuffled(colors)
	local gap = BOARD.Y / n
	local plugX, socketX = 70, BOARD.X - 60
	local selected = nil
	local done = 0
	local plugs = {}
	for i, col in ipairs(left) do
		local pos = Vector2.new(plugX, gap * (i - 0.5))
		-- Loose stub from the left edge to the plug.
		wire(self.area, Vector2.new(0, pos.Y), pos, col.c, 3)
		local b = terminal(self.area, pos, col.c, false)
		plugs[i] = { button = b, color = col, pos = pos, done = false }
		b.Activated:Connect(function()
			if self.session ~= s or s.won or plugs[i].done then
				return
			end
			UiKit.play("click")
			if selected then
				selected.button:FindFirstChildOfClass("UIStroke").Color = UiKit.OUTLINE
			end
			selected = plugs[i]
			b:FindFirstChildOfClass("UIStroke").Color = UiKit.WHITE
			UiKit.pop(b, 0.2)
		end)
	end
	for i, col in ipairs(right) do
		local pos = Vector2.new(socketX, gap * (i - 0.5))
		wire(self.area, pos, Vector2.new(BOARD.X, pos.Y), col.c, 3)
		local b = terminal(self.area, pos, col.c, true)
		local used = false
		b.Activated:Connect(function()
			if self.session ~= s or s.won or used then
				return
			end
			if not selected then
				miss(b)
				self.hint.Text = "Pick a loose wire on the left first."
				return
			end
			if selected.color ~= col then
				miss(b)
				self.hint.Text = "Wrong colour! Match the wire to its socket."
				return
			end
			used = true
			selected.done = true
			selected.button:FindFirstChildOfClass("UIStroke").Color = UiKit.OUTLINE
			local w = wire(self.area, selected.pos, pos, col.c, 4)
			local full = w.Size
			w.Size = UDim2.fromOffset(0, 12)
			tween(w, 0.18, { Size = full })
			UiKit.play("pop")
			UiKit.pop(b, 0.25)
			selected = nil
			done += 1
			if done >= n then
				self:win(s)
			else
				self.hint.Text = ("%d of %d wires connected."):format(done, n)
			end
		end)
	end
end

------------------------------------------------------------------------
-- Breaker: switches + main lever
------------------------------------------------------------------------

local SWITCHES = 5
local GREEN = Color3.fromRGB(70, 186, 70)
local RED = Color3.fromRGB(214, 52, 52)

function FixGame:buildBreaker(s)
	local cfg = self.config.minigame
	local tripped = math.clamp(if s.easy then cfg.trippedEasy else cfg.tripped, 1, SWITCHES)
	self.hint.Text = "Flip the tripped (red) switches up."
	local order = {}
	for i = 1, SWITCHES do
		order[i] = i
	end
	order = shuffled(order)
	local isTripped = {}
	for i = 1, tripped do
		isTripped[order[i]] = true
	end
	local left = tripped

	-- Row of switches (top part of the board).
	local w, h = 64, 110
	local span = BOARD.X / SWITCHES
	local lever -- built below, enabled when every switch is up
	for i = 1, SWITCHES do
		local slot = make("TextButton", {
			Name = "Switch" .. i,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(40, 44, 52),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(span * (i - 0.5), 4),
			Size = UDim2.fromOffset(w, h),
			ZIndex = 4,
			Parent = self.area,
		})
		UiKit.corner(slot, UDim.new(0, 10))
		UiKit.outline(slot, 3)
		local up = not isTripped[i]
		local knob = make("Frame", {
			Name = "Knob",
			BackgroundColor3 = if up then GREEN else RED,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = if up then UDim2.new(0.5, 0, 0, 8) else UDim2.new(0.5, 0, 1, -56),
			Size = UDim2.new(1, -16, 0, 48),
			ZIndex = 5,
			Parent = slot,
		})
		UiKit.corner(knob, UDim.new(0, 8))
		UiKit.outline(knob, 2)
		slot.Activated:Connect(function()
			if self.session ~= s or s.won then
				return
			end
			if up then
				UiKit.play("click")
				UiKit.wiggle(slot, 4, 0.2)
				return
			end
			up = true
			UiKit.play("click")
			tween(knob, 0.15, { Position = UDim2.new(0.5, 0, 0, 8), BackgroundColor3 = GREEN }, Enum.EasingStyle.Back)
			UiKit.pop(slot, 0.12)
			left -= 1
			if left <= 0 then
				lever.enable()
			end
		end)
	end

	-- Main lever: needle sweeping a bar with a green zone.
	local barW, barY = BOARD.X - 170, 150
	local bar = make("Frame", {
		Name = "LeverBar",
		BackgroundColor3 = Color3.fromRGB(40, 44, 52),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, barY),
		Size = UDim2.fromOffset(barW, 40),
		ZIndex = 4,
		Parent = self.area,
	})
	UiKit.corner(bar, UDim.new(0, 10))
	UiKit.outline(bar, 3)
	local zoneW = if s.easy then cfg.zoneEasy else cfg.zone
	local zone = make("Frame", {
		Name = "Zone",
		BackgroundColor3 = GREEN,
		BorderSizePixel = 0,
		Size = UDim2.new(zoneW, 0, 1, -8),
		Position = UDim2.fromOffset(0, 4),
		ZIndex = 5,
		Parent = bar,
	})
	UiKit.corner(zone, UDim.new(0, 6))
	local needle = make("Frame", {
		Name = "Needle",
		BackgroundColor3 = UiKit.WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 8, 1, 14),
		ZIndex = 6,
		Parent = bar,
	})
	UiKit.corner(needle, UDim.new(1, 0))
	UiKit.outline(needle, 2)
	local zoneAt = 0
	local function placeZone()
		zoneAt = 0.1 + math.random() * (0.9 - zoneW - 0.1)
		zone.Position = UDim2.new(zoneAt, 0, 0, 4)
	end
	placeZone()

	local pull = UiKit.button(
		self.area,
		"Pull",
		UDim2.fromOffset(140, 56),
		UDim2.fromOffset(BOARD.X - 146, barY - 8),
		UiKit.GREY,
		"PULL!",
		function() end,
		"lightning"
	)
	local active = false
	local t = 0
	local pos = 0
	lever = {
		enable = function()
			active = true
			UiKit.setColors(pull.grad, UiKit.GOLD)
			UiKit.pop(pull.holder, 0.2)
			self.hint.Text = "Now press PULL while the needle is in the green!"
		end,
	}
	pull.body.Activated:Connect(function()
		if self.session ~= s or s.won then
			return
		end
		if not active then
			miss(pull.holder)
			self.hint.Text = "Flip every red switch up first."
			return
		end
		if pos >= zoneAt and pos <= zoneAt + zoneW then
			UiKit.play("power")
			active = false
			self:win(s)
		else
			miss(pull.holder)
			self.hint.Text = "Missed! Wait for the green zone."
			placeZone()
		end
	end)
	-- Hint row under the bar.
	label({
		Parent = self.area,
		Size = UDim2.fromOffset(barW, 30),
		Position = UDim2.fromOffset(10, barY + 52),
		TextSize = 16,
		Text = "MAIN LEVER",
		TextColor3 = Color3.fromRGB(220, 226, 236),
		Stroke = 0,
		ZIndex = 4,
	})
	self.step = RunService.RenderStepped:Connect(function(dt)
		t += dt * cfg.needleSpeed
		-- Ping-pong 0..1..0
		local k = t % 2
		pos = if k <= 1 then k else 2 - k
		needle.Position = UDim2.fromScale(pos, 0.5)
	end)
end

------------------------------------------------------------------------
-- Bed: strip the dirty sheet, smooth the clean one
------------------------------------------------------------------------

local WOOD = Color3.fromRGB(150, 96, 56)
local WOOD_DARK = Color3.fromRGB(112, 70, 40)
local MATTRESS = Color3.fromRGB(246, 236, 214)
local CLEAN = Color3.fromRGB(236, 244, 255)
local DIRTY = Color3.fromRGB(196, 184, 150)
local STAIN = Color3.fromRGB(150, 118, 70)
local WRINKLE = Color3.fromRGB(196, 210, 234)

local function box(parent, name, pos: Vector2, size: Vector2, color: Color3, z: number, radius: number?)
	local f = make("Frame", {
		Name = name,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(pos.X, pos.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = z,
		Parent = parent,
	})
	UiKit.corner(f, UDim.new(0, radius or 10))
	UiKit.outline(f, 3)
	return f
end

function FixGame:buildBed(s)
	local cfg = self.config.minigame
	local wrinkles = math.max(1, if s.easy then cfg.wrinklesEasy else cfg.wrinkles)
	self.hint.Text = "Tap the 4 corners to pull off the dirty sheet."
	local area = self.area
	-- Bed seen from above, headboard on the left.
	box(area, "Frame", Vector2.new(20, 6), Vector2.new(460, 238), WOOD, 2, 16)
	box(area, "Headboard", Vector2.new(20, 6), Vector2.new(34, 238), WOOD_DARK, 3, 12)
	box(area, "Mattress", Vector2.new(60, 18), Vector2.new(410, 214), MATTRESS, 3, 12)
	box(area, "Pillow", Vector2.new(72, 50), Vector2.new(70, 150), UiKit.WHITE, 4, 22)
	local sheetPos, sheetSize = Vector2.new(154, 22), Vector2.new(306, 206)
	local clean = box(area, "CleanSheet", sheetPos, sheetSize, CLEAN, 5, 10)
	clean.Visible = false
	local dirty = box(area, "DirtySheet", sheetPos, sheetSize, DIRTY, 6, 10)
	for i, st in ipairs({ { 70, 50, 46 }, { 190, 120, 34 }, { 120, 150, 24 } }) do
		local stain = make("Frame", {
			Name = "Stain" .. i,
			BackgroundColor3 = STAIN,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(st[1], st[2]),
			Size = UDim2.fromOffset(st[3], st[3] * 0.7),
			ZIndex = 7,
			Parent = dirty,
		})
		UiKit.corner(stain, UDim.new(1, 0))
	end

	local function smoothPhase()
		self.hint.Text = "Smooth out the wrinkles on the clean sheet!"
		clean.Visible = true
		clean.Size = UDim2.fromOffset(0, sheetSize.Y)
		tween(clean, 0.3, { Size = UDim2.fromOffset(sheetSize.X, sheetSize.Y) }, Enum.EasingStyle.Back)
		UiKit.play("sweep")
		local left = wrinkles
		local placed = {}
		for i = 1, wrinkles do
			-- Spread out: retry a few times to keep lumps apart.
			local p
			for _ = 1, 12 do
				p = Vector2.new(math.random(14, sheetSize.X - 74), math.random(14, sheetSize.Y - 44))
				local clear = true
				for _, q in ipairs(placed) do
					if (q - p).Magnitude < 64 then
						clear = false
					end
				end
				if clear then
					break
				end
			end
			table.insert(placed, p)
			local lump = make("TextButton", {
				Name = "Wrinkle" .. i,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = WRINKLE,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(p.X + 30, p.Y + 15),
				Size = UDim2.fromOffset(60, 30),
				Rotation = math.random(-25, 25),
				ZIndex = 7,
				Parent = clean,
			})
			UiKit.corner(lump, UDim.new(1, 0))
			UiKit.outline(lump, 2, Color3.fromRGB(120, 138, 172))
			-- Crease line across the lump.
			local crease = make("Frame", {
				BackgroundColor3 = Color3.fromRGB(120, 138, 172),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(0.7, 0, 0, 3),
				ZIndex = 8,
				Parent = lump,
			})
			UiKit.corner(crease, UDim.new(1, 0))
			local sc = UiKit.scaleOf(lump)
			sc.Value = 0
			tween(sc, 0.25, { Value = 1 }, Enum.EasingStyle.Back)
			local smoothed = false
			lump.Activated:Connect(function()
				if self.session ~= s or s.won or smoothed then
					return
				end
				smoothed = true
				UiKit.play("pop")
				tween(sc, 0.15, { Value = 0 }).Completed:Once(function()
					lump:Destroy()
				end)
				left -= 1
				if left <= 0 then
					self:win(s)
				else
					self.hint.Text = ("%d wrinkle%s left."):format(left, if left == 1 then "" else "s")
				end
			end)
		end
	end

	-- Corner tabs of the dirty sheet.
	local corners = 4
	local tabSize = 46
	for i, c in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
		local center = sheetPos + sheetSize * c
		local tab = make("TextButton", {
			Name = "Corner" .. i,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(236, 122, 40),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = UDim2.fromOffset(tabSize, tabSize),
			Rotation = 45,
			ZIndex = 9,
			Parent = area,
		})
		UiKit.corner(tab, UDim.new(0, 8))
		UiKit.outline(tab, 3)
		tab.Activated:Connect(function()
			if self.session ~= s or s.won or not tab.Visible then
				return
			end
			UiKit.play("click")
			local sc = UiKit.scaleOf(tab)
			tween(sc, 0.12, { Value = 0 }).Completed:Once(function()
				tab.Visible = false
			end)
			UiKit.wiggle(dirty, 2, 0.2)
			corners -= 1
			if corners <= 0 then
				self.hint.Text = "Dirty sheet off!"
				UiKit.play("whooshOut")
				tween(dirty, 0.35, {
					Position = UDim2.fromOffset(sheetPos.X + 380, sheetPos.Y + 30),
					Rotation = 18,
					BackgroundTransparency = 1,
				}).Completed:Once(function()
					dirty:Destroy()
					if self.session == s then
						smoothPhase()
					end
				end)
				for _, st in ipairs(dirty:GetChildren()) do
					if st:IsA("Frame") then
						tween(st, 0.3, { BackgroundTransparency = 1 })
					end
				end
			else
				self.hint.Text = ("%d corner%s left."):format(corners, if corners == 1 then "" else "s")
			end
		end)
	end
end

------------------------------------------------------------------------
-- State: close when it no longer needs fixing or the player walked off
------------------------------------------------------------------------

function FixGame:setState(snapshot)
	local s = self.session
	if not s or s.won or typeof(snapshot) ~= "table" then
		return
	end
	local active = snapshot.phase == "Preparation" or snapshot.phase == "Night" or snapshot.phase == "Closing"
	local needed = true
	if s.fix == "Breaker" then
		needed = snapshot.power == false
	else
		local room = nil
		for _, r in pairs(snapshot.rooms or {}) do
			if r.id == s.roomId then
				room = r
			end
		end
		if s.fix == "Sheets" then
			needed = room ~= nil and room.sheetsDirty == true and not room.occupied
		else
			needed = room ~= nil and room.acBroken == true
		end
	end
	if not active or not needed then
		self:stop(true)
	end
end

function FixGame:checkDistance()
	local s = self.session
	if not s or s.won or not s.origin then
		return
	end
	local hrp = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - s.origin).Magnitude > WALK_AWAY then
		self:stop(true)
	end
end

return FixGame
