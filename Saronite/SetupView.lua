-- The setup window, three tabs:
--   Current optimization — the best setup from your gear in a
--     character-sheet layout: items with gems and enchants, changes
--     highlighted, alternatives for off-spec or weak items; caps, stat
--     priority and gear stats "now / after" in the middle.
--   BiS — the phase BiS list of the spec with its gems and enchants.
--   Talents & glyphs — recommended builds (TalentsView).
local _, ns = ...

local L = ns.L
local Style = ns.Style
local Links = ns.Links
local SetupView = {}
ns.SetupView = SetupView

-- weapons close the left column, the ranged slot / relic the right one
local LEFT = { 1, 2, 3, 15, 5, 9, 16, 17 }
local RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14, 18 }
local ORDER = { 1, 2, 3, 15, 5, 9, 16, 17, 10, 6, 7, 8, 11, 12, 13, 14, 18 }

local ICON, SMALL, ALT = 38, 16, 18
local ALTS = 5 -- alternatives per slot on the BiS tab (2 on the current tab)
local ROW = 52 -- vertical step between items
local COLUMN = 360
local MARGIN = 16
local TOP = 84 -- title bar + tabs
local WIDTH, HEIGHT = 1160, 572
local DEFAULT_SCALE = 1
-- outer zone, from the window edge inwards: alternatives, then the item
local ALT_ZONE = ALTS * (ALT + 3)
local OUTER = ALT_ZONE + 10
local NAME_WIDTH = COLUMN - OUTER - ICON - 10
local PANEL_WIDTH = WIDTH - 2 * COLUMN - 2 * MARGIN - 48
local STAT_ROWS = 7

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local window, rows, tabs, roleButtons
local center, message, capCards, priority, statHeader, statRows, footer, bisCard
local current, onRole
local tab = "current"
local pending = 0 -- refresh attempts left while item data loads

local accent, warn, dim, good = Style.color.accent, Style.color.warn, Style.color.dim, Style.color.good
local hex = Style.Hex

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
	return Links.ItemName(id, name), quality, texture or (GetItemIcon and GetItemIcon(id)) or QUESTION
end

-- Enchants come as a spell (enchanting) or an item (arcanum, armor kit).
local function enchantInfo(kind, source, enchantID)
	if not source then return nil end
	local phase = current and current.phase
	if kind == "s" then
		local name, _, icon = GetSpellInfo(source)
		return Links.EnchantName(phase, enchantID, name), icon, "spell:" .. source
	end
	local name, _, _, _, _, _, _, _, _, texture = GetItemInfo(source)
	if not name then request("item:" .. source) end
	return Links.EnchantName(phase, enchantID, name), texture or (GetItemIcon and GetItemIcon(source)) or QUESTION,
		"item:" .. source
end

local function locationText(slot)
	if slot.loc == "B" then return L.LOC_BAG end
	if slot.loc == "K" then return L.LOC_BANK end
	return nil
end

local function colored(c, text) return "|cff" .. hex(c) .. text .. "|r" end

-- resolved on use so the UI language can change at any time
local function statName(code)
	return L["STAT_" .. code] or code
end

local function showLink(owner, link, lines)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if link then GameTooltip:SetHyperlink(link) end
	for _, line in ipairs(lines or {}) do
		GameTooltip:AddLine(line[1], line[2] or 1, line[3] or 1, line[4] or 1, true)
	end
	GameTooltip:Show()
end

