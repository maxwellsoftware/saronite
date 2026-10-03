-- Minimal WoW 3.3.5a API emulation for running the addon outside the game.
-- The fake character lives in FAKE; tests tweak it before loading the addon.

FAKE = {
	locale = "ruRU",
	realm = "Frostmourne",
	name = "Артас",
	class = { "Рыцарь смерти", "DEATHKNIGHT" },
	race = { "Человек", "Human" },
	sex = 2,
	level = 80,
	time = 1790000000,
	activeGroup = 1,
	-- [group][tab] = list of { tier, column, rank } in GetTalentInfo order
	-- (deliberately not positional, the addon must sort).
	talents = {
		[1] = {
			[1] = { { 2, 1, 0 }, { 1, 1, 0 } },
			-- sorted: (1,1)2 (1,2)3 (2,3)3 (3,1)5 (3,2)0 (4,1)3 — index 5 is
			-- the 3/3 one-handed hit talent the bot must count
			[2] = { { 1, 2, 3 }, { 1, 1, 2 }, { 3, 1, 5 }, { 2, 3, 3 }, { 4, 1, 3 }, { 3, 2, 0 } },
			[3] = { { 1, 1, 5 }, { 2, 1, 1 } },
		},
		[2] = {
			[1] = { { 1, 1, 5 }, { 2, 1, 0 } },
			[2] = { { 1, 1, 0 }, { 1, 2, 0 }, { 2, 3, 0 }, { 3, 1, 0 }, { 3, 2, 0 }, { 4, 1, 0 } },
			[3] = { { 1, 1, 0 }, { 2, 1, 0 } },
		},
	},
	glyphs = { [1] = { 58631, 0, 63335, 0, 0, 0 }, [2] = { 0, 0, 0, 0, 0, 0 } },
	skills = {
		{ "Профессии", true, false },
		{ "Ювелирное дело", false, false, 450, 450 },
		{ "Горное дело", false, false, 450, 450 },
		{ "Вторичные навыки", true, true },
		{ "Кулинария", false, false, 300, 450 },
	},
	stats = {
		ratings = { [6] = 210, [7] = 0, [8] = 210, [9] = 400, [18] = 300, [24] = 80, [25] = 150 },
		expertise = { 19, 19 },
		ap = { 4000, 900, 0 }, rap = { 1000, 0, 0 },
		primary = { 1800, 400, 1500, 80, 120 },
		armor = 15000, hp = 30000, mana = 0, buffs = 2,
	},
	-- link pieces: itemString, quality, ilvl, itemType, equipLoc, stats
	items = {},
	equipped = {},
	bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} },
	bagSizes = { [0] = 16, [1] = 20, [2] = 20, [3] = 20, [4] = 20 },
}

local function noop() end

-- Frames: any method call is a no-op, but scripts and events are recorded so
-- tests can fire events.
FRAMES = {}
local frameMethods = {}
function frameMethods:RegisterEvent(event) self.events[event] = true end
function frameMethods:SetScript(name, fn) self.scripts[name] = fn end
function frameMethods:GetScript(name) return self.scripts[name] end
function frameMethods:SetText(t) self.text = t end
function frameMethods:GetText() return self.text or "" end
function frameMethods:IsShown() return self.shown end
function frameMethods:Show() self.shown = true end
function frameMethods:Hide() self.shown = false end
function frameMethods:CreateFontString() return NewFrame() end

function NewFrame()
	local f = { events = {}, scripts = {} }
	return setmetatable(f, {
		__index = function(_, key)
			return frameMethods[key] or noop
		end,
	})
end

