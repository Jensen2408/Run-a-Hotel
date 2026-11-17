--!nonstrict
-- UI sound player. Sounds live in SoundService on this client only and are
-- played with PlayLocalSound. IDs come from UiAssets.sounds.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local UiAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiAssets"))

local Sfx = {}
Sfx.__index = Sfx

local MIN_GAP = 0.06 -- seconds between two plays of the same cue

function Sfx.new()
	local self = setmetatable({}, Sfx)
	self.sounds = {}
	self.lastPlayed = {}
	local folder = Instance.new("Folder")
	folder.Name = "MotelUiSounds"
	folder.Parent = SoundService
	local preload = {}
	for name, def in pairs(UiAssets.sounds) do
		if def.id ~= "" then
			local s = Instance.new("Sound")
			s.Name = name
			s.SoundId = def.id
			s.Volume = def.volume
			s.Parent = folder
			self.sounds[name] = s
			table.insert(preload, s)
		end
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(preload)
		end)
	end)
	return self
end

function Sfx:play(name: string)
	local s = self.sounds[name]
	if not s then
		return
	end
	local now = os.clock()
	if self.lastPlayed[name] and now - self.lastPlayed[name] < MIN_GAP then
		return
	end
	self.lastPlayed[name] = now
	SoundService:PlayLocalSound(s)
end

return Sfx
