-- Serializes scanned data into the export string.
-- Format: docs/export-format.md. Keep both in sync and bump
-- ns.FORMAT_VERSION on incompatible changes.
local _, ns = ...

local LibDeflate = LibStub("LibDeflate")

local Export = {}
ns.Export = Export

Export.PREFIX = "!SAR:" .. ns.FORMAT_VERSION .. "!"
-- One Telegram message holds 4096 characters; leave room for edits.
Export.TARGET_LENGTH = 4000

local function num(v)
	if type(v) ~= "number" then return "" end
	if v == math.floor(v) then return string.format("%d", v) end
	local s = string.format("%.2f", v)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

-- Field values must not contain the separators.
local function clean(v)
	return (string.gsub(tostring(v or ""), "[|\n\r]", ""))
end

local function line(out, ...)
	local parts = { ... }
	for i = 1, select("#", ...) do
		parts[i] = clean(parts[i])
	end
	out[#out + 1] = table.concat(parts, "|")
end

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	return keys
end

local function statsField(stats)
	if not stats then return "" end
	local parts = {}
	for _, k in ipairs(sortedKeys(stats)) do
		parts[#parts + 1] = k .. "=" .. num(stats[k])
	end
	return table.concat(parts, ",")
end

local function itemLine(out, item, withStats)
	line(out, "I", item.loc, item.slot, num(item.id), num(item.enchant),
		num(item.jewels[1]), num(item.jewels[2]), num(item.jewels[3]), num(item.jewels[4]),
		num(item.suffix), num(item.unique),
		num(item.gems[1]), num(item.gems[2]), num(item.gems[3]), num(item.gems[4]),
		num(item.count), num(item.quality), num(item.ilvl), item.sockets,
		withStats and statsField(item.stats) or "",
		(string.gsub(item.equipLoc or "", "^INVTYPE_", "")),
		item.usable == false and "0" or "1",
		item.bonus or "")
end

-- Snapshot gathers everything once; Build may then serialize it several times
-- while trimming.
function Export.Snapshot()
	local _, classToken = UnitClass("player")
	local _, raceToken = UnitRace("player")
	local version, build = GetBuildInfo()
	local bank = ns.GetBank()

	-- Header values are never nil: a nil would shift the fields after it.
	local function v(x)
		if x == nil then return "" end
		return x
	end

	return {
		header = {
			{ "addon", ns.VERSION },
			{ "client", v(version), v(build), v(GetLocale()) },
			{ "realm", v(GetRealmName()) },
			{ "name", v(UnitName("player")) },
			{ "class", v(classToken) },
			{ "race", v(raceToken) },
			{ "sex", v(UnitSex("player")) },
			{ "level", v(UnitLevel("player")) },
			{ "time", time() },
			{ "group", GetActiveTalentGroup and GetActiveTalentGroup() or 1 },
			{ "bank", bank and bank.time or 0 },
		},
		talents = ns.Scanner.Talents(),
		glyphs = ns.Scanner.Glyphs(),
		professions = ns.Scanner.Professions(),
		stats = ns.Scanner.Stats(),
		equipped = ns.Scanner.ScanEquipped(),
		bags = ns.Scanner.ScanBags(),
		bank = bank and bank.items or {},
	}
end

-- Serialize renders the plain-text body.
-- opts: bagStats (stats for bag/bank items), bags, bank.
function Export.Serialize(snap, opts)
	local out = {}
	line(out, "SAR", ns.FORMAT_VERSION)

	for _, h in ipairs(snap.header) do
		local fields = { "H" }
		for i = 1, #h do fields[#fields + 1] = type(h[i]) == "number" and num(h[i]) or h[i] end
		line(out, unpack(fields))
	end

	for _, t in ipairs(snap.talents) do
		line(out, "T", t.group, t.tab, t.points, t.ranks)
	end
	for group, ids in ipairs(snap.glyphs) do
		line(out, "G", group, table.concat(ids, ","))
	end
	for _, p in ipairs(snap.professions) do
		line(out, "P", p.key, p.rank, p.max)
	end
	for _, k in ipairs(sortedKeys(snap.stats)) do
		line(out, "S", k, num(snap.stats[k]))
	end

	for _, item in ipairs(snap.equipped) do
		itemLine(out, item, true)
	end
	if opts.bags then
		for _, item in ipairs(snap.bags) do itemLine(out, item, opts.bagStats) end
	end
	if opts.bank then
		for _, item in ipairs(snap.bank) do itemLine(out, item, opts.bagStats) end
	end

	-- Stats of every gem in the exported items, so the bot knows what the
	-- current gems give even outside its own gem list.
	local gems, seen = {}, {}
	local function collect(list)
		for _, item in ipairs(list) do
			for _, id in ipairs(item.gems) do
				if id > 0 and not seen[id] then
					seen[id] = true
					gems[#gems + 1] = id
				end
			end
		end
	end
	collect(snap.equipped)
	if opts.bags then collect(snap.bags) end
	if opts.bank then collect(snap.bank) end
	table.sort(gems)
	for _, id in ipairs(gems) do
		line(out, "J", id, statsField(ns.Scanner.StatCodes(GetItemStats("item:" .. id))))
	end

	return table.concat(out, "\n")
end

function Export.Encode(body)
	local compressed = LibDeflate:CompressZlib(body, { level = 9 })
	return Export.PREFIX .. LibDeflate:EncodeForPrint(compressed)
end

-- Trimming steps, from the full export to the bare minimum.
local LEVELS = {
	{ bagStats = true, bags = true, bank = true },
	{ bagStats = false, bags = true, bank = true, note = "TRIMMED_BAGSTATS" },
	{ bagStats = false, bags = true, bank = false, note = "TRIMMED_BANK" },
	{ bagStats = false, bags = false, bank = false, note = "TRIMMED_BAGS" },
}

-- Build returns the export string and a list of notes (locale keys) about
-- what had to be left out.
function Export.Build()
	local snap = Export.Snapshot()
	local result, notes = nil, {}
	for _, level in ipairs(LEVELS) do
		result = Export.Encode(Export.Serialize(snap, level))
		if level.note then notes = { level.note } end
		if #result <= Export.TARGET_LENGTH then
			return result, notes
		end
	end
	notes[#notes + 1] = "TOO_LONG"
	return result, notes
end
