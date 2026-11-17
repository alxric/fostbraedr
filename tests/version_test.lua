-- Version comparison and the "update available" nudge. Run: lua-5.1 tests/version_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local function Sender(f, l) return f .. " " .. l end
local A = sim.NewClient("Ragnar", "Stormfjord", Sender)
local B = sim.NewClient("Thorgrim", "Stormfjord", Sender)
local C = A.ns.Sync.CompareVersions
assert(C("0.2.0", "0.10.0") == -1 and C("1.0", "0.9.9") == 1 and C("0.2", "0.2.0") == 0)
assert(C("dev", "0.2.0") == nil and C("0.2.0", nil) == nil)

A.ns.version, B.ns.version = "0.2.0", "0.3.0"
A.env.SlashCmdList.FOSTBRAEDR("brother add Thorgrim Stormfjord")
B.env.SlashCmdList.FOSTBRAEDR("brother add Ragnar Stormfjord")
sim.Run(20)
local function count(c, pat) local n = 0 for _, t in ipairs(c.toasts) do if t:find(pat) then n = n + 1 end end return n end
assert(count(A, "Update available: Fostbraedr 0.3.0") == 1, "A should be nudged once")
assert(count(B, "Update available") == 0, "B is newer, no nudge")
A.ns.Sync.HelloAll(true)
sim.Run(20)
assert(count(A, "Update available") == 1, "only one nudge per version per session")
print("ALL OK")
