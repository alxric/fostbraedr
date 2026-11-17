-- Fostbraedr: core (namespace, saved variables, events, slash command)
local ADDON, ns = ...

ns.name = ADDON
ns.ICON = "Interface\\Icons\\Achievement_Zone_HowlingFjord_01" -- also in the .toc (IconTexture)
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

-- Bump when the shape of FostbraedrDB changes; Migrate() upgrades older data.
local DB_SCHEMA = 2

local DEFAULTS = {
    schema = DB_SCHEMA,
    settings = {
        brothers = {},      -- ["First Last"] = true
        window = {},        -- point, relPoint, x, y
        lastTab = 1,
        minimap = { angle = 225, hide = false },
        lootQuality = 4,
        toasts = true,      -- pop-up notices (false = chat)
        pokes = true,       -- receive pokes
        toastSound = true,  -- sounds with pop-up notices (pokes always play)
        -- status = "custom status text" (nil when unset)    -- record loot of this quality and up (4 = epic); mounts always
    },
    entries = {},           -- [id] = entry, id = "Author#n" (see Chronicle.lua)
    counters = {},          -- [author] = highest entry counter
    pending = {},           -- stats not yet written as a tally entry
    myChars = {},           -- ["First Last"] = true for every character on this account
    peers = {},             -- ["First Last"] = { lastSeen, version, level, zone, class } (from sync)
    account = {},           -- our identity: { id, name } (see People.lua)
    people = {},            -- brothers' accounts: [id] = { name, chars, lastSeen }
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local PREFIX = "|cff66ccffFostbraedr|r: "

function ns.Print(fmt, ...)
    local msg = select("#", ...) > 0 and fmt:format(...) or tostring(fmt)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

-- Copper amount as "12g 34s 56c" (with coin icons when the client offers them).
function ns.FormatMoney(copper)
    copper = math.floor(copper or 0)
    local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if fn then
        local ok, s = pcall(fn, copper)
        if ok and type(s) == "string" then return s end
    end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return ("%dg %ds %dc"):format(g, s, c) end
    if s > 0 then return ("%ds %dc"):format(s, c) end
    return ("%dc"):format(c)
end

-- Turn a Blizzard format string (e.g. LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s")
-- into a Lua pattern. Supports %s, %d and positional %1$s / %2$d.
local formatCache = {}
local function FormatToPattern(fmt)
    local out, order, i, nextArg = {}, {}, 1, 1
    while i <= #fmt do
        local _, e, num, typ = fmt:find("^%%(%d+)%$([sd])", i)
        if not e then
            _, e, typ = fmt:find("^%%([sd%%])", i)
        end
        if e then
            if typ == "%" then
                out[#out + 1] = "%%"
            else
                order[#order + 1] = tonumber(num) or nextArg
                nextArg = nextArg + 1
                out[#out + 1] = typ == "d" and "(%-?%d+)" or "(.+)"
            end
            i = e + 1
        else
            local c = fmt:sub(i, i)
            out[#out + 1] = c:find("[%(%)%.%+%-%*%?%[%]%^%$%%]") and ("%" .. c) or c
            i = i + 1
        end
    end
    return "^" .. table.concat(out) .. "$", order
end

-- Match text against a format string; returns the arguments in format order, or nil.
function ns.MatchFormat(text, fmt)
    if type(fmt) ~= "string" or type(text) ~= "string" then return nil end
    local c = formatCache[fmt]
    if not c then
        local pat, order = FormatToPattern(fmt)
        c = { pat = pat, order = order }
        formatCache[fmt] = c
    end
    local caps = { text:match(c.pat) }
    if #caps == 0 then return nil end
    local args = {}
    for k, idx in ipairs(c.order) do args[idx] = caps[k] end
    return args
end

-- Fill missing keys in `dst` from `src`, recursively. Never overwrites.
local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function Migrate(db)
    if (db.schema or 1) < 2 then
        -- Schema 1 stored brothers as "Name-Realm", which is wrong on Forever
        -- (characters have first + last names). Those were test entries; drop them.
        local old = {}
        for k in pairs(db.settings.brothers) do old[#old + 1] = k end
        if #old > 0 then
            ns.pendingNotice = "Brother list was reset (Forever names have surnames). Removed: "
                .. table.concat(old, ", ") .. ". Re-add with /fost brother add First Last"
        end
        wipe(db.settings.brothers)
        db.schema = 2
    end
    db.schema = DB_SCHEMA
end

-- Character identity on Forever: "First Last" (no realm). UnitName returns the
-- surname where retail returns the realm. Either part may be a secret value in
-- restricted situations; then we return nil.
local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end
ns.IsSecret = IsSecret

function ns.UnitFullCharName(unit)
    local first, last = UnitName(unit)
    if not first or IsSecret(first) or first == "" or first == UNKNOWNOBJECT then return nil end
    if last and not IsSecret(last) and last ~= "" then
        return first .. " " .. last
    end
    return first
end

function ns.PlayerFullName()
    return ns.UnitFullCharName("player")
end

local function TitleWord(w)
    return w:sub(1, 1):upper() .. w:sub(2):lower()
end

-- Normalise names from user input or chat events to "First Last":
-- trims, collapses spaces, drops any "-Realm" suffix, capitalises each word.
function ns.NormalizeName(input)
    if type(input) ~= "string" then return nil end
    input = input:gsub("%-.*$", "")
    local words = {}
    for w in input:gmatch("%S+") do words[#words + 1] = TitleWord(w) end
    if #words == 0 then return nil end
    return table.concat(words, " ")
end

-- Case-insensitive key for comparing names.
function ns.NameKey(name)
    local n = ns.NormalizeName(name)
    return n and n:lower()
end

-- Ours, a listed brother, or linked to a brother's account: whose entries we accept.
function ns.IsFamily(name)
    if ns.IsBrother(name) then return true end
    return ns.People.Of(name) ~= nil
end

function ns.IsBrother(name)
    local key = ns.NameKey(name)
    if not key then return false end
    for n in pairs(ns.db.settings.brothers) do
        if ns.NameKey(n) == key then return true end
    end
    return false
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
ns.eventFrame = eventFrame
local handlers = {}

-- ns.On("EVENT", function(...) end) -- multiple handlers per event allowed
function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Internal messages between modules: ns.Listen("ENTRY_ADDED", fn); ns.Fire("ENTRY_ADDED", ...)
local listeners = {}
function ns.Listen(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end
function ns.Fire(msg, ...)
    for _, fn in ipairs(listeners[msg] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

ns.On("ADDON_LOADED", function(loaded)
    if loaded ~= ADDON then return end
    if type(FostbraedrDB) ~= "table" then FostbraedrDB = {} end
    local db = FostbraedrDB
    ApplyDefaults(db, DEFAULTS)
    Migrate(db)
    ns.db = db
    if ns.OnDBReady then ns.OnDBReady() end
end)

ns.On("PLAYER_LOGIN", function()
    ns.me = ns.PlayerFullName()
    if ns.me then ns.db.myChars[ns.me] = true end
    ns.Print("v%s loaded. Type |cffffff00/fost|r to open, |cffffff00/fost help|r for commands.", ns.version)
    if ns.pendingNotice then
        ns.Print(ns.pendingNotice)
        ns.pendingNotice = nil
    end
end)

-------------------------------------------------------------------------------
-- Slash command
-------------------------------------------------------------------------------
local function ListBrothers()
    local people = ns.People.Brothers()
    if #people == 0 then
        return ns.Print("No brothers configured. Target him and type /fost brother add, or /fost brother add First Last")
    end
    ns.Print("Brothers (%d):", #people)
    for _, person in ipairs(people) do
        local chars = {}
        for i, c in ipairs(person.chars) do chars[i] = c .. (ns.IsBrother(c) and "" or " (linked)") end
        print(("  %s: %s"):format(person.name, table.concat(chars, ", ")))
    end
end

local commands = {}

commands.help = function()
    ns.Print("commands:")
    print("  /fost - toggle the window")
    print("  /fost show | hide")
    print("  /fost reset - reset window position")
    print("  /fost brother add [First Last] - no name = your target")
    print("  /fost brother remove First Last")
    print("  /fost brother list")
    print("  /fost minimap - show/hide the minimap button")
    print("  /fost ping [First Last] - check that brothers' addons answer")
    print("  /fost sync - exchange missing chronicle entries now")
    print("  /fost peers - which brothers are online, last seen")
    print("  /fost debug - toggle comm debug output")
    print("  /fost name [Name] - the name your brothers see for you (all your characters)")
    print("  /fost status [text] - set (or clear) your status for the family")
    print("  /fost poke Name [message] - poke a brother")
    print("  /fost toasts - pop-up notices on/off")
    print("  /fost pokes - receiving pokes on/off")
    print("  /fost stats - your quests, gold and time so far")
    print("  /fost lootquality N - loot quality to record (4 = epic)")
    print("  /fost version")
end

commands.show = function() ns.ShowWindow() end
commands.hide = function() ns.HideWindow() end
commands.reset = function() ns.ResetWindow() ns.Print("Window position reset.") end

commands.minimap = function()
    local m = ns.db.settings.minimap
    m.hide = not m.hide
    ns.UpdateMinimapButton()
    ns.Fire("SETTINGS_CHANGED")
    ns.Print("Minimap button %s.", m.hide and "hidden" or "shown")
end

commands.stats = function()
    local t = ns.StatTotals()[ns.me] or {}
    local timeline, snapshots = 0, 0
    for _, e in pairs(ns.db.entries) do
        if e.kind == "tally" then snapshots = snapshots + 1 else timeline = timeline + 1 end
    end
    ns.Print("%s: %d quests, %s earned, %d min played, %d min with brothers.",
        ns.me or "?", t.quests or 0, ns.FormatMoney(t.gold), t.minutes or 0, t.together or 0)
    ns.Print("Chronicle: %d timeline entries, %d hidden stats snapshots.", timeline, snapshots)
end

commands.ping = function(rest)
    ns.Sync.Ping(rest ~= "" and ns.NormalizeName(rest) or nil)
end

commands.sync = function()
    ns.Sync.HelloAll(true)
    ns.Print("Saying hello to all brothers; missing entries will be exchanged.")
end

commands.peers = function() ns.Sync.PrintPeers() end

commands.debug = function()
    ns.Comm.debug = not ns.Comm.debug
    ns.Print("Comm debug output %s.", ns.Comm.debug and "on" or "off")
end

-- "Thorgrim wake up" / "Thorgrim Stormfjord wake up" -> "Thorgrim Stormfjord", "wake up"
function ns.FindBrotherByPrefix(text)
    local lower = (text or ""):lower()
    local best, bestLen, firstMatches = nil, 0, {}
    for n in pairs(ns.db.settings.brothers) do
        local full = n:lower()
        if lower == full or lower:sub(1, #full + 1) == full .. " " then
            if #full > bestLen then best, bestLen = n, #full end
        end
        local first = ns.FirstName(n):lower()
        if lower == first or lower:sub(1, #first + 1) == first .. " " then
            firstMatches[#firstMatches + 1] = n
        end
    end
    if best then return best, (text:sub(bestLen + 2)) end
    -- a person's name ("Thorgrim" even if he's on Brokk): pick his online character
    for _, person in ipairs(ns.People.Brothers()) do
        local pn = person.name:lower()
        if lower == pn or lower:sub(1, #pn + 1) == pn .. " " then
            local pick = person.chars[1]
            for _, c in ipairs(person.chars) do
                if ns.Sync.IsOnline(c) then pick = c break end
            end
            return pick, (text:sub(#pn + 2))
        end
    end
    if #firstMatches == 1 then
        local len = #ns.FirstName(firstMatches[1])
        return firstMatches[1], (text:sub(len + 2))
    end
    return nil
end

commands.poke = function(rest)
    local name, msg = ns.FindBrotherByPrefix(rest)
    if not name then return ns.Print("Usage: /fost poke Name [message] (a brother from /fost brother list)") end
    ns.Poke(name, msg)
end

commands.status = function(rest)
    ns.SetMyStatus(rest)
    ns.Print(ns.db.settings.status and ("Status set: \"%s\""):format(ns.db.settings.status) or "Status cleared.")
end

commands.name = function(rest)
    if rest == "" then return ns.Print("Your name for the family: %s. Change it with /fost name <Name>", tostring(ns.People.MyName())) end
    local name = ns.People.SetMyName(rest)
    if name then ns.Print("Your brothers will see you as %s.", name) end
end

commands.toasts = function()
    ns.db.settings.toasts = ns.db.settings.toasts == false
    ns.Fire("SETTINGS_CHANGED")
    ns.Print("Pop-up notices %s.", ns.db.settings.toasts and "on" or "off (shown in chat instead)")
    if ns.db.settings.toasts then ns.Notify("Pop-up notices are on", "info", { detail = "This is what they look like" }) end
end

commands.pokes = function()
    ns.db.settings.pokes = ns.db.settings.pokes == false
    ns.Fire("SETTINGS_CHANGED")
    ns.Print("Receiving pokes %s.", ns.db.settings.pokes and "on" or "off")
end

commands.loottest = function()
    local ok, err = pcall(ns.LootTest)
    if not ok then ns.Print("Loot test failed: %s", tostring(err)) end
end

commands.lootquality = function(rest)
    local q = tonumber(rest)
    if q and q >= 0 and q <= 7 then
        ns.db.settings.lootQuality = q
        ns.Fire("SETTINGS_CHANGED")
    end
    ns.Print("Recording loot of quality %d and up (2 = green, 3 = blue, 4 = epic); mounts always.", ns.db.settings.lootQuality)
end

commands.version = function()
    local _, build, _, iface = GetBuildInfo()
    ns.Print("addon v%s, schema %d, client build %s, interface %s", ns.version, ns.db.schema, tostring(build), tostring(iface))
end

local function FindBrother(name)
    local key = ns.NameKey(name)
    for n in pairs(ns.db.settings.brothers) do
        if ns.NameKey(n) == key then return n end
    end
end

-- Add a brother by name, or the current target when name is nil/empty.
-- Prints the outcome; returns the stored name on success.
function ns.AddBrother(name)
    local full
    if not name or name == "" then
        if not UnitIsPlayer("target") then
            return ns.Print("Target your brother first, or type his name (First Last).")
        end
        full = ns.UnitFullCharName("target")
        if not full then return ns.Print("Couldn't read your target's name here; type it instead.") end
    else
        full = ns.NormalizeName(name)
    end
    if not full then return ns.Print("Usage: /fost brother add First Last") end
    if ns.me and ns.NameKey(full) == ns.NameKey(ns.me) then return ns.Print("That's you!") end
    if FindBrother(full) then return ns.Print("%s is already in the list.", full) end
    ns.db.settings.brothers[full] = true
    ns.Print("Added brother %s.", full)
    if not full:find(" ") then
        ns.Print("Note: that's only one name. Forever characters have a surname too; add the full name so whispers reach him.")
    end
    ns.Fire("BROTHERS_CHANGED")
    return full
end

function ns.RemoveBrother(name)
    local found = FindBrother(name)
    if not found then return ns.Print("Not in the list: %s", tostring(name)) end
    ns.db.settings.brothers[found] = nil
    ns.People.ForgetIfUnlisted(found)
    ns.Print("Removed brother %s.", found)
    ns.Fire("BROTHERS_CHANGED")
    return found
end

commands.brother = function(rest)
    local sub, arg = rest:match("^(%S*)%s*(.-)%s*$")
    sub = (sub or ""):lower()
    if sub == "add" then
        ns.AddBrother(arg)
    elseif sub == "remove" or sub == "del" then
        ns.RemoveBrother(arg)
    else
        ListBrothers()
    end
end
commands.brothers = commands.brother

SLASH_FOSTBRAEDR1 = "/fost"
SLASH_FOSTBRAEDR2 = "/fostbraedr"
SlashCmdList.FOSTBRAEDR = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns.ToggleWindow()
    elseif commands[cmd] then
        commands[cmd](rest or "")
    else
        ns.Print("Unknown command '%s'.", cmd)
        commands.help()
    end
end

-------------------------------------------------------------------------------
-- Addon compartment (the addon button next to the minimap). Must be globals,
-- they're referenced by name from the .toc.
-------------------------------------------------------------------------------
function Fostbraedr_OnAddonCompartmentClick()
    ns.ToggleWindow()
end

function Fostbraedr_OnAddonCompartmentEnter(_, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("Fostbraedr")
    GameTooltip:AddLine("Click to open the family chronicle.", 1, 1, 1)
    GameTooltip:Show()
end

function Fostbraedr_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

-- Forever has AddonCompartmentFrame but doesn't seem to pick up the TOC
-- AddonCompartmentFunc entry, so register in code unless an entry already exists.
local function RegisterCompartment()
    local cf = AddonCompartmentFrame
    if not (cf and cf.RegisterAddon) then return end
    for _, info in ipairs(cf.registeredAddons or {}) do
        if info.text == "Fostbraedr" then return end
    end
    cf:RegisterAddon({
        text = "Fostbraedr",
        icon = ns.ICON,
        notCheckable = true,
        func = Fostbraedr_OnAddonCompartmentClick,
        funcOnEnter = function(button) Fostbraedr_OnAddonCompartmentEnter(nil, button) end,
        funcOnLeave = Fostbraedr_OnAddonCompartmentLeave,
    })
end

ns.On("PLAYER_LOGIN", function()
    local ok, err = pcall(RegisterCompartment)
    if not ok then ns.Print("Couldn't add the addon-compartment entry: %s", tostring(err)) end
end)
