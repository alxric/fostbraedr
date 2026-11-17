-- Two brothers syncing: initial exchange, live push, combat queueing, party, ping, strangers, re-install.
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
-- Forever sender format unknown: test "First-Last" for one, "First Last" for the other
local A = sim.NewClient("Ragnar", "Stormfjord", function(f,l) return f.."-"..l end)
local B = sim.NewClient("Thorgrim", "Stormfjord", function(f,l) return f.." "..l end)
A.env.SlashCmdList.FOSTBRAEDR("brother add thorgrim stormfjord")
A.env.SlashCmdList.FOSTBRAEDR("brother add Oldalt Stormfjord")
sim.OFFLINE["Oldalt Stormfjord"] = true
B.env.SlashCmdList.FOSTBRAEDR("brother add Ragnar Stormfjord")
-- history before contact
for i = 1, 30 do A.ns.AddEntry("manual", { text = ("A entry %d with some longer text to make batches bigger ^~|"):format(i) }) end
B.fire("PLAYER_DEAD")
B.ns.AddEntry("manual", { text = "B wrote this" })
print("--- run 60s (login hello at 8s)")
sim.Run(60)
local function count(c) local n=0 for _ in pairs(c.ns.db.entries) do n=n+1 end return n end
print("A entries", count(A), "B entries", count(B))
assert(count(A) == 32 and count(B) == 32)
print("--- live push")
A.fire("PLAYER_DEAD")
sim.Run(5)
print("A entries", count(A), "B entries", count(B))
assert(count(B) == 33)
print("--- combat queues")
B.combat = true
B.ns.AddEntry("manual", { text = "in combat" })
sim.Run(5)
assert(count(A) == 33, "should not have arrived during combat")
B.combat = false
sim.Run(3)
assert(count(A) == 34)
print("--- grouped: uses PARTY")
A.grouped, B.grouped = true, true
A.partyFirst, A.partyLast = "Thorgrim", "Stormfjord"
B.partyFirst, B.partyLast = "Ragnar", "Stormfjord"
A.ns.AddEntry("manual", { text = "party msg" })
sim.Run(3)
assert(count(B) == 35)
print("--- ping")
A.env.SlashCmdList.FOSTBRAEDR("ping thorgrim stormfjord")
sim.Run(3)
print("--- stranger ignored")
local entriesBefore = count(A)
A.fire("CHAT_MSG_ADDON", "Fostbraedr", "1:zz:1:1:" .. A.ns.Serialize.Encode({t="E", l={{author="Evil Guy", n=1, time=1, kind="manual", text="hi"}}}), "WHISPER", "Evil-Guy")
A.fire("CHAT_MSG_ADDON", "Fostbraedr", "1:zy:1:1:" .. A.ns.Serialize.Encode({t="E", l={{author="Evil Guy", n=1, time=1, kind="manual", text="hi"}}}), "WHISPER", "Thorgrim-Stormfjord")
A.fire("CHAT_MSG_ADDON", "Fostbraedr", "9:zz:1:1:garbage", "WHISPER", "Thorgrim-Stormfjord")
A.fire("CHAT_MSG_ADDON", "Fostbraedr", "1:zx:1:1:T^Sgarbage", "WHISPER", "Thorgrim-Stormfjord")
assert(count(A) == entriesBefore)
print("--- counters after re-install: B loses its SV, gets own entries back, counter continues")
B.env.SlashCmdList.FOSTBRAEDR("peers")
print("B counter for self", B.ns.db.counters["Thorgrim Stormfjord"])
for k, e in pairs(B.ns.db.entries) do if e.author == "Thorgrim Stormfjord" then B.ns.db.entries[k] = nil end end
B.ns.db.counters["Thorgrim Stormfjord"] = nil
A.ns.Sync.HelloAll(true)
sim.Run(10)
print("B counter after resync", B.ns.db.counters["Thorgrim Stormfjord"])
assert(B.ns.db.counters["Thorgrim Stormfjord"] == 3)
print("A sent packets", A.sent, "B sent", B.sent)
print("ALL OK")
