-- Renders an imported setup like a character sheet: items with their gems
-- and enchants, changes highlighted, caps and notes in the middle.
local _, ns = ...

local L = ns.L
local Style = ns.Style
local SetupView = {}
ns.SetupView = SetupView

local LEFT = { 1, 2, 3, 15, 5, 9 }
local RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOTTOM = { 16, 17, 18 }

local ICON = 32
local ROW = 40
local COLUMN = 214
local WIDTH, HEIGHT = 640, 420

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local window, rows, info, roleButton
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

local function enchantName(slot)
	if not slot.enchantSource then return nil end
	if slot.enchantKind == "s" then
		return (GetSpellInfo(slot.enchantSource))
	end
	local name = itemInfo(slot.enchantSource)
	return name
end

local function locationText(slot)
	if slot.loc == "B" then return L.LOC_BAG end
	if slot.loc == "K" then return L.LOC_BANK end
	return nil
end

local function newRow(parent, alignRight)
	local row = CreateFrame("Frame", nil, parent)
	row:SetWidth(COLUMN)
	row:SetHeight(ICON)

	row.icon = Style.Icon(row, ICON)
	row.icon:EnableMouse(true)
	row.name = Style.Text(row, 12)
	row.detail = Style.Text(row, 11)
	row.detail:SetTextColor(unpack(Style.color.dim))
	row.gems = {}
	for i = 1, 4 do
		row.gems[i] = Style.Icon(row, 13)
	end

	if alignRight then
		row.icon:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row.name:SetPoint("TOPRIGHT", row.icon, "TOPLEFT", -6, -1)
		row.name:SetJustifyH("RIGHT")
		row.gems[1]:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMLEFT", -6, 1)
		for i = 2, 4 do row.gems[i]:SetPoint("RIGHT", row.gems[i - 1], "LEFT", -2, 0) end
		row.detail:SetJustifyH("RIGHT")
	else
		row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
		row.gems[1]:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
		for i = 2, 4 do row.gems[i]:SetPoint("LEFT", row.gems[i - 1], "RIGHT", 2, 0) end
	end
	row.name:SetWidth(COLUMN - ICON - 8)
	row.alignRight = alignRight

	row.icon:SetScript("OnEnter", function(self)
		local s = row.slot
		if not s then return end
		GameTooltip:SetOwner(self, alignRight and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. s.item)
		local ench = enchantName(s)
		if ench or #s.gems > 0 then GameTooltip:AddLine(" ") end
		if ench then
			GameTooltip:AddLine(L.ENCHANT .. ": " .. ench, Style.color.accent[1], Style.color.accent[2], Style.color.accent[3])
		end
		for _, gem in ipairs(s.gems) do
			local name = itemInfo(gem)
			if name then GameTooltip:AddLine("• " .. name, 0.9, 0.9, 0.9) end
		end
		local where = locationText(s)
		if where then GameTooltip:AddLine(where, Style.color.warn[1], Style.color.warn[2], Style.color.warn[3]) end
		GameTooltip:Show()
	end)
	row.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function fillRow(row, slot)
	row.slot = slot
	if not slot then
		row.icon.texture:SetTexture(nil)
		row.icon:SetBorder(0, 0, 0)
		row.name:SetText(L.EMPTY_SLOT)
		row.name:SetTextColor(unpack(Style.color.dim))
		row.detail:SetText("")
		for _, g in ipairs(row.gems) do g:Hide() end
		return
	end

	local name, quality, texture = itemInfo(slot.item)
	row.icon.texture:SetTexture(texture)
	if slot.changedItem then
		row.icon:SetBorder(unpack(Style.color.accent))
	else
		row.icon:SetBorder(Style.QualityColor(quality))
	end
	row.name:SetText(name or ("#" .. slot.item))
	row.name:SetTextColor(Style.QualityColor(quality))

	-- gems: icons right after the item; enchant (and location) as text
	local shown = 0
	for i, g in ipairs(row.gems) do
		local id = slot.gems[i]
		if id and id > 0 then
			local _, _, tex = itemInfo(id)
			g.texture:SetTexture(tex)
			if slot.changedGems then g:SetBorder(unpack(Style.color.accent)) else g:SetBorder(0, 0, 0) end
			g:Show()
			shown = i
		elseif id then
			g.texture:SetTexture(nil)
			g:SetBorder(unpack(Style.color.warn))
			g:Show()
			shown = i
		else
			g:Hide()
		end
	end

	local parts = {}
	local ench = enchantName(slot)
	if ench then
		local c = slot.changedEnchant and Style.color.accent or Style.color.dim
		parts[#parts + 1] = string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, ench)
	end
	local where = locationText(slot)
	if where then
		parts[#parts + 1] = "|cffffb340" .. where .. "|r"
	end
	if slot.buckle then
		parts[#parts + 1] = "|cffffb340" .. L.BUCKLE .. "|r"
	end
	row.detail:SetText(table.concat(parts, "  "))
	row.detail:ClearAllPoints()
	local anchor = shown > 0 and row.gems[shown] or row.icon
	if row.alignRight then
		row.detail:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
		if shown == 0 then row.detail:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMLEFT", -6, 2) end
	else
		row.detail:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
		if shown == 0 then row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 2) end
	end
	row.detail:SetWidth(COLUMN - ICON - 12 - shown * 15)
end

local function capLine(label, cap, percent)
	if not cap then return nil end
	local fmt = percent and "%.2f%%" or "%d"
	local ok = cap.after + 0.05 >= cap.cap
	local color = ok and "|cff66d973" or "|cffffb340"
	return string.format("%s\n|cff8c8c94" .. fmt .. "|r → %s" .. fmt .. "|r |cff8c8c94/ " .. fmt .. "|r",
		label, cap.before, color, cap.after, cap.cap)
end

local function render()
	if not current then return end
	for _, row in pairs(rows) do row:Show() end
	window.caption:SetText((current.name or "") .. "  ·  " .. (current.spec or "") .. "  ·  " .. (current.phase or ""))
	for slot, row in pairs(rows) do
		fillRow(row, current.slots[slot])
	end

	local lines = {}
	local hit = capLine(L.CAP_HIT, current.caps.hit, true)
	local exp = capLine(L.CAP_EXP, current.caps.exp, false)
	if hit then lines[#lines + 1] = hit end
	if exp then lines[#lines + 1] = exp end

	local items, enchants, gems = 0, 0, 0
	for _, s in pairs(current.slots) do
		if s.changedItem then items = items + 1 end
		if s.changedEnchant then enchants = enchants + 1 end
		if s.changedGems then gems = gems + 1 end
	end
	lines[#lines + 1] = string.format(L.CHANGES, items, enchants, gems)
	for _, note in ipairs(current.notes) do
		lines[#lines + 1] = "|cff8c8c94" .. note .. "|r"
	end
	info:SetText(table.concat(lines, "\n\n"))

	if current.canTank and onToggleRole then
		roleButton.label:SetText(current.tank and L.AS_DPS or L.AS_TANK)
		roleButton:Show()
	else
		roleButton:Hide()
	end
end

local function create()
	window = Style.Window("SaroniteSetupFrame", WIDTH, HEIGHT, "")
	rows = {}

	for i, slot in ipairs(LEFT) do
		local row = newRow(window, false)
		row:SetPoint("TOPLEFT", 12, -40 - (i - 1) * ROW)
		rows[slot] = row
	end
	for i, slot in ipairs(RIGHT) do
		local row = newRow(window, true)
		row:SetPoint("TOPRIGHT", -12, -40 - (i - 1) * ROW)
		rows[slot] = row
	end
	for i, slot in ipairs(BOTTOM) do
		local row = newRow(window, false)
		row:SetWidth(COLUMN - 30)
		row:SetPoint("BOTTOMLEFT", 12 + (i - 1) * (COLUMN - 10), 12)
		rows[slot] = row
	end

	local divider = Style.Line(window, 1, 1)
	divider:SetPoint("BOTTOMLEFT", 1, 54)
	divider:SetPoint("BOTTOMRIGHT", -1, 54)

	info = Style.Text(window, 12)
	info:SetPoint("TOP", 0, -46)
	info:SetWidth(WIDTH - 2 * COLUMN - 40)
	info:SetJustifyH("CENTER")
	info:SetJustifyV("TOP")
	info:SetSpacing(2)

	roleButton = Style.Button(window, L.AS_TANK, 96, 18)
	roleButton:SetPoint("TOPRIGHT", -32, -6)
	roleButton:SetScript("OnClick", function()
		if onToggleRole then onToggleRole() end
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
	info:SetText(text)
	window:Show()
end

function SetupView.ShowBusy(name)
	message(name, L.CALCULATING)
end

function SetupView.ShowError(text)
	message("", "|cffffb340" .. text .. "|r")
end
