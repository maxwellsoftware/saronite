-- Fixture: a frost Death Knight with a few deliberate problems
-- (unenchanted cloak and boots, one empty socket).

local GEM = "Самоцветы"
local ARMOR = "Доспехи"

GEM_BY_ENCHANT[3621] = 41398 -- meta
GEM_BY_ENCHANT[3519] = 40111 -- red, +16 STR (phase-appropriate blue quality gem)
GEM_BY_ENCHANT[3525] = 40125 -- orange

local function item(id, quality, ilvl, itemType, equipLoc, stats)
	FAKE.items[id] = { quality, ilvl, itemType, equipLoc, stats }
end

item(41398, 4, 80, GEM, "", {})
item(40111, 3, 80, GEM, "", {})
item(40125, 3, 80, GEM, "", {})

item(40565, 4, 226, ARMOR, "INVTYPE_HEAD", { ITEM_MOD_STRENGTH_SHORT = 74, ITEM_MOD_STAMINA_SHORT = 98, ITEM_MOD_HIT_RATING_SHORT = 49, RESISTANCE0_NAME = 1914, EMPTY_SOCKET_META = 1, EMPTY_SOCKET_RED = 1 })
item(40387, 4, 226, ARMOR, "INVTYPE_NECK", { ITEM_MOD_STRENGTH_SHORT = 40, ITEM_MOD_CRIT_RATING_SHORT = 34 })
item(40568, 4, 226, ARMOR, "INVTYPE_SHOULDER", { ITEM_MOD_STRENGTH_SHORT = 58, ITEM_MOD_HASTE_RATING_SHORT = 38, EMPTY_SOCKET_YELLOW = 1 })
item(40550, 4, 226, ARMOR, "INVTYPE_CHEST", { ITEM_MOD_STRENGTH_SHORT = 80, ITEM_MOD_EXPERTISE_RATING_SHORT = 40, EMPTY_SOCKET_RED = 1, EMPTY_SOCKET_YELLOW = 1 })
item(40278, 4, 226, ARMOR, "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 61, ITEM_MOD_HIT_RATING_SHORT = 41 })
item(40556, 4, 226, ARMOR, "INVTYPE_LEGS", { ITEM_MOD_STRENGTH_SHORT = 81, ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = 54 })
item(40591, 4, 226, ARMOR, "INVTYPE_FEET", { ITEM_MOD_STRENGTH_SHORT = 60 })
item(40330, 4, 226, ARMOR, "INVTYPE_WRIST", { ITEM_MOD_STRENGTH_SHORT = 47 })
item(40552, 4, 226, ARMOR, "INVTYPE_HAND", { ITEM_MOD_STRENGTH_SHORT = 61 })
item(40717, 4, 226, ARMOR, "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 41 })
item(40075, 4, 213, ARMOR, "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 35 })
item(40256, 4, 226, ARMOR, "INVTYPE_TRINKET", { ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = 84 })
item(40684, 4, 226, ARMOR, "INVTYPE_TRINKET", { ITEM_MOD_ATTACK_POWER_SHORT = 136 })
item(40403, 4, 226, ARMOR, "INVTYPE_CLOAK", { ITEM_MOD_STRENGTH_SHORT = 40 })
item(40189, 4, 226, "Оружие", "INVTYPE_WEAPON", { ITEM_MOD_STRENGTH_SHORT = 40, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 155.5 })
item(40703, 4, 213, "Оружие", "INVTYPE_WEAPON", { ITEM_MOD_STRENGTH_SHORT = 35, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 141.07 })
item(40207, 4, 226, ARMOR, "INVTYPE_RELIC", {})

-- bags: spare gear, gems and things that must be filtered out
item(40384, 4, 226, "Оружие", "INVTYPE_2HWEAPON", { ITEM_MOD_STRENGTH_SHORT = 101, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 186.6, EMPTY_SOCKET_RED = 1 })
item(39401, 4, 213, ARMOR, "INVTYPE_HEAD", { ITEM_MOD_STRENGTH_SHORT = 60 })
item(1234, 0, 10, ARMOR, "INVTYPE_CHEST", {})            -- grey junk
item(41599, 1, 80, "Сумки", "INVTYPE_BAG", {})           -- a bag
item(33447, 1, 70, "Расходуемые", "", {})                -- potion
item(37000, 3, 200, ARMOR, "INVTYPE_TABARD", {})         -- tabard
-- bank
item(40343, 4, 226, ARMOR, "INVTYPE_SHIELD", { ITEM_MOD_STAMINA_SHORT = 60 })
-- random suffix item: negative suffix id, unique id carries the factor
item(36000, 3, 187, ARMOR, "INVTYPE_CLOAK", {})

FAKE.equipped = {
	[1] = MakeLink(40565, 3817, 3621, 3519),
	[2] = MakeLink(40387),
	[3] = MakeLink(40568, 3808, 3525),
	[5] = MakeLink(40550, 3832, 3519, 0), -- yellow socket left empty
	[6] = MakeLink(40278, 0, 3519), -- belt buckle socket filled
	[7] = MakeLink(40556, 3823),
	[8] = MakeLink(40591), -- no enchant
	[9] = MakeLink(40330, 3845),
	[10] = MakeLink(40552, 3604),
	[11] = MakeLink(40717),
	[12] = MakeLink(40075),
	[13] = MakeLink(40256),
	[14] = MakeLink(40684),
	[15] = MakeLink(40403), -- no enchant
	[16] = MakeLink(40189, 3370),
	[17] = MakeLink(40703, 3368),
	[18] = MakeLink(40207),
	[4] = MakeLink(37000), -- shirt slot, must be skipped
}

FAKE.bags[0][1] = { MakeLink(40384, 0, 3519), 1 }
FAKE.bags[0][2] = { MakeLink(1234), 1 }
FAKE.bags[1][5] = { MakeLink(39401), 1 }
FAKE.bags[1][6] = { MakeLink(41599), 1 }
FAKE.bags[2][1] = { MakeLink(40111), 5 }
FAKE.bags[2][2] = { MakeLink(33447), 20 }
FAKE.bags[4][20] = { MakeLink(37000), 1 }

FAKE.bags[-1] = { [3] = { MakeLink(40343), 1 }, [4] = { MakeLink(36000, 0, 0, 0, 0, 0, -39, 2031682), 1 } }
FAKE.bagSizes[-1] = 28
