-- Fostbraedr: diagnostics for things we can't know without the live client.
--
-- /fost loottest: dumps the game's Loot History (C_LootHistory) and reports which
-- values are readable and which are secret. Run it after a dungeon with item rolls,
-- once inside and once after leaving, to see whether roll tracking can use it.
local ADDON, ns = ...

-- Run a test body that writes lines with Out(fmt, ...), then show everything in
-- the copyable text window (also when the body stops early or errors).
local function RunInWindow(title, body, ...)
    local buffer = {}
    local function Out(fmt, ...)
        buffer[#buffer + 1] = select("#", ...) > 0 and fmt:format(...) or tostring(fmt)
    end
    local ok, err = pcall(body, Out, ...)
    if not ok then Out("Error: %s", tostring(err)) end
    ns.ShowTextWindow(title, table.concat(buffer, "\n"))
    ns.Print("%s: output is in the window (Select all, then Ctrl+C).", title)
end

-- Render a value for printing without ever touching a secret's contents.
local function Show(v)
    if v == nil then return "nil" end
    if ns.IsSecret(v) then return "|cffff6060<secret>|r" end
    return tostring(v)
end

local function LootTestBody(Out)

    local inInstance = IsInInstance()
    Out("Loot test: in instance=%s, in combat=%s, issecretvalue exists=%s",
        Show(inInstance), tostring(InCombatLockdown()), tostring(issecretvalue ~= nil))

    local LH = C_LootHistory
    if not LH then return Out("C_LootHistory doesn't exist in this client.") end
    local fns = {}
    for _, f in ipairs({ "GetAllEncounterInfos", "GetSortedDropsForEncounter", "GetSortedInfoForDrop", "GetInfoForEncounter", "GetLootHistoryTime" }) do
        fns[#fns + 1] = f .. (LH[f] and "" or " (missing)")
    end
    Out("Functions: %s", table.concat(fns, ", "))
    if not (LH.GetAllEncounterInfos and LH.GetSortedDropsForEncounter) then return end

    local ok, encounters = pcall(LH.GetAllEncounterInfos)
    if not ok then return Out("GetAllEncounterInfos error: %s", tostring(encounters)) end
    if ns.IsSecret(encounters) then return Out("GetAllEncounterInfos returned a secret.") end
    encounters = encounters or {}
    Out("%d encounter(s) in Loot History.", #encounters)

    for _, enc in ipairs(encounters) do
        Out("Encounter %s: %s", Show(enc.encounterID), Show(enc.encounterName))
        local ok2, drops = pcall(LH.GetSortedDropsForEncounter, enc.encounterID)
        if not ok2 then
            Out("  GetSortedDropsForEncounter error: %s", tostring(drops))
        elseif ns.IsSecret(drops) then
            Out("  drops: <secret>")
        else
            for _, drop in ipairs(drops or {}) do
                local info = drop
                if LH.GetSortedInfoForDrop and not ns.IsSecret(drop.lootListID) and drop.lootListID then
                    local ok3, full = pcall(LH.GetSortedInfoForDrop, enc.encounterID, drop.lootListID)
                    if ok3 and full then info = full end
                end
                local winner = info.winner
                -- never branch on these fields: testing a secret's truth value is an error
                Out("  %s  winner: %s (%s), allPassed=%s", Show(info.itemHyperlink),
                    type(winner) == "table" and Show(winner.playerName) or Show(winner),
                    type(winner) == "table" and Show(winner.roll) or "-", Show(info.allPassed))
                local rolls = info.rollInfos
                if ns.IsSecret(rolls) then
                    Out("    rollInfos: <secret>")
                else
                    for _, r in ipairs(rolls or {}) do
                        Out("    %s rolled %s, state %s, isSelf=%s", Show(r.playerName), Show(r.roll), Show(r.state), Show(r.isSelf))
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- /fost ejtest [dungeon name]: is the Adventure Guide (Encounter Journal) loot
-- data available in Forever? Lists tiers and dungeons, then one dungeon's bosses
-- and loot with slot, required level and stats. Also reports spec/talent APIs.
-------------------------------------------------------------------------------
local function Has(name)
    local v = _G
    for part in name:gmatch("[^%.]+") do
        v = type(v) == "table" and v[part] or nil
    end
    return v ~= nil
end

local function EJTestBody(Out, filter)
    filter = filter and filter ~= "" and filter:lower() or nil
    -- some clients only expose the EJ API once the Adventure Guide module is loaded
    if not EJ_GetNumTiers and C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    end

    local apis = {}
    for _, f in ipairs({ "EJ_GetNumTiers", "EJ_SelectTier", "EJ_GetInstanceByIndex", "EJ_SelectInstance",
                         "EJ_GetEncounterInfoByIndex", "EJ_SelectEncounter", "EJ_GetNumLoot", "EJ_SetLootFilter",
                         "C_EncounterJournal.GetLootInfoByIndex", "EJ_GetLootInfoByIndex", "C_Item.GetItemStats",
                         "GetSpecialization", "C_SpecializationInfo.GetSpecialization", "GetNumTalentTabs",
                         "GetTalentTabInfo", "C_ClassTalents" }) do
        apis[#apis + 1] = f .. (Has(f) and "" or " |cffff6060(missing)|r")
    end
    Out("APIs: %s", table.concat(apis, ", "))
    if not (EJ_GetNumTiers and EJ_GetInstanceByIndex and EJ_SelectInstance) then
        return Out("No Encounter Journal API: the BiS idea would need another data source.")
    end

    local okT, numTiers = pcall(EJ_GetNumTiers)
    Out("Tiers: %s", tostring(okT and numTiers or numTiers))
    local chosen
    for tier = 1, (okT and numTiers or 0) do
        pcall(EJ_SelectTier, tier)
        local names = {}
        for _, isRaid in ipairs({ false, true }) do
            for i = 1, 60 do
                local ok, id, name = pcall(EJ_GetInstanceByIndex, i, isRaid)
                if not ok or not id then break end
                names[#names + 1] = (isRaid and "[R] " or "") .. tostring(name)
                if not chosen and (not filter or tostring(name):lower():find(filter, 1, true)) and not isRaid then
                    chosen = { id = id, name = name, tier = tier }
                end
            end
        end
        local tierName = EJ_GetTierInfo and select(1, EJ_GetTierInfo(tier)) or ("tier " .. tier)
        Out("Tier %d (%s): %d instances: %s", tier, tostring(tierName), #names, table.concat(names, ", "):sub(1, 220))
    end
    if not chosen then return Out("No dungeon found%s.", filter and (" matching '" .. filter .. "'") or "") end

    pcall(EJ_SelectTier, chosen.tier)
    pcall(EJ_SelectInstance, chosen.id)
    if EJ_SetLootFilter then pcall(EJ_SetLootFilter, 0, 0) end -- all classes
    Out("Dungeon: %s (id %s)", tostring(chosen.name), tostring(chosen.id))
    local bosses = {}
    for i = 1, 20 do
        local ok, name = pcall(EJ_GetEncounterInfoByIndex, i, chosen.id)
        if not ok or not name then break end
        bosses[#bosses + 1] = name
    end
    Out("Bosses (%d): %s", #bosses, table.concat(bosses, ", "))

    local okN, numLoot = pcall(EJ_GetNumLoot)
    Out("Loot entries: %s %s", tostring(okN and numLoot or numLoot),
        (okN and numLoot == 0) and "(data may load async: run the command again in a few seconds)" or "")
    local getLoot = (C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex) or EJ_GetLootInfoByIndex
    for i = 1, math.min(okN and numLoot or 0, 8) do
        local ok, info = pcall(getLoot, i)
        if ok and type(info) == "table" then
            local link = info.link
            local minLevel, equipLoc
            if link then
                local _, _, _, _, ml, _, _, _, el = C_Item.GetItemInfo(link)
                minLevel, equipLoc = ml, el
            end
            local stats = {}
            if link and C_Item.GetItemStats then
                local okS, st = pcall(C_Item.GetItemStats, link)
                if okS and type(st) == "table" then
                    for k, v in pairs(st) do stats[#stats + 1] = (_G[k] or k) .. " " .. tostring(v) end
                end
            end
            Out("  %s | %s | req %s | %s | %s", tostring(link or info.name), tostring(info.slot or equipLoc),
                tostring(minLevel), tostring(info.encounterID), table.concat(stats, ", "):sub(1, 120))
        elseif ok then
            Out("  loot %d: %s", i, tostring(info))
        else
            Out("  loot %d error: %s", i, tostring(info))
        end
    end
end

function ns.LootTest() RunInWindow("Loot test", LootTestBody) end
function ns.EJTest(filter) RunInWindow("Adventure Guide test", EJTestBody, filter) end

-------------------------------------------------------------------------------
-- /fost dbtest [dungeon]: is the ForeverDB data addon installed, and what does
-- its data look like? Shows meta, every table with its size and a sample entry,
-- then tries "what drops in <dungeon>" (default: Scarlet Monastery).
-------------------------------------------------------------------------------
-- Compact, bounded description of any value (never touches secrets: this is
-- static addon data).
local function Describe(v, depth, budget)
    depth, budget = depth or 0, budget or { n = 0 }
    budget.n = budget.n + 1
    if budget.n > 60 then return "..." end
    local t = type(v)
    if t == "string" then return ("%q"):format(#v > 40 and (v:sub(1, 40) .. "...") or v) end
    if t ~= "table" then return tostring(v) end
    if depth >= 2 then return "{...}" end
    local parts, i = {}, 0
    for k, val in pairs(v) do
        i = i + 1
        if i > 8 then parts[#parts + 1] = "..." break end
        parts[#parts + 1] = tostring(k) .. "=" .. Describe(val, depth + 1, budget)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function ns.LoadForeverDB()
    if type(ForeverDB) == "table" then return ForeverDB end
    if C_AddOns and C_AddOns.LoadAddOn then
        local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, "ForeverDB")
        if ok and type(ForeverDB) == "table" then return ForeverDB end
        return nil, ok and tostring(reason or loaded) or tostring(loaded)
    end
    return nil, "C_AddOns.LoadAddOn missing"
end

local function DBTestBody(Out, dungeon)
    dungeon = (dungeon and dungeon ~= "") and dungeon:lower() or "scarlet monastery"
    local db, why = ns.LoadForeverDB()
    if not db then
        Out("No ForeverDB data table found (LoadAddOn said: %s).", tostring(why))
        -- what's actually installed / defined?
        Out("")
        Out("Installed addons with 'forever' or 'db' in their folder name:")
        local A = C_AddOns
        local n = A and A.GetNumAddOns and A.GetNumAddOns() or 0
        for i = 1, n do
            local name, title, _, loadable, reason = A.GetAddOnInfo(i)
            local lname = tostring(name):lower()
            if lname:find("forever", 1, true) or lname:find("db", 1, true) then
                local loaded = A.IsAddOnLoaded and A.IsAddOnLoaded(i)
                local lod = A.IsAddOnLoadOnDemand and A.IsAddOnLoadOnDemand(i)
                Out("  %s (title: %s) loaded=%s loadOnDemand=%s loadable=%s reason=%s", tostring(name),
                    tostring(title), tostring(loaded), tostring(lod), tostring(loadable), tostring(reason))
            end
        end
        Out("")
        Out("Global names containing 'forever' (other than our own):")
        local globals = {}
        for k, v in pairs(_G) do
            if type(k) == "string" and k:lower():find("forever", 1, true) and not k:find("^Fostbraedr") then
                globals[#globals + 1] = ("%s (%s)"):format(k, type(v))
            end
        end
        table.sort(globals)
        for i, g in ipairs(globals) do
            if i > 60 then Out("  ... %d more", #globals - 60) break end
            Out("  %s", g)
        end
        if #globals == 0 then Out("  none") end
        return
    end
    Out("ForeverDB loaded. meta: %s", Describe(db.meta))
    Out("")
    Out("Tables:")
    local names = {}
    for k in pairs(db) do names[#names + 1] = tostring(k) end
    table.sort(names)
    for _, k in ipairs(names) do
        local v = db[k]
        if type(v) == "table" then
            local sk, sv = next(v)
            Out("  %s: %d entries, e.g. [%s] = %s", k, Count(v), tostring(sk), Describe(sv))
        else
            Out("  %s = %s", k, Describe(v))
        end
    end

    -- Try: what drops in <dungeon>?
    Out("")
    Out("Looking for dungeon '%s':", dungeon)
    local areas = {}
    for areaId, d in pairs(db.dng or {}) do
        local name = type(d) == "table" and d[1] or d
        if type(name) == "string" and name:lower():find(dungeon, 1, true) then
            areas[areaId] = name
            Out("  dng[%s] = %s", tostring(areaId), Describe(d))
        end
    end
    if not next(areas) then return Out("  no dungeon with that name in 'dng'.") end

    -- npcs/objects inside it
    local inside = {}
    for key, list in pairs(db.ind or {}) do
        local ids = type(list) == "table" and list or { list }
        for _, a in pairs(ids) do
            if areas[a] then inside[key] = true end
        end
    end
    Out("  %d npcs/objects inside (from 'ind')", Count(inside))

    -- items dropped by them (drop[item] = {source, chance, source, chance, ...})
    local found = 0
    for itemId, srcs in pairs(db.drop or {}) do
        if type(srcs) == "table" then
            for i = 1, #srcs, 2 do
                local src = srcs[i]
                local key = type(src) == "number" and ("c" .. src) or tostring(src)
                if inside[key] or inside[src] then
                    found = found + 1
                    if found <= 40 then
                        local it = db.item and db.item[itemId]
                        local npcId = tonumber(tostring(key):match("%d+"))
                        local npc = db.npc and npcId and db.npc[npcId]
                        Out("  item %s %s from %s (%s), chance %s/10000", tostring(itemId), Describe(it),
                            tostring(key), Describe(npc), tostring(srcs[i + 1]))
                    end
                    break
                end
            end
        end
    end
    Out("  %d items drop inside%s", found, found > 40 and " (first 40 shown)" or "")
end

function ns.DBTest(dungeon) RunInWindow("ForeverDB test", DBTestBody, dungeon) end
