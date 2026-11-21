-- Fostbraedr: main window. Flat dark frame with a title bar, a sidebar of tabs
-- and a content area. Each tab's content is built by ns[def.build](panel).
local ADDON, ns = ...
local T = ns.Theme

local FRAME_NAME = "FostbraedrMainFrame"
local WIDTH, HEIGHT = 780, 480
local TITLE_H, SIDEBAR_W, PAD = 32, 150, 14

local TABS = {
    { key = "chronicle", title = "Chronicle", icon = "Interface\\Icons\\INV_Misc_Book_09", build = "BuildChronicleTab" },
    { key = "rivalry",   title = "Rivalry",   icon = "Interface\\Icons\\Ability_Warrior_BattleShout", build = "BuildRivalryTab" },
    { key = "family",    title = "Family",    icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", build = "BuildFamilyTab" },
    { key = "frames",    title = "Frames",    icon = "Interface\\Icons\\INV_Misc_Spyglass_03", build = "BuildFramesTab" },
    { key = "questitems", title = "Quest items", icon = "Interface\\Icons\\INV_Misc_Bag_08", build = "BuildQuestItemsTab" },
    { key = "gear",      title = "Gear",      icon = "Interface\\Icons\\Ability_Druid_CatForm", build = "BuildGearTab" },
    { key = "settings",  title = "Settings",  icon = "Interface\\Icons\\INV_Misc_Gear_01", build = "BuildSettingsTab" },
}

local frame -- created lazily on first show

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    local w = ns.db.settings.window
    w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
end

local function RestorePosition()
    local w = ns.db.settings.window
    frame:ClearAllPoints()
    if w.point then
        frame:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

-------------------------------------------------------------------------------
-- Sidebar navigation
-------------------------------------------------------------------------------
local function PaintNav(item)
    local c = T.colors
    if item.selected then
        item.bar:Show()
        item.bg:SetColorTexture(c.accent[1], c.accent[2], c.accent[3], 0.10)
        item.label:SetTextColor(unpack(c.accent))
        item.icon:SetDesaturated(false)
        item.icon:SetAlpha(1)
    else
        item.bar:Hide()
        item.bg:SetColorTexture(1, 1, 1, item.hover and 0.05 or 0)
        item.label:SetTextColor(unpack(item.hover and c.text or c.muted))
        item.icon:SetDesaturated(not item.hover)
        item.icon:SetAlpha(item.hover and 1 or 0.7)
    end
end

local function SelectTab(index)
    if not frame.tabs[index] then index = 1 end
    for i, tab in ipairs(frame.tabs) do
        local on = i == index
        tab.nav.selected = on
        PaintNav(tab.nav)
        tab.panel:SetShown(on)
        if on then
            frame.heading:SetText(tab.def.title)
            if tab.panel.Refresh then tab.panel:Refresh() end
        end
    end
    ns.db.settings.lastTab = index
end

local function CreateNavItem(parent, index, def)
    local item = CreateFrame("Button", nil, parent)
    item:SetHeight(34)
    item:SetPoint("TOPLEFT", 0, -(TITLE_H + 10) - (index - 1) * 36)
    item:SetPoint("RIGHT", parent, "RIGHT", -1, 0)
    item.bg = T.Fill(item, { 0, 0, 0, 0 })
    item.bar = item:CreateTexture(nil, "ARTWORK")
    item.bar:SetColorTexture(unpack(T.colors.accent))
    item.bar:SetPoint("TOPLEFT")
    item.bar:SetPoint("BOTTOMLEFT")
    item.bar:SetWidth(3)
    item.icon = item:CreateTexture(nil, "ARTWORK")
    item.icon:SetSize(18, 18)
    item.icon:SetPoint("LEFT", 16, 0)
    item.icon:SetTexture(def.icon)
    item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    item.label = T.Text(item, 13)
    item.label:SetPoint("LEFT", item.icon, "RIGHT", 10, 0)
    item.label:SetText(def.title)
    item:SetScript("OnEnter", function(self) self.hover = true PaintNav(self) end)
    item:SetScript("OnLeave", function(self) self.hover = nil PaintNav(self) end)
    item:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        SelectTab(index)
    end)
    return item
end

-- "● 1 of 2 brothers online" at the bottom of the sidebar.
local function UpdateOnline()
    if not frame then return end
    local online, total = 0, 0
    for _, person in ipairs(ns.People.Brothers()) do
        total = total + 1
        if ns.Sync and ns.Sync.PersonOnline(person.chars[1]) then online = online + 1 end
    end
    local c = online > 0 and T.colors.good or T.colors.muted
    frame.dot:SetColorTexture(c[1], c[2], c[3], 1)
    if total == 0 then
        frame.online:SetText("no brothers added")
    else
        frame.online:SetText(("%d of %d online"):format(online, total))
    end
