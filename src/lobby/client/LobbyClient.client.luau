--!nonstrict
--[[
	Lobby client: room panel while standing on a pad (slots with headshots,
	countdown bar, LEAVE), a hint pill otherwise, the personal profile board
	(drawn locally on Workspace.Lobby.Boards.ProfileBoard), toasts, music and
	the settings gear.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local UiKit = require(script.Parent:WaitForChild("UiKit"))
local Icons = require(script.Parent:WaitForChild("Icons"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))
local Settings = require(script.Parent:WaitForChild("Settings"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local R = Constants.LobbyRemotes
local remotes = ReplicatedStorage:WaitForChild(R.Folder)

local sfx = Sfx.new()
UiKit.setSfx(sfx)
Settings.new(playerGui, sfx, "lobby")

local ROOM_NAMES = { "SOLO", "DUO", "TRIO", "SQUAD" }
-- Same order as LobbyBuilder.ROOM_COLORS (green, blue, purple, orange).
local ROOM_COLORS = { UiKit.GREEN, UiKit.BLUE, UiKit.PURPLE, UiKit.ORANGE }

local screen = UiKit.screen(playerGui, "LobbyHud", 5)
local root = screen.root

------------------------------------------------------------------------
-- Hint pill (not on a pad)
------------------------------------------------------------------------

local hint, hintBody = UiKit.chunk({
	Name = "Hint",
	Parent = root,
	Size = UDim2.fromOffset(470, 58),
	Position = UDim2.new(0.5, 0, 1, -24),
	AnchorPoint = Vector2.new(0.5, 1),
	Colors = UiKit.PAPER,
	Radius = UDim.new(0, 18),
})
Icons.create("people", {
	Parent = hintBody,
	Size = UDim2.fromOffset(38, 38),
	Position = UDim2.new(0, 12, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	ZIndex = 2,
})
UiKit.label({
	Parent = hintBody,
	Size = UDim2.new(1, -66, 1, 0),
	Position = UDim2.fromOffset(58, 0),
	TextSize = 20,
	TextColor3 = UiKit.TEXT_DARK,
	Stroke = 0,
	Text = "Step on a glowing pad (1-4 players) to join a room",
})

------------------------------------------------------------------------
-- Room panel (on a pad)
------------------------------------------------------------------------

local panel, panelBody = UiKit.chunk({
	Name = "RoomPanel",
	Parent = root,
	Size = UDim2.fromOffset(460, 236),
	Position = UDim2.new(0.5, 0, 1, -20),
	AnchorPoint = Vector2.new(0.5, 1),
	Colors = UiKit.PAPER,
	Radius = UDim.new(0, 22),
	Visible = false,
	Stroke = 4,
})
local ribbon, ribbonBody, ribbonGrad = UiKit.chunk({
	Name = "Ribbon",
	Parent = panel,
	Size = UDim2.fromOffset(280, 48),
	Position = UDim2.new(0.5, 0, 0, -22),
	AnchorPoint = Vector2.new(0.5, 0),
	Colors = UiKit.BLUE,
})
ribbon.ZIndex = 3
Icons.create("door", {
	Parent = ribbonBody,
	Size = UDim2.fromOffset(34, 34),
	Position = UDim2.new(0, 10, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	ZIndex = 2,
})
local roomTitle = UiKit.label({ Parent = ribbonBody, Size = UDim2.fromScale(1, 1), TextSize = 24, Text = "ROOM 1" })

local slotsFrame = UiKit.make("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -40, 0, 92),
	Position = UDim2.fromOffset(20, 36),
	Parent = panelBody,
})
UiKit.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = slotsFrame,
})
local slots = {}
for i = 1, 4 do
	local holder, body, grad = UiKit.chunk({
		Name = "Slot" .. i,
		Parent = slotsFrame,
		Size = UDim2.fromOffset(92, 92),
		Colors = UiKit.CARD,
		LayoutOrder = i,
		Shine = false,
	})
	local face = UiKit.make("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(62, 62),
		Position = UDim2.new(0.5, 0, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0),
		Image = "",
		ZIndex = 2,
		Parent = body,
	})
	UiKit.corner(face, UDim.new(1, 0))
	local empty = Icons.create("plus", {
		Parent = body,
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.new(0.5, 0, 0, 16),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 2,
	})
	local name = UiKit.label({
		Parent = body,
		Size = UDim2.new(1, -6, 0, 22),
		Position = UDim2.new(0, 3, 1, -24),
		TextSize = 14,
		TextColor3 = UiKit.TEXT_DARK,
		Stroke = 0,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		ZIndex = 2,
	})
	slots[i] = { holder = holder, grad = grad, face = face, empty = empty, name = name, userId = nil }
end

local barBack = UiKit.make("Frame", {
	BackgroundColor3 = Color3.fromRGB(80, 60, 44),
	BackgroundTransparency = 0.6,
	BorderSizePixel = 0,
	Size = UDim2.new(1, -210, 0, 26),
	Position = UDim2.fromOffset(20, 146),
	Parent = panelBody,
})
UiKit.corner(barBack, UDim.new(1, 0))
UiKit.outline(barBack, 2)
local barFill = UiKit.make("Frame", {
	BackgroundColor3 = UiKit.WHITE,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Parent = barBack,
})
UiKit.corner(barFill, UDim.new(1, 0))
UiKit.gradient(barFill, UiKit.GOLD)
local barText = UiKit.label({
	Parent = barBack,
	Size = UDim2.fromScale(1, 1),
	TextSize = 18,
	Text = "",
	ZIndex = 2,
})
Icons.create("alarm", {
	Parent = panelBody,
	Size = UDim2.fromOffset(34, 34),
	Position = UDim2.new(1, -186, 0, 142),
	ZIndex = 2,
})
local statusText = UiKit.label({
	Parent = panelBody,
	Size = UDim2.new(1, -40, 0, 28),
	Position = UDim2.fromOffset(20, 184),
	TextSize = 17,
	TextColor3 = UiKit.TEXT_DARK,
	Stroke = 0,
	Text = "",
})
UiKit.button(panelBody, "Leave", UDim2.fromOffset(136, 44), UDim2.new(1, -150, 0, 138), UiKit.RED, "LEAVE", function()
	remotes:WaitForChild(R.Leave):FireServer()
end, "cross")

------------------------------------------------------------------------
-- Toasts
------------------------------------------------------------------------

local toastList = UiKit.make("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(560, 300),
	Position = UDim2.new(0.5, 0, 0, 20),
	AnchorPoint = Vector2.new(0.5, 0),
	Parent = root,
})
UiKit.make("UIListLayout", {
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = toastList,
})
local toastOrder = 0
local TOAST = {
	info = { colors = UiKit.BLUE, icon = "bell", sound = "notify" },
	ok = { colors = UiKit.GREEN, icon = "check", sound = "success" },
	error = { colors = UiKit.RED, icon = "warning", sound = "error" },
}
local function toast(text: string, kind: string?)
	local style = TOAST[kind or "info"] or TOAST.info
	toastOrder += 1
	local holder, body = UiKit.chunk({
		Name = "Toast",
		Parent = toastList,
		Size = UDim2.fromOffset(540, 52),
		Colors = style.colors,
		LayoutOrder = toastOrder,
	})
	Icons.create(style.icon, {
		Parent = body,
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 2,
	})
	UiKit.label({
		Parent = body,
		Size = UDim2.new(1, -62, 1, 0),
		Position = UDim2.fromOffset(52, 0),
		TextSize = 18,
		Text = text,
	})
	UiKit.pop(holder, 0.15)
	sfx:play(style.sound)
	task.delay(4.5, function()
		UiKit.tween(UiKit.scaleOf(holder), 0.2, { Value = 0 })
		task.wait(0.22)
		holder:Destroy()
	end)
end

------------------------------------------------------------------------
-- Rooms state
------------------------------------------------------------------------

local state = nil
local myRoom = nil

local function headshot(userId: number)
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId)
end

