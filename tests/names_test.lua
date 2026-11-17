-- First names only on party/raid frames, with fake Blizzard frames. Run: lua-5.1 tests/names_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local A = sim.NewClient("Ragnar", "Stormfjord", function(f, l) return f .. " " .. l end)
local env, ns = A.env, A.ns
A.partyFirst, A.partyLast = "Thorgrim", "Stormfjord"

local function Label() return { text = "", SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end } end
local function FullName(unit) local f, l = env.UnitName(unit) return l and (f .. " " .. l) or f end
-- Blizzard's functions set the full name; our hooks run after them
env.CompactUnitFrame_UpdateName = function(frame) frame.name:SetText(FullName(frame.unit)) end
local compact = { unit = "party1", name = Label() }
env.CompactPartyFrameMember1 = compact
local party = { unit = "party1", Name = Label(), IsShown = function() return true end }
function party:UpdateName() self.Name:SetText(FullName(self.unit)) end
env.PartyFrame = { MemberFrame1 = party }
A.fire("PLAYER_LOGIN") -- install hooks now that the fake frames exist

local s = ns.db.settings.names
env.CompactUnitFrame_UpdateName(compact); party:UpdateName()
assert(compact.name.text == "Thorgrim Stormfjord" and party.Name.text == "Thorgrim Stormfjord", "off by default")

s.enabled = true
ns.Fire("NAMES_CHANGED")
assert(compact.name.text == "Thorgrim" and party.Name.text == "Thorgrim", "should shorten when enabled")
env.CompactUnitFrame_UpdateName(compact)     -- Blizzard updates again later
assert(compact.name.text == "Thorgrim", "hook should re-apply after Blizzard's update")

s.raidFrames = false
ns.Fire("NAMES_CHANGED")
assert(compact.name.text == "Thorgrim Stormfjord" and party.Name.text == "Thorgrim", "raid-style off restores only those")
s.raidFrames = true

print("--- family mode: only family surnames")
s.mode = "family"
ns.Fire("NAMES_CHANGED")
assert(compact.name.text == "Thorgrim", "Stormfjord is our own surname, so it's family")
A.partyFirst, A.partyLast = "Random", "Stranger"
ns.Fire("NAMES_CHANGED")
assert(compact.name.text == "Random Stranger", "non-family surname stays in family mode")
s.mode = "all"
ns.Fire("NAMES_CHANGED")
assert(compact.name.text == "Random", "all mode shortens everyone")

print("--- secret names are left alone")
local SECRET = {}
env.issecretvalue = function(v) return v == SECRET end
local realUnitName = env.UnitName
env.UnitName = function(u) if u == "party1" then return SECRET, SECRET end return realUnitName(u) end
compact.name.text = "untouched"
local ok = pcall(ns.Names.Refresh)
assert(ok, "refresh must not error on secrets")
env.UnitName = realUnitName
env.issecretvalue = nil

print("--- in combat the refresh waits")
A.combat = true
s.enabled = false
ns.Fire("NAMES_CHANGED")
assert(ns.Names.pendingRefresh, "should defer in combat")
A.combat = false
A.fire("PLAYER_REGEN_ENABLED")
assert(not ns.Names.pendingRefresh)
assert(compact.name.text == "Random Stranger" and party.Name.text == "Random Stranger", "disabled after combat restores full names")
print("ALL OK")
