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

-- Serves the front guest through the whole desk flow (open, mode, code,
-- room, payment with exact change or card), then releases the desk.
local txSeq = 0
local function serve(core, pid, roomId, t)
	local ok, err = core:deskOpen(pid, t)
	if not ok then
		return false, err
	end
	local function finish(...)
		core:deskRelease(pid)
		return ...
	end
	local g = core:deskGuest()
	if not g then
		return finish(false, "No guest is waiting at the desk.")
	end
	ok, err = core:deskChoose(pid, g.profile.kind, t)
	if not ok then
		return finish(false, err)
	end
	if g.profile.booking then
		ok, err = core:deskVerify(pid, g.profile.booking.code, t)
		if not ok then
			return finish(false, err)
		end
	end
	ok, err = core:deskSelectRoom(pid, roomId, t)
	if not ok then
		return finish(false, err)
	end
	local v = core:deskView(pid)
	local change = {}
	if v.method == "Cash" then
		if v.given < v.due then
			if table.find(g.profile.methods, "Card") then
				core:deskSetMethod(pid, "Card", t)
			end
		else
			local left = v.given - v.due
			local notes = Config.desk.denominations
			for i = #notes, 1, -1 do
				while left >= notes[i] do
					table.insert(change, notes[i])
					left -= notes[i]
				end
			end
		end
	end
	txSeq += 1
	return finish(core:deskConfirm(pid, { txId = txSeq, change = change }, t))
end

------------------------------------------------------------------------

test("M1: single-room cycle (arrive, check in, checkout, clean, reuse)", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	eq(core.cash, 50, "starting cash")
	local ok, msg = serve(core, "A", 1, t)
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
	ok, msg = serve(core, "A", 1, t)
	expect(ok, msg)
	eq(core.cash, 100, "second rent")
end)

test("M1: replaying a check-in is counted once", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	assert(serve(core, "A", 1, t))
	local ok = serve(core, "A", 1, t)
	eq(ok, false, "replay rejected")
	eq(core.cash, 75, "rent paid once")
	eq(core.nightStats.rent, 25, "rent stat once")
end)

