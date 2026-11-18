--!nonstrict
--[[
	MotelCore: the authoritative game state for one motel run.

	Pure Luau: no Roblox services, no yields. Time is passed in as `now`
	(the server uses workspace:GetServerTimeNow()). Every public mutation
	runs to completion without yielding, so a check-in assigns guest, room,
	payment and reservation in one step, and two requests that arrive back
	to back can never both consume the same stock, room or tip.

	Check-in goes through the front desk terminal (one session per desk):
	Start (Booking / Walk-in) -> Code (reservations) -> Room -> Payment.
	Nothing changes until deskConfirm commits; a repeated confirm with the
	same txId returns the first result without a second transaction.

	Config and Constants are injected so the CLI test runner can load this
	module without the Roblox DataModel.
]]

local MotelCore = {}
MotelCore.__index = MotelCore

local ACTIVE_PHASES = { Preparation = true, Night = true, Closing = true }

local function copyEvents(list)
	local out = {}
	for i, e in ipairs(list or {}) do
		out[i] = table.clone(e)
	end
	return out
end

local function sortedKeys(map)
	local keys = {}
	for k in pairs(map) do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

function MotelCore.new(config, constants, options)
	options = options or {}
	local self = setmetatable({}, MotelCore)
	self.config = config
	self.C = constants
	self.timeScale = options.timeScale or config.timeScale or 1
	self.random = options.random or function(a, b)
		return a + math.random() * (b - a)
	end
	self.bestNights = 0
	self.runId = 0
	self.version = 0
	self.playerCount = math.max(1, options.playerCount or 1)
	self.pendingEvents = {}
	self.roles = {} -- [playerId] = role id (soft roles; kept across restarts)
	self:resetRun(options.now or 0)
	return self
end

-- Scales a config duration by the tester time scale.
function MotelCore:dur(seconds: number): number
	return seconds * self.timeScale
end

function MotelCore:bump()
	self.version += 1
end

-- Events are drained by the server to show broadcast feedback and effects.
function MotelCore:emit(kind: string, data)
	data = data or {}
	data.kind = kind
	table.insert(self.pendingEvents, data)
end

function MotelCore:drainEvents()
	local list = self.pendingEvents
	self.pendingEvents = {}
	return list
end

------------------------------------------------------------------------
-- Run lifecycle
------------------------------------------------------------------------

function MotelCore:resetRun(now: number)
	local cfg = self.config
	self.runId += 1
	self.cash = cfg.economy.startingCash
	self.stock = { Sheet = cfg.supplies.startingSheets, Towel = cfg.supplies.startingTowels }
	self.trolley = false
	self.power = true
	self.rain = false
	self.rooms = {}
	for i = 1, cfg.roomCount do
		local def = cfg.rooms[i]
		self.rooms[i] = {
			id = i,
			number = def.number,
			type = def.type,
			occupant = nil,
			trash = false,
			sheetsDirty = false,
			acBroken = false,
			towelRequest = false,
			mealOrder = nil, -- { recipe, placedAt, expiresAt }
		}
	end
	self.guests = {}
	self.queue = {}
	self.nextGuestId = 0
	self.carries = {} -- [playerId] = { items }
	self.night = 1
	self.nightsSurvived = 0
	self.complete = false
	self.lastReport = nil
	self.billPaidForNight = 0
	self.totals = { served = 0, walkouts = 0, unserved = 0, rent = 0, tips = 0, deposits = 0, meals = 0 }
	self:resetKitchen()
	self.desk = nil -- front desk session (see Front desk section)
	self.reservations = {}
	self.fixes = {} -- [playerId] = repair minigame in progress
	self.cashierTutorialDone = false
	self:enterPreparation(now)
	self:emit("RunStarted", { runId = self.runId })
	self:bump()
end

function MotelCore:setPlayerCount(n: number)
	n = math.clamp(math.floor(n), 1, self.config.coop.maxPlayers)
	if n ~= self.playerCount then
		self.playerCount = n
		self:bump()
	end
end

