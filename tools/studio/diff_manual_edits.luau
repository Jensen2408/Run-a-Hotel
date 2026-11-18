--[[
	Find objects moved / resized by hand in the Edit-mode map
	(Workspace.Motel) compared to a fresh build from the code.

	Run in the Studio command bar (or via MCP execute_luau, Edit). It:
	  1. backs the current map up (ServerStorage.Motel_UserBackup),
	  2. builds a reference map from ServerScriptService.Server (a clone, so
	     the require cache is fresh),
	  3. prints every part whose position / size / turn differs (scale-1
	     coordinates, i.e. divided by Config.mapScale),
	  4. puts the hand-edited map back exactly as it was.

	Then port the differences into MapBuilder / MapDecor so the next map
	rebuild (MapVersion bump) keeps them, and delete the backup.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local S = Config.mapScale or 1
local user = workspace:FindFirstChild("Motel")
assert(user, "no Workspace.Motel")
local backup = user:Clone()
backup.Name = "Motel_UserBackup"
backup.Parent = game.ServerStorage

local function keyed(root)
	local map = {}
	local function walk(inst, prefix)
		local counts = {}
		for _, c in ipairs(inst:GetChildren()) do
			counts[c.Name] = (counts[c.Name] or 0) + 1
			local key = prefix .. "/" .. c.Name .. "#" .. counts[c.Name]
			if c:IsA("BasePart") then
				map[key] = c
			end
			walk(c, key)
		end
	end
	walk(root, "")
	return map
end

local copy = game.ServerScriptService.Server:Clone()
copy.Name = "ServerCopyTmp"
copy.Parent = game.ServerStorage
local ok, err = pcall(function()
	require(copy.MapBuilder).build(Config)
end)
copy:Destroy()

local lines = {}
if ok then
	local u, r = keyed(backup), keyed(workspace.Motel)
	for k, up in pairs(u) do
		local rp = r[k]
		if not rp then
			table.insert(lines, "only in hand-edited map: " .. k)
		else
			local d = up.Position - rp.Position
			local ds = up.Size - rp.Size
			local _, uy = up.CFrame:ToOrientation()
			local _, ry = rp.CFrame:ToOrientation()
			local turn = math.deg(uy - ry)
			if d.Magnitude > 0.05 or ds.Magnitude > 0.05 or math.abs(turn) > 1 then
				table.insert(
					lines,
					string.format(
						"%s  offset/scale (%.2f, %.2f, %.2f)  pos/scale (%.2f, %.2f, %.2f)  size/scale (%.2f, %.2f, %.2f)  turn %.0f",
						k,
						d.X / S,
						d.Y / S,
						d.Z / S,
						up.Position.X / S,
						up.Position.Y / S,
						up.Position.Z / S,
						up.Size.X / S,
						up.Size.Y / S,
						up.Size.Z / S,
						turn
					)
				)
			end
		end
	end
	for k in pairs(r) do
		if not u[k] then
			table.insert(lines, "only in code map (deleted by hand?): " .. k)
		end
	end
end

if workspace:FindFirstChild("Motel") then
	workspace.Motel:Destroy()
end
local restored = backup:Clone()
restored.Name = "Motel"
restored.Parent = workspace

table.sort(lines)
print(if ok then (#lines .. " differences:\n" .. table.concat(lines, "\n")) else ("build error: " .. tostring(err)))
