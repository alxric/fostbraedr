-- Fostbraedr: people (accounts) and their characters.
--
-- Each copy has an account identity in FostbraedrDB.account = { id, name }:
-- a random id made once, and a person name (default: first name of the first
-- character that logged in; editable in Settings). Saved variables are
-- account-wide, so db.myChars already lists every character on the account.
--
-- HI messages carry { id, name, chars } so brothers learn which characters
-- belong to whom. You only need to add one character per brother; his other
-- characters are linked automatically when his addon says hello.
--
-- db.people[id] = { name, chars = { ["First Last"] = true }, lastSeen }
local ADDON, ns = ...

local People = {}
ns.People = People

local MAX_CHARS = 60
local MAX_NAME = 24

local function Key(n) return ns.NameKey(n) end

-------------------------------------------------------------------------------
-- Our own account
-------------------------------------------------------------------------------
function People.MyId() return ns.db and ns.db.account.id end
function People.MyName() return ns.db and ns.db.account.name end

local function CleanName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("[|%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return name:sub(1, MAX_NAME)
end

local index -- [nameKey] = person id (ours included); rebuilt lazily
function People.Invalidate()
    index = nil
    ns.Fire("PEOPLE_CHANGED")
end

ns.On("PLAYER_LOGIN", function()
    local a = ns.db.account
    if not a.id then a.id = ("%x%06x"):format(GetServerTime(), math.random(0, 0xFFFFFF)) end
    if not a.name and ns.me then a.name = ns.FirstName(ns.me) end
    index = nil
end)

function People.SetMyName(name)
    name = CleanName(name)
    if not name then return ns.Print("Your name can't be empty.") end
    ns.db.account.name = name
    People.Invalidate()
    if ns.StatusChanged then ns.StatusChanged() end
    return name
end

-- What we tell brothers about ourselves.
function People.MyAccount(withChars)
    local a = { id = People.MyId(), name = People.MyName() }
    if withChars then
        a.chars = {}
        for c in pairs(ns.db.myChars) do a.chars[#a.chars + 1] = c end
        table.sort(a.chars)
    end
    return a
end

-------------------------------------------------------------------------------
-- Lookups
-------------------------------------------------------------------------------
local function Rebuild()
    index = {}
    for id, p in pairs(ns.db.people) do
        for c in pairs(p.chars or {}) do index[Key(c)] = id end
    end
    local mine = People.MyId()
    if mine then
        for c in pairs(ns.db.myChars) do index[Key(c)] = mine end
    end
end

-- Person id for a character, or nil if it isn't linked to anyone.
function People.Of(char)
    if not char then return nil end
    if not index then Rebuild() end
    return index[Key(char)]
end

function People.Name(id)
    if not id then return nil end
    if id == People.MyId() then return People.MyName() end
    local p = ns.db.people[id]
    return p and p.name
end

-- "Thorgrim" when the person's name is the character's first name, else
-- "Thorgrim (Brokk)". Unlinked characters show their first name.
function People.DisplayName(char)
    local first = ns.FirstName(char)
    local pname = People.Name(People.Of(char))
    if pname and pname:lower() ~= first:lower() then
        return pname .. " (" .. first .. ")"
    end
    return pname or first
end

-- Key for grouping a character's data by person ("char:..." when unlinked).
function People.GroupKey(char)
    return People.Of(char) or ("char:" .. (Key(char) or "?"))
end

-- A brother's character: listed by us, or linked to a brother's account.
function People.IsKin(char)
    if ns.IsBrother(char) then return true end
    local id = People.Of(char)
    return id ~= nil and id ~= People.MyId()
end

-- Every brother character we know: listed ones plus linked alts. Sorted.
function People.KinChars()
    local seen, list = {}, {}
    local function Add(c)
        local k = Key(c)
        if k and not seen[k] then
            seen[k] = true
            list[#list + 1] = c
        end
    end
    for c in pairs(ns.db.settings.brothers) do Add(c) end
    local mine = People.MyId()
    for id, p in pairs(ns.db.people) do
        if id ~= mine then
            for c in pairs(p.chars or {}) do Add(c) end
        end
    end
    table.sort(list)
    return list
end

-- Brothers as people: { { key, name, chars = {...} }, ... } sorted by name.
-- Characters that aren't linked yet stand alone.
function People.Brothers()
    local byKey, list = {}, {}
    for _, c in ipairs(People.KinChars()) do
        local k = People.GroupKey(c)
        local person = byKey[k]
        if not person then
            person = { key = k, name = People.Name(People.Of(c)) or ns.FirstName(c), chars = {} }
            byKey[k] = person
            list[#list + 1] = person
        end
        person.chars[#person.chars + 1] = c
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

-- Other characters of the same person (including char itself).
function People.SiblingChars(char)
    local id = People.Of(char)
    if not id then return { char } end
    local list = {}
    for _, c in ipairs(People.KinChars()) do
        if People.Of(c) == id then list[#list + 1] = c end
    end
    return list
end

-------------------------------------------------------------------------------
-- Learning from brothers
-------------------------------------------------------------------------------
-- Record what a brother's character told us about its account (from HI or ST).
-- `acct.chars` is optional (ST only carries id and name).
function People.Record(fromChar, acct)
    if type(acct) ~= "table" or type(acct.id) ~= "string" then return end
    local id = acct.id:sub(1, 32)
    if id == People.MyId() then return end
    local p = ns.db.people[id]
    local changed = false
    if not p then
        p = { chars = {} }
        ns.db.people[id] = p
        changed = true
    end
    local name = CleanName(acct.name) or p.name or ns.FirstName(fromChar)
    if p.name ~= name then p.name, changed = name, true end
    if type(acct.chars) == "table" then
        local chars = { [fromChar] = true }
        for i, c in ipairs(acct.chars) do
            if i > MAX_CHARS then break end
            local n = type(c) == "string" and ns.NormalizeName(c)
            if n then chars[n] = true end
        end
        for c in pairs(chars) do if not p.chars[c] then changed = true end end
        for c in pairs(p.chars) do if not chars[c] then changed = true end end
        p.chars = chars
    elseif not p.chars[fromChar] then
        p.chars[fromChar] = true
        changed = true
    end
    p.lastSeen = GetServerTime()
    -- a character belongs to one account: drop it from any other person
    for otherId, other in pairs(ns.db.people) do
        if otherId ~= id then
            for c in pairs(p.chars) do
                if other.chars and other.chars[c] then other.chars[c] = nil changed = true end
            end
            if not next(other.chars or {}) then ns.db.people[otherId] = nil end
        end
    end
    if changed then People.Invalidate() end
end

-- Called when a character is removed from the brother list: forget the person
-- it belonged to unless another of their characters is still listed.
function People.ForgetIfUnlisted(char)
    local id = People.Of(char)
    if not id or id == People.MyId() then return end
    local p = ns.db.people[id]
    if not p then return end
    for c in pairs(p.chars) do
        if ns.IsBrother(c) then return end
    end
    ns.db.people[id] = nil
    People.Invalidate()
end

-- Just the person's name (or the character's first name when unlinked).
function People.ShortName(char)
    return People.Name(People.Of(char)) or ns.FirstName(char)
end

-- Display name for a grouping key from GroupKey().
function People.KeyName(key, sampleChar)
    if key and not key:find("^char:") then
        local n = People.Name(key)
        if n then return n end
    end
    return sampleChar and ns.FirstName(sampleChar) or "?"
end
