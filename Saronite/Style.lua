-- Minimal dark UI kit: flat panels with 1px borders, an accent color and a
-- custom font. No external libraries.
local _, ns = ...

local Style = {}
ns.Style = Style

local WHITE = "Interface\\Buttons\\WHITE8X8"

Style.color = {
	bg = { 0.04, 0.04, 0.05, 0.86 },
	panel = { 0.08, 0.08, 0.09, 0.90 },
	border = { 0, 0, 0, 1 },
	line = { 0.20, 0.20, 0.22, 1 },
	hover = { 0.16, 0.16, 0.18, 0.95 },
	accent = { 0.36, 0.78, 0.69, 1 }, -- saronite green
	text = { 0.92, 0.92, 0.92, 1 },
	dim = { 0.55, 0.55, 0.58, 1 },
	good = { 0.40, 0.85, 0.45, 1 },
	warn = { 1.00, 0.70, 0.25, 1 },
}

-- PT Sans Narrow (SIL OFL, bundled, has Cyrillic); the client's default
-- font if it cannot be loaded.
local BUNDLED = "Interface\\AddOns\\Saronite\\Media\\Fonts\\PTSansNarrow-Bold.ttf"

local font

local function normalize(path)
	return string.lower(string.gsub(path or "", "/", "\\"))
end

-- A font file works if the font string accepts it and text rendered with it
-- has a width. The probe always starts from the client's default font: a
-- font string without a font raises "Font not set" on SetText.
local probe
local function check(path)
	probe = probe or UIParent:CreateFontString(nil, "OVERLAY")
	probe:Hide()
	probe:SetFont(STANDARD_TEXT_FONT, 12)
	probe:SetFont(path, 12)
	if normalize(probe:GetFont()) ~= normalize(path) then return false end
	probe:SetText("Saronite 123")
	local width = probe:GetStringWidth() or 0
	probe:SetText("")
	return width > 0
end

local function usable(path)
	local ok, result = pcall(check, path)
	return ok and result
end

function Style.Font()
	if not font then
		font = usable(BUNDLED) and BUNDLED or STANDARD_TEXT_FONT
	end
	return font
end

function Style.Backdrop(frame, color)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(unpack(color or Style.color.bg))
	frame:SetBackdropBorderColor(unpack(Style.color.border))
end

function Style.Text(parent, size, kind, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(Style.Font(kind), size or 12)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	fs:SetTextColor(unpack(Style.color.text))
	fs:SetJustifyH("LEFT")
	return fs
end

function Style.Line(parent, width, height)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetTexture(WHITE)
	t:SetVertexColor(unpack(Style.color.line))
	t:SetWidth(width or 1)
	t:SetHeight(height or 1)
	return t
end

-- Window: a movable, Escape-closable panel with a title row.
function Style.Window(name, width, height, title)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetWidth(width)
	f:SetHeight(height)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	Style.Backdrop(f)
	f:Hide()
	table.insert(UISpecialFrames, name)

	local brand = Style.Text(f, 13, "latin")
	brand:SetPoint("TOPLEFT", 10, -9)
	brand:SetText("SARONITE")
	brand:SetTextColor(unpack(Style.color.accent))
	f.brand = brand

	local caption = Style.Text(f, 12)
	caption:SetPoint("LEFT", brand, "RIGHT", 8, 0)
	caption:SetTextColor(unpack(Style.color.dim))
	caption:SetText(title or "")
	f.caption = caption

	local close = Style.Button(f, "×", 20, 18, "latin")
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function() f:Hide() end)

	local rule = Style.Line(f, 1, 1)
	rule:SetPoint("TOPLEFT", 1, -30)
	rule:SetPoint("TOPRIGHT", -1, -30)
	return f
end

function Style.Button(parent, label, width, height, kind)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(width or 100)
	b:SetHeight(height or 22)
	Style.Backdrop(b, Style.color.panel)

	local text = Style.Text(b, 12, kind)
	text:SetPoint("CENTER", 0, 0)
	text:SetJustifyH("CENTER")
	text:SetText(label)
	b.label = text

	b:SetScript("OnEnter", function(self)
		self:SetBackdropColor(unpack(Style.color.hover))
		self:SetBackdropBorderColor(unpack(Style.color.accent))
	end)
	b:SetScript("OnLeave", function(self)
		self:SetBackdropColor(unpack(Style.color.panel))
		self:SetBackdropBorderColor(unpack(Style.color.border))
	end)
	return b
end

-- Icon with a 1px border; SetBorder colors it.
function Style.Icon(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(size)
	f:SetHeight(size)
	Style.Backdrop(f, Style.color.panel)

	local tex = f:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", 1, -1)
	tex:SetPoint("BOTTOMRIGHT", -1, 1)
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- crop the default icon border
	f.texture = tex

	function f:SetBorder(r, g, b)
		self:SetBackdropBorderColor(r, g, b, 1)
	end
	return f
end

-- Scrollable multi-line edit box inside a panel.
function Style.EditArea(parent)
	local holder = CreateFrame("Frame", nil, parent)
	Style.Backdrop(holder, Style.color.panel)

	local scroll = CreateFrame("ScrollFrame", nil, holder)
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -6, 6)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(0)
	edit:SetFont(Style.Font("latin"), 12)
	edit:SetTextColor(unpack(Style.color.text))
	edit:SetWidth(400)
	scroll:SetScrollChild(edit)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, edit:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 20)))
	end)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() edit:SetFocus() end)
	holder:SetScript("OnSizeChanged", function(self, w)
		edit:SetWidth(math.max(50, (w or self:GetWidth()) - 12))
	end)

	holder.edit = edit
	return holder
end

function Style.QualityColor(quality)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

-- Corner grip: drag to scale the window as a whole (the layout stays
-- intact). The scale is saved per window key.
function Style.ScaleGrip(frame, key, default)
	SaroniteDB.scale = SaroniteDB.scale or {}
	frame:SetScale(SaroniteDB.scale[key] or default or 1)

	local grip = CreateFrame("Button", nil, frame)
	grip:SetWidth(16)
	grip:SetHeight(16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

	local absLeft, absTop
	local function pin()
		-- keep the top-left corner where it is on screen while scaling
		local eff = frame:GetEffectiveScale()
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", absLeft / eff, absTop / eff)
	end

	grip:SetScript("OnMouseDown", function()
		local eff = frame:GetEffectiveScale()
		absLeft, absTop = frame:GetLeft() * eff, frame:GetTop() * eff
		grip:SetScript("OnUpdate", function()
			local x = GetCursorPosition()
			local width = math.max(50, x - absLeft)
			local scale = width / frame:GetWidth() / UIParent:GetEffectiveScale()
			frame:SetScale(math.min(2, math.max(0.7, scale)))
			pin()
		end)
	end)
	grip:SetScript("OnMouseUp", function()
		grip:SetScript("OnUpdate", nil)
		SaroniteDB.scale[key] = frame:GetScale()
	end)
	return grip
end