function CreateFrame(_, name)
	local f = NewFrame()
	FRAMES[#FRAMES + 1] = f
	if name then _G[name] = f end
	return f
end

function FireEvent(event, ...)
	for _, f in ipairs(FRAMES) do
		local handler = f.scripts.OnEvent
		if f.events[event] and handler then handler(f, event, ...) end
	end
end

UIParent = NewFrame()
PaperDollFrame = NewFrame()
CharacterMainHandSlot = NewFrame()
GameTooltip = NewFrame()
UISpecialFrames = {}
SlashCmdList = {}
CHAT_LOG = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) CHAT_LOG[#CHAT_LOG + 1] = msg end }
NUM_BAG_SLOTS = 4
NUM_GLYPH_SLOTS = 6

function strtrim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
function SecondsToTime(s) return tostring(s) .. " sec" end
function IsShiftKeyDown() return false end
function time() return FAKE.time end

function GetLocale() return FAKE.locale end
function GetBuildInfo() return "3.3.5", "12340", "Jun 24 2010", 30300 end
function GetRealmName() return FAKE.realm end
function UnitName() return FAKE.name end
function UnitClass() return FAKE.class[1], FAKE.class[2] end
function UnitRace() return FAKE.race[1], FAKE.race[2] end
function UnitSex() return FAKE.sex end
function UnitLevel() return FAKE.level end

function GetActiveTalentGroup() return FAKE.activeGroup end
function GetNumTalentGroups() return 2 end
function GetNumTalentTabs() return 3 end
function GetNumTalents(tab) return #FAKE.talents[1][tab] end
function GetTalentInfo(tab, index, _, _, group)
	local t = FAKE.talents[group or 1][tab][index]
	return "Talent" .. tab .. "_" .. index, "icon", t[1], t[2], t[3], 5
end
function GetGlyphSocketInfo(socket, group)
	local id = FAKE.glyphs[group][socket]
	return true, 1, id ~= 0 and id or nil
end

local SPELL_NAMES = {
	[2259] = "Алхимия", [2018] = "Кузнечное дело", [7411] = "Наложение чар",
	[4036] = "Инженерное дело", [45357] = "Начертание", [25229] = "Ювелирное дело",
	[2108] = "Кожевничество", [2575] = "Горное дело", [8613] = "Снятие шкур", [3908] = "Портняжное дело",
}
function GetSpellInfo(id) return SPELL_NAMES[id] end

function GetNumSkillLines()
	local n = 0
	for _, s in ipairs(FAKE.skills) do
		n = n + 1
		if s[2] and not s[3] then break end -- lines below a collapsed header are hidden
	end
	return n
end
function GetSkillLineInfo(i)
	local s = FAKE.skills[i]
	if not s then return nil end
	return s[1], s[2], s[3], s[4] or 0, 0, 0, s[5] or 0
end
function ExpandSkillHeader(i)
	FAKE.skills[i][3] = true
	-- Expand everything below too, good enough for the fixture.
	for _, s in ipairs(FAKE.skills) do if s[2] then s[3] = true end end
end

local s = FAKE.stats
function GetCombatRating(cr) return s.ratings[cr] or 0 end
function GetCombatRatingBonus(cr)
	local perPct = { [6] = 32.79, [7] = 32.79, [8] = 26.23, [9] = 45.91, [18] = 32.79, [24] = 8.2, [25] = 13.99 }
	if not perPct[cr] then return 0 end
	return (s.ratings[cr] or 0) / perPct[cr]
end
-- GetHitModifier / GetSpellHitModifier do not exist in the 3.3.5 client.
function GetExpertise() return s.expertise[1], s.expertise[2] end
function UnitAttackPower() return s.ap[1], s.ap[2], s.ap[3] end
function UnitRangedAttackPower() return s.rap[1], s.rap[2], s.rap[3] end
function GetSpellBonusDamage() return 0 end
function GetSpellBonusHealing() return 0 end
function UnitStat(_, i) return s.primary[i], s.primary[i], 0, 0 end
function UnitArmor() return s.armor, s.armor end
function UnitHealthMax() return s.hp end
function UnitPowerMax() return s.mana end
function GetDodgeChance() return 5.5 end
function GetParryChance() return 6.25 end
function GetBlockChance() return 0 end
function UnitBuff(_, i) if i <= s.buffs then return "Buff" .. i end end

function GetAuctionItemClasses()
	return "Оружие", "Доспехи", "Сумки", "Расходуемые", "Символы", "Хозяйственные товары",
		"Боеприпасы", "Амуниция", "Рецепты", "Самоцветы", "Разное", "Задания"
end

-- Items are registered by id; a link carries the per-instance parts.
-- FAKE.items[id] = { quality, ilvl, itemType, equipLoc, stats }
function MakeLink(id, enchant, j1, j2, j3, j4, suffix, unique)
	return string.format("|cffa335ee|Hitem:%d:%d:%d:%d:%d:%d:%d:%d:80|h[Item %d]|h|r",
		id, enchant or 0, j1 or 0, j2 or 0, j3 or 0, j4 or 0, suffix or 0, unique or 0, id)
end

local function linkID(link)
	return tonumber(string.match(link or "", "item:(%d+)"))
end

-- gem enchant id -> gem item id
GEM_BY_ENCHANT = {}

function GetItemInfo(link)
	local id = type(link) == "number" and link or linkID(link)
	local info = FAKE.items[id]
	if not info then return nil end
	return "Item " .. id, link, info[1], info[2], 80, info[3], "sub", 1, info[4], "icon", 0
end

function GetItemStats(link)
	local info = FAKE.items[linkID(link)]
	if not info then return nil end
	local copy = {}
	for k, v in pairs(info[5] or {}) do copy[k] = v end
	return copy
end

function GetItemGem(link, index)
	local jewel = tonumber((select(index + 2, string.match(link, "item:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)"))))
	local gemID = jewel and GEM_BY_ENCHANT[jewel]
	if not gemID then return nil end
	return "Gem " .. gemID, MakeLink(gemID)
end

function GetInventoryItemLink(_, slot) return FAKE.equipped[slot] end
function GetContainerNumSlots(bag) return FAKE.bagSizes[bag] or 0 end
function GetContainerItemLink(bag, slot)
	local entry = FAKE.bags[bag] and FAKE.bags[bag][slot]
	return entry and entry[1]
end
function GetContainerItemInfo(bag, slot)
	local entry = FAKE.bags[bag] and FAKE.bags[bag][slot]
	if not entry then return nil end
	return "icon", entry[2] or 1
end