-- Scripted night from Config.nights, or a generated one past the last
-- scripted night (endless run).
function MotelCore:nightConfig(night: number)
	local cfg = self.config
	local scripted = cfg.nights[night]
	if scripted then
		return scripted
	end
	local e = cfg.endless
	local last = cfg.nights[#cfg.nights]
	local extra = night - #cfg.nights
	local function chance(p: number): boolean
		return self.random(0, 1) < p
	end
	local rain = chance(e.rainChance)
	local events = {}
	local notes = {}
	if chance(e.acChance) then
		table.insert(events, { type = "ACBreak", at = math.floor(self.random(20, 70)) })
		if night >= 6 and chance(e.acSecondChance) then
			table.insert(events, { type = "ACBreak", at = math.floor(self.random(80, 120)) })
			table.insert(notes, "Two AC units may break.")
		else
			table.insert(notes, "An AC unit may break.")
		end
	end
	if chance(e.powerChance) then
		table.insert(events, { type = "PowerOutage", minAt = 40, queueAtLeast = 2, fallbackAt = 90 })
		table.insert(notes, "Power may fail.")
	end
	local head = if rain then "Rainy night: guests are impatient." else "Busier night ahead."
	return {
		guests = math.min(e.maxGuests, last.guests + math.floor(extra * e.guestsPerNight)),
		bill = last.bill + extra * e.billPerNight,
		rain = rain,
		forecast = table.concat({ head, table.unpack(notes) }, " "),
		events = events,
	}
end

function MotelCore:buildNightPlan(night: number, playerCount: number)
	local cfg = self.config
	local nightCfg = self:nightConfig(night)
	local n = math.clamp(playerCount, 1, cfg.coop.maxPlayers)
	local guestCount = math.max(1, math.floor(nightCfg.guests * cfg.coop.guestMultiplier[n] + 0.5))
	local bill = math.floor(nightCfg.bill * cfg.coop.billMultiplier[n] + 0.5)

	local first = cfg.guests.firstArrivalAt
	local last = cfg.phases.night - cfg.guests.lastArrivalBuffer
	local arrivals = {}
	if guestCount == 1 then
		arrivals[1] = first
	else
		local spacing = (last - first) / (guestCount - 1)
		local jitter = math.min(cfg.guests.arrivalJitter, spacing * 0.3)
		for i = 1, guestCount do
			local t = first + spacing * (i - 1) + self.random(-jitter, jitter)
			arrivals[i] = math.clamp(t, first, last)
		end
		table.sort(arrivals)
	end

	return {
		night = night,
		playerCount = n,
		guestCount = guestCount,
		guests = self:makeGuestProfiles(night, guestCount),
		depositsCredited = false,
		bill = bill,
		arrivals = arrivals, -- unscaled seconds into the night
		rain = nightCfg.rain == true,
		forecast = nightCfg.forecast or "",
		events = copyEvents(nightCfg.events),
	}
end

-- One profile per planned guest: name, walk-in or reservation, how they pay.
function MotelCore:makeGuestProfiles(night: number, count: number)
	local cfg = self.config
	local d = cfg.desk
	local C = self.C
	local function chance(p: number): boolean
		return self.random(0, 1) < p
	end
	local function pickIndex(n: number): number
		return math.clamp(math.floor(self.random(1, n + 1)), 1, n)
	end
	local types = {}
	for _, def in ipairs(cfg.rooms) do
		if not table.find(types, def.type) then
			table.insert(types, def.type)
		end
	end
	local names = table.clone(d.names)
	local usedCodes = {}
	local profiles = {}
	for i = 1, count do
		local name = if #names > 0 then table.remove(names, pickIndex(#names)) else ("Guest %d"):format(i)
		local p = {
			index = i,
			name = name,
			kind = C.GuestKind.WalkIn,
			methods = { C.PayMethod.Cash },
			cashStyle = d.cashStyles[pickIndex(#d.cashStyles)],
			cashLimit = nil,
			booking = nil,
		}
		if chance(d.cardChance) then
			table.insert(p.methods, C.PayMethod.Card)
			if chance(d.shortCashChance) then
				p.cashLimit = d.shortCashAmount -- must switch to card
			end
		end
		local isBooking = chance(d.bookingChance)
		if night == 1 and i == 1 then
			-- First guest of a run: plain walk-in paying cash (cashier tutorial).
			isBooking = false
			p.methods = { C.PayMethod.Cash }
			p.cashLimit = nil
			p.cashStyle = "round10"
		end
		if isBooking then
			p.kind = C.GuestKind.Booking
			-- Random 4-digit code; on a clash step to the next free one.
			local n = math.clamp(math.floor(self.random(1000, 10000)), 1000, 9999)
			while usedCodes[tostring(n)] do
				n = if n >= 9999 then 1000 else n + 1
			end
			local code = tostring(n)
			usedCodes[code] = true
			local roomType = types[pickIndex(#types)]
			local total = cfg.roomTypes[roomType].rate
			local roll = self.random(0, 1)
			local payment, paid
			if roll < d.prepaidChance then
				payment, paid = C.Payment.Prepaid, total
			elseif roll < d.prepaidChance + d.partialChance then
				payment, paid = C.Payment.Partial, math.min(d.partialDeposit, total - 1)
			else
				payment, paid = C.Payment.PayAtMotel, 0
			end
			p.booking = {
				code = code,
				roomType = roomType,
				total = total,
				paid = paid,
				payment = payment,
				night = night,
			}
		end
		profiles[i] = p
	end
	return profiles
end

function MotelCore:setPhase(phase: string, now: number, duration: number?)
	self.phase = phase
	self.phaseStartedAt = now
	self.phaseEndsAt = if duration then now + self:dur(duration) else nil
	self:emit("PhaseChanged", { phase = phase, night = self.night })
	self:bump()
end

function MotelCore:enterPreparation(now: number)
	self.ready = {}
	self.rain = false
	-- Player count captured here applies to this coming night only.
	self.plan = self:buildNightPlan(self.night, self.playerCount)
	self.nightStats = {
		rent = 0, -- money taken at the front desk
		deposits = 0, -- reservation money paid in advance (credited when the night starts)
		checkIns = 0,
		meals = 0, -- room service money (price + fast tips)
		missedMeals = 0,
		burnt = 0,
		tips = 0,
		purchases = 0,
		arrivals = 0,
		served = 0,
		walkouts = 0,
		unserved = 0,
		evicted = 0,
		missedTowels = 0,
	}
	self.nextArrival = 1
	self.reservations = {}
	if self.slots then
		self:clearStove() -- leftovers on the stove are thrown out each night
	end
	self:setPhase(self.C.Phase.Preparation, now, self.config.phases.preparation)
end

function MotelCore:enterNight(now: number)
	self.rain = self.plan.rain
	-- Tonight's reservations go live; money paid in advance is credited once.
	self.reservations = {}
	for _, p in ipairs(self.plan.guests) do
		local b = p.booking
		if b then
			self.reservations[b.code] = {
				code = b.code,
				night = b.night,
				guestIndex = p.index,
				name = p.name,
				roomType = b.roomType,
				total = b.total,
				paid = b.paid,
				payment = b.payment,
				used = false,
			}
		end
	end
	if not self.plan.depositsCredited then
		self.plan.depositsCredited = true
		for _, r in pairs(self.reservations) do
			if r.paid > 0 then
				self.cash += r.paid
				self.nightStats.deposits += r.paid
				self.totals.deposits += r.paid
			end
		end
	end
	self:setPhase(self.C.Phase.Night, now, self.config.phases.night)
	if self.rain then
		self:emit("Rain", {})
	end
end

function MotelCore:enterClosing(now: number)
	-- Stop arrivals; anyone not yet in a room leaves and is recorded once.
	for _, id in ipairs(sortedKeys(self.guests)) do
		local g = self.guests[id]
		if g.state == self.C.GuestState.Arriving or g.state == self.C.GuestState.Queued then
			self:depart(g, "Unserved", now)
		end
	end
	self.queue = {}
	self.desk = nil -- check-in is over: release the front desk
	self:setPhase(self.C.Phase.Closing, now, self.config.phases.closing)
end

function MotelCore:enterReport(now: number)
	-- Close the motel: evict guests still staying, their rooms become dirty.
	for _, id in ipairs(sortedKeys(self.guests)) do
		local g = self.guests[id]
		if g.state == self.C.GuestState.Staying then
			self:checkout(g, now, "ClosedOut")
		end
	end
	self.rain = false
	self.desk = nil

	local plan = self.plan
	local report = {
		night = self.night,
		rent = self.nightStats.rent,
		deposits = self.nightStats.deposits,
		tips = self.nightStats.tips,
		meals = self.nightStats.meals,
		missedMeals = self.nightStats.missedMeals,
		burnt = self.nightStats.burnt,
		purchases = self.nightStats.purchases,
		bill = plan.bill,
		served = self.nightStats.served,
		walkouts = self.nightStats.walkouts,
		unserved = self.nightStats.unserved,
		evicted = self.nightStats.evicted,
		missedTowels = self.nightStats.missedTowels,
		guestsPlanned = plan.guestCount,
		cashBefore = self.cash,
		cashAfter = self.cash,
		passed = false,
		shortfall = 0,
	}
	-- Charge the bill exactly once per night.
	if self.billPaidForNight ~= self.night then
		self.billPaidForNight = self.night
		if self.cash >= plan.bill then
			self.cash -= plan.bill
			self.nightsSurvived += 1
			report.passed = true
		else
			report.shortfall = plan.bill - self.cash
		end
		report.cashAfter = self.cash
	end
	report.nightsSurvived = self.nightsSurvived
	self.lastReport = report
	self.bestNights = math.max(self.bestNights, self.nightsSurvived)
	self:setPhase(self.C.Phase.Report, now, self.config.phases.report)
end

function MotelCore:endReport(now: number)
	local report = self.lastReport
	-- Endless: the run only ends when the bill can't be paid.
	if not report.passed then
		self.complete = false
		self:setPhase(self.C.Phase.RunEnded, now, nil)
	else
		self.night += 1
		self:enterPreparation(now)
	end
end

------------------------------------------------------------------------
-- Guests
------------------------------------------------------------------------

function MotelCore:spawnGuest(now: number, index: number?)
	self.nextGuestId += 1
	local profile = index and self.plan.guests[index]
	if not profile then
		profile = {
			index = 0,
			name = "Guest",
			kind = self.C.GuestKind.WalkIn,
			methods = { self.C.PayMethod.Cash },
			cashStyle = "exact",
		}
	end
	local g = {
		id = self.nextGuestId,
		profile = profile,
		runId = self.runId,
		state = self.C.GuestState.Arriving,
		arrivedAt = now,
		queueAt = now + self:dur(self.config.guests.arriveDuration),
		lastState = nil,
	}
	self.guests[g.id] = g
	self.nightStats.arrivals += 1
	self:emit("GuestArriving", { guestId = g.id })
	self:bump()
	return g
end

function MotelCore:depart(g, reason: string, now: number)
	local prev = g.state
	g.previousState = prev
	g.state = self.C.GuestState.Departed
	g.departReason = reason
	g.departedAt = now
	g.removeAt = now + self:dur(self.config.guests.departDuration)
	if reason == "Walkout" then
		self.nightStats.walkouts += 1
		self.totals.walkouts += 1
		self:emit("Walkout", { guestId = g.id })
	elseif reason == "Unserved" then
		if not g.unservedCounted then
			g.unservedCounted = true
			self.nightStats.unserved += 1
			self.totals.unserved += 1
		end
	elseif reason == "Checkout" or reason == "ClosedOut" then
		self.nightStats.served += 1
		self.totals.served += 1
		if reason == "ClosedOut" then
			self.nightStats.evicted += 1
		end
	end
	-- Remove from queue if still listed.
	for i, id in ipairs(self.queue) do
		if id == g.id then
			table.remove(self.queue, i)
			break
		end
	end
	self:bump()
end

function MotelCore:checkout(g, now: number, reason: string)
	local room = self.rooms[g.roomId]
	if room and room.occupant == g.id then
		room.occupant = nil
		room.trash = true
		room.sheetsDirty = true
		if room.towelRequest then
			room.towelRequest = false
			self.nightStats.missedTowels += 1
		end
		if room.mealOrder then
			room.mealOrder = nil
			self.nightStats.missedMeals += 1
		end
	end
	self:depart(g, reason, now)
	self:emit("Checkout", { guestId = g.id, roomId = g.roomId })
end

function MotelCore:queuePosition(guestId: number): number?
	for i, id in ipairs(self.queue) do
		if id == guestId then
			return i
		end
	end
	return nil
end

function MotelCore:updateGuests(now: number)
	local GS = self.C.GuestState
	for _, id in ipairs(sortedKeys(self.guests)) do
		local g = self.guests[id]
		if g.state == GS.Arriving and now >= g.queueAt then
			g.state = GS.Queued
			g.queuedAt = now
			local patience = self.config.guests.patience
			if self.rain then
				patience *= self.config.guests.rainPatienceMultiplier
			end
			g.patienceEndsAt = now + self:dur(patience)
			table.insert(self.queue, g.id)
			self:bump()
		elseif g.state == GS.Queued and now >= g.patienceEndsAt then
			self:depart(g, "Walkout", now)
		elseif g.state == GS.Staying then
			self:placeMealOrder(g, now)
			if g.towelAt and now >= g.towelAt then
				g.towelAt = nil
				local room = self.rooms[g.roomId]
				if room and room.occupant == g.id then
					room.towelRequest = true
					self:emit("TowelRequest", { roomId = room.id })
					self:bump()
				end
			end
			if now >= g.stayUntil then
				self:checkout(g, now, "Checkout")
			end
		elseif g.state == GS.Departed and now >= g.removeAt then
			self.guests[id] = nil
			self:bump()
		end
	end
end

function MotelCore:updateNightEvents(now: number)
	local t = (now - self.phaseStartedAt)
	for _, e in ipairs(self.plan.events) do
		if not e.fired then
			if e.type == "ACBreak" and t >= self:dur(e.at) then
				e.fired = true
				local candidates = {}
				for _, room in ipairs(self.rooms) do
					if not room.acBroken then
						table.insert(candidates, room)
					end
				end
				if #candidates > 0 then
					local idx = math.clamp(math.floor(self.random(1, #candidates + 1)), 1, #candidates)
					local room = candidates[idx]
					room.acBroken = true
					self:emit("ACBroken", { roomId = room.id })
					self:bump()
				end
			elseif e.type == "PowerOutage" and t >= self:dur(e.minAt) then
				if #self.queue >= (e.queueAtLeast or 1) or t >= self:dur(e.fallbackAt or e.minAt) then
					e.fired = true
					if self.power then
						self.power = false
						self:emit("PowerOut", {})
						self:bump()
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Main tick
------------------------------------------------------------------------

function MotelCore:allReady(): boolean
	local count = 0
	for _ in pairs(self.ready) do
		count += 1
	end
	return count > 0 and count >= self.playerCount
end

function MotelCore:update(now: number)
	local P = self.C.Phase
	local phase = self.phase
	if phase == P.Preparation then
		if now >= self.phaseEndsAt or self:allReady() then
			self:enterNight(now)
		end
	elseif phase == P.Night then
		local t = now - self.phaseStartedAt
		local arrivals = self.plan.arrivals
		while self.nextArrival <= #arrivals and t >= self:dur(arrivals[self.nextArrival]) do
			self.nextArrival += 1
			self:spawnGuest(now, self.nextArrival - 1)
		end
		self:updateNightEvents(now)
		self:updateGuests(now)
		if now >= self.phaseEndsAt then
			self:enterClosing(now)
		end
	elseif phase == P.Closing then
		self:updateGuests(now)
		local anyStaying = false
		for _, g in pairs(self.guests) do
			if g.state == self.C.GuestState.Staying then
				anyStaying = true
				break
			end
		end
		if now >= self.phaseEndsAt or not anyStaying then
			self:enterReport(now)
		end
	elseif phase == P.Report then
		self:updateGuests(now)
		if now >= self.phaseEndsAt then
			self:endReport(now)
		end
	else
		self:updateGuests(now)
	end
	self:deskTick(now)
	self:updateKitchen(now)
end

------------------------------------------------------------------------
-- Rooms
------------------------------------------------------------------------

function MotelCore:roomBlockers(room): { string }
	local list = {}
	if room.occupant then
		table.insert(list, "occupied")
	end
	if room.trash then
		table.insert(list, "trash")
	end
	if room.sheetsDirty then
		table.insert(list, "dirty sheets")
	end
	if room.acBroken then
		table.insert(list, "AC broken")
	end
	return list
end

function MotelCore:isRoomReady(room): boolean
	return room.occupant == nil and not room.trash and not room.sheetsDirty and not room.acBroken
end

------------------------------------------------------------------------
-- Player carry
------------------------------------------------------------------------

function MotelCore:getCarry(pid)
	local carry = self.carries[pid]
	if not carry then
		carry = {}
		self.carries[pid] = carry
	end
	return carry
end

function MotelCore:carryCapacity(pid): number
	local s = self.config.supplies
	local cap = if self.trolley then s.trolleyCarryCapacity else s.baseCarryCapacity
	if pid ~= nil and self:hasRole(pid, "Housekeeper") then
		cap += self.config.rolePerks.housekeeperExtraCarry
	end
	return cap
end

local function removeOne(list, item): boolean
	for i, v in ipairs(list) do
		if v == item then
			table.remove(list, i)
			return true
		end
	end
	return false
end

local function count(list, item): number
	local n = 0
	for _, v in ipairs(list) do
		if v == item then
			n += 1
		end
	end
	return n
end

function MotelCore:requireActive(): (boolean, string?)
	if not ACTIVE_PHASES[self.phase] then
		return false, "The motel is closed right now."
	end
	return true, nil
end

------------------------------------------------------------------------
-- Actions. Each returns (ok: boolean, message: string).
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Front desk terminal
------------------------------------------------------------------------

local function newSession(pid, now: number)
	return {
		owner = pid,
		guestId = nil, -- guest this transaction belongs to
		step = "Start",
		mode = nil,
		verified = false,
		roomId = nil,
		method = nil,
		given = nil, -- cash the guest hands over (set when the room is picked)
		notice = nil, -- "GuestLeft" | "RoomUnavailable"
		message = nil, -- { text, kind, seq } shown inside the terminal
		lastActive = now,
		lastTx = nil, -- { txId, ok, msg } for idempotent confirms
	}
end

function MotelCore:roomNumber(roomId: number): number
	local room = self.rooms[roomId]
	return room and room.number or roomId
end

-- Front guest waiting at the desk, if any.
function MotelCore:deskGuest()
	local id = self.queue[1]
	local g = id and self.guests[id]
	if g and g.state == self.C.GuestState.Queued then
		return g
	end
	return nil
end

-- Clears transaction progress (keeps owner, message and lastTx).
local function resetProgress(s)
	s.step = "Start"
	s.mode = nil
	s.verified = false
	s.roomId = nil
	s.method = nil
	s.given = nil
end

-- Keeps the session pointed at the current front guest. If that guest is
-- gone, the old transaction is dropped and can never apply to the next one.
function MotelCore:deskSync()
	local s = self.desk
	if not s then
		return
	end
	local g = self:deskGuest()
	local fid = g and g.id or nil
	if s.guestId ~= fid then
		if s.guestId ~= nil then
			s.notice = "GuestLeft"
			s.message = nil
		end
		s.guestId = fid
		resetProgress(s)
		self:bump()
	end
end

function MotelCore:deskTick(now: number)
	local s = self.desk
	if not s then
		return
	end
	if now - s.lastActive > self:dur(self.config.desk.sessionTimeout) then
		self.desk = nil
		self:bump()
		return
	end
	self:deskSync()
end

function MotelCore:deskMessage(s, text: string, kind: string)
	-- Run-wide counter, so a new session never repeats an old message id.
	self.deskMsgSeq = (self.deskMsgSeq or 0) + 1
	s.message = { text = text, kind = kind, seq = self.deskMsgSeq }
	self:bump()
end

-- Opens (or reopens) the desk for this player. Returns false, "busy" when
-- another player holds the desk.
function MotelCore:deskOpen(pid, now: number): (boolean, string?)
	if not ACTIVE_PHASES[self.phase] then
		return false, "The motel is closed right now."
	end
	local s = self.desk
	if s and s.owner ~= pid then
		return false, "busy"
	end
	if not s then
		s = newSession(pid, now)
		self.desk = s
	end
	s.lastActive = now
	self:deskSync()
	self:bump()
	return true, nil
end

function MotelCore:deskRelease(pid): boolean
	if self.desk and self.desk.owner == pid then
		self.desk = nil
		self:bump()
		return true
	end
	return false
end

-- Common checks for terminal actions. Returns session, guest or nil, nil, error.
function MotelCore:deskGuard(pid, now: number)
	local s = self.desk
	if not s or s.owner ~= pid then
		return nil, nil, "Open the front desk first."
	end
	s.lastActive = now
	self:deskSync()
	local P = self.C.Phase
	if self.phase == P.Closing then
		return nil, nil, "Closing time: no new check-ins."
	elseif self.phase ~= P.Night then
		return nil, nil, "Check-in opens at Night."
	end
	if not self.power then
		return nil, nil, "Power is out! Reset the breaker first."
	end
	local g = self:deskGuest()
	if not g then
		return nil, nil, "No guest is waiting at the desk."
	end
	s.notice = nil
	return s, g, nil
end

-- The session of this player (for error messages), or nil.
function MotelCore:ownSession(pid)
	local s = self.desk
	return if s and s.owner == pid then s else nil
end

local function fail(self, s, text: string): (boolean, string)
	if s then
		self:deskMessage(s, text, "error")
	end
	return false, text
end

function MotelCore:reservationFor(g)
	local b = g.profile.booking
	if not b then
		return nil
	end
	local r = self.reservations[b.code]
	if r and r.night == self.night and r.guestIndex == g.profile.index then
		return r
	end
	return nil
end

-- Amount still to collect at the desk for this guest and room.
function MotelCore:deskDue(s, g): number?
	if s.mode == self.C.GuestKind.Booking then
		local r = self:reservationFor(g)
		return r and (r.total - r.paid) or nil
	end
	local room = s.roomId and self.rooms[s.roomId]
	return room and self.config.roomTypes[room.type].rate or nil
end

-- Cash the guest hands over for an amount (decided by the server).
function MotelCore:cashGiven(profile, due: number): number
	local style = profile.cashStyle
	local given = due
	if style == "round10" then
		given = math.ceil(due / 10) * 10
	elseif style == "twenty" then
		given = math.ceil(due / 20) * 20
	elseif style == "fifty" then
		given = math.max(50, math.ceil(due / 50) * 50)
	end
	if profile.cashLimit then
		given = math.min(given, profile.cashLimit)
	end
	return given
end

function MotelCore:deskChoose(pid, mode, now: number): (boolean, string)
	local s, g, err = self:deskGuard(pid, now)
	if not s then
		return fail(self, self:ownSession(pid), err)
	end
	local K = self.C.GuestKind
	if mode ~= K.Booking and mode ~= K.WalkIn then
		return false, "Unknown option."
	end
	if s.step ~= "Start" then
		return fail(self, s, "Finish or go back first.")
	end
	if g.profile.kind ~= mode then
		if mode == K.Booking then
			return fail(self, s, "This guest has no reservation. Go back and choose Walk-in.")
		end
		return fail(self, s, "This guest has a reservation. Choose Booking and enter the code.")
	end
	s.mode = mode
	s.step = if mode == K.Booking then "Code" else "Room"
	s.message = nil
	self:bump()
	return true, ""
end

function MotelCore:deskVerify(pid, code, now: number): (boolean, string)
	local s, g, err = self:deskGuard(pid, now)
	if not s then
		return fail(self, self:ownSession(pid), err)
	end
	if s.step ~= "Code" then
		return fail(self, s, "Choose Booking first.")
	end
	if typeof(code) ~= "string" or not string.match(code, "^%d%d%d%d$") then
		return fail(self, s, "Enter all 4 digits.")
	end
	local r = self.reservations[code]
	if not r or r.used or r.night ~= self.night or r.guestIndex ~= g.profile.index then
		return fail(self, s, "Code not found for this guest.")
	end
	s.verified = true
	s.step = "Room"
	s.message = nil
	self:bump()
	return true, ""
end

-- Why a room cannot take this guest right now (nil = it can).
function MotelCore:deskRoomProblem(s, g, room): string?
	if not self:isRoomReady(room) then
		return ("Room %d is not ready (%s)."):format(room.number, table.concat(self:roomBlockers(room), ", "))
	end
	if s.mode == self.C.GuestKind.Booking then
		local r = self:reservationFor(g)
		if not r then
			return "Reservation no longer valid."
		end
		if room.type ~= r.roomType then
			return ("This guest booked a %s room."):format(self.config.roomTypes[r.roomType].label)
		end
	end
	return nil
end

function MotelCore:deskSelectRoom(pid, roomId, now: number): (boolean, string)
	local s, g, err = self:deskGuard(pid, now)
	if not s then
		return fail(self, self:ownSession(pid), err)
	end
	if s.step ~= "Room" and s.step ~= "Payment" then
		return fail(self, s, "Choose Booking or Walk-in first.")
	end
	if s.mode == self.C.GuestKind.Booking and not s.verified then
		return fail(self, s, "Verify the reservation code first.")
	end
	local room = self.rooms[roomId]
	if not room then
		return false, "Unknown room."
	end
	local problem = self:deskRoomProblem(s, g, room)
	if problem then
		return fail(self, s, problem)
	end
	s.roomId = room.id
	s.step = "Payment"
	local due = self:deskDue(s, g) or 0
	local M = self.C.PayMethod
	s.method = if due <= 0 then M.Online else g.profile.methods[1]
	s.given = if due > 0 then self:cashGiven(g.profile, due) else 0
	s.message = nil
	self:bump()
	return true, ""
end

function MotelCore:deskSetMethod(pid, method, now: number): (boolean, string)
	local s, g, err = self:deskGuard(pid, now)
	if not s then
		return fail(self, self:ownSession(pid), err)
	end
	if s.step ~= "Payment" then
		return fail(self, s, "Pick a room first.")
	end
	if (self:deskDue(s, g) or 0) <= 0 then
		return fail(self, s, "Already paid online.")
	end
	if not table.find(g.profile.methods, method) then
		return fail(self, s, "This guest can't pay that way.")
	end
	s.method = method
	s.message = nil
	self:bump()
	return true, ""
end

function MotelCore:deskBack(pid, now: number): (boolean, string)
	local s = self:ownSession(pid)
	if not s then
		return false, "Open the front desk first."
	end
	s.lastActive = now
	s.notice = nil
	s.message = nil
	if s.step == "Payment" then
		s.step = "Room"
		s.roomId = nil
		s.method = nil
		s.given = nil
	elseif s.step == "Room" then
		if s.mode == self.C.GuestKind.Booking then
			s.step = "Code"
			s.verified = false
		else
			resetProgress(s)
		end
	elseif s.step == "Code" then
		resetProgress(s)
	end
	self:bump()
	return true, ""
end

-- Moves the guest into the room and records the money: one step, no yield.
function MotelCore:commitCheckIn(g, room, amount: number, pid, now: number)
	for i, id in ipairs(self.queue) do
		if id == g.id then
			table.remove(self.queue, i)
			break
		end
	end
	g.state = self.C.GuestState.Staying
	g.roomId = room.id
	g.checkedInAt = now
	g.stayUntil = now + self:dur(self.random(self.config.guests.stayMin, self.config.guests.stayMax))
	if self.random(0, 1) < self.config.guests.towelRequestChance then
		g.towelAt = now
			+ self:dur(self.random(self.config.guests.towelRequestDelayMin, self.config.guests.towelRequestDelayMax))
	end
	room.occupant = g.id
	self:planMeal(g, now)
	self.cash += amount
	self.nightStats.rent += amount
	self.nightStats.checkIns += 1
	self.totals.rent += amount
	self:emit("CheckedIn", { guestId = g.id, roomId = room.id, amount = amount, by = pid })
	self:bump()
end

--[[
	Final step: validates everything again and commits room, cash,
	reservation and check-in together. payload = { txId, change = { notes } }.
	The same txId always returns the first answer and never pays twice.
]]
function MotelCore:deskConfirm(pid, payload, now: number): (boolean, string)
	local own = self:ownSession(pid)
	local txId = if typeof(payload) == "table" then payload.txId else nil
	if typeof(txId) ~= "number" then
		return false, "Bad request."
	end
	if own and own.lastTx and own.lastTx.txId == txId then
		return own.lastTx.ok, own.lastTx.msg
	end
	local function done(s, ok: boolean, msg: string): (boolean, string)
		if s then
			s.lastTx = { txId = txId, ok = ok, msg = msg }
			self:deskMessage(s, msg, if ok then "ok" else "error")
		end
		return ok, msg
	end

	local s, g, err = self:deskGuard(pid, now)
	if not s then
		return done(own, false, err)
	end
	if s.step ~= "Payment" or not s.roomId then
		return done(s, false, "Pick a room first.")
	end
	local room = self.rooms[s.roomId]
	local problem = self:deskRoomProblem(s, g, room)
	if problem then
		-- Room changed meanwhile: keep the guest, ask for another room.
		s.roomId = nil
		s.method = nil
		s.given = nil
		s.step = "Room"
		s.notice = "RoomUnavailable"
		return done(s, false, "Room no longer available. Pick another room.")
	end
	local due = self:deskDue(s, g)
	if due == nil then
		return done(s, false, "Reservation no longer valid.")
	end
	local M = self.C.PayMethod
	local method = s.method
	if due <= 0 then
		method = M.Online
	elseif method == M.Cash then
		local given = s.given or 0
		if given < due then
			return done(s, false, ("Guest is $%d short. Ask for another way to pay."):format(due - given))
		end
		local change = payload.change
		if typeof(change) ~= "table" or #change > self.config.desk.maxChangeNotes then
			return done(s, false, "Change is incorrect")
		end
		local sum = 0
		for _, note in ipairs(change) do
			if typeof(note) ~= "number" or not table.find(self.config.desk.denominations, note) then
				return done(s, false, "Change is incorrect")
			end
			sum += note
		end
		if sum ~= given - due then
			return done(s, false, "Change is incorrect")
		end
	elseif method == M.Card then
		if not table.find(g.profile.methods, M.Card) then
			return done(s, false, "This guest has no card.")
		end
	else
		return done(s, false, "Choose how the guest pays.")
	end

	-- Commit (no yields from here on).
	local r = self:reservationFor(g)
	if r then
		r.used = true
	end
	self:commitCheckIn(g, room, due, pid, now)
	if method == M.Cash then
		self.cashierTutorialDone = true
	end
	s.guestId = nil -- the next front guest starts a fresh transaction (no "left" notice)
	resetProgress(s)
	local msg = if due > 0
		then ("%s checked into Room %d. +$%d"):format(g.profile.name, room.number, due)
		else ("%s checked into Room %d (paid online)."):format(g.profile.name, room.number)
	return done(s, true, msg)
end

local function guestLine(g): string
	local b = g.profile.booking
	if b then
		return ("I have a reservation. My code is %s."):format(b.code)
	end
	return "Do you have a room for tonight?"
end

local PAYMENT_LABEL = { Prepaid = "Prepaid", PayAtMotel = "Pay at Motel", Partial = "Partially Paid" }

-- What the terminal shows to one player.
function MotelCore:deskView(pid)
	local s = self.desk
	local view = {
		open = s ~= nil and s.owner == pid,
		busy = s ~= nil and s.owner ~= pid,
		busyBy = if s and s.owner ~= pid then s.owner else nil,
		night = self.night,
		queueLength = #self.queue,
	}
	if not view.open then
		return view
	end
	local P = self.C.Phase
	local g = self:deskGuest()
	if self.phase ~= P.Night then
		view.status = if self.phase == P.Preparation then "NotOpen" else "Closed"
	elseif not self.power then
		view.status = "PowerOut"
	elseif not g then
		view.status = "NoGuests"
	else
		view.status = "Active"
	end
	view.step = s.step
	view.mode = s.mode
	view.verified = s.verified
	view.notice = s.notice
	view.message = s.message
	view.roomId = s.roomId
	view.method = s.method
	view.denominations = self.config.desk.denominations
	if g then
		view.guest = {
			id = g.id,
			name = g.profile.name,
			line = guestLine(g),
			code = g.profile.booking and g.profile.booking.code or nil,
			patienceEndsAt = g.patienceEndsAt,
			patienceTotal = if g.queuedAt then g.patienceEndsAt - g.queuedAt else nil,
			methods = table.clone(g.profile.methods),
		}
		local r = if s.verified then self:reservationFor(g) else nil
		if r then
			view.reservation = {
				name = r.name,
				roomType = self.config.roomTypes[r.roomType].label,
				total = r.total,
				paid = r.paid,
				remaining = r.total - r.paid,
				payment = PAYMENT_LABEL[r.payment] or r.payment,
			}
		end
		local anySelectable = false
		view.rooms = {}
		for i, room in ipairs(self.rooms) do
			local status = "Ready"
			if room.occupant then
				status = "Occupied"
			elseif room.acBroken then
				status = "Out of Order"
			elseif room.trash or room.sheetsDirty then
				status = "Dirty"
			end
			local selectable = s.step == "Room" and self:deskRoomProblem(s, g, room) == nil
			if selectable then
				anySelectable = true
			end
			view.rooms[i] = {
				id = room.id,
				number = room.number,
				type = self.config.roomTypes[room.type].label,
				rate = self.config.roomTypes[room.type].rate,
				status = status,
				selectable = selectable,
			}
		end
		view.noMatch = s.step == "Room" and not anySelectable
		if s.step == "Payment" then
			local due = self:deskDue(s, g) or 0
			view.due = due
			view.given = s.given
			local hint = not self.cashierTutorialDone or self:hasRole(pid, "Receptionist")
			if s.method == self.C.PayMethod.Cash and hint and s.given and s.given >= due then
				view.changeHint = s.given - due
			end
		end
	end
	return view
end

function MotelCore:takeSupply(pid, item: string): (boolean, string)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	if item ~= self.C.Item.Sheet and item ~= self.C.Item.Towel then
		return false, "Unknown supply."
	end
	local carry = self:getCarry(pid)
	if #carry >= self:carryCapacity(pid) then
		return false, ("Your hands are full (%d/%d)."):format(#carry, self:carryCapacity(pid))
	end
	if self.stock[item] <= 0 then
		return false, ("Out of %ss. Buy a refill."):format(item:lower())
	end
	self.stock[item] -= 1
	table.insert(carry, item)
	self:bump()
	return true, ("Picked up a clean %s."):format(item:lower())
end

function MotelCore:returnSupplies(pid): (boolean, string)
	local carry = self:getCarry(pid)
	local returned = 0
	for i = #carry, 1, -1 do
		local item = carry[i]
		if item == self.C.Item.Sheet or item == self.C.Item.Towel then
			self.stock[item] += 1
			table.remove(carry, i)
			returned += 1
		end
	end
	if returned == 0 then
		return false, "Nothing to return."
	end
	self:bump()
	return true, ("Returned %d item(s) to the linen room."):format(returned)
end

function MotelCore:collectTrash(pid, roomId): (boolean, string)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	local room = self.rooms[roomId]
	if not room or not room.trash then
		return false, "No trash here."
	end
	local carry = self:getCarry(pid)
	if #carry >= self:carryCapacity(pid) then
		return false, "Your hands are full."
	end
	room.trash = false
	table.insert(carry, self.C.Item.Trash)
	self:bump()
	return true, ("Picked up trash from Room %d. Take it to the dumpster."):format(room.number)
end

function MotelCore:dumpTrash(pid): (boolean, string)
	local carry = self:getCarry(pid)
	local n = 0
	while removeOne(carry, self.C.Item.Trash) do
		n += 1
	end
	if n == 0 then
		return false, "You are not carrying trash."
	end
	self:bump()
	return true, ("Dumped %d trash bag(s)."):format(n)
end

function MotelCore:changeSheets(pid, roomId): (boolean, string)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	local room = self.rooms[roomId]
	if not room or not room.sheetsDirty then
		return false, "The sheets are already clean."
	end
	if room.occupant then
		return false, "A guest is staying here."
	end
	local carry = self:getCarry(pid)
	if not removeOne(carry, self.C.Item.Sheet) then
		return false, "Bring a clean sheet from the linen room."
	end
	room.sheetsDirty = false
	self:bump()
	local suffix = if self:isRoomReady(room) then " Room is READY." else ""
	return true, ("Changed sheets in Room %d.%s"):format(room.number, suffix)
end

function MotelCore:deliverTowel(pid, roomId): (boolean, string)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	local room = self.rooms[roomId]
	if not room or not room.towelRequest or not room.occupant then
		return false, "Nobody asked for a towel here."
	end
	local carry = self:getCarry(pid)
	if not removeOne(carry, self.C.Item.Towel) then
		return false, "Bring a clean towel from the linen room."
	end
	room.towelRequest = false -- cleared before paying: the tip is paid once
	local tip = self.config.economy.towelTip
	self.cash += tip
	self.nightStats.tips += tip
	self.totals.tips += tip
	self:bump()
	return true, ("Towel delivered to Room %d. Tip +$%d"):format(room.number, tip)
end

function MotelCore:repairAC(_pid, roomId): (boolean, string)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	local room = self.rooms[roomId]
	if not room or not room.acBroken then
		return false, "The AC works fine."
	end
	room.acBroken = false
	self:bump()
	return true, ("Repaired the AC in Room %d."):format(room.number)
end

-- Repair minigames: the prompt opens a session, the client plays it and
-- reports a win; the server applies the repair only for an open session that
-- lasted at least Config.minigame.minSeconds. kind: "AC" | "Breaker".
function MotelCore:startFix(pid, kind: string, roomId: number?, now: number): (boolean, string?)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	if kind == "AC" then
		local room = roomId and self.rooms[roomId]
		if not room or not room.acBroken then
			return false, "The AC works fine."
		end
	elseif kind == "Breaker" then
		if self.power then
			return false, "The power is already on."
		end
	elseif kind == "Sheets" then
		local room = roomId and self.rooms[roomId]
		if not room or not room.sheetsDirty then
			return false, "The sheets are already clean."
		end
		if room.occupant then
			return false, "A guest is staying here."
		end
		if not table.find(self:getCarry(pid), self.C.Item.Sheet) then
			return false, "Bring a clean sheet from the linen room."
		end
	else
		return false, "Nothing to fix."
	end
	self.fixes[pid] = { kind = kind, roomId = roomId, startedAt = now }
	return true, nil
end

function MotelCore:finishFix(pid, kind: string, roomId: number?, now: number): (boolean, string)
	local s = self.fixes[pid]
	if not s or s.kind ~= kind or s.roomId ~= roomId then
		return false, "Start the repair at the panel first."
	end
	local minimum = (self.config.minigame and self.config.minigame.minSeconds) or 0
	if now - s.startedAt < minimum then
		return false, "Too fast, try again."
	end
	self.fixes[pid] = nil
	if kind == "AC" then
		return self:repairAC(pid, roomId)
	elseif kind == "Sheets" then
		return self:changeSheets(pid, roomId)
	end
	return self:resetBreaker(pid)
end

function MotelCore:cancelFix(pid)
	self.fixes[pid] = nil
end

function MotelCore:resetBreaker(pid): (boolean, string)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	if self.power then
		return false, "The power is already on."
	end
	self.power = true
	self:emit("PowerRestored", { by = pid })
	self:bump()
	return true, "Breaker reset. Power restored!"
end

-- Shop catalog lookup (Config.shop).
function MotelCore:shopItem(itemId: string)
	for _, item in ipairs(self.config.shop or {}) do
		if item.id == itemId then
			return item
		end
	end
	return nil
end

-- Buys one catalog item for the whole team. Validates phase, ownership and
-- cash, then applies everything in one step (no yields).
function MotelCore:buyItem(_pid, itemId: string): (boolean, string)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	local item = self:shopItem(itemId)
	if not item then
		return false, "That item is not sold here."
	end
	if item.trolley and self.trolley then
		return false, "The team already owns a trolley."
	end
	if self.cash < item.cost then
		return false, ("Need $%d for %s."):format(item.cost, item.name)
	end
	self.cash -= item.cost
	self.nightStats.purchases += item.cost
	local parts = {}
	if item.sheets and item.sheets > 0 then
		self.stock.Sheet += item.sheets
		table.insert(parts, ("+%d sheets"):format(item.sheets))
	end
	if item.towels and item.towels > 0 then
		self.stock.Towel += item.towels
		table.insert(parts, ("+%d towels"):format(item.towels))
	end
	if item.food then
		local keys = {}
		for k in pairs(item.food) do
			table.insert(keys, k)
		end
		table.sort(keys)
		for _, ing in ipairs(keys) do
			self.pantry[ing] = (self.pantry[ing] or 0) + item.food[ing]
			table.insert(parts, ("+%d %s"):format(item.food[ing], ing:lower()))
		end
	end
	if item.trolley then
		self.trolley = true
		table.insert(parts, ("everyone carries %d"):format(self.config.supplies.trolleyCarryCapacity))
	end
	self:emit("Purchase", { itemId = item.id })
	self:bump()
	return true, ("Bought %s: %s. -$%d"):format(item.name, table.concat(parts, ", "), item.cost)
end

function MotelCore:buyRefill(pid): (boolean, string)
	return self:buyItem(pid, "refill")
end

function MotelCore:buyTrolley(pid): (boolean, string)
	return self:buyItem(pid, "trolley")
end

function MotelCore:setReady(pid): (boolean, string)
	if self.phase ~= self.C.Phase.Preparation then
		return false, "You can only skip during Preparation."
	end
	if self.ready[pid] then
		return false, "Already marked ready."
	end
	self.ready[pid] = true
	self:bump()
	return true, "Ready! Night starts when everyone is ready."
end

function MotelCore:restart(_pid, now: number): (boolean, string)
	if self.phase ~= self.C.Phase.RunEnded then
		return false, "Restart is available when the run ends."
	end
	self:resetRun(now)
	return true, "New run started."
end

-- Player left mid-run: unused clean supplies go back to stock.
function MotelCore:playerLeft(pid)
	local carry = self.carries[pid]
	if carry then
		for _, item in ipairs(carry) do
			if item == self.C.Item.Sheet or item == self.C.Item.Towel then
				self.stock[item] += 1
			end
		end
	end
	self.carries[pid] = nil
	self.ready[pid] = nil
	self.roles[pid] = nil
	self:deskRelease(pid)
	self:bump()
end

------------------------------------------------------------------------
-- Kitchen (room service) and soft roles
------------------------------------------------------------------------

function MotelCore:recipe(id)
	for _, r in ipairs(self.config.recipes) do
		if r.id == id then
			return r
		end
	end
	return nil
end

local function emptySlot(kind: string)
	return { kind = kind, recipe = nil, state = "Empty", startedAt = nil, readyAt = nil, burnAt = nil, cook = nil }
end

function MotelCore:resetKitchen()
	self.pantry = table.clone(self.config.kitchen.startingStock)
	self:clearStove()
end

function MotelCore:clearStove()
	self.slots = {}
	for i, kind in ipairs(self.config.kitchen.slots) do
		self.slots[i] = emptySlot(kind)
	end
end

-- Soft roles: a solo player has every perk.
function MotelCore:hasRole(pid, role: string): boolean
	return self.playerCount <= 1 or self.roles[pid] == role
end

function MotelCore:roleDef(role)
	for _, r in ipairs(self.config.roles) do
		if r.id == role then
			return r
		end
	end
	return nil
end

function MotelCore:setRole(pid, role): (boolean, string)
	local def = self:roleDef(role)
	if not def then
		return false, "Unknown role."
	end
	if self.phase ~= self.C.Phase.Preparation then
		return false, "Pick your role during Preparation."
	end
	if self.roles[pid] == role then
		return true, ("You are already the %s."):format(def.label)
	end
	self.roles[pid] = role
	self:emit("RoleChanged", { by = pid, role = role })
	self:bump()
	return true, ("You are the %s! Perk: %s."):format(def.label, def.perk)
end

-- Ticks stove timers and meal order deadlines.
function MotelCore:updateKitchen(now: number)
	for i, slot in ipairs(self.slots) do
		if slot.state == "Cooking" and now >= slot.readyAt then
			slot.state = "Ready"
			self:emit("DishReady", { slot = i, recipe = slot.recipe })
			self:bump()
		end
		if slot.state == "Ready" and slot.burnAt and now >= slot.burnAt then
			slot.state = "Burnt"
			if self.nightStats then
				self.nightStats.burnt += 1
			end
			self:emit("DishBurnt", { slot = i, recipe = slot.recipe })
			self:bump()
		end
	end
	for _, room in ipairs(self.rooms) do
		local order = room.mealOrder
		if order and now >= order.expiresAt then
			room.mealOrder = nil
			self.nightStats.missedMeals += 1
			self:emit("MealMissed", { roomId = room.id, recipe = order.recipe })
			self:bump()
		end
	end
end

-- Called when a guest checks in: maybe they will order a meal later.
function MotelCore:planMeal(g, now: number)
	local k = self.config.kitchen
	if self.random(0, 1) < k.orderChance then
		local list = self.config.recipes
		g.mealAt = now + self:dur(self.random(k.orderDelayMin, k.orderDelayMax))
		g.mealRecipe = list[math.clamp(math.floor(self.random(1, #list + 1)), 1, #list)].id
	end
end

-- Called from updateGuests for a staying guest.
function MotelCore:placeMealOrder(g, now: number)
	if not (g.mealAt and now >= g.mealAt) then
		return
	end
	g.mealAt = nil
	local room = self.rooms[g.roomId]
	if room and room.occupant == g.id and not room.mealOrder then
		room.mealOrder = {
			recipe = g.mealRecipe,
			placedAt = now,
			expiresAt = now + self:dur(self.config.kitchen.orderPatience),
		}
		-- A hungry guest waits for the food: the stay lasts at least until
		-- the order deadline, so the whole delivery window is usable.
		g.stayUntil = math.max(g.stayUntil, room.mealOrder.expiresAt + self:dur(2))
		self:emit("MealOrder", { roomId = room.id, recipe = g.mealRecipe })
		self:bump()
	end
end

function MotelCore:startCook(pid, slotIndex, recipeId, now: number): (boolean, string)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	local slot = self.slots[slotIndex]
	if not slot then
		return false, "Unknown cooking spot."
	end
	local r = self:recipe(recipeId)
	if not r then
		return false, "Unknown recipe."
	end
	if slot.state ~= "Empty" then
		return false, "That spot is busy."
	end
	if r.station ~= slot.kind then
		return false, ("%s is made on the %s."):format(r.name, if r.station == "Board" then "prep board" else "burner")
	end
	for item, n in pairs(r.ingredients) do
		if (self.pantry[item] or 0) < n then
			return false, ("Not enough %s. Buy more at the shop (Food tab)."):format(item:lower())
		end
	end
	-- Commit: ingredients and the cooking spot in one step.
	for item, n in pairs(r.ingredients) do
		self.pantry[item] -= n
	end
	local perks = self.config.rolePerks
	local chef = self:hasRole(pid, "Chef")
	local cookTime = r.cookTime * (if chef then perks.chefCookMultiplier else 1)
	slot.recipe = r.id
	slot.state = "Cooking"
	slot.startedAt = now
	slot.readyAt = now + self:dur(cookTime)
	slot.burnAt = if slot.kind == "Burner"
		then slot.readyAt + self:dur(self.config.kitchen.burnAfter * (if chef then perks.chefBurnMultiplier else 1))
		else nil
	slot.cook = pid
	self:bump()
	return true, ("Cooking %s..."):format(r.name)
end

function MotelCore:collectDish(pid, slotIndex): (boolean, string)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	local slot = self.slots[slotIndex]
	if not slot or slot.state == "Empty" then
		return false, "Nothing to pick up there."
	elseif slot.state == "Cooking" then
		return false, "Not ready yet."
	elseif slot.state == "Burnt" then
		return false, "It burned! Throw it away and cook again."
	end
	local carry = self:getCarry(pid)
	local cap = self:carryCapacity(pid)
	if #carry >= cap then
		return false, ("Your hands are full (%d/%d)."):format(#carry, cap)
	end
	local r = self:recipe(slot.recipe)
	table.insert(carry, self.C.DishPrefix .. slot.recipe)
	self.slots[slotIndex] = emptySlot(slot.kind) -- cleared together with the pickup
	self:bump()
	return true, ("Picked up %s. Take it to the room!"):format(r and r.name or "the dish")
end

function MotelCore:discardDish(_pid, slotIndex): (boolean, string)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	local slot = self.slots[slotIndex]
	if not slot or slot.state == "Empty" then
		return false, "Nothing to throw away."
	elseif slot.state == "Cooking" then
		return false, "Still cooking."
	end
	local burnt = slot.state == "Burnt"
	self.slots[slotIndex] = emptySlot(slot.kind)
	self:bump()
	return true, if burnt then "Burnt food thrown away." else "Dish thrown away."
end

function MotelCore:deliverMeal(pid, roomId, now: number): (boolean, string)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	local room = self.rooms[roomId]
	local order = room and room.mealOrder
	if not order or not room.occupant then
		return false, "Nobody ordered food here."
	end
	local r = self:recipe(order.recipe)
	local carry = self:getCarry(pid)
	if not removeOne(carry, self.C.DishPrefix .. order.recipe) then
		return false, ("Room %d ordered %s. Cook it in the kitchen."):format(room.number, r.name)
	end
	room.mealOrder = nil -- cleared before paying: the meal is paid once
	local k = self.config.kitchen
	local tip = if now - order.placedAt <= self:dur(k.fastWindow) then k.fastTip else 0
	local amount = r.price + tip
	self.cash += amount
	self.nightStats.meals += amount
	self.totals.meals += amount
	self:emit("MealDelivered", { roomId = room.id, recipe = order.recipe, by = pid })
	self:bump()
	if tip > 0 then
		return true, ("%s delivered to Room %d. +$%d (fast tip +$%d)"):format(r.name, room.number, r.price, tip)
	end
	return true, ("%s delivered to Room %d. +$%d"):format(r.name, room.number, r.price)
end

-- Room door: hand over whatever the room asked for (towel or meal).
function MotelCore:deliver(pid, roomId, now: number): (boolean, string)
	local room = self.rooms[roomId]
	if not room then
		return false, "Unknown room."
	end
	local carry = self:getCarry(pid)
	if room.towelRequest and (count(carry, self.C.Item.Towel) > 0 or not room.mealOrder) then
		return self:deliverTowel(pid, roomId)
	end
	if room.mealOrder then
		return self:deliverMeal(pid, roomId, now)
	end
	return false, "Nothing to deliver here."
end

------------------------------------------------------------------------
-- Snapshot for clients
------------------------------------------------------------------------

function MotelCore:snapshot(pid)
	local stoveView = {}
	for i, slot in ipairs(self.slots) do
		stoveView[i] = {
			kind = slot.kind,
			recipe = slot.recipe,
			state = slot.state,
			startedAt = slot.startedAt,
			readyAt = slot.readyAt,
			burnAt = slot.burnAt,
		}
	end
	local rooms = {}
	for i, room in ipairs(self.rooms) do
		rooms[i] = {
			id = room.id,
			number = room.number,
			type = room.type,
			mealOrder = if room.mealOrder
				then {
					recipe = room.mealOrder.recipe,
					placedAt = room.mealOrder.placedAt,
					expiresAt = room.mealOrder.expiresAt,
				}
				else nil,
			occupied = room.occupant ~= nil,
			trash = room.trash,
			sheetsDirty = room.sheetsDirty,
			acBroken = room.acBroken,
			towelRequest = room.towelRequest,
			ready = self:isRoomReady(room),
		}
	end
	local front = self.queue[1] and self.guests[self.queue[1]]
	local carry = table.clone(self.carries[pid] or {})
	local readyCount = 0
	for _ in pairs(self.ready) do
		readyCount += 1
	end
	return {
		runId = self.runId,
		phase = self.phase,
		phaseStartedAt = self.phaseStartedAt,
		phaseEndsAt = self.phaseEndsAt,
		night = self.night,
		nightsSurvived = self.nightsSurvived,
		bestNights = self.bestNights,
		complete = self.complete,
		cash = self.cash,
		bill = self.plan.bill,
		plannedGuests = self.plan.guestCount,
		forecast = self.plan.forecast,
		rainForecast = self.plan.rain,
		planPlayers = self.plan.playerCount,
		playerCount = self.playerCount,
		stock = { Sheet = self.stock.Sheet, Towel = self.stock.Towel },
		trolley = self.trolley,
		carry = carry,
		carryCapacity = self:carryCapacity(pid),
		sheetsCarried = count(carry, self.C.Item.Sheet),
		power = self.power,
		rain = self.rain,
		rooms = rooms,
		queueLength = #self.queue,
		frontPatienceEndsAt = front and front.patienceEndsAt or nil,
		readyCount = readyCount,
		isReady = self.ready[pid] == true,
		nightStats = table.clone(self.nightStats),
		report = self.lastReport and table.clone(self.lastReport) or nil,
		desk = self:deskView(pid),
		pantry = table.clone(self.pantry),
		slots = stoveView,
		role = self.roles[pid],
		soloRoles = self.playerCount <= 1,
	}
end

return MotelCore
