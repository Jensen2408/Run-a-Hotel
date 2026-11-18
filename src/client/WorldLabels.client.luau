--!nonstrict
--[[
	WorldLabels: keeps the labels above objects readable.

	A BillboardGui is a flat card that turns to face the camera. Next to a
	wall (linen shelf, stove, breaker, room signs) part of that card goes
	into the wall when the camera turns, so the text gets cut off.

	Here every world label is drawn on top (AlwaysOnTop, set locally) so it
	is never cut, and a raycast from the camera hides it while the object is
	really behind a wall, so labels do not show through buildings either.
	Glass, transparent and decorative parts (CanQuery off) do not block.

	Covers: object labels ("Label", MapBuilder), guest mood labels ("Mood",
	Visuals) and role tags ("RoleTag", above players).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Mode = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Mode"))
if Mode.get() ~= Mode.Game then
	return
end

local NAMES = { Label = true, Mood = true, RoleTag = true }
local CHECK_EVERY = 0.12 -- seconds between visibility checks
local MAX_PASSES = 4 -- see-through parts skipped per ray

local labels = {} -- [BillboardGui] = true

local function track(gui: Instance)
	if gui:IsA("BillboardGui") and NAMES[gui.Name] and not labels[gui] then
		labels[gui] = true
		gui.AlwaysOnTop = true
		gui.Destroying:Once(function()
			labels[gui] = nil
		end)
	end
end

for _, d in ipairs(Workspace:GetDescendants()) do
	track(d)
end
Workspace.DescendantAdded:Connect(track)

-- World point the label hangs at.
local function anchorOf(gui: BillboardGui): Vector3?
	local adornee = gui.Adornee or gui.Parent
	local base
	if adornee and adornee:IsA("BasePart") then
		base = adornee.Position
	elseif adornee and adornee:IsA("Attachment") then
		base = adornee.WorldPosition
	elseif adornee and adornee:IsA("Model") then
		base = adornee:GetPivot().Position
	end
	if not base then
		return nil
	end
	return base + gui.StudsOffsetWorldSpace + Vector3.new(0, gui.StudsOffset.Y, 0)
end

-- A part blocks the view when it is solid and mostly opaque. Walls hidden
-- under a Blender kit mesh (Occluder) still block: the mesh itself is not
-- queryable, so its invisible gameplay wall stands in for it.
local function blocks(part: BasePart): boolean
	return part.CanCollide and (part.Transparency < 0.25 or part:GetAttribute("Occluder") == true)
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function visible(from: Vector3, to: Vector3, ignore): boolean
	local skip = table.clone(ignore)
	local dir = to - from
	for _ = 1, MAX_PASSES do
		params.FilterDescendantsInstances = skip
		local hit = Workspace:Raycast(from, dir, params)
		if not hit then
			return true
		end
		if blocks(hit.Instance) then
			return false
		end
		table.insert(skip, hit.Instance)
	end
	return true
end

local timer = 0
RunService.Heartbeat:Connect(function(dt)
	timer -= dt
	if timer > 0 then
		return
	end
	timer = CHECK_EVERY
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local character = Players.LocalPlayer.Character
	for gui in pairs(labels) do
		if not gui.Parent then
			labels[gui] = nil
		else
			local point = anchorOf(gui)
			local show = false
			if point then
				local dist = (point - camPos).Magnitude
				if dist <= gui.MaxDistance then
					-- Ignore the labelled object itself (and its model) and the local character.
					local owner = gui.Parent
					local model = owner and owner:FindFirstAncestorOfClass("Model")
					local ignore = { owner }
					if model then
						table.insert(ignore, model)
					end
					if character then
						table.insert(ignore, character)
					end
					show = visible(camPos, point, ignore)
				end
			end
			if gui.Enabled ~= show then
				gui.Enabled = show
			end
		end
	end
end)
