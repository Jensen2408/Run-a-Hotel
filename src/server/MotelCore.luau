--!nonstrict
--[[
	MotelCore: the authoritative game state for one motel run.

	Pure Luau: no Roblox services, no yields. Time is passed in as `now`
	(the server uses workspace:GetServerTimeNow()). Every public mutation
	runs to completion without yielding, so a check-in assigns guest, room
	and payment in one step, and two requests that arrive back to back can
	never both consume the same stock, room or tip.

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
		self.rooms[i] = {
			id = i,
			occupant = nil,
			trash = false,
			sheetsDirty = false,
			acBroken = false,
			towelRequest = false,
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
	self.totals = { served = 0, walkouts = 0, unserved = 0, rent = 0, tips = 0 }
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

function MotelCore:buildNightPlan(night: number, playerCount: number)
	local cfg = self.config
	local nightCfg = cfg.nights[night]
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
		bill = bill,
		arrivals = arrivals, -- unscaled seconds into the night
		rain = nightCfg.rain == true,
		forecast = nightCfg.forecast or "",
		events = copyEvents(nightCfg.events),
	}
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
		rent = 0,
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
	self:setPhase(self.C.Phase.Preparation, now, self.config.phases.preparation)
end

function MotelCore:enterNight(now: number)
	self.rain = self.plan.rain
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

	local plan = self.plan
	local report = {
		night = self.night,
		rent = self.nightStats.rent,
		tips = self.nightStats.tips,
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
	report.isFinalNight = self.night >= #self.config.nights
	self.lastReport = report
	self.bestNights = math.max(self.bestNights, self.nightsSurvived)
	self:setPhase(self.C.Phase.Report, now, self.config.phases.report)
end

function MotelCore:endReport(now: number)
	local report = self.lastReport
	if not report.passed then
		self.complete = false
		self:setPhase(self.C.Phase.RunEnded, now, nil)
	elseif self.night >= #self.config.nights then
		self.complete = true
		self:setPhase(self.C.Phase.RunEnded, now, nil)
	else
		self.night += 1
		self:enterPreparation(now)
	end
end

------------------------------------------------------------------------
-- Guests
------------------------------------------------------------------------

function MotelCore:spawnGuest(now: number)
	self.nextGuestId += 1
	local g = {
		id = self.nextGuestId,
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
			self:spawnGuest(now)
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

function MotelCore:carryCapacity(): number
	local s = self.config.supplies
	return if self.trolley then s.trolleyCarryCapacity else s.baseCarryCapacity
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

-- Checks everything about a check-in except the room choice.
function MotelCore:checkInPrecheck(): (boolean, string?, any)
	local P = self.C.Phase
	if self.phase == P.Closing then
		return false, "Closing time: no new check-ins.", nil
	elseif self.phase ~= P.Night then
		return false, "Check-in opens at Night.", nil
	end
	if not self.power then
		return false, "Power is out! Reset the breaker first.", nil
	end
	local frontId = self.queue[1]
	local guest = frontId and self.guests[frontId]
	if not guest or guest.state ~= self.C.GuestState.Queued then
		return false, "No guest is waiting at the desk.", nil
	end
	return true, nil, guest
end

function MotelCore:checkIn(pid, roomId, now: number): (boolean, string)
	local ok, err, guest = self:checkInPrecheck()
	if not ok then
		return false, err :: string
	end
	local room = self.rooms[roomId]
	if not room then
		return false, "Unknown room."
	end
	if not self:isRoomReady(room) then
		return false, ("Room %d is not ready (%s)."):format(room.id, table.concat(self:roomBlockers(room), ", "))
	end

	-- Commit: guest, room and payment in one step.
	table.remove(self.queue, 1)
	guest.state = self.C.GuestState.Staying
	guest.roomId = room.id
	guest.checkedInAt = now
	guest.stayUntil = now + self:dur(self.random(self.config.guests.stayMin, self.config.guests.stayMax))
	if self.random(0, 1) < self.config.guests.towelRequestChance then
		guest.towelAt = now
			+ self:dur(self.random(self.config.guests.towelRequestDelayMin, self.config.guests.towelRequestDelayMax))
	end
	room.occupant = guest.id
	local rent = self.config.economy.rent
	self.cash += rent
	self.nightStats.rent += rent
	self.totals.rent += rent
	self:emit("CheckedIn", { guestId = guest.id, roomId = room.id, by = pid })
	self:bump()
	return true, ("Guest checked into Room %d. +$%d"):format(room.id, rent)
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
	if #carry >= self:carryCapacity() then
		return false, ("Your hands are full (%d/%d)."):format(#carry, self:carryCapacity())
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
	if #carry >= self:carryCapacity() then
		return false, "Your hands are full."
	end
	room.trash = false
	table.insert(carry, self.C.Item.Trash)
	self:bump()
	return true, ("Picked up trash from Room %d. Take it to the dumpster."):format(room.id)
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
	return true, ("Changed sheets in Room %d.%s"):format(room.id, suffix)
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
	return true, ("Towel delivered to Room %d. Tip +$%d"):format(room.id, tip)
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
	return true, ("Repaired the AC in Room %d."):format(room.id)
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

function MotelCore:buyRefill(_pid): (boolean, string)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	local s = self.config.supplies
	if self.cash < s.refillCost then
		return false, ("Need $%d for a refill."):format(s.refillCost)
	end
	self.cash -= s.refillCost
	self.nightStats.purchases += s.refillCost
	self.stock.Sheet += s.refillSheets
	self.stock.Towel += s.refillTowels
	self:bump()
	return true, ("Bought refill: +%d sheets, +%d towels. -$%d"):format(s.refillSheets, s.refillTowels, s.refillCost)
end

function MotelCore:buyTrolley(_pid): (boolean, string)
	local ok, err = self:requireActive()
	if not ok then
		return false, err
	end
	local s = self.config.supplies
	if self.trolley then
		return false, "The team already owns a trolley."
	end
	if self.cash < s.trolleyCost then
		return false, ("Need $%d for a trolley."):format(s.trolleyCost)
	end
	self.cash -= s.trolleyCost
	self.nightStats.purchases += s.trolleyCost
	self.trolley = true
	self:bump()
	return true, ("Bought a trolley! Everyone can carry %d items. -$%d"):format(s.trolleyCarryCapacity, s.trolleyCost)
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
	self:bump()
end

------------------------------------------------------------------------
-- Snapshot for clients
------------------------------------------------------------------------

function MotelCore:snapshot(pid)
	local rooms = {}
	for i, room in ipairs(self.rooms) do
		rooms[i] = {
			id = room.id,
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
		phaseEndsAt = self.phaseEndsAt,
		night = self.night,
		totalNights = #self.config.nights,
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
		carryCapacity = self:carryCapacity(),
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
	}
end

return MotelCore
