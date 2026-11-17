-- Fostbraedr: diagnostics for things we can't know without the live client.
--
-- /fost loottest: dumps the game's Loot History (C_LootHistory) and reports which
-- values are readable and which are secret. Run it after a dungeon with item rolls,
-- once inside and once after leaving, to see whether roll tracking can use it.
local ADDON, ns = ...

local MAX_LINES = 40

-- Render a value for printing without ever touching a secret's contents.
local function Show(v)
    if v == nil then return "nil" end
    if ns.IsSecret(v) then return "|cffff6060<secret>|r" end
    return tostring(v)
end

function ns.LootTest()
    local lines = 0
    local function Out(fmt, ...)
        lines = lines + 1
        if lines <= MAX_LINES then ns.Print(fmt, ...) end
    end

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
    if lines > MAX_LINES then ns.Print("... %d more lines not shown.", lines - MAX_LINES) end
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

function ns.EJTest(filter)
    local lines = 0
    local function Out(fmt, ...)
        lines = lines + 1
        if lines <= MAX_LINES then ns.Print(fmt, ...) end
    end
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
    if lines > MAX_LINES then ns.Print("... %d more lines not shown.", lines - MAX_LINES) end
end
