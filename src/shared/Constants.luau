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
	TakeSheet = "TakeSheet",
	TakeTowel = "TakeTowel",
	ReturnSupplies = "ReturnSupplies",
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
}

Constants.Remotes = {
	Folder = "MotelRemotes",
	Action = "Action", -- client -> server
	State = "State", -- server -> client snapshot
	Feedback = "Feedback", -- server -> client toast
	OpenCheckIn = "OpenCheckIn", -- server -> client: show room picker
	OpenShop = "OpenShop", -- server -> client: show the supply shop panel
}

return Constants
