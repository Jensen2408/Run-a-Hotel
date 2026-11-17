--!strict
--[[
	UI assets: icon sheet and sound IDs.

	ICON SHEET
	  1024x1024 PNG, transparent, 4 columns x 4 rows of 256px cells.
	  Prompt to generate it: assets/ui/ICON_SHEET_PROMPT.md
	  After uploading it to Roblox, paste the image ID below, e.g.
	    UiAssets.iconSheet = "rbxassetid://1234567890"
	  While it is empty the HUD falls back to emoji/text icons.

	SOUNDS
	  Free Creator Store audio from Roblox's own UI pack, ProSoundEffects
	  and APM Music (both licensed for use on Roblox). Replace any ID to
	  change a sound; set an entry to "" to mute it.
]]

local UiAssets = {}

UiAssets.iconSheet = "" -- "rbxassetid://..." once uploaded
UiAssets.cellSize = 256 -- pixels per icon cell in the sheet
UiAssets.cellInset = 0 -- shave pixels off each cell edge if neighbours bleed in

-- { column, row } in the 4x4 sheet (1-based, left-to-right, top-to-bottom).
UiAssets.icons = {
	coin = { 1, 1 },
	sheet = { 2, 1 },
	towel = { 3, 1 },
	trolley = { 4, 1 },
	guests = { 1, 2 },
	hourglass = { 2, 2 },
	hand = { 3, 2 },
	trophy = { 4, 2 },
	sun = { 1, 3 },
	moon = { 2, 3 },
	rain = { 3, 3 },
	lightning = { 4, 3 },
	check = { 1, 4 },
	trash = { 2, 4 },
	wrench = { 3, 4 },
	star = { 4, 4 },
}

-- Used until iconSheet is set.
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
}

export type SoundDef = { id: string, volume: number }

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
