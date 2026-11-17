-- Alts link to their owner automatically. Run: lua-5.1 tests/people_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local function Sender(f, l) return f .. " " .. l end

-- Thorgrim's account has played Brokk and Sven before.
local B = sim.NewClient("Thorgrim", "Stormfjord", Sender)
B.ns.db.myChars["Brokk Stormfjord"] = true
B.ns.db.myChars["Sven Stormfjord"] = true
local A = sim.NewClient("Ragnar", "Stormfjord", Sender)
A.env.SlashCmdList.FOSTBRAEDR("brother add Thorgrim Stormfjord")   -- only his main
B.env.SlashCmdList.FOSTBRAEDR("brother add Ragnar Stormfjord")
B.env.SlashCmdList.FOSTBRAEDR("name Tor")
sim.Run(20)

local P = A.ns.People
local bros = P.Brothers()
assert(#bros == 1, "expected one brother person, got " .. #bros)
assert(bros[1].name == "Tor" and #bros[1].chars == 3, "Tor should have 3 characters")
assert(P.DisplayName("Brokk Stormfjord") == "Tor (Brokk)")
assert(P.DisplayName("Thorgrim Stormfjord") == "Tor (Thorgrim)")
assert(P.IsKin("Sven Stormfjord") and not P.IsKin("Ragnar Stormfjord"))
print("linked:", table.concat(bros[1].chars, ", "))
assert(A.toasts[1] == "Tor (Thorgrim) is online", "first toast should use the person name, got: " .. tostring(A.toasts[1]))

print("--- Thorgrim logs out, logs in on Brokk (same account data)")
B.fire("PLAYER_LOGOUT")
B.loggedOut = true
local Bk = sim.NewClient("Brokk", "Stormfjord", Sender, sim.Copy(B.env.FostbraedrDB))
Bk.fire("PLAYER_DEAD")
sim.Run(20)
assert(A.ns.Sync.IsOnline("Brokk Stormfjord"), "Brokk should be online for A")
assert(A.ns.Sync.PersonOnline("Thorgrim Stormfjord"), "Tor counts as online via Brokk")
local dead = false
for _, e in pairs(A.ns.db.entries) do if e.author == "Brokk Stormfjord" and e.kind == "death" then dead = true end end
assert(dead, "Brokk's death should have synced")
local stats, keys = A.ns.ComputeRivalry(nil, nil)
local tor = stats[P.GroupKey("Thorgrim Stormfjord")]
assert(tor and tor.deaths == 1 and tor.name == "Tor", "rivalry should group Brokk under Tor")
assert(P.GroupKey("Brokk Stormfjord") == P.GroupKey("Thorgrim Stormfjord"))
local n = 0 for _ in pairs(stats) do n = n + 1 end
assert(n == 2, "rivalry should have 2 people (me + Tor), got " .. n)

print("--- poke 'Tor' reaches Brokk")
A.env.SlashCmdList.FOSTBRAEDR("poke tor wake up")
sim.Run(3)
local poked = false
for _, t in ipairs(Bk.toasts) do if t:find("pokes you") then poked = true end end
assert(poked, "poke by person name should reach the online character")

print("--- a brand-new alt links itself")
Bk.fire("PLAYER_LOGOUT")
Bk.loggedOut = true
local Nw = sim.NewClient("Newbie", "Stormfjord", Sender, sim.Copy(Bk.env.FostbraedrDB))
Nw.ns.Sync.HelloAll(true)
sim.Run(20)
assert(P.Of("Newbie Stormfjord") == P.Of("Thorgrim Stormfjord"), "Newbie should be linked to Tor")
assert(A.ns.Sync.IsOnline("Newbie Stormfjord"))

print("--- a stranger claiming nothing is still ignored")
assert(not P.IsKin("Evil Guy"))

print("--- removing Thorgrim forgets the whole person")
A.env.SlashCmdList.FOSTBRAEDR("brother remove thorgrim stormfjord")
assert(#P.Brothers() == 0, "Tor and his alts should be gone")
assert(not P.IsKin("Brokk Stormfjord"))
print("ALL OK")
