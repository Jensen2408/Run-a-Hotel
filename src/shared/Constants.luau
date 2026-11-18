--!strict
-- Names shared by server and client. Pure table (no Roblox APIs) so CLI tests can load it.

local Constants = {}

Constants.Phase = {
	Preparation = "Preparation",
	Night = "Night",
	Closing = "Closing",
	Report = "Report",
	RunEnded = "RunEnded",
}

Constants.GuestState = {
	Arriving = "Arriving",
	Queued = "Queued",
	Staying = "Staying",
	Departed = "Departed",
}

Constants.Item = {
	Sheet = "Sheet",
	Towel = "Towel",
	Trash = "Trash",
}
-- A carried dish is the item "Dish:<recipeId>", e.g. "Dish:burger".
Constants.DishPrefix = "Dish:"

-- Actions a ProximityPrompt can carry in its "Action" attribute.
Constants.PromptAction = {
	OpenCheckIn = "OpenCheckIn",
	OpenLinen = "OpenLinen",
	CollectTrash = "CollectTrash",
	DumpTrash = "DumpTrash",
	ChangeSheets = "ChangeSheets",
	Deliver = "Deliver", -- room door: towel or meal, whichever the room asked for
	OpenKitchen = "OpenKitchen",
	RepairAC = "RepairAC",
	ResetBreaker = "ResetBreaker",
	OpenShop = "OpenShop",
}

-- Actions a client may send through the Action RemoteEvent.
Constants.RemoteAction = {
	DeskClose = "DeskClose",
	DeskMode = "DeskMode", -- { mode = "Booking" | "WalkIn" }
	DeskVerify = "DeskVerify", -- { code = "2846" }
	DeskRoom = "DeskRoom", -- { roomId }
	DeskMethod = "DeskMethod", -- { method = "Cash" | "Card" }
	DeskBack = "DeskBack",
	DeskConfirm = "DeskConfirm", -- { txId, change = { 20, 5 } }
	Ready = "Ready",
	Restart = "Restart",
	RequestState = "RequestState",
	Buy = "Buy",
	TakeSupply = "TakeSupply",
	ReturnSupplies = "ReturnSupplies",
	BackToLobby = "BackToLobby",
	Cook = "Cook", -- { slot, recipe }
	CollectDish = "CollectDish", -- { slot }
	DiscardDish = "DiscardDish", -- { slot }
	SetRole = "SetRole", -- { role }
	FinishFix = "FinishFix", -- { fix = "AC" | "Breaker" | "Sheets", roomId? }: minigame won
	CancelFix = "CancelFix", -- repair minigame closed
	ForwardCall = "ForwardCall", -- { roomId, call = "Meal" | "Towel" | "AC" }: front desk phone
}

-- Front desk terminal.
Constants.DeskStep = {
	Start = "Start", -- choose Booking or Walk-in
	Code = "Code", -- enter the reservation code
	Room = "Room", -- pick a ready room
	Payment = "Payment", -- take the money, give change, issue the key
}
Constants.GuestKind = { Booking = "Booking", WalkIn = "WalkIn" }
Constants.Payment = { Prepaid = "Prepaid", PayAtMotel = "PayAtMotel", Partial = "Partial" }
Constants.PayMethod = { Cash = "Cash", Card = "Card", Online = "Online" }

Constants.Remotes = {
	Folder = "MotelRemotes",
	Action = "Action", -- client -> server
	State = "State", -- server -> client snapshot
	Feedback = "Feedback", -- server -> client toast
	OpenCheckIn = "OpenCheckIn", -- server -> client: open the front desk terminal
	OpenShop = "OpenShop", -- server -> client: show the supply shop panel
	OpenLinen = "OpenLinen", -- server -> client: show the linen closet panel
	OpenKitchen = "OpenKitchen", -- server -> client: show the kitchen panel
	OpenFix = "OpenFix", -- server -> client: start a repair minigame { fix, roomId?, easy }
}

-- Lobby place remotes (ReplicatedStorage.LobbyRemotes).
Constants.LobbyRemotes = {
	Folder = "LobbyRemotes",
	Rooms = "Rooms", -- server -> client: pad/room state
	Profile = "Profile", -- server -> client: the player's saved stats
	Leave = "Leave", -- client -> server: leave the current room pad
	Notice = "Notice", -- server -> client: toast message
}

-- DataStore names (shared by lobby and game).
Constants.Stores = {
	BestNights = "BestNights_v1", -- OrderedDataStore: userId -> best nights survived
	Profiles = "Profiles_v1", -- DataStore: "u_<userId>" -> { best, runs, nights, served }
}

return Constants
