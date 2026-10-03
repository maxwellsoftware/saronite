-- Game rules the optimizer needs: specs, hit talents, rating conversions.
-- A port of the bot's internal/gear/analysis (specs.go, talents.go,
-- plan.go, weights.go); keep both in sync — the tests compare the results.
local _, ns = ...

local Rules = {}
ns.Rules = Rules

Rules.MELEE, Rules.TANK, Rules.RANGED, Rules.CASTER, Rules.HEALER = 0, 1, 2, 3, 4
local MELEE, TANK, RANGED, CASTER, HEALER = 0, 1, 2, 3, 4

-- Rating conversions at level 80; caps against a level 83 boss.
Rules.meleeHitPerPct = 32.78998
Rules.spellHitPerPct = 26.231964
Rules.expertisePerPoint = 8.1974973
Rules.meleeHitCap = 8.0
Rules.spellHitCap = 17.0
Rules.expertiseCap = 26.0

local function spec(name, role, maybeTank, nameEN)
	return { name = name, nameEN = nameEN or name, role = role, maybeTank = maybeTank or false }
end

-- ruRU client tree names (Wowhead WotLK skill pages).
Rules.specs = {
	WARRIOR = { spec("Оружие", MELEE, false, "Arms"), spec("Неистовство", MELEE, false, "Fury"), spec("Защита", TANK, false, "Protection") },
	PALADIN = { spec("Свет", HEALER, false, "Holy"), spec("Защита", TANK, false, "Protection"), spec("Воздаяние", MELEE, false, "Retribution") },
	HUNTER = { spec("Повелитель зверей", RANGED, false, "Beast Mastery"), spec("Стрельба", RANGED, false, "Marksmanship"), spec("Выживание", RANGED, false, "Survival") },
	ROGUE = { spec("Ликвидация", MELEE, false, "Assassination"), spec("Бой", MELEE, false, "Combat"), spec("Скрытность", MELEE, false, "Subtlety") },
	PRIEST = { spec("Послушание", HEALER, false, "Discipline"), spec("Свет", HEALER, false, "Holy"), spec("Темная магия", CASTER, false, "Shadow") },
	DEATHKNIGHT = { spec("Кровь", MELEE, true, "Blood"), spec("Лед", MELEE, true, "Frost"), spec("Нечестивость", MELEE, true, "Unholy") },
	SHAMAN = { spec("Стихии", CASTER, false, "Elemental"), spec("Совершенствование", MELEE, false, "Enhancement"), spec("Восстановление", HEALER, false, "Restoration") },
	MAGE = { spec("Тайная магия", CASTER, false, "Arcane"), spec("Огонь", CASTER, false, "Fire"), spec("Лед", CASTER, false, "Frost") },
	WARLOCK = { spec("Колдовство", CASTER, false, "Affliction"), spec("Демонология", CASTER, false, "Demonology"), spec("Разрушение", CASTER, false, "Destruction") },
	DRUID = { spec("Баланс", CASTER, false, "Balance"), spec("Сила зверя", MELEE, true, "Feral Combat"), spec("Восстановление", HEALER, false, "Restoration") },
}

-- Hit talents: tree, position in the (tier, column) ordered rank string
-- (0-based like the Go code), % per rank, hit kinds, condition.
Rules.HIT_MELEE, Rules.HIT_RANGED, Rules.HIT_SPELL = "melee", "ranged", "spell"
local function talent(name, tab, index, perRank, kinds, applies)
	local k = {}
	for _, kind in ipairs(kinds) do k[kind] = true end
	return { name = name, tab = tab, index = index, perRank = perRank, kinds = k, applies = applies }
end
local oneHanded = function(c) return c.oneHanded end
local dualWield = function(c) return c.dualWield end
Rules.hitTalents = {
	WARRIOR = { talent("Точность", 2, 12, 1, { "melee" }) },
	ROGUE = { talent("Точность", 2, 5, 1, { "melee", "ranged" }) },
	DEATHKNIGHT = {
		talent("Ледяная выдержка", 2, 5, 1, { "melee" }, oneHanded),
		talent("Болезнетворность", 3, 1, 1, { "spell" }),
	},
	SHAMAN = {
		talent("Точность стихии", 1, 13, 1, { "spell" }),
		talent("Специализация на бое двумя оружиями", 2, 18, 2, { "melee" }, dualWield),
	},
	HUNTER = { talent("Точное наведение", 2, 1, 1, { "ranged" }) },
	MAGE = {
		talent("Средоточие чар", 1, 1, 1, { "spell" }, function(c) return c.specTab == 1 end),
		talent("Точность", 3, 5, 1, { "spell" }),
	},
	WARLOCK = { talent("Подавление", 1, 1, 1, { "spell" }) },
	PRIEST = { talent("Средоточие Тьмы", 3, 5, 1, { "spell" }, function(c) return c.specTab == 3 end) },
	DRUID = { talent("Баланс сил", 1, 16, 2, { "spell" }) },
}

