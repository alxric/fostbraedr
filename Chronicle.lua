-- Fostbraedr: chronicle data model and local event recording.
--
-- Entry (stored in FostbraedrDB.entries[id], synced later as-is):
--   id     = author .. "#" .. n      unique across the family
--   author = "First Last"            character that recorded it
--   n      = per-author counter      1, 2, 3, ...
--   time   = server epoch seconds
--   kind   = "level" | "death" | "boss" | "loot" | "manual" | "tally" | "roll" | "rollwin"
--   plus kind-specific fields (level, zone, name, link, text, with, ...)
--
-- "tally" entries carry aggregated stats (quests, gold, minutes played) and are
-- written every 15 minutes and at logout. "roll" (our own item roll: roll,
-- rollType, link) and "rollwin" (item roll we won: link) feed the Rivalry tab.
-- None of these three show in the timeline.
local ADDON, ns = ...

local TALLY_INTERVAL = 15 * 60

-------------------------------------------------------------------------------
-- Entries
-------------------------------------------------------------------------------
function ns.AddEntry(kind, fields)
    local me = ns.me or ns.PlayerFullName()
    if not me then return end
    local db = ns.db
    local n = (db.counters[me] or 0) + 1
    db.counters[me] = n
    local e = fields or {}
    e.id, e.author, e.n, e.time, e.kind = me .. "#" .. n, me, n, GetServerTime(), kind
    db.entries[e.id] = e
    ns.Fire("ENTRY_ADDED", e)
    return e
end

