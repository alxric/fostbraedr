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

-- Process finished drops we haven't seen yet. Returns the number of entries added.
function ns.ScanLootHistory()
    local LH = C_LootHistory
    if not (ns.db and LH and LH.GetAllEncounterInfos and LH.GetSortedDropsForEncounter) then return 0 end
    local inInstance = IsInInstance()
    if inInstance ~= false then return 0 end -- inside (or unknown): values may be hidden
    local seen, added = ns.db.lootSeen, 0
    local ok, encounters = pcall(LH.GetAllEncounterInfos)
    if not ok or type(encounters) ~= "table" or ns.IsSecret(encounters) then return 0 end
    for _, enc in ipairs(encounters) do
        local encID = Plain(enc.encounterID)
        local okD, drops = false, nil
        if encID then okD, drops = pcall(LH.GetSortedDropsForEncounter, encID) end
        if okD and type(drops) == "table" and not ns.IsSecret(drops) then
            for _, d in ipairs(drops) do
                local listID = Plain(d.lootListID)
                local info = d
                if listID and LH.GetSortedInfoForDrop then
                    local okI, full = pcall(LH.GetSortedInfoForDrop, encID, listID)
                    if okI and type(full) == "table" then info = full end
                end
                local key = listID and (encID .. "/" .. listID .. "/" ..
                    tostring(Plain(info.startTime) or Plain(enc.startTime) or ""))
                local rolls = info.rollInfos
                if key and not seen[key] and not HasSecrets(info, rolls) then
                    local winner = info.winner
                    local finished = type(winner) == "table" or info.allPassed == true
                    if finished then
                        seen[key] = GetServerTime()
                        local link = Plain(info.itemHyperlink)
                        local boss = Plain(enc.encounterName)
                        if boss == "" then boss = nil end
                        for _, r in ipairs(type(rolls) == "table" and rolls or {}) do
                            if r.isSelf == true and type(r.roll) == "number" then
                                ns.AddEntry("roll", { roll = r.roll, rollType = ns.RollTypeFromState(r.state), link = link, boss = boss })
                                added = added + 1
                            end
                        end
                        if type(winner) == "table" and winner.isSelf == true then
                            ns.AddEntry("rollwin", { link = link, boss = boss })
                            added = added + 1
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
    local now = GetServerTime()
    for key, t in pairs(ns.db.lootSeen) do
        if type(t) ~= "number" or now - t > KEEP then ns.db.lootSeen[key] = nil end
    end
end)
