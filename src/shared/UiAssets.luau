--!strict
--[[
	UI assets: icon sheets and sound IDs.

	ICON SHEETS
	  Each sheet is a 1024x1024 transparent PNG, 4 columns x 4 rows of 256px
	  cells. Every symbol in the UI comes from these sheets (no emoji/glyphs);
	  emoji in `fallback` only show while a sheet is empty or still loading.
	    Sheet 1: assets/ui/icon-sheet.png    prompt: assets/ui/ICON_SHEET_PROMPT.md
	    Sheet 2: assets/ui/icon-sheet-2.png  prompt: assets/ui/ICON_SHEET_2_PROMPT.md
	  After uploading a sheet to Roblox, paste its image ID in `iconSheets`.

	SOUNDS
	  Free Creator Store audio from Roblox's own UI pack, ProSoundEffects
	  and APM Music (both licensed for use on Roblox). Replace any ID to
	  change a sound; set an entry to "" to mute it.
]]

local UiAssets = {}

UiAssets.iconSheets = {
	"rbxassetid://85647358432325", -- sheet 1: assets/ui/icon-sheet.png
	"rbxassetid://92991628549421", -- sheet 2: assets/ui/icon-sheet-2.png
	"rbxassetid://91194297042510", -- sheet 3: assets/ui/icon-sheet-3.png (lobby/settings icons; paste "rbxassetid://..." after upload)
}
UiAssets.cellSize = 256 -- pixels per icon cell in a sheet
UiAssets.cellInset = 0 -- shave pixels off each cell edge if neighbours bleed in

-- { sheet, column, row } (1-based, left-to-right, top-to-bottom).
UiAssets.icons = {
	-- Sheet 1
	coin = { 1, 1, 1 },
	sheet = { 1, 2, 1 },
	towel = { 1, 3, 1 },
	trolley = { 1, 4, 1 },
	guests = { 1, 1, 2 },
	hourglass = { 1, 2, 2 },
	hand = { 1, 3, 2 },
	trophy = { 1, 4, 2 },
	sun = { 1, 1, 3 },
	moon = { 1, 2, 3 },
	rain = { 1, 3, 3 },
	lightning = { 1, 4, 3 },
	check = { 1, 1, 4 },
	trash = { 1, 2, 4 },
	wrench = { 1, 3, 4 },
	star = { 1, 4, 4 },
	-- Sheet 2
	arrowDown = { 2, 1, 1 },
	arrowRight = { 2, 2, 1 },
	cross = { 2, 3, 1 },
	warning = { 2, 4, 1 },
	sleep = { 2, 1, 2 },
	broom = { 2, 2, 2 },
	bell = { 2, 3, 2 },
	key = { 2, 4, 2 },
	bed = { 2, 1, 3 },
	door = { 2, 2, 3 },
	snowflake = { 2, 3, 3 },
	plug = { 2, 4, 3 },
	next = { 2, 1, 4 },
	skip = { 2, 2, 4 },
	sparkle = { 2, 3, 4 },
	alarm = { 2, 4, 4 },
	-- Sheet 3 (lobby, settings, ranks)
	gear = { 3, 1, 1 },
	music = { 3, 2, 1 },
	speaker = { 3, 3, 1 },
	home = { 3, 4, 1 },
	crown = { 3, 1, 2 },
	medalSilver = { 3, 2, 2 },
	medalBronze = { 3, 3, 2 },
	profile = { 3, 4, 2 },
	book = { 3, 1, 3 },
	podium = { 3, 2, 3 },
	play = { 3, 3, 3 },
	plus = { 3, 4, 3 },
	minus = { 3, 1, 4 },
	people = { 3, 2, 4 },
	calendar = { 3, 3, 4 },
	gift = { 3, 4, 4 },
}

