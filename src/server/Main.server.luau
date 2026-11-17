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
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local MotelCore = require(script.Parent:WaitForChild("MotelCore"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local Visuals = require(script.Parent:WaitForChild("Visuals"))
local LightingFX = require(script.Parent:WaitForChild("LightingFX"))

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
remotes.Parent = ReplicatedStorage

------------------------------------------------------------------------
-- Setup
------------------------------------------------------------------------

local timeScale = Config.timeScale
if RunService:IsStudio() and Config.allowStudioTimeScaleOverride then
	local override = Workspace:GetAttribute("TimeScale")
	if typeof(override) == "number" and override > 0 and override <= 4 then
		timeScale = override
		warn(("[Motel] Studio TimeScale override active: %.2f"):format(timeScale))
	end
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

local core = MotelCore.new(Config, Constants, {
	now = now(),
	timeScale = timeScale,
	playerCount = math.max(1, #Players:GetPlayers()),
	random = function(a, b)
		return rng:NextNumber(a, b)
	end,
})
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

local function validRoomId(roomId): boolean
	return typeof(roomId) == "number" and roomId == math.floor(roomId) and roomId >= 1 and roomId <= Config.roomCount
end

------------------------------------------------------------------------
-- ProximityPrompt interactions
------------------------------------------------------------------------

local promptHandlers = {
	[PA.OpenCheckIn] = function(player: Player)
		local ok, err = core:checkInPrecheck()
		if not ok then
			return false, err
		end
		openCheckInRemote:FireClient(player)
		return nil, nil -- no toast; the client opens the room picker
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
	[PA.ResetBreaker] = function(player)
		return core:resetBreaker(player.UserId)
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
	[PA.ChangeSheets] = function(player, roomId)
		return core:changeSheets(player.UserId, roomId)
	end,
	[PA.DeliverTowel] = function(player, roomId)
		return core:deliverTowel(player.UserId, roomId)
	end,
	[PA.RepairAC] = function(player, roomId)
		return core:repairAC(player.UserId, roomId)
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
	local ok, msg = handler(player, roomId)
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
	if kind == RA.CheckIn then
		local roomId = payload.roomId
		if not validRoomId(roomId) then
			return
		end
		if not withinRange(player, layout.deskPosition, Config.interaction.deskRange * (Config.mapScale or 1)) then
			feedback(player, "Go back to the front desk to check guests in.", "error")
			return
		end
		ok, msg = core:checkIn(player.UserId, roomId, now())
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

Players.PlayerAdded:Connect(function(player)
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
	sendState(player)
end

------------------------------------------------------------------------
-- Event messages
------------------------------------------------------------------------

local eventMessages = {
	Walkout = function()
		return "A guest got tired of waiting and left!", "alert"
	end,
	Checkout = function(e)
		return ("Room %d checked out. Clean it up!"):format(e.roomId or 0), "info"
	end,
	TowelRequest = function(e)
		return ("Room %d wants a towel!"):format(e.roomId), "alert"
	end,
	ACBroken = function(e)
		return ("The AC in Room %d broke! Repair it."):format(e.roomId), "alert"
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

local lastVersion = -1
local resendTimer = 0

RunService.Heartbeat:Connect(function(dt)
	local t = now()
	core:update(t)

	for _, e in ipairs(core:drainEvents()) do
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

print(("[Motel] Server ready. %d rooms, %d nights, timeScale %.2f"):format(Config.roomCount, #Config.nights, timeScale))