-- hoverable: tooltip from getTooltip(frame) -> link, lines; clicks open the
-- link (Shift+click into chat, Ctrl+click to try on).
local function hoverable(frame, getTooltip)
	frame:EnableMouse(true)
	frame:SetScript("OnEnter", function(self)
		local link, lines = getTooltip(self)
		if link or lines then showLink(self, link, lines) end
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
	Links.Clickable(frame, function(self)
		local link = getTooltip(self)
		return link
	end)
end

-- Item rows ------------------------------------------------------------------

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
	row.detail:SetTextColor(unpack(dim))
	row.alts = {}
	for i = 1, ALTS do row.alts[i] = Style.Icon(row, ALT) end
	row.altLabel = Style.Text(row, 10)
	row.altLabel:SetText(L.ALTERNATIVE)

	row.gems = {}
	for i = 1, 4 do row.gems[i] = Style.Icon(row, SMALL) end
	row.ench = Style.Icon(row, SMALL)

	local side = alignRight and "RIGHT" or "LEFT"
	local other = alignRight and "LEFT" or "RIGHT"
	local dir = alignRight and -1 or 1

	-- outer edge: alternatives (the first one next to the item), then the
	-- item; texts grow inwards
	for i = 1, ALTS do
		row.alts[i]:SetPoint(side, row, side, (ALTS - i) * (ALT + 3) * dir, -6)
	end
	row.altLabel:SetPoint("BOTTOM" .. other, row.alts[1], "TOP" .. other, 0, 2)
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
		if tab == "bis" then
			if s.owned then
				lines[#lines + 1] = { L.TIP_OWNED, accent[1], accent[2], accent[3] }
			else
				lines[#lines + 1] = { string.format(L.TIP_BIS, current.phase or ""), accent[1], accent[2], accent[3] }
			end
			return "item:" .. s.item, lines
		end
		local where = locationText(s)
		if where then lines[#lines + 1] = { where, warn[1], warn[2], warn[3] } end
		if s.changedItem then lines[#lines + 1] = { L.TIP_EQUIP, accent[1], accent[2], accent[3] } end
		if s.offSpec then
			local names = {}
			for _, code in ipairs(s.offSpec) do names[#names + 1] = statName(code) end
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
	for i, g in ipairs(row.gems) do
		hoverable(g, function()
			local s = row.slot
			local id = s and s.gems[i]
			if not id or id == 0 then return nil end
			local lines = {}
			if tab == "current" then
				local old = s.oldGems and s.oldGems[i]
				if s.buckle and i == #s.gems then
					lines[#lines + 1] = { L.TIP_BUCKLE, warn[1], warn[2], warn[3] }
				end
				if old and old ~= 0 and old ~= id then
					lines[#lines + 1] = { string.format(L.TIP_REPLACE, itemInfo(old) or ("#" .. old)), warn[1], warn[2], warn[3] }
				elseif (not old or old == 0) and s.changedGems then
					lines[#lines + 1] = { L.TIP_INSERT, accent[1], accent[2], accent[3] }
				end
			end
			return "item:" .. id, lines
		end)
	end
	hoverable(row.ench, function()
		local s = row.slot
		if not s then return nil end
		local _, _, link = enchantInfo(s.enchantKind, s.enchantSource, s.enchant)
		local lines = {}
		if tab == "current" then
			if s.changedEnchant and s.oldEnchant and s.oldEnchant ~= 0 then
				local oldName = enchantInfo(s.oldEnchantKind, s.oldEnchantSource, s.oldEnchant)
				lines[#lines + 1] = { string.format(L.TIP_REPLACE, oldName or L.OLD_ENCHANT), warn[1], warn[2], warn[3] }
			elseif s.changedEnchant then
				lines[#lines + 1] = { L.TIP_APPLY, accent[1], accent[2], accent[3] }
			end
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
	if slot.changedItem or slot.owned then
		row.icon:SetBorder(unpack(accent))
	elseif slot.offSpec or slot.weak then
		row.icon:SetBorder(unpack(warn))
	else
		row.icon:SetBorder(Style.QualityColor(quality))
	end
	row.name:SetText(name or ("#" .. slot.item))
	row.name:SetTextColor(Style.QualityColor(quality))

	-- alternatives on the outer side
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
	if #alts > 0 then
		row.altLabel:SetTextColor(unpack(tab == "bis" and dim or warn))
		row.altLabel:Show()
	else
		row.altLabel:Hide()
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
	local enchName, enchIcon = enchantInfo(slot.enchantKind, slot.enchantSource, slot.enchant)
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
	if enchName then parts[#parts + 1] = colored(slot.changedEnchant and accent or dim, enchName) end
	local where = tab == "current" and locationText(slot)
	if where then parts[#parts + 1] = colored(warn, where) end
	row.detail:SetText(table.concat(parts, "  "))
	-- one anchor only; the width is what is left of the row
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
-- A vertical stack of cards: caps, stat priority, gear stats, changes.

local stackY = 0
local function stack(region, height, gap)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", center, "TOPLEFT", 0, -stackY)
	stackY = stackY + height + (gap or 0)
	region:Show()
end

local function newCapCard()
	local card = Style.Card(center, PANEL_WIDTH, 50)
	card.title = Style.Text(card, 13)
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -7)
	card.value = Style.Text(card, 13)
	card.value:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -7)
	card.value:SetJustifyH("RIGHT")
	card.bar = Style.Bar(card, PANEL_WIDTH - 20, 5)
	card.bar:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -26)
	card.detail = Style.Text(card, 11)
	card.detail:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -35)
	card.detail:SetWidth(PANEL_WIDTH - 20)
	card.detail:SetHeight(12)
	card.detail:SetTextColor(unpack(dim))
	card:EnableMouse(true)
	card:SetScript("OnEnter", function(self)
		if not self.help then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.helpTitle or "", accent[1], accent[2], accent[3])
		GameTooltip:AddLine(self.help, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	card:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return card
end

-- fillCap: kind "hit" (percent), "exp" or "def" (skill).
local function fillCap(card, kind, cap)
	local percent = kind == "hit"
	local fmt = percent and "%.2f%%" or "%d"
	local ok = cap.after + 0.005 >= cap.cap
	-- haste to a 1 s GCD is a target, not a must: no warning color
	local color = ok and good or (kind == "haste" and accent or warn)
	local title = ({ hit = L.CAP_HIT, exp = L.CAP_EXP, def = L.CAP_DEF, haste = L.CAP_HASTE, crit = L.CAP_CRIT })[kind]
	card.title:SetText(colored(Style.StatColor(string.upper(kind)), title))
	local value = string.format(fmt, cap.after)
	if math.abs(cap.after - cap.before) >= 0.005 then
		value = colored(dim, string.format(fmt, cap.before) .. " » ") .. value
	end
	card.value:SetText(value .. colored(dim, " / " .. string.format(fmt, cap.cap)))
	card.value:SetTextColor(unpack(color))
	-- the bar shows the way to the cap; for defense it starts at the base 400
	local base = kind == "def" and 400 or 0
	local span = math.max(0.01, cap.cap - base)
	card.bar:SetValues((cap.before - base) / span, (cap.after - base) / span, color[1], color[2], color[3])
	local detail
	if kind == "hit" and cap.rating then
		detail = string.format(L.HIT_FROM, cap.rating, cap.talent or 0)
	elseif kind == "exp" and cap.rating then
		detail = string.format(L.EXP_FROM, cap.rating, cap.talent or 0)
	elseif kind == "def" and cap.rating then
		detail = string.format(L.DEF_FROM, cap.rating)
	elseif kind == "haste" then
		detail = string.format(L.HASTE_FROM, cap.gcdAfter or 1.5, cap.talent or 0)
	elseif kind == "crit" then
		detail = string.format(L.CRIT_FROM, (GetSpellInfo(cap.spell or 0)) or "", cap.after, cap.cap)
	end
	local state
	if kind == "haste" then
		state = colored(color, ok and L.HASTE_DONE or L.HASTE_SHORT)
	elseif kind == "crit" then
		state = colored(color, ok and L.CRIT_DONE or L.CRIT_SHORT)
	else
		state = colored(color, ok and L.CAP_DONE or L.CAP_SHORT)
	end
	card.detail:SetText(detail and (state .. colored(dim, "  ·  " .. detail)) or state)
	card.helpTitle = title
	card.help = ({ hit = L.HIT_HELP, exp = L.EXP_HELP, def = L.DEF_HELP, haste = L.HASTE_HELP, crit = L.CRIT_HELP })[kind]
end

local function delta(before, after)
	local d = after - before
	if math.abs(d) < 0.005 then return colored({ 0.42, 0.42, 0.45 }, "—") end
	return colored(d > 0 and good or { 1, 0.48, 0.4 }, string.format("%+d", d))
end

-- Gear stats: colored name | now | after | difference, and a bar per stat
-- (relative to the largest one) under it.
local function newStatRow(size)
	local r = CreateFrame("Frame", nil, center)
	r:SetWidth(PANEL_WIDTH)
	r:SetHeight(size + 9)
	r.name = Style.Text(r, size)
	r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.name:SetWidth(PANEL_WIDTH - 170)
	r.name:SetHeight(size + 3)
	for key, x in pairs({ before = PANEL_WIDTH - 110, after = PANEL_WIDTH - 56, delta = PANEL_WIDTH }) do
		local fs = Style.Text(r, size)
		fs:SetJustifyH("RIGHT")
		fs:SetWidth(52)
		fs:SetHeight(size + 3)
		fs:SetPoint("TOPRIGHT", r, "TOPLEFT", x, 0)
		r[key] = fs
	end
	r.bar = Style.Bar(r, PANEL_WIDTH, 2)
	r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -(size + 4))
	return r
end

local function fillStats(all, limit)
	local stats = {}
	local top = 1
	for _, st in ipairs(all or {}) do
		if (st.before ~= 0 or st.after ~= 0) and #stats < (limit or STAT_ROWS) then
			stats[#stats + 1] = st
			top = math.max(top, st.before, st.after)
		end
	end
	if #stats == 0 then
		statHeader:Hide()
		for _, r in ipairs(statRows) do r:Hide() end
		return
	end
	stack(statHeader, 18, 4)
	for i, r in ipairs(statRows) do
		local st = stats[i]
		if st then
			local c = Style.StatColor(st.code)
			r.name:SetText(statName(st.code))
			r.name:SetTextColor(c[1], c[2], c[3])
			r.before:SetText(string.format("%d", st.before))
			r.before:SetTextColor(unpack(dim))
			r.after:SetText(string.format("%d", st.after))
			r.delta:SetText(delta(st.before, st.after))
			r.bar:SetValues(st.before / top, st.after / top, c[1], c[2], c[3])
			stack(r, 22, 0)
		else
			r:Hide()
		end
	end
	stackY = stackY + 10
end

-- Stat priority: the spec's stats by weight, in their colors.
local function fillPriority(stats, healer)
	local names = {}
	for i, st in ipairs(stats or {}) do
		if i > 6 then break end
		names[#names + 1] = colored(Style.StatColor(st.code), statName(st.code))
	end
	if #names == 0 then
		priority:Hide()
		return
	end
	local text = colored(dim, L.PRIORITY) .. "\n" .. table.concat(names, colored(dim, "  »  "))
	if healer then text = colored(accent, L.HEALER_CAPS) .. "\n" .. text end
	priority:SetText(text)
	stack(priority, healer and 50 or 34, 12)
end

local function hideCenter()
	for _, card in pairs(capCards) do card:Hide() end
	priority:Hide()
	statHeader:Hide()
	for _, r in ipairs(statRows) do r:Hide() end
	footer:Hide()
	bisCard:Hide()
	message:Hide()
end

local function renderCurrent()
	for slot, row in pairs(rows) do fillRow(row, current.slots[slot]) end

	stackY = 0
	local caps = 0
	for _, kind in ipairs({ "hit", "exp", "def", "crit", "haste" }) do
		local cap = current.caps[kind]
		if cap then
			fillCap(capCards[kind], kind, cap)
			stack(capCards[kind], 50, 8)
			caps = caps + 1
		else
			capCards[kind]:Hide()
		end
	end
	if caps > 0 then stackY = stackY + 4 end
	fillPriority(current.stats, current.role == ns.Rules.HEALER)
	-- three cap cards (plate tanks) leave room for fewer stat rows
	fillStats(current.stats, caps >= 3 and 5 or STAT_ROWS)

	local blocks = {}
	local items, enchants, gems = 0, 0, 0
	for _, s in pairs(current.slots) do
		if s.changedItem then items = items + 1 end
		if s.changedEnchant then enchants = enchants + 1 end
		if s.changedGems then gems = gems + 1 end
	end
	local parts = {}
	local function count(fmt, n)
		local text = string.format(fmt, n)
		return (string.gsub(text, "%d+", function(d) return colored(accent, d) end))
	end
	if items > 0 then parts[#parts + 1] = count(L.CHANGES_ITEMS, items) end
	if enchants > 0 then parts[#parts + 1] = count(L.CHANGES_ENCHANTS, enchants) end
	if gems > 0 then parts[#parts + 1] = count(L.CHANGES_GEMS, gems) end
	blocks[#blocks + 1] = #parts > 0 and (colored(dim, L.CHANGES) .. " " .. table.concat(parts, colored(dim, "  ·  ")))
		or colored(good, L.NO_CHANGES)

	local off = {}
	for _, slot in ipairs(ORDER) do
		local s = current.slots[slot]
		if s and (s.offSpec or s.weak) and not s.changedItem then off[#off + 1] = L.SLOTS[slot] or tostring(slot) end
	end
	if #off > 0 then
		blocks[#blocks + 1] = colored(warn, string.format(L.NOTE_OFFSPEC, table.concat(off, ", ")))
	end
	for _, note in ipairs(current.notes or {}) do
		blocks[#blocks + 1] = colored(dim, note)
	end
	for _, slot in ipairs(current.bankSlots or {}) do
		blocks[#blocks + 1] = colored(dim, string.format(L.NOTE_BANK, L.SLOTS[slot] or tostring(slot)))
	end
	footer:SetText(table.concat(blocks, "\n\n"))
	stack(footer, 10)
end

local function renderBis()
	local bis = current.bis or { slots = {} }
	for slot, row in pairs(rows) do fillRow(row, bis.slots[slot]) end
	stackY = 0
	local owned, total = bis.owned or 0, bis.total or 0
	bisCard.title:SetText(colored(accent, string.format(L.BIS_TITLE, current.phase or "")))
	bisCard.value:SetText(colored(Style.color.text, owned) .. colored(dim, " / " .. total))
	local frac = total > 0 and owned / total or 0
	local c = frac >= 1 and good or accent
	bisCard.bar:SetValues(0, frac, c[1], c[2], c[3])
	bisCard.detail:SetText(string.format(L.BIS_OWNED, owned, total))
	stack(bisCard, 50, 14)
	footer:SetText(colored({ 0.42, 0.42, 0.45 }, L.BIS_HELP))
	stack(footer, 10)
end

local function setRoleButtons()
	local show = current and current.canTank and onRole and tab ~= "talents"
	if not show then
		roleButtons.tank:Hide()
		roleButtons.dps:Hide()
		return
	end
	for key, b in pairs(roleButtons) do
		local selected = (key == "tank") == (current.tank == true)
		b.selected = selected
		b:SetBackdropColor(unpack(selected and { accent[1] * 0.3, accent[2] * 0.3, accent[3] * 0.3, 0.95 } or Style.color.panel))
		b:SetBackdropBorderColor(unpack(selected and accent or Style.color.border))
		b.label:SetTextColor(unpack(selected and Style.color.text or dim))
		b:Show()
	end
end

local function setTabButtons()
	for key, b in pairs(tabs) do
		local selected = key == tab
		b:SetBackdropColor(unpack(selected and Style.color.hover or Style.color.panel))
		b:SetBackdropBorderColor(unpack(selected and { 1, 1, 1, 0.12 } or Style.color.border))
		b.label:SetTextColor(unpack(selected and Style.color.text or dim))
		if selected then b.underline:Show() else b.underline:Hide() end
	end
end

local function render()
	if not current then return end
	hideCenter()
	local spec = current.spec or ""
	if current.specNames then
		spec = current.specNames[ns.lang] or spec
		if current.canTank then spec = spec .. " (" .. (current.tank and L.ROLE_TANK or L.ROLE_DPS) .. ")" end
	end
	window.caption:SetText((current.name or "") .. "  ·  " .. spec .. "  ·  " .. (current.phase or ""))
	if tab == "talents" then
		for _, row in pairs(rows) do row:Hide() end
		ns.TalentsView.Render(current)
	else
		ns.TalentsView.Hide()
		if tab == "bis" then renderBis() else renderCurrent() end
	end
	setTabButtons()
	setRoleButtons()
end

local TAB_DEFS = {
	{ "current", "TAB_CURRENT", 180 },
	{ "bis", "TAB_BIS", 80 },
	{ "talents", "TAB_TALENTS", 160 },
}

local function create()
	window = Style.Window("SaroniteSetupFrame", WIDTH, HEIGHT, "")
	Style.ScaleGrip(window, "setup.v4", DEFAULT_SCALE)
	rows = {}

	Style.LanguageSwitch(window)

	-- tabs under the title bar, an accent underline on the selected one
	tabs = {}
	local prev
	for _, def in ipairs(TAB_DEFS) do
		local key = def[1]
		local b = Style.Button(window, L[def[2]], def[3], 26)
		if prev then
			b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
		else
			b:SetPoint("TOPLEFT", MARGIN, -42)
		end
		b.underline = b:CreateTexture(nil, "OVERLAY")
		b.underline:SetTexture("Interface\\Buttons\\WHITE8X8")
		b.underline:SetVertexColor(accent[1], accent[2], accent[3], 1)
		b.underline:SetHeight(2)
		b.underline:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
		b.underline:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
		b:SetScript("OnClick", function() SetupView.SelectTab(key) end)
		b:SetScript("OnLeave", function() setTabButtons() end)
		b.key = def[2]
		tabs[key] = b
		prev = b
	end

	-- tank / DPS select, a segmented control right of the tabs
	roleButtons = {}
	local tankB = Style.Button(window, L.ROLE_TANK, 70, 26)
	tankB:SetPoint("LEFT", prev, "RIGHT", 24, 0)
	local dps = Style.Button(window, L.ROLE_DPS, 70, 26)
	dps:SetPoint("LEFT", tankB, "RIGHT", -1, 0)
	roleButtons.dps, roleButtons.tank = dps, tankB
	for key, b in pairs(roleButtons) do
		b:SetScript("OnClick", function(self)
			if not self.selected and onRole then ns.Safe(onRole, key == "tank") end
		end)
		b:SetScript("OnLeave", function() setRoleButtons() end)
		b:Hide()
	end

	for i, slot in ipairs(LEFT) do
		local row = newRow(window, false)
		row:SetPoint("TOPLEFT", MARGIN, -TOP - (i - 1) * ROW)
		rows[slot] = row
	end
	for i, slot in ipairs(RIGHT) do
		local row = newRow(window, true)
		row:SetPoint("TOPRIGHT", -MARGIN, -TOP - (i - 1) * ROW)
		rows[slot] = row
	end

	center = CreateFrame("Frame", nil, window)
	center:SetWidth(PANEL_WIDTH)
	center:SetHeight(10)
	center:SetPoint("TOP", 0, -TOP)

	capCards = { hit = newCapCard(), exp = newCapCard(), def = newCapCard(), crit = newCapCard(), haste = newCapCard() }

	priority = Style.Text(center, 12)
	center.priority = priority
	priority:SetWidth(PANEL_WIDTH)
	priority:SetJustifyH("LEFT")
	priority:SetJustifyV("TOP")
	priority:SetSpacing(4)

	statHeader = newStatRow(12)
	statHeader.bar:Hide()
	statRows = {}
	for i = 1, STAT_ROWS do statRows[i] = newStatRow(13) end

	footer = Style.Text(center, 12)
	center.footer = footer
	footer:SetWidth(PANEL_WIDTH)
	footer:SetJustifyH("LEFT")
	footer:SetJustifyV("TOP")
	footer:SetSpacing(3)

	bisCard = newCapCard()
	bisCard:SetScript("OnEnter", nil)

	-- calculating / error message, centered in the window
	message = Style.Text(window, 14)
	window.message = message
	message:SetPoint("CENTER", window, "CENTER", 0, 0)
	message:SetWidth(PANEL_WIDTH + 200)
	message:SetJustifyH("CENTER")

	ns.TalentsView.Create(window, MARGIN, TOP + 6, WIDTH - 2 * MARGIN)
	hideCenter()
	SetupView.Relabel()

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

-- Relabel updates texts created once (tabs, role buttons, headers).
function SetupView.Relabel()
	if not window then return end
	for _, b in pairs(tabs) do b.label:SetText(L[b.key]) end
	roleButtons.tank.label:SetText(L.ROLE_TANK)
	roleButtons.dps.label:SetText(L.ROLE_DPS)
	statHeader.name:SetText(colored(dim, L.GEAR_STATS))
	statHeader.before:SetText(L.COL_NOW)
	statHeader.after:SetText(L.COL_AFTER)
	statHeader.delta:SetText("±")
	for _, k in ipairs({ "before", "after", "delta" }) do statHeader[k]:SetTextColor(unpack(dim)) end
	for _, row in pairs(rows) do row.altLabel:SetText(L.ALTERNATIVE) end
	Style.RefreshLanguageSwitch(window)
	ns.TalentsView.Relabel()
	render()
end

function SetupView.SelectTab(name)
	if name ~= "bis" and name ~= "talents" then name = "current" end
	tab = name
	render()
end

-- Show renders a setup; role, when given, recomputes it: role(tank).
function SetupView.Show(setup, role)
	if not window then create() end
	current = setup
	onRole = role
	pending = 0
	render()
	window:Show()
end

local function showMessage(caption, text)
	if not window then create() end
	current = nil
	window.caption:SetText(caption or "")
	for _, row in pairs(rows) do
		row.slot = nil
		row:Hide()
	end
	hideCenter()
	ns.TalentsView.Hide()
	setRoleButtons()
	message:SetText(text)
	message:Show()
	window:Show()
end

function SetupView.ShowBusy(name)
	showMessage(name, colored(accent, L.CALCULATING))
end

function SetupView.ShowError(text)
	showMessage("", colored(warn, text))
end