local function render()
	if not state then
		return
	end
	local found = nil
	for i, room in ipairs(state.rooms) do
		for _, p in ipairs(room.players) do
			if p.userId == player.UserId then
				found = i
			end
		end
	end
	if found ~= myRoom then
		if found then
			sfx:play("whoosh")
			panel.Visible = true
			UiKit.pop(panel, 0.1)
		elseif myRoom then
			sfx:play("whooshOut")
		end
		myRoom = found
	end
	panel.Visible = found ~= nil
	hint.Visible = found == nil
	if not found then
		return
	end
	local room = state.rooms[found]
	roomTitle.Text = ("ROOM %d · %s"):format(found, ROOM_NAMES[found] or "")
	UiKit.setColors(ribbonGrad, ROOM_COLORS[found] or UiKit.BLUE)
	for i, slot in ipairs(slots) do
		slot.holder.Visible = i <= room.size
		local p = room.players[i]
		local uid = p and p.userId or nil
		if uid ~= slot.userId then
			slot.userId = uid
			slot.face.Image = if uid then headshot(uid) else ""
			slot.empty.frame.Visible = uid == nil
			UiKit.setColors(slot.grad, if uid then (ROOM_COLORS[found] or UiKit.CARD) else UiKit.CARD)
			if uid then
				UiKit.pop(slot.holder, 0.18)
				sfx:play("pop")
			end
		end
		slot.name.Text = if p then p.name else "waiting..."
	end
	if room.launching then
		statusText.Text = "Starting! Get ready..."
	elseif #room.players >= room.size then
		statusText.Text = "Room full - starting!"
	else
		local missing = room.size - #room.players
		statusText.Text = ("Waiting for %d more - starts anyway when time runs out"):format(missing)
	end
end

remotes:WaitForChild(R.Rooms).OnClientEvent:Connect(function(payload)
	state = payload
	render()
end)

