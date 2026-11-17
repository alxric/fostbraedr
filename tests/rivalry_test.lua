-- Rivalry stats, awards, item-roll parsing and week ranges. Run: lua-5.1 tests/rivalry_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local A = sim.NewClient("Ragnar", "Stormfjord", function(f, l) return f .. " " .. l end)
local env, ns = A.env, A.ns
env.LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s"
env.LOOT_ROLL_ROLLED_GREED = "Greed Roll - %d for %s by %s"
env.LOOT_ROLL_YOU_WON = "You won: %s"
env.LOOT_ITEM_SELF = "You receive loot: %s."
env.YOU = "You"
env.C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 2 * 86400 end }
env.SlashCmdList.FOSTBRAEDR("brother add Thorgrim Stormfjord")
local link = "|cnIQ3:|Hitem:555::::|h[Shield]|h|r"
for _, line in ipairs({
    "Need Roll - 90 for " .. link .. " by Ragnar",
    "Greed Roll - 40 for " .. link .. " by Ragnar",
    "Need Roll - 20 for " .. link .. " by Ragnar-Stormfjord",
    "Need Roll - 99 for " .. link .. " by Thorgrim",   -- someone else's roll: ignored
    "You won: " .. link,
    "Thorgrim won: " .. link,                          -- not ours
}) do A.fire("CHAT_MSG_LOOT", line) end
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
-- an old entry from two weeks ago
local old = { author = "Thorgrim Stormfjord", n = 8, time = env.GetServerTime() - 20 * 86400, kind = "death" }
assert(ns.Sync.Accept(old))

local ME, BRO = ns.People.GroupKey("Ragnar Stormfjord"), ns.People.GroupKey("Thorgrim Stormfjord")
local stats = ns.ComputeRivalry(ns.WeekStart(0), nil)
local me, bro = stats[ME], stats[BRO]
print("me", me.rolls, me.rollSum, me.luck, me.rollWins, me.deaths, me.quests)
print("bro", bro.rolls, bro.luck, bro.deaths, bro.quests, bro.gold, bro.level)
assert(me.rolls == 3 and me.rollSum == 150 and me.luck == 50 and me.rollWins == 1 and me.deaths == 1 and me.quests == 1)
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
-- roll entries are hidden from the timeline (needs ChronicleUI)
print("ALL OK")
