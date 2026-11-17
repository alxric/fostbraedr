-- /fost dump and /fost globals. Run: lua-5.1 tests/dump_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local A = sim.NewClient("Ragnar", "Stormfjord", function(f, l) return f .. " " .. l end)
local env, ns = A.env, A.ns
local ch = assert(loadfile("./Diagnostics.lua")); setfenv(ch, env); ch("Fostbraedr", ns)
local shown = {}
ns.ShowTextWindow = function(title, text) shown[#shown + 1] = text print("[" .. title .. "]\n" .. text) end
env.ForeverDB_DB = { items = { [7717] = { name = "Ravager", src = { "c3975" } } }, version = 3 }
env.ForeverDJ_Loot = { [1] = { 2, 3 } }
env.SlashCmdList.FOSTBRAEDR("dump ForeverDB_DB")
env.SlashCmdList.FOSTBRAEDR("dump ForeverDB_DB.items.7717")
env.SlashCmdList.FOSTBRAEDR("globals foreverdj")
env.SlashCmdList.FOSTBRAEDR("dump Nope")
assert(shown[1]:find("items: table, 1 entries") and shown[1]:find("version = 3"))
assert(shown[2]:find("name = \"Ravager\""))
assert(shown[3]:find("ForeverDJ_Loot %(table, 1 keys%)"))
assert(shown[4]:find("Nope is nil"))
print("ALL OK")
