-- Fostbraedr: Gear tab. Druids: one weapon/trinket set in cat form, another in
-- every other form. Other classes see a short note instead.
local ADDON, ns = ...

local COLUMN_W = 290

function ns.BuildGearTab(panel)
    local T = ns.Theme
    local G = ns.Gear

    local notDruid = T.Text(panel, 13, T.colors.muted)
    notDruid:SetPoint("CENTER")
    notDruid:SetText("Form swaps are for druids: this character has no forms to swap on.")

    local body = CreateFrame("Frame", nil, panel)
    body:SetAllPoints()

    local function Place(region, y, x) region:SetPoint("TOPLEFT", body, "TOPLEFT", x or 0, y) end
    local function Hint(text, y, x, width)
        local fs = T.Text(body, 11, T.colors.muted)
        Place(fs, y, x)
        if width then fs:SetWidth(width) else fs:SetPoint("RIGHT", body, "RIGHT") end
        fs:SetText(text)
        return fs
    end
    local function Section(title, y, x, width)
        local h = T.Section(body, title)
        Place(h, y, x)
        if width then h.line:SetWidth(width) else h.line:SetPoint("RIGHT", body, "RIGHT") end
        return h
    end

    Section("Swap when you change form (out of combat only)", 0)
    Hint("One set in cat form, the other in every other form. The game doesn't let addons change gear in combat:\na form change during a fight swaps your gear when the fight ends.", -22)

    local toggles = {}
    local function Toggle(label, y, key)
        local t = T.Toggle(body, label, function(v)
            local d = G.Data(true)
            d[key] = v
            if v then G.ApplyWithRetries("switched on") end
            panel:Refresh()
        end)
        Place(t, y)
        t.key = key
        toggles[#toggles + 1] = t
    end
    Toggle("Swap weapons (main and off hand)", -52, "weapons")
    Toggle("Swap trinkets", -76, "trinkets")

    -- One column per set: its items, then Save / Wear now.
    local columns = {}
    for i, setKey in ipairs(G.SETS) do
        local x = (i - 1) * (COLUMN_W + 20)
        local col = { setKey = setKey, lines = {} }
        col.title = Section(G.SET_TITLES[setKey], -108, x, COLUMN_W)
        for j, s in ipairs(G.SLOTS) do
            local label = T.Text(body, 11, T.colors.muted)
            Place(label, -128 - (j - 1) * 22, x)
            label:SetWidth(70)
            label:SetText(s.label)
            local item = T.Text(body, 12, T.colors.text)
            item:SetPoint("LEFT", label, "RIGHT", 4, 0)
            item:SetWidth(COLUMN_W - 74)
            item:SetWordWrap(false)
            col.lines[j] = item
        end
        local save = T.Button(body, "Save what I'm wearing", 150, 24)
        Place(save, -222, x)
        save:SetScript("OnClick", function()
            G.SaveCurrent(setKey)
            ns.Print("Saved what you're wearing as your %s set.", G.SET_TITLES[setKey]:lower())
        end)
        local wear = T.Button(body, "Wear now", 90, 24)
        wear:SetPoint("LEFT", save, "RIGHT", 6, 0)
        wear:SetScript("OnClick", function() G.WearNow(setKey) end)
        col.wear = wear
        columns[i] = col
    end

    local current = T.Text(body, 12, T.colors.text)
    Place(current, -270)
    current:SetPoint("RIGHT", body, "RIGHT")
    local status = Hint("", -290)
    status:SetTextColor(unpack(T.colors.accent))

    Hint("\"Wear now\" puts a set on straight away; it stays on until you next change form.", -326)
    Hint("Type /fost geartest to see what happened on each swap (how long it took, the global cooldown).", -342)

    local function ItemText(entry)
        if not entry then return T.Muted("-") end
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.id)
        return (icon and ("|T" .. icon .. ":14|t ") or "") .. (entry.link or ("item " .. entry.id))
    end

    function panel:Refresh()
        local druid = G.IsDruid()
        notDruid:SetShown(not druid)
        body:SetShown(druid)
        if not druid then return end
        local d = G.Data()
        for _, t in ipairs(toggles) do t:SetChecked(d and d[t.key]) end
        for _, col in ipairs(columns) do
            local set = d and d.sets[col.setKey] or {}
            for j, s in ipairs(G.SLOTS) do col.lines[j]:SetText(ItemText(set[s.slot])) end
            col.wear:SetEnabled(d and next(set) ~= nil or false)
        end
        local wanted = G.WantedSet()
        current:SetText("You're in " .. (wanted == "cat" and "cat form" or wanted and "another form (not cat)" or "a form we can't read right now")
            .. ((d and (d.weapons or d.trinkets)) and "." or T.Muted(" (swapping is off)")))
        status:SetText(G.status or "")
    end

    ns.Listen("GEAR_CHANGED", function() if panel:IsVisible() then panel:Refresh() end end)
    ns.OnOptional("UPDATE_SHAPESHIFT_FORM", function() if panel:IsVisible() then panel:Refresh() end end)
end
