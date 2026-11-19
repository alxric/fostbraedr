-- Fostbraedr: quest items in your bags, and whether a quest in your log still
-- needs them. The game has no "this item belongs to quest X" link, so this goes by
-- what it can see: quest objectives (by item name), each quest's usable item, the
-- quest text, and the quest an item starts. Nothing here deletes anything.
local ADDON, ns = ...

local QI = {}
ns.QuestItems = QI

-- Groups, in display order.
QI.DELETE = "delete" -- probably safe to delete
QI.CHECK  = "check"  -- starts a quest you haven't done, or not loaded yet
QI.KEEP   = "keep"   -- a quest in your log uses it
QI.ORDER  = { QI.DELETE, QI.CHECK, QI.KEEP }

local QUEST_ITEM_CLASS = 12 -- Enum.ItemClass.Questitem
local MIN_NAME_LEN = 3      -- shorter names would match too much quest text
QI.OUTDATED_GAP = 5         -- this many levels below you: the quest is most likely outdated

-- Readable plain value, or nil for secrets (testing a secret's truth is an error).
local function Val(v) if not ns.IsSecret(v) then return v end end
local function Str(v) v = Val(v) return type(v) == "string" and v ~= "" and v or nil end

local function ItemIDFromLink(link)
    link = Str(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function NameFromLink(link)
    link = Str(link)
    return link and link:match("%[(.-)%]")
end
QI.ItemIDFromLink = ItemIDFromLink

-------------------------------------------------------------------------------
-- Quest log
-------------------------------------------------------------------------------
-- Every quest in the log: { questID, title, objectives = {lowercase text},
-- text = {lowercase text}, goal = lowercase "objectives text" or nil, itemIDs = {[id] = true} }. Second value: a problem, if any.
function QI.ActiveQuests()
    local QL = C_QuestLog
    if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo) then return {}, "the quest log API is missing" end
    local list = {}
    local descriptions, sameText = {}, true
    for i = 1, QL.GetNumQuestLogEntries() or 0 do
        local info = QL.GetInfo(i)
        local questID = info and Val(info.questID)
        if questID and not Val(info.isHeader) then
            local q = { questID = questID, title = Str(info.title) or ("quest " .. questID), logIndex = i,
                        objectives = {}, text = {}, itemIDs = {} }
            if QL.GetQuestObjectives then
                for _, o in ipairs(QL.GetQuestObjectives(questID) or {}) do
                    local t = Str(o.text)
                    if t then q.objectives[#q.objectives + 1] = t:lower() end
                end
            end
            if GetQuestLogSpecialItemInfo then
                local id = ItemIDFromLink((GetQuestLogSpecialItemInfo(i)))
                if id then q.itemIDs[id] = true end
            end
            if GetQuestLogQuestText then
                local desc, objText = GetQuestLogQuestText(i)
                desc, objText = Str(desc), Str(objText)
                if desc then q.text[#q.text + 1] = desc:lower() end
                if objText then q.text[#q.text + 1] = objText:lower() q.goal = objText:lower() end
                local key = (desc or "") .. "|" .. (objText or "")
                if #descriptions > 0 and descriptions[1] ~= key then sameText = false end
                descriptions[#descriptions + 1] = key
            end
            list[#list + 1] = q
        end
    end
    -- If every quest returned the same text, the client ignored the index and gave
    -- us the selected quest's text: matching on it would be wrong, so drop it.
    if #descriptions > 1 and sameText then
        for _, q in ipairs(list) do q.text, q.goal = {}, nil end
    end
    return list
end

local function Mentions(texts, name)
    for _, t in ipairs(texts) do
        if t:find(name, 1, true) then return true end
    end
    return false
end

-- The item's main word, for objectives that don't use the full name ("Deliver the
-- blade" for Beguiler's Blade): the first part of "X of Y", else the last word.
-- Words under 4 letters are too common to use. Lowercase input.
function QI.HeadWord(name)
    name = name:gsub("%s+of%s.*$", "")
    local head
    for w in name:gmatch("[%a']+") do
        if #w >= 4 then head = w end
    end
    return head and (head:gsub("'s$", ""))
end

-- Whole-word match of word (or its plural) in a quest's objectives.
local function ObjectiveMentionsWord(q, word)
    local pattern = "[^%a]" .. word:gsub("%p", "%%%0") .. "e?s?[^%a]"
    local texts = { q.goal }
    for _, t in ipairs(q.objectives) do texts[#texts + 1] = t end
    for _, t in ipairs(texts) do
        if (" " .. t .. " "):find(pattern) then return true end
    end
    return false
end

local function QuestTitle(questID)
    local QL = C_QuestLog
    local title = QL and QL.GetTitleForQuestID and Str(QL.GetTitleForQuestID(questID))
    return title or ("quest #" .. questID)
end

local function IsQuestDone(questID)
    local QL = C_QuestLog
    if QL and QL.IsQuestFlaggedCompleted then return Val(QL.IsQuestFlaggedCompleted(questID)) == true end
    if IsQuestFlaggedCompleted then return Val(IsQuestFlaggedCompleted(questID)) == true end
    return false
end

-------------------------------------------------------------------------------
-- Bags
-------------------------------------------------------------------------------
local function IsQuestClass(itemID)
    if not (C_Item and C_Item.GetItemInfoInstant) then return false end
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    return Val(classID) == QUEST_ITEM_CLASS
end

-- Quest items in your bags, one per item ID (stacks added up):
-- { itemID, name, link, icon, count, bag, slot, startsQuest }
function QI.BagQuestItems()
    local C = C_Container
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return {}, "the bag API is missing" end
    local byID, list = {}, {}
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local info = C.GetContainerItemInfo(bag, slot)
            local itemID = info and Val(info.itemID)
            if itemID then
                local q = C.GetContainerItemQuestInfo and C.GetContainerItemQuestInfo(bag, slot) or {}
                local startsQuest = Val(q.questID)
                if Val(q.isQuestItem) or startsQuest or IsQuestClass(itemID) then
                    local item = byID[itemID]
                    if not item then
                        item = { itemID = itemID, link = Str(info.hyperlink), icon = Val(info.iconFileID),
                                 count = 0, bag = bag, slot = slot, startsQuest = startsQuest,
                                 starterActive = Val(q.isActive) and true or nil }
                        item.name = Str(info.itemName) or NameFromLink(item.link)
                        byID[itemID] = item
                        list[#list + 1] = item
                    end
                    item.count = item.count + (Val(info.stackCount) or 1)
                end
            end
        end
    end
    return list
end

-------------------------------------------------------------------------------
-- Sorting the items into groups
-------------------------------------------------------------------------------
-- Level of the quest an item belongs to, as far as we can tell: the quest's own
-- level for items that start one, else the item level (quest items are usually
-- made at their quest's level). nil when unknown. Second value: where it came from.
function QI.ItemLevel(item)
    local QL = C_QuestLog
    if item.startsQuest and QL and QL.GetQuestDifficultyLevel then
        local lvl = Val(QL.GetQuestDifficultyLevel(item.startsQuest))
        if type(lvl) == "number" and lvl > 0 then return lvl, "quest" end
    end
    if C_Item and C_Item.GetItemInfo then
        -- On Forever quest items report item level 1 (no help), and "required
        -- level" is the level to use the item, not the quest's: don't use it.
        local ilvl = Val((select(4, C_Item.GetItemInfo(item.itemID))))
        if type(ilvl) == "number" and ilvl > 1 then return ilvl, "item" end
    end
end

local function PlayerLevel() return Val(UnitLevel("player")) or 0 end

-- Sets item.group, item.reason and item.level.
function QI.Classify(item, quests)
    local name = item.name and item.name:lower()
    item.level = QI.ItemLevel(item)
    local behind = item.level and PlayerLevel() - item.level
    local old = behind and behind >= QI.OUTDATED_GAP
    local levelText = item.level and (" (level %d, you're %d)"):format(item.level, PlayerLevel()) or ""
    -- a quest in the log uses it
    for _, q in ipairs(quests) do
        if q.itemIDs[item.itemID] then
            item.group, item.reason = QI.KEEP, "Usable item for " .. q.title
            return
        end
    end
    if name and #name >= MIN_NAME_LEN then
        for _, q in ipairs(quests) do
            if Mentions(q.objectives, name) then
                item.group, item.reason = QI.KEEP, "Objective of " .. q.title
                return
            end
        end
    end
    -- it starts a quest
    local qid = item.startsQuest
    if qid then
        for _, q in ipairs(quests) do
            if q.questID == qid then item.starterActive = true end
        end
        if item.starterActive then
            item.group, item.reason = QI.KEEP, "Starts " .. QuestTitle(qid) .. ", which is in your log"
        elseif IsQuestDone(qid) then
            item.group, item.reason = QI.DELETE, "Starts " .. QuestTitle(qid) .. ", which you've done"
        elseif old then
            item.group, item.reason = QI.DELETE, "Starts an old quest you haven't done: " .. QuestTitle(qid) .. levelText
        else
            item.group, item.reason = QI.CHECK, "Starts a quest you haven't done: " .. QuestTitle(qid) .. levelText
        end
        return
    end
    if name and #name >= MIN_NAME_LEN then
        for _, q in ipairs(quests) do
            if Mentions(q.text, name) then
                item.group, item.reason = QI.KEEP, "Mentioned in " .. q.title
                return
            end
        end
    end
    if name and name:find("page %d+$") then
        item.group, item.reason = QI.CHECK, "A book page: pages are collected and handed in together"
        return
    end
    local head = name and QI.HeadWord(name)
    if head then
        for _, q in ipairs(quests) do
            if ObjectiveMentionsWord(q, head) then
                item.group, item.reason = QI.CHECK, ("Maybe for %s (its objective mentions \"%s\")"):format(q.title, head)
                return
            end
        end
    end
    -- a quest item with a "Use:" effect may be a tool you keep (Goblin Transponder
    -- teleports you into Gadgetzan) rather than leftover loot
    local spell = C_Item and C_Item.GetItemSpell and Str((C_Item.GetItemSpell(item.itemID)))
    if spell then
        item.group, item.reason = QI.CHECK, ("Has a use (%s): it may be a tool, not leftover loot"):format(spell)
        return
    end
    if not name then
        item.group, item.reason = QI.CHECK, "Item info not loaded yet"
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(item.itemID) end
        return
    end
    if old then
        item.group, item.reason = QI.DELETE, "No quest in your log uses it, and it's old" .. levelText
    elseif item.level then
        item.group, item.reason = QI.CHECK, "No quest in your log uses it, but it's near your level: maybe for a later step of a chain" .. levelText
    else
        item.group, item.reason = QI.DELETE, "No quest in your log uses or mentions it"
    end
end

-- Everything for the tab: { items (sorted by group, then name), counts = {[group] = n}, problem }
function QI.Scan()
    local quests, qProblem = QI.ActiveQuests()
    local items, bProblem = QI.BagQuestItems()
    local rank = {}
    for i, g in ipairs(QI.ORDER) do rank[g] = i end
    local counts = { [QI.DELETE] = 0, [QI.CHECK] = 0, [QI.KEEP] = 0 }
    for _, item in ipairs(items) do
        QI.Classify(item, quests)
        counts[item.group] = counts[item.group] + 1
    end
    table.sort(items, function(a, b)
        if a.group ~= b.group then return rank[a.group] < rank[b.group] end
        return (a.name or "") < (b.name or "")
    end)
    return { items = items, counts = counts, quests = #quests, problem = bProblem or qProblem }
end
