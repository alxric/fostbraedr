-- Item rolls from the Loot History, shaped like the real data seen in game.
-- Run: lua-5.1 tests/rolls_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local A = sim.NewClient("Ragnar", "Stormfjord", function(f, l) return f .. " " .. l end)
local env, ns = A.env, A.ns
env.Enum.EncounterLootDropRollState = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }

local function R(name, roll, state, isSelf) return { playerName = name, roll = roll, state = state, isSelf = isSelf } end
local drops = {
    [0] = { -- Miscellaneous (trash)
        { lootListID = 1, itemHyperlink = "[Enduring Gauntlets]", startTime = 100,
          winner = R("Nomarak", 83, 3, false), rollInfos = { R("Nomarak", 83, 3, false), R("Ragnar", 35, 3, true), R("Tasty", nil, 4, false) } },
        { lootListID = 2, itemHyperlink = "[Mithril Rifle Schematic]", startTime = 101,
          winner = R("Ragnar", 95, 3, true), rollInfos = { R("Ragnar", 95, 3, true), R("Nomarak", 93, 3, false) } },
        { lootListID = 3, itemHyperlink = "[Strong Iron Lockbox]", startTime = 102, -- someone needed: our greed never rolled
          winner = R("Panda", 9, 0, false), rollInfos = { R("Panda", 9, 0, false), R("Ragnar", nil, 3, true) } },
    },
    [2780] = { -- Tuten'kash
        { lootListID = 1, itemHyperlink = "[Arachnid Gloves]", startTime = 200,
          winner = R("Ragnar", 40, 0, true), rollInfos = { R("Ragnar", 40, 0, true), R("Tasty", nil, 3, false) } },
        { lootListID = 2, itemHyperlink = "[Still rolling]", startTime = 201, -- not finished: no winner yet
          rollInfos = { R("Ragnar", 50, 3, true) } },
    },
}
env.C_LootHistory = {
    GetAllEncounterInfos = function()
        return { { encounterID = 0, encounterName = "Miscellaneous" }, { encounterID = 2780, encounterName = "Tuten'kash" } }
    end,
    GetSortedDropsForEncounter = function(id) return drops[id] end,
    GetSortedInfoForDrop = function(id, listID)
        for _, d in ipairs(drops[id]) do if d.lootListID == listID then return d end end
    end,
}

local function Entries(kind)
    local list = {}
    for _, e in pairs(ns.db.entries) do if e.kind == kind then list[#list + 1] = e end end
    table.sort(list, function(a, b) return a.n < b.n end)
    return list
end

print("--- inside an instance nothing is read")
A.instance = "Razorfen Downs"
assert(ns.ScanLootHistory() == 0)

print("--- outside: our rolls and wins are recorded once")
A.instance = nil
local added = ns.ScanLootHistory()
local rolls, wins = Entries("roll"), Entries("rollwin")
print("added", added, "rolls", #rolls, "wins", #wins)
assert(#rolls == 3, "35 greed, 95 greed, 40 need; the lockbox had no roll from us; unfinished drop skipped")
assert(rolls[1].roll == 35 and rolls[1].rollType == "greed" and rolls[1].boss == "Miscellaneous")
assert(rolls[3].roll == 40 and rolls[3].rollType == "need" and rolls[3].boss == "Tuten'kash")
assert(#wins == 2, "won the schematic and the gloves")
assert(ns.ScanLootHistory() == 0, "second scan adds nothing")

print("--- the unfinished drop is picked up once it has a winner")
drops[2780][2].winner = R("Tasty", 77, 3, false)
assert(ns.ScanLootHistory() == 1)
assert(#Entries("roll") == 4 and #Entries("rollwin") == 2)

print("--- hidden values are skipped and retried later")
local SECRET = {}
env.issecretvalue = function(v) return v == SECRET end
drops[2780][3] = { lootListID = 3, itemHyperlink = "[Secret Thing]", startTime = 202,
                   winner = R("Ragnar", 60, 3, true), rollInfos = { R("Ragnar", SECRET, 3, true) } }
assert(ns.ScanLootHistory() == 0)
drops[2780][3].rollInfos[1].roll = 60
env.issecretvalue = nil
assert(ns.ScanLootHistory() == 2, "roll + win once readable")

print("--- the scan runs on leaving an instance")
drops[2780][4] = { lootListID = 4, itemHyperlink = "[Late]", startTime = 203,
                   winner = R("Nomarak", 70, 3, false), rollInfos = { R("Ragnar", 12, 3, true) } }
A.fire("PLAYER_ENTERING_WORLD", false, false)
sim.Run(5)
assert(#Entries("roll") == 6)

print("--- a drop listed before its rolls loaded is retried, not lost")
drops[2780][5] = { lootListID = 5, itemHyperlink = "[Loading]", startTime = 204,
                   winner = R("Ragnar", 88, 3, true), rollInfos = {} }
assert(ns.ScanLootHistory() == 0, "nothing yet")
drops[2780][5].rollInfos = { R("Ragnar", 88, 3, true) }
assert(ns.ScanLootHistory() == 2, "roll + win once loaded")
drops[2780][5] = nil

print("--- Rivalry luck uses them")
local stats = ns.ComputeRivalry(nil, nil)
local me = stats[ns.People.GroupKey("Ragnar Stormfjord")]
print("rolls", me.rolls, "luck", me.luck, "wins", me.rollWins)
assert(me.rolls == 7 and me.rollWins == 4)
print("--- Forever's drops have no lootListID: fingerprint instead")
drops[2781] = {
    { itemHyperlink = "|cnIQ3:|Hitem:10760::::|h[Swine Fists]|h|r", winner = R("Ragnar", 67, 0, true),
      rollInfos = { R("Ragnar", 67, 0, true), R("Tasty", nil, 3, false) } },
    { itemHyperlink = "|cnIQ3:|Hitem:4636::::|h[Strong Iron Lockbox]|h|r", winner = R("Panda", 9, 0, false),
      rollInfos = { R("Panda", 9, 0, false), R("Ragnar", 21, 0, true) } },
}
local realEncounters = env.C_LootHistory.GetAllEncounterInfos
env.C_LootHistory.GetAllEncounterInfos = function()
    local list = realEncounters()
    list[#list + 1] = { encounterID = 2781, encounterName = "Plaguemaw the Rotting" }
    return list
end
-- an old chat-recorded win for Swine Fists exists already (0.2.x)
ns.AddEntry("rollwin", { link = "|cnIQ3:|Hitem:10760::::|h[Swine Fists]|h|r" })
local winsBefore = #Entries("rollwin")
assert(ns.ScanLootHistory() == 2, "two rolls recorded, the Swine Fists win not duplicated")
assert(#Entries("rollwin") == winsBefore, "no double win")
assert(ns.ScanLootHistory() == 0, "fingerprints prevent recounting")

print("--- /fost rolls report")
local report
ns.ShowTextWindow = function(_, text) report = text end
env.SlashCmdList.FOSTBRAEDR("rolls")
print(report)
assert(report:find("Our roll entries: 9, wins: 5") and report:find("already counted"), "report explains")

print("--- login repair: no rolls of our own -> forget processed drops")
local B = sim.NewClient("Brokk", "Stormfjord", function(f, l) return f .. " " .. l end)
B.ns.db.lootSeen["0/1/100"] = 1
B.fire("PLAYER_LOGIN")
assert(next(B.ns.db.lootSeen) == nil, "wiped when we hold no rolls")
ns.db.lootSeen["x"] = env.GetServerTime()
A.fire("PLAYER_LOGIN")
assert(ns.db.lootSeen["x"], "kept when we already have rolls")
print("ALL OK")
