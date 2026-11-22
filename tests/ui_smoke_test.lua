-- Builds the whole window with mock frames (any method is accepted) to catch nil
-- calls and typos in UI code paths. Run: lua-5.1 tests/ui_smoke_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local A = sim.NewClient("Ragnar", "Stormfjord", function(f, l) return f .. " " .. l end)
local env, ns = A.env, A.ns

local calls = {}
local function Mock(kind)
    local m = { __kind = kind, scripts = {} }
    return setmetatable(m, { __index = function(t, k)
        if k:match("^[a-z_]") then return nil end
        calls[k] = (calls[k] or 0) + 1
        if k == "GetWidth" then return function() return 600 end end
        if k == "GetText" then return function() return t.__text or "" end end
        if k == "SetText" then return function(self, v) self.__text = v end end
        if k == "IsEnabled" or k == "IsVisible" or k == "IsShown" then return function() return true end end
        if k == "SetScript" then return function(self, n, f) self.scripts[n] = f end end
        if k == "GetScript" then return function(self, n) return self.scripts[n] end end
        if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 10, 20 end end
        if k:match("^Create") then return function() return Mock(k) end end
        if k:match("^Get") or k:match("^Is") or k:match("^Has") then return function() return nil end end
        return function() end
    end })
end
env.CreateFrame = function(kind, name) local f = Mock(kind) if name then env[name] = f end return f end
env.UIParent = Mock("UIParent")
env.UISpecialFrames = {}
env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
env.SOUNDKIT = {}
env.PlaySound = function() end
env.GameTooltip = Mock("GameTooltip")
env.Minimap = Mock("Minimap")
local rowInits = {} -- one per list, in tab build order
env.CreateScrollBoxListLinearView = function()
    local v = Mock("view")
    rawset(v, "SetElementInitializer", function(_, _, fn) rowInits[#rowInits + 1] = fn end)
    return v
end
env.ScrollUtil = { InitScrollBoxListWithScrollBar = function() end }
env.CreateDataProvider = function(rows) return rows end
env.ScrollBoxConstants = {}
env.C_Item = { GetItemIconByID = function() return 123 end }
env.PixelUtil = { SetHeight = function() end, SetWidth = function() end }
env.C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 86400 end }

env.PlaySoundFile = function() return false end
env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
env.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior" }
for _, f in ipairs({ "QuestItems.lua", "Gear.lua", "Theme.lua", "Toast.lua", "UI.lua", "ChronicleUI.lua", "RivalryUI.lua", "FamilyUI.lua", "NamesUI.lua", "QuestItemsUI.lua", "GearUI.lua", "SettingsUI.lua", "Minimap.lua" }) do
    local ch = assert(loadfile("./" .. f)); setfenv(ch, env); ch("Fostbraedr", ns)
end
A.fire("PLAYER_LOGIN")
env.SlashCmdList.FOSTBRAEDR("brother add Thorgrim Stormfjord")
A.fire("PLAYER_DEAD")
A.fire("PLAYER_LEVEL_UP", 21)
ns.AddEntry("loot", { link = "|cnIQ4:|Hitem:1::::|h[X]|h|r" })
ns.AddEntry("manual", { text = "hello" })
ns.AddEntry("roll", { roll = 50 })

ns.ShowWindow()
local frame = env.FostbraedrMainFrame
assert(frame, "main frame not created")
frame.scripts.OnShow()
-- render chronicle rows through the initializer
local rows = ns.BuildChronicleRows()
assert(#rows == 4, "expected 4 visible rows, got " .. #rows)
local rowInit = rowInits[1] -- the Chronicle tab is built first
assert(rowInit, "row initializer not registered")
for _, r in ipairs(rows) do
    local rowFrame = Mock("row")
    rowInit(rowFrame, r)
    rowInit(rowFrame, r) -- reuse path
    rowFrame.scripts.OnEnter(rowFrame)
    rowFrame.scripts.OnLeave(rowFrame)
end
-- click every nav item and every button-ish thing we can reach
for i, tab in ipairs(frame.tabs) do
    tab.nav.scripts.OnEnter(tab.nav)
    tab.nav.scripts.OnClick(tab.nav)
    tab.nav.scripts.OnLeave(tab.nav)
    if tab.panel.Refresh then tab.panel:Refresh() end
end
-- family tab with a known peer
ns.db.peers["Thorgrim Stormfjord"] = { level = 22, zone = "Westfall", class = "WARRIOR", activity = "Questing", status = "afk soon", lastSeen = env.GetServerTime() - 4000 }
frame.tabs[3].panel:Refresh()
ns.Fire("PEER_STATUS", "Thorgrim Stormfjord")
-- toasts: show five (max 4 visible), animate, click one
for i = 1, 5 do ns.Notify("Toast " .. i, i == 5 and "poke" or "death", { detail = i % 2 == 0 and "detail" or nil }) end
local anchor = env.FostbraedrToastAnchor
assert(anchor, "toast anchor missing")
-- a synced entry from a brother should toast
ns.Sync.Accept({ author = "Thorgrim Stormfjord", n = 1, time = env.GetServerTime(), kind = "death", zone = "Duskwood", level = 22 })
ns.Fire("ENTRY_ADDED", ns.db.entries["Thorgrim Stormfjord#1"], "Thorgrim Stormfjord")
ns.db.settings.toasts = false
ns.Notify("in chat instead", "info")
env.SlashCmdList.FOSTBRAEDR("toasts")
env.SlashCmdList.FOSTBRAEDR("status testing things")
env.SlashCmdList.FOSTBRAEDR("poke thorgrim hi")
-- settings tab: refresh, click a quality, flip toggles, add/remove brothers
local settings
for _, tab in ipairs(frame.tabs) do if tab.def.key == "settings" then settings = tab end end
assert(settings and settings.def.key == "settings", "settings tab missing")
settings.panel:Refresh()
env.ITEM_QUALITY_COLORS = { [3] = { hex = "ff0070dd" } }
ns.Fire("SETTINGS_CHANGED")
assert(ns.AddBrother("Brokk Stormfjord") == "Brokk Stormfjord")
assert(ns.AddBrother("brokk stormfjord") == nil, "duplicate should be refused")
assert(ns.AddBrother("Ragnar Stormfjord") == nil, "adding yourself should be refused")
assert(ns.RemoveBrother("BROKK STORMFJORD") == "Brokk Stormfjord")
-- quest items tab: rows with a heading and an item, tooltip, click
local qrows = ns.BuildQuestItemRows({ counts = { delete = 1 }, items = {
    { group = "delete", itemID = 5, name = "Candle", count = 2, bag = 0, slot = 1, reason = "old" } } })
assert(#qrows == 2 and qrows[1].heading, "heading row then item row")
env.ClearCursor = function() end
env.C_Container = { GetContainerItemInfo = function() return { itemID = 5 } end, PickupContainerItem = function() end }
for _, r in ipairs(qrows) do
    local rowFrame = Mock("row")
    rowInits[#rowInits](rowFrame, r) -- Quest items is the last tab with a list
    rowFrame.scripts.OnEnter(rowFrame)
    rowFrame.scripts.OnClick(rowFrame)
    rowFrame.scripts.OnLeave(rowFrame)
end
-- gear tab: as a warrior (note only), then as a druid with and without saved sets
local gear
for _, tab in ipairs(frame.tabs) do if tab.def.key == "gear" then gear = tab end end
assert(gear, "gear tab missing")
gear.panel:Refresh()
env.UnitClass = function() return "Druid", "DRUID" end
ns.Gear.ForgetClass()
env.GetShapeshiftFormID = function() return 1 end
gear.panel:Refresh()
env.GetInventoryItemID = function(_, slot) return slot == 16 and 101 or nil end
env.GetInventoryItemLink = function() return "|Hitem:101|h[Dagger]|h" end
ns.Gear.SaveCurrent("cat")
gear.panel:Refresh()
ns.Fire("GEAR_CHANGED")
env.UnitClass = function() return "Warrior", "WARRIOR" end
ns.Gear.ForgetClass()
-- copyable text window
ns.ShowTextWindow("Test", "line 1\n|cnIQ4:|Hitem:5::::|h[X]|h|r | y")
ns.ShowTextWindow("Again", "reuse")
assert(env.FostbraedrTextWindow, "text window missing")
ns.ToggleWindow()
ns.ResetWindow()
print("ALL OK")
