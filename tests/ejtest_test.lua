-- /fost ejtest handles a missing and a present Encounter Journal API. Run: lua-5.1 tests/ejtest_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local A = sim.NewClient("Ragnar", "Stormfjord", function(f, l) return f .. " " .. l end)
local env, ns = A.env, A.ns
local ch = assert(loadfile("./Diagnostics.lua")); setfenv(ch, env); ch("Fostbraedr", ns)
local shown = {}
ns.ShowTextWindow = function(title, text) shown[#shown + 1] = text print("[window: " .. title .. "]\n" .. text) end
env.SlashCmdList.FOSTBRAEDR("ejtest")            -- no EJ API at all
env.EJ_GetNumTiers = function() return 1 end
env.EJ_SelectTier = function() end
env.EJ_GetInstanceByIndex = function(i, raid) if raid then return nil end if i <= 2 then return 100 + i, i == 1 and "Deadmines" or "Scarlet Monastery" end end
env.EJ_SelectInstance = function() end
env.EJ_GetEncounterInfoByIndex = function(i) if i <= 2 then return "Boss " .. i end end
env.EJ_GetNumLoot = function() return 2 end
env.C_EncounterJournal = { GetLootInfoByIndex = function(i) return { link = "[Item" .. i .. "]", slot = "Chest", encounterID = 7 } end }
env.C_Item = { GetItemInfo = function() return "x", "y", 3, 30, 25, nil, nil, nil, "INVTYPE_CHEST" end,
               GetItemStats = function() return { ITEM_MOD_STRENGTH_SHORT = 5 } end }
env.SlashCmdList.FOSTBRAEDR("ejtest scarlet")
assert(shown[1]:find("No Encounter Journal API"), "early stop still shows the window")
assert(shown[2]:find("Scarlet Monastery") and shown[2]:find("req 25"), "dungeon details in the window")
assert(#shown == 2, "each run should open the window once")
print("ALL OK")