-- Below this item level an item is weak for the phase (heroic dungeons
-- and up are fine).
Rules.weakItemLevel = { T7 = 187 }

-- Bistooltip spec keys per class and tree: { dps, tank }.
Rules.bisSpecs = {
	WARRIOR = { { "Warrior/Arms" }, { "Warrior/Fury" }, { "Warrior/Protection", "Warrior/Protection" } },
	PALADIN = { { "Paladin/Holy" }, { "Paladin/Protection", "Paladin/Protection" }, { "Paladin/Retribution" } },
	HUNTER = { { "Hunter/Beast mastery" }, { "Hunter/Marksmanship" }, { "Hunter/Survival" } },
	ROGUE = { { "Rogue/Assassination" }, { "Rogue/Combat" }, { "Rogue/Combat" } },
	PRIEST = { { "Priest/Discipline" }, { "Priest/Holy" }, { "Priest/Shadow" } },
	DEATHKNIGHT = {
		{ "Death knight/Frost", "Death knight/Blood tank" },
		{ "Death knight/Frost", "Death knight/Blood tank" },
		{ "Death knight/Unholy", "Death knight/Blood tank" },
	},
	SHAMAN = { { "Shaman/Elemental" }, { "Shaman/Enhancement" }, { "Shaman/Restoration" } },
	MAGE = { { "Mage/Arcane" }, { "Mage/Fire" }, { "Mage/Frost" } },
	WARLOCK = { { "Warlock/Affliction" }, { "Warlock/Demonology" }, { "Warlock/Destruction" } },
	DRUID = { { "Druid/Balance" }, { "Druid/Feral dps", "Druid/Feral tank" }, { "Druid/Restoration" } },
}

function Rules.SpecKey(class, tab, tank)
	local opts = Rules.bisSpecs[class]
	if not opts or tab < 1 or tab > 3 then return "" end
	local o = opts[tab]
	if tank and o[2] then return o[2] end
	return o[1]
end

function Rules.SimFor(class, tab, tank)
	if class == "WARRIOR" then
		return tab == 3 and "protection_warrior" or "warrior"
	elseif class == "PALADIN" then
		return ({ "holy_paladin", "protection_paladin", "retribution_paladin" })[tab]
	elseif class == "HUNTER" then
		return "hunter"
	elseif class == "ROGUE" then
		return "rogue"
	elseif class == "PRIEST" then
		return tab == 3 and "shadow_priest" or "healing_priest"
	elseif class == "DEATHKNIGHT" then
		return tank and "tank_deathknight" or "deathknight"
	elseif class == "SHAMAN" then
		return ({ "elemental_shaman", "enhancement_shaman", "restoration_shaman" })[tab]
	elseif class == "MAGE" then
		return "mage"
	elseif class == "WARLOCK" then
		return "warlock"
	elseif class == "DRUID" then
		if tab == 1 then return "balance_druid" end
		if tab == 2 and tank then return "feral_tank_druid" end
		if tab == 2 then return "feral_druid" end
		return "restoration_druid"
	end
	return ""
end

Rules.bisSlots = {
	[1] = "Head", [2] = "Neck", [3] = "Shoulder", [15] = "Back", [5] = "Chest", [9] = "Wrist", [10] = "Hands",
	[6] = "Waist", [7] = "Legs", [8] = "Feet", [11] = "Finger", [12] = "Finger", [13] = "Trinket", [14] = "Trinket",
	[16] = "Weapon", [17] = "Off hand", [18] = "Ranged",
}

Rules.slotNames = {
	[1] = "Голова", [2] = "Шея", [3] = "Плечи", [5] = "Грудь", [6] = "Пояс", [7] = "Ноги", [8] = "Ступни",
	[9] = "Запястья", [10] = "Кисти рук", [11] = "Кольцо 1", [12] = "Кольцо 2", [13] = "Аксессуар 1",
	[14] = "Аксессуар 2", [15] = "Спина", [16] = "Правая рука", [17] = "Левая рука", [18] = "Дальний бой / реликвия",
}

