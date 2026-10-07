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
		if code ~= "HIT" and code ~= "EXP" and code ~= "DPS" and code ~= "FAP"
			and not (code == "DEF" and (self.defPre or 0) > 0) -- DEF, HASTE: valued against the cap in totals
			and not (code == "HASTE" and (self.hasteBP or 0) > 0) then
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
	-- Plate tanks need 540 defense against crits; druids are immune
	-- through Survival of the Fittest.
	self.defPre, self.defPost = 0, 0
	if self.tank and c.class ~= "DRUID" then
		self.defPre = math.max(self.w.DEF or 0, 1.15 * self.gemUnit)
		self.defPost = self.w.DEF or 0
	end

	local s = c.stats
	local gear = self:gearStats(self:currentSetup())
	local ratingKey = ({ melee = "hitMelee", ranged = "hitRanged", spell = "hitSpell" })[self.hitKind or "melee"]
	self.baseHit = math.max(0, (s[ratingKey] or 0) - (gear.HIT or 0))
	self.baseExp = math.max(0, (s.expertise or 0) - (gear.EXP or 0))
	self.expTalents = math.max(0, (s.expMH or 0) - math.floor((s.expertise or 0) / Rules.expertisePerPoint))
	self.baseDef = math.max(0, (s.defense or 0) - (gear.DEF or 0))
	self.baseArp = math.max(0, (s.arp or 0) - (gear.ARP or 0))
	self.baseHasteRes = math.max(0, (s.hasteSpell or 0) - (gear.HASTE or 0))

	-- the main haste breakpoint, valued like a cap where guides chase it
	self.hasteBP, self.hastePre, self.hastePost, self.baseHaste = 0, 0, 0, 0
	local h = Rules.HasteSpec(self.sim, self.spec.tab)
	if h and h.pursue then
		local ranks = {}
		for _, t in ipairs(Character.ActiveTalents(c)) do
			if not ranks[t.tab] then ranks[t.tab] = t.ranks end
		end
		self.hasteBP = Rules.HasteRatings(h, ranks)[1]
		self.hastePre = math.max(self.w.HASTE or 0, 1.15 * self.gemUnit)
		self.hastePost = h.post * (self.w.HASTE or 0)
		self.baseHaste = self.baseHasteRes
	end
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
			-- stats read from the item tooltip (live character); unknown otherwise
			s.enchant = { id = it.enchant, stats = it.enchantStats or {} }
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
	if self.defPre > 0 then v = v + (self.defPre + self.defPost) / 2 * (stats.DEF or 0) end
	if self.hasteBP > 0 then v = v + (self.hastePre + self.hastePost) / 2 * (stats.HASTE or 0) end
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

-- Secondary criterion: when two setups are worth the same (a socket bonus
-- of stamina for a DPS, hit over the cap), the one with more stats wins.
-- 0.001 per point never outweighs a real difference in value.
local SECONDARY_WEIGHT = 0.001
local SECONDARY_STATS = { "STR", "AGI", "STA", "INT", "SPI", "HIT", "CRIT", "HASTE", "EXP", "ARP",
	"DEF", "DODGE", "PARRY", "BLOCK", "SP", "AP", "MP5" }

local function secondaryValue(stats)
	local points = 0
	for _, code in ipairs(SECONDARY_STATS) do points = points + (stats[code] or 0) end
	return SECONDARY_WEIGHT * points
end

