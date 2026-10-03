-- Collects raw character data through the WoW 3.3.5a API.
-- Everything is locale-independent: ids and API tokens, never display names
-- (except profession names that have no id-based API, see Professions()).
local _, ns = ...

local Scanner = {}
ns.Scanner = Scanner

-- Inventory slots worth exporting: shirt (4) and tabard (19) are skipped.
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local BANK_CONTAINER = -1
local FIRST_BANK_BAG, LAST_BANK_BAG = 5, 11

-- Equippable item types that never matter for gear advice.
local IGNORED_EQUIP_LOC = {
	INVTYPE_BAG = true,
	INVTYPE_QUIVER = true,
	INVTYPE_AMMO = true,
	INVTYPE_BODY = true,
	INVTYPE_TABARD = true,
}

-- Short codes for GetItemStats keys; unknown keys are sent as-is without the
-- ITEM_MOD_ prefix and _SHORT suffix so the bot can still learn them.
local STAT_CODES = {
	ITEM_MOD_STRENGTH_SHORT = "STR",
	ITEM_MOD_AGILITY_SHORT = "AGI",
	ITEM_MOD_STAMINA_SHORT = "STA",
	ITEM_MOD_INTELLECT_SHORT = "INT",
	ITEM_MOD_SPIRIT_SHORT = "SPI",
	ITEM_MOD_HIT_RATING_SHORT = "HIT",
	ITEM_MOD_CRIT_RATING_SHORT = "CRIT",
	ITEM_MOD_HASTE_RATING_SHORT = "HASTE",
	ITEM_MOD_EXPERTISE_RATING_SHORT = "EXP",
	ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "ARP",
	ITEM_MOD_ATTACK_POWER_SHORT = "AP",
	ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
	ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "FAP",
	ITEM_MOD_SPELL_POWER_SHORT = "SP",
	ITEM_MOD_SPELL_PENETRATION_SHORT = "SPEN",
	ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
	ITEM_MOD_POWER_REGEN0_SHORT = "MP5", -- what 3.3.5 actually returns for mp5
	ITEM_MOD_HEALTH_REGEN_SHORT = "HP5",
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEF",
	ITEM_MOD_DODGE_RATING_SHORT = "DODGE",
	ITEM_MOD_PARRY_RATING_SHORT = "PARRY",
	ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK",
	ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKV",
	ITEM_MOD_RESILIENCE_RATING_SHORT = "RESIL",
	RESISTANCE0_NAME = "ARMOR",
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
}

local SOCKET_CODES = {
	EMPTY_SOCKET_META = "M",
	EMPTY_SOCKET_RED = "R",
	EMPTY_SOCKET_YELLOW = "Y",
	EMPTY_SOCKET_BLUE = "B",
	EMPTY_SOCKET_PRISMATIC = "P",
}
local SOCKET_ORDER = { "EMPTY_SOCKET_META", "EMPTY_SOCKET_RED", "EMPTY_SOCKET_YELLOW", "EMPTY_SOCKET_BLUE", "EMPTY_SOCKET_PRISMATIC" }

-- Gems are recognised by their item class. GetAuctionItemClasses() returns
-- localized class names; in 3.3.5 "Gem" is the 10th entry. English and
-- Russian names are a fallback in case a custom client reorders the list.
local gemClassNames
local function IsGemClass(itemType)
	if not gemClassNames then
		gemClassNames = { Gem = true, ["Самоцветы"] = true, ["Самоцвет"] = true }
		local tenth = select(10, GetAuctionItemClasses())
		if tenth then gemClassNames[tenth] = true end
	end
	return itemType ~= nil and gemClassNames[itemType] == true
end

local function toint(v)
	return tonumber(v) or 0
end

