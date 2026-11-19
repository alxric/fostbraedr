-- Fostbraedr: Quest items tab. Lists the quest items in your bags, grouped by
-- whether a quest in your log still needs them. Click a row to pick the item up
-- (then drop it outside your bags to delete it, as usual).
local ADDON, ns = ...

local ROW_HEIGHT = 26

local GROUPS = {
    delete = { title = "Probably safe to delete", color = "bad" },
    check  = { title = "Check first",             color = "accent" },
    keep   = { title = "Keep: a quest in your log uses it", color = "good" },
}

-- Display rows: a heading per non-empty group, then its items.
function ns.BuildQuestItemRows(scan)
    local rows, last = {}, nil
    for _, item in ipairs(scan.items) do
        if item.group ~= last then
            last = item.group
            rows[#rows + 1] = { heading = true, group = item.group, count = scan.counts[item.group] }
        end
        rows[#rows + 1] = { item = item, odd = #rows % 2 == 1 }
    end
    return rows
end

local function Row_OnEnter(row)
    local item = row.data and row.data.item
    if not item then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetBagItem then
        GameTooltip:SetBagItem(item.bag, item.slot)
    elseif item.link then
        GameTooltip:SetHyperlink(item.link)
    end
    local c = ns.Theme.colors[GROUPS[item.group].color]
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Fostbraedr: " .. item.reason, c[1], c[2], c[3], true)
    GameTooltip:AddLine("Click to pick it up; drop it outside your bags to delete it.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

-- Pick the item up, if it's still where the scan found it.
local function Row_OnClick(row)
    local item = row.data and row.data.item
    local C = C_Container
    if not (item and C and C.PickupContainerItem) then return end
    local info = C.GetContainerItemInfo(item.bag, item.slot)
    if not info or info.itemID ~= item.itemID then
        ns.Print("That item has moved; the list is refreshed.")
        ns.Fire("QUEST_ITEMS_STALE")
        return
    end
    ClearCursor()
    C.PickupContainerItem(item.bag, item.slot)
end

local function PaintRow(row)
    local alpha = row.data and not row.data.heading and (row.hover and 0.07 or (row.data.odd and 0.025 or 0)) or 0
    row.bg:SetColorTexture(1, 1, 1, alpha)
end

local function InitRow(row, data)
    local T = ns.Theme
    if not row.text then
        row:EnableMouse(true)
        row.bg = T.Fill(row, { 0, 0, 0, 0 })
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text = T.Text(row, 12, T.colors.text)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetWidth(200)
        row.text:SetWordWrap(false)
        row.reason = T.Text(row, 11, T.colors.muted)
        row.reason:SetPoint("LEFT", row.text, "RIGHT", 8, 0)
        row.reason:SetPoint("RIGHT", -6, 0)
        row.reason:SetWordWrap(false)
        row.heading = T.Text(row, 10, T.colors.accent)
        row.heading:SetPoint("BOTTOMLEFT", 2, 4)
        row:SetScript("OnEnter", function(self) self.hover = true PaintRow(self) Row_OnEnter(self) end)
        row:SetScript("OnLeave", function(self) self.hover = nil PaintRow(self) GameTooltip:Hide() end)
        row:SetScript("OnClick", Row_OnClick)
    end
    row.data = data
    if data.heading then
        local g = GROUPS[data.group]
        row.heading:SetText(("%s (%d)"):format(g.title:upper(), data.count))
        row.heading:SetTextColor(unpack(T.colors[g.color]))
        row.heading:Show()
        row.icon:Hide()
        row.text:Hide()
        row.reason:Hide()
    else
        local item = data.item
        row.heading:Hide()
        row.icon:Show()
        row.text:Show()
        row.reason:Show()
        row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local name = item.link or item.name or ("item " .. item.itemID)
        row.text:SetText(item.count > 1 and (name .. T.Muted(" x" .. item.count)) or name)
        row.reason:SetText(item.reason)
    end
    PaintRow(row)
end

function ns.BuildQuestItemsTab(panel)
    local T = ns.Theme

    local summary = T.Text(panel, 13, T.colors.text)
    summary:SetPoint("TOPLEFT", 0, -2)
    summary:SetPoint("RIGHT", panel, "RIGHT", -100, 0)
    local hint = T.Text(panel, 11, T.colors.muted)
    hint:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -4)
    hint:SetPoint("RIGHT", panel, "RIGHT")
    hint:SetText("A best guess from your quest log. Nothing is deleted for you: click a row to pick the item up.")

    local refresh = T.Button(panel, "Refresh", 94, 24)
    refresh:SetPoint("TOPRIGHT", 0, 0)

    -- "Button" rows so OnClick works.
    local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 0, -42)
    scrollBox:SetPoint("BOTTOMRIGHT", -14, 0)
    local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    local empty = T.Text(panel, 13, T.colors.muted)
    empty:SetPoint("CENTER", scrollBox, "CENTER")

    function panel:Refresh()
        local scan = ns.QuestItems.Scan()
        local rows = ns.BuildQuestItemRows(scan)
        scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
        local c = scan.counts
        if scan.problem then
            summary:SetText(T.Hex("ff6060", "Can't check quest items: " .. scan.problem .. "."))
        elseif #scan.items == 0 then
            summary:SetText("No quest items in your bags.")
        else
            summary:SetText(("%d quest items: %s, %s, %s"):format(#scan.items,
                T.Hex("ff6060", c.delete .. " probably safe to delete"),
                T.Accent(c.check .. " to check"),
                T.Hex("5ad973", c.keep .. " to keep")))
        end
        empty:SetText(#scan.items == 0 and not scan.problem and "Your bags are free of quest items." or "")
        empty:SetShown(#scan.items == 0)
    end
    refresh:SetScript("OnClick", function() panel:Refresh() end)

    -- Bags and the quest log change a lot while questing: refresh at most twice a second.
    local pending = false
    local function RefreshSoon()
        if pending or not panel:IsVisible() then return end
        pending = true
        C_Timer.After(0.5, function()
            pending = false
            if panel:IsVisible() then panel:Refresh() end
        end)
    end
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "QUEST_REMOVED", "GET_ITEM_INFO_RECEIVED", "PLAYER_LEVEL_UP" }) do
        ns.OnOptional(event, RefreshSoon)
    end
    ns.Listen("QUEST_ITEMS_STALE", RefreshSoon)
end