test("M2: two players use the same room one after another", function()
	local core = newCore()
	local t = nightWithQueue(core, 2)
	local okA = serve(core, "A", 2, t)
	local okB = serve(core, "B", 2, t)
	expect(okA and not okB, "only one check-in for room 2")
	eq(core.cash, 80, "single rent (Double $30)")
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
	local core = newCore({ playerCount = 2 }) -- solo players get the housekeeper perk
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
	assert(serve(core, "A", 1, t))
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

test("Shop: catalog items add stock, trolley once, unknown item rejected", function()
	local core = newCore()
	core.cash = 100
	assert(core:buyItem("A", "sheets"))
	eq(core.stock.Sheet, 10, "sheet pack +4")
	assert(core:buyItem("A", "towels"))
	eq(core.stock.Towel, 8, "towel pack +4")
	eq(core.cash, 80, "12 + 8 spent")
	eq(core.nightStats.purchases, 20, "purchases tracked")
	assert(core:buyItem("A", "trolley"))
	eq(core:buyItem("B", "trolley"), false, "trolley once")
	eq(core:buyItem("A", "nope"), false, "unknown item")
	eq(core.cash, 35, "trolley 45")
	core.cash = 5
	eq(core:buyItem("A", "sheets"), false, "cannot afford")
	eq(core.stock.Sheet, 10, "no stock change when broke")
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
	assert(serve(core, "A", 1, t))
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
	assert(serve(core, "A", 1, t))
	core:enterClosing(t)
	eq(core.nightStats.unserved, 1, "one unserved")
	eq(serve(core, "A", 2, t), false, "no check-in while closing")
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
	eq(serve(core, "A", 1, t), false, "blocked")
	assert(core:repairAC("A", 1))
	assert(serve(core, "A", 1, t))
end)

test("M3: power outage blocks check-in, housekeeping continues", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	core.power = false
	eq(serve(core, "A", 1, t), false, "blocked")
	assert(core:takeSupply("A", "Sheet"))
	assert(core:resetBreaker("A"))
	assert(serve(core, "A", 1, t))
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

------------------------------------------------------------------------
-- Front desk terminal
------------------------------------------------------------------------

-- Gives the guest at the front a known profile (and a live reservation).
local function setFront(core, profile)
	local g = core.guests[core.queue[1]]
	profile.index = profile.index or 900 + g.id
	profile.name = profile.name or "Test Guest"
	profile.methods = profile.methods or { "Cash" }
	profile.cashStyle = profile.cashStyle or "exact"
	profile.kind = if profile.booking then "Booking" else "WalkIn"
	g.profile = profile
	if profile.booking then
		local b = profile.booking
		b.night = core.night
		core.reservations[b.code] = {
			code = b.code,
			night = core.night,
			guestIndex = profile.index,
			name = profile.name,
			roomType = b.roomType,
			total = b.total,
			paid = b.paid,
			payment = b.payment,
			used = false,
		}
	end
	return g
end

local function booking(code, roomType, total, paid, payment)
	return { code = code, roomType = roomType, total = total, paid = paid, payment = payment }
end

test("Desk: walk-in cash, $25 due, guest gives $50, change 20+5 adds $25", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	setFront(core, { cashStyle = "fifty" })
	assert(core:deskOpen("A", t))
	assert(core:deskChoose("A", "WalkIn", t))
	assert(core:deskSelectRoom("A", 1, t))
	local v = core:deskView("A")
	eq(v.due, 25, "due")
	eq(v.given, 50, "guest gives")
	eq(core.rooms[1].occupant, nil, "room not taken before confirm")
	local ok, msg = core:deskConfirm("A", { txId = 1, change = { 20, 5 } }, t)
	expect(ok, msg)
	eq(core.cash, 75, "+25")
	eq(core.nightStats.rent, 25, "rent stat")
	expect(core.rooms[1].occupant ~= nil, "guest in room")
	eq(#core.queue, 0, "queue empty")
end)

test("Desk: wrong change is rejected, nothing changes, then corrected", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	setFront(core, { cashStyle = "fifty" })
	assert(core:deskOpen("A", t))
	assert(core:deskChoose("A", "WalkIn", t))
	assert(core:deskSelectRoom("A", 1, t))
	local ok, msg = core:deskConfirm("A", { txId = 1, change = { 20 } }, t)
	eq(ok, false, "wrong change")
	eq(msg, "Change is incorrect", "message")
	eq(core.cash, 50, "cash unchanged")
	eq(core.rooms[1].occupant, nil, "room unchanged")
	eq(#core.queue, 1, "guest still waiting")
	eq(core:deskView("A").step, "Payment", "stays on payment")
	ok, msg = core:deskConfirm("A", { txId = 2, change = { 20, 5 } }, t)
	expect(ok, msg)
	eq(core.cash, 75, "+25 after correction")
end)

test("Desk: exact cash with no change", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	setFront(core, { cashStyle = "exact" })
	assert(core:deskOpen("A", t))
	assert(core:deskChoose("A", "WalkIn", t))
	assert(core:deskSelectRoom("A", 2, t)) -- Double, $30
	eq(core:deskView("A").given, 30, "exact")
	assert(core:deskConfirm("A", { txId = 1, change = {} }, t))
	eq(core.cash, 80, "+30")
end)

test("Desk: guest short on cash switches to card", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	setFront(core, { methods = { "Cash", "Card" }, cashStyle = "fifty", cashLimit = 20 })
	assert(core:deskOpen("A", t))
	assert(core:deskChoose("A", "WalkIn", t))
	assert(core:deskSelectRoom("A", 1, t))
	eq(core:deskView("A").given, 20, "only $20 cash")
	local ok, msg = core:deskConfirm("A", { txId = 1, change = {} }, t)
	eq(ok, false, "short")
	expect(msg:find("short"), msg)
	eq(core.cash, 50, "no money yet")
	assert(core:deskSetMethod("A", "Card", t))
	assert(core:deskConfirm("A", { txId = 2 }, t))
	eq(core.cash, 75, "card +25")
end)

test("Desk: card not offered by the guest is rejected", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	setFront(core, { methods = { "Cash" } })
	assert(core:deskOpen("A", t))
	assert(core:deskChoose("A", "WalkIn", t))
	assert(core:deskSelectRoom("A", 1, t))
	eq(core:deskSetMethod("A", "Card", t), false, "no card")
end)

test("Desk: wrong mode gives a hint and stays on Start", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	setFront(core, {})
	assert(core:deskOpen("A", t))
	local ok, msg = core:deskChoose("A", "Booking", t)
	eq(ok, false, "walk-in guest")
	expect(msg:find("Walk%-in"), msg)
	eq(core:deskView("A").step, "Start", "still start")
end)

test("Desk: booking code wrong then right; prepaid issues key for $0", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	setFront(core, { booking = booking("2846", "Single", 25, 25, "Prepaid") })
	assert(core:deskOpen("A", t))
	eq(core:deskVerify("A", "2846", t), false, "must choose Booking first")
	assert(core:deskChoose("A", "Booking", t))
	eq(core:deskVerify("A", "1111", t), false, "wrong code")
	eq(core:deskVerify("A", "28a6", t), false, "not digits")
	assert(core:deskVerify("A", "2846", t))
	local v = core:deskView("A")
	eq(v.reservation.remaining, 0, "nothing due")
	eq(v.reservation.payment, "Prepaid", "label")
	assert(core:deskSelectRoom("A", 1, t))
	eq(core:deskView("A").method, "Online", "paid online")
	assert(core:deskConfirm("A", { txId = 1 }, t))
	eq(core.cash, 50, "no money at check-in")
	eq(core.nightStats.checkIns, 1, "checked in")
	expect(core.reservations["2846"].used, "reservation used")
end)

test("Desk: partially paid booking collects the rest ($15), change $5", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	setFront(core, { booking = booking("5310", "Single", 25, 10, "Partial"), cashStyle = "round10" })
	assert(core:deskOpen("A", t))
	assert(core:deskChoose("A", "Booking", t))
	assert(core:deskVerify("A", "5310", t))
	assert(core:deskSelectRoom("A", 3, t))
	local v = core:deskView("A")
	eq(v.due, 15, "remaining")
	eq(v.given, 20, "guest gives 20")
	assert(core:deskConfirm("A", { txId = 1, change = { 5 } }, t))
	eq(core.cash, 65, "+15 at check-in")
	eq(core.nightStats.rent, 15, "rent = collected")
end)

test("Desk: pay-at-motel booking collects the full rate", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	setFront(core, { booking = booking("7777", "Double", 30, 0, "PayAtMotel"), cashStyle = "fifty" })
	assert(core:deskOpen("A", t))
	assert(core:deskChoose("A", "Booking", t))
	assert(core:deskVerify("A", "7777", t))
	assert(core:deskSelectRoom("A", 2, t))
	assert(core:deskConfirm("A", { txId = 1, change = { 20 } }, t))
	eq(core.cash, 80, "+30")
end)

test("Desk: deposits are credited once at night start and reported apart", function()
	local core = newCore()
	core.plan.guests[1] = {
		index = 1,
		name = "Deposit Guest",
		kind = "Booking",
		methods = { "Cash" },
		cashStyle = "exact",
		booking = booking("4242", "Single", 25, 10, "Partial"),
	}
	core.plan.guests[1].booking.night = 1
	core:enterNight(0)
	eq(core.cash, 60, "deposit credited")
	eq(core.nightStats.deposits, 10, "deposit stat")
	core:enterNight(0) -- re-entering must not credit again
	eq(core.cash, 60, "credited once")
	core:enterClosing(1)
	core:update(1.5)
	eq(core.lastReport.deposits, 10, "report line")
	eq(core.lastReport.rent, 0, "rent separate")
end)

test("Desk: booking needs its room type; no matching room ready", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	setFront(core, { booking = booking("9001", "Double", 30, 0, "PayAtMotel") })
	core.rooms[2].trash = true
	assert(core:deskOpen("A", t))
	assert(core:deskChoose("A", "Booking", t))
	assert(core:deskVerify("A", "9001", t))
	local ok, msg = core:deskSelectRoom("A", 1, t)
	eq(ok, false, "single room refused")
	expect(msg:find("Double"), msg)
	expect(core:deskView("A").noMatch, "no matching room")
	core.rooms[2].trash = false
	expect(not core:deskView("A").noMatch, "double ready again")
	assert(core:deskSelectRoom("A", 2, t))
end)

test("Desk: double click on confirm pays once", function()
	local core = newCore()
	local t = nightWithQueue(core, 2)
	setFront(core, { cashStyle = "fifty" })
	assert(core:deskOpen("A", t))
	assert(core:deskChoose("A", "WalkIn", t))
	assert(core:deskSelectRoom("A", 1, t))
	local ok1 = core:deskConfirm("A", { txId = 77, change = { 20, 5 } }, t)
	local ok2 = core:deskConfirm("A", { txId = 77, change = { 20, 5 } }, t)
	expect(ok1 and ok2, "same answer for the same tx")
	eq(core.cash, 75, "paid once")
	eq(core.nightStats.checkIns, 1, "one check-in")
	-- A new click after success has no transaction to apply to.
	eq(core:deskConfirm("A", { txId = 78, change = { 20, 5 } }, t), false, "nothing to confirm")
	eq(core.cash, 75, "still once")
	eq(#core.queue, 1, "second guest untouched")
end)

test("Desk: room taken away before confirm asks for another room", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	setFront(core, { cashStyle = "exact" })
	assert(core:deskOpen("A", t))
	assert(core:deskChoose("A", "WalkIn", t))
	assert(core:deskSelectRoom("A", 1, t))
	core.rooms[1].acBroken = true
	local ok = core:deskConfirm("A", { txId = 1, change = {} }, t)
	eq(ok, false, "room unavailable")
	local v = core:deskView("A")
	eq(v.step, "Room", "back to room step")
	eq(v.notice, "RoomUnavailable", "notice")
	eq(v.guest ~= nil, true, "guest kept")
	eq(core.cash, 50, "no money")
	assert(core:deskSelectRoom("A", 3, t))
	assert(core:deskConfirm("A", { txId = 2, change = {} }, t))
end)

test("Desk: guest walks out mid-transaction, old transaction is void", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	setFront(core, { cashStyle = "exact" })
	local firstId = core.queue[1]
	assert(core:deskOpen("A", t))
	assert(core:deskChoose("A", "WalkIn", t))
	assert(core:deskSelectRoom("A", 1, t))
	while core.guests[firstId] and core.guests[firstId].state ~= "Departed" do
		t += 0.5
		core:update(t)
		core.desk.lastActive = t -- keep the session alive while waiting
	end
	local v = core:deskView("A")
	eq(v.notice, "GuestLeft", "guest left notice")
	eq(v.step, "Start", "transaction reset")
	eq(core:deskConfirm("A", { txId = 1, change = {} }, t), false, "old tx void")
	eq(core.cash, 50, "no money")
	eq(core.rooms[1].occupant, nil, "room free")
end)

test("Desk: one session per desk (co-op), release and timeout", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	assert(core:deskOpen("A", t))
	local ok, err = core:deskOpen("B", t)
	eq(ok, false, "B blocked")
	eq(err, "busy", "busy")
	eq(core:deskView("B").busy, true, "B sees busy")
	eq(core:deskChoose("B", "WalkIn", t), false, "B cannot act")
	eq(core:deskConfirm("B", { txId = 1 }, t), false, "B cannot confirm")
	core:deskRelease("A")
	assert(core:deskOpen("B", t))
	-- Idle past the timeout releases the desk.
	core:update(t + Config.desk.sessionTimeout + 1)
	eq(core.desk, nil, "timed out")
	-- Leaving the server releases too.
	assert(core:deskOpen("A", t + 50))
	core:playerLeft("A")
	eq(core.desk, nil, "released on leave")
end)

test("Desk: power out blocks the terminal, closing releases it", function()
	local core = newCore()
	local t = nightWithQueue(core, 1)
	assert(core:deskOpen("A", t))
	core.power = false
	eq(core:deskView("A").status, "PowerOut", "power out state")
	eq(core:deskChoose("A", "WalkIn", t), false, "blocked")
	core.power = true
	core:enterClosing(t)
	eq(core.desk, nil, "released at closing")
	eq(core:deskOpen("A", t), true, "can open to see the closed state")
	eq(core:deskView("A").status, "Closed", "closed state")
	eq(core:deskChoose("A", "WalkIn", t), false, "no check-in while closing")
end)

------------------------------------------------------------------------
-- Kitchen and roles
------------------------------------------------------------------------

-- Puts a meal order on a room with a guest in it.
local function orderMeal(core, roomId, recipe, now)
	local room = core.rooms[roomId]
	room.occupant = room.occupant or 999
	room.mealOrder = { recipe = recipe, placedAt = now, expiresAt = now + Config.kitchen.orderPatience }
end

test("Kitchen: cook pancakes, pick up, deliver for price + fast tip", function()
	local core = newCore({ playerCount = 2 })
	local t = 1
	orderMeal(core, 1, "pancakes", t)
	local ok, msg = core:startCook("A", 1, "pancakes", t)
	expect(ok, msg)
	eq(core.pantry.Flour, 1, "flour used")
	eq(core.pantry.Egg, 1, "egg used")
	eq(core:collectDish("A", 1), false, "not ready yet")
	core:update(t + 8.1)
	eq(core.slots[1].state, "Ready", "ready after cook time")
	assert(core:collectDish("A", 1))
	eq(core.slots[1].state, "Empty", "slot freed")
	eq(core:getCarry("A")[1], "Dish:pancakes", "carrying the dish")
	local cash = core.cash
	ok, msg = core:deliver("A", 1, t + 10)
	expect(ok, msg)
	eq(core.cash, cash + 10 + Config.kitchen.fastTip, "price + fast tip")
	eq(core.rooms[1].mealOrder, nil, "order closed")
	eq(core.nightStats.meals, 13, "meal stat")
end)

test("Kitchen: wrong station, missing ingredients, busy spot", function()
	local core = newCore({ playerCount = 2 })
	eq(core:startCook("A", 3, "burger", 1), false, "burger needs a burner")
	eq(core:startCook("A", 1, "salad", 1), false, "salad needs the board")
	core.pantry.Bun = 0
	eq(core:startCook("A", 1, "burger", 1), false, "no buns")
	eq(core.pantry.Patty, 2, "no ingredient used on failure")
	assert(core:startCook("A", 1, "pancakes", 1))
	eq(core:startCook("B", 1, "pancakes", 1), false, "spot busy")
	eq(core.pantry.Egg, 1, "second cook used nothing")
end)

test("Kitchen: dish burns if left on the burner, discard frees the spot", function()
	local core = newCore({ playerCount = 2 })
	assert(core:startCook("A", 1, "burger", 0))
	core:update(10 + Config.kitchen.burnAfter + 0.5)
	eq(core.slots[1].state, "Burnt", "burnt")
	eq(core.nightStats.burnt, 1, "burnt counted")
	eq(core:collectDish("A", 1), false, "cannot serve burnt food")
	assert(core:discardDish("A", 1))
	eq(core.slots[1].state, "Empty", "spot free")
	-- The prep board never burns.
	assert(core:startCook("A", 3, "salad", 0))
	core:update(200)
	eq(core.slots[3].state, "Ready", "salad waits")
end)

test("Kitchen: two players grab the same dish, only one gets it", function()
	local core = newCore({ playerCount = 2 })
	assert(core:startCook("A", 3, "salad", 0))
	core:update(6)
	local okA = core:collectDish("A", 3)
	local okB = core:collectDish("B", 3)
	expect(okA and not okB, "one pickup")
	eq(#core:getCarry("B"), 0, "B empty-handed")
end)

test("Kitchen: two deliveries for one order pay once", function()
	local core = newCore({ playerCount = 2 })
	orderMeal(core, 2, "salad", 0)
	core.carries.A = { "Dish:salad" }
	core.carries.B = { "Dish:salad" }
	local cash = core.cash
	local okA = core:deliver("A", 2, 1)
	local okB = core:deliver("B", 2, 1)
	expect(okA and not okB, "one delivery")
	eq(core.cash, cash + 8 + Config.kitchen.fastTip, "paid once")
	eq(#core.carries.B, 1, "B keeps the dish")
end)

test("Kitchen: wrong dish is refused, late orders are missed", function()
	local core = newCore({ playerCount = 2 })
	orderMeal(core, 1, "burger", 0)
	core.carries.A = { "Dish:salad" }
	local ok, msg = core:deliver("A", 1, 1)
	eq(ok, false, "wrong dish")
	expect(msg:find("Burger"), msg)
	core:update(Config.kitchen.orderPatience + 1)
	eq(core.rooms[1].mealOrder, nil, "order expired")
	eq(core.nightStats.missedMeals, 1, "missed counted")
end)

test("Kitchen: slow delivery gets no tip; towel and meal on the same door", function()
	local core = newCore({ playerCount = 2 })
	orderMeal(core, 1, "salad", 0)
	core.rooms[1].towelRequest = true
	core.carries.A = { "Towel" }
	core.carries.B = { "Dish:salad" }
	local cash = core.cash
	assert(core:deliver("A", 1, 30)) -- towel first (A carries a towel)
	eq(core.cash, cash + Config.economy.towelTip, "towel tip")
	assert(core:deliver("B", 1, 30)) -- then the meal, after the fast window
	eq(core.cash, cash + Config.economy.towelTip + 8, "no fast tip")
end)

test("Kitchen: food purchases fill the pantry", function()
	local core = newCore()
	core.cash = 100
	assert(core:buyItem("A", "burgerkit"))
	eq(core.pantry.Bun, 5, "buns")
	eq(core.pantry.Patty, 5, "patties")
	eq(core.cash, 91, "cost")
	assert(core:buyItem("A", "eggs"))
	eq(core.pantry.Egg, 6, "eggs")
end)

test("Kitchen: guests order after check-in, checkout misses an open order", function()
	local core = newCore({ random = lowRandom }) -- always orders, minimum delays
	local t = nightWithQueue(core, 1)
	assert(serve(core, "A", 1, t))
	t = run(core, t, t + Config.kitchen.orderDelayMin + 0.5)
	local order = core.rooms[1].mealOrder
	expect(order ~= nil, "order placed")
	eq(order.recipe, "pancakes", "first recipe with the low random")
	local g = core.guests[core.rooms[1].occupant]
	expect(g.stayUntil >= order.expiresAt, "guest stays until the order deadline")
	core:checkout(core.guests[core.rooms[1].occupant], t, "Checkout")
	eq(core.nightStats.missedMeals, 1, "missed on checkout")
end)

test("Roles: soft roles in Preparation; chef cooks faster; housekeeper carries more", function()
	local core = newCore({ playerCount = 2 })
	eq(core:setRole("A", "Pilot"), false, "unknown role")
	assert(core:setRole("A", "Chef"))
	assert(core:setRole("B", "Housekeeper"))
	assert(core:startCook("A", 1, "burger", 0))
	eq(core.slots[1].readyAt, 10 * Config.rolePerks.chefCookMultiplier, "chef speed")
	assert(core:startCook("B", 2, "pancakes", 0))
	eq(core.slots[2].readyAt, 8, "normal speed")
	eq(core:carryCapacity("B"), 2, "housekeeper +1")
	eq(core:carryCapacity("A"), 1, "chef normal carry")
	core:setReady("A")
	core:setReady("B")
	core:update(0.5)
	eq(core:setRole("A", "Maintenance"), false, "roles only change in Preparation")
	-- Solo players have every perk.
	local solo = newCore()
	eq(solo:carryCapacity("A"), 2, "solo carry perk")
	expect(solo:hasRole("A", "Chef"), "solo chef")
end)

-- Simulates players doing every job through the normal actions.
-- The run is endless: stops when the run ends or `maxNights` bills are paid.
local function simulateRun(playerCount, competent, random, maxNights)
	maxNights = maxNights or 3
	local core = newCore({ playerCount = playerCount, random = random or midRandom })
	local t = 0
	local guard = 0
	while core.phase ~= P.RunEnded and core.nightsSurvived < maxNights do
		guard += 1
		assert(guard < 40000, "simulation did not finish")
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
				-- Room service: cook what is ordered, pick up, deliver.
				for _, room in ipairs(core.rooms) do
					local order = room.mealOrder
					if order then
						local dish = "Dish:" .. order.recipe
						local carry = core:getCarry("A")
						if table.find(carry, dish) then
							core:deliver("A", room.id, t)
						else
							local cooking = false
							for i, slot in ipairs(core.slots) do
								if slot.recipe == order.recipe and slot.state == "Ready" then
									core:collectDish("A", i)
									cooking = true
								elseif slot.recipe == order.recipe and slot.state == "Cooking" then
									cooking = true
								end
							end
							if not cooking then
								for i, slot in ipairs(core.slots) do
									if slot.state == "Empty" and core:startCook("A", i, order.recipe, t) then
										break
									end
								end
							end
						end
					end
				end
				for i, slot in ipairs(core.slots) do
					if slot.state == "Burnt" then
						core:discardDish("A", i)
					end
				end
				if core.phase == P.Night and #core.queue > 0 then
					for _, room in ipairs(core.rooms) do
						if core:isRoomReady(room) then
							serve(core, "A", room.id, t)
							break
						end
					end
				end
			end
		end
	end
	return core
end

test("Endless: competent solo team survives 5 nights (into generated nights)", function()
	local core = simulateRun(1, true, nil, 5)
	eq(core.nightsSurvived, 5, "5 nights")
	expect(core.phase ~= P.RunEnded, "run still going")
	print(("      final cash $%d, served %d, walkouts %d"):format(core.cash, core.totals.served, core.totals.walkouts))
end)

test("M3: competent 4-player team survives the 3 scripted nights", function()
	local core = simulateRun(4, true)
	eq(core.nightsSurvived, 3, "3 nights")
	print(("      final cash $%d, served %d, walkouts %d"):format(core.cash, core.totals.served, core.totals.walkouts))
end)

-- Seeded pseudo-random (LCG) so guests book, pay and order in a mix.
local function seededRandom(seed)
	local state = seed
	return function(a, b)
		state = (state * 1103515245 + 12345) % 2147483648
		return a + (state / 2147483648) * (b - a)
	end
end

test("Kitchen: competent solo team with room service survives 3 nights", function()
	for _, seed in ipairs({ 7, 42, 2026 }) do
		local core = simulateRun(1, true, seededRandom(seed))
		eq(core.nightsSurvived, 3, "3 nights with seed " .. seed)
		print(
			("      seed %d: cash $%d, meals $%d, served %d, walkouts %d"):format(
				seed,
				core.cash,
				core.totals.meals,
				core.totals.served,
				core.totals.walkouts
			)
		)
	end
end)

test("M3: idle team fails night 1 with score 0", function()
	local core = simulateRun(1, false)
	eq(core.complete, false, "not complete")
	eq(core.nightsSurvived, 0, "score")
	eq(core.lastReport.shortfall, 5, "shortfall $5")
end)

test("Endless: nights past the script grow and the run never completes", function()
	local core = newCore({ random = seededRandom(5) })
	local last = Config.nights[#Config.nights]
	local n4 = core:nightConfig(#Config.nights + 1)
	local n10 = core:nightConfig(#Config.nights + 7)
	expect(n4.bill > last.bill, "bill grows")
	expect(n10.bill > n4.bill, "bill keeps growing")
	expect(n10.guests >= n4.guests and n10.guests <= Config.endless.maxGuests, "guests capped")
	expect(type(n10.forecast) == "string" and #n10.forecast > 0, "forecast")
	local plan = core:buildNightPlan(#Config.nights + 20, 1)
	expect(plan.guestCount >= 1 and plan.bill > 0, "far night plan")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("tests failed")
end
