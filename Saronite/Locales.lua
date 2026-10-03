local _, ns = ...

local L = {
	TITLE = "Saronite",
	BUTTON = "Export",
	BUTTON_TOOLTIP = "Export gear for the guild bot.\nShift+drag to move the button.",
	REFRESH = "Refresh",
	CLOSE = "Close",
	HINT = "Press Ctrl+C to copy, then send it to the bot in Telegram.",
	LENGTH = "Length: %d characters.",
	TRIMMED_BAGSTATS = "Item stats for bags/bank were left out to fit into one Telegram message.",
	TRIMMED_BANK = "Bank items were left out to fit into one Telegram message.",
	TRIMMED_BAGS = "Bag items were left out to fit into one Telegram message.",
	TOO_LONG = "The string is still longer than one Telegram message; send it anyway — the bot will glue the parts together.",
	BANK_SCANNED = "Bank scanned: %d items will be included in the export.",
	BANK_NONE = "Bank was never opened on this character — open it once so its gear is included.",
	BANK_AGE = "Bank scanned %s ago.",
	USAGE = "/sar — open export window, /sar bank — bank scan status",
	ERROR = "Export failed: %s",
}

if GetLocale() == "ruRU" then
	L.BUTTON = "Экспорт"
	L.BUTTON_TOOLTIP = "Экспорт экипировки для гир-бота.\nShift+перетаскивание — сдвинуть кнопку."
	L.REFRESH = "Обновить"
	L.CLOSE = "Закрыть"
	L.HINT = "Нажмите Ctrl+C, чтобы скопировать, и отправьте боту в Telegram."
	L.LENGTH = "Длина: %d символов."
	L.TRIMMED_BAGSTATS = "Характеристики вещей из сумок/банка не включены, чтобы строка влезла в одно сообщение Telegram."
	L.TRIMMED_BANK = "Вещи из банка не включены, чтобы строка влезла в одно сообщение Telegram."
	L.TRIMMED_BAGS = "Вещи из сумок не включены, чтобы строка влезла в одно сообщение Telegram."
	L.TOO_LONG = "Строка всё равно длиннее одного сообщения Telegram — отправьте как есть, бот склеит части."
	L.BANK_SCANNED = "Банк просканирован: в экспорт попадёт %d вещей."
	L.BANK_NONE = "Банк на этом персонаже ещё не открывался — откройте его один раз, чтобы вещи оттуда попали в экспорт."
	L.BANK_AGE = "Банк просканирован %s назад."
	L.USAGE = "/sar — окно экспорта, /sar bank — состояние скана банка"
	L.ERROR = "Ошибка экспорта: %s"
end

ns.L = L
