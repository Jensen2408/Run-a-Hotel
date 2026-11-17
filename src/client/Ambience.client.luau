--!nonstrict
-- Client-only ambience for the motel scenery. Purely cosmetic and local:
--   Chase bulbs   marquee chase on the MOTEL / OFFICE signs
--   Blink bulbs   slow twinkle on string lights
--   Flicker       campfire light brightness
--   Fireflies     particle emitters enabled at night
-- Neon dims when the server marks Workspace.Motel "Powered" = false.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Mode = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Mode"))
if Mode.get() ~= Mode.Game then
	return
end

local chase, blink, bulbs, flicker, fireflies = {}, {}, {}, {}, {}
local motel: Instance? = nil

local lastPowered: boolean? = nil
local lastNight: boolean? = nil

-- Registers one instance. Called for existing descendants and for every
-- part that streams in later (StreamingEnabled sends far parts gradually).
local function register(d: Instance)
	if d:IsA("BasePart") then
		if d:GetAttribute("Chase") then
			table.insert(chase, { part = d, index = d:GetAttribute("Chase") })
		elseif d:GetAttribute("Blink") then
			table.insert(blink, { part = d, period = d:GetAttribute("Blink"), offset = math.random() * 3 })
		elseif d:GetAttribute("Bulb") then
			table.insert(bulbs, d)
			lastPowered = nil -- re-apply the power state to new bulbs
		end
	elseif d:IsA("Light") and d:GetAttribute("Flicker") then
		table.insert(flicker, { light = d, base = d:GetAttribute("Flicker") })
	elseif d:IsA("ParticleEmitter") and d:GetAttribute("Fireflies") then
		table.insert(fireflies, d)
		lastNight = nil
	end
end

local addedConnection: RBXScriptConnection? = nil
local function attach(root: Instance)
	motel = root
	table.clear(chase)
	table.clear(blink)
	table.clear(bulbs)
	table.clear(flicker)
	table.clear(fireflies)
	if addedConnection then
		addedConnection:Disconnect()
	end
	addedConnection = root.DescendantAdded:Connect(register)
	for _, d in ipairs(root:GetDescendants()) do
		register(d)
	end
end

-- Drops entries whose instance streamed out or was destroyed.
local function prune()
	local function keepParts(list)
		for i = #list, 1, -1 do
			local item = list[i]
			local inst = if typeof(item) == "Instance" then item else (item.part or item.light)
			if not inst.Parent then
				table.remove(list, i)
			end
		end
	end
	keepParts(chase)
	keepParts(blink)
	keepParts(bulbs)
	keepParts(flicker)
	keepParts(fireflies)
end

Workspace.ChildAdded:Connect(function(child)
	if child.Name == "Motel" then
		attach(child)
	end
end)
task.spawn(function()
	attach(Workspace:WaitForChild("Motel"))
end)
task.spawn(function()
	while true do
		task.wait(5)
		prune()
	end
end)

local accumulator = 0

RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	if accumulator < 1 / 20 or not motel then
		return
	end
	accumulator = 0
	local t = os.clock()
	local powered = motel:GetAttribute("Powered") ~= false
	local clock = Lighting.ClockTime
	local night = clock < 6.3 or clock > 17.5

	-- Marquee: every third bulb lit, stepping 8 times a second.
	local stepIndex = math.floor(t * 8)
	for _, c in ipairs(chase) do
		local on = powered and ((c.index + stepIndex) % 3 ~= 0)
		c.part.Transparency = if on then 0 else 0.75
	end
	for _, b in ipairs(blink) do
		local on = powered and math.sin((t + b.offset) * math.pi * 2 / b.period) > -0.6
		b.part.Transparency = if on then 0 else 0.6
	end
	if powered ~= lastPowered then
		lastPowered = powered
		for _, p in ipairs(bulbs) do
			p.Transparency = if powered then 0 else 0.8
		end
	end
	for _, f in ipairs(flicker) do
		f.light.Brightness = f.base * (0.75 + 0.35 * math.noise(t * 3, f.base))
	end
	if night ~= lastNight then
		lastNight = night
		for _, em in ipairs(fireflies) do
			em.Enabled = night
		end
	end
end)
