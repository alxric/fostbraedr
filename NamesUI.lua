-- Fostbraedr: Frames tab (first names only on party and raid frames).
local ADDON, ns = ...

function ns.BuildFramesTab(panel)
    local T = ns.Theme
    local function S() return ns.db.settings.names end
    local function Changed() ns.Fire("NAMES_CHANGED") end

    local function Place(region, y, x) region:SetPoint("TOPLEFT", panel, "TOPLEFT", x or 0, y) end
    local function Hint(text, y, x)
        local fs = T.Text(panel, 11, T.colors.muted)
        Place(fs, y, x)
        fs:SetPoint("RIGHT", panel, "RIGHT")
        fs:SetText(text)
        return fs
    end
    local function Section(title, y)
        local h = T.Section(panel, title)
        Place(h, y)
        h.line:SetPoint("RIGHT", panel, "RIGHT")
    end

    Section("Names on party and raid frames", 0)
    Hint("Forever names are long. Show only first names on Blizzard's party and raid frames.", -22)
    Hint("Only the displayed text changes: clicking still targets and whispers the full name.", -38)

    local toggles = {}
    local function Toggle(label, y, x, get, set)
        local t = T.Toggle(panel, label, function(v) set(v) Changed() panel:Refresh() end)
        Place(t, y, x)
        t:SetPoint("RIGHT", panel, "RIGHT")
        t.get = get
        toggles[#toggles + 1] = t
        return t
    end
    local main = Toggle("Show first names only", -64, 0,
        function() return S().enabled end, function(v) S().enabled = v end)
    local raid = Toggle("Raid-style frames (compact party and raid frames)", -92, 24,
        function() return S().raidFrames end, function(v) S().raidFrames = v end)
    local party = Toggle("Classic party frames", -116, 24,
        function() return S().partyFrames end, function(v) S().partyFrames = v end)

    Section("Which surnames", -156)
    local modes = {
        { key = "all",    label = "All surnames" },
        { key = "family", label = "Only our family's" },
    }
    local modeButtons = {}
    for i, m in ipairs(modes) do
        local b = T.Button(panel, m.label, 140, 24)
        Place(b, -178, (i - 1) * 146)
        b:SetScript("OnClick", function()
            S().mode = m.key
            Changed()
            panel:Refresh()
        end)
        modeButtons[m.key] = b
    end
    local familyHint = Hint("", -210)

    Section("Preview", -246)
    local preview = T.Text(panel, 13, T.colors.text)
    Place(preview, -268)
    preview:SetPoint("RIGHT", panel, "RIGHT")

    Hint("Only Blizzard's own frames. With EllesmereUI, ElvUI, Cell or similar, use an addon such as", -346)
    Hint("\"First Name Basis\" instead; it supports those frames.", -362)

    local combat = Hint("", -386)
    combat:SetTextColor(unpack(T.colors.accent))

    local function SampleNames()
        local list = {}
        if ns.me then list[#list + 1] = ns.me end
        for _, c in ipairs(ns.People.KinChars()) do
            if #list >= 3 then break end
            list[#list + 1] = c
        end
        list[#list + 1] = "Someone Elsewhere"
        return list
    end

    function panel:Refresh()
        local s = S()
        for _, t in ipairs(toggles) do t:SetChecked(t.get()) end
        raid:SetAlpha(s.enabled and 1 or 0.4)
        party:SetAlpha(s.enabled and 1 or 0.4)
        for key, b in pairs(modeButtons) do b:SetSelected(s.mode == key) end
        local fam = {}
        for sn in pairs(ns.Names.FamilySurnames()) do fam[#fam + 1] = sn:sub(1, 1):upper() .. sn:sub(2) end
        table.sort(fam)
        familyHint:SetText(#fam > 0 and ("Family surnames: " .. table.concat(fam, ", "))
            or "No family surnames known yet (add your brothers first).")
        local lines = {}
        for _, full in ipairs(SampleNames()) do
            local first, last = full:match("^(%S+)%s+(.+)$")
            local short = s.enabled and ns.Names.Shorten(first, last)
            lines[#lines + 1] = short and (full .. T.Muted("  ->  ") .. T.Accent(short)) or (full .. T.Muted("  (unchanged)"))
        end
        preview:SetText(table.concat(lines, "\n"))
        combat:SetText(ns.Names.pendingRefresh and "Changes apply when you leave combat." or "")
    end

    for _, msg in ipairs({ "BROTHERS_CHANGED", "PEOPLE_CHANGED" }) do
        ns.Listen(msg, function() if panel:IsVisible() then panel:Refresh() end end)
    end
end
