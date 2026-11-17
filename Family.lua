-- Fostbraedr: live family status, heartbeat, bye, and pokes.
--
-- Messages:
--   ST   { t, st = status, hw } status changed, or 4-minute heartbeat (with hw, see Sync)
--   BYE  { t }                 sent at logout (or /reload), best effort
--   POKE { t, m }              optional short message
local ADDON, ns = ...

local Comm, Sync = ns.Comm, ns.Sync
local HEARTBEAT = 4 * 60        -- must stay below Sync's 10-minute online window
local STATUS_DEBOUNCE = 3
local STATUS_MIN_INTERVAL = 15
local POKE_COOLDOWN = 10        -- per target, sender side
local POKE_RECEIVE_LIMIT = 5    -- per sender, receiver side

-------------------------------------------------------------------------------
-- Our status
-------------------------------------------------------------------------------
local function NotSecret(v)
    if v == nil or ns.IsSecret(v) then return nil end
    return v
end

function ns.MyActivity()
    local inInstance, instanceType = IsInInstance()
    if NotSecret(inInstance) then
        local name = NotSecret((GetInstanceInfo()))
        if instanceType == "raid" then return "Raiding " .. (name or "") end
        if instanceType == "pvp" or instanceType == "arena" then return "In " .. (name or "a battleground") end
        return "In dungeon: " .. (name or "?")
    end
    if UnitIsDeadOrGhost("player") then return "Dead, running back" end
    if UnitIsAFK("player") then return "AFK" end
    if UnitOnTaxi("player") then return "Flying" end
    if IsResting() then return "Resting in town" end
    if IsInGroup() then return "Adventuring in a group" end
    return "Out in the world"
end

function ns.MyStatus()
    local _, classFile = UnitClass("player")
    local sub = NotSecret(GetSubZoneText())
    local zone = ns.Zone()
    if sub == "" then sub = nil end
    return {
        level = UnitLevel("player"),
        zone = zone and sub and sub ~= zone and (zone .. " - " .. sub) or zone,
        class = classFile,
        activity = ns.MyActivity(),
        status = ns.db.settings.status,
        grouped = IsInGroup() or nil,
    }
end

-------------------------------------------------------------------------------
-- Sending status
-------------------------------------------------------------------------------
local lastSentKey, lastSentAt, pending = nil, 0, false

local function StatusKey(st)
    return ns.Serialize.Encode(st)
end

local function SendStatus(force)
    pending = false
    local st = ns.MyStatus()
    local key = StatusKey(st)
    if not force and key == lastSentKey then return end
    lastSentKey, lastSentAt = key, GetTime()
    -- The heartbeat also carries our high-water marks, so brothers who missed live
    -- entries (e.g. sent while we were in an instance) catch up within minutes.
    Sync.SendToOnline({ t = "ST", st = st, acct = ns.People.MyAccount(false), hw = force and Sync.HighWater() or nil })
    ns.Fire("MY_STATUS", st)
end

local function StatusChanged()
    if pending then return end
    pending = true
    local wait = math.max(STATUS_DEBOUNCE, STATUS_MIN_INTERVAL - (GetTime() - lastSentAt))
    C_Timer.After(wait, function() SendStatus(false) end)
end
ns.StatusChanged = StatusChanged

for _, ev in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_LEVEL_UP",
                      "PLAYER_FLAGS_CHANGED", "PLAYER_UPDATE_RESTING", "PLAYER_DEAD", "PLAYER_ALIVE",
                      "PLAYER_UNGHOST", "GROUP_ROSTER_UPDATE", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do
    ns.On(ev, StatusChanged)
end

function ns.SetMyStatus(text)
    text = text and text:gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
    ns.db.settings.status = text ~= "" and text:sub(1, 80) or nil
    SendStatus(false)
    ns.Fire("MY_STATUS", ns.MyStatus())
end

Comm.On("ST", function(msg, sender)
    Sync.LearnAccount(sender, msg.acct)
    local name = Sync.From(sender)
    if not name then return end
    Sync.ApplyStatus(name, msg.st)
    if type(msg.hw) == "table" then Sync.SendMissing(name, msg.hw) end
end)

Comm.On("BYE", function(msg, sender)
    local name = ns.ResolveSender(sender)
    if name and ns.People.IsKin(name) then Sync.MarkOffline(name) end
end)

ns.On("PLAYER_LOGIN", function()
    C_Timer.NewTicker(HEARTBEAT, function() SendStatus(true) end)
end)

ns.On("PLAYER_LOGOUT", function()
    for _, name in ipairs(Sync.Brothers()) do
        if Sync.IsOnline(name) then Comm.SendNow({ t = "BYE" }, "WHISPER", name) end
    end
end)

-------------------------------------------------------------------------------
-- Pokes
-------------------------------------------------------------------------------
local pokedAt, pokedBy = {}, {}

function ns.Poke(name, text)
    name = ns.NormalizeName(name)
    if not name or not ns.People.IsKin(name) then
        return ns.Print("Poke whom? /fost poke First Last [message] (must be in your brother list)")
    end
    -- match the stored spelling
    for _, n in ipairs(Sync.Brothers()) do
        if ns.NameKey(n) == ns.NameKey(name) then name = n end
    end
    -- if he's online on another of his characters, poke that one
    if not Sync.IsOnline(name) then
        for _, c in ipairs(ns.People.SiblingChars(name)) do
            if Sync.IsOnline(c) then name = c break end
        end
    end
    if pokedAt[name] and GetTime() - pokedAt[name] < POKE_COOLDOWN then
        return ns.Print("Easy! You just poked %s.", ns.People.DisplayName(name))
    end
    pokedAt[name] = GetTime()
    text = text and text:gsub("|", ""):sub(1, 80) or nil
    if text == "" then text = nil end
    Sync.SendTo(name, { t = "POKE", m = text })
    if Sync.IsOnline(name) then
        ns.Print("You poke %s.", ns.People.DisplayName(name))
    else
        ns.Print("Poke sent to %s (not seen online with the addon, so it may not arrive).", ns.People.DisplayName(name))
    end
end

Comm.On("POKE", function(msg, sender)
    local name = Sync.From(sender)
    if not name then return end
    if ns.db.settings.pokes == false then return end
    if pokedBy[name] and GetTime() - pokedBy[name] < POKE_RECEIVE_LIMIT then return end
    pokedBy[name] = GetTime()
    local text = ("%s pokes you!"):format(ns.People.DisplayName(name))
    local m = type(msg.m) == "string" and msg.m:gsub("|", ""):sub(1, 80) or nil
    ns.Notify(text, "poke", { detail = m and ('"' .. m .. '"') or nil, sound = "poke", force = true })
end)
