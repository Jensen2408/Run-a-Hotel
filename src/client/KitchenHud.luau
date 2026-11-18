--!nonstrict
--[[
	KitchenHud: room service and soft roles (display only).

	  kitchen panel   opened by the stove prompt: pantry stock, two burners
	                  and a prep board (cook / pick up / discard), open orders
	  orders card     left side of the screen: open meal orders with timers
	  role badge      left side: your role (or ALL ROLES when solo); tap in
	                  Preparation to open the role picker
	  role picker     four soft roles with their perks

	All rules live on the server (MotelCore); this sends choices only.
]]

local Workspace = game:GetService("Workspace")

local UiKit = require(script.Parent:WaitForChild("UiKit"))
local Icons = require(script.Parent:WaitForChild("Icons"))

local KitchenHud = {}
KitchenHud.__index = KitchenHud

local SLOT_TITLES = { Burner = "BURNER", Board = "PREP BOARD" }

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

local function strip(parent, size: UDim2, pos: UDim2)
	local f = frame(parent, {
		BackgroundColor3 = UiKit.WHITE,
		BackgroundTransparency = 0.3,
		Size = size,
		Position = pos,
	})
	UiKit.corner(f, UDim.new(0, 12))
	return f
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

function KitchenHud.new(playerGui: PlayerGui, callbacks, config)
	local self = setmetatable({}, KitchenHud)
	self.callbacks = callbacks -- send(payload)
	self.config = config
	self.state = nil
	self.recipes = {}
	for _, r in ipairs(config.recipes) do
		self.recipes[r.id] = r
	end
	self.roleDefs = {}
	for _, r in ipairs(config.roles) do
		self.roleDefs[r.id] = r
	end
	self.autoRoleShown = false

	-- Full-screen gui so positions line up with the main HUD (also full screen).
	local screen = UiKit.screen(playerGui, "KitchenHud", 6, true)
	self.screen = screen
	self:buildKitchen()
	self:buildOrdersCard()
	self:buildRoleBadge()
	self:buildRolePicker()
	return self
end

function KitchenHud:send(kind: string, payload)
	payload = payload or {}
	payload.kind = kind
	self.callbacks.send(payload)
end

------------------------------------------------------------------------
-- Kitchen panel
------------------------------------------------------------------------

