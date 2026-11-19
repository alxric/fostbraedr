-- Quest items: sorting bag quest items into delete / check / keep. Run: lua-5.1 tests/questitems_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local A = sim.NewClient("Ragnar", "Stormfjord", function(f, l) return f .. " " .. l end)
local env, ns = A.env, A.ns
for _, f in ipairs({ "QuestItems.lua", "Diagnostics.lua" }) do
  local ch = assert(loadfile("./" .. f)); setfenv(ch, env); ch("Fostbraedr", ns)
end
local QI = ns.QuestItems
local SECRET = {}
env.issecretvalue = function(v) return v == SECRET end

local level = 20
env.UnitLevel = function() return level end

-- items: id -> { name, classID, ilvl }
local ITEMS = {
  [1] = { "Gnoll Paw", 12, 18 },        -- objective of an active quest
  [2] = { "Signal Flare", 12, 19 },     -- the quest's usable item
  [3] = { "Old Letter", 12, 0 },        -- starts a quest already done
  [4] = { "Torn Map", 12, 20 },         -- starts a quest not done, near level
  [5] = { "Kobold Candle", 12, 8 },     -- leftover, old
  [6] = { "Strange Shard", 12, 19 },    -- leftover near level: maybe a later chain step
  [7] = { "Sealed Package", 12, 0 },    -- mentioned in quest text
  [8] = { "Linen Cloth", 7, 5 },        -- not a quest item
  [9] = { "Mystery Rock", 12, 0 },      -- leftover, level unknown
  [10] = { "Faded Note", 12, 6 },       -- starts an old quest not done
}
-- bag contents: { bag, slot, itemID, count, questInfo }
local BAGS = {
  { 0, 1, 1, 3 }, { 0, 2, 1, 2 }, { 0, 3, 2, 1 }, { 1, 1, 3, 1, { isQuestItem = true, questID = 300, isActive = false } },
  { 1, 2, 4, 1, { isQuestItem = true, questID = 400, isActive = false } }, { 1, 3, 5, 4 }, { 1, 4, 6, 1 },
  { 2, 1, 7, 1 }, { 2, 2, 8, 20 }, { 2, 3, 9, 1 }, { 2, 4, 10, 1, { questID = 1000, isActive = false } },
}
local function Find(bag, slot)
  for _, b in ipairs(BAGS) do if b[1] == bag and b[2] == slot then return b end end
end
env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
env.C_Container = {
  GetContainerNumSlots = function(bag) return bag <= 2 and 4 or 0 end,
  GetContainerItemInfo = function(bag, slot)
    local b = Find(bag, slot)
    if not b then return nil end
    local it = ITEMS[b[3]]
    return { itemID = b[3], stackCount = b[4], itemName = it[1], iconFileID = 100 + b[3],
             hyperlink = "|cffffffff|Hitem:" .. b[3] .. "::::|h[" .. it[1] .. "]|h|r" }
  end,
  GetContainerItemQuestInfo = function(bag, slot)
    local b = Find(bag, slot)
    return b and b[5] or { isQuestItem = false, isActive = false }
  end,
}
env.C_Item = {
  GetItemInfoInstant = function(id) return id, "x", "y", "", 1, ITEMS[id][2], 0 end,
  GetItemInfo = function(id) local it = ITEMS[id] return it[1], nil, 1, it[3], 1 end,
}
local QUESTS = {
  { title = "Elwynn", isHeader = true },
  { title = "The Gnoll Problem", questID = 10, objectives = { { text = "Gnoll Paw: 5/8", type = "item" } }, special = 2,
    desc = "Kill gnolls.", obj = "Bring 8 Gnoll Paws." },
  { title = "Special Delivery", questID = 11, objectives = { { text = "Deliver the package", type = "event" } },
    desc = "Take the Sealed Package to Goldshire.", obj = "Deliver it." },
  { title = "Secret Quest", questID = SECRET },
}
local done = { [300] = true }
env.C_QuestLog = {
  GetNumQuestLogEntries = function() return #QUESTS end,
  GetInfo = function(i) return QUESTS[i] end,
  GetQuestObjectives = function(id) for _, q in ipairs(QUESTS) do if q.questID == id then return q.objectives end end end,
  GetTitleForQuestID = function(id) return ({ [300] = "A Letter Home", [400] = "Treasure Hunt", [1000] = "Old Business" })[id] end,
  IsQuestFlaggedCompleted = function(id) return done[id] or false end,
  GetQuestDifficultyLevel = function(id) return ({ [400] = 21, [1000] = 7 })[id] end,
}
env.GetQuestLogSpecialItemInfo = function(i)
  local q = QUESTS[i]
  if q and q.special then return "|cffffffff|Hitem:" .. q.special .. "::::|h[x]|h|r", 1, 1 end
