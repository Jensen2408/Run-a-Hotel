--!nonstrict
-- CLI tests for MotelCore. Run from the repo root:
--   luau tests/core.spec.luau
-- These exercise the pure server logic (transactions, races, bill, restart).
-- They do not replace playtesting in Studio.

local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local MotelCore = require("../src/server/MotelCore")

local P = Constants.Phase
local passed, failed = 0, 0

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("PASS  " .. name)
	else
		failed += 1
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end

local function expect(cond, msg)
	if not cond then
		error(msg or "expectation failed", 2)
	end
end

local function eq(a, b, msg)
	if a ~= b then
		error(("%s: expected %s, got %s"):format(msg or "eq", tostring(b), tostring(a)), 2)
	end
end

-- Deterministic random: midpoint (stay 35s, no towel requests, no jitter).
local function midRandom(a, b)
	return (a + b) / 2
end

-- Random that always triggers towel requests (returns the minimum).
local function lowRandom(a, b)
	return a
end

local function newCore(opts)
	opts = opts or {}
	return MotelCore.new(Config, Constants, {
		now = 0,
		random = opts.random or midRandom,
		playerCount = opts.playerCount or 1,
	})
end

-- Advance simulated time in small steps.
local function run(core, from, to, step, onTick)
	local t = from
	while t < to do
		t += step or 0.5
		core:update(t)
		if onTick then
			onTick(t)
		end
	end
	return t
end

-- Moves straight to Night and waits until `n` guests are queued.
local function nightWithQueue(core, n)
	core:setReady("A")
	local t = run(core, 0, 0.5)
	eq(core.phase, P.Night, "phase after ready")
	while #core.queue < n do
		t += 0.5
		core:update(t)
		expect(t < 200, "queue never filled")
	end
	return t
end

-- Fully cleans a room through the normal player actions.
local function cleanRoom(core, pid, roomId)
	local room = core.rooms[roomId]
	if room.trash then
		assert(core:collectTrash(pid, roomId))
		assert(core:dumpTrash(pid))
	end
	if room.sheetsDirty then
		if core.stock.Sheet <= 0 then
			assert(core:buyRefill(pid))
		end
		assert(core:takeSupply(pid, "Sheet"))
		assert(core:changeSheets(pid, roomId))
	end
	if room.acBroken then
		assert(core:repairAC(pid, roomId))
	end
end

------------------------------------------------------------------------

test("M1: single-room cycle (arrive, check in, checkout, clean, reuse)", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	eq(core.cash, 50, "starting cash")
	local ok, msg = core:checkIn("A", 1, t)
	expect(ok, msg)
	eq(core.cash, 75, "cash after rent")
	eq(core.rooms[1].occupant ~= nil, true, "occupied")
	-- Stay is 35s with midRandom.
	t = run(core, t, t + 36)
	local room = core.rooms[1]
	eq(room.occupant, nil, "checked out")
	expect(room.trash and room.sheetsDirty, "checkout leaves trash and dirty sheets")
	expect(not core:isRoomReady(room), "not ready while dirty")
	cleanRoom(core, "A", 1)
	expect(core:isRoomReady(room), "ready after cleaning")
	eq(core.stock.Sheet, 5, "one sheet used")
	-- Second guest uses the same room.
	while #core.queue < 1 do
		t += 0.5
		core:update(t)
	end
	ok, msg = core:checkIn("A", 1, t)
	expect(ok, msg)
	eq(core.cash, 100, "second rent")
end)

test("M1: replaying a check-in is counted once", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	assert(core:checkIn("A", 1, t))
	local ok = core:checkIn("A", 1, t)
	eq(ok, false, "replay rejected")
	eq(core.cash, 75, "rent paid once")
	eq(core.nightStats.rent, 25, "rent stat once")
end)

