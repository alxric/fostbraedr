-- Fostbraedr: item rolls from the game's Loot History (C_LootHistory).
--
-- Inside instances, loot chat reaches addons as secret values, so we can't see
-- rolls there. The Loot History, however, is fully readable once we're outside
-- (tested in game): every drop, everyone's roll with its type, and the winner.
-- So we scan it outside instances (on leaving one, and on Loot History updates)
-- and record our own roll ("roll") and our wins ("rollwin"). Brothers' copies do
-- the same for theirs, and sync shares them. db.lootSeen remembers which drops
-- were processed so nothing is counted twice.
local ADDON, ns = ...

local KEEP = 7 * 24 * 3600     -- forget processed drops after a week
local FALLBACK_STATES = { [0] = "need", [1] = "need", [2] = "transmog", [3] = "greed" }

local function Plain(v)
    if v == nil or ns.IsSecret(v) then return nil end
    return v
end

-- Roll state number -> "need" / "greed" / "transmog" / "disenchant" (nil for no roll / pass).
function ns.RollTypeFromState(state)
    if type(state) ~= "number" then return nil end
    local E = Enum.EncounterLootDropRollState
    if E then
        for name, value in pairs(E) do
            if value == state then
                local n = name:lower()
                if n:find("need") then return "need" end
                if n:find("greed") then return "greed" end
                if n:find("transmog") then return "transmog" end
                if n:find("disenchant") then return "disenchant" end
                return nil
            end
        end
    end
    return FALLBACK_STATES[state]
end

-- Does any field we rely on hide behind a secret? Then try again later.
local function HasSecrets(info, rolls)
    if ns.IsSecret(info.winner) or ns.IsSecret(info.allPassed) or ns.IsSecret(rolls) then return true end
    for _, r in ipairs(type(rolls) == "table" and rolls or {}) do
        if ns.IsSecret(r.isSelf) or ns.IsSecret(r.roll) or ns.IsSecret(r.state) then return true end
    end
    if type(info.winner) == "table" and ns.IsSecret(info.winner.isSelf) then return true end
    return false
end

-- Versions before 0.3.1 recorded wins from chat ("You won: ..."); those same
-- wins are in the Loot History. Don't record a win twice for the same item
-- within a day.
local function RecentWinFor(link)
    local id = link and link:match("item:(%d+)")
    if not id then return false end
    local now = GetServerTime()
    for _, e in pairs(ns.db.entries) do
        if e.kind == "rollwin" and e.author == ns.me and e.link and e.link:match("item:(%d+)") == id
            and math.abs(now - (e.time or 0)) < 24 * 3600 then
            return true
        end
    end
    return false
end