remotes:WaitForChild(R.Notice).OnClientEvent:Connect(function(payload)
	toast(payload.text, payload.kind)
end)

-- Countdown bar, smooth every frame.
local lastTick = nil
RunService.RenderStepped:Connect(function()
	if not (state and myRoom) then
		return
	end
	local room = state.rooms[myRoom]
	if not room then
		return
	end
	local total = Config.lobby.padCountdown
	local left = if room.endsAt then math.max(0, room.endsAt - Workspace:GetServerTimeNow()) else total
	barFill.Size = UDim2.fromScale(math.clamp(left / total, 0, 1), 1)
	barText.Text = if room.launching then "GO!" else ("%ds"):format(math.ceil(left))
	local whole = math.ceil(left)
	if whole ~= lastTick then
		lastTick = whole
		if whole <= 5 and whole > 0 and not room.launching then
			sfx:play("alert")
			UiKit.pop(barBack, 0.08)
		end
	end
end)

------------------------------------------------------------------------
-- Profile board (local SurfaceGui on the wall board)
------------------------------------------------------------------------

local profileRows = {}
local function buildProfileGui(board: BasePart)
	local gui = UiKit.make("SurfaceGui", {
		Name = "ProfileGui",
		Face = Enum.NormalId.Left,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0,
		Brightness = 1.4,
		Adornee = board,
		Parent = playerGui,
	})
	local frame = UiKit.make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	UiKit.make("UIPadding", {
		PaddingTop = UDim.new(0.05, 0),
		PaddingLeft = UDim.new(0.06, 0),
		PaddingRight = UDim.new(0.06, 0),
		Parent = frame,
	})
	local face = UiKit.make("ImageLabel", {
		BackgroundColor3 = UiKit.CREAM,
		Size = UDim2.fromScale(0.22, 0.22),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Image = headshot(player.UserId),
		Parent = frame,
	})
	UiKit.corner(face, UDim.new(1, 0))
	UiKit.outline(face, 6)
	UiKit.label({
		Parent = frame,
		Size = UDim2.fromScale(1, 0.1),
		Position = UDim2.fromScale(0.3, 0.02),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "MY PROFILE",
		TextColor3 = Color3.fromRGB(255, 226, 110),
		Stroke = 5,
	})
	UiKit.label({
		Parent = frame,
		Size = UDim2.fromScale(0.7, 0.08),
		Position = UDim2.fromScale(0.3, 0.13),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = player.DisplayName,
		Stroke = 4,
	})
	local items = {
		{ key = "best", icon = "trophy", title = "BEST NIGHTS" },
		{ key = "runs", icon = "calendar", title = "RUNS PLAYED" },
		{ key = "nights", icon = "moon", title = "NIGHTS SURVIVED" },
		{ key = "served", icon = "key", title = "GUESTS SERVED" },
	}
	for k, item in ipairs(items) do
		local y = 0.3 + (k - 1) * 0.165
		local strip = UiKit.make("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 0.14),
			Position = UDim2.fromScale(0, y),
			Parent = frame,
		})
		UiKit.corner(strip, UDim.new(0.25, 0))
		local ic = Icons.create(item.icon, {
			Parent = strip,
			Size = UDim2.fromScale(0.8, 0.8),
			Position = UDim2.fromScale(0.02, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
		})
		ic.frame.SizeConstraint = Enum.SizeConstraint.RelativeYY
		UiKit.label({
			Parent = strip,
			Size = UDim2.fromScale(0.6, 0.6),
			Position = UDim2.fromScale(0.16, 0.2),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = item.title,
			Stroke = 3,
		})
		profileRows[item.key] = UiKit.label({
			Parent = strip,
			Size = UDim2.fromScale(0.22, 0.75),
			Position = UDim2.fromScale(0.76, 0.12),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = "-",
			TextColor3 = Color3.fromRGB(255, 226, 110),
			Stroke = 4,
		})
	end
	profileRows.status = UiKit.label({
		Parent = frame,
		Size = UDim2.fromScale(1, 0.06),
		Position = UDim2.fromScale(0, 0.97),
		AnchorPoint = Vector2.new(0, 1),
		TextScaled = true,
		Text = "Loading...",
		Stroke = 3,
	})
end

local pendingProfile = nil
local function fillProfile()
	if not (pendingProfile and profileRows.best) then
		return
	end
	for _, key in ipairs({ "best", "runs", "nights", "served" }) do
		profileRows[key].Text = tostring(pendingProfile[key] or 0)
	end
	profileRows.status.Text = if pendingProfile.online then "" else "Stats offline (Studio: enable API access)"
end

remotes:WaitForChild(R.Profile).OnClientEvent:Connect(function(profile)
	pendingProfile = profile
	fillProfile()
end)

task.spawn(function()
	local lobby = Workspace:WaitForChild("Lobby")
	local board = lobby:WaitForChild("Boards"):WaitForChild("ProfileBoard")
	buildProfileGui(board)
	fillProfile()
end)
