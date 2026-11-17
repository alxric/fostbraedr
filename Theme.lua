-- Fostbraedr: flat, dark UI theme. Small helpers instead of Blizzard templates.
local ADDON, ns = ...

local T = {}
ns.Theme = T

T.colors = {
    bg       = { 0.055, 0.058, 0.066, 0.96 },  -- window
    sidebar  = { 0.035, 0.037, 0.043, 0.98 },
    panel    = { 1, 1, 1, 0.035 },            -- cards, inputs
    panelHi  = { 1, 1, 1, 0.07 },             -- hover
    border   = { 1, 1, 1, 0.09 },
    accent   = { 1.00, 0.78, 0.26, 1 },       -- gold
    text     = { 0.92, 0.92, 0.93, 1 },
    muted    = { 0.55, 0.56, 0.60, 1 },
    good     = { 0.35, 0.85, 0.45, 1 },
    bad      = { 1.00, 0.38, 0.38, 1 },
}
T.accentHex = "ffc742"
T.mutedHex = "8c8f99"

function T.Hex(hex, text) return "|cff" .. hex .. text .. "|r" end
function T.Accent(text) return T.Hex(T.accentHex, text) end
function T.Muted(text) return T.Hex(T.mutedHex, text) end

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Solid fill covering the frame.
function T.Fill(frame, color, layer)
    local tex = frame:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(unpack(color))
    return tex
end

-- 1px border made of four textures (pixel-snapped where the client supports it).
function T.Border(frame, color)
    color = color or T.colors.border
    local edges = {}
    local function Edge(p1, p2, horizontal)
        local tex = frame:CreateTexture(nil, "BORDER")
        tex:SetTexture(WHITE)
        tex:SetVertexColor(unpack(color))
        tex:SetPoint(p1)
        tex:SetPoint(p2)
        if PixelUtil then
            if horizontal then PixelUtil.SetHeight(tex, 1) else PixelUtil.SetWidth(tex, 1) end
        else
            if horizontal then tex:SetHeight(1) else tex:SetWidth(1) end
        end
        edges[#edges + 1] = tex
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)
    function frame:SetBorderColor(r, g, b, a)
        for _, e in ipairs(edges) do e:SetVertexColor(r, g, b, a or 1) end
    end
    return edges
end

-- Panel = fill + border.
function T.Panel(frame, fill, border)
    frame.bg = T.Fill(frame, fill or T.colors.panel)
    T.Border(frame, border)
    return frame
end

function T.Text(parent, size, color, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size or 12, flags or "")
    fs:SetTextColor(unpack(color or T.colors.text))
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.6)
    fs:SetJustifyH("LEFT")
    return fs
end

-- Flat button. Use :SetSelected(bool) for toggle groups.
function T.Button(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 80, height or 22)
    T.Panel(b)
    b.label = T.Text(b, 11)
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetText(label or "")
    function b:SetText(t) self.label:SetText(t) end
    local function Paint(self)
        local c = T.colors
        if self.selected then
            self.bg:SetColorTexture(c.accent[1], c.accent[2], c.accent[3], 0.16)
            self:SetBorderColor(c.accent[1], c.accent[2], c.accent[3], 0.7)
            self.label:SetTextColor(unpack(c.accent))
        elseif self.hover and self:IsEnabled() then
            self.bg:SetColorTexture(unpack(c.panelHi))
            self:SetBorderColor(c.accent[1], c.accent[2], c.accent[3], 0.45)
            self.label:SetTextColor(unpack(c.text))
        else
            self.bg:SetColorTexture(unpack(c.panel))
            self:SetBorderColor(unpack(c.border))
            self.label:SetTextColor(unpack(self:IsEnabled() and c.text or c.muted))
        end
    end
    b.Paint = Paint
    function b:SetSelected(v) self.selected = v and true or nil Paint(self) end
    b:SetScript("OnEnter", function(self) self.hover = true Paint(self) end)
    b:SetScript("OnLeave", function(self) self.hover = nil Paint(self) end)
    b:HookScript("OnEnable", Paint)
    b:HookScript("OnDisable", Paint)
    Paint(b)
    return b
end

-- Flat single-line input with a placeholder.
function T.Input(parent, placeholder)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetAutoFocus(false)
    box:SetHeight(24)
    box:SetFont(STANDARD_TEXT_FONT, 12, "")
    box:SetTextColor(unpack(T.colors.text))
    box:SetTextInsets(8, 8, 0, 0)
    T.Panel(box)
    local ph = T.Text(box, 12, T.colors.muted)
    ph:SetPoint("LEFT", 8, 0)
    ph:SetText(placeholder or "")
    local function Update(self)
        ph:SetShown(self:GetText() == "" and not self:HasFocus())
        local a = T.colors.accent
        if self:HasFocus() then self:SetBorderColor(a[1], a[2], a[3], 0.6) else self:SetBorderColor(unpack(T.colors.border)) end
    end
    box:SetScript("OnEditFocusGained", Update)
    box:SetScript("OnEditFocusLost", Update)
    box:SetScript("OnTextChanged", Update)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Update(box)
    return box
end

-- Thin horizontal divider.
function T.Divider(parent)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetColorTexture(unpack(T.colors.border))
    tex:SetHeight(1)
    return tex
end

-- Checkbox-style toggle with a label. onChange(newValue) is called on click;
-- use :SetChecked(bool) to update it from settings.
function T.Toggle(parent, label, onChange)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    local box = CreateFrame("Frame", nil, b)
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 0, 0)
    T.Panel(box)
    local mark = box:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 4, -4)
    mark:SetPoint("BOTTOMRIGHT", -4, 4)
    mark:SetColorTexture(unpack(T.colors.accent))
    b.label = T.Text(b, 12, T.colors.text)
    b.label:SetPoint("LEFT", box, "RIGHT", 10, 0)
    b.label:SetText(label)
    b:SetWidth(26 + math.max(40, (b.label:GetStringWidth() or 100)))
    local function Paint(self)
        local a = T.colors.accent
        mark:SetShown(self.checked)
        if self.hover then box:SetBorderColor(a[1], a[2], a[3], 0.6) else box:SetBorderColor(unpack(T.colors.border)) end
    end
    function b:SetChecked(v) self.checked = v and true or false Paint(self) end
    function b:GetChecked() return self.checked end
    b:SetScript("OnEnter", function(self) self.hover = true Paint(self) end)
    b:SetScript("OnLeave", function(self) self.hover = nil Paint(self) end)
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if onChange then onChange(self.checked) end
    end)
    b:SetChecked(false)
    return b
end

-- Small uppercase section heading with a divider underneath.
function T.Section(parent, title)
    local fs = T.Text(parent, 10, T.colors.accent)
    fs:SetText(title:upper())
    local line = T.Divider(parent)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
    fs.line = line
    return fs
end