function O:totals(setup)
	self:tick()
	local stats = self:gearStats(setup)
	local t = { score = 0, hitPct = 0, hitCap = 0, expSkill = 0, expCap = 0, defSkill = 0, defCap = 0, hasteRating = 0, hasteCap = 0 }
	local v = self:statValue(stats)
	for slot, s in pairs(setup) do v = v + self:weaponValue(s.item, slot) end
	v = v + secondaryValue(stats)

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

	if self.defPre > 0 then
		local total = self.baseDef + (stats.DEF or 0)
		local capRating = Rules.defenseCap * Rules.defensePerPoint
		v = v + self.defPre * math.min(total, capRating) + self.defPost * math.max(0, total - capRating)
		v = v - self:shortfall(total, capRating)
		t.defSkill = math.floor(total / Rules.defensePerPoint)
		t.defCap = Rules.defenseCap
		t.defRating = total
	end

	if self.hasteBP > 0 then
		local total = self.baseHaste + (stats.HASTE or 0)
		v = v + self.hastePre * math.min(total, self.hasteBP) + self.hastePost * math.max(0, total - self.hasteBP)
		v = v - self:shortfall(total, self.hasteBP)
		t.hasteRating, t.hasteCap = total, self.hasteBP
	end

	-- armor penetration: 1400 rating is 100%, more does nothing
	local wArp = self.w.ARP or 0
	if wArp > 0 then
		v = v - wArp * math.max(0, self.baseArp + (stats.ARP or 0) - Rules.arpCap)
	end
	t.arpRating = self.baseArp + (stats.ARP or 0)

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

-- Enchants: every option of the slot (any spec's plan, tank defense
-- enchants) is tried and the best one kept (as the Go code).
function O:enchantAllowed(rec, it, slot)
	local c = self.c
	if rec.profession and not c.professions[rec.profession] then return false end
	local name = rec.name or ""
	if string.sub(name, 1, 7) == "Rune of" and c.class ~= "DEATHKNIGHT" then return false end
	local shield = string.find(name, "Shield", 1, true) ~= nil or string.find(name, "Plating", 1, true) ~= nil
	if slot == 17 and shield ~= (it.type == "SHIELD") then return false end
	if slot == 16 and shield then return false end
	if (Rules.TwoHandOnly(rec) or string.find(name, "2H Weapon", 1, true)) and it.type ~= "2HWEAPON" then return false end
	return true
end

function O:optimizeEnchants(setup)
	local changed = false
	local c = self.c
	local options = self.data.enchantOptions or {}
	for _, slot in ipairs(sortedKeys(setup)) do
		local s = setup[slot]
		local skip = not ENCHANT_SLOTS[slot] or (slot == 18 and c.class ~= "HUNTER")
			or ((slot == 11 or slot == 12) and not c.professions.ENCHANTING)
		if not skip then
			local orig = s.enchant.id
			local best, bestScore = s.enchant, self:totals(setup).score
			for _, id in ipairs(options[Rules.bisSlots[slot]] or {}) do
				local rec = self.data.enchants[id]
				if rec and rec.id ~= best.id and self:enchantAllowed(rec, s.item, slot) then
					s.enchant = rec
					local sc = self:totals(setup).score
					if sc > bestScore + EPS then best, bestScore = rec, sc end
				end
			end
			s.enchant = best
			if best.id ~= orig then changed = true end
		end
	end
	return changed
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

-- Socket colors. Coordinate ascent changes one socket at a time, so it
-- cannot reach a socket bonus that needs two gems to change together. These
-- moves change gems jointly and keep the result only if the whole setup
-- scores higher (same order and rules as the Go code).

