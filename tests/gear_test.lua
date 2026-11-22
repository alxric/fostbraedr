-- Form-based gear swap: druids only, retries when a cast or combat blocks it.
-- Run: lua-5.1 tests/gear_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local A = sim.NewClient("Ragnar", "Stormfjord", function(f, l) return f .. " " .. l end)
local env, ns = A.env, A.ns
local ch = assert(loadfile("./Gear.lua")); setfenv(ch, env); ch("Fostbraedr", ns)
local G = ns.Gear
ns.ShowTextWindow = function(_, text) A.shown = text end

-- The character: worn items by slot, bag items by ID, and what the game refuses.
local DAGGER, MACE, SHIELD, TRINKET_A, TRINKET_B, MISSING = 101, 102, 103, 201, 202, 999
local worn = { [16] = MACE, [17] = SHIELD, [13] = TRINKET_B }
local bags = { [DAGGER] = 1, [TRINKET_A] = 1 }
local form, casting, combat, class = 0, nil, false, "WARRIOR"
local equips = 0
env.UnitClass = function() return class, class end
env.GetShapeshiftFormID = function() return form ~= 0 and form or nil end
env.UnitCastingInfo = function() return casting end
env.InCombatLockdown = function() return combat end
env.GetInventoryItemID = function(_, slot) return worn[slot] end
env.GetInventoryItemLink = function(_, slot) return worn[slot] and ("|Hitem:" .. worn[slot] .. "|h[Item " .. worn[slot] .. "]|h") end
env.C_Spell = { GetSpellCooldown = function() return { startTime = 0, duration = 0 } end }
env.C_Item = {
  GetItemCount = function(id) return bags[id] or 0 end,
  EquipItemByName = function(item, slot)
    equips = equips + 1
    local id = type(item) == "number" and item or tonumber(item:match("item:(%d+)"))
    local trinket = slot == 13 or slot == 14
    if casting or (combat and trinket) then
      A.fire("UI_ERROR_MESSAGE", 1, casting and "Can't do that while casting" or "Can't do that while in combat")
      return
    end
    if not bags[id] then return end
    bags[id] = nil
    if worn[slot] then bags[worn[slot]] = 1 end
    worn[slot] = id
  end,
}
local function Shift(f) form = f A.fire("UPDATE_SHAPESHIFT_FORM") end

-- 1. Not a druid: nothing happens, nothing is saved, nothing errors.
G.SaveCurrent("cat")
assert(next(ns.db.gear) == nil, "no gear data for a warrior")
Shift(1) Shift(0)
A.fire("UNIT_SPELLCAST_STOP", "player") A.fire("PLAYER_REGEN_ENABLED")
G.WearNow("cat")
sim.Run(3)
assert(equips == 0, "a warrior's stances never swap gear")
assert(not G.Active())
G.ShowLog()
assert(A.shown:find("druid=false"), "the log opens for other classes too")

-- 2. Druid: save both sets (cat = dagger + trinket A; other = mace + shield + trinket B).
class = "DRUID"
G.ForgetClass()
G.SaveCurrent("other")
worn[16], worn[17], worn[13] = DAGGER, nil, TRINKET_A
bags = { [MACE] = 1, [SHIELD] = 1, [TRINKET_B] = 1 }
G.SaveCurrent("cat")
assert(ns.db.gear["Ragnar Stormfjord"].sets.cat[16].id == DAGGER)
-- back to caster gear, swapping still off
worn[16], worn[17], worn[13] = MACE, SHIELD, TRINKET_B
bags = { [DAGGER] = 1, [TRINKET_A] = 1 }
Shift(1) sim.Run(1)
assert(worn[16] == MACE, "nothing swaps until it's switched on")

-- weapons on, trinkets off
local d = G.Data()
d.weapons = true
Shift(0) Shift(1) sim.Run(1)
assert(worn[16] == DAGGER and worn[13] == TRINKET_B, "cat form: dagger, trinket untouched")
Shift(0) sim.Run(1)
assert(worn[16] == MACE and worn[17] == SHIELD, "caster: mace and shield back")

