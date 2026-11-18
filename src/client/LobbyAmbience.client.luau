--!nonstrict
-- Client-only ambience for the lobby (cosmetic, local):
--   Flicker   lights with a "Flicker" attribute (fireplace, lanterns)
--   Twinkle   the Christmas string-light meshes breathe softly, each at its
--             own pace, so the bulbs feel alive without blinking

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Mode = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Mode"))
if Mode.get() ~= Mode.Lobby then
	return
end

local TWINKLE = {
	SM_Xmas_Hall_Lights = true,
	SM_Xmas_Int_Lights = true,
	SM_Xmas_Tree_Glow = true,
	SM_Xmas_PathLantern_Glow = true,
	SM_Bld_LobbyTitle_Glow = true,
	SM_Bld_LobbyHall_Glow = true,
	SM_Prop_LobbyPad_Glow = true,
}

local flicker, twinkle = {}, {}

local function register(d: Instance)
	if d:IsA("Light") and typeof(d:GetAttribute("Flicker")) == "number" then
		table.insert(flicker, { light = d, base = d:GetAttribute("Flicker"), seed = math.random() * 100 })
	elseif d:IsA("BasePart") and TWINKLE[d.Name] then
		table.insert(twinkle, { part = d, speed = 0.6 + math.random() * 0.8, offset = math.random() * 10 })
	end
end

task.spawn(function()
	local lobby = Workspace:WaitForChild("Lobby")
	lobby.DescendantAdded:Connect(register)
	for _, d in ipairs(lobby:GetDescendants()) do
		register(d)
	end
end)

local acc = 0
RunService.RenderStepped:Connect(function(dt)
	acc += dt
	if acc < 1 / 24 then
		return
	end
	acc = 0
	local t = os.clock()
	for i = #flicker, 1, -1 do
		local f = flicker[i]
		if not f.light.Parent then
			table.remove(flicker, i)
		else
			f.light.Brightness = f.base * (0.78 + 0.32 * math.noise(t * 3.2, f.seed))
		end
	end
	for i = #twinkle, 1, -1 do
		local w = twinkle[i]
		if not w.part.Parent then
			table.remove(twinkle, i)
		else
			w.part.Transparency = 0.12 * (0.5 + 0.5 * math.sin((t + w.offset) * w.speed * math.pi))
		end
	end
end)
