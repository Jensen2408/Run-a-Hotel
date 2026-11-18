--!nonstrict
--[[
	Server entry point for Run a Motel.

	The server owns timers, cash, stock, queue, room state and every
	interaction result. Clients only receive snapshots and send requests,
	which are validated here (type, phase, distance, carried items, latest
	state) before MotelCore applies them without yielding.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mode = require(Shared:WaitForChild("Mode"))
if Mode.get() ~= Mode.Game then
	return -- this server is a lobby (see Shared/Mode)
end

local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local MotelCore = require(script.Parent:WaitForChild("MotelCore"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local Visuals = require(script.Parent:WaitForChild("Visuals"))
local LightingFX = require(script.Parent:WaitForChild("LightingFX"))
local Persistence = require(script.Parent:WaitForChild("Persistence"))
local UiAssets = require(Shared:WaitForChild("UiAssets"))
local TeleportService = game:GetService("TeleportService")

local PA = Constants.PromptAction
local RA = Constants.RemoteAction

------------------------------------------------------------------------
-- Remotes
------------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = Constants.Remotes.Folder
local function remote(name: string)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local actionRemote = remote(Constants.Remotes.Action)
local stateRemote = remote(Constants.Remotes.State)
local feedbackRemote = remote(Constants.Remotes.Feedback)
local openCheckInRemote = remote(Constants.Remotes.OpenCheckIn)
local openShopRemote = remote(Constants.Remotes.OpenShop)
local openLinenRemote = remote(Constants.Remotes.OpenLinen)
local openKitchenRemote = remote(Constants.Remotes.OpenKitchen)
local openFixRemote = remote(Constants.Remotes.OpenFix)
remotes.Parent = ReplicatedStorage

------------------------------------------------------------------------
-- Setup
------------------------------------------------------------------------

local timeScale = Config.timeScale
if RunService:IsStudio() then
	local override = Config.studioTimeScale
	if typeof(override) == "number" and override > 0 and override <= 4 and override ~= 1 then
		timeScale = override
		warn(("[Motel] Studio time scale (Config.studioTimeScale): %.2f"):format(timeScale))
	end
end

-- A lobby hall saved in the place file is not needed here.
local savedLobby = Workspace:FindFirstChild("Lobby")
if savedLobby then
	savedLobby:Destroy()
end
local layout = MapBuilder.ensure(Config)
LightingFX.apply()
local rng = Random.new()
local function now()
	return Workspace:GetServerTimeNow()
end

-- Wait for the first player so Preparation does not tick down on an empty server.
if #Players:GetPlayers() == 0 then
	Players.PlayerAdded:Wait()
end

-- A group teleported from a lobby pad carries its size in the teleport data;
-- wait (briefly) for everyone so co-op scaling starts with the right count.
do
	local first = Players:GetPlayers()[1]
	local partySize = 1
	local ok, joinData = pcall(function()
		return first:GetJoinData()
	end)
	local data = ok and joinData and joinData.TeleportData
	if typeof(data) == "table" and typeof(data.partySize) == "number" then
		partySize = math.clamp(math.floor(data.partySize), 1, Config.coop.maxPlayers)
	end
	local deadline = os.clock() + Config.lobby.partyWait
	while #Players:GetPlayers() < partySize and os.clock() < deadline do
		task.wait(0.25)
	end
end

local core = MotelCore.new(Config, Constants, {
	now = now(),
	timeScale = timeScale,
	playerCount = math.max(1, #Players:GetPlayers()),
	random = function(a, b)
		return rng:NextNumber(a, b)
	end,
})
if RunService:IsStudio() then
	-- Studio only: test hook for the command bar / tools (scripts there run in
	-- another Lua context, so a BindableFunction instead of _G).
	-- ("setRoom", roomId, field, value) or (methodName, ...args).
	local debugFn = Instance.new("BindableFunction")
	debugFn.Name = "MotelDebug"
	debugFn.OnInvoke = function(cmd, ...)
		if cmd == "setRoom" then
			local roomId, field, value = ...
			core.rooms[roomId][field] = value
			core:bump()
			return true
		end
		local fn = core[cmd]
		if typeof(fn) == "function" then
			return fn(core, ...)
		end
		return core[cmd]
	end
	debugFn.Parent = game:GetService("ServerStorage")
end
local visuals = Visuals.new(layout, Config, Constants, timeScale)
visuals:refreshWorld(core)

local function feedback(player: Player, text: string, kind: string?)
	feedbackRemote:FireClient(player, { text = text, kind = kind or "info" })
end

-- Sends to everyone, optionally skipping the player who caused the event
-- (they already got a personal message).
local function broadcast(text: string, kind: string?, exceptUserId: number?)
	local payload = { text = text, kind = kind or "info" }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId ~= exceptUserId then
			feedbackRemote:FireClient(player, payload)
		end
	end
end

local function sendState(player: Player)
	stateRemote:FireClient(player, core:snapshot(player.UserId))
end

local function sendStateAll()
	for _, player in ipairs(Players:GetPlayers()) do
		sendState(player)
	end
end

------------------------------------------------------------------------
-- Validation helpers
------------------------------------------------------------------------

local function rootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function withinRange(player: Player, position: Vector3, range: number): boolean
	local hrp = rootPart(player)
	if not hrp then
		return false
	end
	return (hrp.Position - position).Magnitude <= range
end

local function promptPosition(prompt: ProximityPrompt): Vector3
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return Vector3.new(math.huge, math.huge, math.huge)
end

local lastRequest: { [Player]: number } = {}
local function rateLimited(player: Player): boolean
	local t = os.clock()
	local last = lastRequest[player]
	if last and t - last < Config.interaction.remoteCooldown then
		return true
	end
	lastRequest[player] = t
	return false
end

-- Kitchen actions (all need the player at the stove).
local KITCHEN_ACTIONS = {
	[RA.Cook] = true,
	[RA.CollectDish] = true,
	[RA.DiscardDish] = true,
}

local function validSlot(slot): boolean
	return typeof(slot) == "number" and slot == math.floor(slot) and slot >= 1 and slot <= #Config.kitchen.slots
end

-- Front desk terminal actions (all need the player at the desk).
local DESK_ACTIONS = {
	[RA.DeskMode] = true,
	[RA.DeskVerify] = true,
	[RA.DeskRoom] = true,
	[RA.DeskMethod] = true,
	[RA.DeskBack] = true,
	[RA.DeskConfirm] = true,
}

local function atDesk(player: Player): boolean
	return withinRange(player, layout.deskPosition, Config.interaction.deskRange * (Config.mapScale or 1))
end

local function validRoomId(roomId): boolean
	return typeof(roomId) == "number" and roomId == math.floor(roomId) and roomId >= 1 and roomId <= Config.roomCount
end

------------------------------------------------------------------------
-- ProximityPrompt interactions
------------------------------------------------------------------------

-- Repair minigames: where each player's repair was started (the win must be
-- reported from near the same panel).
local fixSpots = {} -- [Player] = { position, range }
local function openFix(player: Player, kind: string, roomId: number?, prompt: ProximityPrompt)
	local ok, err = core:startFix(player.UserId, kind, roomId, now())
	if not ok then
		return false, err
	end
	fixSpots[player] = {
		position = promptPosition(prompt),
		range = prompt.MaxActivationDistance + Config.interaction.rangeSlack + 6,
	}
	openFixRemote:FireClient(player, {
		fix = kind,
		roomId = roomId,
		easy = core:hasRole(player.UserId, if kind == "Sheets" then "Housekeeper" else "Maintenance"),
	})
	return nil, nil -- no toast; the client opens the minigame
end
Players.PlayerRemoving:Connect(function(player)
	fixSpots[player] = nil
	core:cancelFix(player.UserId)
end)

local promptHandlers = {
	[PA.OpenCheckIn] = function(player: Player)
		local ok, err = core:deskOpen(player.UserId, now())
		if ok then
			openCheckInRemote:FireClient(player, { busy = false })
			sendState(player)
			return nil, nil -- no toast; the client opens the terminal
		elseif err == "busy" then
			local owner = core.desk and Players:GetPlayerByUserId(core.desk.owner)
			openCheckInRemote:FireClient(player, { busy = true, by = owner and owner.DisplayName or "Someone" })
			return nil, nil
		end
		return false, err
	end,
	[PA.OpenLinen] = function(player)
		local ok, err = core:requireActive()
		if not ok then
			return false, err
		end
		openLinenRemote:FireClient(player)
		return nil, nil -- no toast; the client opens the linen panel
	end,
	[PA.DumpTrash] = function(player)
		return core:dumpTrash(player.UserId)
	end,
	[PA.ResetBreaker] = function(player, _roomId, prompt)
		return openFix(player, "Breaker", nil, prompt)
	end,
	[PA.OpenShop] = function(player)
		local ok, err = core:requireActive()
		if not ok then
			return false, err
		end
		openShopRemote:FireClient(player)
		return nil, nil -- no toast; the client opens the shop panel
	end,
	[PA.CollectTrash] = function(player, roomId)
		return core:collectTrash(player.UserId, roomId)
	end,
	[PA.ChangeSheets] = function(player, roomId, prompt)
		return openFix(player, "Sheets", roomId, prompt)
	end,
	[PA.Deliver] = function(player, roomId)
		return core:deliver(player.UserId, roomId, now())
	end,
	[PA.OpenKitchen] = function(player)
		local ok, err = core:requireActive()
		if not ok then
			return false, err
		end
		openKitchenRemote:FireClient(player)
		return nil, nil -- no toast; the client opens the kitchen panel
	end,
	[PA.RepairAC] = function(player, roomId, prompt)
		return openFix(player, "AC", roomId, prompt)
	end,
}

local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	local action = prompt:GetAttribute("Action")
	local handler = action and promptHandlers[action]
	if not handler then
		return
	end
	local range = prompt.MaxActivationDistance + Config.interaction.rangeSlack
	if not withinRange(player, promptPosition(prompt), range) then
		feedback(player, "Too far away.", "error")
		return
	end
	local roomId = prompt:GetAttribute("RoomId")
	if roomId ~= nil and not validRoomId(roomId) then
		return
	end
	local ok, msg = handler(player, roomId, prompt)
	if msg then
		feedback(player, msg, if ok then "ok" else "error")
	end
end

for _, inst in ipairs(layout.root:GetDescendants()) do
	if inst:IsA("ProximityPrompt") and inst:GetAttribute("Action") then
		inst.Triggered:Connect(function(player)
			onPromptTriggered(inst, player)
		end)
	end
end

------------------------------------------------------------------------
-- RemoteEvent actions (check-in picker, ready, restart)
------------------------------------------------------------------------

actionRemote.OnServerEvent:Connect(function(player: Player, payload)
	if typeof(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	if typeof(kind) ~= "string" then
		return
	end
	if kind == RA.RequestState then
		sendState(player)
		return
	end
	if rateLimited(player) then
		return
	end

	local ok, msg
	if kind == RA.DeskClose then
		core:deskRelease(player.UserId)
		return
	elseif DESK_ACTIONS[kind] then
		if not atDesk(player) then
			core:deskRelease(player.UserId)
			feedback(player, "Go back to the front desk to check guests in.", "error")
			return
		end
		local pid, t = player.UserId, now()
		if kind == RA.DeskMode then
			ok, msg = core:deskChoose(pid, payload.mode, t)
		elseif kind == RA.DeskVerify then
			ok, msg = core:deskVerify(pid, payload.code, t)
		elseif kind == RA.DeskRoom then
			if not validRoomId(payload.roomId) then
				return
			end
			ok, msg = core:deskSelectRoom(pid, payload.roomId, t)
		elseif kind == RA.DeskMethod then
			ok, msg = core:deskSetMethod(pid, payload.method, t)
		elseif kind == RA.DeskBack then
			ok, msg = core:deskBack(pid, t)
		elseif kind == RA.DeskConfirm then
			ok, msg = core:deskConfirm(pid, { txId = payload.txId, change = payload.change }, t)
			if ok then
				feedback(player, msg, "ok")
			end
		end
		-- Errors and progress show inside the terminal (desk view), not as toasts.
		return
	elseif KITCHEN_ACTIONS[kind] then
		if not validSlot(payload.slot) then
			return
		end
		local range = Config.interaction.kitchenRange * (Config.mapScale or 1)
		if not withinRange(player, layout.kitchenPosition, range) then
			feedback(player, "Walk to the kitchen stove first.", "error")
			return
		end
		if kind == RA.Cook then
			if typeof(payload.recipe) ~= "string" then
				return
			end
			ok, msg = core:startCook(player.UserId, payload.slot, payload.recipe, now())
		elseif kind == RA.CollectDish then
			ok, msg = core:collectDish(player.UserId, payload.slot)
		else
			ok, msg = core:discardDish(player.UserId, payload.slot)
		end
	elseif kind == RA.ForwardCall then
		local call = payload.call
		if not validRoomId(payload.roomId) or (call ~= "Meal" and call ~= "Towel" and call ~= "AC") then
			return
		end
		if not atDesk(player) then
			feedback(player, "Answer the phone at the FRONT DESK.", "error")
			return
		end
		ok, msg = core:forwardCall(player.UserId, payload.roomId, call, now())
	elseif kind == RA.CancelFix then
		core:cancelFix(player.UserId)
		fixSpots[player] = nil
		return
	elseif kind == RA.FinishFix then
		local fix = payload.fix
		if fix ~= "AC" and fix ~= "Breaker" and fix ~= "Sheets" then
			return
		end
		local roomId = payload.roomId
		if roomId ~= nil and not validRoomId(roomId) then
			return
		end
		local spot = fixSpots[player]
		if not spot or not withinRange(player, spot.position, spot.range) then
			core:cancelFix(player.UserId)
			fixSpots[player] = nil
			feedback(player, "You walked away from the repair.", "error")
			return
		end
		ok, msg = core:finishFix(player.UserId, fix, roomId, now())
		if ok then
			fixSpots[player] = nil
		end
	elseif kind == RA.SetRole then
		if typeof(payload.role) ~= "string" then
			return
		end
		ok, msg = core:setRole(player.UserId, payload.role)
	elseif kind == RA.TakeSupply or kind == RA.ReturnSupplies then
		local range = Config.interaction.linenRange * (Config.mapScale or 1)
		if not withinRange(player, layout.linenPosition, range) then
			feedback(player, "Walk to the linen closet first.", "error")
			return
		end
		if kind == RA.ReturnSupplies then
			ok, msg = core:returnSupplies(player.UserId)
		else
			local item = payload.item
			if item ~= Constants.Item.Sheet and item ~= Constants.Item.Towel then
				return
			end
			ok, msg = core:takeSupply(player.UserId, item)
		end
	elseif kind == RA.Buy then
		local itemId = payload.itemId
		if typeof(itemId) ~= "string" or not core:shopItem(itemId) then
			return
		end
		local range = Config.interaction.shopRange * (Config.mapScale or 1)
		if not withinRange(player, layout.shopPosition, range) then
			feedback(player, "Walk to the shop counter to buy supplies.", "error")
			return
		end
		ok, msg = core:buyItem(player.UserId, itemId)
	elseif kind == RA.BackToLobby then
		if RunService:IsStudio() then
			feedback(player, "Back to lobby works in the live game (not in Studio).", "info")
			return
		end
		local tpOk, err = pcall(function()
			-- No TeleportOptions = a public server of this place = the lobby.
			TeleportService:TeleportAsync(game.PlaceId, { player })
		end)
		if not tpOk then
			feedback(player, "Could not reach the lobby, try again.", "error")
			warn("[Motel] Lobby teleport failed: " .. tostring(err))
		end
		return
	elseif kind == RA.Ready then
		ok, msg = core:setReady(player.UserId)
	elseif kind == RA.Restart then
		ok, msg = core:restart(player.UserId, now())
		if ok then
			broadcast(player.DisplayName .. " started a new run!", "ok")
			return
		end
	else
		return
	end
	if msg then
		feedback(player, msg, if ok then "ok" else "error")
	end
end)

------------------------------------------------------------------------
-- Players
------------------------------------------------------------------------

local function refreshPlayerCount(excluding: Player?)
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= excluding then
			n += 1
		end
	end
	core:setPlayerCount(math.max(1, n))
end

-- The map is scaled up, so players walk a bit faster than Roblox's default.
local function applyWalkSpeed(player: Player)
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.WalkSpeed = Config.player.walkSpeed
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

-- Role tag above the head (soft roles).
local function applyRoleTag(player: Player)
	local role = core.roles[player.UserId]
	player:SetAttribute("Role", role)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("RoleTag")
	if old then
		old:Destroy()
	end
	local def = role and core:roleDef(role)
	if not def then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "RoleTag"
	gui.Size = UDim2.fromScale(5, 1)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Size = UDim2.fromScale(0.24, 1.2)
	icon.Position = UDim2.fromScale(0, 0.5)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	UiAssets.applyTo(icon, def.icon)
	icon.Parent = gui
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(0.74, 1)
	text.Position = UDim2.fromScale(0.26, 0)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.fromRGB(255, 226, 120)
	text.Text = def.label:upper()
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(46, 32, 22)
	stroke.Parent = text
	text.Parent = gui
	gui.Parent = head
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.defer(applyRoleTag, player)
	end)
	refreshPlayerCount(nil)
	applyWalkSpeed(player)
	sendState(player)
end)

Players.PlayerRemoving:Connect(function(player)
	core:playerLeft(player.UserId)
	lastRequest[player] = nil
	refreshPlayerCount(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	applyWalkSpeed(player)
	player.CharacterAdded:Connect(function()
		task.defer(applyRoleTag, player)
	end)
	sendState(player)
end

------------------------------------------------------------------------
-- Event messages
------------------------------------------------------------------------

local function recipeName(id): string
	local r = core:recipe(id)
	return if r then r.name else "Food"
end

local eventMessages = {
	MealOrder = function(e)
		return ("Phone! Room %d wants %s. Answer at the FRONT DESK."):format(
			core:roomNumber(e.roomId),
			recipeName(e.recipe)
		),
			"alert"
	end,
	DishReady = function(e)
		return ("%s is ready on the stove!"):format(recipeName(e.recipe)), "ok"
	end,
	DishBurnt = function(e)
		return ("The %s burned! Throw it away and cook again."):format(recipeName(e.recipe)), "alert"
	end,
	MealMissed = function(e)
		return ("Room %d gave up on their %s."):format(core:roomNumber(e.roomId), recipeName(e.recipe)), "alert"
	end,
	Walkout = function()
		return "A guest got tired of waiting and left!", "alert"
	end,
	Checkout = function(e)
		return ("Room %d checked out. Clean it up!"):format(core:roomNumber(e.roomId or 0)), "info"
	end,
	TowelRequest = function(e)
		return ("Phone! Room %d wants a towel. Answer at the FRONT DESK."):format(core:roomNumber(e.roomId)), "alert"
	end,
	ACBroken = function(e)
		return ("Phone! The AC in Room %d broke. Answer at the FRONT DESK."):format(core:roomNumber(e.roomId)), "alert"
	end,
	CallForwarded = function(e)
		local what = if e.kind == "Meal" then "food order" elseif e.kind == "Towel" then "towel" else "AC repair"
		return ("New ticket for %s: Room %d %s."):format(e.role, core:roomNumber(e.roomId), what), "info"
	end,
	PowerOut = function()
		return "POWER OUTAGE! Reset the breaker in the lobby.", "alert"
	end,
	PowerRestored = function()
		return "Power restored.", "ok"
	end,
	Rain = function()
		return "It's raining. Guests are less patient tonight.", "info"
	end,
	GuestArriving = function()
		return "A car pulls into the lot.", "info"
	end,
}

------------------------------------------------------------------------
-- Main loop
------------------------------------------------------------------------

-- Releases the front desk when its owner walks away, dies or is gone.
local deskCheckTimer = 0
local function checkDeskOwner(dt: number)
	deskCheckTimer -= dt
	if deskCheckTimer > 0 or not core.desk then
		return
	end
	deskCheckTimer = 0.25
	local owner = Players:GetPlayerByUserId(core.desk.owner)
	local range = Config.interaction.deskRange * (Config.mapScale or 1) + Config.interaction.rangeSlack
	if not owner then
		core:deskRelease(core.desk.owner)
	elseif not withinRange(owner, layout.deskPosition, range) then
		core:deskRelease(owner.UserId)
		feedback(owner, "You left the front desk.", "info")
	end
end

local lastVersion = -1
local savedRunId = nil
local resendTimer = 0

RunService.Heartbeat:Connect(function(dt)
	local t = now()
	core:update(t)
	checkDeskOwner(dt)

	-- Save every finished run once (profile + leaderboard) and announce records.
	if core.phase == Constants.Phase.RunEnded and savedRunId ~= core.runId then
		savedRunId = core.runId
		local nights, served = core.nightsSurvived, core.totals.served
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				local profile, isRecord, saved = Persistence.recordRun(player.UserId, nights, served)
				if isRecord then
					feedbackRemote:FireClient(player, {
						text = ("NEW RECORD! %d night%s survived"):format(nights, if nights == 1 then "" else "s"),
						kind = "record",
					})
				elseif not saved then
					warn("[Motel] Could not save run for " .. player.Name .. " (DataStore offline?)")
				end
				player:SetAttribute("BestNights", profile.best)
			end)
		end
	end

	for _, e in ipairs(core:drainEvents()) do
		if e.kind == "RoleChanged" then
			local p = Players:GetPlayerByUserId(e.by)
			if p then
				applyRoleTag(p)
			end
		end
		local fn = eventMessages[e.kind]
		if fn then
			local text, kind = fn(e)
			-- e.by is set for player-caused events (e.g. PowerRestored); skip that player.
			broadcast(text, kind, if typeof(e.by) == "number" then e.by else nil)
		end
	end

	visuals:sync(core, t, dt)

	resendTimer -= dt
	if core.version ~= lastVersion or resendTimer <= 0 then
		lastVersion = core.version
		resendTimer = 2 -- periodic resync in case a client missed an update
		visuals:refreshWorld(core)
		sendStateAll()
	end
end)

print(
	("[Motel] Server ready. %d rooms, %d scripted nights then endless, timeScale %.2f"):format(
		Config.roomCount,
		#Config.nights,
		timeScale
	)
)