test("M2: two players pick the same room at once", function()
	local core = newCore()
	local t = nightWithQueue(core, 2)
	local okA = core:checkIn("A", 2, t)
	local okB = core:checkIn("B", 2, t)
	expect(okA and not okB, "only one check-in for room 2")
	eq(core.cash, 75, "single rent")
	eq(#core.queue, 1, "second guest still queued")
end)

test("M2: two players grab the last sheet", function()
	local core = newCore()
	core.stock.Sheet = 1
	local okA = core:takeSupply("A", "Sheet")
	local okB = core:takeSupply("B", "Sheet")
	expect(okA and not okB, "only one gets the sheet")
	eq(core.stock.Sheet, 0, "stock not negative")
end)

test("M2: carry capacity 1, trolley raises to 2", function()
	local core = newCore()
	assert(core:takeSupply("A", "Sheet"))
	eq(core:takeSupply("A", "Towel"), false, "hands full")
	core.cash = 100
	assert(core:buyTrolley("A"))
	eq(core.cash, 55, "trolley cost")
	assert(core:takeSupply("A", "Towel"))
	eq(core:buyTrolley("A"), false, "trolley once")
end)

test("M2: towel tip paid exactly once", function()
	local core = newCore({ random = lowRandom })
	local t = nightWithQueue(core, 1)
	assert(core:checkIn("A", 1, t))
	t = run(core, t, t + 7) -- towel delay min 6s
	expect(core.rooms[1].towelRequest, "towel requested")
	assert(core:takeSupply("A", "Towel"))
	assert(core:takeSupply("B", "Towel"))
	local cash = core.cash
	local okA = core:deliverTowel("A", 1)
	local okB = core:deliverTowel("B", 1)
	expect(okA and not okB, "one delivery accepted")
	eq(core.cash, cash + 5, "tip once")
	eq(#core.carries.B, 1, "B keeps the towel")
end)

test("M2: FIFO queue and patience walkout", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	local firstId = core.queue[1]
	t = run(core, t, t + 41)
	eq(core.guests[firstId].state, "Departed", "walked out")
	eq(core.nightStats.walkouts >= 1, true, "walkout counted")
end)

test("M2: refill purchase", function()
	local core = newCore()
	assert(core:buyRefill("A"))
	eq(core.cash, 35, "cash")
	eq(core.stock.Sheet, 9, "sheets")
	eq(core.stock.Towel, 7, "towels")
	core.cash = 10
	eq(core:buyRefill("A"), false, "cannot afford")
end)

test("M2: cash exactly equal to the bill passes", function()
	local core = newCore()
	core:setReady("A")
	run(core, 0, 0.5)
	core.cash = core.plan.bill
	core:enterClosing(1)
	core:update(1.5) -- no one staying -> Report
	eq(core.phase, P.Report, "report")
	expect(core.lastReport.passed, "passed")
	eq(core.cash, 0, "cash zero")
	eq(core.nightsSurvived, 1, "survived")
	-- Re-entering report logic must not charge again.
	core:enterReport(2)
	eq(core.cash, 0, "bill charged once")
	eq(core.nightsSurvived, 1, "not double counted")
end)

test("M2: cash below the bill ends the run with shortfall", function()
	local core = newCore()
	core:setReady("A")
	run(core, 0, 0.5)
	core.cash = 40
	core:enterClosing(1)
	core:update(1.5)
	eq(core.lastReport.passed, false, "failed")
	eq(core.lastReport.shortfall, 15, "shortfall")
	eq(core.cash, 40, "no charge on failure")
	run(core, 1.5, 20)
	eq(core.phase, P.RunEnded, "run ended")
	eq(core.nightsSurvived, 0, "score 0")
end)

test("M2: restart with pending guests clears everything", function()
	local core = newCore()
	local t = nightWithQueue(core, 2)
	assert(core:checkIn("A", 1, t))
	assert(core:takeSupply("A", "Sheet"))
	eq(core:restart("A", t), false, "restart blocked mid-run")
	core.phase = P.RunEnded
	local oldRun = core.runId
	assert(core:restart("A", t))
	eq(core.runId, oldRun + 1, "new run id")
	eq(next(core.guests), nil, "no guests")
	eq(#core.queue, 0, "empty queue")
	eq(core.phase, P.Preparation, "preparation")
	eq(core.cash, 50, "cash reset")
	eq(core.rooms[1].occupant, nil, "room free")
	eq(#core:getCarry("A"), 0, "carry cleared")
end)

test("M2: closing records unserved once and evicts stayers", function()
	local core = newCore()
	local t = nightWithQueue(core, 2)
	assert(core:checkIn("A", 1, t))
	core:enterClosing(t)
	eq(core.nightStats.unserved, 1, "one unserved")
	eq(core:checkIn("A", 2, t), false, "no check-in while closing")
	-- Closing again must not double count.
	core:enterClosing(t)
	eq(core.nightStats.unserved, 1, "still one")
	core:update(t + 21)
	eq(core.phase, P.Report, "report after closing")
	eq(core.nightStats.evicted, 1, "evicted")
	expect(core.rooms[1].trash and core.rooms[1].sheetsDirty, "evicted room dirty")
end)

test("M3: broken AC blocks renting until repaired", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	core.rooms[1].acBroken = true
	eq(core:checkIn("A", 1, t), false, "blocked")
	assert(core:repairAC("A", 1))
	assert(core:checkIn("A", 1, t))
end)

test("M3: power outage blocks check-in, housekeeping continues", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	core.power = false
	eq(core:checkIn("A", 1, t), false, "blocked")
	assert(core:takeSupply("A", "Sheet"))
	assert(core:resetBreaker("A"))
	assert(core:checkIn("A", 1, t))
end)

test("M3: player leaving returns clean supplies", function()
	local core = newCore()
	core.trolley = true
	assert(core:takeSupply("A", "Sheet"))
	assert(core:takeSupply("A", "Towel"))
	core:playerLeft("A")
	eq(core.stock.Sheet, 6, "sheet returned")
	eq(core.stock.Towel, 4, "towel returned")
end)

test("M3: co-op scaling uses player count at Preparation start", function()
	local core = newCore({ playerCount = 1 })
	eq(core.plan.guestCount, 4, "solo night 1")
	core:setPlayerCount(4) -- mid-phase change affects the next plan only
	eq(core.plan.guestCount, 4, "unchanged this night")
	local plan = core:buildNightPlan(3, 4)
	eq(plan.guestCount, 9, "4p night 3 guests")
	eq(plan.bill, 128, "4p night 3 bill")
	local last = Config.phases.night - Config.guests.lastArrivalBuffer
	for _, a in ipairs(plan.arrivals) do
		expect(a <= last, "arrival before buffer")
	end
end)

test("M3: night events (AC on night 2, power on night 3)", function()
	local core = newCore()
	core.night = 2
	core:enterPreparation(0)
	core:setReady("A")
	run(core, 0, 32)
	local broken = 0
	for _, r in ipairs(core.rooms) do
		if r.acBroken then
			broken += 1
		end
	end
	eq(broken, 1, "one AC broke")

	core = newCore()
	core.night = 3
	core:enterPreparation(0)
	core:setReady("A")
	run(core, 0, 81)
	eq(core.power, false, "power failed by fallback")
	expect(core.rain, "rain on night 3")
end)

-- Simulates players doing every job through the normal actions.
local function simulateRun(playerCount, competent)
	local core = newCore({ playerCount = playerCount, random = midRandom })
	local t = 0
	local guard = 0
	while core.phase ~= P.RunEnded do
		guard += 1
		assert(guard < 20000, "simulation did not finish")
		t += 0.5
		core:update(t)
		if competent then
			if core.phase == P.Preparation then
				for _, room in ipairs(core.rooms) do
					cleanRoom(core, "A", room.id)
				end
				if core.stock.Sheet < 4 and core.cash >= Config.supplies.refillCost then
					core:buyRefill("A")
				end
				core:setReady("A")
			elseif core.phase == P.Night or core.phase == P.Closing then
				if not core.power then
					core:resetBreaker("A")
				end
				for _, room in ipairs(core.rooms) do
					if not room.occupant then
						cleanRoom(core, "A", room.id)
					elseif room.towelRequest then
						if core:takeSupply("A", "Towel") then
							core:deliverTowel("A", room.id)
						end
					end
				end
				if core.phase == P.Night and #core.queue > 0 then
					for _, room in ipairs(core.rooms) do
						if core:isRoomReady(room) then
							core:checkIn("A", room.id, t)
							break
						end
					end
				end
			end
		end
	end
	return core
end

test("M3: competent solo team completes the 3-night prototype", function()
	local core = simulateRun(1, true)
	expect(core.complete, "prototype complete")
	eq(core.nightsSurvived, 3, "3 nights")
	print(("      final cash $%d, served %d, walkouts %d"):format(core.cash, core.totals.served, core.totals.walkouts))
end)

test("M3: competent 4-player schedule is completable", function()
	local core = simulateRun(4, true)
	expect(core.complete, "prototype complete")
	print(("      final cash $%d, served %d, walkouts %d"):format(core.cash, core.totals.served, core.totals.walkouts))
end)

test("M3: idle team fails night 1 with score 0", function()
	local core = simulateRun(1, false)
	eq(core.complete, false, "not complete")
	eq(core.nightsSurvived, 0, "score")
	eq(core.lastReport.shortfall, 5, "shortfall $5")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("tests failed")
end