-- Gem colors and sockets.
function Rules.Fits(gem, socket)
	local c = gem.color
	if socket == "M" then return c == "meta" end
	if socket == "P" then return c ~= "meta" end -- like the Go code: any non-meta, even unknown
	if socket == "R" then return c == "red" or c == "orange" or c == "purple" or c == "prismatic" end
	if socket == "Y" then return c == "yellow" or c == "orange" or c == "green" or c == "prismatic" end
	if socket == "B" then return c == "blue" or c == "purple" or c == "green" or c == "prismatic" end
	return false
end

function Rules.Counts(gem, color)
	local c = gem.color
	if color == "red" then return c == "red" or c == "orange" or c == "purple" or c == "prismatic" end
	if color == "yellow" then return c == "yellow" or c == "orange" or c == "green" or c == "prismatic" end
	if color == "blue" then return c == "blue" or c == "purple" or c == "green" or c == "prismatic" end
	return false
end

function Rules.IsPureCapGem(g)
	local n, stat = 0, nil
	for k in pairs(g.stats or {}) do
		n = n + 1
		stat = k
	end
	return n == 1 and (stat == "HIT" or stat == "EXP") and g.stats[stat] > 0
end

function Rules.TwoHandOnly(ench)
	return ench.id == 3827 or ench.id == 3847 -- Massacre, Stoneskin Gargoyle
end

function Rules.ExpandAll(stats)
	stats = stats or {}
	local all = stats.ALL
	if not all then return stats end
	local out = {}
	for k, v in pairs(stats) do
		if k ~= "ALL" then out[k] = v end
	end
	for _, k in ipairs({ "STR", "AGI", "STA", "INT", "SPI" }) do
		out[k] = (out[k] or 0) + all
	end
	return out
end

-- Stat phrases of enUS and ruRU tooltips (socket bonuses), longest first.
local PHRASES = {
	{ "critical strike rating", "CRIT" }, { "armor penetration rating", "ARP" }, { "expertise rating", "EXP" },
	{ "resilience rating", "RESIL" }, { "defense rating", "DEF" }, { "dodge rating", "DODGE" }, { "parry rating", "PARRY" },
	{ "block rating", "BLOCK" }, { "haste rating", "HASTE" }, { "hit rating", "HIT" }, { "spell power", "SP" },
	{ "attack power", "AP" }, { "all stats", "ALL" }, { "strength", "STR" }, { "agility", "AGI" }, { "stamina", "STA" },
	{ "intellect", "INT" }, { "spirit", "SPI" }, { "mana per 5 sec", "MP5" }, { "mana every 5 seconds", "MP5" },
	{ "к рейтингу критического удара", "CRIT" }, { "к рейтингу пробивания брони", "ARP" }, { "к рейтингу мастерства", "EXP" },
	{ "к рейтингу устойчивости", "RESIL" }, { "к рейтингу защиты", "DEF" }, { "к рейтингу уклонения", "DODGE" },
	{ "к рейтингу парирования", "PARRY" }, { "к рейтингу блокирования", "BLOCK" }, { "к рейтингу блока", "BLOCK" },
	{ "к рейтингу скорости", "HASTE" }, { "к рейтингу меткости", "HIT" }, { "к силе заклинаний", "SP" },
	{ "к силе атаки", "AP" }, { "ко всем характеристикам", "ALL" }, { "к силе", "STR" }, { "к ловкости", "AGI" },
	{ "к выносливости", "STA" }, { "к интеллекту", "INT" }, { "к духу", "SPI" }, { "ед. маны каждые 5", "MP5" },
	{ "к мане каждые 5", "MP5" }, { "ед. маны раз в 5", "MP5" },
}

-- StatsFromText parses "+8 Strength", "+4 к рейтингу меткости" and
-- combinations joined with "and"/"и".
function Rules.StatsFromText(text)
	local stats = {}
	local lower = string.lower(text or "")
	local marks = {}
	local pos = 1
	while true do
		local s, e, n = string.find(lower, "%+(%d+)%s*", pos)
		if not s then break end
		local rest = e + 1
		local to = string.match(lower, "^to%s+", rest)
		if to then rest = rest + string.len(to) end
		marks[#marks + 1] = { start = s, rest = rest, value = tonumber(n) }
		pos = e + 1
	end
	for i, m in ipairs(marks) do
		local stop = marks[i + 1] and marks[i + 1].start - 1 or string.len(lower)
		local rest = string.gsub(string.sub(lower, m.rest, stop), "^%s+", "")
		for _, p in ipairs(PHRASES) do
			if string.sub(rest, 1, string.len(p[1])) == p[1] then
				stats[p[2]] = (stats[p[2]] or 0) + m.value
				break
			end
		end
	end
	return stats
end
