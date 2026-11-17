-- Fostbraedr: pop-up notices ("toasts") in the window's flat style.
-- ns.Notify(text, kind, { detail, icon, sound, force }) shows one; when toasts are
-- turned off it prints to chat instead (force = toast even when turned off).
local ADDON, ns = ...
local T = ns.Theme

local MAX_VISIBLE = 4
local HOLD, FADE = 5, 0.35
local W, H, GAP = 320, 48, 6
local RECENT = 10 * 60          -- only toast synced entries newer than this

local ICONS = {
    online = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    poke   = "Interface\\Icons\\Ability_Warrior_Charge",
    level  = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
    death  = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    boss   = "Interface\\Icons\\INV_Sword_04",
    loot   = "Interface\\Icons\\INV_Misc_Bag_10",
    manual = "Interface\\Icons\\INV_Misc_Note_01",
    info   = ns.ICON,
}

local CUSTOM_POKE_SOUND = "Interface\\AddOns\\Fostbraedr\\Sounds\\poke.ogg"

local anchor, active, pool = nil, {}, {}

local function PlayNotifySound(kind)
    if ns.db.settings.toastSound == false and kind ~= "poke" then return end
    if kind == "poke" then
        -- drop your own poke.ogg into the Sounds folder to customise it
        local willPlay = PlaySoundFile(CUSTOM_POKE_SOUND, "Master")
        if willPlay then return end
        if SOUNDKIT.READY_CHECK then PlaySound(SOUNDKIT.READY_CHECK, "Master") end
        return
    end
    local id = kind == "death" and SOUNDKIT.RAID_WARNING or SOUNDKIT.TELL_MESSAGE
    if id then PlaySound(id) end
end

local function Layout()
    for i, t in ipairs(active) do
        t:ClearAllPoints()
        t:SetPoint("TOP", anchor, "TOP", 0, -(i - 1) * (H + GAP))
    end
end

local function Release(t)
    t:Hide()
    t:SetScript("OnUpdate", nil)
    for i, a in ipairs(active) do
        if a == t then table.remove(active, i) break end
    end
    pool[#pool + 1] = t
    Layout()
end

local function OnUpdate(t, elapsed)
    t.age = t.age + elapsed
    local a
    if t.age < FADE then
        a = t.age / FADE
    elseif t.age < FADE + HOLD or t:IsMouseOver() then
        if t:IsMouseOver() then t.age = math.min(t.age, FADE + HOLD) end
        a = 1
    else
        a = 1 - (t.age - FADE - HOLD) / FADE
    end
    if a <= 0 then return Release(t) end
    t:SetAlpha(math.min(1, a))
end

local function NewToast()
    local t = table.remove(pool)
    if t then return t end
    t = CreateFrame("Button", nil, anchor)
    t:SetSize(W, H)
    t:SetFrameStrata("DIALOG")
    T.Panel(t, { 0.055, 0.058, 0.066, 0.94 }, { 0, 0, 0, 1 })
    local bar = t:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(unpack(T.colors.accent))
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMLEFT", 1, 1)
    bar:SetWidth(3)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(30, 30)
    t.icon:SetPoint("LEFT", 12, 0)
    t.text = T.Text(t, 13, T.colors.text)
    t.text:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 10, -1)
    t.text:SetPoint("RIGHT", -10, 0)
    t.text:SetWordWrap(false)
    t.detail = T.Text(t, 11, T.colors.muted)
    t.detail:SetPoint("TOPLEFT", t.text, "BOTTOMLEFT", 0, -3)
    t.detail:SetPoint("RIGHT", -10, 0)
    t.detail:SetWordWrap(false)
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    t:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then ns.ShowWindow() end
        Release(self)
    end)
    return t
end

local function ShowToast(text, kind, opts)
    if not anchor then
        anchor = CreateFrame("Frame", "FostbraedrToastAnchor", UIParent)
        anchor:SetSize(W, H)
        anchor:SetPoint("TOP", UIParent, "TOP", 0, -150)
    end
    while #active >= MAX_VISIBLE do Release(active[1]) end
    local t = NewToast()
    t.icon:SetTexture(opts.icon or ICONS[kind] or ICONS.info)
    if kind == "death" then t.icon:SetTexCoord(0, 1, 0, 1) else t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    t.text:SetText(text)
    t.detail:SetText(opts.detail or "")
    t.text:ClearAllPoints()
    if opts.detail then
        t.text:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 10, -1)
    else
        t.text:SetPoint("LEFT", t.icon, "RIGHT", 10, 0)
    end
    t.text:SetPoint("RIGHT", -10, 0)
    t.age = 0
    t:SetAlpha(0)
    t:Show()
    t:SetScript("OnUpdate", OnUpdate)
    active[#active + 1] = t
    Layout()
end

function ns.Notify(text, kind, opts)
    opts = opts or {}
    if not ns.db then return end
    if ns.db.settings.toasts == false and not opts.force then
        ns.Print(text .. (opts.detail and (" " .. opts.detail) or ""))
        return
    end
    ShowToast(text, kind, opts)
    if opts.sound ~= false then PlayNotifySound(opts.sound or kind) end
end

-- Toast brothers' fresh entries as they sync in.
local function EntryToast(e)
    local who = ns.People.DisplayName(e.author)
    local where = e.zone and (" in " .. e.zone) or ""
    if e.kind == "level" then
        return ("%s reached level %s!"):format(who, tostring(e.level or "?")), where ~= "" and where:sub(5) or nil
    elseif e.kind == "death" then
        return ("%s died%s"):format(who, where), e.level and ("at level " .. e.level) or nil
    elseif e.kind == "boss" then
        return ("%s defeated %s"):format(who, e.name or "a boss"), e.zone
    elseif e.kind == "loot" then
        return ("%s looted %s"):format(who, e.link or "something"), e.zone
    elseif e.kind == "manual" then
        return ("%s wrote in the chronicle"):format(who), e.text and ('"' .. e.text .. '"') or nil
    end
end

-- Were we in on this boss kill? (grouped with the brother, or we recorded it too)
local function WeWereThere(e)
    local myKey = ns.me and ns.NameKey(ns.me)
    for _, c in ipairs(e.with or {}) do
        if ns.NameKey(c) == myKey then return true end
    end
    for _, mine in pairs(ns.db.entries) do
        if mine.kind == "boss" and mine.author == ns.me and mine.name == e.name
            and math.abs((mine.time or 0) - (e.time or 0)) <= 10 * 60 then
            return true
        end
    end
    return false
end

ns.Listen("ENTRY_ADDED", function(e, fromPeer)
    if not fromPeer or not e.time or GetServerTime() - e.time > RECENT then return end
    if e.kind == "boss" and WeWereThere(e) then return end
    local text, detail = EntryToast(e)
    if not text then return end
    local icon
    if e.kind == "loot" and e.link and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(e.link) end
    ns.Notify(text, e.kind, { detail = detail, icon = icon })
end)
