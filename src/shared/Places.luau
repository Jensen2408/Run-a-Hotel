--!strict
--[[
	Place IDs of the "Run A Hotel" universe.

	  lobby  start place: leaderboard, profile, how-to-play, room pads 1-4
	  game   the motel itself; groups are teleported here into a reserved server

	Fill `game` with the ID of the Game place once it exists (Creator Hub ->
	Run A Hotel -> Places -> Add place, or Studio Asset Manager -> Places).
	While it is 0, the lobby pads only simulate the launch.
]]

local Places = {}

Places.lobby = 138304056640374
Places.game = 0 -- paste the Game place ID here

return Places