-- Temporary stand-ins while a sheet is empty or loading.
UiAssets.fallback = {
	coin = "$",
	sheet = "🛏",
	towel = "🧺",
	trolley = "🛒",
	guests = "👥",
	hourglass = "⏳",
	hand = "✋",
	trophy = "🏆",
	sun = "☀",
	moon = "🌙",
	rain = "🌧",
	lightning = "⚡",
	check = "✅",
	trash = "🗑",
	wrench = "🔧",
	star = "★",
	arrowDown = "▼",
	arrowRight = "▶",
	cross = "❌",
	warning = "⚠",
	sleep = "💤",
	broom = "🧹",
	bell = "🛎",
	key = "🔑",
	bed = "🛏",
	door = "🚪",
	snowflake = "❄",
	plug = "🔌",
	next = "▶",
	skip = "⏭",
	sparkle = "✨",
	alarm = "⏰",
	gear = "⚙",
	music = "🎵",
	speaker = "🔊",
	home = "🏠",
	crown = "👑",
	medalSilver = "🥈",
	medalBronze = "🥉",
	profile = "👤",
	book = "📖",
	podium = "🏆",
	play = "▶",
	plus = "+",
	minus = "-",
	people = "👪",
	calendar = "📅",
	gift = "🎁",
}

-- Sheet image + rect for an icon, or nil when its sheet is not uploaded.
-- Pure lookup: safe on the server (world labels) and the client.
function UiAssets.cell(name: string): (string?, Vector2?, Vector2?)
	local def = UiAssets.icons[name]
	if not def then
		return nil, nil, nil
	end
	local image = UiAssets.iconSheets[def[1]]
	if not image or image == "" then
		return nil, nil, nil
	end
	local inset = UiAssets.cellInset
	local size = UiAssets.cellSize - inset * 2
	local offset = Vector2.new((def[2] - 1) * UiAssets.cellSize + inset, (def[3] - 1) * UiAssets.cellSize + inset)
	return image, offset, Vector2.new(size, size)
end

-- Points an ImageLabel at an icon (no fallback; used for world labels).
function UiAssets.applyTo(label: ImageLabel, name: string)
	local image, offset, size = UiAssets.cell(name)
	if image and offset and size then
		label.Image = image
		label.ImageRectOffset = offset
		label.ImageRectSize = size
	else
		label.Image = ""
	end
end

export type SoundDef = { id: string, volume: number }

-- Looping background music per place (Settings scales the volume).
UiAssets.music = {
	lobby = { id = "rbxassetid://9045473167", volume = 0.35 }, -- APM "Jazz Joint (a 60)"
	game = { id = "rbxassetid://9112764573", volume = 0.45 }, -- ProSoundEffects "Crickets Night 3" (ambience loop)
} :: { [string]: SoundDef }

UiAssets.sounds = {
	click = { id = "rbxassetid://15675032796", volume = 0.5 }, -- Roblox_UI_Small_Click
	pop = { id = "rbxassetid://15675055424", volume = 0.5 }, -- Roblox_UI_Cute_Pop
	whoosh = { id = "rbxassetid://15674975792", volume = 0.4 }, -- Roblox_UI_Whoosh_03
	whooshOut = { id = "rbxassetid://15675024286", volume = 0.35 }, -- Roblox_UI_Whoosh_01
	error = { id = "rbxassetid://15675075163", volume = 0.5 }, -- Roblox_UI_Delete
	notify = { id = "rbxassetid://15675085146", volume = 0.45 }, -- Roblox_UI_Indicator
	coin = { id = "rbxassetid://15675059323", volume = 0.6 }, -- Roblox_UI_Bright_Click
	success = { id = "rbxassetid://15675043410", volume = 0.5 }, -- Roblox_UI_Tonal_Stinger
	sweep = { id = "rbxassetid://15675046931", volume = 0.45 }, -- Roblox_UI_Sweep
	alert = { id = "rbxassetid://15675062723", volume = 0.5 }, -- Roblox_UI_Whistle_Low
	paid = { id = "rbxassetid://15675016548", volume = 0.5 }, -- Roblox_UI_Piano_Hello
	power = { id = "rbxassetid://9116276946", volume = 0.6 }, -- ProSoundEffects electrical burst
	fanfare = { id = "rbxassetid://9038514384", volume = 0.6 }, -- APM "Halfway to Rio (sting b)"
	fail = { id = "rbxassetid://9042536620", volume = 0.5 }, -- APM "Feud Warrior - Hit"
} :: { [string]: SoundDef }

return UiAssets
