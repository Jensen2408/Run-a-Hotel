--!nonstrict
-- Client entry: wires remotes to the HUD. The client never decides outcomes;
-- it only displays snapshots and sends requests the server validates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local Tutorial = require(script.Parent:WaitForChild("Tutorial"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Constants.Remotes.Folder)
local actionRemote = remotes:WaitForChild(Constants.Remotes.Action)
local stateRemote = remotes:WaitForChild(Constants.Remotes.State)
local feedbackRemote = remotes:WaitForChild(Constants.Remotes.Feedback)
local openCheckInRemote = remotes:WaitForChild(Constants.Remotes.OpenCheckIn)

local RA = Constants.RemoteAction

local hud = Hud.new(player:WaitForChild("PlayerGui"), Config, {
	sfx = Sfx.new(),
	onCheckIn = function(roomId: number)
		actionRemote:FireServer({ kind = RA.CheckIn, roomId = roomId })
	end,
	onReady = function()
		actionRemote:FireServer({ kind = RA.Ready })
	end,
	onRestart = function()
		actionRemote:FireServer({ kind = RA.Restart })
	end,
})

-- First-night tutorial with arrows (client only).
local tutorial = Tutorial.new(hud)

local lastPhase = nil
stateRemote.OnClientEvent:Connect(function(snapshot)
	if typeof(snapshot) ~= "table" then
		return
	end
	if snapshot.phase ~= lastPhase then
		local banners = {
			Preparation = {
				("GET READY: NIGHT %d"):format(snapshot.night),
				"Clean rooms, restock, buy supplies.",
				"sun",
			},
			Night = { "NIGHT FALLS!", "Guests are on their way.", "moon" },
			Closing = { "CLOSING TIME", "No more check-ins. Finish up!", "alarm" },
			Report = { "NIGHT OVER", "Counting the money...", "coin" },
		}
		local b = banners[snapshot.phase]
		if b and (lastPhase ~= nil or snapshot.phase == "Preparation") then
			hud:banner(b[1], b[2], b[3])
		end
		lastPhase = snapshot.phase
	end
	hud:setState(snapshot)
	tutorial:update(snapshot)
end)

feedbackRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) == "table" and typeof(payload.text) == "string" then
		hud:toast(payload.text, payload.kind)
	end
end)

openCheckInRemote.OnClientEvent:Connect(function()
	hud:openPicker()
end)

RunService.RenderStepped:Connect(function()
	hud:tick()
	tutorial:tick()
end)

actionRemote:FireServer({ kind = RA.RequestState })
