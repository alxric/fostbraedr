-- Fostbraedr: Settings tab. Everything here is also available as a /fost command.
local ADDON, ns = ...

local QUALITIES = { 2, 3, 4, 5 } -- uncommon, rare, epic, legendary
local QUALITY_FALLBACK = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }

local function QualityLabel(q)
    local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or QUALITY_FALLBACK[q]
    local hex
    if C_Item and C_Item.GetItemQualityColor then
        local _, _, _, h = C_Item.GetItemQualityColor(q)
        hex = h
    end
    if not hex and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then hex = ITEM_QUALITY_COLORS[q].hex end
    if type(hex) == "string" then
        if not hex:find("^|c") then hex = "|c" .. hex end
        return hex .. name .. "|r"
    end
    return name
end

function ns.BuildSettingsTab(panel)
    local T = ns.Theme
    local s = function() return ns.db.settings end

    local left = CreateFrame("Frame", nil, panel)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -12, 0)
    local right = CreateFrame("Frame", nil, panel)
    right:SetPoint("TOPLEFT", panel, "TOP", 12, 0)
    right:SetPoint("BOTTOMRIGHT")

    local function Place(region, parent, y, x)
        region:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y)
    end
    local function Section(parent, title, y)
        local h = T.Section(parent, title)
        Place(h, parent, y)
        h.line:SetPoint("RIGHT", parent, "RIGHT")
        return h
    end
    local function Hint(parent, text, y)
        local fs = T.Text(parent, 11, T.colors.muted)
        Place(fs, parent, y)
        fs:SetPoint("RIGHT", parent, "RIGHT")
        fs:SetText(text)
        return fs
    end

    ---------------------------------------------------------------------------
    -- Recording
    ---------------------------------------------------------------------------
    Section(left, "Recording", 0)
    Hint(left, "Record looted items of this quality and better:", -22)
    local qualityButtons = {}
    for i, q in ipairs(QUALITIES) do
        local b = T.Button(left, QualityLabel(q), 68, 24)
        Place(b, left, -40, (i - 1) * 72)
        b:SetScript("OnClick", function()
            s().lootQuality = q
            ns.Fire("SETTINGS_CHANGED")
        end)
        qualityButtons[q] = b
    end
    Hint(left, "Mounts are always recorded.", -70)

    ---------------------------------------------------------------------------
    -- Notifications
    ---------------------------------------------------------------------------
    Section(left, "Notifications", -102)
    local toggles = {}
    local function Toggle(parent, label, y, get, set)
        local t = T.Toggle(parent, label, function(v)
            set(v)
            ns.Fire("SETTINGS_CHANGED")
        end)
        Place(t, parent, y)
        t:SetPoint("RIGHT", parent, "RIGHT")
        t.get = get
        toggles[#toggles + 1] = t
        return t
    end
    Toggle(left, "Pop-up notices (off: messages go to chat)", -124,
        function() return s().toasts ~= false end, function(v) s().toasts = v end)
    Toggle(left, "Play a sound with notices", -148,
        function() return s().toastSound ~= false end, function(v) s().toastSound = v end)
    Toggle(left, "Let brothers poke me", -172,
        function() return s().pokes ~= false end, function(v) s().pokes = v end)
    local test = T.Button(left, "Show a test notice", 140, 24)
    Place(test, left, -202)
    test:SetScript("OnClick", function()
        ns.Notify("This is a Fostbraedr notice", "info", { detail = "Click to open the window, right-click to dismiss", force = true })
    end)

    ---------------------------------------------------------------------------
    -- Interface
    ---------------------------------------------------------------------------
    Section(left, "Interface", -246)
    Toggle(left, "Show the minimap button", -268,
        function() return not s().minimap.hide end,
        function(v)
            s().minimap.hide = not v
            ns.UpdateMinimapButton()
        end)
    local reset = T.Button(left, "Reset window position", 160, 24)
    Place(reset, left, -298)
    reset:SetScript("OnClick", function() ns.ResetWindow() end)
    Hint(left, ("Fostbraedr %s  \194\183  updates: %s"):format(tostring(ns.version), ns.Sync.DOWNLOAD_URL), -334)

    ---------------------------------------------------------------------------
    -- You
    ---------------------------------------------------------------------------
    Section(right, "You", 0)
    local myName = T.Input(right, "Your name")
    myName:SetMaxLetters(24)
    Place(myName, right, -22)
    myName:SetPoint("RIGHT", right, "RIGHT", -70, 0)
    local saveName = T.Button(right, "Save", 64, 24)
    saveName:SetPoint("LEFT", myName, "RIGHT", 6, 0)
    local function SaveName()
        if ns.People.SetMyName(myName:GetText()) then myName:ClearFocus() end
    end
    saveName:SetScript("OnClick", SaveName)
    myName:SetScript("OnEnterPressed", SaveName)
    Hint(right, "What your brothers see for all of your characters.", -52)

    ---------------------------------------------------------------------------
    -- Brothers
    ---------------------------------------------------------------------------
    local B = -84 -- top of the Brothers section
    Section(right, "Brothers", B)
    local input = T.Input(right, "First Last")
    input:SetMaxLetters(40)
    Place(input, right, B - 22)
    input:SetPoint("RIGHT", right, "RIGHT", -70, 0)
    local add = T.Button(right, "Add", 64, 24)
    add:SetPoint("LEFT", input, "RIGHT", 6, 0)
    local function AddTyped()
        if ns.AddBrother(input:GetText()) then input:SetText("") end
        input:ClearFocus()
    end
    add:SetScript("OnClick", AddTyped)
    input:SetScript("OnEnterPressed", AddTyped)
    local addTarget = T.Button(right, "Add my target", 120, 24)
    Place(addTarget, right, B - 52)
    addTarget:SetScript("OnClick", function() ns.AddBrother(nil) end)
    local HINT = "One character per brother is enough; his alts (*) link up automatically."
    local listHint = Hint(right, HINT, B - 84)

    local ROW_H, LIST_TOP = 38, B - 106
    local rows = {}
    local function GetRow(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, right)
        r:SetHeight(ROW_H - 4)
        Place(r, right, LIST_TOP - (i - 1) * ROW_H)
        r:SetPoint("RIGHT", right, "RIGHT")
        T.Panel(r)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetSize(7, 7)
        r.dot:SetPoint("TOPLEFT", 10, -9)
        r.name = T.Text(r, 12)
        r.name:SetPoint("LEFT", r.dot, "RIGHT", 8, 0)
        r.name:SetPoint("RIGHT", r, "RIGHT", -76, 0)
        r.name:SetWordWrap(false)
        r.chars = T.Text(r, 10, T.colors.muted)
        r.chars:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
        r.chars:SetPoint("RIGHT", r, "RIGHT", -76, 0)
        r.chars:SetWordWrap(false)
        r.remove = T.Button(r, "Remove", 64, 20)
        r.remove:SetPoint("RIGHT", -6, 0)
        r.remove:SetScript("OnClick", function()
            -- remove every listed character of this brother (his links go with them)
            for _, c in ipairs(r.person and r.person.chars or {}) do
                if ns.IsBrother(c) then ns.RemoveBrother(c) end
            end
        end)
        rows[i] = r
        return r
    end
    local empty = T.Text(right, 12, T.colors.muted)
    Place(empty, right, LIST_TOP - 4, 4)
    empty:SetText("No brothers yet.")

    function panel:Refresh()
        for q, b in pairs(qualityButtons) do b:SetSelected((s().lootQuality or 4) == q) end
        for _, t in ipairs(toggles) do t:SetChecked(t.get()) end
        if not myName:HasFocus() then myName:SetText(ns.People.MyName() or "") end
        local people = ns.People.Brothers()
        local h = right:GetHeight()
        if not h or h <= 0 then h = 400 end -- not laid out yet
        local maxRows = math.max(1, math.floor((h + LIST_TOP) / ROW_H))
        local shown = math.min(#people, maxRows)
        for i = 1, shown do
            local person = people[i]
            local r = GetRow(i)
            r.person = person
            r.name:SetText(person.name)
            local names = {}
            for j, c in ipairs(person.chars) do
                names[j] = ns.FirstName(c) .. (ns.IsBrother(c) and "" or "*")
            end
            local n = #person.chars
            r.chars:SetText(("%d character%s: %s"):format(n, n == 1 and "" or "s", table.concat(names, ", ")))
            local online = ns.Sync.PersonOnline(person.chars[1])
            local c = online and T.colors.good or T.colors.muted
            r.dot:SetColorTexture(c[1], c[2], c[3], 1)
            r:Show()
        end
        for i = shown + 1, #rows do rows[i]:Hide() end
        empty:SetShown(#people == 0)
        listHint:SetText(#people > shown and ("+%d more not shown (see /fost brother list)"):format(#people - shown)
            or HINT)
    end

    local function RefreshIfVisible()
        if panel:IsVisible() then panel:Refresh() end
    end
    for _, msg in ipairs({ "SETTINGS_CHANGED", "BROTHERS_CHANGED", "PEER_ONLINE", "PEER_OFFLINE", "PEOPLE_CHANGED" }) do
        ns.Listen(msg, RefreshIfVisible)
    end
end
