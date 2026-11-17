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

-- Actions a ProximityPrompt can carry in its "Action" attribute.
Constants.PromptAction = {
	OpenCheckIn = "OpenCheckIn",
	OpenLinen = "OpenLinen",
	CollectTrash = "CollectTrash",
	DumpTrash = "DumpTrash",
	ChangeSheets = "ChangeSheets",
	DeliverTowel = "DeliverTowel",
	RepairAC = "RepairAC",
	ResetBreaker = "ResetBreaker",
	OpenShop = "OpenShop",
}

-- Actions a client may send through the Action RemoteEvent.
Constants.RemoteAction = {
	CheckIn = "CheckIn",
	Ready = "Ready",
	Restart = "Restart",
	RequestState = "RequestState",
	Buy = "Buy",
	TakeSupply = "TakeSupply",
	ReturnSupplies = "ReturnSupplies",
	BackToLobby = "BackToLobby",
}

Constants.Remotes = {
	Folder = "MotelRemotes",
	Action = "Action", -- client -> server
	State = "State", -- server -> client snapshot
	Feedback = "Feedback", -- server -> client toast
	OpenCheckIn = "OpenCheckIn", -- server -> client: show room picker
	OpenShop = "OpenShop", -- server -> client: show the supply shop panel
	OpenLinen = "OpenLinen", -- server -> client: show the linen closet panel
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
