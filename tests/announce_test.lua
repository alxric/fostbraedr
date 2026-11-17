-- Hidden entries (stats snapshots, rolls) sync silently; only old timeline
-- entries are announced in chat. Run: lua-5.1 tests/announce_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local function Sender(f, l) return f .. " " .. l end
local A = sim.NewClient("Ragnar", "Stormfjord", Sender)
local B = sim.NewClient("Thorgrim", "Stormfjord", Sender)
A.env.SlashCmdList.FOSTBRAEDR("brother add Thorgrim Stormfjord")
B.env.SlashCmdList.FOSTBRAEDR("brother add Ragnar Stormfjord")
-- B has history before contact: 2 old timeline entries, 1 old snapshot
local old = B.env.GetServerTime() - 3600
B.ns.AddEntry("manual", { text = "old one" }).time = old
B.ns.AddEntry("death", {}).time = old
B.ns.AddEntry("tally", { quests = 3 }).time = old
sim.Run(30)
local function received(c)
    local n = 0
    for _, m in ipairs(c.chat) do
        local k = m:match("Received (%d+) chronicle")
        if k then n = n + tonumber(k) end
    end
    return n
end
assert(received(A) == 2, "catch-up should announce the 2 old timeline entries, got " .. received(A))
-- live: a stats snapshot and a roll arrive silently
B.ns.AddEntry("tally", { quests = 1 })
B.ns.AddEntry("roll", { roll = 50 })
sim.Run(20)
assert(received(A) == 2, "hidden entries must not be announced")
-- live: a fresh timeline entry arrives but isn't counted in chat (it gets a
-- pop-up in game; Toast.lua isn't loaded in the simulator)
local e = B.ns.AddEntry("manual", { text = "fresh" })
sim.Run(20)
assert(A.ns.db.entries[e.id], "fresh entry should arrive")
assert(received(A) == 2, "fresh entries are announced by pop-up, not chat")
print("ALL OK")