-- Process finished drops we haven't seen yet. Returns the number of entries added.
-- With `log` (a function taking a format string), explains what happens to each drop.
function ns.ScanLootHistory(log)
    log = log or function() end
    local LH = C_LootHistory
    if not (ns.db and LH and LH.GetAllEncounterInfos and LH.GetSortedDropsForEncounter) then
        log("Loot History API or saved data not available.")
        return 0
    end
    local inInstance = IsInInstance()
    if inInstance and not ns.IsSecret(inInstance) or ns.IsSecret(inInstance) then
        log("Inside an instance: not reading (values may be hidden). Leave first.")
        return 0
    end
    if not ns.me then
        log("Character name not known yet.")
        return 0
    end
    local seen, added = ns.db.lootSeen, 0
    local ok, encounters = pcall(LH.GetAllEncounterInfos)
    if not ok or type(encounters) ~= "table" or ns.IsSecret(encounters) then
        log("GetAllEncounterInfos failed: %s", tostring(encounters))
        return 0
    end
    log("%d encounter(s) in the Loot History.", #encounters)
    local loggedFields = false
    for _, enc in ipairs(encounters) do
        local encID = Plain(enc.encounterID)
        local okD, drops = false, nil
        if encID then okD, drops = pcall(LH.GetSortedDropsForEncounter, encID) end
        log("Encounter %s (%s): %s", tostring(encID), tostring(Plain(enc.encounterName)),
            okD and (type(drops) == "table" and (#drops .. " drop(s)") or tostring(drops)) or ("error: " .. tostring(drops)))
        if okD and type(drops) == "table" and not ns.IsSecret(drops) then
            for _, d in ipairs(drops) do
                local listID = Plain(d.lootListID)
                local info = d
                if listID and LH.GetSortedInfoForDrop then
                    local okI, full = pcall(LH.GetSortedInfoForDrop, encID, listID)
                    if okI and type(full) == "table" then info = full end
                end
                -- Identify the drop: by its loot list id when the client has one (Forever
                -- doesn't), else by a fingerprint of boss, item, winner and start time.
                local key
                if listID then
                    key = encID .. "/" .. listID .. "/" .. tostring(Plain(info.startTime) or Plain(enc.startTime) or "")
                else
                    local w = type(info.winner) == "table" and info.winner or {}
                    local link = Plain(info.itemHyperlink)
                    local itemID = link and link:match("item:(%d+)")
                    if itemID then
                        key = table.concat({ encID, itemID, tostring(Plain(w.playerName) or ""), tostring(Plain(w.roll) or ""),
                            tostring(Plain(info.startTime) or Plain(enc.startTime) or "") }, "|")
                    end
                end
                if not loggedFields then
                    loggedFields = true
                    local fields = {}
                    for k in pairs(info) do fields[#fields + 1] = tostring(k) end
                    table.sort(fields)
                    log("  (drop fields: %s)", table.concat(fields, ", "))
                end
                local rolls = info.rollInfos
                local what = tostring(Plain(info.itemHyperlink) or ("drop " .. tostring(listID)))
                if not key then
                    log("  %s: can't identify this drop, skipped", what)
                elseif seen[key] then
                    log("  %s: already counted", what)
                elseif HasSecrets(info, rolls) then
                    log("  %s: has hidden values, will retry later", what)
                end
                if key and not seen[key] and not HasSecrets(info, rolls) then
                    local winner = info.winner
                    -- After login the history can list a drop before its rolls have
                    -- loaded: only count it once the roll list is actually there.
                    local hasRolls = type(rolls) == "table" and #rolls > 0
                    local finished = (type(winner) == "table" and hasRolls) or info.allPassed == true
                    if not finished then
                        log("  %s: %s", what, hasRolls and "still being rolled on" or "rolls not loaded yet, will retry")
                    end
                    if finished then
                        seen[key] = GetServerTime()
                        local link = Plain(info.itemHyperlink)
                        local boss = Plain(enc.encounterName)
                        if boss == "" then boss = nil end
                        local mine = false
                        for _, r in ipairs(type(rolls) == "table" and rolls or {}) do
                            if r.isSelf == true and type(r.roll) == "number" then
                                ns.AddEntry("roll", { roll = r.roll, rollType = ns.RollTypeFromState(r.state), link = link, boss = boss, src = "history" })
                                added = added + 1
                                mine = true
                                log("  %s: recorded our roll %d (%s)", what, r.roll, tostring(ns.RollTypeFromState(r.state)))
                            end
                        end
                        if not mine then log("  %s: no roll from us", what) end
                        if type(winner) == "table" and winner.isSelf == true then
                            if RecentWinFor(link) then
                                log("  %s: we won it (already recorded earlier)", what)
                            else
                                ns.AddEntry("rollwin", { link = link, boss = boss, src = "history" })
                                added = added + 1
                                log("  %s: we won it", what)
                            end
                        end
                    end
                end
            end
        end
    end
    return added
end

local pending = false
local function ScanSoon(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 2, function()
        pending = false
        local ok, err = pcall(ns.ScanLootHistory)
        if not ok then geterrorhandler()(err) end
    end)
end
ns.ScanLootHistorySoon = ScanSoon

ns.On("PLAYER_ENTERING_WORLD", function() ScanSoon(3) end)
ns.OnOptional("LOOT_HISTORY_UPDATE_DROP", function() ScanSoon(2) end)
ns.OnOptional("LOOT_HISTORY_UPDATE_ENCOUNTER", function() ScanSoon(2) end)

ns.On("PLAYER_LOGIN", function()
    -- Repair for 0.3.1/0.3.2: drops could be marked as processed before their rolls
    -- had loaded, so nothing was recorded. If we hold no roll of our own at all,
    -- forget what was marked and read the history again.
    local haveRoll = false
    for _, e in pairs(ns.db.entries) do
        if e.kind == "roll" and ns.me and e.author == ns.me then haveRoll = true break end
    end
    if not haveRoll then wipe(ns.db.lootSeen) end
    local now = GetServerTime()
    for key, t in pairs(ns.db.lootSeen) do
        if type(t) ~= "number" or now - t > KEEP then ns.db.lootSeen[key] = nil end
    end
end)

-- /fost rolls: scan now and explain, plus how many roll entries we hold.
function ns.RollsReport()
    local lines = {}
    local function Log(fmt, ...)
        lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or tostring(fmt)
    end
    local ok, added = pcall(ns.ScanLootHistory, Log)
    if not ok then Log("Error: %s", tostring(added)) end
    local rolls, wins, counted = 0, 0, 0
    local winList = {}
    for _, e in pairs(ns.db.entries) do
        if e.author == ns.me and e.kind == "roll" then rolls = rolls + 1 end
        if e.author == ns.me and e.kind == "rollwin" then
            wins = wins + 1
            local isCounted = not ns.WinCounted or ns.WinCounted(e)
            if isCounted then counted = counted + 1 end
            winList[#winList + 1] = { e = e, counted = isCounted }
        end
    end
    table.sort(winList, function(a, b) return (a.e.time or 0) < (b.e.time or 0) end)
    table.insert(lines, 1, ("Fostbraedr %s. Added now: %s. Our roll entries: %d. Win entries: %d, counted in Rivalry: %d."):format(
        tostring(ns.version), tostring(ok and added or 0), rolls, wins, counted))
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Our win entries:"
    for _, w in ipairs(winList) do
        local e = w.e
        lines[#lines + 1] = ("  %s  %s  from %s%s"):format(date("%d %b %H:%M", e.time or 0), tostring(e.link or "?"),
            (e.src == "history" or e.boss) and ("Loot History (" .. tostring(e.boss) .. ")") or "chat (old version)",
            w.counted and "" or "  -> duplicate, not counted")
    end
    ns.ShowTextWindow("Item rolls", table.concat(lines, "\n"))
end
