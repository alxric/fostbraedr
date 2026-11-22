-- Fostbraedr: Family tab (a card per character: who's online, where, doing what).
local ADDON, ns = ...

local MAX_CARDS = 8
local CARD_H, GAP = 88, 8 -- 4 rows of cards must fit in the window

local function ClassColor(classFile)
    if classFile then
        if C_ClassColor and C_ClassColor.GetClassColor then
            local c = C_ClassColor.GetClassColor(classFile)
            if c then return c.r, c.g, c.b end
        end
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if c then return c.r, c.g, c.b end
    end
    return unpack(ns.Theme.colors.text)
end

local function ClassName(classFile)
    return classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]
        or (classFile and (classFile:sub(1, 1) .. classFile:sub(2):lower())) or nil
end

function ns.TimeAgo(seconds)
    if seconds < 90 then return "just now" end
    if seconds < 3600 then return ("%d min ago"):format(seconds / 60) end
    if seconds < 86400 then return ("%d h ago"):format(seconds / 3600) end
    return ("%d days ago"):format(seconds / 86400)
end

local function CreateCard(panel)
    local T = ns.Theme
    local card = CreateFrame("Frame", nil, panel)
    card:SetHeight(CARD_H)
    T.Panel(card)
    card.dot = card:CreateTexture(nil, "ARTWORK")
    card.dot:SetSize(8, 8)
    card.dot:SetPoint("TOPLEFT", 12, -15)
    card.name = T.Text(card, 14)
    card.name:SetPoint("LEFT", card.dot, "RIGHT", 8, 0)
    card.seen = T.Text(card, 10, T.colors.muted)
    card.seen:SetPoint("TOPRIGHT", -10, -12)
    card.seen:SetJustifyH("RIGHT")
    card.info = T.Text(card, 11, T.colors.muted)
    card.info:SetPoint("TOPLEFT", 12, -30)
    card.info:SetPoint("RIGHT", -10, 0)
    card.info:SetWordWrap(false)
    card.xp = T.Text(card, 11, T.colors.muted)
    card.xp:SetPoint("TOPLEFT", card.info, "BOTTOMLEFT", 0, -3)
    card.xp:SetPoint("RIGHT", -10, 0)
    card.xp:SetWordWrap(false)
    card.activity = T.Text(card, 12, T.colors.text)
    card.activity:SetPoint("TOPLEFT", card.xp, "BOTTOMLEFT", 0, -3)
    card.activity:SetPoint("RIGHT", -80, 0)
    card.activity:SetWordWrap(false)
    card.status = T.Text(card, 11, T.colors.accent)
    card.status:SetPoint("TOPLEFT", card.activity, "BOTTOMLEFT", 0, -3)
    card.status:SetPoint("RIGHT", -80, 0)
    card.status:SetWordWrap(false)
    card.poke = T.Button(card, "Poke", 64, 22)
    card.poke:SetPoint("BOTTOMRIGHT", -10, 10)
    card.poke:SetScript("OnClick", function() if card.who then ns.Poke(card.who) end end)
    return card
end

