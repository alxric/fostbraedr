-- Fostbraedr: Rivalry tab (award cards + leaderboard, by period).
local ADDON, ns = ...

local PERIODS = {
    { label = "This week", range = function() return ns.WeekStart(0), nil end },
    { label = "Last week", range = function() return ns.WeekStart(1), ns.WeekStart(0) end },
    { label = "All time",  range = function() return nil, nil end },
}

local COLUMNS = {
    { title = "Name",    width = 90,  get = function(_, s) return s.name end, left = true },
    { title = "Lvl",     width = 30,  get = function(_, s) return s.level or "-" end },
    { title = "Deaths",  width = 48,  get = function(_, s) return s.deaths end },
    { title = "Quests",  width = 48,  get = function(_, s) return s.quests end },
    { title = "Gold",    width = 62,  get = function(_, s) return ns.ShortMoney(s.gold) end },
    { title = "Bosses",  width = 46,  get = function(_, s) return s.bosses end },
    { title = "Epics",   width = 40,  get = function(_, s) return s.loot end, tip = "Notable loot (epics and mounts)" },
    { title = "Luck",    width = 46,  get = function(_, s) return s.luck and ("%.0f"):format(s.luck) or "-" end,
      tip = "Average item roll (Need/Greed), at least 3 rolls" },
    { title = "Wins",    width = 40,  get = function(_, s) return s.rollWins end, tip = "Item rolls won" },
    { title = "Played",  width = 52,  get = function(_, s) return ns.ShortTime(s.minutes) end },
    { title = "Together", width = 60, get = function(_, s) return ns.ShortTime(s.together) end,
      tip = "Time played grouped with a brother" },
}

function ns.ShortMoney(copper)
    copper = copper or 0
    if copper >= 10000 then return math.floor(copper / 10000) .. "g" end
    if copper >= 100 then return math.floor(copper / 100) .. "s" end
    return copper .. "c"
end

function ns.ShortTime(minutes)
    minutes = minutes or 0
    if minutes < 60 then return minutes .. "m" end
    return ("%.1fh"):format(minutes / 60)
end

local function NamesText(winners, stats)
    local names = {}
    for i, key in ipairs(winners) do names[i] = stats[key].name end
    return table.concat(names, " & ")
end

local function TimeLeftText(seconds)
    local d, h = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
    if d > 0 then return ("%dd %dh"):format(d, h) end
    return ("%dh %dm"):format(h, math.floor(seconds % 3600 / 60))
end

