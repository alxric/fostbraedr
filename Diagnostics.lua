-- Fostbraedr: diagnostics for things we can't know without the live client.
--
-- /fost loottest: dumps the game's Loot History (C_LootHistory) and reports which
-- values are readable and which are secret. Run it after a dungeon with item rolls,
-- once inside and once after leaving, to see whether roll tracking can use it.
--
-- /fost questtest: what the quest and bag APIs return (for the Quest items tab).
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

function ns.LootTest() RunInWindow("Loot test", LootTestBody) end

-------------------------------------------------------------------------------
-- /fost questtest: what the quest log and bag APIs return, so we can check the
-- Quest items tab against the live client. Run it with a few quests in your log
-- and some quest items in your bags.
-------------------------------------------------------------------------------
local function QuestTestBody(Out)
    local QL, C = C_QuestLog or {}, C_Container or {}
    local fns = {}
    for _, f in ipairs({ "GetNumQuestLogEntries", "GetInfo", "GetQuestObjectives", "GetTitleForQuestID",
                         "IsQuestFlaggedCompleted", "GetQuestDifficultyLevel" }) do
        fns[#fns + 1] = f .. (QL[f] and "" or " (missing)")
    end
    Out("C_QuestLog: %s", table.concat(fns, ", "))
    fns = {}
    for _, f in ipairs({ "GetContainerNumSlots", "GetContainerItemInfo", "GetContainerItemQuestInfo", "PickupContainerItem" }) do
        fns[#fns + 1] = f .. (C[f] and "" or " (missing)")
    end
    Out("C_Container: %s", table.concat(fns, ", "))
    Out("GetQuestLogSpecialItemInfo=%s, GetQuestLogQuestText=%s, C_Item.GetItemInfoInstant=%s, bags 0-%s",
        tostring(GetQuestLogSpecialItemInfo ~= nil), tostring(GetQuestLogQuestText ~= nil),
        tostring(C_Item and C_Item.GetItemInfoInstant ~= nil), tostring(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS))
    Out("Your level: %s", Show(UnitLevel("player")))

    Out("")
    Out("QUEST LOG")
    if QL.GetNumQuestLogEntries and QL.GetInfo then
        for i = 1, QL.GetNumQuestLogEntries() or 0 do
            local info = QL.GetInfo(i) or {}
            if info.isHeader then
                Out("[%d] header: %s", i, Show(info.title))
            else
                Out("[%d] %s (id %s, level %s)", i, Show(info.title), Show(info.questID), Show(info.level))
                if QL.GetQuestObjectives and info.questID then
                    for _, o in ipairs(QL.GetQuestObjectives(info.questID) or {}) do
                        Out("    objective: %q type=%s %s/%s", tostring(o.text), Show(o.type), Show(o.numFulfilled), Show(o.numRequired))
                    end
                end
                if GetQuestLogSpecialItemInfo then Out("    usable item: %s", Show((GetQuestLogSpecialItemInfo(i)))) end
                if GetQuestLogQuestText then
                    local desc, obj = GetQuestLogQuestText(i)
                    Out("    text: %s", type(desc) == "string" and not ns.IsSecret(desc) and desc:sub(1, 70) or Show(desc))
                    Out("    objectives text: %s", type(obj) == "string" and not ns.IsSecret(obj) and obj:sub(1, 70) or Show(obj))
                end
            end
        end
    end

    Out("")
    Out("QUEST ITEMS IN BAGS (as the tab sorts them)")
    local scan = ns.QuestItems.Scan()
    if scan.problem then Out("Problem: %s", scan.problem) end
    for _, item in ipairs(scan.items) do
        local q = C.GetContainerItemQuestInfo and C.GetContainerItemQuestInfo(item.bag, item.slot) or {}
        local classID = C_Item and C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(item.itemID))
        local ilvl, minLevel
        if C_Item and C_Item.GetItemInfo then ilvl, minLevel = select(4, C_Item.GetItemInfo(item.itemID)) end
        Out("%s x%d (id %d, bag %d slot %d)", tostring(item.name), item.count, item.itemID, item.bag, item.slot)
        Out("    questInfo: isQuestItem=%s questID=%s isActive=%s, classID=%s, item level=%s, required level=%s",
            Show(q.isQuestItem), Show(q.questID), Show(q.isActive), Show(classID), Show(ilvl), Show(minLevel))
        if C_Item and C_Item.GetItemSpell then Out("    use effect: %s", Show((C_Item.GetItemSpell(item.itemID)))) end
        Out("    -> %s: %s", item.group, item.reason)
    end
    Out("%d quest item(s), %d quest(s) in the log.", #scan.items, scan.quests)
end

function ns.QuestTest() RunInWindow("Quest test", QuestTestBody) end

-------------------------------------------------------------------------------
-- Helpers for /fost dump and /fost globals
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

-------------------------------------------------------------------------------
-- /fost dump <GlobalName>[.key.key]: structure of any global table, two levels
-- deep, with counts and sample entries. /fost globals <text>: every global whose
-- name contains <text>, with type and size.
-------------------------------------------------------------------------------
local function Resolve(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[tonumber(part) or part]
        if v == nil and tonumber(part) then return nil end
    end
    return v
end

local function DumpBody(Out, path)
    if not path or path == "" then return Out("Usage: /fost dump GlobalName (or GlobalName.key.key)") end
    local v = Resolve(path)
    if type(v) ~= "table" then return Out("%s is %s: %s", path, type(v), Describe(v)) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    Out("%s: table with %d keys", path, #keys)
    for i, k in ipairs(keys) do
        if i > 120 then Out("  ... %d more keys", #keys - 120) break end
        local val = v[k]
        if type(val) == "table" then
            local sk, sv = next(val)
            Out("  %s: table, %d entries, e.g. [%s] = %s", tostring(k), Count(val), tostring(sk), Describe(sv))
        else
            Out("  %s = %s", tostring(k), Describe(val))
        end
    end
end

local function GlobalsBody(Out, text)
    if not text or text == "" then return Out("Usage: /fost globals <part of a name>") end
    text = text:lower()
    local list = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:lower():find(text, 1, true) then
            list[#list + 1] = ("%s (%s%s)"):format(k, type(v), type(v) == "table" and (", " .. Count(v) .. " keys") or "")
        end
    end
    table.sort(list)
    Out("%d globals containing '%s':", #list, text)
    for _, l in ipairs(list) do Out("  %s", l) end
end

function ns.Dump(path) RunInWindow("Dump " .. tostring(path), DumpBody, path) end
function ns.Globals(text) RunInWindow("Globals: " .. tostring(text), GlobalsBody, text) end
