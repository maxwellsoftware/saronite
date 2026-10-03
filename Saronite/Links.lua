-- Names in the UI language and clicks on item / spell icons, shared by the
-- setup and talents views.
local _, ns = ...

local Links = {}
ns.Links = Links

-- the client language: names the client returns are in it
local clientLang = GetLocale() == "ruRU" and "ru" or "en"

local function pick(en, ru)
	if ns.lang == "ru" then return ru or en end
	return en or ru
end

-- upperFirst capitalizes the first letter, Latin or Cyrillic (UTF-8).
local function upperFirst(s)
	local b1, b2 = string.byte(s, 1, 2)
	if not b1 then return s end
	if b1 < 128 then return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2) end
	if b1 == 0xD0 and b2 and b2 >= 0xB0 and b2 <= 0xBF then -- а..п
		return string.char(0xD0, b2 - 0x20) .. string.sub(s, 3)
	elseif b1 == 0xD1 and b2 and b2 >= 0x80 and b2 <= 0x8F then -- р..я
		return string.char(0xD0, b2 + 0x20) .. string.sub(s, 3)
	elseif b1 == 0xD1 and b2 == 0x91 then -- ё
		return string.char(0xD0, 0x81) .. string.sub(s, 3)
	end
	return s
end
Links.UpperFirst = upperFirst

-- ItemName: items, gems and glyphs in the UI language. The client name is
-- used when it is in that language or the addon data does not know the item.
function Links.ItemName(id, clientName)
	if not id then return clientName end
	if ns.lang == clientLang and clientName then return clientName end
	local n = ns.Data.names and ns.Data.names[id]
	if n then return pick(n[1], n[2]) end
	for _, phase in pairs(ns.Data.phases or {}) do
		local g = phase.gems and phase.gems[id]
		if g then return pick(g.name, g.nameRU) end
	end
	local glyph = ns.Data.glyphs and ns.Data.glyphs[id]
	if glyph then return pick(glyph[1], glyph[2]) end
	return clientName
end

-- EnchantName: a short enchant name in the UI language, without the
-- "Enchant Cloak - " part ("Major Agility").
function Links.EnchantName(phase, enchantID, clientName)
	local data = phase and ns.Data.phases and ns.Data.phases[phase]
	local e = data and data.enchants and data.enchants[enchantID or 0]
	local name = clientName
	if e and not (ns.lang == clientLang and clientName) then name = pick(e.name, e.nameRU) end
	if not name then return nil end
	return upperFirst((string.gsub(name, "^[^-]+ %- ", "")))
end

local function fullLink(kind, id)
	if kind == "item" then
		local _, link = GetItemInfo(id)
		return link
	end
	return GetSpellLink and GetSpellLink(id)
end

-- Click: Shift+click links the item or spell into the open chat box,
-- Ctrl+click tries an item on; any other click opens it in the item viewer
-- (the window chat links open), a second click closes it.
function Links.Click(link)
	if not link then return end
	local kind, id = string.match(link, "^(%a+):(%d+)")
	id = tonumber(id)
	if not id then return end
	local full = fullLink(kind, id)
	if full and IsModifiedClick and IsModifiedClick() then
		if kind == "item" and HandleModifiedItemClick and HandleModifiedItemClick(full) then return end
		if kind == "spell" and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink and ChatEdit_InsertLink(full) then return end
	end
	local tip = ItemRefTooltip
	if not tip then return end
	if tip:IsShown() and tip.saroniteLink == link then
		tip:Hide()
		return
	end
	if ShowUIPanel then ShowUIPanel(tip) end
	if not tip:IsShown() then tip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
	tip:SetHyperlink(link)
	tip:Show()
	tip.saroniteLink = link
end

-- Clickable makes a frame open getLink(frame) ("item:123" / "spell:123").
function Links.Clickable(frame, getLink)
	frame:EnableMouse(true)
	frame:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then ns.Safe(Links.Click, getLink(self)) end
	end)
end
