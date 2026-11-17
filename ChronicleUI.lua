-- Fostbraedr: Chronicle tab (timeline, newest first, plus manual entries).
local ADDON, ns = ...

local ROW_HEIGHT = 24
local MAX_LEVEL = 60

local function WithText(e)
    if not e.with or #e.with == 0 then return "" end
    local names = {}
    for i, n in ipairs(e.with) do names[i] = ns.People.ShortName(n) end
    return " |cff5ad973(together with " .. table.concat(names, ", ") .. ")|r"
end

local function InZone(e)
    return e.zone and (" in " .. e.zone) or ""
end

-- Builds display rows (newest first) with running totals worked out oldest first.
function ns.BuildChronicleRows()
    local deaths, firstMax = {}, nil
    local rows = {}
    for _, e in ipairs(ns.SortedEntries()) do
        local who = ns.People.DisplayName(e.author)
        local text
        if e.kind == "level" then
            text = ("%s reached level %s%s"):format(who, tostring(e.level or "?"), InZone(e))
            if e.level == MAX_LEVEL and not firstMax then
                firstMax = e.id
                text = text .. " |cffffc742- first brother to " .. MAX_LEVEL .. "!|r"
            end
        elseif e.kind == "death" then
            local dk = ns.People.GroupKey(e.author) -- deaths count per person, all characters
            deaths[dk] = (deaths[dk] or 0) + 1
            text = ("|cffff6060%s died|r%s (level %s), death #%d%s"):format(
                who, InZone(e), tostring(e.level or "?"), deaths[dk], WithText(e))
        elseif e.kind == "boss" then
            text = ("%s defeated |cffffc742%s|r%s%s"):format(who, e.name or "a boss", InZone(e), WithText(e))
        elseif e.kind == "loot" then
            text = ("%s looted %s%s"):format(who, e.link or "something", WithText(e))
        elseif e.kind == "manual" then
            text = ("%s: |cffffffff%s|r"):format(who, e.text or "")
        end
        if text then
            rows[#rows + 1] = { entry = e, text = text }
        end
    end
    -- newest first
    for i = 1, math.floor(#rows / 2) do
        rows[i], rows[#rows - i + 1] = rows[#rows - i + 1], rows[i]
    end
    for i, r in ipairs(rows) do r.odd = i % 2 == 1 end
    return rows
end

local function Row_OnEnter(row)
    local d = row.data
    if not d then return end
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
    if d.entry.kind == "loot" and d.entry.link then
        GameTooltip:SetHyperlink(d.entry.link)
    else
        GameTooltip:SetText(date("%Y-%m-%d %H:%M", d.entry.time), 1, 1, 1)
        GameTooltip:AddLine(d.text, nil, nil, nil, true)
        GameTooltip:AddLine(d.entry.author, 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local KIND_ICONS = {
    level  = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
    death  = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    boss   = "Interface\\Icons\\INV_Sword_04",
    loot   = "Interface\\Icons\\INV_Misc_Bag_10",
    manual = "Interface\\Icons\\INV_Misc_Note_01",
}

local function PaintRow(row)
    local alpha = row.hover and 0.07 or (row.odd and 0.025 or 0)
    row.bg:SetColorTexture(1, 1, 1, alpha)
end

local function InitRow(row, data)
    local T = ns.Theme
    if not row.when then
        row:EnableMouse(true)
        row.bg = T.Fill(row, { 0, 0, 0, 0 })
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 6, 0)
        row.when = T.Text(row, 11, T.colors.muted)
        row.when:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.when:SetWidth(84)
        row.text = T.Text(row, 12, T.colors.text)
        row.text:SetPoint("LEFT", row.when, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", -6, 0)
        row.text:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) self.hover = true PaintRow(self) Row_OnEnter(self) end)
        row:SetScript("OnLeave", function(self) self.hover = nil PaintRow(self) GameTooltip:Hide() end)
    end
    row.data = data
    row.odd = data.odd
    PaintRow(row)
    local e = data.entry
    local icon = KIND_ICONS[e.kind]
    if e.kind == "loot" and e.link and C_Item and C_Item.GetItemIconByID then
        icon = C_Item.GetItemIconByID(e.link) or icon
    end
    row.icon:SetTexture(icon)
    if e.kind == "death" then row.icon:SetTexCoord(0, 1, 0, 1) else row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    row.when:SetText(date("%d %b  %H:%M", e.time))
    row.text:SetText(data.text)
end

function ns.BuildChronicleTab(panel)
    local T = ns.Theme
    -- Manual entry row.
    local input = T.Input(panel, "Write something for the chronicle... (Enter to add)")
    input:SetMaxLetters(200)
    input:SetPoint("TOPLEFT", 0, 0)
    input:SetPoint("TOPRIGHT", -100, 0)

    local add = T.Button(panel, "Add entry", 94, 24)
    add:SetPoint("LEFT", input, "RIGHT", 6, 0)

    local function Submit()
        local text = input:GetText():gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then return end
        local with = ns.BrothersInGroup()
        ns.AddEntry("manual", { text = text, zone = ns.Zone(), with = #with > 0 and with or nil })
        input:SetText("")
        input:ClearFocus()
    end
    add:SetScript("OnClick", Submit)
    input:SetScript("OnEnterPressed", Submit)

    -- Timeline list.
    local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 0, -34)
    scrollBox:SetPoint("BOTTOMRIGHT", -14, 0)

    local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Frame", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    local empty = T.Text(panel, 13, T.colors.muted)
    empty:SetPoint("CENTER", scrollBox, "CENTER")
    empty:SetText("Nothing in the chronicle yet. Go level, loot or die!")

    function panel:Refresh()
        local rows = ns.BuildChronicleRows()
        scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
        empty:SetShown(#rows == 0)
    end

    for _, msg in ipairs({ "ENTRY_ADDED", "PEOPLE_CHANGED" }) do
        ns.Listen(msg, function()
            if panel:IsVisible() then panel:Refresh() end
        end)
    end
end