end
env.GetQuestLogQuestText = function(i) return QUESTS[i].desc, QUESTS[i].obj end

local scan = QI.Scan()
assert(not scan.problem, tostring(scan.problem))
local by = {}
for _, it in ipairs(scan.items) do by[it.name] = it print(it.group, it.name, it.count, it.reason) end
local function Is(name, group, pat)
  local it = assert(by[name], name .. " missing")
  assert(it.group == group, name .. ": expected " .. group .. ", got " .. it.group)
  if pat then assert(it.reason:find(pat, 1, true), name .. ": reason '" .. it.reason .. "' lacks '" .. pat .. "'") end
end
Is("Gnoll Paw", "keep", "Objective of The Gnoll Problem")
assert(by["Gnoll Paw"].count == 5, "stacks add up")
Is("Signal Flare", "keep", "Usable item for The Gnoll Problem")
Is("Old Letter", "delete", "A Letter Home, which you've done")
Is("Torn Map", "check", "Treasure Hunt (level 21")
Is("Kobold Candle", "delete", "it's old (level 8, you're 20)")
Is("Strange Shard", "check", "later step of a chain")
Is("Sealed Package", "keep", "Mentioned in Special Delivery")
Is("Mystery Rock", "delete", "No quest in your log uses it")
Is("Faded Note", "delete", "old quest")
assert(not by["Linen Cloth"], "non-quest items are left out")
assert(scan.items[1].group == "delete" and scan.items[#scan.items].group == "keep", "sorted delete, check, keep")
assert(scan.counts.delete == 4 and scan.counts.check == 2 and scan.counts.keep == 3, "counts")
assert(scan.quests == 2, "headers and secret quests are skipped")

-- an active starter quest keeps its item
QUESTS[#QUESTS + 1] = { title = "Treasure Hunt", questID = 400, objectives = {} }
scan = QI.Scan()
for _, it in ipairs(scan.items) do by[it.name] = it end
Is("Torn Map", "keep", "in your log")
table.remove(QUESTS)

-- a client that ignores the index returns the same text for every quest: don't match on it
env.GetQuestLogQuestText = function() return "Take the Sealed Package to Goldshire.", "x" end
scan = QI.Scan()
for _, it in ipairs(scan.items) do by[it.name] = it end
assert(by["Sealed Package"].group ~= "keep", "identical quest text is ignored")

-- level the gap: at level 12 the candle (8) is no longer old
level = 12
scan = QI.Scan()
for _, it in ipairs(scan.items) do by[it.name] = it end
Is("Kobold Candle", "check")

-- missing APIs
env.C_Container = nil
assert(QI.Scan().problem, "missing bag API is reported")

-- the probe runs and writes to the window
env.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
local shown
ns.ShowTextWindow = function(_, text) shown = text end
env.SlashCmdList.FOSTBRAEDR("questtest")
assert(shown and shown:find("QUEST LOG") and shown:find("The Gnoll Problem"), "probe output")
print("ALL OK")