function ns.BuildFamilyTab(panel)
    local T = ns.Theme

    -- Your custom status.
    local input = T.Input(panel, "Your status for the family (Enter to set, empty to clear)")
    input:SetMaxLetters(80)
    input:SetPoint("TOPLEFT", 0, 0)
    input:SetPoint("TOPRIGHT", -100, 0)
    local set = T.Button(panel, "Set status", 94, 24)
    set:SetPoint("LEFT", input, "RIGHT", 6, 0)
    local function Submit()
        ns.SetMyStatus(input:GetText())
        input:ClearFocus()
    end
    set:SetScript("OnClick", Submit)
    input:SetScript("OnEnterPressed", Submit)

    local empty = T.Text(panel, 13, T.colors.muted)
    empty:SetPoint("CENTER")
    empty:SetJustifyH("CENTER")
    empty:SetText("No brothers yet.\n\nTarget one and type |cffffc742/fost brother add|r")

    local more = T.Text(panel, 11, T.colors.muted)
    more:SetPoint("BOTTOMLEFT", 0, 0)

    local cards = {}
    local function Layout(n)
        local w = (panel:GetWidth() - GAP) / 2
        for i = 1, n do
            local card = cards[i] or CreateCard(panel)
            cards[i] = card
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            card:ClearAllPoints()
            if w > 0 then card:SetWidth(w) end
            card:SetPoint("TOPLEFT", col * (w + GAP), -36 - row * (CARD_H + GAP))
            card:Show()
        end
        for i = n + 1, #cards do cards[i]:Hide() end
    end

    local function Fill(card, name, isMe)
        local T = ns.Theme
        local peer, st, online
        if isMe then
            st, online = ns.MyStatus(), true
        else
            peer = ns.db.peers[name]
            st = peer or {}
            online = ns.Sync.IsOnline(name)
        end
        card.who = not isMe and name or nil
        local c = online and T.colors.good or T.colors.muted
        card.dot:SetColorTexture(c[1], c[2], c[3], 1)
        local person = isMe and ns.People.MyName() or ns.People.ShortName(name)
        local first = ns.FirstName(name)
        local on = (person and person:lower() ~= first:lower()) and T.Muted("  on " .. first) or ""
        card.name:SetText((person or first) .. on .. (isMe and T.Muted("  (you)") or ""))
        card.name:SetTextColor(ClassColor(st.class))
        local parts = {}
        if st.level then parts[#parts + 1] = "Level " .. st.level .. (ClassName(st.class) and (" " .. ClassName(st.class)) or "") end
        if st.zone then parts[#parts + 1] = st.zone end
        card.info:SetText(#parts > 0 and table.concat(parts, "  \194\183  ") or "Never seen with the addon")
        card.xp:SetText(ns.XPText(st.level, st.xpLeft, st.tiLeft, st.tiN))
        if isMe or online then
            card.activity:SetText(st.activity or "")
            card.seen:SetText(isMe and "" or "online")
            card.seen:SetTextColor(unpack(T.colors.good))
        else
            card.activity:SetText(T.Muted("Offline"))
            card.seen:SetText(peer and peer.lastSeen and ("last seen " .. ns.TimeAgo(GetServerTime() - peer.lastSeen)) or "")
            card.seen:SetTextColor(unpack(T.colors.muted))
        end
        card.status:SetText(st.status and ('"' .. st.status .. '"') or "")
        card.poke:SetShown(not isMe)
    end

    -- The character to show for a brother: the one he's online on, else the one
    -- we saw most recently.
    local function PickChar(person)
        local best, bestSeen
        for _, c in ipairs(person.chars) do
            if ns.Sync.IsOnline(c) then return c, true end
            local p = ns.db.peers[c]
            local seen = p and p.lastSeen or 0
            if not best or seen > bestSeen then best, bestSeen = c, seen end
        end
        return best, false
    end

    function panel:Refresh()
        if not input:HasFocus() then input:SetText(ns.db.settings.status or "") end
        local list = {}
        for _, person in ipairs(ns.People.Brothers()) do
            local char, online = PickChar(person)
            list[#list + 1] = { char = char, online = online, name = person.name }
        end
        -- online brothers first, then by name
        table.sort(list, function(a, b)
            if a.online ~= b.online then return a.online end
            return a.name:lower() < b.name:lower()
        end)
        table.insert(list, 1, { char = ns.me, me = true })
        local n = math.min(#list, MAX_CARDS)
        Layout(n)
        for i = 1, n do Fill(cards[i], list[i].char, list[i].me) end
        empty:SetShown(#list <= 1)
        more:SetText(#list > MAX_CARDS and ("+%d more not shown"):format(#list - MAX_CARDS) or "")
    end

    local function RefreshIfVisible()
        if panel:IsVisible() then panel:Refresh() end
    end
    for _, msg in ipairs({ "PEER_STATUS", "PEER_ONLINE", "PEER_OFFLINE", "MY_STATUS", "BROTHERS_CHANGED", "PEOPLE_CHANGED" }) do
        ns.Listen(msg, RefreshIfVisible)
    end
    -- keep "last seen" and our own activity fresh while open
    local acc = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 15 then
            acc = 0
            panel:Refresh()
        end
    end)
end
