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

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Constants.Remotes.Folder)
local actionRemote = remotes:WaitForChild(Constants.Remotes.Action)
local stateRemote = remotes:WaitForChild(Constants.Remotes.State)
local feedbackRemote = remotes:WaitForChild(Constants.Remotes.Feedback)
local openCheckInRemote = remotes:WaitForChild(Constants.Remotes.OpenCheckIn)

local RA = Constants.RemoteAction

local hud = Hud.new(player:WaitForChild("PlayerGui"), Config, {
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

local lastPhase = nil
stateRemote.OnClientEvent:Connect(function(snapshot)
	if typeof(snapshot) ~= "table" then
		return
	end
	if snapshot.phase ~= lastPhase then
		if lastPhase ~= nil then
			local banner = {
				Preparation = ("Preparation: get ready for Night %d"):format(snapshot.night),
				Night = "Night falls. Guests are coming!",
				Closing = "Closing time. No more check-ins.",
				Report = "The night is over.",
			}
			if banner[snapshot.phase] then
				hud:toast(banner[snapshot.phase], "info")
			end
		end
		lastPhase = snapshot.phase
	end
	hud:setState(snapshot)
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
end)

actionRemote:FireServer({ kind = RA.RequestState })
