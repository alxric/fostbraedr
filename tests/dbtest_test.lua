-- /fost dbtest with ForeverDB missing and with a small fake ForeverDB. Run: lua-5.1 tests/dbtest_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local A = sim.NewClient("Ragnar", "Stormfjord", function(f, l) return f .. " " .. l end)
local env, ns = A.env, A.ns
local ch = assert(loadfile("./Diagnostics.lua")); setfenv(ch, env); ch("Fostbraedr", ns)
local shown = {}
ns.ShowTextWindow = function(title, text) shown[#shown + 1] = text print("[window: " .. title .. "]\n" .. text) end

env.C_AddOns = { LoadAddOn = function() return false, "MISSING" end }
env.SlashCmdList.FOSTBRAEDR("dbtest")
assert(shown[1]:find("isn't available") and shown[1]:find("MISSING"), "missing ForeverDB reported")

env.C_AddOns = { LoadAddOn = function()
    env.ForeverDB = {
        meta = { date = "2026.11.18", items = 3 },
        dng = { [796] = { "Scarlet Monastery", 85 }, [717] = { "The Stockade" } },
        ind = { c3975 = { 796 }, c3974 = { 796 }, c1716 = { 717 } },
        npc = { [3975] = { "Herod", nil, 40, 40, 1 }, [3974] = { "Houndmaster Loksey" }, [1716] = { "Bazil" } },
        item = { [7717] = { "Ravager", 3, 37, 40 }, [7710] = { "Loksey's Training Stick", 3 }, [2941] = { "Prison Shank" } },
        drop = { [7717] = { "c3975", 2500 }, [7710] = { "c3974", 0 }, [2941] = { "c1716", 1100 } },
    }
    return true
end }
env.SlashCmdList.FOSTBRAEDR("dbtest scarlet")
local out = shown[2]
assert(out:find("ForeverDB loaded") and out:find("drop: 3 entries"), "tables listed")
assert(out:find("Ravager") and out:find("Loksey"), "Scarlet Monastery drops found")
assert(not out:find("Prison Shank"), "Stockade item must not be listed")
assert(out:find("2 items drop inside"), "count")
print("ALL OK")
