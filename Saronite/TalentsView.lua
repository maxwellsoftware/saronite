-- Talents & glyphs tab of the setup window: recommended builds of the spec
-- (wowsims presets) on the three class trees, with the player's own talents
-- compared point by point, and the build's glyphs.
local _, ns = ...

local L = ns.L
local Style = ns.Style
local Rules = ns.Rules
local Links = ns.Links

local TalentsView = {}
ns.TalentsView = TalentsView

local CELL, STEP = 32, 40 -- talent icon and grid step
local ROWS, COLS = 11, 4
local TREE_WIDTH = COLS * STEP - (STEP - CELL)
local TREE_GAP = 22
local LIST_WIDTH = 210
local MAX_BUILDS = 9
local GLYPH_ICON = 30

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local frame, list, trees, glyphRows, summary, titles
local view, builds, selected

local accent, warn, dim = Style.color.accent, Style.color.warn, Style.color.dim

local function hex(c) return Style.Hex(c) end

local function treeName(class, tab)
	local s = Rules.specs[class] and Rules.specs[class][tab]
	if not s then return "" end
	return ns.lang == "ru" and s.name or s.nameEN
end

-- ranks parses a talent string ("-5432...-2035") into rank lists per tree.
local function parseRanks(text)
	local out = { {}, {}, {} }
	local tab = 1
	for i = 1, string.len(text or "") do
		local ch = string.sub(text, i, i)
		if ch == "-" then
			tab = tab + 1
		elseif out[tab] then
			out[tab][#out[tab] + 1] = tonumber(ch) or 0
		end
	end
	return out
end

local function points(ranks)
	local n = 0
	for _, r in ipairs(ranks) do n = n + r end
	return n
end

local function isPlayer()
	if not view then return false end
	local _, class = UnitClass("player")
	return view.class == class and view.name == UnitName("player")
end

-- Talent index by (tier, column) for the player's own class, to show the
-- real talent tooltip and icon.
local function talentIndex(tab, row, col)
	if not isPlayer() or not GetNumTalents then return nil end
	for i = 1, GetNumTalents(tab) or 0 do
		local _, icon, tier, column = GetTalentInfo(tab, i)
		if tier == row + 1 and column == col + 1 then return i, icon end
	end
	return nil
end

-- diff counts talents where the player's ranks differ from the build.
local function diff(rec, mine, tree)
	local n = 0
	for tab = 1, 3 do
		for k = 1, #((tree[tab] or {}).talents or {}) do
			if (rec[tab][k] or 0) ~= (mine[tab][k] or 0) then n = n + 1 end
		end
	end
	return n
end

local function mineRanks()
	local out = { {}, {}, {} }
	for tab = 1, 3 do
		local s = view and view.talentRanks and view.talentRanks[tab] or ""
		for i = 1, string.len(s) do out[tab][i] = tonumber(string.sub(s, i, i)) or 0 end
	end
	return out
end

-- Builds of the spec: the same simulator (feral cat / bear, DK DPS / tank
-- are separate), the spec tree first.
local function buildsFor(v)
	local all = ns.Data.builds and ns.Data.builds[v.class] or {}
	local out, other = {}, {}
	for _, b in ipairs(all) do
		if b.sim == v.sim then
			if b.tab == v.specTab then out[#out + 1] = b else other[#other + 1] = b end
		end
	end
	for _, b in ipairs(other) do out[#out + 1] = b end
	if #out == 0 then
		for _, b in ipairs(all) do
			if b.tab == v.specTab then out[#out + 1] = b end
		end
	end
	return out
end

local function hasGlyph(id)
	local data = ns.Data.glyphs and ns.Data.glyphs[id]
	if not data or not view or not view.glyphs then return false end
	local itemName = GetItemInfo(id)
	for _, spell in ipairs(view.glyphs) do
		if spell and spell ~= 0 then
			if spell == data[6] then return true end
			local name = GetSpellInfo(spell)
			if itemName and name == itemName then return true end
		end
	end
	return false
end

-- Widgets ----------------------------------------------------------------

local function newCell(parent, tab, index)
	local cell = Style.Icon(parent, CELL)
	cell.tab, cell.index = tab, index
	cell.rank = Style.Text(cell, 10)
	cell.rank:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 2, -3)
	cell.rank:SetJustifyH("RIGHT")
	cell:EnableMouse(true)
	cell:SetScript("OnEnter", function(self)
		local t = self.talent
		if not t then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local idx = talentIndex(self.tab, t.row, t.col)
		if idx and GameTooltip.SetTalent then
			GameTooltip:SetTalent(self.tab, idx)
		elseif t.spell and t.spell > 0 then
			GameTooltip:SetHyperlink("spell:" .. t.spell)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(string.format(L.TIP_BUILD_RANK, self.rec or 0, t.max), accent[1], accent[2], accent[3])
		local ok = (self.mine or 0) == (self.rec or 0)
		local c = ok and Style.color.good or warn
		GameTooltip:AddLine(string.format(L.TIP_YOUR_RANK, self.mine or 0, t.max), c[1], c[2], c[3])
		GameTooltip:Show()
	end)
	cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
	Links.Clickable(cell, function(self)
		return self.talent and self.talent.spell and self.talent.spell > 0 and ("spell:" .. self.talent.spell) or nil
	end)
	return cell
end

local function newGlyphRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(50)
	row.icon = Style.Icon(row, GLYPH_ICON)
	row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
	row.name = Style.Text(row, 13)
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
	row.name:SetHeight(15)
	row.status = Style.Text(row, 11)
	row.status:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
	row.status:SetJustifyH("RIGHT")
	row.effect = Style.Text(row, 11)
	row.effect:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
	row.effect:SetJustifyV("TOP")
	row.effect:SetTextColor(unpack(dim))
	row.effect:SetHeight(28)
	row.icon:EnableMouse(true)
	row.icon:SetScript("OnEnter", function(self)
		if not row.id then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. row.id)
		local c = row.owned and Style.color.good or warn
		GameTooltip:AddLine(row.owned and L.TIP_GLYPH_HAVE or L.TIP_GLYPH_MISSING, c[1], c[2], c[3])
		GameTooltip:Show()
	end)
	row.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	Links.Clickable(row.icon, function() return row.id and ("item:" .. row.id) or nil end)
	return row
end

-- Render -----------------------------------------------------------------

local function renderList()
	for i, b in ipairs(list) do
		local build = builds[i]
		if build then
			b.label:SetText(build.name)
			local on = build == selected
			b.selected = on
			b:SetBackdropColor(unpack(on and { accent[1] * 0.3, accent[2] * 0.3, accent[3] * 0.3, 0.95 } or Style.color.panel))
			b:SetBackdropBorderColor(unpack(on and accent or Style.color.border))
			b.label:SetTextColor(unpack(on and Style.color.text or dim))
			b:Show()
		else
			b:Hide()
		end
	end
end

local function renderTrees()
	local tree = ns.Data.talentTrees and ns.Data.talentTrees[view.class] or {}
	local rec = selected and parseRanks(selected.talents) or { {}, {}, {} }
	local mine = mineRanks()
	for tab = 1, 3 do
		local t = trees[tab]
		local talents = tree[tab] and tree[tab].talents or {}
		local recPoints, minePoints = points(rec[tab]), points(mine[tab])
		local main = selected and selected.tab == tab
		titles[tab]:SetText("|cff" .. hex(main and accent or Style.color.text) .. treeName(view.class, tab) .. "|r  |cff"
			.. hex(dim) .. recPoints .. "|r")
		for k, cell in ipairs(t.cells) do
			local talent = talents[k]
			if talent then
				cell.talent = talent
				cell.rec, cell.mine = rec[tab][k] or 0, mine[tab][k] or 0
				cell:ClearAllPoints()
				cell:SetPoint("TOPLEFT", t, "TOPLEFT", talent.col * STEP, -talent.row * STEP)
				local _, icon = talentIndex(tab, talent.row, talent.col)
				if not icon and talent.spell > 0 then
					local _, _, spellIcon = GetSpellInfo(talent.spell)
					icon = spellIcon
				end
				cell.texture:SetTexture(icon or QUESTION)
				if cell.rec > 0 then
					cell.texture:SetDesaturated(false)
					cell:SetAlpha(1)
					cell:SetBorder(unpack(cell.rec == cell.mine and accent or warn))
					cell.rank:SetText(cell.rec .. "/" .. talent.max)
					cell.rank:SetTextColor(unpack(cell.rec == talent.max and accent or Style.color.text))
					cell.rank:Show()
				else
					cell.texture:SetDesaturated(true)
					cell:SetAlpha(cell.mine > 0 and 0.8 or 0.35)
					if cell.mine > 0 then cell:SetBorder(unpack(warn)) else cell:SetBorder(0, 0, 0) end
					cell.rank:Hide()
				end
				cell:Show()
			else
				cell.talent = nil
				cell:Hide()
			end
		end
		t.minePoints = minePoints
	end

	-- summary under the build list
	local parts = {}
	if selected then
		local r = {}
		for tab = 1, 3 do r[tab] = points(rec[tab]) end
		parts[#parts + 1] = "|cff" .. hex(accent) .. selected.name .. "|r  " .. table.concat(r, " / ")
		local m = {}
		for tab = 1, 3 do m[tab] = points(mine[tab]) end
		parts[#parts + 1] = string.format(L.TALENTS_YOURS, table.concat(m, " / "))
		local d = diff(rec, mine, tree)
		if d == 0 then
			parts[#parts + 1] = "|cff" .. hex(Style.color.good) .. L.TALENTS_MATCH .. "|r"
		else
			parts[#parts + 1] = "|cff" .. hex(warn) .. string.format(L.TALENTS_DIFF, d) .. "|r"
		end
	else
		parts[#parts + 1] = "|cff" .. hex(warn) .. L.NO_BUILDS .. "|r"
	end
	-- legend: the border colors of the talent icons
	parts[#parts + 1] = L.LEGEND .. "  |cff" .. hex(accent) .. L.LEGEND_MATCH .. "|r  ·  |cff" .. hex(warn) .. L.LEGEND_DIFF .. "|r"
	parts[#parts + 1] = "|cff6b6b72" .. L.CLICK_HINT .. "|r"
	parts[#parts + 1] = "|cff6b6b72" .. L.BUILDS_SOURCE .. "|r"
	summary:SetText(table.concat(parts, "\n\n"))
end

local function renderGlyphs()
	local major = selected and selected.major or {}
	local minor = selected and selected.minor or {}
	for i, row in ipairs(glyphRows) do
		local id = i <= 3 and major[i] or minor[i - 3]
		local data = id and ns.Data.glyphs and ns.Data.glyphs[id]
		row.id = id
		if id and data then
			row.owned = hasGlyph(id)
			row.icon.texture:SetTexture((data[3] and data[3] ~= "") and ("Interface\\Icons\\" .. data[3]) or QUESTION)
			row.icon:SetBorder(unpack(row.owned and accent or warn))
			row.name:SetText(ns.lang == "ru" and data[2] or data[1])
			row.effect:SetText(ns.lang == "ru" and data[5] or data[4])
			row.status:SetText(row.owned and L.GLYPH_HAVE or L.GLYPH_MISSING)
			row.status:SetTextColor(unpack(row.owned and Style.color.good or warn))
			row:Show()
		else
			row:Hide()
		end
	end
end

function TalentsView.Render(v)
	if not frame then return end
	if v ~= view then
		view = v
		builds = buildsFor(v)
		-- default: the build closest to the player's talents
		selected = nil
		local tree = ns.Data.talentTrees and ns.Data.talentTrees[v.class] or {}
		local mine, best = mineRanks(), nil
		for _, b in ipairs(builds) do
			local d = diff(parseRanks(b.talents), mine, tree)
			if not best or d < best then best, selected = d, b end
		end
	end
	renderList()
	renderTrees()
	renderGlyphs()
	frame:Show()
end

function TalentsView.Hide()
	if frame then frame:Hide() end
end

function TalentsView.Relabel()
	if not frame then return end
	frame.listTitle:SetText(L.BUILDS)
	frame.majorTitle:SetText(L.GLYPHS_MAJOR)
	frame.minorTitle:SetText(L.GLYPHS_MINOR)
	if view and frame:IsShown() then TalentsView.Render(view) end
end

-- Create builds the tab inside parent: left (x) and top (y) offsets and the
-- width of the area.
function TalentsView.Create(parent, x, y, width)
	frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	frame:SetWidth(width)
	frame:SetHeight(ROWS * STEP + 30)

	-- build list
	frame.listTitle = Style.Text(frame, 13)
	frame.listTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	frame.listTitle:SetTextColor(unpack(accent))
	frame.listTitle:SetText(L.BUILDS)
	list = {}
	for i = 1, MAX_BUILDS do
		local b = Style.Button(frame, "", LIST_WIDTH, 24)
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -22 - (i - 1) * 28)
		b.label:SetWidth(LIST_WIDTH - 12)
		b.label:SetHeight(14)
		b:SetScript("OnClick", function()
			if builds[i] and builds[i] ~= selected then
				selected = builds[i]
				TalentsView.Render(view)
			end
		end)
		b:SetScript("OnLeave", function() renderList() end)
		list[i] = b
	end
	summary = Style.Text(frame, 12)
	summary:SetWidth(LIST_WIDTH)
	summary:SetJustifyV("TOP")
	summary:SetSpacing(2)
	summary:SetPoint("TOPLEFT", list[1], "TOPLEFT", 0, -MAX_BUILDS * 28 - 8)

	-- three trees
	trees, titles = {}, {}
	local treeX = LIST_WIDTH + 24
	for tab = 1, 3 do
		local left = treeX + (tab - 1) * (TREE_WIDTH + TREE_GAP)
		local card = Style.Card(frame, TREE_WIDTH + 16, ROWS * STEP + 30)
		card:SetPoint("TOPLEFT", frame, "TOPLEFT", left - 8, 4)
		titles[tab] = Style.Text(frame, 13)
		titles[tab]:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -2)
		titles[tab]:SetWidth(TREE_WIDTH)
		titles[tab]:SetHeight(15)
		local t = CreateFrame("Frame", nil, frame)
		t:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -24)
		t:SetWidth(TREE_WIDTH)
		t:SetHeight(ROWS * STEP)
		t.cells = {}
		for k = 1, 31 do t.cells[k] = newCell(t, tab, k) end
		trees[tab] = t
	end

	-- glyphs
	local glyphX = treeX + 3 * TREE_WIDTH + 2 * TREE_GAP + 24
	local glyphWidth = width - glyphX
	frame.majorTitle = Style.Text(frame, 13)
	frame.majorTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", glyphX, 0)
	frame.majorTitle:SetTextColor(unpack(accent))
	frame.majorTitle:SetText(L.GLYPHS_MAJOR)
	frame.minorTitle = Style.Text(frame, 13)
	frame.minorTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", glyphX, -22 - 3 * 56 - 10)
	frame.minorTitle:SetTextColor(unpack(accent))
	frame.minorTitle:SetText(L.GLYPHS_MINOR)
	glyphRows = {}
	for i = 1, 6 do
		local row = newGlyphRow(frame)
		local top = i <= 3 and (22 + (i - 1) * 56) or (22 + 3 * 56 + 10 + 22 + (i - 4) * 56)
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", glyphX, -top)
		row:SetWidth(glyphWidth)
		row.name:SetWidth(glyphWidth - GLYPH_ICON - 8 - 70)
		row.effect:SetWidth(glyphWidth - GLYPH_ICON - 8)
		glyphRows[i] = row
	end
	frame:Hide()
	return frame
end
