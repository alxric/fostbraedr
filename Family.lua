-- Fostbraedr: live family status, heartbeat, bye, and pokes.
--
-- Messages:
--   ST   { t, st = status, hw } status changed, or 4-minute heartbeat (with hw, see Sync)
--        st.xpLeft: whole % of this level's XP still to go (nil at max level)
--        st.ilvl10: average item level of equipped gear x 10, as a whole number
--        st.tiLeft, st.tiN: % left once the tiN completed quests are handed in
--                           (0 = enough to level; both nil without completed quests)
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

-- Whole % of this level's XP still to go, 1-100; nil at max level or unreadable.
-- Worked out from the % done, rounded down, so it never says 0% before you ding.
function ns.MyXPLeft()
    if not (UnitXP and UnitXPMax) then return nil end
    local xp, max = NotSecret(UnitXP("player")), NotSecret(UnitXPMax("player"))
    if type(xp) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
    return 100 - math.floor(xp * 100 / max)
end

-- Average item level of what you're wearing, or nil if it can't be read.
-- GetAverageItemLevel() when the client has it; else worked out like the game
-- does: 16 slots (shirt and tabard don't count), ranged only if worn, and a
-- two-hander counts for the empty off hand too.
local ILVL_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local function SlotItemLevel(slot)
    local link = NotSecret(GetInventoryItemLink("player", slot))
    if type(link) ~= "string" then return nil end
    local ilvl
    if C_Item and C_Item.GetDetailedItemLevelInfo then ilvl = NotSecret(C_Item.GetDetailedItemLevelInfo(link)) end
    if type(ilvl) ~= "number" and C_Item and C_Item.GetItemInfo then ilvl = NotSecret((select(4, C_Item.GetItemInfo(link)))) end
    return type(ilvl) == "number" and ilvl or nil
end
ns.SlotItemLevel = SlotItemLevel

function ns.MyItemLevel()
    if GetAverageItemLevel then
        local _, equipped = GetAverageItemLevel()
        equipped = NotSecret(equipped)
        if type(equipped) == "number" and equipped > 0 then return equipped, "GetAverageItemLevel" end
    end
    if not GetInventoryItemLink then return nil end
    local sum, slots, any = 0, #ILVL_SLOTS, false
    for _, slot in ipairs(ILVL_SLOTS) do
        local ilvl = SlotItemLevel(slot)
        if ilvl then sum, any = sum + ilvl, true end
    end
    local main = SlotItemLevel(16)
    if main and not GetInventoryItemLink("player", 17) then
        local equipLoc = C_Item and C_Item.GetItemInventoryTypeByID and NotSecret(C_Item.GetItemInventoryTypeByID(GetInventoryItemLink("player", 16)))
        -- 17 = two-hand (Enum.InventoryType.IndexWeapontwohandType)
        if equipLoc == 17 then sum = sum + main end
    end
    local ranged = SlotItemLevel(18)
    if ranged then sum, slots = sum + ranged, slots + 1 end
    if not any then return nil end
    return sum / slots, "worked out from your slots"
end

-- XP from completed quests in the log that are waiting to be handed in, and how
-- many there are. GetQuestLogRewardXP(questID) is the XP for handing one in.
function ns.TurnInXP()
    local QL = C_QuestLog
    if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo and QL.IsComplete and GetQuestLogRewardXP) then return 0, 0 end
    local total, count = 0, 0
    for i = 1, QL.GetNumQuestLogEntries() or 0 do
        local info = QL.GetInfo(i)
        local id = info and NotSecret(info.questID)
        if id and not NotSecret(info.isHeader) and NotSecret(QL.IsComplete(id)) then
            local xp = NotSecret(GetQuestLogRewardXP(id))
            if type(xp) == "number" and xp > 0 then
                total, count = total + xp, count + 1
            end
        end
    end
    return total, count
end

-- % left once completed quests are handed in (0 = enough to level), and how
-- many quests; nil when there's nothing to hand in or XP can't be read.
function ns.MyTurnInLeft()
    if not (UnitXP and UnitXPMax) then return nil end
    local xp, max = NotSecret(UnitXP("player")), NotSecret(UnitXPMax("player"))
    if type(xp) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
    local bonus, count = ns.TurnInXP()
    if count == 0 then return nil end
    if xp + bonus >= max then return 0, count end
    return 100 - math.floor((xp + bonus) * 100 / max), count
end

-- "37% left to 44  ·  12% after 3 turn-ins" for the Family tab, or "" when unknown.
function ns.XPText(level, xpLeft, tiLeft, tiN)
    level, xpLeft, tiLeft, tiN = tonumber(level), tonumber(xpLeft), tonumber(tiLeft), tonumber(tiN)
    if not (level and xpLeft) then return "" end
    local text = ("%d%% left to %d"):format(xpLeft, level + 1)
    if tiLeft and tiN and tiN > 0 then
        local quests = tiN == 1 and "1 turn-in" or (tiN .. " turn-ins")
        if tiLeft == 0 then
            text = text .. "  \194\183  " .. "|cffffc742" .. ("enough for %d with %s"):format(level + 1, quests) .. "|r"
        else
            text = text .. "  \194\183  " .. ("%d%% after %s"):format(tiLeft, quests)
        end
    end
    return text
end

function ns.MyStatus()
    local _, classFile = UnitClass("player")
    local sub = NotSecret(GetSubZoneText())
    local zone = ns.Zone()
    if sub == "" then sub = nil end
    local st = {
        level = UnitLevel("player"),
        zone = zone and sub and sub ~= zone and (zone .. " - " .. sub) or zone,
        class = classFile,
        activity = ns.MyActivity(),
        status = ns.db.settings.status,
        grouped = IsInGroup() or nil,
        xpLeft = ns.MyXPLeft(),
    }
    local okIlvl, ilvl = pcall(ns.MyItemLevel)
    if okIlvl and ilvl then st.ilvl10 = math.floor(ilvl * 10 + 0.5) end
    -- never let the turn-in sum break the status: it goes into every hello
    local ok, tiLeft, tiN = pcall(ns.MyTurnInLeft)
    if ok then st.tiLeft, st.tiN = tiLeft, tiN end
    return st
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
                      "PLAYER_UNGHOST", "GROUP_ROSTER_UPDATE", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
                      "PLAYER_XP_UPDATE", "QUEST_LOG_UPDATE", "PLAYER_EQUIPMENT_CHANGED" }) do
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
