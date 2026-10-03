-- Export window and the character sheet button.
-- WoW has no clipboard API: the string is shown pre-selected in an edit box
-- and the player presses Ctrl+C.
local _, ns = ...

local L = ns.L
local UI = {}
ns.UI = UI

local window, editBox, infoText
local currentText = ""

local function SetExportText(text)
	currentText = text
	editBox:SetText(text)
	editBox:SetFocus()
	editBox:HighlightText()
end

function UI.Refresh()
	local ok, result, notes = pcall(ns.Export.Build)
	if not ok then
		ns.Print(string.format(L.ERROR, tostring(result)))
		SetExportText("")
		infoText:SetText(string.format(L.ERROR, tostring(result)))
		return
	end

	SetExportText(result)

	local lines = { string.format(L.LENGTH, #result) .. " " .. L.HINT }
	for _, key in ipairs(notes) do
		lines[#lines + 1] = "|cffffd100" .. L[key] .. "|r"
	end
	if not ns.GetBank() then
		lines[#lines + 1] = "|cff999999" .. L.BANK_NONE .. "|r"
	end
	infoText:SetText(table.concat(lines, "\n"))
end

local function CreateWindow()
	window = CreateFrame("Frame", "SaroniteFrame", UIParent)
	window:SetWidth(560)
	window:SetHeight(320)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:Hide()
	-- Escape closes the window like any Blizzard panel.
	table.insert(UISpecialFrames, "SaroniteFrame")

	local title = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -18)
	title:SetText(L.TITLE)

	local closeX = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	closeX:SetPoint("TOPRIGHT", -6, -6)

	local scroll = CreateFrame("ScrollFrame", "SaroniteScroll", window, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 22, -48)
	scroll:SetPoint("BOTTOMRIGHT", -40, 96)

	editBox = CreateFrame("EditBox", nil, scroll)
	editBox:SetMultiLine(true)
	editBox:SetAutoFocus(false)
	editBox:SetMaxLetters(0)
	editBox:SetFontObject(ChatFontNormal)
	editBox:SetWidth(490)
	editBox:SetScript("OnEscapePressed", function() window:Hide() end)
	editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	-- Read-only: undo any typing so a stray key press cannot corrupt the string.
	editBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self:GetText() ~= currentText then
			self:SetText(currentText)
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(editBox)
	-- Clicking anywhere in the text area focuses and re-selects the string.
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function()
		editBox:SetFocus()
		editBox:HighlightText()
	end)

	infoText = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	infoText:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -8)
	infoText:SetPoint("RIGHT", window, "RIGHT", -24, 0)
	infoText:SetJustifyH("LEFT")
	infoText:SetJustifyV("TOP")

	local refresh = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	refresh:SetWidth(110)
	refresh:SetHeight(24)
	refresh:SetPoint("BOTTOMRIGHT", window, "BOTTOM", -6, 18)
	refresh:SetText(L.REFRESH)
	refresh:SetScript("OnClick", UI.Refresh)

	local close = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	close:SetWidth(110)
	close:SetHeight(24)
	close:SetPoint("BOTTOMLEFT", window, "BOTTOM", 6, 18)
	close:SetText(L.CLOSE)
	close:SetScript("OnClick", function() window:Hide() end)
end

function UI.Show()
	if not window then CreateWindow() end
	window:Show()
	UI.Refresh()
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

	local button = CreateFrame("Button", "SaroniteCharacterButton", PaperDollFrame, "UIPanelButtonTemplate")
	button:SetWidth(80)
	button:SetHeight(22)
	button:SetText(L.BUTTON)
	button:SetMovable(true)
	button:RegisterForDrag("LeftButton")

	local pos = SaroniteDB.buttonPos
	if pos then
		button:SetPoint("TOPLEFT", PaperDollFrame, "TOPLEFT", pos.x, pos.y)
	elseif CharacterMainHandSlot then
		-- Bottom left, in the free space next to the weapon slots (mirrors
		-- where Pawn puts its button on the right).
		button:SetPoint("BOTTOMRIGHT", CharacterMainHandSlot, "BOTTOMLEFT", -12, 0)
	else
		button:SetPoint("BOTTOMLEFT", PaperDollFrame, "BOTTOMLEFT", 24, 86)
	end

	button:SetScript("OnClick", UI.Show)
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
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L.TITLE)
		GameTooltip:AddLine(L.BUTTON_TOOLTIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.Init()
	CreateCharacterButton()
end
