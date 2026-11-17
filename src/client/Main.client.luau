--!nonstrict
-- Client entry: wires remotes to the HUD. The client never decides outcomes;
-- it only displays snapshots and sends requests the server validates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mode = require(Shared:WaitForChild("Mode"))
if Mode.get() ~= Mode.Game then
	return -- lobby server: LobbyClient runs instead
end
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local DeskHud = require(script.Parent:WaitForChild("DeskHud"))
local Tutorial = require(script.Parent:WaitForChild("Tutorial"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local UiKit = require(script.Parent:WaitForChild("UiKit"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Constants.Remotes.Folder)
local actionRemote = remotes:WaitForChild(Constants.Remotes.Action)
local stateRemote = remotes:WaitForChild(Constants.Remotes.State)
local feedbackRemote = remotes:WaitForChild(Constants.Remotes.Feedback)
local openCheckInRemote = remotes:WaitForChild(Constants.Remotes.OpenCheckIn)
local openShopRemote = remotes:WaitForChild(Constants.Remotes.OpenShop)
local openLinenRemote = remotes:WaitForChild(Constants.Remotes.OpenLinen)

local RA = Constants.RemoteAction

local sfx = Sfx.new()
local hud = Hud.new(player:WaitForChild("PlayerGui"), Config, {
	sfx = sfx,
	onTakeSupply = function(item: string)
		actionRemote:FireServer({ kind = RA.TakeSupply, item = item })
	end,
	onReturnSupplies = function()
		actionRemote:FireServer({ kind = RA.ReturnSupplies })
	end,
	onBuy = function(itemId: string)
		actionRemote:FireServer({ kind = RA.Buy, itemId = itemId })
	end,
	onReady = function()
		actionRemote:FireServer({ kind = RA.Ready })
	end,
	onBackToLobby = function()
		actionRemote:FireServer({ kind = RA.BackToLobby })
	end,
	onRestart = function()
		actionRemote:FireServer({ kind = RA.Restart })
	end,
})

-- Front desk terminal (opened by the desk prompt, driven by state.desk).
local desk = DeskHud.new(player:WaitForChild("PlayerGui"), {
	send = function(payload)
		actionRemote:FireServer(payload)
	end,
})

-- Music + volume settings (gear button, top right).
UiKit.setSfx(sfx)
Settings.new(player:WaitForChild("PlayerGui"), sfx, "game")

-- First-night tutorial with arrows (client only).
local tutorial = Tutorial.new(hud)

local lastPhase = nil
stateRemote.OnClientEvent:Connect(function(snapshot)
	if typeof(snapshot) ~= "table" then
		return
	end
	desk:setState(snapshot)
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
	if typeof(payload) ~= "table" or typeof(payload.text) ~= "string" then
		return
	end
	if payload.kind == "record" then
		-- New personal best: big banner, confetti and fanfare.
		hud:banner("NEW RECORD!", payload.text, "trophy")
		hud:confetti(80)
		sfx:play("fanfare")
		return
	end
	hud:toast(payload.text, payload.kind)
end)

openCheckInRemote.OnClientEvent:Connect(function(info)
	desk:open(if typeof(info) == "table" then info else nil)
end)

openShopRemote.OnClientEvent:Connect(function()
	hud:openShop()
end)

openLinenRemote.OnClientEvent:Connect(function()
	hud:openLinen()
end)

-- Close station panels when the player walks away from the station.
local SCALE = Config.mapScale or 1
local stations = {
	{ panel = "shop", part = "SupplyShop", range = Config.interaction.shopRange * SCALE + 6, close = "closeShop" },
	{ panel = "linen", part = "LinenShelf", range = Config.interaction.linenRange * SCALE + 6, close = "closeLinen" },
}
local function checkShopDistance()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local motel = workspace:FindFirstChild("Motel")
	local interact = motel and motel:FindFirstChild("Interactables")
	if not (hrp and interact) then
		return
	end
	for _, st in ipairs(stations) do
		if hud[st.panel].Visible then
			local part = interact:FindFirstChild(st.part)
			if part and (hrp.Position - part.Position).Magnitude > st.range then
				hud[st.close](hud)
			end
		end
	end
end

RunService.RenderStepped:Connect(function()
	hud:tick()
	desk:tick()
	tutorial:tick()
	checkShopDistance()
end)

actionRemote:FireServer({ kind = RA.RequestState })