-- socketSlots: indexes of the item's own sockets that take regular gems.
local function socketSlots(s)
	local out = {}
	local base = s.item.sockets
	for i = 1, math.min(string.len(base), #s.gems) do
		if string.sub(base, i, i) ~= "M" then out[#out + 1] = i end
	end
	return out
end

-- permutations of 1..n in lexicographic order.
local function permutations(n)
	local out, prefix, used = {}, {}, {}
	local function rec()
		if #prefix == n then
			local copy = {}
			for k, v in ipairs(prefix) do copy[k] = v end
			out[#out + 1] = copy
			return
		end
		for i = 1, n do
			if not used[i] then
				used[i] = true
				prefix[#prefix + 1] = i
				rec()
				prefix[#prefix] = nil
				used[i] = false
			end
		end
	end
	rec()
	return out
end

-- arrangeGems tries every order of the item's gems over its sockets.
function O:arrangeGems(setup, slot)
	local s = setup[slot]
	local idx = socketSlots(s)
	if #idx < 2 then return false end
	local orig = {}
	for k, i in ipairs(idx) do orig[k] = s.gems[i] end
	local bestScore = self:totals(setup).score
	local best
	for _, perm in ipairs(permutations(#idx)) do
		local same = true
		for k, p in ipairs(perm) do
			if orig[p].id ~= orig[k].id then same = false end
			s.gems[idx[k]] = orig[p]
		end
		if not same then
			local sc = self:totals(setup).score
			if sc > bestScore + EPS then best, bestScore = perm, sc end
		end
	end
	for k, i in ipairs(idx) do
		s.gems[i] = best and orig[best[k]] or orig[k]
	end
	return best ~= nil
end

-- matchColors fills all the item's sockets with gems of their colors (two
-- passes, the second one sees the active bonus) and keeps that if better.
function O:matchColors(setup, slot)
	local s = setup[slot]
	local idx = socketSlots(s)
	if #idx == 0 or next(s.item.socketBonus or {}) == nil then return false end
	local before = self:totals(setup).score
	local orig = {}
	for i, g in ipairs(s.gems) do orig[i] = g end
	local function restore()
		for i, g in ipairs(orig) do s.gems[i] = g end
	end
	for _ = 1, 2 do
		for _, i in ipairs(idx) do
			local socket = string.sub(s.item.sockets, i, i)
			local best, bestScore = nil, -math.huge
			for _, g in ipairs(self.gems) do
				if Rules.Fits(g, socket) and not (g.color == "prismatic" and self:uniqueUsed(setup, g.id, slot, i)) then
					s.gems[i] = g
					local sc = self:totals(setup).score
					if sc > bestScore + EPS then best, bestScore = g, sc end
				end
			end
			if not best then
				restore()
				return false
			end
			s.gems[i] = best
		end
	end
	if self:totals(setup).score > before + EPS then return true end
	restore()
	return false
end

-- swapGems exchanges gems between sockets of different items.
function O:swapGems(setup)
	local slots = sortedKeys(setup)
	local changed = false
	for ai, a in ipairs(slots) do
		for bi = ai + 1, #slots do
			local sa, sb = setup[a], setup[slots[bi]]
			for i = 1, #sa.gems do
				for j = 1, #sb.gems do
					if string.sub(sa.sockets, i, i) ~= "M" and string.sub(sb.sockets, j, j) ~= "M"
						and sa.gems[i].id ~= sb.gems[j].id then
						local before = self:totals(setup).score
						sa.gems[i], sb.gems[j] = sb.gems[j], sa.gems[i]
						if self:totals(setup).score > before + EPS then
							changed = true
						else
							sa.gems[i], sb.gems[j] = sb.gems[j], sa.gems[i]
						end
					end
				end
			end
		end
	end
	return changed
end

function O:socketMoves(setup, slots)
	local changed = false
	for _, slot in ipairs(slots) do
		if setup[slot] then
			if self:matchColors(setup, slot) then changed = true end
			if self:arrangeGems(setup, slot) then changed = true end
		end
	end
	return changed
end

-- polishSockets: joint moves on every item and gem swaps between items,
-- then single sockets again, until nothing improves.
function O:polishSockets(setup)
	for _ = 1, 4 do
		local changed = self:socketMoves(setup, sortedKeys(setup))
		if self:swapGems(setup) then changed = true end
		if self:optimizeEnchants(setup) then changed = true end
		if not changed then return end
		self:optimizeGems(setup)
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
						if self:socketMoves(trial, { slot }) then self:optimizeGems(trial) end
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

	local o = setmetatable({ c = c, data = data, plan = plan, spec = spec, tank = tank, w = w, sim = sim, yield = yield, evals = 0 }, O)
	o:prepare()

	local current = o:currentSetup()
	local before = o:totals(current)
	local best = o:initialSetup()
	o:optimizeGems(best)
	o:hillClimb(best)
	o:polishSockets(best)
	local after = o:totals(best)
	o:markChanges(best, current)
	-- after markChanges: it may swap rings / trinkets to their current slots
	local upgrades = o:checkUpgrades(best, key)
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
		plan = plan,
		data = data,
		upgrades = upgrades,
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
	if r.after.hasteCap > 0 then
		add("C", "haste", math.floor(r.before.hasteRating), math.floor(r.after.hasteRating), math.floor(r.after.hasteCap))
	end
	if r.after.defCap > 0 then
		add("C", "def", 400 + r.before.defSkill, 400 + r.after.defSkill, 400 + r.after.defCap)
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
	local name = ns.lang == "ru" and spec.name or spec.nameEN
	if spec.maybeTank then name = name .. " (" .. (r.tank and L.ROLE_TANK or L.ROLE_DPS) .. ")" end
	return name
end

-- Alternatives for a slot: the phase BiS list without the current item and
-- the BiS shown next to it.
local function alternativesFor(items, current)
	local out = {}
	for _, id in ipairs(items or {}) do
		if id ~= current and #out < 2 then out[#out + 1] = id end
	end
	return out
end

-- Upgrades within reach: items of the phase's content (Data/Upgrades.lua)
-- at most one content step (+13 item levels) above the character's
-- average item level that score higher than the equipped item. EP as the
-- generator's itemEP: weights x stats (feral attack power left out),
-- weapon DPS x the slot's DPS weight, sockets x best gem, socket bonus.
local REACH = 13

local function upgradeEP(it, slot, w, gem)
	if not it then return 0 end
	local v = 0
	for code, x in pairs(Rules.ExpandAll(it.stats)) do
		if code ~= "DPS" and code ~= "FAP" then v = v + (w[code] or 0) * x end
	end
	local dps = it.stats.DPS or 0
	if slot == 16 then v = v + (w.MHDPS or 0) * dps
	elseif slot == 17 then v = v + (w.OHDPS or 0) * dps
	elseif slot == 18 then v = v + (w.RDPS or 0) * dps
	end
	v = v + string.len(it.sockets or "") * gem
	for code, x in pairs(Rules.ExpandAll(it.socketBonus or {})) do v = v + (w[code] or 0) * x end
	return v
end

-- averageItemLevel of the equipped gear (shirt and tabard left out).
local function averageItemLevel(c)
	local sum, n = 0, 0
	for _, it in pairs(Character.Equipped(c)) do
		if it.invSlot ~= 4 and it.invSlot ~= 19 and it.ilvl > 0 then
			sum, n = sum + it.ilvl, n + 1
		end
	end
	return n > 0 and math.floor(sum / n + 0.5) or 0
end

local UPGRADE_SLOT = { [12] = 11, [14] = 13 }

-- itemValue for upgrades: EP, or for trinkets (procs are not in the
-- stats) the BiS list rank of the trinket, 0 when it is not in the list.
local function slotValue(list, slot, item, w, gem)
	if slot == 13 or slot == 14 then
		for _, e in ipairs(list) do
			if item and e[1] == item.id then return e[3] end
		end
		return 0
	end
	return upgradeEP(item, slot, w, gem)
end

-- candidates: items better than the equipped one and within reach,
-- nearest first: item levels up to the character's average from the
-- closest down, then the ones above it from the closest up; within a level
-- the easier source (dungeons, emblems before raids), then the value.
local function candidates(r, slot, item, avg, reach, have, taken)
	local data = ns.Data.upgrades and ns.Data.upgrades[r.specKey]
	local list = data and data[UPGRADE_SLOT[slot] or slot]
	if not list then return {} end
	local trinket = slot == 13 or slot == 14
	local current = slotValue(list, slot, item, r.weights or {}, data.gem)
	local out = {}
	for _, e in ipairs(list) do
		local id, ilvl, ep, tier = e[1], e[2], e[3], e[4] or 0
		local better = trinket and ep > current or (not trinket and ep > current * 1.03 + 1)
		if ilvl <= reach and better and not have[id] and not taken[id] then
			out[#out + 1] = { id = id, ilvl = ilvl, ep = ep, tier = tier }
		end
	end
	-- "your level": the average plus a little (an average of 199 in 200 gear)
	local level = avg + 3
	table.sort(out, function(a, b)
		local ga, gb = a.ilvl <= level and 0 or 1, b.ilvl <= level and 0 or 1
		if ga ~= gb then return ga < gb end
		if a.ilvl ~= b.ilvl then
			if ga == 0 then return a.ilvl > b.ilvl end
			return a.ilvl < b.ilvl
		end
		if a.tier ~= b.tier then return a.tier < b.tier end
		if a.ep ~= b.ep then return a.ep > b.ep end
		return a.id < b.id
	end)
	return out
end

-- pickUpgrades: up to 2 upgrades per slot. Rings and trinkets are a pair:
-- the weaker of the two picks first and no item is offered for both.
-- accept(slot, candidate) confirms a candidate (tried in the real setup);
-- at most MAX_TRIES candidates are tried per slot.
local MAX_TRIES = 8

local function pickUpgrades(r, avg, reach, have, accept)
	local out = {}
	local data = ns.Data.upgrades and ns.Data.upgrades[r.specKey]
	if not data then return out end
	local function take(slot, taken)
		local s = r.slots[slot]
		if not s then return end
		local list = candidates(r, slot, s.item, avg, reach, have, taken)
		local ups = {}
		for i = 1, math.min(MAX_TRIES, #list) do
			if #ups >= 2 then break end
			if not accept or accept(slot, list[i]) then
				ups[#ups + 1] = list[i]
				taken[list[i].id] = true
			end
		end
		out[slot] = ups
	end
	for slot in pairs(r.slots) do
		if slot ~= 11 and slot ~= 12 and slot ~= 13 and slot ~= 14 then take(slot, {}) end
	end
	for _, pair in ipairs({ { 11, 12 }, { 13, 14 } }) do
		local a, b = pair[1], pair[2]
		local list = data[UPGRADE_SLOT[b] or b] or {}
		local function value(slot)
			local s = r.slots[slot]
			return s and slotValue(list, slot, s.item, r.weights or {}, data.gem) or -1, s and s.item.ilvl or 0
		end
		local va, la = value(a)
		local vb, lb = value(b)
		if vb < va or (vb == va and lb < la) then a, b = b, a end
		local taken = {}
		take(a, taken)
		take(b, taken)
	end
	return out
end

-- The phase BiS list of the spec, laid out per inventory slot: the item,
-- the list's gems and enchant, up to 5 more items from the list.
local function planSlot(plan, slot)
	local p = plan.slots[Rules.bisSlots[slot]]
	if not p and slot == 18 then p = plan.slots.Relic end
	return p
end

local function bisView(c, r)
	local out = { slots = {}, owned = 0, total = 0 }
	if not r.plan then return out end
	local have = {}
	for _, it in ipairs(c.items) do have[it.id] = true end
	for slot in pairs(Rules.bisSlots) do
		local p = planSlot(r.plan, slot)
		local pair = slot == 11 or slot == 12 or slot == 13 or slot == 14
		local main = p and p.items and p.items[(slot == 12 or slot == 14) and 2 or 1]
		if main then
			local alts = {}
			for i, id in ipairs(p.items) do
				local isMain = pair and i <= 2 or (not pair and i == 1)
				if not isMain and #alts < 5 then alts[#alts + 1] = id end
			end
			local kind, source = enchantRef(r.data.enchants[p.enchant or 0])
			local gems = {}
			for i, g in ipairs(p.gems or {}) do gems[i] = g end
			out.slots[slot] = {
				slot = slot, item = main, gems = gems, sockets = "",
				enchant = p.enchant or 0, enchantKind = kind, enchantSource = source,
				alternatives = alts, owned = have[main] == true,
			}
			out.total = out.total + 1
			if have[main] then out.owned = out.owned + 1 end
		end
	end
	return out
end

function Optimizer.View(c, r)
	local L = ns.L
	local view = { name = c.name, realm = c.realm, spec = localLabel(r), phase = r.phase, caps = {}, slots = {},
		notes = {}, bankSlots = {}, canTank = r.canTank, tank = r.tank, stats = {},
		specNames = r.spec and { ru = r.spec.name, en = r.spec.nameEN } or nil }
	local weakLevel = Rules.weakItemLevel[r.phase] or 0
	view.bis = bisView(c, r)
	view.averageLevel = averageItemLevel(c)
	view.reach = view.averageLevel + REACH
	local have = {}
	for _, it in ipairs(c.items) do have[it.id] = true end
	-- confirmed in the real setup by Optimizer.Run (O:checkUpgrades)
	local upgrades = r.upgrades or {}
	if r.after.hitCap > 0 then
		view.caps.hit = { before = r.before.hitPct, after = r.after.hitPct, cap = r.after.hitCap,
			rating = r.after.hitRating, talent = r.after.hitTalent }
	end
	if r.after.expCap > 0 then
		view.caps.exp = { before = r.before.expSkill, after = r.after.expSkill, cap = r.after.expCap,
			rating = r.after.expRating, talent = r.after.expTalent }
	end
	if r.after.defCap > 0 then
		view.caps.def = { before = 400 + r.before.defSkill, after = 400 + r.after.defSkill, cap = 400 + r.after.defCap,
			rating = r.after.defRating }
	end
	view.role = r.spec and r.spec.role
	local role = view.role
	-- Haste breakpoints (Rules.HasteSpec): every one with its rating for
	-- this character's talents; the first is the main one.
	local h = Rules.HasteSpec(r.sim, r.spec and r.spec.tab)
	if h then
		local ranks = {}
		for _, t in ipairs(Character.ActiveTalents(c)) do
			if not ranks[t.tab] then ranks[t.tab] = t.ranks end
		end
		local gearBefore = (r.beforeStats or {}).HASTE or 0
		local base = math.max(0, (c.stats.hasteSpell or 0) - gearBefore)
		local ratings = Rules.HasteRatings(h, ranks)
		local bps = {}
		for i, bp in ipairs(h.bps) do bps[i] = { key = bp.key, rating = ratings[i] } end
		view.caps.haste = { before = base + gearBefore, after = base + ((r.afterStats or {}).HASTE or 0),
			cap = ratings[1], breakpoints = bps, pursued = h.pursue == true }
	end
	-- Armor penetration for the specs that stack it: 1400 rating is 100%.
	if (r.weights.ARP or 0) >= 0.8 then
		view.caps.arp = { before = r.before.arpRating or 0, after = r.after.arpRating or 0, cap = Rules.arpCap }
	end
	-- Feral tanks: crit immunity from Survival of the Fittest 3/3.
	if c.class == "DRUID" and r.tank then
		local trees = ns.Data.talentTrees and ns.Data.talentTrees.DRUID
		local ranks = ""
		for _, t in ipairs(Character.ActiveTalents(c)) do
			if t.tab == 2 then ranks = t.ranks end
		end
		for k, t in ipairs(trees and trees[2] and trees[2].talents or {}) do
			if t.name == "survivalOfTheFittest" then
				local rank = tonumber(string.sub(ranks, k, k)) or 0
				view.caps.crit = { before = rank, after = rank, cap = t.max, spell = t.spell }
			end
		end
	end
	-- talents and glyphs tab: the class trees and what the player has now
	view.class, view.specTab, view.sim = c.class, r.spec and r.spec.tab, r.sim
	view.talentRanks = {}
	for _, t in ipairs(Character.ActiveTalents(c)) do view.talentRanks[t.tab] = t.ranks end
	view.glyphs = c.glyphs and c.glyphs[c.activeGroup] or {}
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
		-- socket colors and the bonus, for the strips under the gems
		v.itemSockets = s.item.sockets
		if next(s.item.socketBonus or {}) then
			v.bonus = s.item.socketBonus
			local matched = string.len(s.item.sockets) > 0
			for i = 1, string.len(s.item.sockets) do
				local g = s.gems[i]
				if not g or g.id == 0 or not Rules.Fits(g, string.sub(s.item.sockets, i, i)) then matched = false end
			end
			v.bonusActive = matched
		end
		-- upgrades within reach for every slot; off-spec and weak items
		-- fall back to the BiS list when the phase data has none
		local ups = upgrades[slot]
		if ups and #ups > 0 then
			v.alternatives, v.alternativeLevels = {}, {}
			v.alternativeGains = {}
			for i, u in ipairs(ups) do
				v.alternatives[i], v.alternativeLevels[i], v.alternativeGains[i] = u.id, u.ilvl, u.gain or 0
			end
			v.upgrades = true
		elseif v.offSpec or v.weak then
			v.alternatives = alternativesFor(r.alternatives and r.alternatives[slot], s.item.id)
		end
		if s.item.loc == "K" and s.changedItem then
			view.bankSlots[#view.bankSlots + 1] = slot
		end
		-- what is on the item now, to show what gets replaced
		local cur = s.current
		if cur and s.changedItem then v.oldItem = cur.item.id end
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

-- Upgrades confirmed in the real setup: the candidate replaces the item,
-- gets its gems and enchant, and is kept only if the whole setup scores
-- higher (caps, socket bonuses, set rules included). Trinkets are ranked
-- by the BiS list instead: their procs are not in the stats.
function O:upgradeGain(setup, slot, id)
	local d = ns.Data.items and ns.Data.items[id]
	if not d then return nil end
	local it = { id = id, loc = "U", slot = "", invSlot = 0, type = d[1], sockets = d[2], stats = d[3],
		socketBonus = d[4], gems = { 0, 0, 0, 0 }, enchant = 0, quality = 4, ilvl = 0 }
	local twoHand = setup[16] and setup[16].item.type == "2HWEAPON" and not self:titansGrip()
	if slot == 17 and twoHand then return nil end
	local base = self:totals(setup).score
	local trial = cloneSetup(setup)
	trial[slot] = self:newSlot(it, slot)
	if slot == 16 and it.type == "2HWEAPON" and not self:titansGrip() then trial[17] = nil end
	-- gems of the new item only: coordinate ascent, then the joint moves
	local s = trial[slot]
	for _ = 1, 2 do
		for i = 1, #s.gems do
			if string.sub(s.sockets, i, i) ~= "M" then
				local best, bestScore = s.gems[i], self:totals(trial).score
				for _, g in ipairs(self.gems) do
					if g.id ~= best.id and not (g.color == "prismatic" and self:uniqueUsed(trial, g.id, slot, i)) then
						s.gems[i] = g
						local sc = self:totals(trial).score
						if sc > bestScore + EPS then best, bestScore = g, sc end
					end
				end
				s.gems[i] = best
			end
		end
	end
	self:socketMoves(trial, { slot })
	return self:totals(trial).score - base
end

function O:checkUpgrades(setup, key)
	local c = self.c
	local avg = averageItemLevel(c)
	local have = {}
	for _, it in ipairs(c.items) do have[it.id] = true end
	local r = { slots = setup, specKey = key, weights = self.w }
	return pickUpgrades(r, avg, avg + REACH, have, function(slot, cand)
		if slot == 13 or slot == 14 then return true end
		local gain = self:upgradeGain(setup, slot, cand.id)
		cand.gain = gain
		return gain ~= nil and gain > 1
	end)
end
