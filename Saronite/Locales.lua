local _, ns = ...

-- UI texts only. Data read from the client (profession names, socket
-- bonuses, item and enchant names) always stays in the client language.
local EN = {
	BUTTON = "Saronite",
	BUTTON_TOOLTIP = "Click: build the best setup from your gear.\nRight-click: export / import window.\nShift+drag to move the button.",
	COMPUTE = "Build setup",
	CALCULATING = "Calculating the best setup…",
	AS_TANK = "As tank",
	AS_DPS = "As DPS",
	OPTIMIZE_ERROR = "Could not build a setup: %s",
	EXPORT_TITLE = "Export",
	IMPORT_TITLE = "Import",
	REFRESH = "Refresh",
	EXPORT = "Export",
	IMPORT = "Import",
	IMPORT_SHOW = "Show setup",
	LAST_SETUP = "Last setup",
	NO_LAST_SETUP = "No setup built yet.",
	HINT = "Ctrl+C to copy and share: a guildmate can paste it into Import.",
	IMPORT_HINT = "Paste a guildmate's export (!SAR:) to see their best setup, or a bot answer (!SARP:).",
	IMPORT_BAD = "Not a Saronite string: it starts with !SAR: or !SARP:",
	IMPORT_DAMAGED = "The string is damaged — copy it again.",
	IMPORT_VERSION = "The string is from a newer version — update the addon.",
	LENGTH = "Length: %d characters.",
	TRIMMED_BAGSTATS = "Item stats for bags/bank were left out to fit into one Telegram message.",
	TRIMMED_BANK = "Bank items were left out to fit into one Telegram message.",
	TRIMMED_BAGS = "Bag items were left out to fit into one Telegram message.",
	TOO_LONG = "The string is longer than one Telegram message.",
	BANK_SCANNED = "Bank scanned: %d items are taken into account.",
	BANK_NONE = "Bank was never opened on this character — open it once so its gear is taken into account.",
	BANK_AGE = "Bank scanned %s ago.",
	USAGE = "/sar — window, /sar import — paste a string, /sar bank — bank scan status, /sar sources — item sources in tooltips on/off, /sar lang ru|en — UI language",
	ERROR = "Export failed: %s",
	ENCHANT = "Enchant",
	EMPTY_SLOT = "—",
	LOC_BAG = "in bags",
	LOC_BANK = "in the bank",
	BUCKLE = "+ belt buckle",
	CAP_HIT = "Hit",
	CAP_EXP = "Expertise",
	TAB_CURRENT = "Current optimization",
	TAB_BIS = "BiS",
	TIP_OWNED = "You have this item",
	BIS_TITLE = "Phase %s BiS list",
	BIS_OWNED = "You have %d of %d items.",
	BIS_HELP = "Items, gems and enchants of the BiS list (wowtbc.gg via Bistooltip). Next to every item: other options from the list. Hover for where it drops.",
	SOURCE = "Source:",
	VENDOR = "Vendor",
	SOURCES_ON = "Item sources in tooltips: on.",
	SOURCES_OFF = "Item sources in tooltips: off.",
	CHANGES = "Changes:",
	CHANGES_ITEMS = "items %d",
	CHANGES_ENCHANTS = "enchants %d",
	CHANGES_GEMS = "gems in %d items",
	NO_CHANGES = "Nothing to change.",
	NO_CHANGE = "No change",
	COL_NOW = "Now",
	COL_AFTER = "After",
	ROLE_TANK = "Tank",
	ROLE_DPS = "DPS",
	ALTERNATIVE = "Alternative",
	TIP_ALT = "Alternative from the phase %s BiS list",
	TIP_WEAK = "Weak for this phase: worth replacing",
	NOTE_BANK = "%s: the item is in the bank.",
	SLOTS = {
		[1] = "Head", [2] = "Neck", [3] = "Shoulders", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
		[9] = "Wrists", [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2",
		[15] = "Back", [16] = "Main hand", [17] = "Off hand", [18] = "Ranged / relic",
	},
	TIP_EQUIP = "Equip this item",
	TIP_BIS = "BiS of phase %s for this slot",
	TIP_BUCKLE = "Belt buckle socket (Eternal Belt Buckle)",
	TIP_REPLACE = "Replaces: %s",
	TIP_INSERT = "Insert into the empty socket",
	TIP_APPLY = "Apply this enchant",
	TIP_OFFSPEC = "Not for your spec: %s is wasted",
	NOTE_OFFSPEC = "Not for your spec: %s — alternatives are shown next to the item.",
	OLD_ENCHANT = "the current enchant",
	CAP_OF = "Cap %s",
	CAP_DONE = "Cap reached",
	CAP_SHORT = "Below the cap",
	HIT_FROM = "gear %d rating + talents/race %.0f%%",
	EXP_FROM = "gear %d rating + talents %d",
	HIT_HELP = "Chance to hit a raid boss. Over the cap hit does nothing (except auto attacks with two weapons).",
	EXP_HELP = "Removes the boss's dodges; 26 removes all of them. Tanks gain up to 56 (parries).",
	GEAR_STATS = "Gear stats",
	TAB_TALENTS = "Talents & glyphs",
	CAP_DEF = "Defense",
	DEF_FROM = "gear %d rating",
	DEF_HELP = "540 defense makes a plate tank immune to critical hits from raid bosses. Druids get the immunity from Survival of the Fittest and do not need defense.",
	PRIORITY = "Stat priority",
	HEALER_CAPS = "Healers have no hit or expertise cap: all budget goes into the stats below.",
	BUILDS = "Recommended builds",
	BUILDS_SOURCE = "Talents and glyphs: wowsims presets for the spec.",
	NO_BUILDS = "No recommended build for this spec.",
	GLYPHS_MAJOR = "Major glyphs",
	GLYPHS_MINOR = "Minor glyphs",
	GLYPH_HAVE = "Equipped",
	GLYPH_MISSING = "Missing",
	TIP_GLYPH_HAVE = "You have this glyph",
	TIP_GLYPH_MISSING = "You do not have this glyph",
	TIP_BUILD_RANK = "Build: %d/%d",
	TIP_YOUR_RANK = "You: %d/%d",
	TALENTS_YOURS = "Yours: %s",
	TALENTS_MATCH = "Your talents match this build.",
	TALENTS_DIFF = "Talents that differ from yours: %d",
	LEGEND = "Border:",
	LEGEND_MATCH = "as yours",
	LEGEND_DIFF = "differs",
	CLICK_HINT = "Click an icon to open it, Shift+click to link it in chat.",
	STAT_STR = "Strength", STAT_AGI = "Agility", STAT_STA = "Stamina", STAT_INT = "Intellect", STAT_SPI = "Spirit",
	STAT_AP = "Attack power", STAT_SP = "Spell power", STAT_CRIT = "Crit rating", STAT_HASTE = "Haste rating",
	STAT_ARP = "Armor pen.", STAT_DEF = "Defense", STAT_DODGE = "Dodge", STAT_PARRY = "Parry", STAT_BLOCK = "Block",
	STAT_BLOCKV = "Block value", STAT_MP5 = "Mana per 5 s", STAT_ARMOR = "Armor", STAT_RESIL = "Resilience",
}

local RU = setmetatable({}, { __index = EN })
do
	RU.BUTTON_TOOLTIP = "Клик — собрать лучший сетап из твоих вещей.\nПравый клик — окно экспорта и импорта.\nShift+перетаскивание — сдвинуть кнопку."
	RU.COMPUTE = "Собрать сетап"
	RU.CALCULATING = "Подбираю лучший сетап…"
	RU.AS_TANK = "Как танк"
	RU.AS_DPS = "Как ДД"
	RU.OPTIMIZE_ERROR = "Не получилось собрать сетап: %s"
	RU.EXPORT_TITLE = "Экспорт"
	RU.IMPORT_TITLE = "Импорт"
	RU.REFRESH = "Обновить"
	RU.EXPORT = "Экспорт"
	RU.IMPORT = "Импорт"
	RU.IMPORT_SHOW = "Показать сетап"
	RU.LAST_SETUP = "Последний сетап"
	RU.NO_LAST_SETUP = "Сетап ещё не собирался."
	RU.HINT = "Ctrl+C — скопировать и поделиться: согильдиец вставит строку в «Импорт»."
	RU.IMPORT_HINT = "Вставь строку экспорта согильдийца (!SAR:) — увидишь его лучший сетап. Ответ бота (!SARP:) тоже подойдёт."
	RU.IMPORT_BAD = "Это не строка Saronite: она начинается с !SAR: или !SARP:"
	RU.IMPORT_DAMAGED = "Строка повреждена — скопируй её ещё раз."
	RU.IMPORT_VERSION = "Строка от более новой версии — обнови аддон."
	RU.LENGTH = "Длина: %d символов."
	RU.TRIMMED_BAGSTATS = "Характеристики вещей из сумок/банка не включены, чтобы строка влезла в одно сообщение Telegram."
	RU.TRIMMED_BANK = "Вещи из банка не включены, чтобы строка влезла в одно сообщение Telegram."
	RU.TRIMMED_BAGS = "Вещи из сумок не включены, чтобы строка влезла в одно сообщение Telegram."
	RU.TOO_LONG = "Строка длиннее одного сообщения Telegram."
	RU.BANK_SCANNED = "Банк просканирован: учитывается %d вещей."
	RU.BANK_NONE = "Банк на этом персонаже ещё не открывался — открой его один раз, чтобы вещи оттуда учитывались."
	RU.BANK_AGE = "Банк просканирован %s назад."
	RU.USAGE = "/sar — окно, /sar import — вставить строку, /sar bank — состояние скана банка, /sar sources — источники вещей в подсказках вкл/выкл, /sar lang ru|en — язык интерфейса"
	RU.ERROR = "Ошибка экспорта: %s"
	RU.ENCHANT = "Чары"
	RU.LOC_BAG = "в сумке"
	RU.LOC_BANK = "в банке"
	RU.BUCKLE = "+ пряжка"
	RU.CAP_HIT = "Меткость"
	RU.CAP_EXP = "Мастерство"
	RU.TAB_CURRENT = "Текущая оптимизация"
	RU.TAB_BIS = "BiS"
	RU.TIP_OWNED = "Эта вещь у тебя есть"
	RU.BIS_TITLE = "BiS-лист фазы %s"
	RU.BIS_OWNED = "У тебя есть %d из %d вещей."
	RU.BIS_HELP = "Вещи, камни и чары из BiS-листа (wowtbc.gg через Bistooltip). Рядом с каждой вещью — другие варианты из списка. Наведи, чтобы увидеть, откуда падает."
	RU.SOURCE = "Источник:"
	RU.VENDOR = "Торговец"
	RU.SOURCES_ON = "Источники вещей в подсказках: включены."
	RU.SOURCES_OFF = "Источники вещей в подсказках: выключены."
	RU.CHANGES = "Изменения:"
	RU.CHANGES_ITEMS = "вещей %d"
	RU.CHANGES_ENCHANTS = "чар %d"
	RU.CHANGES_GEMS = "камни в %d вещах"
	RU.NO_CHANGES = "Менять ничего не нужно."
	RU.NO_CHANGE = "Без изменений"
	RU.COL_NOW = "Сейчас"
	RU.COL_AFTER = "После"
	RU.ROLE_TANK = "Танк"
	RU.ROLE_DPS = "ДД"
	RU.ALTERNATIVE = "Альтернатива"
	RU.TIP_ALT = "Альтернатива из BiS-списка фазы %s"
	RU.TIP_WEAK = "Слабая вещь для этой фазы — стоит заменить"
	RU.NOTE_BANK = "%s: вещь лежит в банке."
	RU.SLOTS = {
		[1] = "Голова", [2] = "Шея", [3] = "Плечи", [5] = "Грудь", [6] = "Пояс", [7] = "Ноги", [8] = "Ступни",
		[9] = "Запястья", [10] = "Кисти рук", [11] = "Кольцо 1", [12] = "Кольцо 2", [13] = "Аксессуар 1",
		[14] = "Аксессуар 2", [15] = "Спина", [16] = "Правая рука", [17] = "Левая рука", [18] = "Дальний бой / реликвия",
	}
	RU.TIP_EQUIP = "Надень эту вещь"
	RU.TIP_BIS = "BiS фазы %s для этого слота"
	RU.TIP_BUCKLE = "Гнездо пряжки (Вечная пряжка)"
	RU.TIP_REPLACE = "Вместо: %s"
	RU.TIP_INSERT = "Вставить в пустое гнездо"
	RU.TIP_APPLY = "Наложить эти чары"
	RU.TIP_OFFSPEC = "Не для твоего спека: пропадают %s"
	RU.NOTE_OFFSPEC = "Не по спеку: %s — альтернативы показаны рядом с вещью."
	RU.OLD_ENCHANT = "текущих чар"
	RU.CAP_OF = "Кап %s"
	RU.CAP_DONE = "Кап закрыт"
	RU.CAP_SHORT = "Ниже капа"
	RU.HIT_FROM = "экипировка %d рейтинга + таланты/раса %.0f%%"
	RU.EXP_FROM = "экипировка %d рейтинга + таланты %d"
	RU.HIT_HELP = "Шанс попасть по рейд-боссу. Выше капа меткость не нужна (кроме автоатак с двумя оружиями)."
	RU.EXP_HELP = "Убирает уклонения босса, 26 — все. Танку полезно до 56 (парирования)."
	RU.GEAR_STATS = "Характеристики экипировки"
	RU.TAB_TALENTS = "Таланты и символы"
	RU.CAP_DEF = "Защита"
	RU.DEF_FROM = "экипировка %d рейтинга"
	RU.DEF_HELP = "540 защиты делают танка в латах неуязвимым к критическим ударам рейд-боссов. Друиду неуязвимость даёт «Выживание сильнейшего», защита ему не нужна."
	RU.PRIORITY = "Приоритет характеристик"
	RU.HEALER_CAPS = "У лекарей нет капа меткости и мастерства: весь бюджет идёт в характеристики ниже."
	RU.BUILDS = "Рекомендуемые сборки"
	RU.BUILDS_SOURCE = "Таланты и символы: пресеты wowsims для спека."
	RU.NO_BUILDS = "Для этого спека нет рекомендуемой сборки."
	RU.GLYPHS_MAJOR = "Большие символы"
	RU.GLYPHS_MINOR = "Малые символы"
	RU.GLYPH_HAVE = "Стоит"
	RU.GLYPH_MISSING = "Нет"
	RU.TIP_GLYPH_HAVE = "Этот символ у тебя стоит"
	RU.TIP_GLYPH_MISSING = "Этого символа у тебя нет"
	RU.TIP_BUILD_RANK = "В сборке: %d/%d"
	RU.TIP_YOUR_RANK = "У тебя: %d/%d"
	RU.TALENTS_YOURS = "Твои: %s"
	RU.TALENTS_MATCH = "Твои таланты совпадают со сборкой."
	RU.TALENTS_DIFF = "Талантов отличается от твоих: %d"
	RU.LEGEND = "Рамка:"
	RU.LEGEND_MATCH = "как у тебя"
	RU.LEGEND_DIFF = "отличается"
	RU.CLICK_HINT = "Клик по иконке — открыть, Shift+клик — ссылка в чат."
	RU.STAT_STR, RU.STAT_AGI, RU.STAT_STA, RU.STAT_INT, RU.STAT_SPI = "Сила", "Ловкость", "Выносливость", "Интеллект", "Дух"
	RU.STAT_AP, RU.STAT_SP, RU.STAT_CRIT, RU.STAT_HASTE = "Сила атаки", "Сила заклинаний", "Рейтинг крита", "Рейтинг скорости"
	RU.STAT_ARP, RU.STAT_DEF, RU.STAT_DODGE, RU.STAT_PARRY = "Пробивание брони", "Защита", "Уклонение", "Парирование"
	RU.STAT_BLOCK, RU.STAT_BLOCKV, RU.STAT_MP5, RU.STAT_ARMOR = "Блок", "Показатель блока", "Мана за 5 сек", "Броня"
	RU.STAT_RESIL = "Устойчивость"
end

local LANGUAGES = { en = EN, ru = RU }

-- ns.lang: "en" or "ru", the client language by default; /sar lang and the
-- RU/EN switch in the windows change it (saved in SaroniteDB.lang).
ns.lang = GetLocale() == "ruRU" and "ru" or "en"

ns.L = setmetatable({}, {
	__index = function(_, key)
		return (LANGUAGES[ns.lang] or EN)[key]
	end,
})

function ns.SetLanguage(lang)
	if LANGUAGES[lang] then ns.lang = lang end
end
