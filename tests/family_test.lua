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
print("ALL OK")