-- 3. Leaving cat form straight into a cast: the swap waits, then happens when the cast ends.
Shift(1) sim.Run(1)
casting = "Healing Touch"
Shift(0) sim.Run(1)
assert(worn[16] == DAGGER, "blocked while casting")
casting = nil
A.fire("UNIT_SPELLCAST_STOP", "player") sim.Run(1)
assert(worn[16] == MACE, "swapped once the cast ended")
G.ShowLog()
assert(A.shown:find("Can't do that while casting"), "the game's error is logged")

-- 4. In combat addons can't equip (Forever: ADDON_ACTION_BLOCKED): don't even
-- try, and put the whole set on when combat ends.
d.trinkets = true
combat = true
local before = equips
Shift(1) sim.Run(8)
for _ = 1, 3 do A.fire("UNIT_SPELLCAST_STOP", "player") A.fire("UNIT_SPELLCAST_SUCCEEDED", "player") end
sim.Run(2)
assert(equips == before, "no equip calls in combat")
assert(worn[16] == MACE and worn[13] == TRINKET_B, "nothing changes in combat")
local waiting = 0
for _, l in ipairs(G.log) do if l:find("in combat addons can't equip") then waiting = waiting + 1 end end
assert(waiting == 1, "one log line per fight, got " .. waiting)
assert(G.status:find("when combat ends"))
G.WearNow("other")
assert(equips == before, "wear now does nothing in combat")
combat = false
A.fire("PLAYER_REGEN_ENABLED") sim.Run(1)
assert(worn[16] == DAGGER and worn[13] == TRINKET_A, "whole set on after combat")

-- 5. Wear now: stays on until the next form change.
G.WearNow("other") sim.Run(1)
assert(worn[16] == MACE, "wear now in cat form")
A.fire("UNIT_SPELLCAST_SUCCEEDED", "player") A.fire("PLAYER_REGEN_ENABLED") sim.Run(2)
assert(worn[16] == MACE, "wear now isn't undone by a cast or combat ending")
Shift(0) Shift(1) sim.Run(1)
assert(worn[16] == DAGGER, "a form change takes over again")

-- 6. An item that isn't in the bags is reported, not equipped.
d.sets.cat[16] = { id = MISSING }
Shift(0) sim.Run(1)
Shift(1) sim.Run(1)
assert(G.status:find("isn't in your bags"), "missing item reported")
G.ShowLog()
assert(A.shown:find("item 999 isn't in your bags"))

-- 7. Other units' casts are ignored, and a secret form ID doesn't break anything.
A.fire("UNIT_SPELLCAST_STOP", "target")
local SECRET = {}
env.issecretvalue = function(v) return v == SECRET end
env.GetShapeshiftFormID = function() return SECRET end
A.fire("UPDATE_SHAPESHIFT_FORM") sim.Run(1)
A.fire("UPDATE_SHAPESHIFT_FORM") sim.Run(1)
assert(G.WantedSet() == nil)
local unreadable = 0
for _, l in ipairs(G.log) do if l:find("can't read your form") then unreadable = unreadable + 1 end end
assert(unreadable == 2, "every unreadable form change is logged, got " .. unreadable)

-- 8. An unreadable class in combat doesn't turn the druid off.
env.UnitClass = function() return SECRET, SECRET end
assert(G.IsDruid(), "class remembered from before")

-- 9. A blocked equip call is logged, and the log is in the saved variables.
env.GetShapeshiftFormID = function() return form ~= 0 and form or nil end
d.sets.cat[16] = { id = DAGGER }
worn[16] = MACE bags[DAGGER] = 1
env.C_Item.EquipItemByName = function()
  A.fire("ADDON_ACTION_BLOCKED", "Fostbraedr", "EquipItemByName()")
  error("blocked")
end
Shift(0) Shift(1) sim.Run(1)
G.ShowLog()
assert(A.shown:find("the game blocked EquipItemByName"), "blocked action logged")
assert(A.shown:find("equip call failed"), "failed call logged")
assert(ns.db.gearLog == G.log and #ns.db.gearLog > 0, "log is saved")
assert(#G.log <= 60, "log stays short")
print("ALL OK")