-- Splits "item:id:enchant:j1:j2:j3:j4:suffix:unique:level" out of a link.
function Scanner.ParseLink(link)
	local itemString = link and string.match(link, "item:([%-%d:]+)")
	if not itemString then return nil end

	-- Plain split: gmatch with "[^:]*" yields extra empty matches in Lua 5.1.
	local f, start = {}, 1
	while true do
		local sep = string.find(itemString, ":", start, true)
		if not sep then
			f[#f + 1] = string.sub(itemString, start)
			break
		end
		f[#f + 1] = string.sub(itemString, start, sep - 1)
		start = sep + 1
	end
	return {
		id = toint(f[1]),
		enchant = toint(f[2]),
		jewels = { toint(f[3]), toint(f[4]), toint(f[5]), toint(f[6]) },
		suffix = toint(f[7]),
		unique = toint(f[8]),
	}
end

local function GemItemIDs(link)
	local ids = { 0, 0, 0, 0 }
	for i = 1, 4 do
		local _, gemLink = GetItemGem(link, i)
		local parsed = gemLink and Scanner.ParseLink(gemLink)
		if parsed then ids[i] = parsed.id end
	end
	return ids
end

-- StatCodes converts GetItemStats keys into the export's stat codes.
function Scanner.StatCodes(raw)
	local stats = {}
	for key, value in pairs(raw or {}) do
		if not SOCKET_CODES[key] then
			local code = STAT_CODES[key] or (string.gsub(string.gsub(key, "^ITEM_MOD_", ""), "_SHORT$", ""))
			stats[code] = value
		end
	end
	return stats
end

local function SocketsAndStats(link)
	local raw = GetItemStats(link) or {}
	local sockets = {}
	for _, key in ipairs(SOCKET_ORDER) do
		for _ = 1, toint(raw[key]) do
			sockets[#sockets + 1] = SOCKET_CODES[key]
		end
	end
	return table.concat(sockets), Scanner.StatCodes(raw)
end

-- Tooltip scan: whether the player can use the item (no red requirement
-- lines, which is locale independent) and its socket bonus text.
local scanTip, bonusPattern

local function ScanTooltip()
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "SaroniteScanTooltip", nil, "GameTooltipTemplate")
		local fmt = ITEM_SOCKET_BONUS or "Socket Bonus: %s"
		fmt = string.gsub(fmt, "[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
		bonusPattern = "^" .. string.gsub(fmt, "%%s", "(.+)") .. "$"
	end
	return scanTip
end

local function isRed(fs)
	if not fs or not fs:GetText() then return false end
	local r, g, b = fs:GetTextColor()
	return r and r > 0.99 and g < 0.2 and b < 0.2
end

function Scanner.TooltipInfo(link)
	local tip = ScanTooltip()
	tip:SetOwner(WorldFrame, "ANCHOR_NONE")
	tip:ClearLines()
	tip:SetHyperlink(link)

	local usable, bonus = true, ""
	for i = 1, tip:NumLines() or 0 do
		local left = _G["SaroniteScanTooltipTextLeft" .. i]
		local right = _G["SaroniteScanTooltipTextRight" .. i]
		if isRed(left) or isRed(right) then usable = false end
		local text = left and left:GetText()
		local match = text and string.match(text, bonusPattern)
		if match then bonus = match end
	end
	tip:Hide()
	-- Drop color codes; the bot parses the plain text.
	bonus = string.gsub(string.gsub(bonus, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
	return usable, bonus
end

-- Builds the export record of one item. Returns nil for unreadable items.
local function ItemRecord(loc, slot, link, count)
	local parsed = Scanner.ParseLink(link)
	if not parsed or parsed.id == 0 then return nil end

	local _, _, quality, ilvl, _, itemType, _, _, equipLoc = GetItemInfo(link)
	local sockets, stats = SocketsAndStats(link)
	local usable, bonus = Scanner.TooltipInfo(link)

	return {
		loc = loc,
		slot = slot,
		id = parsed.id,
		enchant = parsed.enchant,
		jewels = parsed.jewels,
		suffix = parsed.suffix,
		-- For random-suffix items (negative suffix id) the unique id carries
		-- the suffix factor needed to compute stats; otherwise it is noise.
		unique = parsed.suffix < 0 and parsed.unique or 0,
		gems = GemItemIDs(link),
		count = count or 1,
		quality = quality or -1,
		ilvl = ilvl or 0,
		sockets = sockets,
		stats = stats,
		itemType = itemType,
		equipLoc = equipLoc,
		usable = usable,
		bonus = bonus,
	}
end

-- Gear worth considering from bags and bank: equippable items of uncommon+
-- quality and gems.
local function IsInteresting(record)
	if IsGemClass(record.itemType) then return true end
	return record.equipLoc ~= nil and record.equipLoc ~= ""
		and not IGNORED_EQUIP_LOC[record.equipLoc]
		and record.quality >= 2
end

function Scanner.ScanEquipped()
	local items = {}
	for _, slot in ipairs(EQUIP_SLOTS) do
		local link = GetInventoryItemLink("player", slot)
		local record = link and ItemRecord("E", tostring(slot), link, 1)
		if record then items[#items + 1] = record end
	end
	return items
end

local function ScanContainer(loc, bag, items)
	for slot = 1, GetContainerNumSlots(bag) or 0 do
		local link = GetContainerItemLink(bag, slot)
		if link then
			local _, count = GetContainerItemInfo(bag, slot)
			local record = ItemRecord(loc, bag .. ":" .. slot, link, count)
			if record and IsInteresting(record) then
				items[#items + 1] = record
			end
		end
	end
end

function Scanner.ScanBags()
	local items = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		ScanContainer("B", bag, items)
	end
	return items
end

-- Only valid while the bank window is open (see Core.lua).
function Scanner.ScanBank()
	local items = {}
	ScanContainer("K", BANK_CONTAINER, items)
	for bag = FIRST_BANK_BAG, LAST_BANK_BAG do
		ScanContainer("K", bag, items)
	end
	-- Drop the localized type name: it only exists for filtering.
	for _, item in ipairs(items) do
		item.itemType = nil
	end
	return items
end

-- Talent ranks are ordered by (tier, column), the order used by talent
-- calculators, because GetTalentInfo's index order is not positional.
function Scanner.Talents()
	local result = {}
	local groups = GetNumTalentGroups and GetNumTalentGroups() or 1
	for group = 1, groups do
		for tab = 1, GetNumTalentTabs() do
			local talents = {}
			for i = 1, GetNumTalents(tab) do
				local _, _, tier, column, rank = GetTalentInfo(tab, i, false, false, group)
				talents[#talents + 1] = { tier = tier or 0, column = column or 0, rank = rank or 0 }
			end
			table.sort(talents, function(a, b)
				if a.tier ~= b.tier then return a.tier < b.tier end
				return a.column < b.column
			end)

			local digits, points = {}, 0
			for i, t in ipairs(talents) do
				digits[i] = tostring(t.rank)
				points = points + t.rank
			end
			result[#result + 1] = { group = group, tab = tab, points = points, ranks = table.concat(digits) }
		end
	end
	return result
end

function Scanner.Glyphs()
	local result = {}
	local groups = GetNumTalentGroups and GetNumTalentGroups() or 1
	for group = 1, groups do
		local ids = {}
		for socket = 1, NUM_GLYPH_SLOTS or 6 do
			local _, _, spellID = GetGlyphSocketInfo(socket, group)
			ids[socket] = spellID or 0
		end
		result[group] = ids
	end
	return result
end

-- Professions have no id-based API in 3.3.5: skill lines are matched by
-- their localized name against the localized name of each profession spell.
local PROFESSION_SPELLS = {
	ALCHEMY = 2259,
	BLACKSMITHING = 2018,
	ENCHANTING = 7411,
	ENGINEERING = 4036,
	INSCRIPTION = 45357,
	JEWELCRAFTING = 25229,
	LEATHERWORKING = 2108,
	MINING = 2575,
	SKINNING = 8613,
	TAILORING = 3908,
}
-- Herbalism's spell is "Herb Gathering", which differs from the skill name.
local HERBALISM_NAMES = { Herbalism = true, ["Травничество"] = true }

function Scanner.Professions()
	local byName = {}
	for key, spellID in pairs(PROFESSION_SPELLS) do
		local name = GetSpellInfo(spellID)
		if name then byName[name] = key end
	end

	-- Collapsed headers hide their lines; expand from the bottom up so that
	-- indices of not yet visited lines do not shift.
	for i = GetNumSkillLines(), 1, -1 do
		local _, isHeader, isExpanded = GetSkillLineInfo(i)
		if isHeader and not isExpanded then ExpandSkillHeader(i) end
	end

	local result = {}
	for i = 1, GetNumSkillLines() do
		local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
		if name and not isHeader then
			local key = byName[name] or (HERBALISM_NAMES[name] and "HERBALISM")
			if key then
				result[#result + 1] = { key = key, rank = rank or 0, max = maxRank or 0 }
			end
		end
	end
	return result
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
	return nil
end

-- Character sheet numbers. They include active buffs, so the bot warns when
-- a snapshot was taken buffed; they are used to cross-check its own math.
function Scanner.Stats()
	local CR = function(name, fallback) return _G[name] or fallback end
	local s = {}

	local function rating(key, cr)
		s[key] = Call(GetCombatRating, cr)
		s[key .. "Pct"] = Call(GetCombatRatingBonus, cr)
	end
	rating("hitMelee", CR("CR_HIT_MELEE", 6))
	rating("hitRanged", CR("CR_HIT_RANGED", 7))
	rating("hitSpell", CR("CR_HIT_SPELL", 8))
	rating("critMelee", CR("CR_CRIT_MELEE", 9))
	rating("critRanged", CR("CR_CRIT_RANGED", 10))
	rating("critSpell", CR("CR_CRIT_SPELL", 11))
	rating("hasteMelee", CR("CR_HASTE_MELEE", 18))
	rating("hasteRanged", CR("CR_HASTE_RANGED", 19))
	rating("hasteSpell", CR("CR_HASTE_SPELL", 20))
	rating("expertise", CR("CR_EXPERTISE", 24))
	rating("arp", CR("CR_ARMOR_PENETRATION", 25))
	rating("defense", CR("CR_DEFENSE_SKILL", 2))

	-- Total spell haste % (rating, talents and auras): the haste card
	-- derives the part that does not come from rating.
	s.spellHaste = Call(UnitSpellHaste, "player")

	-- Hit chance from talents and auras, on top of rating.
	s.hitMod = Call(GetHitModifier)
	s.spellHitMod = Call(GetSpellHitModifier)

	local mh, oh = Call(GetExpertise)
	s.expMH, s.expOH = mh, oh

	local base, pos, neg = UnitAttackPower("player")
	s.ap = (base or 0) + (pos or 0) + (neg or 0)
	base, pos, neg = UnitRangedAttackPower("player")
	s.rap = (base or 0) + (pos or 0) + (neg or 0)

	local sp = 0
	for school = 2, 7 do
		sp = math.max(sp, Call(GetSpellBonusDamage, school) or 0)
	end
	s.sp = sp
	s.heal = Call(GetSpellBonusHealing)

	local statKeys = { "str", "agi", "sta", "int", "spi" }
	for i, key in ipairs(statKeys) do
		local _, effective = UnitStat("player", i)
		s[key] = effective
	end
	local _, armor = UnitArmor("player")
	s.armor = armor
	s.hp = UnitHealthMax("player")
	s.mana = UnitPowerMax("player", 0)
	s.dodge = Call(GetDodgeChance)
	s.parry = Call(GetParryChance)
	s.block = Call(GetBlockChance)

	local buffs = 0
	while UnitBuff("player", buffs + 1) do
		buffs = buffs + 1
	end
	s.buffs = buffs

	return s
end
