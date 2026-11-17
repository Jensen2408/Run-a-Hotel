--!nonstrict
--[[
	Settings: background music + a gear button (top right) that opens a
	panel with music and SFX volume (10 steps each, -/+ buttons).

	Used by both the lobby and the game client:
	  local settings = Settings.new(playerGui, sfx, "lobby")  -- or "game"

	Volumes are kept for the session as player attributes (MusicVolume,
	SfxVolume, 0..1) so both scripts in a place share them.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local UiAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiAssets"))
local UiKit = require(script.Parent:WaitForChild("UiKit"))
local Icons = require(script.Parent:WaitForChild("Icons"))

local Settings = {}
Settings.__index = Settings

local STEPS = 10

function Settings.new(playerGui: PlayerGui, sfx, track: string)
	local self = setmetatable({}, Settings)
	self.sfx = sfx
	self.player = Players.LocalPlayer
	local function attr(name, default)
		local v = self.player:GetAttribute(name)
		return if typeof(v) == "number" then v else default
	end
	self.music = attr("MusicVolume", 0.7)
	self.effects = attr("SfxVolume", 1)

	-- Music.
	local def = UiAssets.music[track]
	if def and def.id ~= "" then
		local s = Instance.new("Sound")
		s.Name = "MotelMusic"
		s.SoundId = def.id
		s.Looped = true
		s.Parent = SoundService
		self.musicSound = s
		self.musicBase = def.volume
		s:Play()
	end

	-- UI. Full-screen gui so the gear can sit in Roblox's topbar row.
	local screen = UiKit.screen(playerGui, "MotelSettings", 20, true)
	self.screen = screen
	-- Gear: just the icon (no button background), hover/press scale.
	local GEAR = 50
	local holder = UiKit.make("Frame", {
		Name = "SettingsButton",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(GEAR, GEAR),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = screen.root,
	})
	local gearBody = UiKit.make("TextButton", {
		Name = "Body",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	Icons.create("gear", { Parent = gearBody, Size = UDim2.fromScale(1, 1) })
	UiKit.pressable(holder, gearBody, function()
		self:render()
		screen:open(self.panel)
	end)
	self.gear = holder
	local function place()
		local s = screen.uiScale.Scale
		local inset = GuiService.TopbarInset
		local cam = workspace.CurrentCamera
		local vpX = if cam then cam.ViewportSize.X else 1280
		local centerY = math.max(inset.Max.Y - 24, 22)
		holder.Position = UDim2.fromOffset((math.min(inset.Max.X, vpX) - 12) / s, centerY / s)
	end
	place()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(place) -- after the screen rescales
		end)
	end

	local panel, body = screen:modal("Settings", Vector2.new(480, 280), "SETTINGS", "gear")
	self.panel = panel
	self.rows = {}
	local function row(key, iconName, title, y)
		local strip = UiKit.make("Frame", {
			BackgroundColor3 = UiKit.WHITE,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -40, 0, 80),
			Position = UDim2.fromOffset(20, y),
			Parent = body,
		})
		UiKit.corner(strip, UDim.new(0, 14))
		Icons.create(iconName, {
			Parent = strip,
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.new(0, 12, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
		})
		UiKit.label({
			Parent = strip,
			Size = UDim2.fromOffset(120, 30),
			Position = UDim2.fromOffset(64, 8),
			TextSize = 20,
			TextColor3 = UiKit.TEXT_DARK,
			Stroke = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = title,
		})
		local pct = UiKit.label({
			Parent = strip,
			Size = UDim2.fromOffset(70, 30),
			Position = UDim2.fromOffset(184, 8),
			TextSize = 20,
			TextColor3 = UiKit.TEXT_DARK,
			Stroke = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		})
		local segs = {}
		for i = 1, STEPS do
			local seg = UiKit.make("Frame", {
				BackgroundColor3 = UiKit.WHITE,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(18, 18),
				Position = UDim2.fromOffset(64 + (i - 1) * 22, 46),
				Parent = strip,
			})
			UiKit.corner(seg, UDim.new(0, 5))
			UiKit.outline(seg, 2)
			segs[i] = { frame = seg, grad = UiKit.gradient(seg, UiKit.GREY) }
		end
		UiKit.button(strip, "Minus", UDim2.fromOffset(48, 48), UDim2.new(1, -116, 0.5, -24), UiKit.RED, "", function()
			self:change(key, -1)
		end, "minus")
		UiKit.button(strip, "Plus", UDim2.fromOffset(48, 48), UDim2.new(1, -60, 0.5, -24), UiKit.GREEN, "", function()
			self:change(key, 1)
		end, "plus")
		self.rows[key] = { pct = pct, segs = segs }
	end
	row("music", "music", "MUSIC", 40)
	row("effects", "speaker", "SOUND FX", 134)

	self:apply()
	return self
end

function Settings:change(key: string, dir: number)
	local v = math.clamp(math.floor(self[key] * STEPS + 0.5) + dir, 0, STEPS) / STEPS
	self[key] = v
	self:apply()
	self:render()
	if key == "effects" then
		UiKit.play("pop")
	end
end

function Settings:apply()
	self.player:SetAttribute("MusicVolume", self.music)
	self.player:SetAttribute("SfxVolume", self.effects)
	if self.musicSound then
		self.musicSound.Volume = self.musicBase * self.music
	end
	if self.sfx and self.sfx.setScale then
		self.sfx:setScale(self.effects)
	end
end

function Settings:render()
	for key, r in pairs(self.rows) do
		local level = math.floor(self[key] * STEPS + 0.5)
		r.pct.Text = ("%d%%"):format(level * 10)
		for i, seg in ipairs(r.segs) do
			UiKit.setColors(
				seg.grad,
				if i <= level then (if key == "music" then UiKit.PURPLE else UiKit.BLUE) else UiKit.GREY
			)
		end
	end
end

return Settings