function ns.BuildRivalryTab(panel)
    local T = ns.Theme
    local period = 1

    -- Period heading (left) and segmented period buttons (right).
    local heading = T.Text(panel, 14, T.colors.text)
    heading:SetPoint("TOPLEFT", 0, -1)
    local sub = T.Text(panel, 11, T.colors.muted)
    sub:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -3)

    local buttons = {}
    for i = #PERIODS, 1, -1 do
        local b = T.Button(panel, PERIODS[i].label, 84, 24)
        if i == #PERIODS then
            b:SetPoint("TOPRIGHT", 0, 0)
        else
            b:SetPoint("RIGHT", buttons[i + 1], "LEFT", -4, 0)
        end
        b:SetScript("OnClick", function()
            period = i
            panel:Refresh()
        end)
        buttons[i] = b
    end

    -- Award cards: 3 per row, sized to the panel width.
    local cards = {}
    local GAP, CARD_H, CARDS_TOP = 8, 54, -44
    for i, a in ipairs(ns.AWARDS) do
        local card = CreateFrame("Frame", nil, panel)
        card:SetHeight(CARD_H)
        T.Panel(card)
        card.icon = card:CreateTexture(nil, "ARTWORK")
        card.icon:SetSize(30, 30)
        card.icon:SetPoint("LEFT", 12, 0)
        card.icon:SetTexture(a.icon)
        card.title = T.Text(card, 10, T.colors.accent)
        card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, 1)
        card.title:SetText(a.title:upper())
        card.winner = T.Text(card, 13, T.colors.text)
        card.winner:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
        card.winner:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        card.winner:SetWordWrap(false)
        card.value = T.Text(card, 10, T.colors.muted)
        card.value:SetPoint("TOPLEFT", card.winner, "BOTTOMLEFT", 0, -2)
        card.value:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        card.value:SetWordWrap(false)
        card.award = a
        cards[i] = card
    end
    local function LayoutCards()
        local w = (panel:GetWidth() - 2 * GAP) / 3
        if w <= 0 then return end
        for i, card in ipairs(cards) do
            local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
            card:ClearAllPoints()
            card:SetWidth(w)
            card:SetPoint("TOPLEFT", col * (w + GAP), CARDS_TOP - row * (CARD_H + GAP))
        end
    end
    panel:SetScript("OnSizeChanged", LayoutCards)

    -- Leaderboard.
    local tableTop = CARDS_TOP - 2 * (CARD_H + GAP) - 10
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 0, tableTop)
    header:SetPoint("RIGHT", panel, "RIGHT")
    header:SetHeight(22)
    local line = T.Divider(header)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")

    local function LayoutCells(parent, size, color)
        local cells, x = {}, 6
        for i, c in ipairs(COLUMNS) do
            local fs = T.Text(parent, size, color)
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(c.width)
            fs:SetJustifyH(c.left and "LEFT" or "RIGHT")
            fs:SetWordWrap(false)
            cells[i] = fs
            x = x + c.width + 2
        end
        return cells
    end

    local headerCells = LayoutCells(header, 10, T.colors.muted)
    for i, c in ipairs(COLUMNS) do
        headerCells[i]:SetText(c.title:upper())
        if c.tip then
            local hit = CreateFrame("Frame", nil, header)
            hit:SetAllPoints(headerCells[i])
            hit:EnableMouse(true)
            hit:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(c.tip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

    local ROW_H = 24
    local rows = {}
    local function GetRow(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, panel)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -(i - 1) * ROW_H - 2)
        r:SetPoint("RIGHT", header, "RIGHT")
        local base = i % 2 == 0 and 0.025 or 0
        r.bg = T.Fill(r, { 1, 1, 1, base })
        r:EnableMouse(true)
        r:SetScript("OnEnter", function() r.bg:SetColorTexture(1, 1, 1, 0.07) end)
        r:SetScript("OnLeave", function() r.bg:SetColorTexture(1, 1, 1, base) end)
        r.cells = LayoutCells(r, 12, T.colors.text)
        rows[i] = r
        return r
    end

    function panel:Refresh()
        LayoutCards()
        for i, b in ipairs(buttons) do b:SetSelected(i == period) end
        local from, to = PERIODS[period].range()
        if period == 1 then
            heading:SetText("This week")
            sub:SetText(("Since %s, resets in %s"):format(date("%a %d %b %H:%M", from),
                TimeLeftText(ns.WeekStart(-1) - GetServerTime())))
        elseif period == 2 then
            heading:SetText("Last week")
            sub:SetText(("%s - %s"):format(date("%d %b", from), date("%d %b", to)))
        else
            heading:SetText("All time")
            sub:SetText("Everything in the chronicle")
        end

        local stats, authors = ns.ComputeRivalry(from, to)
        local awards = ns.ComputeAwards(stats)
        for _, card in ipairs(cards) do
            local res = awards[card.award.key]
            if #res.winners > 0 then
                card.winner:SetText(NamesText(res.winners, stats))
                card.winner:SetTextColor(unpack(T.colors.text))
                card.value:SetText(card.award.fmt(res.value))
                card.icon:SetDesaturated(false)
                card.icon:SetAlpha(1)
            else
                card.winner:SetText("Nobody yet")
                card.winner:SetTextColor(unpack(T.colors.muted))
                card.value:SetText("")
                card.icon:SetDesaturated(true)
                card.icon:SetAlpha(0.5)
            end
        end

        for i, author in ipairs(authors) do
            local r = GetRow(i)
            local s = stats[author]
            for c, col in ipairs(COLUMNS) do
                r.cells[c]:SetText(tostring(col.get(author, s)))
            end
            local c = s.isMe and T.colors.accent or T.colors.text
            r.cells[1]:SetTextColor(unpack(c))
            r:Show()
        end
        for i = #authors + 1, #rows do rows[i]:Hide() end
    end

    for _, msg in ipairs({ "ENTRY_ADDED", "PEOPLE_CHANGED", "BROTHERS_CHANGED" }) do
        ns.Listen(msg, function()
            if panel:IsVisible() then panel:Refresh() end
        end)
    end
end
