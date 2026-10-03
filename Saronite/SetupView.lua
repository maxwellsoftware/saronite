-- Renders a setup like a character sheet: items with gems, enchants and the
-- phase BiS item for comparison, changes highlighted; caps and the gear
-- stats "now / after" in the middle.
local _, ns = ...

local L = ns.L
local Style = ns.Style
local SetupView = {}
ns.SetupView = SetupView

local LEFT = { 1, 2, 3, 15, 5, 9 }
local RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOTTOM = { 16, 17, 18 }

local ICON, SMALL, BIS, ALT = 38, 16, 24, 20
local ROW = 54 -- vertical step between items
local COLUMN = 350
local MARGIN = 16
local WIDTH, HEIGHT = 1060, 560
local DEFAULT_SCALE = 1
-- outer zone, from the window edge inwards: 2 alternatives, BiS, the item
local ALT_ZONE = 2 * (ALT + 4)
local OUTER = ALT_ZONE + 6 + BIS + 12
local NAME_WIDTH = COLUMN - OUTER - ICON - 10

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local window, rows, panel, roleButton
local current, onToggleRole
local pending = 0 -- refresh attempts left while item data loads

-- Items the client has not cached yet are requested from the server by
-- showing them in a hidden tooltip; the view refreshes a few times.
local queryTip
local requested = {}
local function request(link)
	if requested[link] then return end
	requested[link] = true
	if not queryTip then
		queryTip = CreateFrame("GameTooltip", "SaroniteQueryTooltip", nil, "GameTooltipTemplate")
	end
	queryTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	queryTip:SetHyperlink(link)
	pending = math.max(pending, 6)
end

local function itemInfo(id)
	if not id or id == 0 then return nil end
	local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(id)
	if not name then request("item:" .. id) end
	return name, quality, texture or (GetItemIcon and GetItemIcon(id)) or QUESTION
end

-- Enchants come as a spell (enchanting) or an item (arcanum, armor kit).
local function enchantInfo(kind, source)
	if not source then return nil end
	if kind == "s" then
		local name, _, icon = GetSpellInfo(source)
		return name, icon, "spell:" .. source
	end
	local name, _, texture = itemInfo(source)
	return name, texture, "item:" .. source
end

local function locationText(slot)
	if slot.loc == "B" then return L.LOC_BAG end
	if slot.loc == "K" then return L.LOC_BANK end
	return nil
end

