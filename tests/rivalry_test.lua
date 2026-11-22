-- Rivalry stats, awards and week ranges. Run: lua-5.1 tests/rivalry_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local A = sim.NewClient("Ragnar", "Stormfjord", function(f, l) return f .. " " .. l end)
local env, ns = A.env, A.ns
env.C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 2 * 86400 end }
env.SlashCmdList.FOSTBRAEDR("brother add Thorgrim Stormfjord")
-- our item rolls (recorded from the Loot History, see rolls_test.lua): 90, 40, 20 and one win
ns.AddEntry("roll", { roll = 90, rollType = "need" })
ns.AddEntry("roll", { roll = 40, rollType = "greed" })
ns.AddEntry("roll", { roll = 20, rollType = "need" })
ns.AddEntry("rollwin", { link = "|cnIQ3:|Hitem:555::::|h[Shield]|h|r", boss = "Herod", src = "history" })
A.fire("PLAYER_DEAD")
A.fire("QUEST_TURNED_IN")
-- a brother's entries, as if synced
local function remote(n, kind, fields)
    local e = fields or {}
    e.author, e.n, e.time, e.kind = "Thorgrim Stormfjord", n, env.GetServerTime(), kind
    assert(ns.Sync.Accept(e))
end
remote(1, "death") remote(2, "death")
remote(3, "tally", { quests = 5, gold = 12345, minutes = 30, together = 10 })
remote(4, "roll", { roll = 10 }) remote(5, "roll", { roll = 20 }) remote(6, "roll", { roll = 30 })
remote(7, "level", { level = 12 })
remote(9, "loot", { quality = 2, link = "green" })              -- recorded at a low threshold: not an epic
remote(10, "loot", { quality = 4, link = "epic" })
remote(11, "loot", { quality = 1, mount = true, link = "mount" })
-- an old entry from two weeks ago
local old = { author = "Thorgrim Stormfjord", n = 8, time = env.GetServerTime() - 20 * 86400, kind = "death" }
assert(ns.Sync.Accept(old))

-- double wins: an old chat-recorded win (no boss) plus the same win from the Loot History
ns.AddEntry("rollwin", { link = "|cnIQ3:|Hitem:10777::::|h[Arachnid Gloves]|h|r" })
ns.AddEntry("rollwin", { link = "|cnIQ3:|Hitem:10777::::|h[Arachnid Gloves]|h|r", boss = "Tuten'kash", src = "history" })
local ME, BRO = ns.People.GroupKey("Ragnar Stormfjord"), ns.People.GroupKey("Thorgrim Stormfjord")
local stats = ns.ComputeRivalry(ns.WeekStart(0), nil)
local me, bro = stats[ME], stats[BRO]
print("me", me.rolls, me.rollSum, me.luck, me.rollWins, me.deaths, me.quests)
print("bro", bro.rolls, bro.luck, bro.deaths, bro.quests, bro.gold, bro.level)
assert(me.rolls == 3 and me.rollSum == 150 and me.luck == 50 and me.rollWins == 2 and me.deaths == 1 and me.quests == 1)
assert(bro.loot == 2, "Epics should count the epic and the mount only, got " .. bro.loot)
assert(bro.rolls == 3 and bro.luck == 20 and bro.deaths == 2 and bro.quests == 5 and bro.level == 12)
local aw = ns.ComputeAwards(stats)
assert(aw.deaths.winners[1] == BRO and aw.deaths.value == 2)
assert(aw.luck.winners[1] == ME)
assert(aw.quests.winners[1] == BRO)
assert(me.isMe and me.name == "Ragnar" and bro.name == "Thorgrim")
assert(#aw.bosses.winners == 0)
local all = ns.ComputeRivalry(nil, nil)
assert(all[BRO].deaths == 3)
local last = ns.ComputeRivalry(ns.WeekStart(1), ns.WeekStart(0))
assert(last[BRO].deaths == 0)
assert(ns.WeekStart(0) - ns.WeekStart(1) == 7 * 86400)

-- gear: my average item level (from the client) against a brother's (from his status)
assert(not all[ME].ilvl and not ns.ComputeAwards(all).ilvl.value, "no item level known yet")
env.GetAverageItemLevel = function() return 41.0, 39.84 end
ns.Sync.ApplyStatus("Thorgrim Stormfjord", { level = 12, ilvl10 = 413 })
local now = ns.ComputeRivalry(ns.WeekStart(0), nil)
assert(math.abs(now[ME].ilvl - 39.84) < 0.001 and now[BRO].ilvl == 41.3, tostring(now[BRO].ilvl))
local gaw = ns.ComputeAwards(now)
assert(gaw.ilvl.winners[1] == BRO and gaw.ilvl.value == 41.3, "best geared")
assert(ns.ComputeRivalry(nil, nil)[BRO].ilvl == 41.3, "the same in every period")
-- my status sends it as tenths, rounded
assert(ns.MyStatus().ilvl10 == 398)
-- bad values from a peer are dropped
ns.Sync.ApplyStatus("Thorgrim Stormfjord", { level = 12, ilvl10 = "lots" })
assert(not ns.ComputeRivalry(nil, nil)[BRO].ilvl)
-- without GetAverageItemLevel: worked out from the slots (16 slots; a two-hander counts twice)
env.GetAverageItemLevel = nil
local worn = { [1] = 30, [5] = 34, [16] = 40, [18] = 16 } -- the ranged/relic slot doesn't count
env.GetInventoryItemLink = function(_, slot) return worn[slot] and ("|Hitem:" .. slot .. "|h[x]|h") end
env.C_Item = { GetDetailedItemLevelInfo = function(link) return worn[tonumber(link:match("item:(%d+)"))] end,
               GetItemInventoryTypeByID = function() return 17 end }
local ilvl = ns.MyItemLevel()
assert(math.abs(ilvl - (30 + 34 + 40 + 40) / 16) < 0.001, tostring(ilvl))
-- real gear from /fost ilvltest on Forever (2026-11-22): the game said 40.875
worn = { [1] = 49, [2] = 46, [3] = 48, [5] = 34, [6] = 36, [7] = 49, [8] = 44, [9] = 46, [10] = 38,
         [11] = 35, [12] = 39, [13] = 50, [15] = 46, [16] = 47, [18] = 16 }  -- staff (two-hander), idol
assert(ns.MyItemLevel() == 40.875, tostring(ns.MyItemLevel()))
env.GetInventoryItemLink = function() return nil end
assert(ns.MyItemLevel() == nil, "nothing worn: unknown")
-- roll entries are hidden from the timeline (needs ChronicleUI)
print("ALL OK")
