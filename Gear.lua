-- Fostbraedr: form-based gear swap (druids). One set is worn in cat form, the
-- other in every other form (caster included). Weapons and trinkets can each be
-- switched on or off. Every attempt is logged for /fost geartest.
--
-- The game decides when an item may be equipped (mid-cast, in combat, on the
-- global cooldown). We just try, check shortly after, and try again when your
-- cast ends, when combat ends, and a few more times after a form change.
local ADDON, ns = ...

local G = {}
ns.Gear = G

local CAT_FORM = 1 -- GetShapeshiftFormID() in cat form
local GCD_SPELL = 61304 -- the global cooldown's own spell ID

G.SLOTS = {
    { slot = 16, label = "Main hand",  group = "weapons" },
    { slot = 17, label = "Off hand",   group = "weapons" },
    { slot = 13, label = "Trinket 1",  group = "trinkets" },
    { slot = 14, label = "Trinket 2",  group = "trinkets" },
}
G.SETS = { "cat", "other" }
G.SET_TITLES = { cat = "Cat form", other = "Every other form" }

local RETRY_EVERY, RETRIES = 0.5, 10 -- after a form change: keep trying for 5 seconds
local VERIFY_AFTER = 0.3
local LOG_SIZE = 60

local function Val(v) if not ns.IsSecret(v) then return v end end

-------------------------------------------------------------------------------
-- Saved data, per character: { weapons = bool, trinkets = bool,
-- sets = { cat = { [slot] = { id, link } }, other = { ... } } }
-------------------------------------------------------------------------------
-- create: make the entry if it's missing (only when saving a set, so other
-- classes never get one).
function G.Data(create)
    if not (ns.db and ns.me) then return nil end
    local all = ns.db.gear
    local d = all[ns.me]
    if not d and create then
        d = { weapons = false, trinkets = false, sets = { cat = {}, other = {} } }
        all[ns.me] = d
    end
    return d
end

function G.IsDruid()
    local _, class = UnitClass("player")
    return Val(class) == "DRUID"
end

-- Only druids, with at least one group switched on. Other classes' stances and
-- stealth fire the same events; they must do nothing.
local function Active()
    local d = G.Data()
    return d and (d.weapons or d.trinkets) and G.IsDruid()
end
G.Active = Active

-- "cat" or "other"; nil if the form can't be read right now.
function G.WantedSet()
    if not GetShapeshiftFormID then return nil end
    local id = GetShapeshiftFormID()
    if ns.IsSecret(id) then return nil end
    return id == CAT_FORM and "cat" or "other"
end

-- Save what you're wearing in these slots as the given set.
function G.SaveCurrent(setKey)
    if not G.IsDruid() then return end
    local d = G.Data(true)
    if not d then return end
    local set = {}
    for _, s in ipairs(G.SLOTS) do
        local id = Val(GetInventoryItemID("player", s.slot))
        if id then set[s.slot] = { id = id, link = Val(GetInventoryItemLink("player", s.slot)) } end
    end
    d.sets[setKey] = set
    ns.Fire("GEAR_CHANGED")
end

-------------------------------------------------------------------------------
-- Log, for /fost geartest
-------------------------------------------------------------------------------
G.log = {}
local t0

local function GCDLeft()
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local cd = C_Spell.GetSpellCooldown(GCD_SPELL)
        if type(cd) == "table" then start, duration = cd.startTime, cd.duration end
    elseif GetSpellCooldown then
        start, duration = GetSpellCooldown(GCD_SPELL)
    end
    start, duration = Val(start), Val(duration)
    if not (start and duration) then return nil end
    if duration == 0 then return 0 end
    return math.max(0, start + duration - GetTime())
end

local function Casting()
    local name = UnitCastingInfo and Val(UnitCastingInfo("player"))
    if not name and UnitChannelInfo then name = Val(UnitChannelInfo("player")) end
    return name
end

local function Log(line)
    t0 = t0 or GetTime()
    local entry = ("%7.2f  %s"):format(GetTime() - t0, line)
    table.insert(G.log, entry)
    if #G.log > LOG_SIZE then table.remove(G.log, 1) end
    if ns.db and ns.db.settings.gearDebug then ns.Print("gear: %s", line) end
end

local function GCDText()
    local left = GCDLeft()
    return left and ("%.2fs"):format(left) or "?"
end

local function State()
    return ("combat=%s, casting=%s, gcd left=%s"):format(tostring(InCombatLockdown() and true or false),
        tostring(Casting() or "no"), GCDText())
end

-- The last game error, so the log can show why an equip didn't happen.
local lastError
ns.OnOptional("UI_ERROR_MESSAGE", function(_, message)
    message = Val(message)
    if message then lastError = { text = message, time = GetTime() } end
end)

-------------------------------------------------------------------------------
-- Equipping
-------------------------------------------------------------------------------
local function Equip(item, slot)
    local fn = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    if fn then fn(item, slot) end
end

local function HaveItem(id)
    local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id)) or 0
    return (Val(count) or 0) > 0
end

