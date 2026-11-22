-- /fost synctest: shows who was heard, friends list state, and ignored senders.
-- Run: lua-5.1 tests/synctest_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local function Sender(f, l) return f .. " " .. l end
local A = sim.NewClient("Ragnar", "Stormfjord", Sender)
local B = sim.NewClient("Thorgrim", "Stormfjord", Sender)
local C = sim.NewClient("Brokk", "Ironside", Sender)   -- a new alt A doesn't know about
local ch = assert(loadfile("./Diagnostics.lua")); setfenv(ch, A.env); ch("Fostbraedr", A.ns)
local shown
A.ns.ShowTextWindow = function(_, text) shown = text end
A.env.C_FriendList = { GetFriendInfo = function(name)
  if name == "Thorgrim Stormfjord" then return { name = "Thorgrim Stormfjord", connected = true } end
end }
A.env.SlashCmdList.FOSTBRAEDR("brother add Thorgrim Stormfjord")
B.env.SlashCmdList.FOSTBRAEDR("brother add Ragnar Stormfjord")
C.env.SlashCmdList.FOSTBRAEDR("brother add Ragnar Stormfjord")
sim.Run(30)
A.env.SlashCmdList.FOSTBRAEDR("synctest")
print(shown)
assert(shown:find("Thorgrim Stormfjord %(on your list%): addon heard %d+s ago, ONLINE"), "B heard")
assert(shown:find("friends list: online as 'Thorgrim Stormfjord'", 1, true), "friends list state")
assert(shown:find("'Brokk Ironside': %d+ message%(s%), last .-: not on the brother list"), "unknown sender listed")
assert(shown:find("received %d+") and shown:find("Sending is on"), "counters")
-- the addon blocks sending in instances; the window says so
A.instance = "The Deadmines"
A.env.SlashCmdList.FOSTBRAEDR("synctest")
assert(shown:find("PAUSED"), "paused sending shown")
-- /fost ilvltest opens its window with and without the game's average
A.env.GetInventoryItemLink = function(_, slot) return slot == 16 and "|Hitem:5|h[Stick]|h" or nil end
A.env.C_Item = { GetDetailedItemLevelInfo = function() return 40 end }
A.env.SlashCmdList.FOSTBRAEDR("ilvltest")
assert(shown:find("Main hand") and shown:find("detailed 40") and shown:find("Rivalry uses: 2.5"), shown)
A.env.GetAverageItemLevel = function() return 42, 41.5 end
A.env.SlashCmdList.FOSTBRAEDR("ilvltest")
assert(shown:find("equipped 41.5") and shown:find("Rivalry uses: 41.5 %(GetAverageItemLevel%); your status sends 415"))
print("ALL OK")
