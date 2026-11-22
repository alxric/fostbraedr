-- Family status, heartbeat keeps peers online, bye/reload, pokes. Run: lua-5.1 tests/family_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local A = sim.NewClient("Ragnar", "Stormfjord", function(f, l) return f .. " " .. l end)
local B = sim.NewClient("Thorgrim", "Stormfjord", function(f, l) return f .. "-" .. l end)
A.env.SlashCmdList.FOSTBRAEDR("brother add Thorgrim Stormfjord")
B.env.SlashCmdList.FOSTBRAEDR("brother add Ragnar Stormfjord")
sim.Run(20)
assert(A.ns.Sync.IsOnline("Thorgrim Stormfjord") and B.ns.Sync.IsOnline("Ragnar Stormfjord"), "not online after hello")
assert(#A.toasts == 1 and A.toasts[1] == "Thorgrim is online", "online toast")

print("--- in an instance nothing goes out; it all arrives after leaving")
B.instance = "The Deadmines"
B.fire("ZONE_CHANGED_NEW_AREA")
B.env.SlashCmdList.FOSTBRAEDR("status farming linen")
B.fire("PLAYER_DEAD")                       -- recorded inside the instance
sim.Run(30)
local p = A.ns.db.peers["Thorgrim Stormfjord"]
assert(p.status ~= "farming linen", "status should not get out of an instance")
assert(not A.ns.db.entries["Thorgrim Stormfjord#1"], "entry should not get out of an instance")
B.instance = nil
B.fire("ZONE_CHANGED_NEW_AREA")
B.fire("PLAYER_ENTERING_WORLD", false, false)
sim.Run(30)
p = A.ns.db.peers["Thorgrim Stormfjord"]
print("peer:", p.level, p.zone, p.class, p.activity, p.status)
assert(p.status == "farming linen" and p.activity == "Out in the world" and p.class == "WARRIOR")
assert(A.ns.db.entries["Thorgrim Stormfjord#1"], "death from the instance should arrive after leaving")

print("--- a lost live push is repaired by the heartbeat")
B.loggedOut = true                           -- drop everything for a moment
B.ns.AddEntry("manual", { text = "lost in transit" })
sim.Run(2)
B.loggedOut = false
assert(not A.ns.db.entries["Thorgrim Stormfjord#2"])
sim.Run(5 * 60)
assert(A.ns.db.entries["Thorgrim Stormfjord#2"], "heartbeat should have repaired the gap")

print("--- heartbeat keeps them online past 10 minutes")
sim.Run(13 * 60)
assert(A.ns.Sync.IsOnline("Thorgrim Stormfjord"), "dropped offline despite heartbeat")

print("--- poke by first name, with message; cooldown")
A.env.SlashCmdList.FOSTBRAEDR("poke thorgrim wake up!")
A.env.SlashCmdList.FOSTBRAEDR("poke Thorgrim again")
sim.Run(3)
local pokes = 0
for _, t in ipairs(B.toasts) do if t:find("pokes you") then pokes = pokes + 1 end end
assert(pokes == 1, "expected exactly one poke, got " .. pokes)

print("--- reload: BYE then HI, no second online toast")
local before = #A.toasts
B.fire("PLAYER_LOGOUT")   -- BYE goes out synchronously here
B.loggedOut = true         -- after that the client is gone (queued messages are lost)
sim.Run(1)
assert(not A.ns.Sync.IsOnline("Thorgrim Stormfjord"), "BYE should mark offline")
B.loggedOut = false
B.ns.Sync.HelloAll(true)
sim.Run(5)
assert(A.ns.Sync.IsOnline("Thorgrim Stormfjord"))
assert(#A.toasts == before, "reload should not toast 'online'")

print("--- poke prefix parsing")
assert(A.ns.FindBrotherByPrefix("Thorgrim Stormfjord hi there") == "Thorgrim Stormfjord")
local n, m = A.ns.FindBrotherByPrefix("thorgrim hi there")
assert(n == "Thorgrim Stormfjord" and m == "hi there", tostring(m))
assert(A.ns.FindBrotherByPrefix("Nobody hi") == nil)

print("--- % left to next level reaches the brother, only when it changes")
local xp, xpMax = 6300, 10000
B.env.UnitXP = function() return xp end
B.env.UnitXPMax = function() return xpMax end
B.fire("PLAYER_XP_UPDATE")
sim.Run(20)
p = A.ns.db.peers["Thorgrim Stormfjord"]
assert(p.xpLeft == 37, "63% done = 37% left, got " .. tostring(p.xpLeft))
assert(A.ns.XPText(p.level, p.xpLeft) == "37% left to 21", A.ns.XPText(p.level, p.xpLeft))
assert(p.tiLeft == nil, "no completed quests, no turn-in text")
-- count status changes sent (heartbeats carry hw and are sent every 4 minutes anyway)
local changes = 0
local origSend = B.ns.Sync.SendToOnline
B.ns.Sync.SendToOnline = function(msg, ...)
  if msg.t == "ST" and not msg.hw then changes = changes + 1 end
  return origSend(msg, ...)
end
xp = 6350                                   -- still 63%: nothing new to send
for _ = 1, 5 do B.fire("PLAYER_XP_UPDATE") end
sim.Run(20)
assert(changes == 0, "no message when the whole % is unchanged, got " .. changes)
xp = 6400                                   -- 64%: one message
for _ = 1, 5 do B.fire("PLAYER_XP_UPDATE") end
sim.Run(20)
assert(changes == 1 and p.xpLeft == 36, "one message when it changes")
print("--- turn-ins: completed quests' XP")
local QUESTS = {
  { title = "Zone", isHeader = true },
  { questID = 1, complete = true, xp = 1000 },
  { questID = 2, complete = true, xp = 1500 },
  { questID = 3, complete = false, xp = 5000 },  -- not done: doesn't count
  { questID = 4, complete = true, xp = 0 },      -- no XP: doesn't count
}
B.env.C_QuestLog = {
  GetNumQuestLogEntries = function() return #QUESTS end,
  GetInfo = function(i) return QUESTS[i] end,
  IsComplete = function(id) for _, q in ipairs(QUESTS) do if q.questID == id then return q.complete end end end,
}
B.env.GetQuestLogRewardXP = function(id) for _, q in ipairs(QUESTS) do if q.questID == id then return q.xp end end end
B.fire("QUEST_LOG_UPDATE")
sim.Run(20)
-- 6400 + 2500 = 8900 of 10000: 11% left after 2 turn-ins
assert(p.xpLeft == 36 and p.tiLeft == 11 and p.tiN == 2, ("got %s %s %s"):format(tostring(p.xpLeft), tostring(p.tiLeft), tostring(p.tiN)))
assert(A.ns.XPText(p.level, p.xpLeft, p.tiLeft, p.tiN) == "36% left to 21  \194\183  11% after 2 turn-ins")
QUESTS[5].xp = 1200                          -- quest 4 (entry 5: entry 1 is the header): now 10100, enough to level
B.fire("QUEST_LOG_UPDATE")
sim.Run(20)
local bl, bn = B.ns.MyTurnInLeft()
assert(p.tiLeft == 0 and p.tiN == 3, ("got %s %s, B says %s %s"):format(tostring(p.tiLeft), tostring(p.tiN), tostring(bl), tostring(bn)))
assert(A.ns.XPText(p.level, p.xpLeft, p.tiLeft, p.tiN):find("enough for 21 with 3 turn-ins", 1, true))
QUESTS[3].complete, QUESTS[5].complete = false, false  -- only quest 1 left
B.fire("QUEST_LOG_UPDATE")
sim.Run(20)
assert(A.ns.XPText(p.level, p.xpLeft, p.tiLeft, p.tiN) == "36% left to 21  \194\183  26% after 1 turn-in", "singular")
for _, q in ipairs(QUESTS) do q.complete = false end
B.fire("QUEST_LOG_UPDATE")
sim.Run(20)
assert(p.tiLeft == nil and p.tiN == nil, "turn-in text goes away when nothing is complete")
B.env.GetQuestLogRewardXP = nil              -- an API this client lacks: just no turn-ins
assert(B.ns.TurnInXP() == 0)

xp = 9999                                   -- 99.99% done still says 1% left, never 0%
assert(B.ns.MyXPLeft() == 1)
xp = 0
assert(B.ns.MyXPLeft() == 100)
xpMax = 0                                   -- max level: nothing shown
B.fire("PLAYER_XP_UPDATE")
sim.Run(20)
assert(p.xpLeft == nil and A.ns.XPText(p.level, p.xpLeft) == "", "nothing at max level")
local SECRET = {}
B.env.issecretvalue = function(v) return v == SECRET end
B.env.UnitXP = function() return SECRET end
xpMax = 100
assert(B.ns.MyXPLeft() == nil, "secret XP is ignored")
A.ns.Sync.ApplyStatus("Thorgrim Stormfjord", { level = 30, xpLeft = "junk" })
assert(p.xpLeft == nil, "bad values from a peer are dropped")
A.ns.Sync.ApplyStatus("Thorgrim Stormfjord", { level = 30, xpLeft = 250 })
assert(p.xpLeft == nil, "out of range values are dropped")
A.ns.Sync.ApplyStatus("Thorgrim Stormfjord", { level = 30, xpLeft = 40, tiLeft = 10, tiN = "x" })
assert(p.xpLeft == 40 and p.tiLeft == nil and p.tiN == nil, "turn-in values must come as a valid pair")
print("ALL OK")
