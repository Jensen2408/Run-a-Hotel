--!strict
--[[
	One place, two modes. Every server decides at startup what it runs:

	  Lobby  public servers (players joining from the game page): lobby hall,
	         room pads, leaderboard
	  Game   reserved servers created by the lobby (TeleportService:
	         ReserveServer(game.PlaceId)): the motel run

	In Studio there is no reserved server, so Config.studioMode picks the
	mode ("Game" or "Lobby").

	The server publishes the result as Workspace attribute "Mode"; clients
	wait for it. Scripts call Mode.get() and return early when the mode is
	not theirs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Mode = {}

Mode.Lobby = "Lobby"
Mode.Game = "Game"

local function decide(): string
	if RunService:IsStudio() then
		local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")) :: any
		return if Config.studioMode == Mode.Lobby then Mode.Lobby else Mode.Game
	end
	-- Reserved servers have a PrivateServerId but no owner.
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
		return Mode.Game
	end
	return Mode.Lobby
end

local cached: string? = nil

function Mode.get(): string
	if cached then
		return cached
	end
	if RunService:IsServer() then
		local m = decide()
		Workspace:SetAttribute("Mode", m)
		cached = m
		return m
	end
	-- Client: the server sets the attribute before anyone joins, but wait to be safe.
	local m = Workspace:GetAttribute("Mode")
	while m ~= Mode.Game and m ~= Mode.Lobby do
		Workspace:GetAttributeChangedSignal("Mode"):Wait()
		m = Workspace:GetAttribute("Mode")
	end
	cached = m :: string
	return m :: string
end

return Mode
