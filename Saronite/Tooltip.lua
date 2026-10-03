-- Adds "Drops: <zone> — <boss>" to every item tooltip in the game (bags,
-- character sheet, chat links, auction house, comparison tooltips and the
-- addon's own windows). Can be turned off with /sar sources.
local _, ns = ...

local L = ns.L
local Tooltip = {}
ns.Tooltip = Tooltip

local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3" }
local MAX_SOURCES = 3

local function itemID(tip)
	local _, link = tip:GetItem()
	return link and tonumber(string.match(link, "item:(%d+)"))
end

-- OnTooltipSetItem can fire more than once for the same tooltip; the lines
-- are added once per item until the tooltip is cleared.
local function addSources(tip)
	if SaroniteDB and SaroniteDB.sources == false then return end
	local id = itemID(tip)
	if not id or tip.saroniteSource == id then return end
	local refs = ns.Data.sources and ns.Data.sources[id]
	if not refs then return end
	tip.saroniteSource = id
	for i, ref in ipairs(refs) do
		if i > MAX_SOURCES then break end
		tip:AddLine(L.SOURCE .. " " .. (ns.Data.sourceNames[ref] or "?"), 0.75, 0.75, 0.8)
	end
	tip:Show() -- resize to the new lines
end

function Tooltip.Init()
	for _, name in ipairs(TOOLTIPS) do
		local tip = _G[name]
		if tip and tip.HookScript then
			tip:HookScript("OnTooltipSetItem", addSources)
			tip:HookScript("OnTooltipCleared", function(self) self.saroniteSource = nil end)
		end
	end
end

function Tooltip.Toggle()
	SaroniteDB.sources = SaroniteDB.sources == false
	ns.Print(SaroniteDB.sources and L.SOURCES_ON or L.SOURCES_OFF)
end
