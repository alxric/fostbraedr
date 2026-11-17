-- /fost loottest prints readable values and never touches secrets. Run: lua-5.1 tests/loottest_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local A = sim.NewClient("Ragnar", "Stormfjord", function(f, l) return f .. " " .. l end)
local env, ns = A.env, A.ns
local ch = assert(loadfile("./Diagnostics.lua")); setfenv(ch, env); ch("Fostbraedr", ns)
local SECRET = {}
env.issecretvalue = function(v) return v == SECRET end
env.C_LootHistory = {
  GetAllEncounterInfos = function() return { { encounterID = 7, encounterName = "VanCleef" } } end,
  GetSortedDropsForEncounter = function() return { { lootListID = 1 }, { lootListID = 2 } } end,
  GetSortedInfoForDrop = function(e, id)
    if id == 1 then return { itemHyperlink = "[Cape]", winner = { playerName = "Thorgrim", roll = 88 }, rollInfos = {
      { playerName = "Thorgrim", roll = 88, state = 0, isSelf = false }, { playerName = "Ragnar", roll = 12, state = 0, isSelf = true } } } end
    return { itemHyperlink = SECRET, winner = SECRET, allPassed = SECRET, rollInfos = SECRET }
  end }
env.SlashCmdList.FOSTBRAEDR("loottest")
env.C_LootHistory = nil
env.SlashCmdList.FOSTBRAEDR("loottest")
print("ALL OK")
