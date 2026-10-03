-- Decodes the bot's answer (!SARP:1!...) into a setup table.
-- Format: docs/response-format.md.
local _, ns = ...

local LibDeflate = LibStub("LibDeflate")

local Import = {}
ns.Import = Import

Import.VERSION = 1

local function split(line)
	local f, start = {}, 1
	while true do
		local sep = string.find(line, "|", start, true)
		if not sep then
			f[#f + 1] = string.sub(line, start)
			return f
		end
		f[#f + 1] = string.sub(line, start, sep - 1)
		start = sep + 1
	end
end

local function num(v) return tonumber(v) or 0 end

-- Returns the setup table, or nil and an error key from the locale
-- (IMPORT_BAD, IMPORT_DAMAGED, IMPORT_VERSION).
function Import.Decode(text)
	text = string.gsub(text or "", "%s", "")
	local version, payload = string.match(text, "!SARP:(%d+)!([%w%(%)]+)")
	if not version then return nil, "IMPORT_BAD" end
	if tonumber(version) ~= Import.VERSION then return nil, "IMPORT_VERSION" end

	local raw = LibDeflate:DecodeForPrint(payload)
	local body = raw and LibDeflate:DecompressZlib(raw)
	if not body then return nil, "IMPORT_DAMAGED" end

	local setup = { slots = {}, notes = {}, caps = {} }
	for line in string.gmatch(body, "[^\n]+") do
		local f = split(line)
		local kind = f[1]
		if kind == "H" then
			if f[2] == "char" then
				setup.name, setup.realm = f[3], f[4]
			elseif f[2] == "spec" then
				setup.spec = f[3]
			elseif f[2] == "phase" then
				setup.phase = f[3]
			end
		elseif kind == "C" then
			setup.caps[f[2]] = { before = num(f[3]), after = num(f[4]), cap = num(f[5]) }
		elseif kind == "I" then
			local flags = f[13] or ""
			local slot = {
				slot = num(f[2]),
				item = num(f[3]),
				loc = f[4],
				where = f[5],
				enchant = num(f[7]),
				gems = {},
				sockets = f[12] or "",
				changedItem = string.find(flags, "I", 1, true) ~= nil,
				changedEnchant = string.find(flags, "E", 1, true) ~= nil,
				changedGems = string.find(flags, "G", 1, true) ~= nil,
				buckle = string.find(flags, "B", 1, true) ~= nil,
			}
			local src = f[6] or ""
			slot.enchantKind, slot.enchantSource = string.sub(src, 1, 1), tonumber(string.sub(src, 2))
			for i = 1, string.len(slot.sockets) do
				slot.gems[i] = num(f[7 + i])
			end
			setup.slots[slot.slot] = slot
		elseif kind == "N" then
			setup.notes[#setup.notes + 1] = f[2]
		end
	end
	if not next(setup.slots) then return nil, "IMPORT_DAMAGED" end
	return setup
end
