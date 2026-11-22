-- Fostbraedr: form-based gear swap (druids). One set is worn in cat form, the
-- other in every other form (caster included). Weapons and trinkets can each be
-- switched on or off. Every attempt is logged for /fost geartest.
--
-- Out of combat we just try, check shortly after, and try again when your cast
-- ends and a few more times after a form change. In combat equipping is a
-- protected action on Forever (ADDON_ACTION_BLOCKED, seen 2026-11-22): only a
-- button or macro you press may do it. So in combat we don't try; the set goes
-- on as soon as combat ends.
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

-- Your class can't change, so remember it: in combat it might be unreadable.
local myClass
function G.IsDruid()
    if not myClass then
        local _, class = UnitClass("player")
        myClass = Val(class)
    end
    return myClass == "DRUID"
end
function G.ForgetClass() myClass = nil end -- tests only

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
-- Kept in the saved variables (ns.db.gearLog) so it survives /reload and logout.
G.log = {}

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
    if ns.db then
        ns.db.gearLog = ns.db.gearLog or {}
        G.log = ns.db.gearLog
    end
    local entry = ("%s  %s"):format(date("%H:%M:%S"), line)
    table.insert(G.log, entry)
    if #G.log > LOG_SIZE then table.remove(G.log, 1) end
    if ns.db and ns.db.settings.gearDebug then ns.Print("gear: %s", line) end
end

local function GCDText()
    local left = GCDLeft()
    return left and ("%.2fs"):format(left) or "?"
end

-- The global cooldown can't be read on Forever (always "?"), so it's only shown
-- when it can.
local function State()
    local gcd = GCDLeft()
    return ("combat=%s, casting=%s%s"):format(tostring(InCombatLockdown() and true or false),
        tostring(Casting() or "no"), gcd and (", gcd left=" .. GCDText()) or "")
end

-- The last game error, so the log can show why an equip didn't happen.
local lastError
ns.OnOptional("UI_ERROR_MESSAGE", function(_, message)
    message = Val(message)
    if message then lastError = { text = message, time = GetTime() } end
end)

-- WoW blocks protected calls from addons (often only in combat) and says so with
-- these events: the strongest sign that equipping is off limits to addons.
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    ns.OnOptional(event, function(addon, func)
        if addon ~= ADDON then return end
        lastError = { text = ("%s: %s"):format(event, tostring(func)), time = GetTime() }
        Log("the game blocked " .. tostring(func) .. " (" .. event .. ")")
    end)
end

-------------------------------------------------------------------------------
-- Equipping
-------------------------------------------------------------------------------
local function Equip(item, slot)
    local fn = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    if not fn then return "no EquipItemByName in this client" end
    local ok, err = pcall(fn, item, slot)
    if not ok then return tostring(err) end
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
    if InCombatLockdown() then
        if not G.waitingForCombat then
            Log(why .. ": in combat addons can't equip; swapping when combat ends")
            G.waitingForCombat = true
        end
        G.status = "In combat: your " .. G.SET_TITLES[setKey]:lower() .. " set goes on when combat ends."
        ns.Fire("GEAR_CHANGED")
        return false
    end
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
            local err = Equip(m.want.link or m.want.id, m.slot)
            if err then Log("  equip call failed: " .. err) end
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
        if InCombatLockdown() then return end -- PLAYER_REGEN_ENABLED takes over
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
    if InCombatLockdown() then return ns.Print("Addons can't change gear in combat; try again after the fight.") end
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
    if not setKey then return Log("form change: can't read your form right now") end
    if setKey == lastSet then return end -- fires for more than form changes
    lastSet = setKey
    G.hold = false
    ApplyWithRetries("form change to " .. tostring(setKey and G.SET_TITLES[setKey] or "?"))
end)

local function OnCastEnd(unit)
    if unit ~= "player" or G.hold or not Active() or InCombatLockdown() then return end
    local setKey = G.WantedSet()
    if setKey and #G.Missing(setKey) > 0 then ApplyWithRetries("cast ended") end
end
for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED",
                         "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    ns.OnOptional(event, OnCastEnd)
end

ns.OnOptional("PLAYER_REGEN_ENABLED", function()
    G.waitingForCombat = false
    if G.hold or not Active() then return end
    local setKey = G.WantedSet()
    if setKey and #G.Missing(setKey) > 0 then ApplyWithRetries("combat ended") end
end)

ns.On("PLAYER_LOGIN", function()
    if ns.db.gearLog then G.log = ns.db.gearLog end
    if G.IsDruid() then lastSet = G.WantedSet() end
end)

-- /fost geartest: the log of recent swaps, in the copyable window.
function G.ShowLog()
    local lines = {
        ("Gear swap log (form now: %s, druid=%s, %s)"):format(tostring(G.WantedSet()), tostring(G.IsDruid()), State()),
        "Each line: time, what happened. Kept across /reload.",
        "",
    }
    for _, l in ipairs(G.log) do lines[#lines + 1] = l end
    if #G.log == 0 then lines[#lines + 1] = "Nothing yet: switch it on in the Gear tab and change form." end
    ns.ShowTextWindow("Gear test", table.concat(lines, "\n"))
end
