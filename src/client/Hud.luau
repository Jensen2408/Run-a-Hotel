--!nonstrict
--[[
	HUD for Run a Motel. Display only: every number comes from the server
	snapshot.

	Visual language: chunky cartoon simulator UI. Thick dark outlines,
	vertical gradients, a drop shadow under every panel, Fredoka text with
	an outline, white cards with a gold ribbon, and a bar of big tiles at
	the bottom. Icons come from the UI icon sheet (see UiAssets / Icons).

	Motion and sound:
	  - numbers roll (cash), "+$25" floats up, pills pop when values change
	  - buttons grow on hover, squash on press, click sound
	  - modals scale in over a dimmed backdrop, report rows reveal one by one,
	    the result stamps in, confetti on a paid bill / completed run
	  - toasts and banners bounce in with a shine sweep
	  - idle motion: READY tile breathes, the night star sways, timers pulse
	    and the queue tile shakes when a guest is about to leave

	Authored for 1280x720 and scaled with UIScale. The bottom bar stays
	centred so it does not collide with the mobile thumbstick or jump button.
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Icons = require(script.Parent:WaitForChild("Icons"))

local Hud = {}
Hud.__index = Hud

------------------------------------------------------------------------
-- Palette and fonts
------------------------------------------------------------------------

local FONT = Enum.Font.FredokaOne
local OUTLINE = Color3.fromRGB(46, 32, 22)
local WHITE = Color3.new(1, 1, 1)
local CREAM = Color3.fromRGB(255, 247, 222)
local TEXT_DARK = Color3.fromRGB(70, 52, 38)

local GOLD = { Color3.fromRGB(255, 226, 110), Color3.fromRGB(240, 172, 34) }
local GREEN = { Color3.fromRGB(150, 232, 92), Color3.fromRGB(62, 170, 46) }
local BLUE = { Color3.fromRGB(130, 200, 255), Color3.fromRGB(52, 128, 230) }
local RED = { Color3.fromRGB(255, 128, 110), Color3.fromRGB(214, 52, 52) }
local ORANGE = { Color3.fromRGB(255, 196, 110), Color3.fromRGB(236, 122, 40) }
local PURPLE = { Color3.fromRGB(206, 170, 255), Color3.fromRGB(132, 88, 222) }
local GREY = { Color3.fromRGB(196, 196, 204), Color3.fromRGB(128, 128, 140) }
local TEAL = { Color3.fromRGB(140, 236, 220), Color3.fromRGB(40, 170, 160) }
local CARD = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(240, 234, 220) }

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 210, 80),
	Color3.fromRGB(90, 220, 140),
	Color3.fromRGB(90, 170, 255),
	Color3.fromRGB(240, 120, 230),
}

local ITEM_ICON = { Sheet = "sheet", Towel = "towel", Trash = "trash" }

-- Layering: modals above the backdrop, which is above the HUD.
local Z_BACKDROP = 9
local Z_MODAL = 10
local Z_TOP = 12

------------------------------------------------------------------------
-- Sound hook (set in Hud.new)
------------------------------------------------------------------------

local sfx = nil
local function play(name: string)
	if sfx then
		sfx:play(name)
	end
end

------------------------------------------------------------------------
-- Building blocks
------------------------------------------------------------------------

local function make(className: string, props)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(parent, radius: UDim?)
	make("UICorner", { CornerRadius = radius or UDim.new(0, 14), Parent = parent })
end

local function outline(parent, thickness: number?, color: Color3?)
	return make("UIStroke", {
		Thickness = thickness or 3,
		Color = color or OUTLINE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

local function gradient(parent, colors)
	return make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(colors[1], colors[2]),
		Parent = parent,
	})
end

-- Outlined cartoon text.
local function label(props)
	local size = props.TextSize or 22
	props.TextSize = nil
	local strokeColor = props.StrokeColor or OUTLINE
	local strokeThickness = props.Stroke
	props.StrokeColor = nil
	props.Stroke = nil
	local t = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = WHITE,
		TextSize = size,
		TextWrapped = true,
		Text = "",
	})
	for k, v in pairs(props) do
		if k ~= "Parent" then
			t[k] = v
		end
	end
	if strokeThickness ~= 0 then
		make("UIStroke", {
			Thickness = strokeThickness or math.max(1.5, size / 11),
			Color = strokeColor,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			LineJoinMode = Enum.LineJoinMode.Round,
			Parent = t,
		})
	end
	t.Parent = props.Parent
	return t
end

