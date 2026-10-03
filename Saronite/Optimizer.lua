-- Best setup from the character's own gear plus the phase's gems and
-- enchants. A line-by-line port of the bot's
-- internal/gear/analysis/optimize.go: the tests run both on the same
-- characters and require identical answers.
local _, ns = ...

local Rules = ns.Rules
local Character = ns.Character

local Optimizer = {}
ns.Optimizer = Optimizer

local EPS = 1e-6 -- ties are broken the same way as in the Go code
local GEM_POINTS = 16
local META_GEM_POINTS = 3

local SINGLE_SLOTS = {
	HEAD = 1, NECK = 2, SHOULDER = 3, CLOAK = 15, CHEST = 5, ROBE = 5,
	WRIST = 9, HAND = 10, WAIST = 6, LEGS = 7, FEET = 8,
	RANGED = 18, RANGEDRIGHT = 18, THROWN = 18, RELIC = 18,
}
local SINGLE_TYPES = {}
for typ in pairs(SINGLE_SLOTS) do SINGLE_TYPES[#SINGLE_TYPES + 1] = typ end
table.sort(SINGLE_TYPES)

local ENCHANT_SLOTS = { [1] = true, [3] = true, [15] = true, [5] = true, [9] = true, [10] = true, [7] = true,
	[8] = true, [16] = true, [17] = true, [18] = true, [11] = true, [12] = true }

local NO_GEM = { id = 0, stats = {} }
local NO_ENCHANT = { id = 0, stats = {} }

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	return keys
end

local function isWeapon(t)
	return t == "WEAPON" or t == "2HWEAPON" or t == "WEAPONMAINHAND" or t == "WEAPONOFFHAND"
end

-- stable sort (table.sort is not)
local function stableSort(list, less)
	for i, v in ipairs(list) do list[i] = { v = v, i = i } end
	table.sort(list, function(a, b)
		if less(a.v, b.v) then return true end
		if less(b.v, a.v) then return false end
		return a.i < b.i
	end)
	for i, w in ipairs(list) do list[i] = w.v end
end

local function detectSpec(c)
	local trees = Character.ActiveTalents(c)
	local points, best, total = {}, nil, 0
	for i, t in ipairs(trees) do
		points[i] = t.points
		total = total + t.points
		if not best or t.points > points[best] then best = i end
	end
	local classSpecs = Rules.specs[c.class]
	if not classSpecs or not best or total < 10 or trees[best].tab < 1 or trees[best].tab > 3 then
		return points, nil
	end
	local s = classSpecs[trees[best].tab]
	return points, { name = s.name, nameEN = s.nameEN, role = s.role, maybeTank = s.maybeTank, tab = trees[best].tab }
end
Optimizer.DetectSpec = detectSpec

local function bonusHit(c, kind, hc)
	local pct = 0
	local ranks = {}
	for _, t in ipairs(Character.ActiveTalents(c)) do ranks[t.tab] = t.ranks end
	for _, t in ipairs(Rules.hitTalents[c.class] or {}) do
		if t.kinds[kind] and (not t.applies or t.applies(hc)) then
			local r = ranks[t.tab] or ""
			if t.index < string.len(r) then
				local rank = tonumber(string.sub(r, t.index + 1, t.index + 1)) or 0
				if rank > 0 and rank <= 5 then pct = pct + rank * t.perRank end
			end
		end
	end
	if c.race == "Draenei" then pct = pct + 1 end
	return pct
end

local function specLabel(spec, tank)
	if spec.maybeTank and tank then return spec.name .. " (танк)" end
	if spec.maybeTank then return spec.name .. " (ДД)" end
	return spec.name
end

-- optimizer state -----------------------------------------------------------

local O = {}
O.__index = O

function O:tick()
	self.evals = self.evals + 1
	if self.yield and self.evals % 150 == 0 then self.yield() end
end

function O:statValue(stats)
	local v = 0
	local w = self.w
	for code, x in pairs(stats) do
		if code ~= "HIT" and code ~= "EXP" and code ~= "DPS" and code ~= "FAP" then
			v = v + (w[code] or 0) * x
		end
	end
	return v
end

function O:gemPool()
	local counts = {}
	for _, s in pairs(self.plan.slots) do
		for _, id in ipairs(s.gems or {}) do counts[id] = (counts[id] or 0) + 1 end
	end
	local pool = {}
	for id, n in pairs(counts) do
		local g = self.data.gems[id]
		if g and g.color ~= "prismatic" and not Rules.IsPureCapGem(g) then
			pool[#pool + 1] = { gem = g, count = n }
		end
	end
	table.sort(pool, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.gem.id < b.gem.id
	end)
	return pool
end

function O:prepare()
	local c, data = self.c, self.data
	self.gems, self.metas, self.gemUnit = {}, {}, 0
	for _, id in ipairs(sortedKeys(data.gems)) do
		local g = data.gems[id]
		if not g.profession or c.professions[g.profession] then
			if g.color == "meta" then
				if next(g.stats) then self.metas[#self.metas + 1] = g end
			else
				self.gems[#self.gems + 1] = g
				if not Rules.IsPureCapGem(g) then
					self.gemUnit = math.max(self.gemUnit, self:statValue(Rules.ExpandAll(g.stats)) / GEM_POINTS)
				end
			end
		end
	end

	local role = self.spec.role
	self.hitCapPct, self.hitPerPct, self.hitKind = 0, 0, nil
	if role == Rules.MELEE or role == Rules.TANK then
		self.hitKind, self.hitPerPct, self.hitCapPct = Rules.HIT_MELEE, Rules.meleeHitPerPct, Rules.meleeHitCap
	elseif role == Rules.RANGED then
		self.hitKind, self.hitPerPct, self.hitCapPct = Rules.HIT_RANGED, Rules.meleeHitPerPct, Rules.meleeHitCap
	elseif role == Rules.CASTER then
		self.hitKind, self.hitPerPct, self.hitCapPct = Rules.HIT_SPELL, Rules.spellHitPerPct, Rules.spellHitCap
	end

	self.hitPre = math.max(self.w.HIT or 0, 1.15 * self.gemUnit)
	self.expPre = math.max(self.w.EXP or 0, 1.15 * self.gemUnit)
	self.hitPost, self.expPost, self.expCap2 = 0, 0, 0
	if role == Rules.HEALER then self.hitPre, self.expPre = 0, 0 end
	if role ~= Rules.MELEE and role ~= Rules.TANK then self.expPre = 0 end
	if self.tank then
		self.expPost = self.w.EXP or 0
		self.expCap2 = 56
	end

	local s = c.stats
	local gear = self:gearStats(self:currentSetup())
	local ratingKey = ({ melee = "hitMelee", ranged = "hitRanged", spell = "hitSpell" })[self.hitKind or "melee"]
	self.baseHit = math.max(0, (s[ratingKey] or 0) - (gear.HIT or 0))
	self.baseExp = math.max(0, (s.expertise or 0) - (gear.EXP or 0))
	self.expTalents = math.max(0, (s.expMH or 0) - math.floor((s.expertise or 0) / Rules.expertisePerPoint))
end

function O:candidates(match)
	local out, seen = {}, {}
	for _, it in ipairs(self.c.items) do
		if not it.unusable and it.type ~= "" and match(it) then
			local key = it.loc .. "/" .. it.slot
			if not seen[key] then
				seen[key] = true
				out[#out + 1] = it
			end
		end
	end
	return out
end

function O:canDualWield()
	local class = self.c.class
	if class == "WARRIOR" or class == "ROGUE" or class == "DEATHKNIGHT" or class == "HUNTER" then return true end
	return class == "SHAMAN" and self.spec.tab == 2
end

function O:titansGrip()
	if self.c.class ~= "WARRIOR" then return false end
	for _, t in ipairs(Character.ActiveTalents(self.c)) do
		if t.tab == 2 and string.len(t.ranks) > 22 and string.sub(t.ranks, 23, 23) ~= "0" then return true end
	end
	return false
end

function O:isMH(it)
	return it.type == "2HWEAPON" or it.type == "WEAPON" or it.type == "WEAPONMAINHAND"
end

function O:isOH(it)
	local t = it.type
	if t == "WEAPONOFFHAND" or t == "WEAPON" then return self:canDualWield() end
	if t == "SHIELD" then
		local class = self.c.class
		return class == "WARRIOR" or class == "PALADIN" or class == "SHAMAN"
	end
	if t == "HOLDABLE" then return true end
	if t == "2HWEAPON" then return self:titansGrip() end
	return false
end

function O:knownGem(id)
	return self.data.gems[id] or { id = id, stats = self.c.gemStats[id] or {} }
end

function O:currentSetup()
	local out = {}
	for slot, it in pairs(Character.Equipped(self.c)) do
		local s = { item = it, sockets = it.sockets, gems = {} }
		if self.data.enchants[it.enchant] then
			s.enchant = self.data.enchants[it.enchant]
		elseif it.enchant ~= 0 then
			s.enchant = { id = it.enchant, stats = {} }
		else
			s.enchant = NO_ENCHANT
		end
		local n = string.len(it.sockets)
		for i = 1, 4 do
			local id = it.gems[i]
			if id == 0 then
				if i <= n then s.gems[#s.gems + 1] = NO_GEM end
			else
				if i > n then s.sockets = s.sockets .. "P" end
				s.gems[#s.gems + 1] = self:knownGem(id)
			end
		end
		out[slot] = s
	end
	return out
end

function O:enchantFor(it, slot)
	if not ENCHANT_SLOTS[slot] then return NO_ENCHANT end
	local c = self.c
	if slot == 17 and not isWeapon(it.type) and it.type ~= "SHIELD" then return NO_ENCHANT end
	if slot == 18 and c.class ~= "HUNTER" then return NO_ENCHANT end
	if (slot == 11 or slot == 12) and not c.professions.ENCHANTING then return NO_ENCHANT end
	local plan = self.plan.slots[Rules.bisSlots[slot]]
	local rec = plan and self.data.enchants[plan.enchant]
	if not rec or (rec.profession and not c.professions[rec.profession]) then return NO_ENCHANT end
	if slot == 16 and Rules.TwoHandOnly(rec) and it.type ~= "2HWEAPON" then return NO_ENCHANT end
	return rec
end

function O:bestMeta()
	for _, p in ipairs(self:gemPool()) do
		if p.gem.color == "meta" and (not p.gem.profession or self.c.professions[p.gem.profession]) then
			return p.gem
		end
	end
	return self.metas[1]
end

function O:defaultGem(socket)
	if socket == "M" then
		if #self.metas > 0 then return self:bestMeta() end
		return NO_GEM
	end
	local best, bestV = NO_GEM, -math.huge
	for _, g in ipairs(self.gems) do
		if g.color ~= "prismatic" and not Rules.IsPureCapGem(g) then
			local v = self:statValue(Rules.ExpandAll(g.stats))
			if v > bestV then best, bestV = g, v end
		end
	end
	return best
end

function O:newSlot(it, slot)
	local s = { item = it, sockets = it.sockets, needsBuckle = false }
	local n = string.len(it.sockets)
	if slot == 6 then
		s.sockets = s.sockets .. "P"
		s.needsBuckle = n >= 4 or it.gems[n + 1] == 0
	end
	if (slot == 9 or slot == 10) and self.c.professions.BLACKSMITHING then
		s.sockets = s.sockets .. "P"
	end
	if string.len(s.sockets) > 4 then s.sockets = string.sub(s.sockets, 1, 4) end
	s.enchant = self:enchantFor(it, slot)
	s.gems = {}
	for i = 1, string.len(s.sockets) do
		s.gems[i] = self:defaultGem(string.sub(s.sockets, i, i))
	end
	return s
end

function O:weaponValue(it, slot)
	local w, stats = self.w, it.stats
	local dps = stats.DPS or 0
	local v = (w.FAP or 0) * (stats.FAP or 0)
	if slot == 16 then v = v + (w.MHDPS or 0) * dps
	elseif slot == 17 then v = v + (w.OHDPS or 0) * dps
	elseif slot == 18 then v = v + (w.RDPS or 0) * dps
	end
	return v
end

function O:itemValue(it, slot)
	local stats = Rules.ExpandAll(it.stats)
	local v = self:statValue(stats)
	v = v + (self.hitPre + self.hitPost) / 2 * (stats.HIT or 0)
	v = v + (self.expPre + self.expPost) / 2 * (stats.EXP or 0)
	v = v + self:weaponValue(it, slot)
	v = v + string.len(it.sockets) * self.gemUnit * GEM_POINTS
	local ench = self:enchantFor(it, slot)
	if ench.id ~= 0 then v = v + self:statValue(Rules.ExpandAll(ench.stats)) end
	return v
end

function O:gearStats(setup)
	local stats = {}
	local function add(m)
		for k, v in pairs(Rules.ExpandAll(m)) do stats[k] = (stats[k] or 0) + v end
	end
	for _, s in pairs(setup) do
		add(s.item.stats)
		add(s.enchant.stats)
		local base = s.item.sockets
		local matched = string.len(base) > 0
		for i, g in ipairs(s.gems) do
			add(g.stats)
			if i <= string.len(base) and (g.id == 0 or not Rules.Fits(g, string.sub(base, i, i))) then
				matched = false
			end
		end
		if matched then add(s.item.socketBonus) end
	end
	return stats
end

function O:metaActive(setup)
	local meta = NO_GEM
	local counts = { red = 0, yellow = 0, blue = 0 }
	for _, s in pairs(setup) do
		for _, g in ipairs(s.gems) do
			if g.color == "meta" then
				meta = g
			else
				for _, color in ipairs({ "red", "yellow", "blue" }) do
					if Rules.Counts(g, color) then counts[color] = counts[color] + 1 end
				end
			end
		end
	end
	if meta.id == 0 then return false, meta end
	for color, n in pairs(meta.requires or {}) do
		if counts[color] < n then return false, meta end
	end
	return true, meta
end

function O:hitContext(setup)
	local hc = { specTab = self.spec.tab, oneHanded = false, dualWield = false }
	if setup[16] then hc.oneHanded = setup[16].item.type == "WEAPON" or setup[16].item.type == "WEAPONMAINHAND" end
	if setup[17] then hc.dualWield = isWeapon(setup[17].item.type) end
	return hc
end

function O:totals(setup)
	self:tick()
	local stats = self:gearStats(setup)
	local t = { score = 0, hitPct = 0, hitCap = 0, expSkill = 0, expCap = 0 }
	local v = self:statValue(stats)
	for slot, s in pairs(setup) do v = v + self:weaponValue(s.item, slot) end

	local hc = self:hitContext(setup)
	if self.hitCapPct > 0 and self.hitPre > 0 then
		local talent = bonusHit(self.c, self.hitKind, hc)
		local rating = self.baseHit + (stats.HIT or 0)
		local total = rating + talent * self.hitPerPct
		local capRating = self.hitCapPct * self.hitPerPct
		local post = self.hitPost
		if self.spec.role == Rules.MELEE and hc.dualWield and not self.tank then post = self.w.HIT or 0 end
		v = v + self.hitPre * math.min(total, capRating) + post * math.max(0, total - capRating)
		v = v - self:shortfall(total, capRating)
		t.hitPct = rating / self.hitPerPct + talent
		t.hitRating, t.hitTalent = rating, talent
		t.hitCap = self.hitCapPct
	end

	if self.expPre > 0 then
		local epp = Rules.expertisePerPoint
		local rating = self.baseExp + (stats.EXP or 0)
		local total = rating + self.expTalents * epp
		local capRating = Rules.expertiseCap * epp
		v = v + self.expPre * math.min(total, capRating)
		v = v - self:shortfall(total, capRating)
		if self.expCap2 > 0 then
			v = v + self.expPost * math.max(0, math.min(total, self.expCap2 * epp) - capRating)
		end
		t.expSkill = math.floor(rating / epp) + self.expTalents
		t.expCap = Rules.expertiseCap
		t.expRating, t.expTalent = rating, self.expTalents
	end

	local ok, meta = self:metaActive(setup)
	if ok then
		v = v + self:statValue(meta.stats) + META_GEM_POINTS * self.gemUnit * GEM_POINTS
	elseif meta.id ~= 0 then
		v = v - self:statValue(meta.stats)
	end
	t.score = v
	return t
end

-- By the book a cap is always closed, even with a little excess: staying
-- under it costs as much as a whole gem.
function O:shortfall(total, capRating)
	if total < capRating then return self.gemUnit * GEM_POINTS end
	return 0
end

function O:pickPair(setup, items, a, b)
	local used = {}
	for _, slot in ipairs({ a, b }) do
		if setup[slot] then used[setup[slot].item.id] = true end
	end
	local values = {}
	for _, it in ipairs(items) do values[it] = self:itemValue(it, a) end
	stableSort(items, function(x, y) return values[x] > values[y] end)
	for _, slot in ipairs({ a, b }) do
		if not setup[slot] then
			for _, it in ipairs(items) do
				if not used[it.id] then
					used[it.id] = true
					setup[slot] = self:newSlot(it, slot)
					break
				end
			end
		end
	end
end

function O:pickWeapons(setup)
	local mhs = self:candidates(function(it) return self:isMH(it) end)
	local ohs = self:candidates(function(it) return self:isOH(it) end)
	local bestValue, bestMH, bestOH = -math.huge, nil, nil
	local function consider(mh, oh, value)
		if value > bestValue then bestValue, bestMH, bestOH = value, mh, oh end
	end
	for _, mh in ipairs(mhs) do
		local value = self:itemValue(mh, 16)
		consider(mh, nil, value)
		if not (mh.type == "2HWEAPON" and not self:titansGrip()) then
			for _, oh in ipairs(ohs) do
				if not (oh.loc == mh.loc and oh.slot == mh.slot) then
					consider(mh, oh, value + self:itemValue(oh, 17))
				end
			end
		end
	end
	setup[16], setup[17] = nil, nil
	if bestMH then setup[16] = self:newSlot(bestMH, 16) end
	if bestOH then setup[17] = self:newSlot(bestOH, 17) end
end

function O:initialSetup()
	local setup = {}
	local eq = Character.Equipped(self.c)
	for _, typ in ipairs(SINGLE_TYPES) do
		local slot = SINGLE_SLOTS[typ]
		for _, it in ipairs(self:candidates(function(x) return x.type == typ end)) do
			if not setup[slot] or self:itemValue(it, slot) > self:itemValue(setup[slot].item, slot) then
				setup[slot] = self:newSlot(it, slot)
			end
		end
	end

	self:pickPair(setup, self:candidates(function(x) return x.type == "FINGER" end), 11, 12)

	local trinkets = self:candidates(function(x) return x.type == "TRINKET" end)
	for _, slot in ipairs({ 13, 14 }) do
		if eq[slot] and not eq[slot].unusable then setup[slot] = self:newSlot(eq[slot], slot) end
	end
	if not setup[13] or not setup[14] then self:pickPair(setup, trinkets, 13, 14) end

	self:pickWeapons(setup)
	return setup
end

function O:uniqueUsed(setup, id, slot, socket)
	for sl, s in pairs(setup) do
		for i, g in ipairs(s.gems) do
			if g.id == id and not (sl == slot and i == socket) then return true end
		end
	end
	return false
end

function O:optimizeGems(setup)
	local slots = sortedKeys(setup)
	for _ = 1, 8 do
		local changed = false
		for _, slot in ipairs(slots) do
			local s = setup[slot]
			for i = 1, #s.gems do
				if string.sub(s.sockets, i, i) ~= "M" then
					local current = s.gems[i]
					local bestScore = self:totals(setup).score
					local best = current
					for _, g in ipairs(self.gems) do
						if g.id ~= current.id and not (g.color == "prismatic" and self:uniqueUsed(setup, g.id, slot, i)) then
							s.gems[i] = g
							local sc = self:totals(setup).score
							if sc > bestScore + EPS then best, bestScore = g, sc end
						end
					end
					s.gems[i] = best
					if best.id ~= current.id then changed = true end
				end
			end
		end
		if not changed then return end
	end
end

local function cloneSetup(setup)
	local out = {}
	for slot, s in pairs(setup) do
		local copy = {}
		for k, v in pairs(s) do copy[k] = v end
		copy.gems = {}
		for i, g in ipairs(s.gems) do copy.gems[i] = g end
		out[slot] = copy
	end
	return out
end

function O:inSetup(setup, it)
	for _, s in pairs(setup) do
		if s.item.loc == it.loc and s.item.slot == it.slot then return true end
	end
	return false
end

function O:fits(setup, slot, it)
	if slot == 11 or slot == 12 then
		local other = slot == 11 and 12 or 11
		if setup[other] and setup[other].item.id == it.id then return false end
	elseif slot == 17 then
		if setup[16] and setup[16].item.type == "2HWEAPON" and not self:titansGrip() then return false end
	end
	return true
end

function O:hillClimb(setup)
	local groups = {
		{ slots = { 11, 12 }, match = function(it) return it.type == "FINGER" end },
		{ slots = { 16 }, match = function(it) return self:isMH(it) end },
		{ slots = { 17 }, match = function(it) return self:isOH(it) end },
	}
	for _, typ in ipairs(SINGLE_TYPES) do
		groups[#groups + 1] = { slots = { SINGLE_SLOTS[typ] }, match = function(it) return it.type == typ end }
	end

	for _ = 1, 3 do
		local improved = false
		for _, g in ipairs(groups) do
			for _, slot in ipairs(g.slots) do
				for _, it in ipairs(self:candidates(g.match)) do
					if not self:inSetup(setup, it) and self:fits(setup, slot, it) then
						local trial = cloneSetup(setup)
						trial[slot] = self:newSlot(it, slot)
						if slot == 16 and it.type == "2HWEAPON" and not self:titansGrip() then trial[17] = nil end
						self:optimizeGems(trial)
						if self:totals(trial).score > self:totals(setup).score + EPS then
							for k in pairs(setup) do setup[k] = nil end
							for k, v in pairs(trial) do setup[k] = v end
							improved = true
						end
					end
				end
			end
		end
		if not improved then return end
	end
end

function O:markChanges(slots, current)
	for _, pair in ipairs({ { 11, 12 }, { 13, 14 } }) do
		local a, b = slots[pair[1]], slots[pair[2]]
		local ca, cb = current[pair[1]], current[pair[2]]
		if a and b and ca and cb and a.item.id == cb.item.id and b.item.id == ca.item.id then
			slots[pair[1]], slots[pair[2]] = b, a
		end
		if a and not b and cb and a.item.id == cb.item.id then
			slots[pair[1]], slots[pair[2]] = nil, a
		end
	end
	for slot, ns in pairs(slots) do
		local cur = current[slot]
		ns.current = cur
		if not cur or cur.item.id ~= ns.item.id or cur.item.loc ~= ns.item.loc then
			ns.changedItem = true
			ns.changedGems = #ns.gems > 0
			ns.changedEnchant = ns.enchant.id ~= 0
		else
			ns.changedEnchant = ns.enchant.id ~= 0 and ns.enchant.id ~= cur.item.enchant
			if ns.enchant.id == 0 and cur.item.enchant ~= 0 then ns.enchant = cur.enchant end
			for i, g in ipairs(ns.gems) do
				if g.id ~= 0 and (i > 4 or cur.item.gems[i] ~= g.id) then ns.changedGems = true end
			end
		end
	end
end

function O:notes(slots)
	local out = {}
	for _, slot in ipairs(sortedKeys(slots)) do
		local s = slots[slot]
		if s.item.loc == "K" and s.changedItem then
			out[#out + 1] = string.format("%s: вещь лежит в банке.", Rules.slotNames[slot])
		end
	end
	return out
end

-- Run computes the setup. yield, when given, is called regularly so the
-- caller can spread the work over frames (coroutine).
function Optimizer.Run(c, data, tank, yield)
	if not data then return nil, "no phase data" end
	local _, spec = detectSpec(c)
	if not spec then return nil, "talents are not spent" end
	if spec.role == Rules.TANK then tank = true end
	if not spec.maybeTank and spec.role ~= Rules.TANK then tank = false end

	local key = Rules.SpecKey(c.class, spec.tab, tank)
	local plan = data.specs[key]
	if not plan then return nil, "no plan for " .. key end
	local sim = Rules.SimFor(c.class, spec.tab, tank)
	local w = ns.Data.weights[sim]
	if not w then return nil, "no weights for " .. sim end

	local o = setmetatable({ c = c, data = data, plan = plan, spec = spec, tank = tank, w = w, yield = yield, evals = 0 }, O)
	o:prepare()

	local current = o:currentSetup()
	local before = o:totals(current)
	local best = o:initialSetup()
	o:optimizeGems(best)
	o:hillClimb(best)
	local after = o:totals(best)
	o:markChanges(best, current)
	local beforeStats, afterStats = o:gearStats(current), o:gearStats(best)
	local bis = {}
	local alternatives = {}
	for slot, name in pairs(Rules.bisSlots) do
		local p = plan.slots[name]
		if p and p.items then
			-- rings and trinkets: the second slot shows the second item
			local index = (slot == 12 or slot == 14) and 2 or 1
			bis[slot] = p.items[index] or p.items[1]
			alternatives[slot] = p.items
		end
	end

	return {
		phase = data.phase,
		specKey = key,
		specLabel = specLabel(spec, tank),
		spec = spec,
		sim = sim,
		tank = tank,
		canTank = spec.maybeTank,
		slots = best,
		before = before,
		after = after,
		notes = o:notes(best),
		evals = o.evals,
		beforeStats = beforeStats,
		afterStats = afterStats,
		weights = w,
		bis = bis,
		alternatives = alternatives,
	}
end

-- Body renders the result exactly like the bot's response body (the tests
-- compare them line by line).
function Optimizer.Body(c, r)
	local lines = {}
	local function add(...)
		local parts = { ... }
		for i = 1, select("#", ...) do
			parts[i] = string.gsub(tostring(parts[i]), "[|\n\r]", { ["|"] = "/", ["\n"] = " ", ["\r"] = " " })
		end
		lines[#lines + 1] = table.concat(parts, "|")
	end
	add("SARP", 1)
	add("H", "char", c.name or "", c.realm or "")
	add("H", "spec", r.specLabel)
	add("H", "phase", r.phase)
	if r.after.hitCap > 0 then
		add("C", "hit", string.format("%.2f", r.before.hitPct), string.format("%.2f", r.after.hitPct), string.format("%.2f", r.after.hitCap))
	end
	if r.after.expCap > 0 then
		add("C", "exp", math.floor(r.before.expSkill), math.floor(r.after.expSkill), math.floor(r.after.expCap))
	end
	for _, slot in ipairs(sortedKeys(r.slots)) do
		local s = r.slots[slot]
		local gems = { 0, 0, 0, 0 }
		for i, g in ipairs(s.gems) do if i <= 4 then gems[i] = g.id end end
		local src = s.enchant.source or ""
		src = string.gsub(string.gsub(src, "^spell:", "s"), "^item:", "i")
		local flags = (s.changedItem and "I" or "") .. (s.changedEnchant and "E" or "") ..
			(s.changedGems and "G" or "") .. (s.needsBuckle and "B" or "")
		add("I", slot, s.item.id, s.item.loc, s.item.slot, src, s.enchant.id, gems[1], gems[2], gems[3], gems[4], s.sockets, flags)
	end
	for _, n in ipairs(r.notes) do add("N", n) end
	return table.concat(lines, "\n")
end

-- View converts a result into the table SetupView renders.
local function enchantRef(e)
	local src = e and e.source or ""
	return string.match(src, "^spell:") and "s" or (string.match(src, "^item:") and "i" or ""),
		tonumber(string.match(src, ":(%d+)$") or "")
end

-- Stats shown in the "now / after" table: the spec's most valuable ones.
local SKIP_IN_TABLE = { HIT = true, EXP = true, MHDPS = true, OHDPS = true, RDPS = true, FAP = true, HP = true }
local function tableStats(w)
	local codes = {}
	for code, weight in pairs(w) do
		if not SKIP_IN_TABLE[code] and weight > 0 then codes[#codes + 1] = code end
	end
	table.sort(codes, function(a, b)
		if w[a] ~= w[b] then return w[a] > w[b] end
		return a < b
	end)
	local out = {}
	for i = 1, math.min(7, #codes) do out[i] = codes[i] end
	return out
end

-- Off-spec items: a noticeable part of the item's stats is worthless for
-- the spec (weight 0), e.g. intellect and spell power on a feral ring.
-- Stamina and armor are useful to everyone and are not judged.
local JUDGED = { "STR", "AGI", "INT", "SPI", "AP", "SP", "MP5", "HIT", "CRIT", "HASTE", "EXP", "ARP",
	"DEF", "DODGE", "PARRY", "BLOCK", "BLOCKV", "RESIL" }
local OFFSPEC_SHARE = 0.3

local function offSpec(stats, w)
	local total, wasted, codes = 0, 0, {}
	for _, code in ipairs(JUDGED) do
		local x = stats[code] or 0
		if x > 0 then
			-- attack and spell power come in bigger numbers than ratings
			local points = (code == "AP" or code == "SP") and x / 2 or x
			total = total + points
			if (w[code] or 0) <= 0 then
				wasted = wasted + points
				codes[#codes + 1] = code
			end
		end
	end
	if total > 0 and wasted / total >= OFFSPEC_SHARE then return codes end
	return nil
end

local function localLabel(r)
	local L = ns.L
	local spec = r.spec
	if not spec then return r.specLabel end
	local name = GetLocale() == "ruRU" and spec.name or spec.nameEN
	if spec.maybeTank then name = name .. " (" .. (r.tank and L.ROLE_TANK or L.ROLE_DPS) .. ")" end
	return name
end

-- Alternatives for a slot: the phase BiS list without the current item and
-- the BiS shown next to it.
local function alternativesFor(items, current, bis)
	local out = {}
	for _, id in ipairs(items or {}) do
		if id ~= current and id ~= bis and #out < 2 then out[#out + 1] = id end
	end
	return out
end

function Optimizer.View(c, r)
	local L = ns.L
	local view = { name = c.name, realm = c.realm, spec = localLabel(r), phase = r.phase, caps = {}, slots = {},
		notes = {}, canTank = r.canTank, tank = r.tank, stats = {} }
	local weakLevel = Rules.weakItemLevel[r.phase] or 0
	if r.after.hitCap > 0 then
		view.caps.hit = { before = r.before.hitPct, after = r.after.hitPct, cap = r.after.hitCap,
			rating = r.after.hitRating, talent = r.after.hitTalent }
	end
	if r.after.expCap > 0 then
		view.caps.exp = { before = r.before.expSkill, after = r.after.expSkill, cap = r.after.expCap,
			rating = r.after.expRating, talent = r.after.expTalent }
	end
	for _, code in ipairs(tableStats(r.weights or {})) do
		view.stats[#view.stats + 1] = { code = code, before = (r.beforeStats or {})[code] or 0, after = (r.afterStats or {})[code] or 0 }
	end
	for slot, s in pairs(r.slots) do
		local kind, source = enchantRef(s.enchant)
		local gems = {}
		for i, g in ipairs(s.gems) do gems[i] = g.id end
		local v = {
			slot = slot, item = s.item.id, loc = s.item.loc, where = s.item.slot, enchant = s.enchant.id,
			enchantKind = kind, enchantSource = source,
			gems = gems, sockets = s.sockets,
			changedItem = s.changedItem, changedEnchant = s.changedEnchant, changedGems = s.changedGems,
			buckle = s.needsBuckle, bis = r.bis and r.bis[slot],
			offSpec = offSpec(s.item.stats, r.weights or {}),
			weak = (s.item.quality >= 0 and s.item.quality <= 2) or (s.item.ilvl > 0 and s.item.ilvl < weakLevel),
		}
		if v.offSpec or v.weak then
			v.alternatives = alternativesFor(r.alternatives and r.alternatives[slot], s.item.id, v.bis)
		end
		if s.item.loc == "K" and s.changedItem then
			view.notes[#view.notes + 1] = string.format(L.NOTE_BANK, L.SLOTS[slot] or tostring(slot))
		end
		-- what is on the item now, to show what gets replaced
		local cur = s.current
		if cur and not s.changedItem then
			v.oldGems = {}
			for i = 1, 4 do v.oldGems[i] = cur.item.gems[i] or 0 end
			v.oldEnchant = cur.item.enchant
			v.oldEnchantKind, v.oldEnchantSource = enchantRef(cur.enchant)
		end
		view.slots[slot] = v
	end
	return view
end

-- Start runs the optimizer in a coroutine, a slice per frame, and calls
-- done(result, err) when finished.
local runner
function Optimizer.Start(c, data, tank, done)
	runner = runner or CreateFrame("Frame")
	local co = coroutine.create(function()
		return Optimizer.Run(c, data, tank, coroutine.yield)
	end)
	runner:SetScript("OnUpdate", function(self)
		local deadline = debugprofilestop and (debugprofilestop() + 12)
		repeat
			local ok, result, err = coroutine.resume(co)
			if not ok then
				self:SetScript("OnUpdate", nil)
				done(nil, tostring(result))
				return
			end
			if coroutine.status(co) == "dead" then
				self:SetScript("OnUpdate", nil)
				done(result, err)
				return
			end
		until not deadline or debugprofilestop() > deadline
	end)
end
