--!nonstrict
--[[
	HUD for Run a Motel. Display only: every number comes from the server
	snapshot.

	Visual language: chunky cartoon simulator UI. Thick dark outlines,
	vertical gradients, a drop shadow under every panel, Fredoka text with
	an outline, white cards with a gold ribbon, and a bar of big tiles at
	the bottom. Authored for 1280x720 and scaled with UIScale. The bottom
	bar stays centred so it does not collide with the mobile thumbstick or
	jump button.
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

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

local ITEM_ICON = { Sheet = "🛏", Towel = "🧺", Trash = "🗑" }

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
	the gradient body on top. Returns holder, body. Put content in body.
]]
local function chunk(props)
	local holder = make("Frame", {
		Name = props.Name or "Chunk",
		BackgroundTransparency = 1,
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
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
	-- Glossy highlight on the top half.
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

-- Small press animation for chunky buttons.
local function pressable(_holder: Frame, body: GuiButton, onActivate)
	body.Activated:Connect(onActivate)
	body.MouseButton1Down:Connect(function()
		body.Position = UDim2.fromOffset(0, 3)
	end)
	local function release()
		body.Position = UDim2.fromOffset(0, 0)
	end
	body.MouseButton1Up:Connect(release)
	body.MouseLeave:Connect(release)
end

-- A circular icon "medallion" that overlaps the left edge of a pill.
local function medallion(parent, size: number, colors, icon: string, iconSize: number?)
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
	local l = label({
		Name = "Icon",
		Parent = body,
		Size = UDim2.fromScale(1, 1),
		Text = icon,
		TextSize = iconSize or size * 0.55,
	})
	return holder, l
end

local function fmtTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------

function Hud.new(playerGui: PlayerGui, config, callbacks)
	local self = setmetatable({}, Hud)
	local roomCount = config.roomCount
	self.rent = config.economy.rent
	self.callbacks = callbacks
	self.state = nil
	self.roomCount = roomCount

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

	self:buildTopBar()
	self:buildRoomsCard()
	self:buildStatusTiles()
	self:buildBottomBar()
	self:buildBanner()
	self:buildAlert()
	self:buildToasts()
	self:buildPicker()
	self:buildReport()
	self:buildTutorial()
	return self
end

-- Top bar: night badge + phase bar, cash, supplies, guests ------------------
function Hud:buildTopBar()
	local root = self.root
	local top = make("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(980, 96),
		Parent = root,
	})
	self.top = top

	-- Night badge (big star) + night ribbon + phase progress bar.
	local nightGroup = make("Frame", {
		Name = "NightGroup",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(250, 80),
		Position = UDim2.fromOffset(0, 0),
		Parent = top,
	})
	local _phaseHolder, phaseBody = chunk({
		Name = "PhaseBar",
		Parent = nightGroup,
		Size = UDim2.fromOffset(190, 34),
		Position = UDim2.fromOffset(52, 30),
		Colors = { Color3.fromRGB(80, 70, 110), Color3.fromRGB(50, 42, 72) },
		Radius = UDim.new(1, 0),
		Shine = false,
	})
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
	self.nightText = label({
		Parent = ribbonBody,
		Size = UDim2.fromScale(1, 1),
		TextSize = 15,
		Text = "NIGHT 1/3",
	})
	self.nightStar = label({
		Name = "Star",
		Parent = nightGroup,
		Size = UDim2.fromOffset(84, 84),
		Position = UDim2.fromOffset(-14, -6),
		Text = "★",
		TextSize = 84,
		TextColor3 = Color3.fromRGB(255, 208, 60),
		Stroke = 4,
		ZIndex = 4,
	})
	self.nightNumber = label({
		Name = "Number",
		Parent = nightGroup,
		Size = UDim2.fromOffset(84, 84),
		Position = UDim2.fromOffset(-14, -2),
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
	self.cashGrad = cashGrad
	medallion(cashHolder, 58, GOLD, "$", 32)
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

	-- Supplies pill (green) + trolley sub-pill.
	local _supHolder, supBody = chunk({
		Name = "Supplies",
		Parent = top,
		Size = UDim2.fromOffset(230, 50),
		Position = UDim2.fromOffset(530, 4),
		Colors = GREEN,
		Radius = UDim.new(1, 0),
	})
	self.stockText = label({
		Parent = supBody,
		Size = UDim2.fromScale(1, 1),
		TextSize = 26,
		Text = "",
	})
	local _trolleyHolder, trolleyBody = chunk({
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
	self.trolleyText = label({
		Parent = trolleyBody,
		Size = UDim2.fromScale(1, 1),
		TextSize = 16,
		TextColor3 = TEXT_DARK,
		Stroke = 0,
		Text = "",
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
	medallion(guestHolder, 58, ORANGE, "👥", 28)
	self.guestText = label({
		Parent = guestBody,
		Size = UDim2.new(1, -30, 1, 0),
		Position = UDim2.fromOffset(26, 0),
		TextSize = 30,
		Text = "0/0",
	})
	local _statusHolder, statusBody = chunk({
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
	self.statusText = label({
		Parent = statusBody,
		Size = UDim2.fromScale(1, 1),
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
	self.roomsTitle = label({
		Parent = ribbonBody,
		Size = UDim2.fromScale(1, 1),
		TextSize = 19,
		Text = "ROOMS 0/0",
	})
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
		local circleStroke = outline(circle, 2.5)
		local circleGrad = gradient(circle, GREEN)
		local mark = label({
			Parent = circle,
			Size = UDim2.fromScale(1, 1),
			TextSize = 18,
			Text = "✓",
			Stroke = 1.5,
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
			Text = "Room " .. i,
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
		local chipText = label({
			Parent = chipBody,
			Size = UDim2.fromScale(1, 1),
			TextSize = 13,
			Text = "READY",
		})
		self.roomRows[i] = {
			circleGrad = circleGrad,
			circleStroke = circleStroke,
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
	local function tile(name, col, row, colors, icon)
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
			Size = UDim2.fromOffset(38, 38),
			Position = UDim2.new(0, 6, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = body,
		})
		corner(medal, UDim.new(1, 0))
		local iconLabel =
			label({ Parent = medal, Size = UDim2.fromScale(1, 1), TextSize = 22, Text = icon, Stroke = 0 })
		local title = label({
			Parent = body,
			Size = UDim2.new(1, -52, 0, 18),
			Position = UDim2.fromOffset(48, 5),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = name:upper(),
		})
		local value = label({
			Parent = body,
			Size = UDim2.new(1, -52, 0, 26),
			Position = UDim2.fromOffset(48, 21),
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
		})
		return { holder = holder, grad = grad, icon = iconLabel, title = title, value = value }
	end
	self.tileQueue = tile("Queue", 0, 0, ORANGE, "⏳")
	self.tileHands = tile("Hands", 1, 0, TEAL, "✋")
	self.tileWeather = tile("Weather", 0, 1, BLUE, "🌙")
	self.tileBest = tile("Best", 1, 1, PURPLE, "🏆")
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

	local function tile(name, order, colors, icon, caption, isButton)
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
		local iconLabel = label({
			Parent = box,
			Size = UDim2.new(1, 0, 1, -10),
			TextSize = 44,
			Text = icon,
			Stroke = 0,
		})
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
		return { holder = holder, boxHolder = boxHolder, box = box, grad = grad, icon = iconLabel, caption = cap }
	end

	self.handTiles = {}
	for i = 1, 2 do
		self.handTiles[i] = tile("Hand" .. i, i, GREY, "", "EMPTY", false)
	end
	self.readyTile = tile("Ready", 10, GREEN, "✅", "READY", true)
	pressable(self.readyTile.boxHolder, self.readyTile.box, function()
		self.callbacks.onReady()
	end)
end

-- Centre banner for phase announcements ------------------------------------
function Hud:buildBanner()
	local holder, body = chunk({
		Name = "Banner",
		Parent = self.root,
		Size = UDim2.fromOffset(420, 66),
		Position = UDim2.new(0.5, 0, 0, 250),
		AnchorPoint = Vector2.new(0.5, 0),
		Colors = GOLD,
		Radius = UDim.new(0, 14),
		Visible = false,
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
	self.bannerTitle = label({
		Parent = inner,
		Size = UDim2.fromScale(1, 1),
		TextSize = 34,
		TextColor3 = Color3.fromRGB(74, 52, 30),
		Stroke = 0,
		Text = "",
	})
	self.bannerSub = label({
		Parent = holder,
		Size = UDim2.new(1, 40, 0, 24),
		Position = UDim2.new(0.5, 0, 1, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		TextSize = 18,
		Text = "",
	})
	self.bannerFrame = holder
	self.bannerToken = 0
end

function Hud:buildAlert()
	local holder, body = chunk({
		Name = "Alert",
		Parent = self.root,
		Size = UDim2.fromOffset(460, 44),
		Position = UDim2.new(0.5, 0, 0, 112),
		AnchorPoint = Vector2.new(0.5, 0),
		Colors = RED,
		Radius = UDim.new(1, 0),
		Visible = false,
	})
	self.alertText = label({ Parent = body, Size = UDim2.fromScale(1, 1), TextSize = 22, Text = "" })
	self.alert = holder
end

function Hud:buildToasts()
	local toasts = make("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -140),
		Size = UDim2.fromOffset(600, 200),
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

-- Modal panel shared by the picker and the report ---------------------------
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

local function chunkyButton(parent, name: string, size: UDim2, pos: UDim2, colors, text: string, onClick)
	local holder, body, grad = chunk({
		Name = name,
		Parent = parent,
		Size = size,
		Position = pos,
		Colors = colors,
		Radius = UDim.new(0, 14),
		Button = true,
	})
	local l = label({ Parent = body, Size = UDim2.fromScale(1, 1), TextSize = 24, Text = text })
	pressable(holder, body, onClick)
	return { holder = holder, body = body, grad = grad, label = l }
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
	self.tutorialTitle = label({ Parent = ribbonBody, Size = UDim2.fromScale(1, 1), TextSize = 18, Text = "TUTORIAL" })
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
		end
	)
	self.tutorialNext.label.TextSize = 20
	local skip = chunkyButton(body, "Skip", UDim2.fromOffset(90, 38), UDim2.new(0, 14, 1, -48), GREY, "SKIP", function()
		if self.onTutorialSkip then
			self.onTutorialSkip()
		end
	end)
	skip.label.TextSize = 18
	self.tutorialCard = holder
end

-- info = { title, text, showNext } or nil to hide.
function Hud:setTutorial(info)
	if not info then
		self.tutorialCard.Visible = false
		return
	end
	self.tutorialCard.Visible = true
	self.tutorialTitle.Text = info.title
	self.tutorialText.Text = info.text
	self.tutorialNext.holder.Visible = info.showNext == true
end

function Hud:buildPicker()
	local h = 110 + 66 * self.roomCount + 64
	local holder, body, title = modal(self.root, "CheckInPicker", Vector2.new(440, h), "ASSIGN A ROOM")
	self.picker = holder
	self.pickerTitle = title
	self.pickerSub = label({
		Parent = body,
		Size = UDim2.new(1, -30, 0, 26),
		Position = UDim2.fromOffset(15, 36),
		TextSize = 19,
		TextColor3 = TEXT_DARK,
		Stroke = 0,
		Text = "",
	})
	self.pickerPatience = label({
		Parent = body,
		Size = UDim2.new(1, -30, 0, 24),
		Position = UDim2.fromOffset(15, 62),
		TextSize = 18,
		TextColor3 = Color3.fromRGB(200, 90, 40),
		Stroke = 0,
		Text = "",
	})
	self.pickerButtons = {}
	for i = 1, self.roomCount do
		local b = chunkyButton(
			body,
			"Room" .. i,
			UDim2.new(1, -40, 0, 54),
			UDim2.fromOffset(20, 96 + 66 * (i - 1)),
			GREEN,
			"Room " .. i,
			function()
				local s = self.state
				if s and s.rooms[i] and s.rooms[i].ready then
					self.callbacks.onCheckIn(i)
					self:closePicker()
				end
			end
		)
		self.pickerButtons[i] = b
	end
	chunkyButton(
		body,
		"Cancel",
		UDim2.new(1, -40, 0, 46),
		UDim2.fromOffset(20, 96 + 66 * self.roomCount + 4),
		RED,
		"CANCEL",
		function()
			self:closePicker()
		end
	)
end

function Hud:buildReport()
	local holder, body, title = modal(self.root, "Report", Vector2.new(480, 460), "NIGHT REPORT")
	self.report = holder
	self.reportTitle = title
	self.reportRows = {}
	local names = { "Rent", "Tips", "Purchases", "Bill", "Cash", "Guests", "Lost" }
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
		label({
			Parent = row,
			Size = UDim2.fromScale(0.45, 1),
			Position = UDim2.fromOffset(10, 0),
			TextSize = 19,
			TextColor3 = TEXT_DARK,
			Stroke = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = n,
		})
		self.reportRows[n] = label({
			Parent = row,
			Size = UDim2.new(0.55, -14, 1, 0),
			Position = UDim2.fromScale(0.45, 0),
			TextSize = 19,
			TextColor3 = TEXT_DARK,
			Stroke = 0,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = "",
		})
	end
	local _resultHolder, resultBody, resultGrad = chunk({
		Name = "Result",
		Parent = body,
		Size = UDim2.new(1, -40, 0, 46),
		Position = UDim2.fromOffset(20, 40 + 34 * #names + 10),
		Colors = GREEN,
		Radius = UDim.new(0, 14),
	})
	self.resultGrad = resultGrad
	self.resultText = label({ Parent = resultBody, Size = UDim2.fromScale(1, 1), TextSize = 21, Text = "" })
	self.restartButton = chunkyButton(
		body,
		"Restart",
		UDim2.fromOffset(240, 54),
		UDim2.new(0.5, -120, 1, -70),
		BLUE,
		"PLAY AGAIN",
		function()
			self.callbacks.onRestart()
		end
	)
end

------------------------------------------------------------------------
-- Feedback
------------------------------------------------------------------------

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
	local text = label({
		Parent = body,
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextSize = 19,
		TextColor3 = textColor,
		Stroke = strokeWidth,
		Text = message,
	})

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
function Hud:banner(title: string, subtitle: string?)
	self.bannerToken += 1
	local token = self.bannerToken
	self.bannerTitle.Text = title
	self.bannerSub.Text = subtitle or ""
	self.bannerFrame.Visible = true
	local scale = self.bannerFrame:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = self.bannerFrame })
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	task.delay(2.6, function()
		if self.bannerToken == token then
			self.bannerFrame.Visible = false
		end
	end)
end

------------------------------------------------------------------------
-- Check-in picker
------------------------------------------------------------------------

function Hud:openPicker()
	self.picker.Visible = true
	self:renderPicker()
end

function Hud:closePicker()
	self.picker.Visible = false
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
				b.label.Text = ("ROOM %d  ·  +$%d"):format(i, self.rent)
				setColors(b.grad, GREEN)
				b.body.Active = true
			else
				b.label.Text = ("Room %d  (%s)"):format(i, table.concat(blockers(r), ", "))
				setColors(b.grad, GREY)
				b.body.Active = false
			end
		end
	end
	self.pickerSub.Text = if anyReady
		then "Pick a ready room for the next guest."
		else "No room is ready. Clean one first!"
end

------------------------------------------------------------------------
-- State rendering
------------------------------------------------------------------------

function Hud:setState(s)
	self.state = s
	local P = s.phase
	local active = P == "Preparation" or P == "Night" or P == "Closing"

	-- Top bar
	self.nightNumber.Text = tostring(s.night)
	self.nightText.Text = ("NIGHT %d/%d"):format(s.night, s.totalNights)
	self.cashText.Text = ("$%d"):format(s.cash)
	setColors(self.cashGrad, if s.cash >= s.bill then GOLD else ORANGE)
	self.billText.Text = ("BILL $%d"):format(s.bill)
	self.stockText.Text = ("🛏 %d    🧺 %d"):format(s.stock.Sheet, s.stock.Towel)
	self.trolleyText.Text = if s.trolley then "🛒 TROLLEY  ✓" else "🛒 NO TROLLEY"
	local ns = s.nightStats
	self.guestText.Text = ("%d/%d"):format(ns.arrivals, s.plannedGuests)

	local status, statusColor
	if not s.power and active then
		status, statusColor = "POWER OUT", Color3.fromRGB(214, 52, 52)
	elseif P == "Night" then
		status, statusColor = "OPEN", Color3.fromRGB(56, 160, 50)
	elseif P == "Closing" then
		status, statusColor = "CLOSING", Color3.fromRGB(226, 122, 30)
	elseif P == "Preparation" then
		status, statusColor = "PREP", Color3.fromRGB(52, 128, 230)
	else
		status, statusColor = "CLOSED", Color3.fromRGB(120, 110, 100)
	end
	self.statusText.Text = status
	self.statusText.TextColor3 = statusColor

	-- Rooms card
	local readyCount = 0
	for i, row in ipairs(self.roomRows) do
		local r = s.rooms[i]
		if r then
			local chipText, chipColors, circleColors, mark
			if r.ready then
				readyCount += 1
				row.text.Text = ("Room %d"):format(i)
				chipText, chipColors, circleColors, mark = "READY", GREEN, GREEN, "✓"
			elseif r.occupied then
				row.text.Text = ("Room %d  · guest"):format(i)
				if r.towelRequest then
					chipText, chipColors, circleColors, mark = "TOWEL!", ORANGE, ORANGE, "!"
				else
					chipText, chipColors, circleColors, mark = "BUSY", BLUE, BLUE, "z"
				end
			else
				row.text.Text = ("Room %d  · %s"):format(i, table.concat(blockers(r), ", "))
				if r.acBroken then
					chipText, chipColors, circleColors, mark = "FIX AC", RED, RED, "!"
				else
					chipText, chipColors, circleColors, mark = "CLEAN", ORANGE, ORANGE, "!"
				end
			end
			row.chipText.Text = chipText
			setColors(row.chipGrad, chipColors)
			setColors(row.circleGrad, circleColors)
			row.mark.Text = mark
		end
	end
	self.roomsTitle.Text = ("ROOMS %d/%d"):format(readyCount, #self.roomRows)

	-- Status tiles
	self.tileQueue.value.Text = ("%d waiting"):format(s.queueLength)
	setColors(self.tileQueue.grad, if s.queueLength >= 3 then RED else ORANGE)
	self.tileHands.value.Text = ("%d/%d"):format(#s.carry, s.carryCapacity)
	if not s.power then
		self.tileWeather.icon.Text = "⚡"
		self.tileWeather.value.Text = "Power out"
		setColors(self.tileWeather.grad, RED)
	elseif s.rain then
		self.tileWeather.icon.Text = "🌧"
		self.tileWeather.value.Text = "Rain"
		setColors(self.tileWeather.grad, BLUE)
	elseif s.rainForecast and P == "Preparation" then
		self.tileWeather.icon.Text = "⛈"
		self.tileWeather.value.Text = "Storm soon"
		setColors(self.tileWeather.grad, PURPLE)
	else
		self.tileWeather.icon.Text = if P == "Preparation" then "☀" else "🌙"
		self.tileWeather.value.Text = "Clear"
		setColors(self.tileWeather.grad, TEAL)
	end
	self.tileBest.value.Text = ("%d night%s"):format(s.bestNights, if s.bestNights == 1 then "" else "s")

	-- Bottom bar: carried items
	for i, t in ipairs(self.handTiles) do
		t.holder.Visible = i <= s.carryCapacity
		local item = s.carry[i]
		if item then
			t.icon.Text = ITEM_ICON[item] or "?"
			t.caption.Text = item:upper()
			setColors(t.grad, if item == "Trash" then ORANGE else TEAL)
		else
			t.icon.Text = ""
			t.caption.Text = "EMPTY"
			setColors(t.grad, GREY)
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

	-- Alert ribbon
	if not s.power and active then
		self.alertText.Text = "⚡ POWER OUT! Reset the breaker in the lobby"
		self.alert.Visible = true
	elseif P == "Preparation" then
		local coop = if s.planPlayers > 1 then (" · %d players"):format(s.planPlayers) else ""
		self.alertText.Text = ("~%d guests%s · %s"):format(s.plannedGuests, coop, s.forecast)
		self.alert.Visible = true
	else
		self.alert.Visible = false
	end
	if self.alert.Visible then
		local body = self.alert:FindFirstChild("Body")
		local grad = body and body:FindFirstChildOfClass("UIGradient")
		if grad then
			setColors(grad, if P == "Preparation" and s.power then PURPLE else RED)
		end
	end

	-- Report / run ended
	if (P == "Report" or P == "RunEnded") and s.report then
		local r = s.report
		self.report.Visible = true
		self.reportRows.Rent.Text = ("+$%d"):format(r.rent)
		self.reportRows.Tips.Text = ("+$%d"):format(r.tips)
		self.reportRows.Purchases.Text = ("-$%d"):format(r.purchases)
		self.reportRows.Bill.Text = ("-$%d"):format(r.bill)
		self.reportRows.Cash.Text = ("$%d  →  $%d"):format(r.cashBefore, r.cashAfter)
		self.reportRows.Guests.Text = ("%d served / %d planned"):format(r.served, r.guestsPlanned)
		self.reportRows.Lost.Text = ("%d walkout · %d unserved · %d towel"):format(
			r.walkouts,
			r.unserved,
			r.missedTowels
		)
		if r.passed then
			self.resultText.Text = ("BILL PAID! Nights survived: %d"):format(r.nightsSurvived)
			setColors(self.resultGrad, GREEN)
		else
			self.resultText.Text = ("SHORT BY $%d. THE MOTEL CLOSES"):format(r.shortfall)
			setColors(self.resultGrad, RED)
		end
		if P == "RunEnded" then
			self.reportTitle.Text = if s.complete then "PROTOTYPE COMPLETE!" else "RUN OVER"
			self.restartButton.holder.Visible = true
		else
			self.reportTitle.Text = ("NIGHT %d REPORT"):format(r.night)
			self.restartButton.holder.Visible = false
		end
	else
		self.report.Visible = false
	end

	self:renderPicker()
end

-- Called every frame for timers and the phase bar.
function Hud:tick()
	local s = self.state
	if not s then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local labelText = s.phase
	if s.phase == "Preparation" then
		labelText = "PREP"
	elseif s.phase == "RunEnded" then
		labelText = if s.complete then "COMPLETE" else "RUN OVER"
	end
	if s.phaseEndsAt and s.phaseStartedAt then
		local total = math.max(0.001, s.phaseEndsAt - s.phaseStartedAt)
		local left = s.phaseEndsAt - now
		local frac = math.clamp(left / total, 0, 1)
		self.phaseFill.Size = UDim2.new(frac, -8 * frac, 1, -8)
		self.phaseFill.Visible = frac > 0.01
		self.phaseText.Text = ("%s  %s"):format(labelText:upper(), fmtTime(left))
		setColors(self.phaseFillGrad, if s.phase == "Night" and left < 30 then ORANGE else BLUE)
	else
		self.phaseFill.Visible = false
		self.phaseText.Text = labelText:upper()
	end

	if s.frontPatienceEndsAt and s.queueLength > 0 then
		local left = math.max(0, math.ceil(s.frontPatienceEndsAt - now))
		self.tileQueue.title.Text = ("QUEUE · %ds"):format(left)
		if self.picker.Visible then
			self.pickerPatience.Text = ("Next guest leaves in %ds"):format(left)
		end
	else
		self.tileQueue.title.Text = "QUEUE"
		self.pickerPatience.Text = ""
	end
end

return Hud