end
ns.UpdateOnlineIndicator = UpdateOnline

local function MakeDraggable(region)
    region:EnableMouse(true)
    region:RegisterForDrag("LeftButton")
    region:SetScript("OnDragStart", function() frame:StartMoving() end)
    region:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
    end)
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------
local function CreateMainFrame()
    frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    T.Panel(frame, T.colors.bg, { 0, 0, 0, 1 })

    -- Soft shadow around the window.
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetColorTexture(0, 0, 0, 0.35)
    shadow:SetPoint("TOPLEFT", -4, 4)
    shadow:SetPoint("BOTTOMRIGHT", 4, -4)

    -- Sidebar.
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", 1, -1)
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(SIDEBAR_W)
    T.Fill(sidebar, T.colors.sidebar)
    local sep = sidebar:CreateTexture(nil, "BORDER")
    sep:SetColorTexture(unpack(T.colors.border))
    sep:SetPoint("TOPRIGHT")
    sep:SetPoint("BOTTOMRIGHT")
    sep:SetWidth(1)
    MakeDraggable(sidebar)

    -- Brand: a small gold diamond and the name.
    local logo = sidebar:CreateTexture(nil, "ARTWORK")
    logo:SetSize(10, 10)
    logo:SetPoint("TOPLEFT", 18, -11)
    logo:SetColorTexture(unpack(T.colors.accent))
    logo:SetRotation(math.rad(45))
    local brand = T.Text(sidebar, 13, T.colors.accent)
    brand:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    brand:SetText("FOSTBRAEDR")

    -- Title bar over the content area: drag handle, heading, close button.
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", SIDEBAR_W + 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(TITLE_H)
    MakeDraggable(titleBar)

    frame.heading = T.Text(titleBar, 15, T.colors.text)
    frame.heading:SetPoint("LEFT", PAD, 0)
    local line = T.Divider(titleBar)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")

    local close = CreateFrame("Button", nil, titleBar)
    close:SetSize(TITLE_H, TITLE_H - 1)
    close:SetPoint("TOPRIGHT")
    local closeBg = T.Fill(close, { 0, 0, 0, 0 })
    local x = T.Text(close, 14, T.colors.muted)
    x:SetPoint("CENTER")
    x:SetJustifyH("CENTER")
    x:SetText("X")
    close:SetScript("OnEnter", function()
        closeBg:SetColorTexture(T.colors.bad[1], T.colors.bad[2], T.colors.bad[3], 0.3)
        x:SetTextColor(unpack(T.colors.text))
    end)
    close:SetScript("OnLeave", function()
        closeBg:SetColorTexture(0, 0, 0, 0)
        x:SetTextColor(unpack(T.colors.muted))
    end)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Online indicator.
    frame.dot = sidebar:CreateTexture(nil, "ARTWORK")
    frame.dot:SetSize(7, 7)
    frame.dot:SetPoint("BOTTOMLEFT", 18, 18)
    frame.online = T.Text(sidebar, 11, T.colors.muted)
    frame.online:SetPoint("LEFT", frame.dot, "RIGHT", 8, 0)

    -- Close with Escape.
    table.insert(UISpecialFrames, FRAME_NAME)

    -- Tabs.
    frame.tabs = {}
    for i, def in ipairs(TABS) do
        local panel = CreateFrame("Frame", nil, frame)
        panel:SetPoint("TOPLEFT", SIDEBAR_W + 1 + PAD, -(TITLE_H + PAD))
        panel:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        panel:Hide()
        if def.build and ns[def.build] then
            ns[def.build](panel)
        else
            local text = T.Text(panel, 13, T.colors.muted)
            text:SetPoint("CENTER")
            text:SetText(def.placeholder or "")
        end
        frame.tabs[i] = { def = def, panel = panel, nav = CreateNavItem(sidebar, i, def) }
    end

    frame:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        UpdateOnline()
    end)
    frame:SetScript("OnHide", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end)

    RestorePosition()
    SelectTab(ns.db.settings.lastTab or 1)
end

ns.Listen("PEER_ONLINE", UpdateOnline)
ns.Listen("PEER_OFFLINE", UpdateOnline)
ns.Listen("BROTHERS_CHANGED", UpdateOnline)
ns.Listen("PEOPLE_CHANGED", UpdateOnline)

function ns.ShowWindow()
    if not ns.db then return end
    if not frame then CreateMainFrame() end
    frame:Show()
end

function ns.HideWindow()
    if frame then frame:Hide() end
end

function ns.ToggleWindow()
    if frame and frame:IsShown() then ns.HideWindow() else ns.ShowWindow() end
end

function ns.ResetWindow()
    wipe(ns.db.settings.window)
    if frame then RestorePosition() end
end
