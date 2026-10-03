-- Main window: export (string pre-selected for Ctrl+C) and import (paste the
-- bot's answer). WoW has no clipboard API, hence the edit boxes.
local _, ns = ...

local L = ns.L
local Style = ns.Style
local UI = {}
ns.UI = UI

local window, area, info, modeButtons
local mode = "export"
local exportText = ""

local function setInfo(text, color)
	info:SetText(text or "")
	info:SetTextColor(unpack(color or Style.color.dim))
end

local function showExport()
	mode = "export"
	window.caption:SetText(L.EXPORT_TITLE)
	modeButtons.action.label:SetText(L.REFRESH)

	local ok, result, notes = pcall(ns.Export.Build)
	if not ok then
		exportText = ""
		area.edit:SetText("")
		setInfo(string.format(L.ERROR, tostring(result)), Style.color.warn)
		return
	end

	exportText = result
	area.edit:SetText(result)
	area.edit:SetFocus()
	area.edit:HighlightText()

	local lines = { string.format(L.LENGTH, #result) .. "  " .. L.HINT }
	for _, key in ipairs(notes) do
		lines[#lines + 1] = "|cffffb340" .. L[key] .. "|r"
	end
	if not ns.GetBank() then
		lines[#lines + 1] = L.BANK_NONE
	end
	setInfo(table.concat(lines, "\n"))
end

local function showImport()
	mode = "import"
	window.caption:SetText(L.IMPORT_TITLE)
	modeButtons.action.label:SetText(L.IMPORT_SHOW)
	area.edit:SetText("")
	area.edit:SetFocus()
	setInfo(L.IMPORT_HINT)
end

local function doImport()
	local err = ns.Planner.Paste(area.edit:GetText())
	if err then
		setInfo(L[err] or err, Style.color.warn)
		return
	end
	window:Hide()
end

local function create()
	window = Style.Window("SaroniteFrame", 560, 300, "")
	Style.ScaleGrip(window, "main", 1.2)
	Style.LanguageSwitch(window)

	area = Style.EditArea(window)
	area:SetPoint("TOPLEFT", 10, -40)
	area:SetPoint("BOTTOMRIGHT", -10, 84)

	local edit = area.edit
	edit:SetScript("OnEscapePressed", function() window:Hide() end)
	edit:SetScript("OnEditFocusGained", function(self)
		if mode == "export" then self:HighlightText() end
	end)
	-- In export mode the box is read-only: undo typing.
	edit:SetScript("OnTextChanged", function(self, userInput)
		if mode == "export" and userInput and self:GetText() ~= exportText then
			self:SetText(exportText)
			self:HighlightText()
		end
	end)

	info = Style.Text(window, 11)
	info:SetPoint("TOPLEFT", area, "BOTTOMLEFT", 2, -6)
	info:SetPoint("RIGHT", window, "RIGHT", -12, 0)
	info:SetJustifyV("TOP")

	modeButtons = {}
	local action = Style.Button(window, L.REFRESH, 120, 22)
	action:SetPoint("BOTTOMLEFT", 10, 10)
	action:SetScript("OnClick", function()
		ns.Safe(mode == "export" and showExport or doImport)
	end)
	modeButtons.action = action

	local toggle = Style.Button(window, L.IMPORT, 120, 22)
	toggle:SetPoint("LEFT", action, "RIGHT", 6, 0)
	toggle:SetScript("OnClick", function(self)
		if mode == "export" then
			showImport()
			self.label:SetText(L.EXPORT)
		else
			showExport()
			self.label:SetText(L.IMPORT)
		end
	end)
	modeButtons.toggle = toggle

	local compute = Style.Button(window, L.COMPUTE, 150, 22)
	compute:SetPoint("BOTTOMRIGHT", -10, 10)
	compute.label:SetTextColor(unpack(Style.color.accent))
	modeButtons.compute = compute
	compute:SetScript("OnClick", function()
		window:Hide()
		ns.Safe(ns.Planner.Mine)
	end)

	local last = Style.Button(window, L.LAST_SETUP, 130, 22)
	last:SetPoint("RIGHT", compute, "LEFT", -6, 0)
	modeButtons.last = last
	last:SetScript("OnClick", function()
		if ns.Planner.ShowLast() then
			window:Hide()
		else
			setInfo(L.NO_LAST_SETUP, Style.color.warn)
		end
	end)
end

function UI.Show(which)
	if not window then create() end
	window:Show()
	if which == "import" then
		showImport()
		modeButtons.toggle.label:SetText(L.EXPORT)
	else
		showExport()
		modeButtons.toggle.label:SetText(L.IMPORT)
	end
end

function UI.Toggle()
	if window and window:IsShown() then
		window:Hide()
	else
		UI.Show()
	end
end

-- Small button on the character sheet. Shift+drag moves it; the position is
-- saved per account.
local function CreateCharacterButton()
	if not PaperDollFrame then return end

	local button = Style.Button(PaperDollFrame, L.BUTTON, 88, 24)
	PaperDollFrame.saroniteButton = button
	-- visible on the dark character sheet: tinted background, accent border
	-- and label
	local a = Style.color.accent
	local function idle(self)
		self:SetBackdropColor(a[1] * 0.22, a[2] * 0.22, a[3] * 0.22, 0.95)
		self:SetBackdropBorderColor(a[1], a[2], a[3], 1)
	end
	button.label:SetTextColor(a[1], a[2], a[3], 1)
	idle(button)
	button:SetMovable(true)
	button:RegisterForDrag("LeftButton")

	local pos = SaroniteDB.buttonPos
	if pos then
		button:SetPoint("TOPLEFT", PaperDollFrame, "TOPLEFT", pos.x, pos.y)
	elseif CharacterMainHandSlot then
		-- Bottom left, in the free space next to the weapon slots.
		button:SetPoint("BOTTOMRIGHT", CharacterMainHandSlot, "BOTTOMLEFT", -12, 0)
	else
		button:SetPoint("BOTTOMLEFT", PaperDollFrame, "BOTTOMLEFT", 24, 86)
	end

	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			ns.Safe(UI.Show)
		else
			ns.Safe(ns.Planner.Mine)
		end
	end)
	button:SetScript("OnDragStart", function(self)
		if IsShiftKeyDown() then self:StartMoving() end
	end)
	button:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- StartMoving re-anchors to the screen; store the offset relative to
		-- the character sheet instead and keep the client from saving its own
		-- layout for this frame.
		local x = self:GetLeft() - PaperDollFrame:GetLeft()
		local y = self:GetTop() - PaperDollFrame:GetTop()
		self:SetUserPlaced(false)
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", PaperDollFrame, "TOPLEFT", x, y)
		SaroniteDB.buttonPos = { x = x, y = y }
	end)

	button:SetScript("OnEnter", function(self)
		self:SetBackdropColor(a[1] * 0.4, a[2] * 0.4, a[3] * 0.4, 1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Saronite")
		GameTooltip:AddLine(L.BUTTON_TOOLTIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		idle(self)
		GameTooltip:Hide()
	end)
end

-- Relabel updates texts created once after a language switch.
function UI.Relabel()
	if PaperDollFrame and PaperDollFrame.saroniteButton then
		PaperDollFrame.saroniteButton.label:SetText(L.BUTTON)
	end
	if not window then return end
	modeButtons.compute.label:SetText(L.COMPUTE)
	modeButtons.last.label:SetText(L.LAST_SETUP)
	Style.RefreshLanguageSwitch(window)
	if window:IsShown() then UI.Show(mode) end
end

function UI.Init()
	CreateCharacterButton()
end