-- Slots of the set that don't hold the right item yet: only switched-on groups,
-- unless all is true.
function G.Missing(setKey, all)
    local d = G.Data()
    local out = {}
    if not d then return out end
    local set = d.sets[setKey] or {}
    for _, s in ipairs(G.SLOTS) do
        local want = set[s.slot]
        if want and (all or d[s.group]) and Val(GetInventoryItemID("player", s.slot)) ~= want.id then
            out[#out + 1] = { slot = s.slot, label = s.label, want = want }
        end
    end
    return out
end

G.status = "" -- one line for the tab

local attempt = 0 -- bumps on every new form change, so old retries stop
G.hold = false    -- a set worn with a button stays on until your next form change

-- Try to put on the set. why: what triggered it (for the log).
function G.Apply(setKey, why, all)
    local missing = G.Missing(setKey, all)
    if #missing == 0 then return true end
    if UnitIsDeadOrGhost("player") then return false end
    if CursorHasItem and CursorHasItem() then
        Log(why .. ": you're holding an item on the cursor; waiting")
        return false
    end
    local tried = 0
    for _, m in ipairs(missing) do -- main hand before off hand: a two-hander replaces both
        local name = m.want.link or ("item " .. m.want.id)
        if not HaveItem(m.want.id) then
            Log(("%s: %s: %s isn't in your bags"):format(why, m.label, name))
            G.status = name .. " isn't in your bags."
        else
            Log(("%s: equip %s in %s (%s)"):format(why, name, m.label, State()))
            lastError = nil
            local started = GetTime()
            Equip(m.want.link or m.want.id, m.slot)
            tried = tried + 1
            C_Timer.After(VERIFY_AFTER, function()
                local now = Val(GetInventoryItemID("player", m.slot))
                if now == m.want.id then
                    Log(("  -> %s worn after %.2fs (%s)"):format(m.label, GetTime() - started, State()))
                else
                    local err = lastError and lastError.time >= started and lastError.text
                    Log(("  -> %s not changed%s"):format(m.label, err and (": " .. err) or ""))
                end
                ns.Fire("GEAR_CHANGED")
            end)
        end
    end
    if tried > 0 then G.status = ("Putting on your %s set..."):format(G.SET_TITLES[setKey]:lower()) end
    return false
end

-- Apply now, then keep checking for a few seconds (a cast or the GCD may block it).
local function ApplyWithRetries(why)
    if not Active() then return end
    local setKey = G.WantedSet()
    if not setKey then
        Log(why .. ": can't read your form right now")
        return
    end
    attempt = attempt + 1
    local mine, tries = attempt, 0
    local function Try()
        if mine ~= attempt then return end
        if G.WantedSet() ~= setKey then return end
        tries = tries + 1
        if G.Apply(setKey, tries == 1 and why or ("retry " .. (tries - 1))) then
            G.status = ("Wearing your %s set."):format(G.SET_TITLES[setKey]:lower())
            ns.Fire("GEAR_CHANGED")
            return
        end
        if tries <= RETRIES then
            C_Timer.After(RETRY_EVERY, Try)
        else
            G.status = InCombatLockdown() and "Some items wait until combat ends." or "Couldn't put on every item; see /fost geartest."
            Log("giving up for now; will try again when your cast or combat ends")
            ns.Fire("GEAR_CHANGED")
        end
    end
    Try()
end
G.ApplyWithRetries = ApplyWithRetries

-- Wear a set right now (the tab's buttons; also good for testing the GCD in combat).
function G.WearNow(setKey)
    if not (G.IsDruid() and G.Data()) then return end
    attempt = attempt + 1 -- stop retries for the other set
    G.hold = true
    G.Apply(setKey, "button", true)
    ns.Fire("GEAR_CHANGED")
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local lastSet
ns.OnOptional("UPDATE_SHAPESHIFT_FORM", function()
    if not Active() then return end
    local setKey = G.WantedSet()
    if setKey == lastSet then return end -- fires for more than form changes
    lastSet = setKey
    G.hold = false
    ApplyWithRetries("form change to " .. tostring(setKey and G.SET_TITLES[setKey] or "?"))
end)

local function OnCastEnd(unit)
    if unit ~= "player" or G.hold or not Active() then return end
    local setKey = G.WantedSet()
    if setKey and #G.Missing(setKey) > 0 then ApplyWithRetries("cast ended") end
end
for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED",
                         "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    ns.OnOptional(event, OnCastEnd)
end

ns.OnOptional("PLAYER_REGEN_ENABLED", function()
    if G.hold or not Active() then return end
    local setKey = G.WantedSet()
    if setKey and #G.Missing(setKey) > 0 then ApplyWithRetries("combat ended") end
end)

ns.On("PLAYER_LOGIN", function() if G.IsDruid() then lastSet = G.WantedSet() end end)

-- /fost geartest: the log of recent swaps, in the copyable window.
function G.ShowLog()
    local lines = {
        ("Gear swap log (form now: %s, druid=%s, %s)"):format(tostring(G.WantedSet()), tostring(G.IsDruid()), State()),
        "Each line: seconds since the first entry, what happened. 'gcd left' is the global cooldown.",
        "",
    }
    for _, l in ipairs(G.log) do lines[#lines + 1] = l end
    if #G.log == 0 then lines[#lines + 1] = "Nothing yet: switch it on in the Gear tab and change form." end
    ns.ShowTextWindow("Gear test", table.concat(lines, "\n"))
end
