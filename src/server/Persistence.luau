--!nonstrict
--[[
	Persistence: saved player stats, shared by the lobby and the game place.

	  BestNights (OrderedDataStore)  userId -> best nights survived (leaderboard)
	  Profiles   (DataStore)         "u_<userId>" -> { best, runs, nights, served }

	All calls are pcall-wrapped. In Studio, DataStores need
	Game Settings -> Security -> "Enable Studio Access to API Services";
	without it the functions return nil / false and the UI shows "offline".
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local Persistence = {}

local ordered, profiles = nil, nil
local function stores()
	if ordered == nil then
		local ok1, o = pcall(function()
			return DataStoreService:GetOrderedDataStore(Constants.Stores.BestNights)
		end)
		local ok2, p = pcall(function()
			return DataStoreService:GetDataStore(Constants.Stores.Profiles)
		end)
		ordered = if ok1 then o else false
		profiles = if ok2 then p else false
	end
	return ordered or nil, profiles or nil
end

local function emptyProfile()
	return { best = 0, runs = 0, nights = 0, served = 0 }
end

-- Returns the saved profile (or a blank one) and whether the read worked.
function Persistence.loadProfile(userId: number): ({ [string]: number }, boolean)
	local _, store = stores()
	if not store then
		return emptyProfile(), false
	end
	local ok, data = pcall(function()
		return store:GetAsync("u_" .. userId)
	end)
	if not ok then
		return emptyProfile(), false
	end
	local profile = emptyProfile()
	if typeof(data) == "table" then
		for k in pairs(profile) do
			if typeof(data[k]) == "number" then
				profile[k] = data[k]
			end
		end
	end
	return profile, true
end

--[[
	Records one finished run for a player. Returns (profile, isNewRecord, ok).
	Updates the profile and, when the best improved, the leaderboard entry.
]]
function Persistence.recordRun(userId: number, nightsSurvived: number, served: number)
	local ord, store = stores()
	if not store then
		return emptyProfile(), false, false
	end
	local newRecord = false
	local result = emptyProfile()
	local ok = pcall(function()
		store:UpdateAsync("u_" .. userId, function(old)
			local p = emptyProfile()
			if typeof(old) == "table" then
				for k in pairs(p) do
					if typeof(old[k]) == "number" then
						p[k] = old[k]
					end
				end
			end
			p.runs += 1
			p.nights += nightsSurvived
			p.served += served
			newRecord = nightsSurvived > p.best
			p.best = math.max(p.best, nightsSurvived)
			result = p
			return p
		end)
	end)
	if ok and newRecord and ord then
		pcall(function()
			ord:UpdateAsync(tostring(userId), function(old)
				return math.max(tonumber(old) or 0, nightsSurvived)
			end)
		end)
	end
	return result, ok and newRecord, ok
end

local nameCache = {}
local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and name then name else ("Player " .. userId)
	nameCache[userId] = result
	return result
end

-- Top entries: { { userId, name, nights } }, or nil when offline.
function Persistence.topNights(count: number)
	local ord = stores()
	if not ord then
		return nil
	end
	local ok, pages = pcall(function()
		return ord:GetSortedAsync(false, count)
	end)
	if not ok or not pages then
		return nil
	end
	local list = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		local userId = tonumber(entry.key)
		if userId and entry.value > 0 then
			table.insert(list, { userId = userId, name = nameOf(userId), nights = entry.value })
		end
	end
	return list
end

return Persistence
