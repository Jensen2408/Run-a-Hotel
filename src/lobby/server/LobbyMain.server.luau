--!nonstrict
--[[
	Lobby server: room pads 1..4, group teleport into a reserved Game server,
	TOP NIGHTS leaderboard and per-player profile.

	Pads: a player standing on pad N joins room N (capacity N). The first
	player starts a countdown (Config.lobby.padCountdown); the room launches
	when it is full or the countdown ends. Launch = TeleportService into a
	fresh reserved server of this same place (which then runs in Game mode,
	see Shared/Mode), with { partySize } teleport data. In Studio the launch
	is only simulated.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mode = require(Shared:WaitForChild("Mode"))
if Mode.get() ~= Mode.Lobby then
	return -- this server runs a motel game
end

local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local LobbyBuilder = require(script.Parent:WaitForChild("LobbyBuilder"))
-- Shared with the game server.
local ServerModules = game:GetService("ServerScriptService"):WaitForChild("Server")
local Persistence = require(ServerModules:WaitForChild("Persistence"))
local LightingFX = require(ServerModules:WaitForChild("LightingFX"))

local SCALE = Config.mapScale or 1
local R = Constants.LobbyRemotes

------------------------------------------------------------------------
-- Remotes
------------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = R.Folder
local function remote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local roomsRemote = remote(R.Rooms)
local profileRemote = remote(R.Profile)
local leaveRemote = remote(R.Leave)
local noticeRemote = remote(R.Notice)
remotes.Parent = ReplicatedStorage

local function notice(player: Player?, text: string, kind: string?)
	local payload = { text = text, kind = kind or "info" }
	if player then
		noticeRemote:FireClient(player, payload)
	else
		noticeRemote:FireAllClients(payload)
	end
end

------------------------------------------------------------------------
-- World
------------------------------------------------------------------------

-- A motel map saved in the place file (Edit-mode preview) is not needed here.
local savedMotel = Workspace:FindFirstChild("Motel")
if savedMotel then
	savedMotel:Destroy()
end
local lobby = LobbyBuilder.build(SCALE)
-- Only the lobby spawn is used.
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("SpawnLocation") and not d:IsDescendantOf(lobby) then
		d.Enabled = false
	end
end
LightingFX.apply()
local lighting = game:GetService("Lighting")
lighting.ClockTime = 19.2
lighting.ExposureCompensation = -0.2

------------------------------------------------------------------------
-- Rooms / pads
------------------------------------------------------------------------

local rooms = {}
for i = 1, Config.lobby.maxRooms do
	rooms[i] = {
		size = i,
		players = {}, -- array of Player
		endsAt = nil,
		launching = false,
		cooldownUntil = 0,
		center = Vector3.new(LobbyBuilder.ROOM_X[i], 0, LobbyBuilder.PAD_Z) * SCALE,
	}
end
local padRadius = LobbyBuilder.PAD_RADIUS * SCALE
local leftUntil: { [Player]: number } = {} -- after LEAVE, ignore the pad briefly

local function roomOf(player: Player)
	for i, room in ipairs(rooms) do
		for _, p in ipairs(room.players) do
			if p == player then
				return i, room
			end
		end
	end
	return nil, nil
end

local function removeFrom(room, player)
	for k, p in ipairs(room.players) do
		if p == player then
			table.remove(room.players, k)
			break
		end
	end
	if #room.players == 0 then
		room.endsAt = nil
	end
end

local function snapshot()
	local list = {}
	for i, room in ipairs(rooms) do
		local names = {}
		for _, p in ipairs(room.players) do
			table.insert(names, { userId = p.UserId, name = p.DisplayName })
		end
		list[i] = { size = room.size, players = names, endsAt = room.endsAt, launching = room.launching }
	end
	return { rooms = list }
end

local dirty = true
local function broadcastRooms()
	dirty = false
	roomsRemote:FireAllClients(snapshot())
	-- Signs above the pads.
	for i, room in ipairs(rooms) do
		local sign = lobby.Pads:FindFirstChild("Sign" .. i)
		local bb = sign and sign:FindFirstChild("Status")
		if bb then
			local count = bb:FindFirstChild("Count")
			if count then
				if room.launching then
					count.Text = "STARTING..."
				elseif room.endsAt then
					local left = math.max(0, math.ceil(room.endsAt - Workspace:GetServerTimeNow()))
					count.Text = ("%d/%d  ·  %ds"):format(#room.players, room.size, left)
				else
					count.Text = ("%s  %d/%d"):format(LobbyBuilder.ROOM_NAMES[i], #room.players, room.size)
				end
			end
		end
	end
end

-- Nudges players off a pad (after a simulated or failed launch).
local function stepOff(players)
	for _, p in ipairs(players) do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.CFrame = hrp.CFrame - Vector3.new(0, 0, padRadius + 6 * SCALE)
		end
		leftUntil[p] = os.clock() + 3
	end
end

local function launch(i)
	local room = rooms[i]
	local party = table.clone(room.players)
	if #party == 0 then
		return
	end
	room.launching = true
	dirty = true
	broadcastRooms()
	if RunService:IsStudio() then
		notice(
			nil,
			("Room %d would start now with %d player(s) (teleport only works in the live game)."):format(i, #party),
			"info"
		)
		task.wait(1.5)
	else
		local ok, err = pcall(function()
			local code = TeleportService:ReserveServer(game.PlaceId)
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = code
			options:SetTeleportData({ partySize = #party, room = i })
			TeleportService:TeleportAsync(game.PlaceId, party, options)
		end)
		if ok then
			for _, p in ipairs(party) do
				notice(p, "Heading to the motel...", "ok")
			end
			task.wait(8) -- teleport in progress; keep the room locked meanwhile
		else
			warn("[Lobby] Teleport failed: " .. tostring(err))
			for _, p in ipairs(party) do
				notice(p, "Could not start the room, try again.", "error")
			end
		end
	end
	-- Reset the room; anyone still here steps off the pad.
	local stillHere = {}
	for _, p in ipairs(party) do
		if p.Parent == Players then
			table.insert(stillHere, p)
		end
	end
	room.players = {}
	room.endsAt = nil
	room.launching = false
	room.cooldownUntil = os.clock() + 2
	stepOff(stillHere)
	dirty = true
end

leaveRemote.OnServerEvent:Connect(function(player)
	local _, room = roomOf(player)
	if room and not room.launching then
		removeFrom(room, player)
		leftUntil[player] = os.clock() + 4
		stepOff({ player })
		dirty = true
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local _, room = roomOf(player)
	if room then
		removeFrom(room, player)
		dirty = true
	end
	leftUntil[player] = nil
end)

-- Pad membership + countdowns, checked a few times per second.
task.spawn(function()
	local signTimer = 0
	while true do
		task.wait(0.2)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local onPad = nil
			if hrp and not (leftUntil[player] and now < leftUntil[player]) then
				for i, room in ipairs(rooms) do
					local d = Vector3.new(hrp.Position.X - room.center.X, 0, hrp.Position.Z - room.center.Z).Magnitude
					if d <= padRadius then
						onPad = i
						break
					end
				end
			end
			local current, currentRoom = roomOf(player)
			if current ~= onPad and not (currentRoom and currentRoom.launching) then
				if currentRoom then
					removeFrom(currentRoom, player)
					dirty = true
				end
				local target = onPad and rooms[onPad]
				if target and not target.launching and now >= target.cooldownUntil then
					if #target.players < target.size then
						table.insert(target.players, player)
						if not target.endsAt then
							target.endsAt = Workspace:GetServerTimeNow() + Config.lobby.padCountdown
						end
						dirty = true
					else
						notice(player, ("Room %d is full."):format(onPad), "error")
						leftUntil[player] = now + 2
					end
				end
			end
		end
		for i, room in ipairs(rooms) do
			if not room.launching and #room.players > 0 then
				local full = #room.players >= room.size
				local timeUp = room.endsAt and Workspace:GetServerTimeNow() >= room.endsAt
				if full or timeUp then
					task.spawn(launch, i)
				end
			end
		end
		signTimer -= 0.2
		if dirty or signTimer <= 0 then
			signTimer = 1
			broadcastRooms()
		end
	end
end)

------------------------------------------------------------------------
-- Leaderboard + profiles
------------------------------------------------------------------------

task.spawn(function()
	local board = lobby.Boards:WaitForChild("Leaderboard")
	while true do
		local entries = Persistence.topNights(Config.lobby.leaderboardSize)
		LobbyBuilder.fillLeaderboard(board, entries)
		task.wait(Config.lobby.leaderboardRefresh)
	end
end)

local function sendProfile(player: Player)
	local profile, online = Persistence.loadProfile(player.UserId)
	profile.online = online
	profileRemote:FireClient(player, profile)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(sendProfile, player)
	task.defer(function()
		roomsRemote:FireClient(player, snapshot())
	end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(sendProfile, player)
end

print("[Lobby] Ready.")
