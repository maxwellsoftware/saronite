local ADDON_NAME, ns = ...

ns.VERSION = "0.3.0"
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
			ns.UI.Init()
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
SlashCmdList.SARONITE = function(msg)
	msg = string.lower(strtrim(msg or ""))
	if msg == "bank" then
		local bank = ns.GetBank()
		if not bank then
			ns.Print(L.BANK_NONE)
		else
			ns.Print(string.format(L.BANK_SCANNED, #bank.items) .. " " ..
				string.format(L.BANK_AGE, SecondsToTime(time() - bank.time)))
		end
	elseif msg == "import" then
		ns.UI.Show("import")
	elseif msg == "help" or msg == "?" then
		ns.Print(L.USAGE)
	else
		ns.UI.Toggle()
	end
end
