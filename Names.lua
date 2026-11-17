-- Fostbraedr: show first names only on Blizzard's party and raid frames.
--
-- Display only: we change the text of the name label after Blizzard sets it.
-- Clicking still targets/whispers the real unit. We never touch secret values:
-- if a name is secret (restricted situations), the frame is left as it is.
--
-- settings.names = { enabled, raidFrames, partyFrames, mode = "all" | "family" }
local ADDON, ns = ...

local Names = {}
ns.Names = Names

local hookedParty = {}             -- party member frames we've hooked
local touched = setmetatable({}, { __mode = "k" }) -- frames whose text we changed

local function S() return ns.db.settings.names end

local function Secret(v) return v ~= nil and ns.IsSecret(v) end

-- Surnames of the family (ours and brothers'), lowercased.
local familySurnames
function Names.FamilySurnames()
    if familySurnames then return familySurnames end
    familySurnames = {}
    local function Add(char)
        local last = char and char:match("%s(%S+)$")
        if last then familySurnames[last:lower()] = true end
    end
    for c in pairs(ns.db.myChars) do Add(c) end
    for _, c in ipairs(ns.People.KinChars()) do Add(c) end
    return familySurnames
end
local function ResetFamily() familySurnames = nil end
ns.Listen("BROTHERS_CHANGED", ResetFamily)
ns.Listen("PEOPLE_CHANGED", ResetFamily)

-- "Thorgrim Stormfjord" -> "Thorgrim" under the current mode, or nil to leave it.
function Names.Shorten(first, last)
    if not first or not last or last == "" then return nil end
    if S().mode == "family" and not Names.FamilySurnames()[last:lower()] then return nil end
    return first
end

-- Apply to one name label for a unit. Returns true if it changed the text.
local function Apply(frame, label, unit)
    if not (frame and label and unit) then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
    local first, last = UnitName(unit)
    if Secret(first) or Secret(last) then return false end
    local short = Names.Shorten(first, last)
    if not short then
        -- this name shouldn't be shortened (any more): undo our earlier change
        if touched[frame] then
            touched[frame] = nil
            if not Secret(label:GetText()) then label:SetText(first .. ((last and last ~= "") and (" " .. last) or "")) end
        end
        return false
    end
    local current = label:GetText()
    if Secret(current) then return false end
    if current ~= short then
        label:SetText(short)
    end
    touched[frame] = { label = label, unit = unit }
    return true
end

-- Put the full name back on a frame we changed. We set the text ourselves
-- rather than calling Blizzard's update functions: addon code calling into the
-- raid frames is a classic source of taint ("action blocked") errors.
local function Restore(frame)
    local t = touched[frame]
    if not t then return end
    touched[frame] = nil
    local first, last = UnitName(t.unit)
    if Secret(first) or Secret(last) or not first then return end
    pcall(t.label.SetText, t.label, (last and last ~= "") and (first .. " " .. last) or first)
end

-------------------------------------------------------------------------------
-- Raid-style frames (CompactUnitFrame: compact party + raid frames)
-------------------------------------------------------------------------------
local function OnCompactName(frame)
    local s = S()
    if not (s.enabled and s.raidFrames) then return end
    local unit = frame.unit or frame.displayedUnit
    -- only party/raid members, not nameplates or other compact frames
    if not unit or not (unit:find("^party") or unit:find("^raid") or unit == "player") then return end
    pcall(Apply, frame, frame.name, unit)
end

-------------------------------------------------------------------------------
-- Classic party frames (PartyFrame member frames)
-------------------------------------------------------------------------------
local function PartyMemberFrames()
    local list = {}
    if PartyFrame then
        if PartyFrame.PartyMemberFramePool and PartyFrame.PartyMemberFramePool.EnumerateActive then
            for f in PartyFrame.PartyMemberFramePool:EnumerateActive() do list[#list + 1] = f end
        end
        for i = 1, 4 do
            local f = PartyFrame["MemberFrame" .. i]
            if f then list[#list + 1] = f end
        end
    end
    for i = 1, 4 do
        local f = _G["PartyMemberFrame" .. i]
        if f then list[#list + 1] = f end
    end
    return list
end

local function PartyLabel(f) return f.Name or f.name end

local function OnPartyName(f)
    local s = S()
    if not (s.enabled and s.partyFrames) then return end
    pcall(Apply, f, PartyLabel(f), f.unit)
end

local function HookPartyFrames()
    for _, f in ipairs(PartyMemberFrames()) do
        if not hookedParty[f] and f.UpdateName then
            hooksecurefunc(f, "UpdateName", OnPartyName)
            hookedParty[f] = true
        end
    end
end

-------------------------------------------------------------------------------
-- Refresh / restore
-------------------------------------------------------------------------------
local function CompactFrames()
    local list = {}
    if CompactPartyFrame and type(CompactPartyFrame.memberUnitFrames) == "table" then
        for _, f in ipairs(CompactPartyFrame.memberUnitFrames) do list[#list + 1] = f end
    end
    for i = 1, 5 do list[#list + 1] = _G["CompactPartyFrameMember" .. i] end
    for i = 1, 40 do list[#list + 1] = _G["CompactRaidFrame" .. i] end          -- "keep groups together" off
    for g = 1, 8 do
        for m = 1, 5 do list[#list + 1] = _G["CompactRaidGroup" .. g .. "Member" .. m] end -- on
    end
    return list
end

-- Apply the current settings to every frame we can find: shorten where enabled,
-- restore where not. Only sets label text; never calls Blizzard's functions.
function Names.Refresh()
    if InCombatLockdown() then
        Names.pendingRefresh = true
        return
    end
    Names.pendingRefresh = false
    HookPartyFrames()
    local s = S()
    local seen = {}
    for _, f in ipairs(CompactFrames()) do
        if f and not seen[f] then
            seen[f] = true
            if s.enabled and s.raidFrames then OnCompactName(f) else Restore(f) end
        end
    end
    for _, f in ipairs(PartyMemberFrames()) do
        if not seen[f] then
            seen[f] = true
            if s.enabled and s.partyFrames then
                if f.unit then OnPartyName(f) end
            else
                Restore(f)
            end
        end
    end
    -- anything else we changed that the lists above didn't cover
    if not s.enabled then
        for f in pairs(touched) do Restore(f) end
    end
end

ns.On("PLAYER_LOGIN", function()
    if CompactUnitFrame_UpdateName then
        hooksecurefunc("CompactUnitFrame_UpdateName", OnCompactName)
    end
    HookPartyFrames()
    C_Timer.After(2, Names.Refresh)
end)

ns.On("GROUP_ROSTER_UPDATE", function()
    HookPartyFrames()
    C_Timer.After(0.5, Names.Refresh)
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if Names.pendingRefresh then Names.Refresh() end
end)

ns.Listen("NAMES_CHANGED", Names.Refresh)
ns.Listen("BROTHERS_CHANGED", function() if S().mode == "family" then Names.Refresh() end end)
