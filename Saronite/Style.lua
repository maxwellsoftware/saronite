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

-- Expressway (Typodermic) may not be redistributed, so it is only used when
-- present: dropped into Saronite/Media/Fonts or shipped by ElvUI. Its
-- Cyrillic coverage is not guaranteed, so localized text on ruRU clients
-- uses PT Sans Narrow (SIL OFL, bundled).
local EXPRESSWAY = {
	"Interface\\AddOns\\Saronite\\Media\\Fonts\\Expressway.ttf",
	"Interface\\AddOns\\ElvUI\\Media\\Fonts\\Expressway.ttf",
	"Interface\\AddOns\\ElvUI\\Core\\Media\\Fonts\\Expressway.ttf",
}
local BUNDLED = "Interface\\AddOns\\Saronite\\Media\\Fonts\\PTSansNarrow-Bold.ttf"

local fonts = {}

-- A font file works if text rendered with it has a width.
local function usable(path)
	local probe = UIParent:CreateFontString(nil, "OVERLAY")
	probe:SetFont(path, 12)
	probe:SetText("Saronite 123")
	local ok = probe:GetFont() ~= nil and (probe:GetStringWidth() or 0) > 0
	probe:SetText("")
	probe:Hide()
	return ok
end

local function resolve(kind)
	if fonts[kind] then return fonts[kind] end
	local latinOnly = kind == "latin" or GetLocale() ~= "ruRU"
	if latinOnly then
		for _, path in ipairs(EXPRESSWAY) do
			if usable(path) then
				fonts[kind] = path
				return path
			end
		end
	end
	fonts[kind] = usable(BUNDLED) and BUNDLED or STANDARD_TEXT_FONT
	return fonts[kind]
end

-- kind: "latin" for titles and numbers, "text" for localized text.
function Style.Font(kind)
	return resolve(kind or "text")
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
