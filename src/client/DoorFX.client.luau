--!nonstrict
--[[
	DoorFX: swings the hinged Blender kit doors (Models with the KitDoor
	attribute, built by Kit.door) open while a player or a guest NPC is
	near, and closed again when they leave.

	Purely cosmetic and local: every client animates its own copy, the
	server never moves the doors (their colliders are the invisible
	gameplay walls, so nothing is blocked either way).

	Door model: PrimaryPart "Hinge" on the hinge line; Swing = degrees
	about +Y that open it (sign = direction, inward).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Mode = require(Shared:WaitForChild("Mode"))
if Mode.get() ~= Mode.Game then
	return
end
local Config = require(Shared:WaitForChild("Config"))

local SCALE = Config.mapScale or 1
local RANGE = 7 * SCALE -- studs from the hinge
local SPEED = 2.6 -- open fraction per second
local SCAN_EVERY = 0.1

local doors = {} -- [Model] = { closed = CFrame, hinge = Vector3, swing = number, t = number, target = number }

local function register(inst: Instance)
	if not inst:IsA("Model") or not inst:GetAttribute("KitDoor") or doors[inst] then
		return
	end
	local hinge = inst.PrimaryPart or inst:FindFirstChild("Hinge")
	if not hinge then
		return
	end
	doors[inst] = {
		closed = inst:GetPivot(),
		hinge = hinge.Position,
		swing = math.rad(tonumber(inst:GetAttribute("Swing")) or 90),
		t = 0,
		target = 0,
	}
	inst.Destroying:Once(function()
		doors[inst] = nil
	end)
end

local function attach(motel: Instance)
	for _, d in ipairs(motel:GetDescendants()) do
		register(d)
	end
	motel.DescendantAdded:Connect(function(d)
		-- Atomic door models arrive whole; the attribute may be set a frame later.
		task.defer(register, d)
	end)
end

local motel = Workspace:FindFirstChild("Motel")
if motel then
	attach(motel)
end
Workspace.ChildAdded:Connect(function(child)
	if child.Name == "Motel" then
		table.clear(doors)
		attach(child)
	end
end)

-- Everyone who can walk through a door: player characters and guest NPCs.
local function people(): { Vector3 }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(out, root.Position)
		end
	end
	local runtime = Workspace:FindFirstChild("Motel") and Workspace.Motel:FindFirstChild("Runtime")
	if runtime then
		for _, m in ipairs(runtime:GetChildren()) do
			local root = m:IsA("Model") and m:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(out, root.Position)
			end
		end
	end
	return out
end

local function ease(t: number): number
	return t * t * (3 - 2 * t)
end

local scan = 0
RunService.Heartbeat:Connect(function(dt)
	scan -= dt
	if scan <= 0 then
		scan = SCAN_EVERY
		local list = people()
		for _, d in pairs(doors) do
			local near = false
			for _, pos in ipairs(list) do
				if (pos - d.hinge).Magnitude < RANGE then
					near = true
					break
				end
			end
			d.target = if near then 1 else 0
		end
	end
	for model, d in pairs(doors) do
		if d.t ~= d.target then
			local step = SPEED * dt
			d.t = if d.target > d.t then math.min(d.target, d.t + step) else math.max(d.target, d.t - step)
			if model.Parent then
				model:PivotTo(d.closed * CFrame.Angles(0, d.swing * ease(d.t), 0))
			end
		end
	end
end)
