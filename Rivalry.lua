-- Fostbraedr: rivalry statistics and weekly awards (computed from synced entries).
local ADDON, ns = ...

local WEEK = 7 * 24 * 3600
local MIN_ROLLS_FOR_LUCK = 3

-- Start of the current game week (the weekly reset), shifted back `weeksAgo` weeks.
function ns.WeekStart(weeksAgo)
    local now = GetServerTime()
    local start
    local fn = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
    local ok, secs = false, nil
    if fn then ok, secs = pcall(fn) end
    if ok and type(secs) == "number" and secs > 0 and secs <= WEEK then
        start = now + secs - WEEK
    else
        -- fallback: Monday 00:00 local time
        local t = date("*t", now)
        local daysSinceMonday = (t.wday + 5) % 7
        start = now - daysSinceMonday * 86400 - t.hour * 3600 - t.min * 60 - t.sec
    end
    return start - (weeksAgo or 0) * WEEK
end

local function NewStats()
    return { deaths = 0, quests = 0, gold = 0, minutes = 0, together = 0, bosses = 0, loot = 0,
             rolls = 0, rollSum = 0, rollWins = 0 }
end

local function ItemID(link)
    return type(link) == "string" and link:match("item:(%d+)") or nil
end

local function IsHistoryWin(e)
    return e.src == "history" or e.boss ~= nil
end

-- An old chat-recorded win that the Loot History also recorded (same author and
-- item within a day)?
local function DuplicateChatWin(e, historyWins)
    if IsHistoryWin(e) then return false end
    local id = ItemID(e.link)
    local times = id and historyWins[e.author .. "|" .. id]
    for _, t in ipairs(times or {}) do
        if math.abs(t - (e.time or 0)) < 24 * 3600 then return true end
    end
    return false
end

-- For reports: is this win counted by Rivalry?
function ns.WinCounted(e)
    local historyWins = {}
    for _, x in pairs(ns.db.entries) do
        if x.kind == "rollwin" and x.author == e.author and IsHistoryWin(x) then
            local id = ItemID(x.link)
            if id then
                local key = x.author .. "|" .. id
                historyWins[key] = historyWins[key] or {}
                table.insert(historyWins[key], x.time or 0)
            end
        end
    end
    return not DuplicateChatWin(e, historyWins)
end

-- Stats per person for entries with from <= time < to (nil = unbounded).
-- A person's characters are combined (see People.lua); characters not linked to
-- anyone count on their own. Returns stats keyed by People.GroupKey (each with
-- .name, .isMe, .level) and a list of keys sorted by name.
function ns.ComputeRivalry(from, to)
    local P = ns.People
    local stats = {}
    local function S(char)
        local key = P.GroupKey(char)
        local s = stats[key]
        if not s then
            s = NewStats()
            s.name = P.KeyName(key, char)
            stats[key] = s
        end
        return s
    end
    -- Wins from the Loot History (they carry a boss) by author and item, so the
    -- same wins recorded from chat by versions before 0.3.1 aren't counted twice.
    local historyWins = {}
    for _, e in pairs(ns.db.entries) do
        if e.kind == "rollwin" and IsHistoryWin(e) then
            local id = ItemID(e.link)
            if id then
                local key = e.author .. "|" .. id
                historyWins[key] = historyWins[key] or {}
                table.insert(historyWins[key], e.time or 0)
            end
        end
    end
    local function Level(char, level)
        local s = S(char)
        if type(level) == "number" and (s.level or 0) < level then s.level = level end
    end
    for _, e in pairs(ns.db.entries) do
        local t = e.time or 0
        if e.kind == "level" and (not to or t < to) then Level(e.author, e.level) end
        if (not from or t >= from) and (not to or t < to) then
            local k = e.kind
            if k == "death" then S(e.author).deaths = S(e.author).deaths + 1
            elseif k == "boss" then S(e.author).bosses = S(e.author).bosses + 1
            elseif k == "loot" then
                if ns.IsEpicLoot(e) then S(e.author).loot = S(e.author).loot + 1 end
            elseif k == "rollwin" then
                if not DuplicateChatWin(e, historyWins) then S(e.author).rollWins = S(e.author).rollWins + 1 end
            elseif k == "roll" and type(e.roll) == "number" then
                local s = S(e.author)
                s.rolls, s.rollSum = s.rolls + 1, s.rollSum + e.roll
            elseif k == "tally" then
                local s = S(e.author)
                for _, f in ipairs({ "quests", "gold", "minutes", "together" }) do
                    if type(e[f]) == "number" then s[f] = s[f] + e[f] end
                end
            end
        end
    end
    -- our stats not yet written to a tally entry
    local now = GetServerTime()
    if ns.me and (not from or now >= from) and (not to or now < to) then
        local s = S(ns.me)
        for _, f in ipairs({ "quests", "gold", "minutes", "together" }) do
            s[f] = s[f] + (ns.db.pending[f] or 0)
        end
    end
    -- brothers and me always listed, even with nothing this period
    if ns.me then
        Level(ns.me, UnitLevel("player"))
        S(ns.me).isMe = true
    end
    for _, c in ipairs(P.KinChars()) do
        local peer = ns.db.peers[c]
        Level(c, peer and peer.level)
    end

    local keys = {}
    for key, st in pairs(stats) do
        st.luck = st.rolls >= MIN_ROLLS_FOR_LUCK and (st.rollSum / st.rolls) or nil
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return stats[a].name:lower() < stats[b].name:lower() end)
    return stats, keys
end

-- Awards: highest value wins; ties share the award; zero means nobody.
ns.AWARDS = {
    { key = "deaths",   title = "Most Deaths",   icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
      fmt = function(v) return v .. (v == 1 and " death" or " deaths") end },
    { key = "gold",     title = "Loot Goblin",   icon = "Interface\\Icons\\INV_Misc_Coin_02",
      fmt = function(v) return ns.FormatMoney(v) end },
    { key = "quests",   title = "Quest Machine", icon = "Interface\\GossipFrame\\AvailableQuestIcon",
      fmt = function(v) return v .. (v == 1 and " quest" or " quests") end },
    { key = "luck",     title = "Luckiest",      icon = "Interface\\Icons\\INV_Misc_Dice_01",
      fmt = function(v) return ("%.1f avg item roll"):format(v) end },
    { key = "rollWins", title = "Roll Winner",   icon = "Interface\\Icons\\INV_Misc_Bag_10",
      fmt = function(v) return v .. (v == 1 and " item roll won" or " item rolls won") end },
    { key = "bosses",   title = "Boss Slayer",   icon = "Interface\\Icons\\INV_Sword_04",
      fmt = function(v) return v .. (v == 1 and " boss" or " bosses") end },
}

-- Returns { [award.key] = { winners = {statsKey, ...}, value = v } } (winners empty if nobody).
function ns.ComputeAwards(stats)
    local result = {}
    for _, a in ipairs(ns.AWARDS) do
        local best, winners = nil, {}
        for author, s in pairs(stats) do
            local v = s[a.key]
            if v and v > 0 then
                if not best or v > best then
                    best, winners = v, { author }
                elseif v == best then
                    winners[#winners + 1] = author
                end
            end
        end
        table.sort(winners, function(x, y) return stats[x].name < stats[y].name end)
        result[a.key] = { winners = winners, value = best }
    end
    return result
end