local function rgbHex(c)
	return string.format("%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

local STAT_NAMES = {
	STR = L.STAT_STR, AGI = L.STAT_AGI, STA = L.STAT_STA, INT = L.STAT_INT, SPI = L.STAT_SPI,
	AP = L.STAT_AP, SP = L.STAT_SP, CRIT = L.STAT_CRIT, HASTE = L.STAT_HASTE, ARP = L.STAT_ARP,
	DEF = L.STAT_DEF, DODGE = L.STAT_DODGE, PARRY = L.STAT_PARRY, BLOCK = L.STAT_BLOCK,
	BLOCKV = L.STAT_BLOCKV, MP5 = L.STAT_MP5, ARMOR = L.STAT_ARMOR, RESIL = L.STAT_RESIL,
}

local function showLink(owner, link, lines)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if link then GameTooltip:SetHyperlink(link) end
	for _, line in ipairs(lines or {}) do
		GameTooltip:AddLine(line[1], line[2] or 1, line[3] or 1, line[4] or 1, true)
	end
	GameTooltip:Show()
end

local function hoverable(frame, getTooltip)
	frame:EnableMouse(true)
	frame:SetScript("OnEnter", function(self)
		local link, lines = getTooltip(self)
		if link or lines then showLink(self, link, lines) end
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local accent, warn = Style.color.accent, Style.color.warn

local function newRow(parent, alignRight)
	local row = CreateFrame("Frame", nil, parent)
	row:SetWidth(COLUMN)
	row:SetHeight(ICON)
	row.alignRight = alignRight

	row.icon = Style.Icon(row, ICON)
	-- single-line texts: a fixed width and height make them truncate
	-- instead of wrapping onto the next line
	row.name = Style.Text(row, 13)
	row.name:SetWidth(NAME_WIDTH)
	row.name:SetHeight(16)
	row.detail = Style.Text(row, 12)
	row.detail:SetHeight(15)
	row.detail:SetTextColor(unpack(Style.color.dim))
	row.alts = {}
	for i = 1, 2 do row.alts[i] = Style.Icon(row, ALT) end
	row.altLabel = Style.Text(row, 9)
	row.altLabel:SetText(L.ALTERNATIVE)
	row.altLabel:SetTextColor(unpack(Style.color.warn))
	row.bis = Style.Icon(row, BIS)
	row.bisLabel = Style.Text(row.bis, 10)
	row.bisLabel:SetText("BiS")
	row.bisLabel:SetPoint("BOTTOM", row.bis, "TOP", 0, 1)
	row.bisLabel:SetTextColor(unpack(Style.color.dim))

	row.gems = {}
	for i = 1, 4 do row.gems[i] = Style.Icon(row, SMALL) end
	row.ench = Style.Icon(row, SMALL)

	local side = alignRight and "RIGHT" or "LEFT"
	local other = alignRight and "LEFT" or "RIGHT"
	local dir = alignRight and -1 or 1

	-- outer edge: alternatives, BiS, then the item; texts grow inwards
	row.alts[1]:SetPoint(side, row, side, (ALT + 4) * dir, -5)
	row.alts[2]:SetPoint(side, row, side, 0, -5)
	row.altLabel:SetPoint("BOTTOM", row.alts[1], "TOP" .. side, -2 * dir, 2)
	row.bis:SetPoint(side, row, side, (ALT_ZONE + 6) * dir, -5)
	row.icon:SetPoint(side, row, side, OUTER * dir, 0)
	row.name:SetPoint("TOP" .. side, row.icon, "TOP" .. other, 8 * dir, -2)
	row.name:SetJustifyH(side)
	row.gems[1]:SetPoint("BOTTOM" .. side, row.icon, "BOTTOM" .. other, 8 * dir, 2)
	for i = 2, 4 do row.gems[i]:SetPoint(side, row.gems[i - 1], other, 3 * dir, 0) end
	row.detail:SetJustifyH(side)

	hoverable(row.icon, function()
		local s = row.slot
		if not s then return nil end
		local lines = {}
		local where = locationText(s)
		if where then lines[#lines + 1] = { where, warn[1], warn[2], warn[3] } end
		if s.changedItem then lines[#lines + 1] = { L.TIP_EQUIP, accent[1], accent[2], accent[3] } end
		if s.offSpec then
			local names = {}
			for _, code in ipairs(s.offSpec) do names[#names + 1] = STAT_NAMES[code] or code end
			lines[#lines + 1] = { string.format(L.TIP_OFFSPEC, table.concat(names, ", ")), warn[1], warn[2], warn[3] }
		elseif s.weak then
			lines[#lines + 1] = { L.TIP_WEAK, warn[1], warn[2], warn[3] }
		end
		return "item:" .. s.item, lines
	end)
	for i, alt in ipairs(row.alts) do
		hoverable(alt, function()
			local s = row.slot
			local id = s and s.alternatives and s.alternatives[i]
			if not id then return nil end
			return "item:" .. id, { { string.format(L.TIP_ALT, current.phase or ""), warn[1], warn[2], warn[3] } }
		end)
	end
	hoverable(row.bis, function()
		local s = row.slot
		if not s or not s.bis then return nil end
		return "item:" .. s.bis, { { string.format(L.TIP_BIS, current.phase or ""), accent[1], accent[2], accent[3] } }
	end)
	for i, g in ipairs(row.gems) do
		hoverable(g, function()
			local s = row.slot
			local id = s and s.gems[i]
			if not id or id == 0 then return nil end
			local lines = {}
			local old = s.oldGems and s.oldGems[i]
			if s.buckle and i == #s.gems then
				lines[#lines + 1] = { L.TIP_BUCKLE, warn[1], warn[2], warn[3] }
			end
			if old and old ~= 0 and old ~= id then
				lines[#lines + 1] = { string.format(L.TIP_REPLACE, itemInfo(old) or ("#" .. old)), warn[1], warn[2], warn[3] }
			elseif (not old or old == 0) and s.changedGems then
				lines[#lines + 1] = { L.TIP_INSERT, accent[1], accent[2], accent[3] }
			end
			return "item:" .. id, lines
		end)
	end
	hoverable(row.ench, function()
		local s = row.slot
		if not s then return nil end
		local _, _, link = enchantInfo(s.enchantKind, s.enchantSource)
		local lines = {}
		if s.changedEnchant and s.oldEnchant and s.oldEnchant ~= 0 then
			local oldName = enchantInfo(s.oldEnchantKind, s.oldEnchantSource)
			lines[#lines + 1] = { string.format(L.TIP_REPLACE, oldName or L.OLD_ENCHANT), warn[1], warn[2], warn[3] }
		elseif s.changedEnchant then
			lines[#lines + 1] = { L.TIP_APPLY, accent[1], accent[2], accent[3] }
		end
		return link, lines
	end)
	return row
end

local function fillRow(row, slot)
	row.slot = slot
	if not slot then
		row:Hide()
		return
	end
	row:Show()

	local name, quality, texture = itemInfo(slot.item)
	row.icon.texture:SetTexture(texture)
	if slot.changedItem then
		row.icon:SetBorder(unpack(accent))
	elseif slot.offSpec or slot.weak then
		row.icon:SetBorder(unpack(warn))
	else
		row.icon:SetBorder(Style.QualityColor(quality))
	end
	row.name:SetText(name or ("#" .. slot.item))
	row.name:SetTextColor(Style.QualityColor(quality))

	-- alternatives for off-spec or weak items
	local alts = slot.alternatives or {}
	for i, alt in ipairs(row.alts) do
		local id = alts[i]
		if id then
			local _, q, tex = itemInfo(id)
			alt.texture:SetTexture(tex)
			alt:SetBorder(Style.QualityColor(q))
			alt:Show()
		else
			alt:Hide()
		end
	end
	if #alts > 0 then row.altLabel:Show() else row.altLabel:Hide() end

	-- BiS of the phase, for comparison; dimmed when it is the same item
	if slot.bis then
		local _, bq, btex = itemInfo(slot.bis)
		row.bis.texture:SetTexture(btex)
		row.bis:SetBorder(Style.QualityColor(bq))
		row.bis:SetAlpha(slot.bis == slot.item and 0.35 or 1)
		row.bis:Show()
	else
		row.bis:Hide()
	end

	-- gem icons, then the enchant icon, then the enchant name / location
	local last = nil
	for i, g in ipairs(row.gems) do
		local id = slot.gems[i]
		if id then
			if id > 0 then
				local _, _, tex = itemInfo(id)
				g.texture:SetTexture(tex)
				local old = slot.oldGems and slot.oldGems[i]
				if slot.changedGems and (old == nil or old ~= id) then g:SetBorder(unpack(accent)) else g:SetBorder(0, 0, 0) end
			else
				g.texture:SetTexture(nil)
				g:SetBorder(unpack(warn))
			end
			g:Show()
			last = g
		else
			g:Hide()
		end
	end

	local dir = row.alignRight and -1 or 1
	local side = row.alignRight and "RIGHT" or "LEFT"
	local other = row.alignRight and "LEFT" or "RIGHT"
	local enchName, enchIcon = enchantInfo(slot.enchantKind, slot.enchantSource)
	row.ench:ClearAllPoints()
	if last then
		row.ench:SetPoint(side, last, other, 8 * dir, 0)
	else
		row.ench:SetPoint("BOTTOM" .. side, row.icon, "BOTTOM" .. other, 8 * dir, 2)
	end
	if enchName then
		row.ench.texture:SetTexture(enchIcon or QUESTION)
		if slot.changedEnchant then row.ench:SetBorder(unpack(accent)) else row.ench:SetBorder(0, 0, 0) end
		row.ench:Show()
	else
		row.ench:Hide()
	end

	local parts = {}
	if enchName then
		local c = slot.changedEnchant and accent or Style.color.dim
		parts[#parts + 1] = "|cff" .. rgbHex(c) .. enchName .. "|r"
	end
	local where = locationText(slot)
	if where then parts[#parts + 1] = "|cff" .. rgbHex(warn) .. where .. "|r" end
	row.detail:SetText(table.concat(parts, "  "))
	-- one anchor only (a second one at another height made the text jump
	-- onto the item name); the width is what is left of the row
	row.detail:ClearAllPoints()
	local anchor = enchName and row.ench or last or row.icon
	local used = 0
	for _, g in ipairs(row.gems) do
		if g:IsShown() then used = used + SMALL + 3 end
	end
	if enchName then used = used + SMALL + 8 end
	if anchor == row.icon then
		row.detail:SetPoint("BOTTOM" .. side, row.icon, "BOTTOM" .. other, 8 * dir, 2)
	else
		row.detail:SetPoint(side, anchor, other, 6 * dir, 0)
	end
	row.detail:SetWidth(math.max(40, NAME_WIDTH - used - 6))
end

-- Center panel ---------------------------------------------------------------


local function delta(before, after, fmt)
	local d = after - before
	if math.abs(d) < 0.005 then return "|cff8c8c94" .. L.NO_CHANGE .. "|r" end
	local color = d > 0 and "66d973" or "ff7a66"
	return string.format("|cff%s%+" .. fmt .. "|r", color, d)
end

local function capBlock(title, cap, percent, help)
	local fmt = percent and "%.2f%%" or "%d"
	local ok = cap.after + 0.005 >= cap.cap
	local color = ok and "66d973" or "ffb340"
	local lines = {
		"|cff" .. rgbHex(accent) .. title .. "|r  " .. string.format(L.CAP_OF, string.format(fmt, cap.cap)),
		math.abs(cap.after - cap.before) < 0.005
			and string.format("|cff%s" .. fmt .. "|r  |cff8c8c94%s|r   %s", color, cap.after, L.NO_CHANGE, ok and L.CAP_DONE or L.CAP_SHORT)
			or string.format("%s |cff8c8c94»|r |cff%s" .. fmt .. "|r   %s",
				string.format(fmt, cap.before), color, cap.after, ok and L.CAP_DONE or L.CAP_SHORT),
	}
	if cap.rating then
		if percent then
			lines[#lines + 1] = "|cff8c8c94" .. string.format(L.HIT_FROM, cap.rating, cap.talent or 0) .. "|r"
		else
			lines[#lines + 1] = "|cff8c8c94" .. string.format(L.EXP_FROM, cap.rating, cap.talent or 0) .. "|r"
		end
	end
	lines[#lines + 1] = "|cff6b6b72" .. help .. "|r"
	return table.concat(lines, "\n")
end

-- Gear stats table: name | now | after | difference, numbers right-aligned.
local PANEL_WIDTH = WIDTH - 2 * COLUMN - 2 * MARGIN - 48
local STAT_ROWS = 8
local center, statHeader, statRows, footer

local function newStatRow(anchor, gap, size)
	local r = {}
	r.name = Style.Text(center, size)
	r.name:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
	r.name:SetWidth(PANEL_WIDTH - 200)
	r.name:SetHeight(size + 3)
	for key, x in pairs({ before = PANEL_WIDTH - 150, after = PANEL_WIDTH - 100, delta = PANEL_WIDTH }) do
		local fs = Style.Text(center, size)
		fs:SetJustifyH("RIGHT")
		fs:SetWidth(key == "delta" and 96 or 48)
		fs:SetPoint("TOPRIGHT", r.name, "TOPLEFT", x, 0)
		r[key] = fs
	end
	function r:Show() for _, k in ipairs({ "name", "before", "after", "delta" }) do self[k]:Show() end end
	function r:Hide() for _, k in ipairs({ "name", "before", "after", "delta" }) do self[k]:Hide() end end
	return r
end

local function fillStats(all)
	local stats = {}
	for _, st in ipairs(all or {}) do
		if st.before ~= 0 or st.after ~= 0 then stats[#stats + 1] = st end
	end
	local last = nil
	if #stats > 0 then
		statHeader:Show()
		last = statHeader.name
	else
		statHeader:Hide()
	end
	for i, r in ipairs(statRows) do
		local st = stats[i]
		if st then
			r.name:SetText(STAT_NAMES[st.code] or st.code)
			r.before:SetText(string.format("%d", st.before))
			r.before:SetTextColor(unpack(Style.color.dim))
			r.after:SetText(string.format("%d", st.after))
			r.delta:SetText(delta(st.before, st.after, "d"))
			r:Show()
			last = r.name
		else
			r:Hide()
		end
	end
	footer:ClearAllPoints()
	footer:SetPoint("TOPLEFT", last or panel, "BOTTOMLEFT", 0, -18)
end

local function render()
	if not current then return end
	window.caption:SetText((current.name or "") .. "  ·  " .. (current.spec or "") .. "  ·  " .. (current.phase or ""))
	for slot, row in pairs(rows) do
		fillRow(row, current.slots[slot])
	end

	local caps = {}
	if current.caps.hit then caps[#caps + 1] = capBlock(L.CAP_HIT, current.caps.hit, true, L.HIT_HELP) end
	if current.caps.exp then caps[#caps + 1] = capBlock(L.CAP_EXP, current.caps.exp, false, L.EXP_HELP) end
	panel:SetText(table.concat(caps, "\n\n"))
	fillStats(current.stats)

	local blocks = {}

	local items, enchants, gems = 0, 0, 0
	for _, s in pairs(current.slots) do
		if s.changedItem then items = items + 1 end
		if s.changedEnchant then enchants = enchants + 1 end
		if s.changedGems then gems = gems + 1 end
	end
	local parts = {}
	if items > 0 then parts[#parts + 1] = string.format(L.CHANGES_ITEMS, items) end
	if enchants > 0 then parts[#parts + 1] = string.format(L.CHANGES_ENCHANTS, enchants) end
	if gems > 0 then parts[#parts + 1] = string.format(L.CHANGES_GEMS, gems) end
	blocks[#blocks + 1] = #parts > 0 and (L.CHANGES .. " " .. table.concat(parts, " · ")) or L.NO_CHANGES

	local off = {}
	for _, slot in ipairs({ 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }) do
		local s = current.slots[slot]
		if s and s.offSpec and not s.changedItem then off[#off + 1] = L.SLOTS[slot] or tostring(slot) end
	end
	if #off > 0 then
		blocks[#blocks + 1] = "|cff" .. rgbHex(warn) .. string.format(L.NOTE_OFFSPEC, table.concat(off, ", ")) .. "|r"
	end
	for _, note in ipairs(current.notes or {}) do
		blocks[#blocks + 1] = "|cff8c8c94" .. note .. "|r"
	end
	footer:SetText(table.concat(blocks, "\n\n"))
	footer:Show()

	if current.canTank and onToggleRole then
		roleButton.label:SetText(current.tank and L.AS_DPS or L.AS_TANK)
		roleButton:Show()
	else
		roleButton:Hide()
	end
end

local function create()
	window = Style.Window("SaroniteSetupFrame", WIDTH, HEIGHT, "")
	Style.ScaleGrip(window, "setup.v2", DEFAULT_SCALE)
	rows = {}

	for i, slot in ipairs(LEFT) do
		local row = newRow(window, false)
		row:SetPoint("TOPLEFT", MARGIN, -48 - (i - 1) * ROW)
		rows[slot] = row
	end
	for i, slot in ipairs(RIGHT) do
		local row = newRow(window, true)
		row:SetPoint("TOPRIGHT", -MARGIN, -48 - (i - 1) * ROW)
		rows[slot] = row
	end
	for i, slot in ipairs(BOTTOM) do
		local row = newRow(window, false)
		row:SetPoint("BOTTOMLEFT", MARGIN + (i - 1) * (COLUMN + 12), MARGIN)
		rows[slot] = row
	end

	local divider = Style.Line(window, 1, 1)
	divider:SetPoint("BOTTOMLEFT", 1, ICON + 2 * MARGIN)
	divider:SetPoint("BOTTOMRIGHT", -1, ICON + 2 * MARGIN)

	center = CreateFrame("Frame", nil, window)
	center:SetWidth(PANEL_WIDTH)
	center:SetHeight(10)
	center:SetPoint("TOP", 0, -50)

	panel = Style.Text(center, 13)
	panel:SetPoint("TOPLEFT", center, "TOPLEFT", 0, 0)
	panel:SetWidth(PANEL_WIDTH)
	panel:SetJustifyH("LEFT")
	panel:SetJustifyV("TOP")
	panel:SetSpacing(3)

	statHeader = newStatRow(panel, 18, 13)
	statHeader.name:SetText("|cff" .. rgbHex(accent) .. L.GEAR_STATS .. "|r")
	statHeader.before:SetText(L.COL_NOW)
	statHeader.after:SetText(L.COL_AFTER)
	for _, k in ipairs({ "before", "after", "delta" }) do statHeader[k]:SetTextColor(unpack(Style.color.dim)) end
	statRows = {}
	for i = 1, STAT_ROWS do
		statRows[i] = newStatRow(i == 1 and statHeader.name or statRows[i - 1].name, 5, 13)
	end

	footer = Style.Text(center, 12)
	footer:SetWidth(PANEL_WIDTH)
	footer:SetJustifyH("LEFT")
	footer:SetJustifyV("TOP")
	footer:SetSpacing(3)

	roleButton = Style.Button(window, L.AS_TANK, 96, 18)
	roleButton:SetPoint("TOPRIGHT", -32, -6)
	roleButton:SetScript("OnClick", function()
		if onToggleRole then ns.Safe(onToggleRole) end
	end)
	roleButton:Hide()

	-- Refresh while uncached items arrive from the server.
	local elapsed = 0
	window:SetScript("OnUpdate", function(_, dt)
		if pending <= 0 then return end
		elapsed = elapsed + dt
		if elapsed < 0.5 then return end
		elapsed = 0
		pending = pending - 1
		render()
	end)
end

-- Show renders a setup; toggleRole, when given, recomputes it as tank/dps.
function SetupView.Show(setup, toggleRole)
	if not window then create() end
	current = setup
	onToggleRole = toggleRole
	pending = 0
	render()
	window:Show()
end

local function message(caption, text)
	if not window then create() end
	current = nil
	window.caption:SetText(caption or "")
	for _, row in pairs(rows) do
		row.slot = nil
		row:Hide()
	end
	roleButton:Hide()
	panel:SetText(text)
	fillStats(nil)
	footer:Hide()
	window:Show()
end

function SetupView.ShowBusy(name)
	message(name, L.CALCULATING)
end

function SetupView.ShowError(text)
	message("", "|cffffb340" .. text .. "|r")
end