--[[
	A chunky panel: a transparent holder containing a dark drop shadow and
	the gradient body on top. Returns holder, body, gradient.
]]
local function chunk(props)
	local holder = make("Frame", {
		Name = props.Name or "Chunk",
		BackgroundTransparency = 1,
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
	local radius = props.Radius or UDim.new(0, 14)
	local shadow = make("Frame", {
		Name = "Shadow",
		BackgroundColor3 = OUTLINE,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, props.ShadowDepth or 5),
		Parent = holder,
	})
	corner(shadow, radius)
	local body = make(props.Button and "TextButton" or "Frame", {
		Name = "Body",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	if props.Button then
		body.Text = ""
		body.AutoButtonColor = false
	end
	corner(body, radius)
	outline(body, props.Stroke or 3)
	local grad = gradient(body, props.Colors or CARD)
	if props.Shine ~= false then
		local shine = make("Frame", {
			Name = "Shine",
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.78,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -10, 0.42, 0),
			Position = UDim2.fromOffset(5, 3),
			Parent = body,
		})
		corner(shine, radius)
	end
	return holder, body, grad
end

local function setColors(grad: UIGradient, colors)
	grad.Color = ColorSequence.new(colors[1], colors[2])
end

local function fmtTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

------------------------------------------------------------------------
-- Animation helpers
------------------------------------------------------------------------

local function tween(obj: Instance, time: number, props, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(
		obj,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

-- Several effects (pop, hover, pulse) may scale the same object, but Roblox
-- applies only one UIScale per GuiObject. Each effect gets a NumberValue
-- component; the object's single UIScale is the product of its components.
local scaleState = setmetatable({}, { __mode = "k" })

local function scaleOf(gui: GuiObject, name: string?): NumberValue
	local st = scaleState[gui]
	if not st then
		local ui = gui:FindFirstChild("FxScale") or make("UIScale", { Name = "FxScale", Parent = gui })
		st = { ui = ui, values = {} }
		scaleState[gui] = st
	end
	local key = name or "Anim"
	local v = st.values[key]
	if not v then
		v = Instance.new("NumberValue")
		v.Name = key
		v.Value = 1
		st.values[key] = v
		v.Changed:Connect(function()
			local product = 1
			for _, c in pairs(st.values) do
				product *= c.Value
			end
			st.ui.Scale = product
		end)
	end
	return v
end

-- Quick squash-and-stretch bounce.
local function pop(gui: GuiObject, amount: number?)
	local s = scaleOf(gui)
	s.Value = 1
	local up = tween(s, 0.08, { Value = 1 + (amount or 0.12) })
	up.Completed:Once(function()
		tween(s, 0.4, { Value = 1 }, Enum.EasingStyle.Back)
	end)
end

-- Rotational wiggle (doesn't disturb layouts).
local function wiggle(gui: GuiObject, degrees: number, duration: number)
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < duration do
			local k = 1 - (os.clock() - start) / duration
			gui.Rotation = math.sin((os.clock() - start) * 40) * degrees * k
			task.wait()
		end
		gui.Rotation = 0
	end)
end

-- White shine that sweeps across a panel body once.
local function shineSweep(body: GuiObject)
	body.ClipsDescendants = true
	local streak = make("Frame", {
		Name = "Sweep",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.25, 2),
		Position = UDim2.fromScale(-0.4, -0.5),
		Rotation = 20,
		ZIndex = 5,
		Parent = body,
	})
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = streak,
	})
	local t = tween(streak, 0.7, { Position = UDim2.fromScale(1.3, -0.5) }, Enum.EasingStyle.Sine)
	t.Completed:Once(function()
		streak:Destroy()
	end)
end

-- Button behaviour: grow on hover, squash on press, click sound.
local function pressable(holder: GuiObject, body: GuiButton, onActivate)
	body.Activated:Connect(function()
		play("click")
		onActivate()
	end)
	local s = scaleOf(holder, "Hover")
	body.MouseEnter:Connect(function()
		tween(s, 0.12, { Value = 1.06 })
	end)
	body.MouseLeave:Connect(function()
		tween(s, 0.15, { Value = 1 })
		body.Position = UDim2.fromOffset(0, 0)
	end)
	body.MouseButton1Down:Connect(function()
		body.Position = UDim2.fromOffset(0, 3)
		tween(s, 0.06, { Value = 0.95 })
	end)
	body.MouseButton1Up:Connect(function()
		body.Position = UDim2.fromOffset(0, 0)
		tween(s, 0.2, { Value = 1.06 }, Enum.EasingStyle.Back)
	end)
end

-- A circular icon "medallion" that overlaps the left edge of a pill.
local function medallion(parent, size: number, colors, iconName: string)
	local holder, body = chunk({
		Name = "Medallion",
		Parent = parent,
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(0, -size * 0.35, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Colors = colors,
		Radius = UDim.new(1, 0),
		ShadowDepth = 4,
	})
	holder.ZIndex = 3
	local icon = Icons.create(iconName, {
		Parent = body,
		Size = UDim2.fromScale(0.86, 0.86),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 2,
	})
	return holder, icon
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------

function Hud.new(playerGui: PlayerGui, config, callbacks)
	local self = setmetatable({}, Hud)
	self.roomDefs = config.rooms
	self.shopItems = config.shop or {}
	self.callbacks = callbacks
	self.state = nil
	self.prev = nil
	self.roomCount = config.roomCount
	self.cashShown = 0
	self.cashTarget = 0
	self.lastTick = os.clock()
	sfx = callbacks.sfx

	local gui = make("ScreenGui", {
		Name = "MotelHud",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	self.gui = gui

	local root = make("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	local uiScale = make("UIScale", { Parent = root })
	local function rescale()
		local cam = Workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		local s = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.5, 1.4)
		uiScale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	rescale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	self.root = root
	self.uiScale = uiScale

	self:buildTopBar()
	self:buildRoomsCard()
	self:buildStatusTiles()
	self:buildBottomBar()
	self:buildBanner()
	self:buildAlert()
	self:buildToasts()
	self:buildBackdrop()
	self:buildReport()
	self:buildShop()
	self:buildLinen()
	self:buildTutorial()
	self:buildFx()
	return self
end

-- Top bar: night badge + phase bar, cash, supplies, guests ------------------
function Hud:buildTopBar()
	local top = make("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(980, 96),
		Parent = self.root,
	})
	self.top = top

	-- Night badge (big star) + night ribbon + phase progress bar.
	local nightGroup = make("Frame", {
		Name = "NightGroup",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(250, 80),
		Parent = top,
	})
	local phaseHolder, phaseBody = chunk({
		Name = "PhaseBar",
		Parent = nightGroup,
		Size = UDim2.fromOffset(190, 34),
		Position = UDim2.fromOffset(52, 30),
		Colors = { Color3.fromRGB(80, 70, 110), Color3.fromRGB(50, 42, 72) },
		Radius = UDim.new(1, 0),
		Shine = false,
	})
	self.phaseHolder = phaseHolder
	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.new(0.5, 0, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		Parent = phaseBody,
	})
	corner(fill, UDim.new(1, 0))
	self.phaseFillGrad = gradient(fill, BLUE)
	self.phaseFill = fill
	self.phaseText = label({
		Name = "Phase",
		Parent = phaseBody,
		Size = UDim2.fromScale(1, 1),
		TextSize = 17,
		Text = "",
		ZIndex = 2,
	})
	local ribbonHolder, ribbonBody = chunk({
		Name = "NightRibbon",
		Parent = nightGroup,
		Size = UDim2.fromOffset(130, 24),
		Position = UDim2.fromOffset(62, 4),
		Colors = PURPLE,
		Radius = UDim.new(0, 10),
		ShadowDepth = 3,
		Stroke = 2.5,
	})
	ribbonHolder.ZIndex = 2
	self.nightText = label({ Parent = ribbonBody, Size = UDim2.fromScale(1, 1), TextSize = 15, Text = "NIGHT 1/3" })
	local starHolder = make("Frame", {
		Name = "Star",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(84, 84),
		Position = UDim2.fromOffset(-14, -6),
		ZIndex = 4,
		Parent = nightGroup,
	})
	self.nightStarIcon = Icons.create("star", {
		Parent = starHolder,
		ZIndex = 4,
		FallbackColor = Color3.fromRGB(255, 208, 60),
	})
	self.nightStar = starHolder
	self.nightNumber = label({
		Name = "Number",
		Parent = starHolder,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 4),
		Text = "1",
		TextSize = 30,
		ZIndex = 5,
	})

	-- Cash pill with gold coin + bill sub-pill.
	local cashHolder, cashBody, cashGrad = chunk({
		Name = "Cash",
		Parent = top,
		Size = UDim2.fromOffset(200, 50),
		Position = UDim2.fromOffset(300, 4),
		Colors = GOLD,
		Radius = UDim.new(1, 0),
	})
	self.cashHolder = cashHolder
	self.cashGrad = cashGrad
	local coinHolder, coinIcon = medallion(cashHolder, 58, GOLD, "coin")
	self.coinHolder = coinHolder
	self.coinIcon = coinIcon
	self.cashText = label({
		Parent = cashBody,
		Size = UDim2.new(1, -36, 1, 0),
		Position = UDim2.fromOffset(30, 0),
		TextSize = 32,
		Text = "$0",
	})
	local _billHolder, billBody = chunk({
		Name = "Bill",
		Parent = top,
		Size = UDim2.fromOffset(150, 28),
		Position = UDim2.fromOffset(330, 58),
		Colors = { CREAM, Color3.fromRGB(240, 226, 190) },
		Radius = UDim.new(1, 0),
		ShadowDepth = 3,
		Stroke = 2.5,
		Shine = false,
	})
	self.billText = label({
		Parent = billBody,
		Size = UDim2.fromScale(1, 1),
		TextSize = 17,
		TextColor3 = TEXT_DARK,
		Stroke = 0,
		Text = "BILL $0",
	})

	-- Supplies pill (green): sheet icon + count, towel icon + count.
	local supHolder, supBody = chunk({
		Name = "Supplies",
		Parent = top,
		Size = UDim2.fromOffset(230, 50),
		Position = UDim2.fromOffset(530, 4),
		Colors = GREEN,
		Radius = UDim.new(1, 0),
	})
	self.supHolder = supHolder
	local function stockGroup(iconName, x)
		Icons.create(iconName, {
			Parent = supBody,
			Size = UDim2.fromOffset(40, 40),
			Position = UDim2.new(0, x, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = 2,
		})
		return label({
			Parent = supBody,
			Size = UDim2.fromOffset(56, 40),
			Position = UDim2.new(0, x + 42, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			TextSize = 28,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "0",
			ZIndex = 2,
		})
	end
	self.sheetCount = stockGroup("sheet", 14)
	self.towelCount = stockGroup("towel", 120)
	local trolleyHolder, trolleyBody = chunk({
		Name = "Trolley",
		Parent = top,
		Size = UDim2.fromOffset(170, 28),
		Position = UDim2.fromOffset(560, 58),
		Colors = { CREAM, Color3.fromRGB(240, 226, 190) },
		Radius = UDim.new(1, 0),
		ShadowDepth = 3,
		Stroke = 2.5,
		Shine = false,
	})
	self.trolleyHolder = trolleyHolder
	Icons.create("trolley", {
		Parent = trolleyBody,
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		FallbackColor = TEXT_DARK,
	})
	self.trolleyText = label({
		Parent = trolleyBody,
		Size = UDim2.new(1, -70, 1, 0),
		Position = UDim2.fromOffset(38, 0),
		TextSize = 16,
		TextColor3 = TEXT_DARK,
		Stroke = 0,
		Text = "",
	})
	self.trolleyCheck = Icons.create("check", {
		Parent = trolleyBody,
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
	})

	-- Guests pill (blue) + status sub-pill (OPEN / CLOSING / POWER OUT).
	local guestHolder, guestBody = chunk({
		Name = "Guests",
		Parent = top,
		Size = UDim2.fromOffset(150, 50),
		Position = UDim2.fromOffset(810, 4),
		Colors = BLUE,
		Radius = UDim.new(1, 0),
	})
	self.guestHolder = guestHolder
	medallion(guestHolder, 58, ORANGE, "guests")
	self.guestText = label({
		Parent = guestBody,
		Size = UDim2.new(1, -30, 1, 0),
		Position = UDim2.fromOffset(26, 0),
		TextSize = 30,
		Text = "0/0",
	})
	local statusHolder, statusBody = chunk({
		Name = "Status",
		Parent = top,
		Size = UDim2.fromOffset(130, 28),
		Position = UDim2.fromOffset(824, 58),
		Colors = { CREAM, Color3.fromRGB(240, 226, 190) },
		Radius = UDim.new(1, 0),
		ShadowDepth = 3,
		Stroke = 2.5,
		Shine = false,
	})
	self.statusHolder = statusHolder
	self.statusIcon = Icons.create("bell", {
		Parent = statusBody,
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
	})
	self.statusText = label({
		Parent = statusBody,
		Size = UDim2.new(1, -36, 1, 0),
		Position = UDim2.fromOffset(32, 0),
		TextSize = 17,
		TextColor3 = Color3.fromRGB(56, 160, 50),
		Stroke = 0,
		Text = "OPEN",
	})
end

-- Rooms card: white card with a gold ribbon, one checklist row per room -----
function Hud:buildRoomsCard()
	local rowH = 40
	local holder, body = chunk({
		Name = "Rooms",
		Parent = self.root,
		Size = UDim2.fromOffset(300, 30 + rowH * self.roomCount + 8),
		Position = UDim2.fromOffset(14, 150),
	})
	self.roomsCard = holder
	local ribbonHolder, ribbonBody = chunk({
		Name = "Ribbon",
		Parent = holder,
		Size = UDim2.fromOffset(150, 30),
		Position = UDim2.fromOffset(14, -18),
		Colors = GOLD,
		Radius = UDim.new(0, 10),
		ShadowDepth = 3,
		Stroke = 2.5,
	})
	ribbonHolder.ZIndex = 2
	self.roomsRibbon = ribbonHolder
	self.roomsTitle = label({ Parent = ribbonBody, Size = UDim2.fromScale(1, 1), TextSize = 19, Text = "ROOMS 0/0" })
	self.roomRows = {}
	for i = 1, self.roomCount do
		local y = 22 + rowH * (i - 1)
		local circle = make("Frame", {
			Name = "Check" .. i,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.fromOffset(12, y + 5),
			Parent = body,
		})
		corner(circle, UDim.new(1, 0))
		outline(circle, 2.5)
		local circleGrad = gradient(circle, GREEN)
		local mark = Icons.create("check", {
			Parent = circle,
			Size = UDim2.fromScale(1.15, 1.15),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 2,
		})
		local text = label({
			Name = "Room" .. i,
			Parent = body,
			Size = UDim2.new(1, -130, 0, rowH),
			Position = UDim2.fromOffset(48, y),
			TextSize = 19,
			TextColor3 = TEXT_DARK,
			Stroke = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "Room " .. (self.roomDefs[i] and self.roomDefs[i].number or i),
		})
		local chipHolder, chipBody, chipGrad = chunk({
			Name = "Chip" .. i,
			Parent = body,
			Size = UDim2.fromOffset(76, 24),
			Position = UDim2.new(1, -86, 0, y + 7),
			Colors = GREEN,
			Radius = UDim.new(1, 0),
			ShadowDepth = 2,
			Stroke = 2,
			Shine = false,
		})
		local chipText = label({ Parent = chipBody, Size = UDim2.fromScale(1, 1), TextSize = 13, Text = "READY" })
		self.roomRows[i] = {
			circle = circle,
			circleGrad = circleGrad,
			mark = mark,
			text = text,
			chip = chipHolder,
			chipGrad = chipGrad,
			chipText = chipText,
		}
	end
end

-- Status tiles (2x2) under the rooms card ---------------------------------
function Hud:buildStatusTiles()
	local top = 150 + 30 + 40 * self.roomCount + 8 + 18
	local grid = make("Frame", {
		Name = "StatusTiles",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(300, 120),
		Position = UDim2.fromOffset(14, top),
		Parent = self.root,
	})
	local function tile(name, col, row, colors, iconName)
		local holder, body, grad = chunk({
			Name = name,
			Parent = grid,
			Size = UDim2.fromOffset(144, 52),
			Position = UDim2.fromOffset(col * 156, row * 62),
			Colors = colors,
			Radius = UDim.new(0, 16),
			ShadowDepth = 4,
		})
		local medal = make("Frame", {
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(40, 40),
			Position = UDim2.new(0, 5, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = body,
		})
		corner(medal, UDim.new(1, 0))
		local icon = Icons.create(iconName, {
			Parent = medal,
			Size = UDim2.fromScale(0.92, 0.92),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
		})
		local title = label({
			Parent = body,
			Size = UDim2.new(1, -52, 0, 18),
			Position = UDim2.fromOffset(50, 5),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = name:upper(),
		})
		local value = label({
			Parent = body,
			Size = UDim2.new(1, -54, 0, 26),
			Position = UDim2.fromOffset(50, 21),
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
		})
		return { holder = holder, body = body, grad = grad, icon = icon, title = title, value = value }
	end
	self.tileQueue = tile("Queue", 0, 0, ORANGE, "hourglass")
	self.tileHands = tile("Hands", 1, 0, TEAL, "hand")
	self.tileWeather = tile("Weather", 0, 1, BLUE, "moon")
	self.tileBest = tile("Best", 1, 1, PURPLE, "trophy")
end

-- Bottom action bar: carried items + Ready ---------------------------------
function Hud:buildBottomBar()
	local bar = make("Frame", {
		Name = "BottomBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(600, 110),
		Parent = self.root,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bar,
	})
	self.bottomBar = bar

	local function tile(name, order, colors, iconName, caption, isButton)
		local holder = make("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(96, 108),
			LayoutOrder = order,
			Parent = bar,
		})
		local boxHolder, box, grad = chunk({
			Name = "Box",
			Parent = holder,
			Size = UDim2.fromOffset(96, 84),
			Colors = colors,
			Radius = UDim.new(0, 18),
			Button = isButton,
		})
		local icon = Icons.create(iconName or "check", {
			Parent = box,
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.new(0.5, 0, 0.5, -5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 2,
		})
		icon.frame.Visible = iconName ~= nil
		local capHolder, capBody = chunk({
			Name = "Caption",
			Parent = holder,
			Size = UDim2.fromOffset(104, 30),
			Position = UDim2.new(0.5, 0, 0, 72),
			AnchorPoint = Vector2.new(0.5, 0),
			Colors = { Color3.fromRGB(110, 76, 50), Color3.fromRGB(74, 50, 32) },
			Radius = UDim.new(0, 10),
			ShadowDepth = 3,
			Stroke = 2.5,
			Shine = false,
		})
		capHolder.ZIndex = 2
		local cap = label({ Parent = capBody, Size = UDim2.fromScale(1, 1), TextSize = 18, Text = caption })
		return { holder = holder, boxHolder = boxHolder, box = box, grad = grad, icon = icon, caption = cap }
	end

	self.handTiles = {}
	for i = 1, 2 do
		self.handTiles[i] = tile("Hand" .. i, i, GREY, nil, "EMPTY", false)
	end
	self.readyTile = tile("Ready", 10, GREEN, "check", "READY", true)
	pressable(self.readyTile.boxHolder, self.readyTile.box, function()
		self.callbacks.onReady()
	end)
end

-- Centre banner for phase announcements ------------------------------------
function Hud:buildBanner()
	local holder, body = chunk({
		Name = "Banner",
		Parent = self.root,
		Size = UDim2.fromOffset(440, 70),
		Position = UDim2.new(0.5, 0, 0, 250),
		AnchorPoint = Vector2.new(0.5, 0),
		Colors = GOLD,
		Radius = UDim.new(0, 16),
		Visible = false,
		ZIndex = Z_TOP,
	})
	local inner = make("Frame", {
		BackgroundColor3 = CREAM,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -16, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		Parent = body,
	})
	corner(inner, UDim.new(0, 10))
	outline(inner, 2, Color3.fromRGB(200, 150, 40))
	self.bannerIcon = Icons.create("moon", {
		Parent = holder,
		Size = UDim2.fromOffset(78, 78),
		Position = UDim2.new(0, -30, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 3,
	})
	self.bannerTitle = label({
		Parent = inner,
		Size = UDim2.new(1, -40, 1, 0),
		Position = UDim2.fromOffset(34, 0),
		TextSize = 36,
		TextColor3 = Color3.fromRGB(74, 52, 30),
		Stroke = 0,
		Text = "",
	})
	self.bannerSub = label({
		Parent = holder,
		Size = UDim2.new(1, 40, 0, 24),
		Position = UDim2.new(0.5, 0, 1, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		TextSize = 20,
		Text = "",
	})
	self.bannerFrame = holder
	self.bannerBody = body
	self.bannerToken = 0
end

function Hud:buildAlert()
	local holder, body, grad = chunk({
		Name = "Alert",
		Parent = self.root,
		Size = UDim2.fromOffset(470, 44),
		Position = UDim2.new(0.5, 0, 0, 112),
		AnchorPoint = Vector2.new(0.5, 0),
		Colors = RED,
		Radius = UDim.new(1, 0),
		Visible = false,
	})
	self.alertIcon = Icons.create("lightning", {
		Parent = body,
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 2,
	})
	self.alertText = label({
		Parent = body,
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromOffset(48, 0),
		TextSize = 20,
		Text = "",
	})
	self.alert = holder
	self.alertGrad = grad
end

function Hud:buildToasts()
	local toasts = make("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -140),
		Size = UDim2.fromOffset(600, 200),
		-- Below the modal backdrop: an open panel (shop, linen, report) is
		-- never covered by toasts; it already shows the result itself.
		ZIndex = Z_BACKDROP - 1,
		Parent = self.root,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toasts,
	})
	self.toasts = toasts
	self.toastOrder = 0
end

function Hud:buildBackdrop()
	self.backdrop = make("Frame", {
		Name = "Backdrop",
		BackgroundColor3 = Color3.fromRGB(20, 14, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z_BACKDROP,
		Visible = false,
		Parent = self.root,
	})
end

-- Effects layer for floating numbers and confetti.
function Hud:buildFx()
	self.fx = make("Frame", {
		Name = "Fx",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z_TOP + 1,
		Parent = self.root,
	})
end

-- Modal panel shared by the station panels and the report ---------------------------
local function modal(parent, name: string, size: Vector2, title: string)
	local holder, body = chunk({
		Name = name,
		Parent = parent,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Colors = { CREAM, Color3.fromRGB(244, 230, 196) },
		Radius = UDim.new(0, 22),
		Visible = false,
		ShadowDepth = 7,
		Stroke = 4,
		ZIndex = Z_MODAL,
	})
	local ribbonHolder, ribbonBody = chunk({
		Name = "Ribbon",
		Parent = holder,
		Size = UDim2.fromOffset(math.min(size.X - 60, 340), 50),
		Position = UDim2.new(0.5, 0, 0, -24),
		AnchorPoint = Vector2.new(0.5, 0),
		Colors = GOLD,
		Radius = UDim.new(0, 14),
	})
	ribbonHolder.ZIndex = 3
	local titleLabel = label({ Parent = ribbonBody, Size = UDim2.fromScale(1, 1), TextSize = 28, Text = title })
	return holder, body, titleLabel
end

local function chunkyButton(
	parent,
	name: string,
	size: UDim2,
	pos: UDim2,
	colors,
	text: string,
	onClick,
	iconName: string?
)
	local holder, body, grad = chunk({
		Name = name,
		Parent = parent,
		Size = size,
		Position = pos,
		Colors = colors,
		Radius = UDim.new(0, 14),
		Button = true,
	})
	local icon = nil
	local l
	if iconName then
		icon = Icons.create(iconName, {
			Parent = body,
			Size = UDim2.fromOffset(34, 34),
			Position = UDim2.new(0, 10, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = 2,
		})
		l = label({
			Parent = body,
			Size = UDim2.new(1, -56, 1, 0),
			Position = UDim2.fromOffset(46, 0),
			TextSize = 24,
			Text = text,
		})
	else
		l = label({ Parent = body, Size = UDim2.fromScale(1, 1), TextSize = 24, Text = text })
	end
	pressable(holder, body, onClick)
	return { holder = holder, body = body, grad = grad, label = l, icon = icon }
end

function Hud:openModal(holder: GuiObject)
	if holder.Visible then
		return
	end
	holder.Visible = true
	local s = scaleOf(holder)
	s.Value = 0.55
	tween(s, 0.38, { Value = 1 }, Enum.EasingStyle.Back)
	self.backdrop.Visible = true
	tween(self.backdrop, 0.25, { BackgroundTransparency = 0.45 })
	play("whoosh")
end

function Hud:closeModal(holder: GuiObject)
	if not holder.Visible then
		return
	end
	local s = scaleOf(holder)
	local t = tween(s, 0.14, { Value = 0.7 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	t.Completed:Once(function()
		holder.Visible = false
		s.Value = 1
		if not (self.report.Visible or self.shop.Visible or self.linen.Visible) then
			tween(self.backdrop, 0.2, { BackgroundTransparency = 1 }).Completed:Once(function()
				if not (self.report.Visible or self.shop.Visible or self.linen.Visible) then
					self.backdrop.Visible = false
				end
			end)
		end
	end)
	play("whooshOut")
end

-- Tutorial card (top right): ribbon with progress, instruction text, NEXT / SKIP.
function Hud:buildTutorial()
	local holder, body = chunk({
		Name = "Tutorial",
		Parent = self.root,
		Size = UDim2.fromOffset(340, 156),
		Position = UDim2.new(1, -14, 0, 150),
		AnchorPoint = Vector2.new(1, 0),
		Colors = { CREAM, Color3.fromRGB(244, 230, 196) },
		Radius = UDim.new(0, 18),
		Visible = false,
		ZIndex = 8,
	})
	local ribbonHolder, ribbonBody = chunk({
		Name = "Ribbon",
		Parent = holder,
		Size = UDim2.fromOffset(190, 32),
		Position = UDim2.fromOffset(14, -18),
		Colors = BLUE,
		Radius = UDim.new(0, 10),
		ShadowDepth = 3,
		Stroke = 2.5,
	})
	ribbonHolder.ZIndex = 2
	self.tutorialIcon = Icons.create("star", {
		Parent = ribbonBody,
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(0, 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 2,
	})
	self.tutorialTitle = label({
		Parent = ribbonBody,
		Size = UDim2.new(1, -40, 1, 0),
		Position = UDim2.fromOffset(34, 0),
		TextSize = 18,
		Text = "TUTORIAL",
	})
	self.tutorialText = label({
		Parent = body,
		Size = UDim2.new(1, -28, 1, -70),
		Position = UDim2.fromOffset(14, 22),
		TextSize = 19,
		TextColor3 = TEXT_DARK,
		Stroke = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
	})
	self.tutorialNext = chunkyButton(
		body,
		"Next",
		UDim2.fromOffset(110, 38),
		UDim2.new(1, -124, 1, -48),
		GREEN,
		"NEXT",
		function()
			if self.onTutorialNext then
				self.onTutorialNext()
			end
		end,
		"next"
	)
	self.tutorialNext.label.TextSize = 20
	local skip = chunkyButton(
		body,
		"Skip",
		UDim2.fromOffset(100, 38),
		UDim2.new(0, 14, 1, -48),
		GREY,
		"SKIP",
		function()
			if self.onTutorialSkip then
				self.onTutorialSkip()
			end
		end,
		"skip"
	)
	skip.label.TextSize = 18
	self.tutorialCard = holder
	self.tutorialBody = body
end

-- info = { title, text, showNext } or nil to hide.
function Hud:setTutorial(info)
	local card = self.tutorialCard
	if not info then
		if card.Visible then
			local t = tween(
				card,
				0.25,
				{ Position = UDim2.new(1, 380, 0, 150) },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			t.Completed:Once(function()
				if not self.tutorialInfo then
					card.Visible = false
				end
			end)
		end
		self.tutorialInfo = nil
		return
	end
	local changed = not self.tutorialInfo or self.tutorialInfo.text ~= info.text
	self.tutorialInfo = info
	self.tutorialTitle.Text = info.title
	self.tutorialIcon:set(info.icon or "star")
	self.tutorialText.Text = info.text
	self.tutorialNext.holder.Visible = info.showNext == true
	if not card.Visible then
		card.Visible = true
		card.Position = UDim2.new(1, 380, 0, 150)
		tween(card, 0.45, { Position = UDim2.new(1, -14, 0, 150) }, Enum.EasingStyle.Back)
		play("notify")
	elseif changed then
		pop(card, 0.06)
		shineSweep(self.tutorialBody)
		play("notify")
	end
end

function Hud:buildReport()
	local holder, body, title = modal(self.root, "Report", Vector2.new(480, 494), "NIGHT REPORT")
	self.report = holder
	self.reportTitle = title
	self.reportRows = {}
	self.reportRowLabels = {}
	local names = { "Rent", "Deposits", "Tips", "Purchases", "Bill", "Cash", "Guests", "Lost" }
	local rowIcons = {
		Rent = "key",
		Deposits = "calendar",
		Tips = "hand",
		Purchases = "trolley",
		Bill = "warning",
		Cash = "coin",
		Guests = "guests",
		Lost = "hourglass",
	}
	for i, n in ipairs(names) do
		local y = 40 + 34 * (i - 1)
		local row = make("Frame", {
			BackgroundColor3 = WHITE,
			BackgroundTransparency = if i % 2 == 1 then 0.35 else 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -40, 0, 30),
			Position = UDim2.fromOffset(20, y),
			Parent = body,
		})
		corner(row, UDim.new(0, 8))
		Icons.create(rowIcons[n], {
			Parent = row,
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.new(0, 6, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
		})
		local name = label({
			Parent = row,
			Size = UDim2.fromScale(0.4, 1),
			Position = UDim2.fromOffset(38, 0),
			TextSize = 19,
			TextColor3 = TEXT_DARK,
			Stroke = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = n,
		})
		local value = label({
			Parent = row,
			Size = UDim2.new(0.55, -14, 1, 0),
			Position = UDim2.fromScale(0.45, 0),
			TextSize = 19,
			TextColor3 = TEXT_DARK,
			Stroke = 0,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = "",
		})
		self.reportRows[n] = value
		table.insert(self.reportRowLabels, { name, value })
		if n == "Cash" then
			-- "$before [arrow] $after": the arrow is an icon, not a glyph.
			value.Size = UDim2.new(0, 80, 1, 0)
			value.Position = UDim2.new(1, -90, 0, 0)
			local before = label({
				Parent = row,
				Size = UDim2.new(0, 80, 1, 0),
				Position = UDim2.new(1, -206, 0, 0),
				TextSize = 19,
				TextColor3 = TEXT_DARK,
				Stroke = 0,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = "",
			})
			Icons.create("arrowRight", {
				Parent = row,
				Size = UDim2.fromOffset(24, 24),
				Position = UDim2.new(1, -110, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
			})
			self.reportCashBefore = before
			table.insert(self.reportRowLabels, { before })
		end
	end
	local resultHolder, resultBody, resultGrad = chunk({
		Name = "Result",
		Parent = body,
		Size = UDim2.new(1, -40, 0, 46),
		Position = UDim2.fromOffset(20, 40 + 34 * #names + 10),
		Colors = GREEN,
		Radius = UDim.new(0, 14),
	})
	self.resultHolder = resultHolder
	self.resultBody = resultBody
	self.resultGrad = resultGrad
	self.resultIcon = Icons.create("check", {
		Parent = resultBody,
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 2,
	})
	self.resultText = label({
		Parent = resultBody,
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromOffset(50, 0),
		TextSize = 21,
		Text = "",
	})
	self.restartButton = chunkyButton(
		body,
		"Restart",
		UDim2.fromOffset(200, 54),
		UDim2.new(0.5, -210, 1, -70),
		BLUE,
		"PLAY AGAIN",
		function()
			self.callbacks.onRestart()
		end,
		"play"
	)
	self.lobbyButton = chunkyButton(
		body,
		"Lobby",
		UDim2.fromOffset(200, 54),
		UDim2.new(0.5, 10, 1, -70),
		PURPLE,
		"LOBBY",
		function()
			self.callbacks.onBackToLobby()
		end,
		"home"
	)
end

------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------

-- Converts a GUI object's on-screen point into root (design) space.
function Hud:rootPoint(gui: GuiObject, anchor: Vector2): Vector2
	local abs = gui.AbsolutePosition + gui.AbsoluteSize * anchor
	return (abs - self.root.AbsolutePosition) / self.uiScale.Scale
end

-- "+$25" style text that rises from a GUI object and fades.
function Hud:floatText(from: GuiObject, text: string, color: Color3)
	local p = self:rootPoint(from, Vector2.new(0.62, 0.5))
	local t = label({
		Parent = self.fx,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(160, 40),
		Position = UDim2.fromOffset(p.X, p.Y),
		TextSize = 30,
		TextColor3 = color,
		Text = text,
		ZIndex = Z_TOP + 1,
	})
	local s = scaleOf(t)
	s.Value = 0.4
	tween(s, 0.3, { Value = 1.15 }, Enum.EasingStyle.Back)
	local rise = tween(t, 1.1, { Position = UDim2.fromOffset(p.X + 24, p.Y - 30) }, Enum.EasingStyle.Quad)
	task.delay(0.6, function()
		tween(t, 0.5, { TextTransparency = 1 })
		local stroke = t:FindFirstChildOfClass("UIStroke")
		if stroke then
			tween(stroke, 0.5, { Transparency = 1 })
		end
	end)
	rise.Completed:Once(function()
		t:Destroy()
	end)
end

function Hud:confetti(count: number)
	local size = self.root.AbsoluteSize / self.uiScale.Scale
	for _ = 1, count do
		local piece = make("Frame", {
			BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)],
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22)),
			Position = UDim2.fromOffset(math.random(0, math.floor(size.X)), -30),
			Rotation = math.random(0, 360),
			ZIndex = Z_TOP + 2,
			Parent = self.fx,
		})
		corner(piece, UDim.new(0, 3))
		local duration = math.random(16, 28) / 10
		local t = tween(piece, duration, {
			Position = UDim2.fromOffset(piece.Position.X.Offset + math.random(-120, 120), size.Y + 40),
			Rotation = piece.Rotation + math.random(-540, 540),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		t.Completed:Once(function()
			piece:Destroy()
		end)
	end
end

------------------------------------------------------------------------
-- Feedback
------------------------------------------------------------------------

local TOAST_SOUND = { ok = "pop", error = "error", alert = "alert" }
local TOAST_ICON = { ok = "check", error = "cross", alert = "warning" }

function Hud:toast(message: string, kind: string?)
	local colors = CARD
	local textColor = TEXT_DARK
	local strokeWidth = 0
	if kind == "ok" then
		colors, textColor, strokeWidth = GREEN, WHITE, nil
	elseif kind == "error" then
		colors, textColor, strokeWidth = RED, WHITE, nil
	elseif kind == "alert" then
		colors, textColor, strokeWidth = ORANGE, WHITE, nil
	end
	self.toastOrder += 1
	local holder, body = chunk({
		Name = "Toast",
		Parent = self.toasts,
		Size = UDim2.fromOffset(560, 38),
		Colors = colors,
		Radius = UDim.new(1, 0),
		LayoutOrder = self.toastOrder,
		ShadowDepth = 4,
		Shine = false,
	})
	Icons.create(TOAST_ICON[kind or ""] or "bell", {
		Parent = body,
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(0, 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 2,
	})
	local text = label({
		Parent = body,
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromOffset(42, 0),
		TextSize = 19,
		TextColor3 = textColor,
		Stroke = strokeWidth,
		Text = message,
	})
	local s = scaleOf(holder)
	s.Value = 0.5
	tween(s, 0.35, { Value = 1 }, Enum.EasingStyle.Back)
	if kind == "error" then
		wiggle(holder, 3, 0.3)
	elseif kind == "alert" then
		shineSweep(body)
	end
	play(TOAST_SOUND[kind or ""] or "notify")

	local list = {}
	for _, c in ipairs(self.toasts:GetChildren()) do
		if c:IsA("Frame") then
			table.insert(list, c)
		end
	end
	table.sort(list, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #list > 4 do
		local oldest = table.remove(list, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	task.delay(3.5, function()
		if holder.Parent then
			local info = TweenInfo.new(0.35)
			TweenService:Create(text, info, { TextTransparency = 1 }):Play()
			TweenService:Create(s, info, { Value = 0.85 }):Play()
			for _, d in ipairs(holder:GetDescendants()) do
				if d:IsA("Frame") or d:IsA("TextButton") then
					TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
				elseif d:IsA("UIStroke") then
					TweenService:Create(d, info, { Transparency = 1 }):Play()
				end
			end
			task.wait(0.4)
			holder:Destroy()
		end
	end)
end

-- Big centred announcement (phase changes).
function Hud:banner(title: string, subtitle: string?, iconName: string?)
	self.bannerIcon:set(iconName or "star")
	self.bannerToken += 1
	local token = self.bannerToken
	self.bannerTitle.Text = title
	self.bannerSub.Text = subtitle or ""
	local frame = self.bannerFrame
	frame.Visible = true
	frame.Rotation = -6
	local s = scaleOf(frame)
	s.Value = 0.3
	tween(s, 0.45, { Value = 1 }, Enum.EasingStyle.Back)
	tween(frame, 0.5, { Rotation = 0 }, Enum.EasingStyle.Elastic)
	task.delay(0.25, function()
		shineSweep(self.bannerBody)
	end)
	play("sweep")
	task.delay(2.6, function()
		if self.bannerToken == token then
			local out = tween(s, 0.2, { Value = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			out.Completed:Once(function()
				if self.bannerToken == token then
					frame.Visible = false
				end
			end)
		end
	end)
end

------------------------------------------------------------------------
-- Supply shop panel
------------------------------------------------------------------------

function Hud:buildShop()
	local items = self.shopItems
	local rows = math.ceil(#items / 2)
	local holder, body = modal(self.root, "Shop", Vector2.new(580, 120 + rows * 176), "SUPPLY SHOP")
	self.shop = holder

	-- Wallet + stock strip.
	local strip = make("Frame", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -40, 0, 44),
		Position = UDim2.fromOffset(20, 38),
		Parent = body,
	})
	corner(strip, UDim.new(0, 12))
	local function stat(iconName, x)
		Icons.create(iconName, {
			Parent = strip,
			Size = UDim2.fromOffset(34, 34),
			Position = UDim2.new(0, x, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
		})
		return label({
			Parent = strip,
			Size = UDim2.fromOffset(110, 40),
			Position = UDim2.new(0, x + 40, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			TextSize = 26,
			TextColor3 = TEXT_DARK,
			Stroke = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		})
	end
	self.shopCash = stat("coin", 12)
	self.shopSheets = stat("sheet", 190)
	self.shopTowels = stat("towel", 330)

	self.shopCards = {}
	for i, item in ipairs(items) do
		local col = (i - 1) % 2
		local row = (i - 1) // 2
		local cardHolder, card = chunk({
			Name = "Item_" .. item.id,
			Parent = body,
			Size = UDim2.fromOffset(255, 160),
			Position = UDim2.fromOffset(20 + col * 285, 98 + row * 176),
			Colors = CARD,
			Radius = UDim.new(0, 16),
			ShadowDepth = 4,
		})
		local medal = make("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 240, 200),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(78, 78),
			Position = UDim2.fromOffset(10, 10),
			Parent = card,
		})
		corner(medal, UDim.new(0, 14))
		outline(medal, 2.5)
		local icon = Icons.create(item.icon, {
			Parent = medal,
			Size = UDim2.fromScale(0.92, 0.92),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
		})
		label({
			Parent = card,
			Size = UDim2.new(1, -104, 0, 30),
			Position = UDim2.fromOffset(96, 10),
			TextSize = 22,
			TextColor3 = TEXT_DARK,
			Stroke = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = item.name,
		})
		label({
			Parent = card,
			Size = UDim2.new(1, -104, 0, 44),
			Position = UDim2.fromOffset(96, 40),
			TextSize = 16,
			Font = Enum.Font.GothamMedium,
			TextColor3 = Color3.fromRGB(110, 90, 70),
			Stroke = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = item.desc,
		})
		-- Price tag.
		local _, priceBody = chunk({
			Name = "Price",
			Parent = card,
			Size = UDim2.fromOffset(96, 34),
			Position = UDim2.fromOffset(10, 112),
			Colors = GOLD,
			Radius = UDim.new(1, 0),
			ShadowDepth = 3,
			Stroke = 2.5,
			Shine = false,
		})
		Icons.create("coin", {
			Parent = priceBody,
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(0, 4, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = 2,
		})
		label({
			Parent = priceBody,
			Size = UDim2.new(1, -36, 1, 0),
			Position = UDim2.fromOffset(32, 0),
			TextSize = 22,
			Text = ("$%d"):format(item.cost),
		})
		local buy = chunkyButton(
			card,
			"Buy",
			UDim2.fromOffset(128, 42),
			UDim2.fromOffset(117, 108),
			GREEN,
			"BUY",
			function()
				self:tryBuy(i)
			end,
			"check"
		)
		buy.label.TextSize = 22
		self.shopCards[i] = { item = item, holder = cardHolder, buy = buy, icon = icon }
	end

	local close = chunkyButton(body, "Close", UDim2.fromOffset(48, 48), UDim2.new(1, -30, 0, -30), RED, "", function()
		self:closeShop()
	end, "cross")
	close.holder.ZIndex = 4
	close.icon.frame.Position = UDim2.fromScale(0.5, 0.5)
	close.icon.frame.AnchorPoint = Vector2.new(0.5, 0.5)
end

function Hud:tryBuy(i: number)
	local card = self.shopCards[i]
	local s = self.state
	if not card or not s then
		return
	end
	local item = card.item
	if (item.trolley and s.trolley) or s.cash < item.cost then
		play("error")
		wiggle(card.holder, 4, 0.3)
		return
	end
	pop(card.holder, 0.08)
	shineSweep(card.holder:FindFirstChild("Body"))
	self.callbacks.onBuy(item.id)
end

function Hud:openShop()
	self:openModal(self.shop)
	self:renderShop()
end

function Hud:closeShop()
	self:closeModal(self.shop)
end

function Hud:renderShop()
	local s = self.state
	if not s or not self.shop.Visible then
		return
	end
	if not (s.phase == "Preparation" or s.phase == "Night" or s.phase == "Closing") then
		self:closeShop()
		return
	end
	self.shopCash.Text = ("$%d"):format(s.cash)
	self.shopSheets.Text = tostring(s.stock.Sheet)
	self.shopTowels.Text = tostring(s.stock.Towel)
	for _, c in ipairs(self.shopCards) do
		local item = c.item
		local owned = item.trolley and s.trolley
		local afford = s.cash >= item.cost
		if owned then
			c.buy.label.Text = "OWNED"
			c.buy.icon:set("check")
			setColors(c.buy.grad, GREY)
		elseif afford then
			c.buy.label.Text = "BUY"
			c.buy.icon:set("coin")
			setColors(c.buy.grad, GREEN)
		else
			c.buy.label.Text = "NEED $" .. (item.cost - s.cash)
			c.buy.icon:set("cross")
			setColors(c.buy.grad, GREY)
		end
	end
end

------------------------------------------------------------------------
-- Linen closet panel
------------------------------------------------------------------------

function Hud:buildLinen()
	local holder, body = modal(self.root, "Linen", Vector2.new(560, 440), "LINEN CLOSET")
	self.linen = holder

	-- "Your hands" strip with one slot per carry capacity.
	local strip = make("Frame", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -40, 0, 78),
		Position = UDim2.fromOffset(20, 38),
		Parent = body,
	})
	corner(strip, UDim.new(0, 12))
	Icons.create("hand", {
		Parent = strip,
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
	})
	label({
		Parent = strip,
		Size = UDim2.fromOffset(150, 30),
		Position = UDim2.new(0, 58, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextSize = 22,
		TextColor3 = TEXT_DARK,
		Stroke = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "YOUR HANDS",
	})
	self.linenSlots = {}
	for i = 1, 2 do
		local slotHolder, slotBody, slotGrad = chunk({
			Name = "Slot" .. i,
			Parent = strip,
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.new(0, 214 + (i - 1) * 72, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Colors = GREY,
			Radius = UDim.new(0, 12),
			ShadowDepth = 3,
		})
		local icon = Icons.create("sheet", {
			Parent = slotBody,
			Size = UDim2.fromScale(0.8, 0.8),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 2,
		})
		self.linenSlots[i] = { holder = slotHolder, grad = slotGrad, icon = icon }
	end
	self.linenReturn = chunkyButton(
		strip,
		"Return",
		UDim2.fromOffset(150, 46),
		UDim2.new(1, -160, 0.5, -23),
		BLUE,
		"RETURN",
		function()
			local s = self.state
			local clean = 0
			for _, item in ipairs(s and s.carry or {}) do
				if item == "Sheet" or item == "Towel" then
					clean += 1
				end
			end
			if clean == 0 then
				play("error")
				wiggle(self.linenReturn.holder, 4, 0.3)
				return
			end
			self.callbacks.onReturnSupplies()
		end,
		"arrowDown"
	)
	self.linenReturn.label.TextSize = 20

	-- One big card per supply type.
	self.linenCards = {}
	for i, def in ipairs({
		{ item = "Sheet", icon = "sheet", name = "Clean Sheet", desc = "For changing dirty beds" },
		{ item = "Towel", icon = "towel", name = "Fresh Towel", desc = "For guests who ask for one" },
	}) do
		local cardHolder, card = chunk({
			Name = "Card_" .. def.item,
			Parent = body,
			Size = UDim2.fromOffset(245, 250),
			Position = UDim2.fromOffset(20 + (i - 1) * 275, 132),
			Colors = CARD,
			Radius = UDim.new(0, 16),
			ShadowDepth = 4,
		})
		local medal = make("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 240, 200),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(104, 104),
			Position = UDim2.new(0.5, 0, 0, 12),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = card,
		})
		corner(medal, UDim.new(0, 16))
		outline(medal, 2.5)
		Icons.create(def.icon, {
			Parent = medal,
			Size = UDim2.fromScale(0.9, 0.9),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
		})
		label({
			Parent = card,
			Size = UDim2.new(1, -20, 0, 28),
			Position = UDim2.fromOffset(10, 120),
			TextSize = 22,
			TextColor3 = TEXT_DARK,
			Stroke = 0,
			Text = def.name,
		})
		local stock = label({
			Parent = card,
			Size = UDim2.new(1, -20, 0, 24),
			Position = UDim2.fromOffset(10, 148),
			TextSize = 17,
			Font = Enum.Font.GothamMedium,
			TextColor3 = Color3.fromRGB(110, 90, 70),
			Stroke = 0,
			Text = def.desc,
		})
		local take = chunkyButton(
			card,
			"Take",
			UDim2.new(1, -24, 0, 50),
			UDim2.fromOffset(12, 186),
			GREEN,
			"TAKE",
			function()
				self:tryTake(i)
			end,
			def.icon
		)
		take.label.TextSize = 22
		self.linenCards[i] = { def = def, holder = cardHolder, take = take, stock = stock }
	end

	local close = chunkyButton(body, "Close", UDim2.fromOffset(48, 48), UDim2.new(1, -30, 0, -30), RED, "", function()
		self:closeLinen()
	end, "cross")
	close.holder.ZIndex = 4
	close.icon.frame.Position = UDim2.fromScale(0.5, 0.5)
	close.icon.frame.AnchorPoint = Vector2.new(0.5, 0.5)
end

function Hud:tryTake(i: number)
	local card = self.linenCards[i]
	local s = self.state
	if not card or not s then
		return
	end
	local inStock = s.stock[card.def.item] or 0
	if #s.carry >= s.carryCapacity or inStock <= 0 then
		play("error")
		wiggle(card.holder, 4, 0.3)
		return
	end
	pop(card.holder, 0.08)
	self.callbacks.onTakeSupply(card.def.item)
end

function Hud:openLinen()
	self:openModal(self.linen)
	self:renderLinen()
end

function Hud:closeLinen()
	self:closeModal(self.linen)
end

function Hud:renderLinen()
	local s = self.state
	if not s or not self.linen.Visible then
		return
	end
	if not (s.phase == "Preparation" or s.phase == "Night" or s.phase == "Closing") then
		self:closeLinen()
		return
	end
	-- Hands.
	local cleanCarried = 0
	for i, slot in ipairs(self.linenSlots) do
		slot.holder.Visible = i <= s.carryCapacity
		local item = s.carry[i]
		if item then
			slot.icon:set(ITEM_ICON[item] or "check")
			slot.icon.frame.Visible = true
			setColors(slot.grad, if item == "Trash" then ORANGE else TEAL)
			if item ~= "Trash" then
				cleanCarried += 1
			end
		else
			slot.icon.frame.Visible = false
			setColors(slot.grad, GREY)
		end
	end
	setColors(self.linenReturn.grad, if cleanCarried > 0 then BLUE else GREY)
	-- Cards.
	local full = #s.carry >= s.carryCapacity
	for _, c in ipairs(self.linenCards) do
		local left = s.stock[c.def.item] or 0
		c.stock.Text = ("%d left in the closet"):format(left)
		if left <= 0 then
			c.take.label.Text = "OUT OF STOCK"
			c.take.icon:set("cross")
			setColors(c.take.grad, GREY)
		elseif full then
			c.take.label.Text = "HANDS FULL"
			c.take.icon:set("hand")
			setColors(c.take.grad, GREY)
		else
			c.take.label.Text = "TAKE"
			c.take.icon:set(c.def.icon)
			setColors(c.take.grad, GREEN)
		end
	end
end

local function blockers(r): { string }
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
	return why
end

local function roomStatus(r): (string, any, any, string)
	if r.ready then
		return "READY", GREEN, GREEN, "check"
	elseif r.occupied then
		if r.towelRequest then
			return "TOWEL!", ORANGE, ORANGE, "towel"
		end
		return "BUSY", BLUE, BLUE, "sleep"
	elseif r.acBroken then
		return "FIX AC", RED, RED, "wrench"
	end
	return "CLEAN", ORANGE, ORANGE, "broom"
end

------------------------------------------------------------------------
-- Report reveal
------------------------------------------------------------------------

function Hud:revealReport(s)
	self:openModal(self.report)
	for i, pair in ipairs(self.reportRowLabels) do
		for _, l in ipairs(pair) do
			l.TextTransparency = 1
			task.delay(0.25 + i * 0.08, function()
				tween(l, 0.25, { TextTransparency = 0 })
			end)
		end
	end
	local r = s.report
	local stamp = scaleOf(self.resultHolder)
	stamp.Value = 0
	self.resultHolder.Rotation = -12
	task.delay(0.95, function()
		tween(stamp, 0.35, { Value = 1 }, Enum.EasingStyle.Back)
		tween(self.resultHolder, 0.4, { Rotation = 0 }, Enum.EasingStyle.Back)
		shineSweep(self.resultBody)
		if s.phase == "RunEnded" and s.complete then
			play("fanfare")
			self:confetti(90)
		elseif r.passed then
			play("paid")
			self:confetti(35)
		else
			play("fail")
			wiggle(self.report, 2, 0.5)
		end
	end)
end

------------------------------------------------------------------------
-- State rendering
------------------------------------------------------------------------

function Hud:setState(s)
	local prev = self.prev
	self.state = s
	local P = s.phase
	local active = P == "Preparation" or P == "Night" or P == "Closing"

	-- Night badge.
	self.nightNumber.Text = tostring(s.night)
	self.nightText.Text = ("NIGHT %d/%d"):format(s.night, s.totalNights)
	if prev and prev.night ~= s.night then
		local spin = scaleOf(self.nightStar)
		spin.Value = 1.4
		tween(spin, 0.6, { Value = 1 }, Enum.EasingStyle.Elastic)
		self.nightStarSpin = os.clock()
	end

	-- Cash: rolling number, floating delta, coin flip.
	self.cashTarget = s.cash
	if not prev then
		self.cashShown = s.cash
	elseif s.cash ~= prev.cash then
		local delta = s.cash - prev.cash
		if delta > 0 then
			self:floatText(self.cashHolder, ("+$%d"):format(delta), Color3.fromRGB(140, 255, 120))
			play("coin")
		else
			self:floatText(self.cashHolder, ("-$%d"):format(-delta), Color3.fromRGB(255, 120, 110))
		end
		pop(self.cashHolder, 0.14)
		self.coinSpin = os.clock()
	end
	setColors(self.cashGrad, if s.cash >= s.bill then GOLD else ORANGE)
	self.billText.Text = ("BILL $%d"):format(s.bill)

	-- Supplies and trolley.
	self.sheetCount.Text = tostring(s.stock.Sheet)
	self.towelCount.Text = tostring(s.stock.Towel)
	self.sheetCount.TextColor3 = if s.stock.Sheet == 0 then Color3.fromRGB(255, 150, 140) else WHITE
	if prev and (prev.stock.Sheet ~= s.stock.Sheet or prev.stock.Towel ~= s.stock.Towel) then
		pop(self.supHolder, 0.1)
		if s.stock.Sheet > prev.stock.Sheet then
			play("pop")
		end
	end
	self.trolleyText.Text = if s.trolley then "TROLLEY" else "NO TROLLEY"
	self.trolleyCheck.frame.Visible = s.trolley
	if prev and s.trolley and not prev.trolley then
		pop(self.trolleyHolder, 0.25)
		play("success")
	end

	-- Guests + status.
	local ns = s.nightStats
	self.guestText.Text = ("%d/%d"):format(ns.arrivals, s.plannedGuests)
	if prev and prev.nightStats.arrivals ~= ns.arrivals then
		pop(self.guestHolder, 0.12)
	end
	local status, statusColor, statusIcon
	if not s.power and active then
		status, statusColor, statusIcon = "POWER OUT", Color3.fromRGB(214, 52, 52), "lightning"
	elseif P == "Night" then
		status, statusColor, statusIcon = "OPEN", Color3.fromRGB(56, 160, 50), "bell"
	elseif P == "Closing" then
		status, statusColor, statusIcon = "CLOSING", Color3.fromRGB(226, 122, 30), "alarm"
	elseif P == "Preparation" then
		status, statusColor, statusIcon = "PREP", Color3.fromRGB(52, 128, 230), "sun"
	else
		status, statusColor, statusIcon = "CLOSED", Color3.fromRGB(120, 110, 100), "moon"
	end
	self.statusIcon:set(statusIcon)
	if self.statusText.Text ~= status then
		pop(self.statusHolder, 0.15)
	end
	self.statusText.Text = status
	self.statusText.TextColor3 = statusColor

	-- Rooms card.
	local readyCount = 0
	for i, row in ipairs(self.roomRows) do
		local r = s.rooms[i]
		if r then
			local chipText, chipColors, circleColors, mark = roomStatus(r)
			if r.ready then
				readyCount += 1
				row.text.Text = ("Room %d"):format(r.number or i)
			elseif r.occupied then
				row.text.Text = ("Room %d  · guest"):format(r.number or i)
			else
				row.text.Text = ("Room %d  · %s"):format(r.number or i, table.concat(blockers(r), ", "))
			end
			if prev and row.chipText.Text ~= chipText then
				pop(row.chip, 0.2)
				pop(row.circle, 0.3)
				if chipText == "READY" then
					play("pop")
				end
			end
			row.chipText.Text = chipText
			setColors(row.chipGrad, chipColors)
			setColors(row.circleGrad, circleColors)
			row.mark:set(mark)
		end
	end
	local roomsTitle = ("ROOMS %d/%d"):format(readyCount, #self.roomRows)
	if prev and self.roomsTitle.Text ~= roomsTitle then
		pop(self.roomsRibbon, 0.12)
	end
	self.roomsTitle.Text = roomsTitle

	-- Status tiles.
	self.tileQueue.value.Text = ("%d waiting"):format(s.queueLength)
	setColors(self.tileQueue.grad, if s.queueLength >= 3 then RED else ORANGE)
	if prev and s.queueLength > prev.queueLength then
		pop(self.tileQueue.holder, 0.12)
	end
	self.tileHands.value.Text = ("%d/%d"):format(#s.carry, s.carryCapacity)
	if not s.power then
		self.tileWeather.icon:set("lightning")
		self.tileWeather.value.Text = "Power out"
		setColors(self.tileWeather.grad, RED)
	elseif s.rain then
		self.tileWeather.icon:set("rain")
		self.tileWeather.value.Text = "Rain"
		setColors(self.tileWeather.grad, BLUE)
	elseif s.rainForecast and P == "Preparation" then
		self.tileWeather.icon:set("rain")
		self.tileWeather.value.Text = "Storm soon"
		setColors(self.tileWeather.grad, PURPLE)
	else
		self.tileWeather.icon:set(if P == "Preparation" then "sun" else "moon")
		self.tileWeather.value.Text = "Clear"
		setColors(self.tileWeather.grad, TEAL)
	end
	self.tileBest.value.Text = ("%d night%s"):format(s.bestNights, if s.bestNights == 1 then "" else "s")

	-- Bottom bar: carried items.
	for i, t in ipairs(self.handTiles) do
		t.holder.Visible = i <= s.carryCapacity
		local item = s.carry[i]
		local before = prev and prev.carry[i]
		if item then
			t.icon:set(ITEM_ICON[item] or "check")
			t.icon.frame.Visible = true
			t.caption.Text = item:upper()
			setColors(t.grad, if item == "Trash" then ORANGE else TEAL)
		else
			t.icon.frame.Visible = false
			t.caption.Text = "EMPTY"
			setColors(t.grad, GREY)
		end
		if prev and item ~= before then
			pop(t.boxHolder, if item then 0.25 else 0.1)
			if item then
				play("pop")
			end
		end
	end
	local readyVisible = P == "Preparation"
	self.readyTile.holder.Visible = readyVisible
	if readyVisible then
		if s.isReady then
			self.readyTile.caption.Text = ("%d/%d"):format(s.readyCount, s.playerCount)
			setColors(self.readyTile.grad, GREY)
		else
			self.readyTile.caption.Text = "READY"
			setColors(self.readyTile.grad, GREEN)
		end
	end

	-- Alert ribbon.
	local powerOut = not s.power and active
	if powerOut then
		self.alertText.Text = "POWER OUT! Reset the breaker in the lobby"
		self.alertIcon:set("lightning")
		setColors(self.alertGrad, RED)
	elseif P == "Preparation" then
		local coop = if s.planPlayers > 1 then (" · %d players"):format(s.planPlayers) else ""
		self.alertText.Text = ("~%d guests%s · %s"):format(s.plannedGuests, coop, s.forecast)
		self.alertIcon:set(if s.rainForecast then "rain" else "guests")
		setColors(self.alertGrad, PURPLE)
	end
	local alertVisible = powerOut or P == "Preparation"
	if alertVisible and not self.alert.Visible then
		self.alert.Visible = true
		local a = scaleOf(self.alert)
		a.Value = 0.6
		tween(a, 0.35, { Value = 1 }, Enum.EasingStyle.Back)
	elseif not alertVisible then
		self.alert.Visible = false
	end
	if prev and prev.power and not s.power and active then
		play("power")
		wiggle(self.alert, 4, 0.6)
	elseif prev and not prev.power and s.power then
		play("success")
	end

	-- Report / run ended.
	if (P == "Report" or P == "RunEnded") and s.report then
		local r = s.report
		self.reportRows.Rent.Text = ("+$%d"):format(r.rent)
		self.reportRows.Deposits.Text = ("+$%d"):format(r.deposits or 0)
		self.reportRows.Tips.Text = ("+$%d"):format(r.tips)
		self.reportRows.Purchases.Text = ("-$%d"):format(r.purchases)
		self.reportRows.Bill.Text = ("-$%d"):format(r.bill)
		self.reportCashBefore.Text = ("$%d"):format(r.cashBefore)
		self.reportRows.Cash.Text = ("$%d"):format(r.cashAfter)
		self.reportRows.Guests.Text = ("%d served / %d planned"):format(r.served, r.guestsPlanned)
		self.reportRows.Lost.Text = ("%d walkout · %d unserved · %d towel"):format(
			r.walkouts,
			r.unserved,
			r.missedTowels
		)
		if r.passed then
			self.resultText.Text = ("BILL PAID! Nights survived: %d"):format(r.nightsSurvived)
			self.resultIcon:set(if P == "RunEnded" and s.complete then "trophy" else "check")
			setColors(self.resultGrad, GREEN)
		else
			self.resultText.Text = ("SHORT BY $%d. THE MOTEL CLOSES"):format(r.shortfall)
			self.resultIcon:set("cross")
			setColors(self.resultGrad, RED)
		end
		if P == "RunEnded" then
			self.reportTitle.Text = if s.complete then "PROTOTYPE COMPLETE!" else "RUN OVER"
			self.restartButton.holder.Visible = true
			self.lobbyButton.holder.Visible = true
		else
			self.reportTitle.Text = ("NIGHT %d REPORT"):format(r.night)
			self.restartButton.holder.Visible = false
			self.lobbyButton.holder.Visible = false
		end
		local key = P .. tostring(r.night) .. tostring(s.runId)
		if self.reportKey ~= key then
			self.reportKey = key
			if self.report.Visible then
				-- Report -> RunEnded: re-stamp the result.
				self.report.Visible = false
			end
			self:revealReport(s)
		end
	else
		self.reportKey = nil
		self:closeModal(self.report)
	end

	self.prev = s
	self:renderShop()
	self:renderLinen()
end

-- Called every frame: timers, rolling numbers and idle motion.
function Hud:tick()
	local s = self.state
	if not s then
		return
	end
	local clock = os.clock()
	local dt = math.min(clock - self.lastTick, 0.1)
	self.lastTick = clock
	local now = Workspace:GetServerTimeNow()

	-- Rolling cash number.
	if self.cashShown ~= self.cashTarget then
		local diff = self.cashTarget - self.cashShown
		self.cashShown += diff * math.min(1, dt * 9)
		if math.abs(self.cashTarget - self.cashShown) < 0.5 then
			self.cashShown = self.cashTarget
		end
	end
	self.cashText.Text = ("$%d"):format(math.floor(self.cashShown + 0.5))

	-- Coin flip after a cash change; star spin after a new night.
	if self.coinSpin then
		local k = (clock - self.coinSpin) / 0.5
		self.coinIcon.frame.Rotation = if k < 1 then k * 360 else 0
		if k >= 1 then
			self.coinSpin = nil
		end
	end
	local starRot = math.sin(clock * 1.6) * 6
	if self.nightStarSpin then
		local k = (clock - self.nightStarSpin) / 0.8
		if k < 1 then
			starRot += (1 - (1 - k) ^ 3) * 360
		else
			self.nightStarSpin = nil
		end
	end
	self.nightStar.Rotation = starRot

	-- Phase timer bar.
	local labelText = s.phase
	if s.phase == "Preparation" then
		labelText = "PREP"
	elseif s.phase == "RunEnded" then
		labelText = if s.complete then "COMPLETE" else "RUN OVER"
	end
	local urgent = false
	if s.phaseEndsAt and s.phaseStartedAt then
		local total = math.max(0.001, s.phaseEndsAt - s.phaseStartedAt)
		local left = s.phaseEndsAt - now
		local frac = math.clamp(left / total, 0, 1)
		self.phaseFill.Size = UDim2.new(frac, -8 * frac, 1, -8)
		self.phaseFill.Visible = frac > 0.01
		self.phaseText.Text = ("%s  %s"):format(labelText:upper(), fmtTime(left))
		urgent = (s.phase == "Night" and left < 30) or (s.phase == "Preparation" and left < 10)
		setColors(self.phaseFillGrad, if urgent then ORANGE else BLUE)
	else
		self.phaseFill.Visible = false
		self.phaseText.Text = labelText:upper()
	end
	scaleOf(self.phaseHolder, "Pulse").Value = if urgent then 1 + math.abs(math.sin(clock * 6)) * 0.06 else 1

	-- Queue tile: countdown + shake when the next guest is about to leave.
	local shake = 0
	if s.frontPatienceEndsAt and s.queueLength > 0 then
		local left = math.max(0, math.ceil(s.frontPatienceEndsAt - now))
		self.tileQueue.title.Text = ("QUEUE · %ds"):format(left)
		if left <= 10 then
			shake = math.sin(clock * 30) * 3
		end
	else
		self.tileQueue.title.Text = "QUEUE"
	end
	self.tileQueue.holder.Rotation = shake

	-- READY tile breathes until pressed; power-out ribbon throbs.
	local readyPulse = scaleOf(self.readyTile.holder, "Pulse")
	readyPulse.Value = if s.phase == "Preparation" and not s.isReady then 1 + math.sin(clock * 5) * 0.045 else 1
	scaleOf(self.alert, "Pulse").Value = if not s.power then 1 + math.abs(math.sin(clock * 5)) * 0.05 else 1
end

return Hud
