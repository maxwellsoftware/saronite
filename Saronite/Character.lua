-- The optimizer's view of a character, built either from the live client
-- (own character) or from an export string (a guildmate's, and the tests).
local _, ns = ...

local LibDeflate = LibStub("LibDeflate")
local Rules = ns.Rules

local Character = {}
ns.Character = Character

local STAT_ALIASES = { POWER_REGEN0 = "MP5" }

local function newChar()
	return {
		professions = {}, talents = {}, stats = {}, items = {}, gemStats = {},
		activeGroup = 1, level = 0,
	}
end

local function itemFromRecord(r)
	local loc = r.loc
	local stats = {}
	for k, v in pairs(r.stats or {}) do stats[STAT_ALIASES[k] or k] = v end
	return {
		loc = loc,
		slot = r.slot,
		invSlot = loc == "E" and tonumber(r.slot) or 0,
		id = r.id,
		enchant = r.enchant or 0,
		gems = { r.gems[1] or 0, r.gems[2] or 0, r.gems[3] or 0, r.gems[4] or 0 },
		sockets = r.sockets or "",
		stats = stats,
		type = string.gsub(r.equipLoc or r.type or "", "^INVTYPE_", ""),
		unusable = r.usable == false,
		socketBonus = Rules.StatsFromText(r.bonus),
	}
end

-- FromSnapshot uses ns.Export.Snapshot() of the player.
function Character.FromSnapshot(snap)
	local c = newChar()
	for _, h in ipairs(snap.header) do
		local key, v = h[1], h[2]
		if key == "realm" then c.realm = v
		elseif key == "name" then c.name = v
		elseif key == "class" then c.class = v
		elseif key == "race" then c.race = v
		elseif key == "level" then c.level = tonumber(v) or 0
		elseif key == "group" then c.activeGroup = tonumber(v) or 1
		end
	end
	for _, t in ipairs(snap.talents) do
		c.talents[#c.talents + 1] = { group = t.group, tab = t.tab, points = t.points, ranks = t.ranks }
	end
	for _, p in ipairs(snap.professions) do c.professions[p.key] = true end
	for k, v in pairs(snap.stats) do c.stats[k] = v end

	for _, list in ipairs({ snap.equipped, snap.bags, snap.bank }) do
		for _, r in ipairs(list) do
			local it = itemFromRecord(r)
			c.items[#c.items + 1] = it
			for _, id in ipairs(it.gems) do
				if id > 0 and not c.gemStats[id] then
					c.gemStats[id] = ns.Scanner.StatCodes(GetItemStats("item:" .. id))
				end
			end
		end
	end
	return c
end

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

local function parseStats(s)
	local stats = {}
	for kv in string.gmatch(s or "", "[^,]+") do
		local k, v = string.match(kv, "^([^=]+)=(.*)$")
		if k then stats[STAT_ALIASES[k] or k] = tonumber(v) or 0 end
	end
	return stats
end

local n = function(v) return tonumber(v) or 0 end

-- FromBody parses a decoded export body (docs/export-format.md).
function Character.FromBody(body)
	local c = newChar()
	local first = true
	for line in string.gmatch(body, "[^\n]+") do
		local f = split(line)
		if first then
			if line ~= "SAR|1" then return nil, "IMPORT_BAD" end
			first = false
		elseif f[1] == "H" then
			local key = f[2]
			if key == "realm" then c.realm = f[3]
			elseif key == "name" then c.name = f[3]
			elseif key == "class" then c.class = f[3]
			elseif key == "race" then c.race = f[3]
			elseif key == "level" then c.level = n(f[3])
			elseif key == "group" then c.activeGroup = n(f[3])
			end
		elseif f[1] == "T" and #f >= 5 then
			c.talents[#c.talents + 1] = { group = n(f[2]), tab = n(f[3]), points = n(f[4]), ranks = f[5] }
		elseif f[1] == "P" and #f >= 4 then
			c.professions[f[2]] = true
		elseif f[1] == "S" and #f >= 3 and f[3] ~= "" then
			c.stats[f[2]] = n(f[3])
		elseif f[1] == "J" and #f >= 3 then
			c.gemStats[n(f[2])] = parseStats(f[3])
		elseif f[1] == "I" and #f >= 20 then
			local loc = f[2]
			c.items[#c.items + 1] = {
				loc = loc,
				slot = f[3],
				invSlot = loc == "E" and n(f[3]) or 0,
				id = n(f[4]),
				enchant = n(f[5]),
				gems = { n(f[12]), n(f[13]), n(f[14]), n(f[15]) },
				sockets = f[19] or "",
				stats = parseStats(f[20]),
				type = f[21] or "",
				unusable = f[22] == "0",
				socketBonus = Rules.StatsFromText(f[23]),
			}
		end
	end
	if first or not c.class or c.level == 0 then return nil, "IMPORT_BAD" end
	if c.activeGroup == 0 then c.activeGroup = 1 end
	return c
end

-- FromExportString decodes "!SAR:1!..." pasted from someone else.
function Character.FromExportString(text)
	text = string.gsub(text or "", "%s", "")
	local version, payload = string.match(text, "!SAR:(%d+)!([%w%(%)]+)")
	if not version then return nil, "IMPORT_BAD" end
	if tonumber(version) ~= ns.FORMAT_VERSION then return nil, "IMPORT_VERSION" end
	local raw = LibDeflate:DecodeForPrint(payload)
	local body = raw and LibDeflate:DecompressZlib(raw)
	if not body then return nil, "IMPORT_DAMAGED" end
	return Character.FromBody(body)
end

function Character.Equipped(c)
	local out = {}
	for _, it in ipairs(c.items) do
		if it.loc == "E" then out[it.invSlot] = it end
	end
	return out
end

function Character.ActiveTalents(c)
	local out = {}
	for _, t in ipairs(c.talents) do
		if t.group == c.activeGroup then out[#out + 1] = t end
	end
	return out
end
