--!strict
-- Run a Motel: all balancing numbers live here.
-- Durations are in seconds at timeScale = 1. The server multiplies every
-- duration by `timeScale` (or the Workspace attribute "TimeScale" in Studio),
-- so testers can run a full three-night run quickly.

local Config = {}

Config.timeScale = 1
-- In Studio only, Workspace:GetAttribute("TimeScale") overrides timeScale (e.g. 0.25).
Config.allowStudioTimeScaleOverride = true

Config.phases = {
	preparation = 45,
	night = 150,
	closing = 20, -- maximum; ends early when no guest is still staying
	report = 15,
}

Config.economy = {
	startingCash = 50,
	towelTip = 5, -- paid once per towel delivery
}

-- Room types and their nightly rates (shown on the front desk terminal).
export type RoomType = { label: string, rate: number }
local roomTypes: { [string]: RoomType } = {
	Single = { label = "Single", rate = 25 },
	Double = { label = "Double", rate = 30 },
}
Config.roomTypes = roomTypes

-- Rooms in map order (index = room id). number is what players see.
export type RoomDef = { number: number, type: string }
local rooms: { RoomDef } = {
	{ number = 101, type = "Single" },
	{ number = 102, type = "Double" },
	{ number = 103, type = "Single" },
}
Config.rooms = rooms

Config.supplies = {
	startingSheets = 6,
	startingTowels = 4,
	refillCost = 15,
	refillSheets = 3,
	refillTowels = 3,
	trolleyCost = 45,
	baseCarryCapacity = 1,
	trolleyCarryCapacity = 2,
}

-- Supply shop catalog (the shop building next to the motel). Order = display
-- order. Each entry adds stock and/or unlocks the trolley; `icon` is an icon
-- name from UiAssets.icons.
export type ShopItem = {
	id: string,
	name: string,
	desc: string,
	icon: string,
	cost: number,
	sheets: number?,
	towels: number?,
	trolley: boolean?,
}
local shop: { ShopItem } = {
	{ id = "sheets", name = "Sheet Pack", desc = "+4 clean sheets", icon = "sheet", cost = 12, sheets = 4 },
	{ id = "towels", name = "Towel Pack", desc = "+4 fresh towels", icon = "towel", cost = 8, towels = 4 },
	{
		id = "refill",
		name = "Linen Refill",
		desc = "+3 sheets & +3 towels",
		icon = "sparkle",
		cost = Config.supplies.refillCost,
		sheets = Config.supplies.refillSheets,
		towels = Config.supplies.refillTowels,
	},
	{
		id = "trolley",
		name = "Trolley",
		desc = "Whole team carries 2 items",
		icon = "trolley",
		cost = Config.supplies.trolleyCost,
		trolley = true,
	},
}
Config.shop = shop

Config.guests = {
	stayMin = 30,
	stayMax = 40,
	patience = 40, -- seconds a guest waits in the queue before walking out
	rainPatienceMultiplier = 0.85,
	arriveDuration = 9, -- car drives in + guest walks to the queue
	departDuration = 18, -- guest walks back to the car + car leaves (visual only)
	firstArrivalAt = 6, -- seconds into the night
	lastArrivalBuffer = 45, -- last arrival is at least this long before Night ends
	arrivalJitter = 3,
	towelRequestChance = 0.5,
	towelRequestDelayMin = 6,
	towelRequestDelayMax = 14,
}

Config.roomCount = #rooms

-- Front desk terminal: guests, reservations and the cash register.
Config.desk = {
	sessionTimeout = 40, -- seconds without input before the desk is released
	bookingChance = 0.5, -- share of guests with a reservation
	prepaidChance = 0.34, -- of reservations: fully paid online
	partialChance = 0.33, -- of reservations: deposit paid (the rest pay at the motel)
	partialDeposit = 10,
	cardChance = 0.45, -- guest can also pay by card
	shortCashChance = 0.3, -- of card holders: not enough cash on hand
	shortCashAmount = 20,
	denominations = { 1, 5, 10, 20 }, -- change buttons
	maxChangeNotes = 20,
	-- How guests hand over cash: exact, next $10, next $20, a $50 note.
	cashStyles = { "exact", "round10", "twenty", "fifty" },
	names = {
		"Ava Brooks",
		"Leo Park",
		"Mia Lopez",
		"Noah Kim",
		"Zoe Carter",
		"Eli Turner",
		"Ruby Diaz",
		"Max Fischer",
		"Ivy Chen",
		"Sam Patel",
		"Nina Rossi",
		"Owen Hart",
		"Lily Grant",
		"Jack Moreno",
		"Ella Novak",
		"Finn Walsh",
	},
}

-- Uniform scale applied to the whole motel map (buildings, furniture, roads,
-- waypoints, prompt ranges). Bigger = roomier relative to the player.
Config.mapScale = 1.4

-- Player movement (default Roblox is 16); raised because the map is larger.
Config.player = {
	walkSpeed = 20,
}

-- One entry per night. Guest counts and bills are the solo values;
-- co-op scaling is applied from `Config.coop` using the player count at the
-- moment Preparation starts.
export type NightEvent = {
	type: string, -- "ACBreak" | "PowerOutage"
	at: number?, -- ACBreak: seconds into the night
	minAt: number?, -- PowerOutage: earliest time
	queueAtLeast: number?, -- PowerOutage: fire when the queue is this long
	fallbackAt: number?, -- PowerOutage: fire at this time regardless
}
export type NightConfig = {
	guests: number,
	bill: number,
	rain: boolean,
	forecast: string,
	events: { NightEvent },
}

local nights: { NightConfig } = {
	{
		guests = 4,
		bill = 55,
		rain = false,
		forecast = "Quiet night. Learn the routine.",
		events = {},
	},
	{
		guests = 5,
		bill = 70,
		rain = false,
		forecast = "An old AC unit is acting up. Expect a breakdown.",
		events = {
			{ type = "ACBreak", at = 30 },
		},
	},
	{
		guests = 6,
		bill = 85,
		rain = true,
		forecast = "Storm incoming: rain makes guests impatient. Power may fail.",
		events = {
			-- Fires once the queue is busy (>= queueAtLeast) after minAt, or at fallbackAt.
			{ type = "PowerOutage", minAt = 40, queueAtLeast = 2, fallbackAt = 80 },
		},
	},
}
Config.nights = nights

-- Index = number of players (1..4) when Preparation starts.
Config.coop = {
	guestMultiplier = { 1, 1.25, 1.4, 1.55 },
	billMultiplier = { 1, 1.2, 1.35, 1.5 },
	maxPlayers = 4,
}

Config.interaction = {
	promptRange = 9, -- ProximityPrompt MaxActivationDistance
	rangeSlack = 4, -- extra studs the server tolerates for latency
	deskRange = 14, -- max distance from the desk anchor for a check-in request
	shopRange = 16, -- max distance from the shop counter for a purchase
	linenRange = 14, -- max distance from the linen closet to take/return supplies
	remoteCooldown = 0.2,
	repairHoldDuration = 1.5,
	breakerHoldDuration = 1,
}

Config.npc = {
	walkSpeed = 20,
	carSpeed = 50,
}

-- Lobby: room pads 1..4 (capacity = room number).
Config.lobby = {
	padCountdown = 20, -- seconds after the first player steps on a pad
	maxRooms = 4,
	leaderboardRefresh = 60, -- seconds between leaderboard reads
	leaderboardSize = 10,
	partyWait = 15, -- game server waits this long for the whole party to arrive
}

return Config
