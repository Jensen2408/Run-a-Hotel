--!nonstrict
--[[
	UiKit: the chunky cartoon UI building blocks (same look as the game HUD)
	for screens outside Hud.luau: the lobby HUD and the settings panel.

	Palette, outlined Fredoka labels, chunky panels with shadow + gradient +
	shine, icon buttons with hover/press/click sound, modals over a dimmed
	backdrop, and small animations (pop, wiggle).

	Note: Hud.luau still has its own copies of these helpers; new screens
	should use UiKit.
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Icons = require(script.Parent:WaitForChild("Icons"))

local UiKit = {}

UiKit.FONT = Enum.Font.FredokaOne
UiKit.OUTLINE = Color3.fromRGB(46, 32, 22)
UiKit.WHITE = Color3.new(1, 1, 1)
UiKit.CREAM = Color3.fromRGB(255, 247, 222)
UiKit.TEXT_DARK = Color3.fromRGB(70, 52, 38)
UiKit.GOLD = { Color3.fromRGB(255, 226, 110), Color3.fromRGB(240, 172, 34) }
UiKit.GREEN = { Color3.fromRGB(150, 232, 92), Color3.fromRGB(62, 170, 46) }
UiKit.BLUE = { Color3.fromRGB(130, 200, 255), Color3.fromRGB(52, 128, 230) }
UiKit.RED = { Color3.fromRGB(255, 128, 110), Color3.fromRGB(214, 52, 52) }
UiKit.ORANGE = { Color3.fromRGB(255, 196, 110), Color3.fromRGB(236, 122, 40) }
UiKit.PURPLE = { Color3.fromRGB(206, 170, 255), Color3.fromRGB(132, 88, 222) }
UiKit.GREY = { Color3.fromRGB(196, 196, 204), Color3.fromRGB(128, 128, 140) }
UiKit.TEAL = { Color3.fromRGB(140, 236, 220), Color3.fromRGB(40, 170, 160) }
UiKit.CARD = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(240, 234, 220) }
UiKit.PAPER = { Color3.fromRGB(255, 247, 222), Color3.fromRGB(244, 230, 196) }

local sfx = nil
function UiKit.setSfx(player)
	sfx = player
end
function UiKit.play(name: string)
	if sfx then
		sfx:play(name)
	end
end

function UiKit.make(className: string, props)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end
local make = UiKit.make

function UiKit.corner(parent, radius: UDim?)
	make("UICorner", { CornerRadius = radius or UDim.new(0, 14), Parent = parent })
end

function UiKit.outline(parent, thickness: number?, color: Color3?)
	return make("UIStroke", {
		Thickness = thickness or 3,
		Color = color or UiKit.OUTLINE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

function UiKit.gradient(parent, colors)
	return make("UIGradient", { Rotation = 90, Color = ColorSequence.new(colors[1], colors[2]), Parent = parent })
end

function UiKit.setColors(grad: UIGradient, colors)
	grad.Color = ColorSequence.new(colors[1], colors[2])
end

-- Outlined cartoon text. Extra props: Stroke (thickness, 0 = none), StrokeColor.
function UiKit.label(props)
	local size = props.TextSize or 22
	local strokeColor = props.StrokeColor or UiKit.OUTLINE
	local strokeThickness = props.Stroke
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = UiKit.FONT
	t.TextColor3 = UiKit.WHITE
	t.TextWrapped = true
	t.Text = ""
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "Stroke" and k ~= "StrokeColor" then
			t[k] = v
		end
	end
	t.TextSize = size
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

-- Chunky panel: holder (transparent) with a drop shadow and a gradient body.
function UiKit.chunk(props)
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
		BackgroundColor3 = UiKit.OUTLINE,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, props.ShadowDepth or 5),
		Parent = holder,
	})
	UiKit.corner(shadow, radius)
	local body = make(props.Button and "TextButton" or "Frame", {
		Name = "Body",
		BackgroundColor3 = UiKit.WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	if props.Button then
		body.Text = ""
		body.AutoButtonColor = false
	end
	UiKit.corner(body, radius)
	UiKit.outline(body, props.Stroke or 3)
	local grad = UiKit.gradient(body, props.Colors or UiKit.CARD)
	if props.Shine ~= false then
		local shine = make("Frame", {
			Name = "Shine",
			BackgroundColor3 = UiKit.WHITE,
			BackgroundTransparency = 0.78,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -10, 0.42, 0),
			Position = UDim2.fromOffset(5, 3),
			Parent = body,
		})
		UiKit.corner(shine, radius)
	end
	return holder, body, grad
end

function UiKit.tween(obj, time, props, style, dir)
	local t = TweenService:Create(
		obj,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

-- One UIScale per object, driven by multiplied components (pop, hover, pulse).
local scaleState = setmetatable({}, { __mode = "k" })
function UiKit.scaleOf(gui: GuiObject, name: string?): NumberValue
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

function UiKit.pop(gui: GuiObject, amount: number?)
	Icons.bumpIn(gui) -- something changed here: animate its icons too
	local s = UiKit.scaleOf(gui)
	s.Value = 1
	local up = UiKit.tween(s, 0.08, { Value = 1 + (amount or 0.12) })
	up.Completed:Once(function()
		UiKit.tween(s, 0.4, { Value = 1 }, Enum.EasingStyle.Back)
	end)
end

function UiKit.wiggle(gui: GuiObject, degrees: number, duration: number)
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

function UiKit.pressable(holder: GuiObject, body: GuiButton, onActivate)
	body.Activated:Connect(function()
		UiKit.play("click")
		Icons.bumpIn(holder)
		onActivate()
	end)
	local s = UiKit.scaleOf(holder, "Hover")
	body.MouseEnter:Connect(function()
		UiKit.tween(s, 0.12, { Value = 1.06 })
	end)
	body.MouseLeave:Connect(function()
		UiKit.tween(s, 0.15, { Value = 1 })
		body.Position = UDim2.fromOffset(0, 0)
	end)
	body.MouseButton1Down:Connect(function()
		body.Position = UDim2.fromOffset(0, 3)
		UiKit.tween(s, 0.06, { Value = 0.95 })
	end)
	body.MouseButton1Up:Connect(function()
		body.Position = UDim2.fromOffset(0, 0)
		UiKit.tween(s, 0.2, { Value = 1.06 }, Enum.EasingStyle.Back)
	end)
end

-- Chunky button with an optional icon on the left of the caption.
function UiKit.button(parent, name: string, size: UDim2, pos: UDim2, colors, text: string, onClick, iconName: string?)
	local holder, body, grad = UiKit.chunk({
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
		if text == "" then
			icon.frame.Position = UDim2.fromScale(0.5, 0.5)
			icon.frame.AnchorPoint = Vector2.new(0.5, 0.5)
		end
		l = UiKit.label({
			Parent = body,
			Size = UDim2.new(1, -56, 1, 0),
			Position = UDim2.fromOffset(46, 0),
			TextSize = 22,
			Text = text,
		})
	else
		l = UiKit.label({ Parent = body, Size = UDim2.fromScale(1, 1), TextSize = 22, Text = text })
	end
	UiKit.pressable(holder, body, onClick)
	return { holder = holder, body = body, grad = grad, label = l, icon = icon }
end

--[[
	A scaled screen: ScreenGui + root frame authored at 1280x720 and scaled
	with UIScale, plus a backdrop for modals. Returns a screen table with
	:modal(name, size, title) and :open(panel) / :close(panel).
]]
function UiKit.screen(playerGui: PlayerGui, name: string, displayOrder: number?, fullScreen: boolean?)
	local gui = make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
		-- fullScreen: draw under Roblox's topbar too (for items placed in its row).
		ScreenInsets = if fullScreen then Enum.ScreenInsets.None else Enum.ScreenInsets.CoreUISafeInsets,
		Parent = playerGui,
	})
	local root =
		make("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
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
	local backdrop = make("Frame", {
		Name = "Backdrop",
		BackgroundColor3 = Color3.fromRGB(20, 14, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
		Visible = false,
		Parent = root,
	})
	local screen = { gui = gui, root = root, uiScale = uiScale, backdrop = backdrop, panels = {} }

	function screen:modal(panelName: string, size: Vector2, title: string, titleIcon: string?)
		local holder, body = UiKit.chunk({
			Name = panelName,
			Parent = root,
			Size = UDim2.fromOffset(size.X, size.Y),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Colors = UiKit.PAPER,
			Radius = UDim.new(0, 22),
			Visible = false,
			ShadowDepth = 7,
			Stroke = 4,
			ZIndex = 10,
		})
		local ribbonHolder, ribbonBody = UiKit.chunk({
			Name = "Ribbon",
			Parent = holder,
			Size = UDim2.fromOffset(math.min(size.X - 60, 340), 50),
			Position = UDim2.new(0.5, 0, 0, -24),
			AnchorPoint = Vector2.new(0.5, 0),
			Colors = UiKit.GOLD,
			Radius = UDim.new(0, 14),
		})
		ribbonHolder.ZIndex = 3
		if titleIcon then
			Icons.create(titleIcon, {
				Parent = ribbonBody,
				Size = UDim2.fromOffset(36, 36),
				Position = UDim2.new(0, 10, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				ZIndex = 2,
			})
		end
		UiKit.label({ Parent = ribbonBody, Size = UDim2.fromScale(1, 1), TextSize = 26, Text = title })
		local close = UiKit.button(
			body,
			"Close",
			UDim2.fromOffset(48, 48),
			UDim2.new(1, -30, 0, -30),
			UiKit.RED,
			"",
			function()
				screen:close(holder)
			end,
			"cross"
		)
		close.holder.ZIndex = 4
		table.insert(screen.panels, holder)
		return holder, body
	end

	function screen:open(panel: GuiObject)
		if panel.Visible then
			return
		end
		panel.Visible = true
		local s = UiKit.scaleOf(panel)
		s.Value = 0.55
		UiKit.tween(s, 0.38, { Value = 1 }, Enum.EasingStyle.Back)
		backdrop.Visible = true
		UiKit.tween(backdrop, 0.25, { BackgroundTransparency = 0.45 })
		UiKit.play("whoosh")
	end

	function screen:close(panel: GuiObject)
		if not panel.Visible then
			return
		end
		local s = UiKit.scaleOf(panel)
		UiKit.tween(s, 0.14, { Value = 0.7 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
			panel.Visible = false
			s.Value = 1
			local anyOpen = false
			for _, p in ipairs(screen.panels) do
				anyOpen = anyOpen or p.Visible
			end
			if not anyOpen then
				UiKit.tween(backdrop, 0.2, { BackgroundTransparency = 1 }).Completed:Once(function()
					backdrop.Visible = false
				end)
			end
		end)
		UiKit.play("whooshOut")
	end

	return screen
end

return UiKit
