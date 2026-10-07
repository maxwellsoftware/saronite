local ADDON_NAME, ns = ...

ns.VERSION = "0.9.4"
ns.FORMAT_VERSION = 1

local L = ns.L

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Saronite|r: " .. tostring(msg))
end

-- Per-character key for SavedVariables.
function ns.CharKey()
	return (GetRealmName() or "?") .. "|" .. (UnitName("player") or "?")
end

-- Returns the saved bank snapshot of the current character, or nil.
function ns.GetBank()
	local db = SaroniteDB
	local char = db and db.chars and db.chars[ns.CharKey()]
	return char and char.bank
end

local function InitDB()
	if type(SaroniteDB) ~= "table" then
		SaroniteDB = {}
	end
	local db = SaroniteDB
	db.version = 1
	db.chars = db.chars or {}
	db.chars[ns.CharKey()] = db.chars[ns.CharKey()] or {}
end

-- The bank is only readable while the bank window is open, so its contents
-- are cached in SavedVariables and reused by later exports.
local bankOpen = false

local function SaveBank()
	if not bankOpen then return end
	local char = SaroniteDB.chars[ns.CharKey()]
	char.bank = { time = time(), items = ns.Scanner.ScanBank() }
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("BANKFRAME_CLOSED")
frame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
frame:RegisterEvent("BAG_UPDATE")

frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			InitDB()
			ns.SetLanguage(SaroniteDB.lang or ns.lang)
			ns.Safe(ns.UI.Init)
			ns.Safe(ns.Tooltip.Init)
		end
	elseif event == "BANKFRAME_OPENED" then
		bankOpen = true
		SaveBank()
	elseif event == "BANKFRAME_CLOSED" then
		-- Items are still readable while this event fires.
		SaveBank()
		bankOpen = false
	elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "BAG_UPDATE" then
		SaveBank()
	end
end)

SLASH_SARONITE1 = "/sar"
SLASH_SARONITE2 = "/saronite"
-- SwitchLanguage changes the UI language and relabels open windows.
function ns.SwitchLanguage(lang)
	ns.SetLanguage(lang)
	SaroniteDB.lang = ns.lang
	ns.Safe(ns.UI.Relabel)
	ns.Safe(ns.SetupView.Relabel)
end

-- Errors are printed to chat: WoW hides script errors by default and a
-- silent failure looks like "the addon does nothing".
function ns.Safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		ns.Print("|cffff5555" .. tostring(err) .. "|r")
	end
	return ok
end

local function slash(msg)
	msg = string.lower(strtrim(msg or ""))
	if msg == "bank" then
		local bank = ns.GetBank()
		if not bank then
			ns.Print(L.BANK_NONE)
		else
			ns.Print(string.format(L.BANK_SCANNED, #bank.items) .. " " ..
				string.format(L.BANK_AGE, SecondsToTime(time() - bank.time)))
		end
	elseif msg == "lang" or msg == "lang ru" or msg == "lang en" then
		local lang = string.match(msg, "lang (%a+)") or (ns.lang == "ru" and "en" or "ru")
		ns.SwitchLanguage(lang)
	elseif msg == "sources" then
		ns.Tooltip.Toggle()
	elseif msg == "import" then
		ns.UI.Show("import")
	elseif msg == "help" or msg == "?" then
		ns.Print(L.USAGE)
	else
		ns.UI.Toggle()
	end
end

SlashCmdList.SARONITE = function(msg)
	ns.Safe(slash, msg)
end