-- All entries sorted oldest first (callers reverse for display).
function ns.SortedEntries()
    local list = {}
    for _, e in pairs(ns.db.entries) do list[#list + 1] = e end
    table.sort(list, function(a, b)
        if a.time ~= b.time then return a.time < b.time end
        if a.author ~= b.author then return a.author < b.author end
        return a.n < b.n
    end)
    return list
end

function ns.FirstName(fullName)
    return fullName and fullName:match("^(%S+)") or "?"
end

-------------------------------------------------------------------------------
-- Group helpers
-------------------------------------------------------------------------------
-- Names of brothers currently in our party/raid.
function ns.BrothersInGroup()
    local found = {}
    if not IsInGroup() then return found end
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
    for i = 1, count do
        local unit = prefix .. i
        if not UnitIsUnit(unit, "player") then
            local name = ns.UnitFullCharName(unit)
            if name and ns.People.IsKin(name) then found[#found + 1] = name end
        end
    end
    return found
end

local function Zone()
    local zone = GetRealZoneText()
    if not zone or ns.IsSecret(zone) or zone == "" then return nil end
    return zone
end
ns.Zone = Zone

-------------------------------------------------------------------------------
-- Recording
-------------------------------------------------------------------------------
ns.On("PLAYER_LEVEL_UP", function(level)
    if ns.IsSecret(level) then level = nil end
    ns.AddEntry("level", { level = level or (UnitLevel("player") + 1), zone = Zone() })
end)

ns.On("PLAYER_DEAD", function()
    local with = ns.BrothersInGroup()
    ns.AddEntry("death", { level = UnitLevel("player"), zone = Zone(), with = #with > 0 and with or nil })
end)

ns.On("ENCOUNTER_END", function(encounterID, encounterName, difficultyID, groupSize, success)
    if ns.IsSecret(success) or success ~= 1 then return end
    if ns.IsSecret(encounterName) then encounterName = nil end
    if ns.IsSecret(encounterID) then encounterID = nil end
    local with = ns.BrothersInGroup()
    ns.AddEntry("boss", {
        name = encounterName or "a boss",
        encounter = encounterID,
        zone = Zone(),
        with = #with > 0 and with or nil,
    })
end)

-- Notable loot: parse our own loot chat lines into item links.
local SELF_LOOT = { "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF" }
-- Item rolls: "Need Roll - %d for %s by %s" etc. (roll, item, player)
local ROLLS = {
    { key = "LOOT_ROLL_ROLLED_NEED", type = "need" },
    { key = "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", type = "need" },
    { key = "LOOT_ROLL_ROLLED_GREED", type = "greed" },
    { key = "LOOT_ROLL_ROLLED_DE", type = "disenchant" },
    { key = "LOOT_ROLL_ROLLED_TRANSMOG", type = "transmog" },
}

local function IsMyName(name)
    if not name or not ns.me then return false end
    if name == YOU then return true end
    local key = ns.NameKey(name)
    return key == ns.NameKey(ns.me) or key == ns.NameKey(ns.FirstName(ns.me))
end

local function ItemLink(text)
    return text and text:match("(|c[^|]*|Hitem:.-|h|r)")
end

-- Returns true if the line was an item roll or roll win (and was handled).
local function HandleRollLine(text)
    local won = ns.MatchFormat(text, LOOT_ROLL_YOU_WON)
    if won then
        ns.AddEntry("rollwin", { link = ItemLink(won[1]) or won[1], zone = Zone() })
        return true
    end
    for _, r in ipairs(ROLLS) do
        local args = ns.MatchFormat(text, _G[r.key])
        if args then
            local roll = tonumber(args[1])
            if roll and IsMyName(args[3]) then
                ns.AddEntry("roll", { roll = roll, rollType = r.type, link = ItemLink(args[2]) })
            end
            return true
        end
    end
    return false
end

local function IsNotable(quality, classID, subclassID)
    local misc = Enum.ItemClass and Enum.ItemClass.Miscellaneous or 15
    local mount = Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.Mount or 5
    if classID == misc and subclassID == mount then
        return true
    end
    return quality and quality >= (ns.db.settings.lootQuality or 4)
end

ns.On("CHAT_MSG_LOOT", function(text)
    if type(text) ~= "string" or ns.IsSecret(text) then return end
    if HandleRollLine(text) then return end
    local matched
    for _, key in ipairs(SELF_LOOT) do
        if ns.MatchFormat(text, _G[key]) then matched = true break end
    end
    if not matched then return end
    local link = ItemLink(text)
    local itemID = text:match("|Hitem:(%d+)")
    if not (link and itemID) then return end
    local zone = Zone()
    local item = Item:CreateFromItemID(tonumber(itemID))
    item:ContinueOnItemLoad(function()
        local _, _, quality, _, _, _, _, _, _, _, _, classID, subclassID = C_Item.GetItemInfo(link)
        if IsNotable(quality, classID, subclassID) then
            local with = ns.BrothersInGroup()
            ns.AddEntry("loot", { link = link, quality = quality, zone = zone, with = #with > 0 and with or nil })
        end
    end)
end)

-- Stats that go into tally entries.
local function Pending()
    return ns.db.pending
end

local function Bump(key, amount)
    local p = Pending()
    p[key] = (p[key] or 0) + amount
end

ns.On("QUEST_TURNED_IN", function()
    Bump("quests", 1)
end)

-- Gold earned: positive money changes while no merchant/mail/trade/AH/bank window is
-- open (quest rewards and looted coin count; selling and mail don't).
local lastMoney
local openWindows = {}
local function ExcludedTypes()
    local T = Enum.PlayerInteractionType or {}
    local set = {}
    for _, k in ipairs({ "Merchant", "MailInfo", "TradePartner", "Auctioneer", "Banker", "GuildBanker", "BlackMarketAuctioneer" }) do
        if T[k] then set[T[k]] = true end
    end
    return set
end
local excluded
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(t)
    excluded = excluded or ExcludedTypes()
    if excluded[t] then openWindows[t] = true end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(t)
    openWindows[t] = nil
end)
ns.On("PLAYER_MONEY", function()
    local money = GetMoney()
    if lastMoney and money > lastMoney and next(openWindows) == nil then
        Bump("gold", money - lastMoney) -- copper
    end
    lastMoney = money
end)

local function FlushTally()
    local p = Pending()
    if next(p) == nil then return end
    local fields = {}
    for k, v in pairs(p) do fields[k] = v end
    wipe(p)
    ns.AddEntry("tally", fields)
end
ns.FlushTally = FlushTally

-- Played / together time, counted per minute.
local function MinuteTick()
    Bump("minutes", 1)
    if #ns.BrothersInGroup() > 0 then Bump("together", 1) end
end

ns.On("PLAYER_LOGIN", function()
    lastMoney = GetMoney()
    C_Timer.NewTicker(60, MinuteTick)
    C_Timer.NewTicker(TALLY_INTERVAL, FlushTally)
end)

ns.On("PLAYER_LOGOUT", FlushTally)

-- Totals per author from tally entries (plus our not-yet-flushed stats).
function ns.StatTotals(since)
    local totals = {}
    local function add(author, src)
        local t = totals[author] or {}
        totals[author] = t
        for _, k in ipairs({ "quests", "gold", "minutes", "together" }) do
            t[k] = (t[k] or 0) + (src[k] or 0)
        end
    end
    for _, e in pairs(ns.db.entries) do
        if e.kind == "tally" and (not since or e.time >= since) then add(e.author, e) end
    end
    if ns.me then add(ns.me, ns.db.pending) end
    return totals
end