function KitchenHud:buildKitchen()
	local panel, body = self.screen:modal("Kitchen", Vector2.new(780, 500), "KITCHEN", "stove")
	self.kitchen = panel

	-- Pantry strip.
	local pantry = strip(body, UDim2.new(1, -40, 0, 50), UDim2.fromOffset(20, 40))
	text(pantry, {
		Size = UDim2.fromOffset(110, 50),
		Position = UDim2.fromOffset(12, 0),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "PANTRY",
	})
	self.pantryLabels = {}
	for i, ing in ipairs(self.config.kitchen.ingredients) do
		local x = 120 + (i - 1) * 122
		Icons.create(self.config.kitchen.ingredientIcons[ing], {
			Parent = pantry,
			Size = UDim2.fromOffset(36, 36),
			Position = UDim2.new(0, x, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
		})
		self.pantryLabels[ing] = text(pantry, {
			Size = UDim2.fromOffset(80, 40),
			Position = UDim2.new(0, x + 40, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "0",
		})
	end

	-- Cooking spots.
	self.slotCards = {}
	local burnerNo = 0
	for i, kind in ipairs(self.config.kitchen.slots) do
		if kind == "Burner" then
			burnerNo += 1
		end
		local holder, card = UiKit.chunk({
			Name = "Slot" .. i,
			Parent = body,
			Size = UDim2.fromOffset(236, 290),
			Position = UDim2.fromOffset(20 + (i - 1) * 252, 104),
			Colors = UiKit.CARD,
			Radius = UDim.new(0, 16),
			Shine = false,
		})
		local title = if kind == "Burner" then ("%s %d"):format(SLOT_TITLES.Burner, burnerNo) else SLOT_TITLES.Board
		text(card, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 6), TextSize = 21, Text = title })
		local c = { kind = kind, holder = holder, card = card }

		-- Empty: recipe buttons for this station.
		c.empty = frame(card, { Name = "Empty", Size = UDim2.new(1, -20, 1, -50), Position = UDim2.fromOffset(10, 42) })
		c.recipeButtons = {}
		local n = 0
		for _, r in ipairs(self.config.recipes) do
			if r.station == kind then
				local b = UiKit.button(
					c.empty,
					"Cook_" .. r.id,
					UDim2.new(1, 0, 0, 66),
					UDim2.fromOffset(0, n * 96),
					UiKit.GREEN,
					r.name:upper(),
					function()
						self:send("Cook", { slot = i, recipe = r.id })
					end,
					r.icon
				)
				local parts = {}
				for ing, count in pairs(r.ingredients) do
					table.insert(parts, ("%d %s"):format(count, ing:lower()))
				end
				table.sort(parts)
				text(c.empty, {
					Size = UDim2.new(1, 0, 0, 20),
					Position = UDim2.fromOffset(0, n * 96 + 70),
					TextSize = 15,
					Text = table.concat(parts, " + ") .. ("  ·  $%d"):format(r.price),
				})
				c.recipeButtons[r.id] = b
				n += 1
			end
		end

		-- Busy: dish icon, status, progress bar, action button.
		c.busy = frame(
			card,
			{ Name = "Busy", Size = UDim2.new(1, -20, 1, -50), Position = UDim2.fromOffset(10, 42), Visible = false }
		)
		c.icon = Icons.create("pot", {
			Parent = c.busy,
			Size = UDim2.fromOffset(96, 96),
			Position = UDim2.fromScale(0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0),
		})
		c.status = text(c.busy, {
			Size = UDim2.new(1, 0, 0, 28),
			Position = UDim2.fromOffset(0, 100),
			TextSize = 22,
			Text = "",
		})
		local barBack = frame(c.busy, {
			BackgroundColor3 = Color3.fromRGB(80, 60, 44),
			BackgroundTransparency = 0.6,
			Size = UDim2.new(1, -10, 0, 20),
			Position = UDim2.fromOffset(5, 134),
		})
		UiKit.corner(barBack, UDim.new(1, 0))
		UiKit.outline(barBack, 2)
		c.bar =
			frame(barBack, { BackgroundColor3 = UiKit.WHITE, BackgroundTransparency = 0, Size = UDim2.fromScale(0, 1) })
		UiKit.corner(c.bar, UDim.new(1, 0))
		c.barGrad = UiKit.gradient(c.bar, UiKit.ORANGE)
		c.barBack = barBack
		c.timer = text(c.busy, {
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 158),
			TextSize = 17,
			Text = "",
		})
		c.action = UiKit.button(
			c.busy,
			"Action",
			UDim2.new(1, 0, 0, 52),
			UDim2.new(0, 0, 1, -54),
			UiKit.GREEN,
			"PICK UP",
			function()
				local slot = self.state and self.state.slots and self.state.slots[i]
				if not slot then
					return
				end
				if slot.state == "Ready" then
					self:send("CollectDish", { slot = i })
				elseif slot.state == "Burnt" then
					self:send("DiscardDish", { slot = i })
				end
			end,
			"tray"
		)
		self.slotCards[i] = c
	end

	-- Open orders.
	local orders = strip(body, UDim2.new(1, -40, 0, 54), UDim2.new(0, 20, 1, -70))
	Icons.create("ticket", {
		Parent = orders,
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
	})
	self.kitchenOrders = text(orders, {
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromOffset(50, 0),
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
end

function KitchenHud:openKitchen()
	self.screen:open(self.kitchen)
	self:render()
end

function KitchenHud:closeKitchen()
	if self.kitchen.Visible then
		self.screen:close(self.kitchen)
	end
end

function KitchenHud:isKitchenOpen(): boolean
	return self.kitchen.Visible
end

------------------------------------------------------------------------
-- Orders card + role badge (main screen, left column)
------------------------------------------------------------------------

function KitchenHud:buildRoleBadge()
	local holder, body, grad = UiKit.chunk({
		Name = "RoleBadge",
		Parent = self.screen.root,
		Size = UDim2.fromOffset(282, 42),
		Position = UDim2.fromOffset(12, 452),
		Colors = UiKit.PURPLE,
		Radius = UDim.new(1, 0),
		Button = true,
	})
	self.roleBadge = holder
	self.roleGrad = grad
	self.roleIcon = Icons.create("roles", {
		Parent = body,
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(0, 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 2,
	})
	self.roleText = UiKit.label({
		Parent = body,
		Size = UDim2.new(1, -54, 1, 0),
		Position = UDim2.fromOffset(46, 0),
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "PICK A ROLE",
		ZIndex = 2,
	})
	UiKit.pressable(holder, body, function()
		self:openRoles()
	end)
end

function KitchenHud:buildOrdersCard()
	local holder, body = UiKit.chunk({
		Name = "Orders",
		Parent = self.screen.root,
		Size = UDim2.fromOffset(282, 60),
		Position = UDim2.fromOffset(12, 504),
		Colors = UiKit.CARD,
		Radius = UDim.new(0, 16),
		Visible = false,
		Shine = false,
	})
	self.ordersCard = holder
	Icons.create("ticket", {
		Parent = body,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(10, 6),
	})
	text(body, {
		Size = UDim2.new(1, -50, 0, 28),
		Position = UDim2.fromOffset(44, 6),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "ROOM SERVICE",
	})
	self.orderRows = {}
	for i = 1, 4 do
		local row = frame(body, { Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 6 + i * 36) })
		local icon = Icons.create("burger", {
			Parent = row,
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.fromScale(0, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
		})
		local name = text(row, {
			Size = UDim2.new(1, -90, 1, 0),
			Position = UDim2.fromOffset(36, 0),
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		})
		local timer = text(row, {
			Size = UDim2.fromOffset(50, 34),
			Position = UDim2.new(1, -50, 0, 0),
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = "",
		})
		self.orderRows[i] = { frame = row, icon = icon, name = name, timer = timer, recipe = nil }
	end
end

------------------------------------------------------------------------
-- Role picker
------------------------------------------------------------------------

function KitchenHud:buildRolePicker()
	local panel, body = self.screen:modal("Roles", Vector2.new(760, 380), "PICK YOUR ROLE", "roles")
	self.rolesPanel = panel
	self.roleSub = text(body, {
		Size = UDim2.new(1, -40, 0, 30),
		Position = UDim2.fromOffset(20, 36),
		TextSize = 19,
		Text = "Everyone can do every job. Your role gives you a perk.",
	})
	self.roleCards = {}
	for i, def in ipairs(self.config.roles) do
		local holder, card, grad = UiKit.chunk({
			Name = "Role_" .. def.id,
			Parent = body,
			Size = UDim2.fromOffset(166, 270),
			Position = UDim2.fromOffset(20 + (i - 1) * 182, 74),
			Colors = UiKit.CARD,
			Radius = UDim.new(0, 16),
			Shine = false,
		})
		Icons.create(def.icon, {
			Parent = card,
			Size = UDim2.fromOffset(80, 80),
			Position = UDim2.new(0.5, 0, 0, 10),
			AnchorPoint = Vector2.new(0.5, 0),
		})
		text(card, {
			Size = UDim2.new(1, -10, 0, 28),
			Position = UDim2.fromOffset(5, 94),
			TextSize = 20,
			Text = def.label:upper(),
		})
		text(card, {
			Size = UDim2.new(1, -16, 0, 70),
			Position = UDim2.fromOffset(8, 124),
			TextSize = 15,
			Text = def.perk,
		})
		local b = UiKit.button(
			card,
			"Choose",
			UDim2.new(1, -20, 0, 50),
			UDim2.new(0, 10, 1, -60),
			UiKit.GREEN,
			"CHOOSE",
			function()
				self:send("SetRole", { role = def.id })
			end,
			"check"
		)
		b.label.TextSize = 19
		self.roleCards[def.id] = { holder = holder, grad = grad, button = b }
	end
end

function KitchenHud:openRoles()
	self.screen:open(self.rolesPanel)
	self:renderRoles()
end

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

function KitchenHud:setState(s)
	local prev = self.state
	self.state = s
	local active = s.phase == "Preparation" or s.phase == "Night" or s.phase == "Closing"
	if not active then
		self:closeKitchen()
	end
	-- First Preparation of a co-op run: offer the role picker once.
	if not self.autoRoleShown and s.phase == "Preparation" and not s.soloRoles and not s.role then
		self.autoRoleShown = true
		task.delay(1.5, function()
			if self.state and self.state.phase == "Preparation" and not self.state.role then
				self:openRoles()
			end
		end)
	end
	if self.rolesPanel.Visible and s.phase ~= "Preparation" then
		self.screen:close(self.rolesPanel)
	end
	if prev and prev.role ~= s.role and s.role and self.rolesPanel.Visible then
		task.delay(0.4, function()
			if self.rolesPanel.Visible then
				self.screen:close(self.rolesPanel)
			end
		end)
	end
	self:render()
end

function KitchenHud:renderRoles()
	local s = self.state
	if not s then
		return
	end
	local prep = s.phase == "Preparation"
	self.roleSub.Text = if s.soloRoles
		then "Playing solo: you have every perk."
		elseif prep then "Everyone can do every job. Your role gives you a perk."
		else "Roles can be changed during Preparation."
	for id, c in pairs(self.roleCards) do
		local mine = s.role == id or s.soloRoles
		UiKit.setColors(c.grad, if mine then UiKit.GOLD else UiKit.CARD)
		c.button.label.Text = if mine then "YOURS" elseif prep then "CHOOSE" else "LOCKED"
		c.button.icon:set(if mine then "check" elseif prep then "play" else "cross")
		UiKit.setColors(c.button.grad, if mine then UiKit.GOLD elseif prep then UiKit.GREEN else UiKit.GREY)
	end
end

function KitchenHud:render()
	local s = self.state
	if not s then
		return
	end
	-- Role badge.
	local def = s.role and self.roleDefs[s.role]
	if s.soloRoles then
		self.roleText.Text = "ALL ROLES (SOLO)"
		self.roleIcon:set("roles")
	elseif def then
		self.roleText.Text = def.label:upper()
		self.roleIcon:set(def.icon)
	else
		self.roleText.Text = if s.phase == "Preparation" then "PICK A ROLE" else "NO ROLE"
		self.roleIcon:set("roles")
	end
	if self.rolesPanel.Visible then
		self:renderRoles()
	end

	-- Pantry.
	for ing, l in pairs(self.pantryLabels) do
		l.Text = tostring(s.pantry and s.pantry[ing] or 0)
	end
	-- Slots (static parts; timers update in tick).
	for i, c in ipairs(self.slotCards) do
		local slot = s.slots and s.slots[i]
		local state = slot and slot.state or "Empty"
		c.empty.Visible = state == "Empty"
		c.busy.Visible = state ~= "Empty"
		if state == "Empty" then
			for id, b in pairs(c.recipeButtons) do
				local r = self.recipes[id]
				local can = true
				for ing, n in pairs(r.ingredients) do
					if (s.pantry[ing] or 0) < n then
						can = false
					end
				end
				UiKit.setColors(b.grad, if can then UiKit.GREEN else UiKit.GREY)
				b.label.Text = if can then r.name:upper() else ("NEED %s"):format(r.name:upper())
			end
		else
			local r = self.recipes[slot.recipe]
			c.icon:set(if state == "Burnt" then "burnt" elseif r then r.icon else "pot")
			if state == "Cooking" then
				c.status.Text = ("Cooking %s"):format(r and r.name or "")
				c.action.holder.Visible = false
				UiKit.setColors(c.barGrad, UiKit.ORANGE)
			elseif state == "Ready" then
				c.status.Text = ("%s READY!"):format(r and r.name:upper() or "")
				c.action.holder.Visible = true
				c.action.label.Text = "PICK UP"
				c.action.icon:set("tray")
				UiKit.setColors(c.action.grad, UiKit.GREEN)
				UiKit.setColors(c.barGrad, UiKit.GREEN)
			else
				c.status.Text = "BURNT!"
				c.action.holder.Visible = true
				c.action.label.Text = "THROW AWAY"
				c.action.icon:set("trash")
				UiKit.setColors(c.action.grad, UiKit.RED)
				UiKit.setColors(c.barGrad, UiKit.RED)
			end
		end
		if c.lastState ~= state then
			if c.lastState ~= nil then
				UiKit.pop(c.holder, 0.06)
				if state == "Ready" then
					UiKit.play("success")
				elseif state == "Burnt" then
					UiKit.play("error")
				end
			end
			c.lastState = state
		end
	end
	self:tick()
end

-- Open orders sorted by deadline: { roomNumber, recipe, left }.
function KitchenHud:openOrders()
	local list = {}
	local s = self.state
	local t = now()
	for _, room in ipairs(s and s.rooms or {}) do
		local o = room.mealOrder
		if o then
			table.insert(list, { number = room.number, recipe = o.recipe, left = math.max(0, o.expiresAt - t) })
		end
	end
	table.sort(list, function(a, b)
		return a.left < b.left
	end)
	return list
end

-- Timers, every frame.
function KitchenHud:tick()
	local s = self.state
	if not s then
		return
	end
	local t = now()
	local orders = self:openOrders()

	-- Orders card.
	local active = s.phase == "Night" or s.phase == "Closing"
	self.ordersCard.Visible = active and #orders > 0
	if self.ordersCard.Visible then
		local shown = math.min(#orders, #self.orderRows)
		self.ordersCard.Size = UDim2.fromOffset(282, 44 + shown * 36)
		for i, row in ipairs(self.orderRows) do
			local o = orders[i]
			row.frame.Visible = o ~= nil
			if o then
				local r = self.recipes[o.recipe]
				if row.recipe ~= o.recipe then
					row.recipe = o.recipe
					row.icon:set(r and r.icon or "pot")
				end
				row.name.Text = ("Room %d · %s"):format(o.number, r and r.name or "")
				row.timer.Text = ("%ds"):format(math.ceil(o.left))
				row.timer.TextColor3 = if o.left < 10 then Color3.fromRGB(210, 60, 50) else UiKit.TEXT_DARK
			end
		end
	end

	if not self.kitchen.Visible then
		return
	end
	-- Kitchen orders strip.
	if #orders == 0 then
		self.kitchenOrders.Text = "No orders yet. Guests order food during their stay."
	else
		local parts = {}
		for _, o in ipairs(orders) do
			local r = self.recipes[o.recipe]
			table.insert(parts, ("Room %d: %s (%ds)"):format(o.number, r and r.name or "?", math.ceil(o.left)))
		end
		self.kitchenOrders.Text = table.concat(parts, "   ")
	end
	-- Slot progress.
	for i, c in ipairs(self.slotCards) do
		local slot = s.slots and s.slots[i]
		if slot and slot.state == "Cooking" then
			local total = math.max(0.01, slot.readyAt - slot.startedAt)
			local k = math.clamp((t - slot.startedAt) / total, 0, 1)
			c.bar.Size = UDim2.fromScale(k, 1)
			c.timer.Text = ("Ready in %ds"):format(math.ceil(math.max(0, slot.readyAt - t)))
		elseif slot and slot.state == "Ready" then
			if slot.burnAt then
				local total = math.max(0.01, slot.burnAt - slot.readyAt)
				local left = math.max(0, slot.burnAt - t)
				c.bar.Size = UDim2.fromScale(math.clamp(left / total, 0, 1), 1)
				c.timer.Text = ("Burns in %ds!"):format(math.ceil(left))
			else
				c.bar.Size = UDim2.fromScale(1, 1)
				c.timer.Text = "Stays fresh on the board"
			end
		elseif slot and slot.state == "Burnt" then
			c.bar.Size = UDim2.fromScale(1, 1)
			c.timer.Text = "Throw it away and cook again"
		end
	end
end

return KitchenHud
