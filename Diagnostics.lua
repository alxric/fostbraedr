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
