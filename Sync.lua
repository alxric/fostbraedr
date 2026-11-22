-- Fostbraedr: sync between brothers' copies.
--
-- Messages (tables, see Comm.lua for the wire format):
--   HI   { t, sv, av, hw = {[author] = n}, st = {level, zone, class}, r }
--        hw = highest counter per author such that we hold 1..n of them all.
--        r = true when this is a reply (don't reply to a reply).
--   E    { t, l = { entry, ... } }   entries without the redundant id field
--   PING { t, s }  ->  PONG { t, s }
--
-- On HI, each side sends the entries the other is missing. New local entries
-- are pushed live to brothers we've heard from recently. Entries are accepted
-- only from brothers, and only if authored by a brother or one of our own chars.
local ADDON, ns = ...

local Comm = ns.Comm
local SYNC_VERSION = 1          -- bump on incompatible message changes
local ONLINE_WINDOW = 10 * 60   -- heard from within this many seconds = online
local HELLO_INTERVAL = 5 * 60
local BATCH_BYTES = 1200        -- serialized entries per E message

local heard = {}                -- [name] = GetTime() of last message
local wentOffline = {}          -- [name] = GetTime() they said bye / were found offline
local lastWhisper = {}          -- [name] = GetTime() we last whispered them
local warnedNewer = {}          -- [version] = true: nudged about this version this session

local Sync = {}
ns.Sync = Sync

-------------------------------------------------------------------------------
-- Names / routing
-------------------------------------------------------------------------------
-- Forever's sender format isn't documented; accept "First Last", "First Last-X"
-- and "First-Last". Returns the family member's "First Last", or nil.
function ns.ResolveSender(sender)
    for _, candidate in ipairs({ ns.NormalizeName(sender), ns.NormalizeName((sender:gsub("%-", " "))) }) do
        if candidate and ns.IsFamily(candidate) then return candidate end
    end
end

local function IsMe(name)
    return ns.NameKey(name) == ns.NameKey(ns.me)
end

local function GroupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function InMyGroup(name)
    local key = ns.NameKey(name)
    for _, n in ipairs(ns.BrothersInGroup()) do
        if ns.NameKey(n) == key then return true end
    end
    return false
end

local function SendTo(name, msg)
    if InMyGroup(name) and GroupChannel() then
        Comm.Send(msg, GroupChannel())
    else
        Comm.Send(msg, "WHISPER", name)
    end
end

function ns.OnBeforeSend(channel, target)
    if channel == "WHISPER" and target then lastWhisper[target] = GetTime() end
end

local function IsOnline(name)
    return heard[name] and (GetTime() - heard[name] < ONLINE_WINDOW)
end
Sync.IsOnline = IsOnline

-- If the character is on our friends list and offline, don't whisper it.
local function KnownOffline(name)
    if not (C_FriendList and C_FriendList.GetFriendInfo) then return false end
    local ok, info = pcall(C_FriendList.GetFriendInfo, name)
    return ok and type(info) == "table" and info.connected == false
end

-- Every brother character: listed ones plus alts linked to their accounts.
local function Brothers()
    return ns.People.KinChars()
end

-- Send to every online brother: once to the group channel for those grouped
-- with us, and by whisper to the rest.
local function SendToOnline(msg)
    local viaGroup = false
    for _, name in ipairs(Brothers()) do
        if IsOnline(name) then
            if InMyGroup(name) and GroupChannel() then
                viaGroup = true
            else
                Comm.Send(msg, "WHISPER", name)
            end
        end
    end
    if viaGroup then Comm.Send(msg, GroupChannel()) end
end

-------------------------------------------------------------------------------
-- Entries
-------------------------------------------------------------------------------
-- Highest n per author such that entries 1..n are all present.
function Sync.HighWater()
    local maxN = {}
    for _, e in pairs(ns.db.entries) do
        if (maxN[e.author] or 0) < e.n then maxN[e.author] = e.n end
    end
    local hw = {}
    for author, top in pairs(maxN) do
        local n = 0
        while n < top and ns.db.entries[author .. "#" .. (n + 1)] do n = n + 1 end
        if n > 0 then hw[author] = n end
    end
    return hw
end

local function WireCopy(e)
    local c = {}
    for k, v in pairs(e) do
        if k ~= "id" then c[k] = v end
    end
    return c
end

-- What we recently sent each peer, so crossing HI messages don't make us send
-- the same entries twice. Forgotten after a while in case packets were lost.
local SENT_MEMORY = 120
local recentlySent = {}   -- [name] = { at = GetTime(), n = { [author] = highest n sent } }

-- Send `name` every entry above their high-water mark, in batches.
function Sync.SendMissing(name, theirHW)
    theirHW = type(theirHW) == "table" and theirHW or {}
    local rs = recentlySent[name]
    if not rs or GetTime() - rs.at > SENT_MEMORY then
        rs = { at = GetTime(), n = {} }
        recentlySent[name] = rs
    end
    local list = {}
    for _, e in pairs(ns.db.entries) do
        local theirs = math.max(tonumber(theirHW[e.author]) or 0, rs.n[e.author] or 0)
        if e.n > theirs then list[#list + 1] = e end
    end
    if #list == 0 then return 0 end
    rs.at = GetTime()
    for _, e in ipairs(list) do
        if (rs.n[e.author] or 0) < e.n then rs.n[e.author] = e.n end
    end
    table.sort(list, function(a, b)
        if a.author ~= b.author then return a.author < b.author end
        return a.n < b.n
    end)
    local batch, bytes = {}, 0
    for _, e in ipairs(list) do
        local copy = WireCopy(e)
        local size = #ns.Serialize.Encode(copy)
        if #batch > 0 and bytes + size > BATCH_BYTES then
            SendTo(name, { t = "E", l = batch })
            batch, bytes = {}, 0
        end
        batch[#batch + 1] = copy
        bytes = bytes + size
    end
    SendTo(name, { t = "E", l = batch })
    local visible = 0
    for _, e in ipairs(list) do
        if ns.TIMELINE_KINDS[e.kind] then visible = visible + 1 end
    end
    return visible
end

-- Validate and store an entry from the wire. Returns the entry if it was new.
function Sync.Accept(e)
    if type(e) ~= "table" then return end
    local author, n = e.author, e.n
    if type(author) ~= "string" or type(n) ~= "number" or n < 1 or n ~= math.floor(n) then return end
    if type(e.time) ~= "number" or type(e.kind) ~= "string" then return end
    if not ns.IsFamily(author) then return end
    author = ns.NormalizeName(author)
    if not author then return end
    e.author = author
    e.id = author .. "#" .. n
    if ns.db.entries[e.id] then return end
    ns.db.entries[e.id] = e
    if (ns.db.counters[author] or 0) < n then ns.db.counters[author] = n end
    return e
end

-------------------------------------------------------------------------------
-- Hello
-------------------------------------------------------------------------------
local function MyStatus()
    if ns.MyStatus then return ns.MyStatus() end
    local _, classFile = UnitClass("player")
    return { level = UnitLevel("player"), zone = ns.Zone(), class = classFile }
end

-- Store a brother's status table (from HI or ST) in db.peers.
local STATUS_STRINGS = { "zone", "class", "activity", "status" }
function Sync.ApplyStatus(name, st, addonVersion)
    local peer = ns.db.peers[name] or {}
    ns.db.peers[name] = peer
    peer.lastSeen = GetServerTime()
    if addonVersion then peer.version = addonVersion end
    if type(st) == "table" then
        peer.level = tonumber(st.level) or peer.level
        for _, k in ipairs(STATUS_STRINGS) do
            local v = st[k]
            peer[k] = type(v) == "string" and v:sub(1, 120) or nil
        end
        peer.grouped = st.grouped == true or nil
        -- missing from older versions and at max level: then show nothing
        local xp = tonumber(st.xpLeft)
        peer.xpLeft = xp and xp >= 0 and xp <= 100 and math.floor(xp) or nil
        local tiLeft, tiN = tonumber(st.tiLeft), tonumber(st.tiN)
        local ok = tiLeft and tiN and tiLeft >= 0 and tiLeft <= 100 and tiN >= 1 and tiN <= 100
        peer.tiLeft = ok and math.floor(tiLeft) or nil
        peer.tiN = ok and math.floor(tiN) or nil
    end
    ns.Fire("PEER_STATUS", name)
end

function Sync.Hello(name, isReply)
    SendTo(name, { t = "HI", sv = SYNC_VERSION, av = ns.version, hw = Sync.HighWater(), st = MyStatus(),
                   acct = ns.People.MyAccount(true), r = isReply or nil })
end

-- Is any character of this character's person online?
local function PersonOnline(name)
    for _, c in ipairs(ns.People.SiblingChars(name)) do
        if IsOnline(c) then return true end
    end
    return false
end
Sync.PersonOnline = PersonOnline

-- Say hello to brothers we haven't heard from recently. A brother who is online
-- on one character is not whispered on his others.
function Sync.HelloAll(force)
    for _, name in ipairs(Brothers()) do
        local skip = not force and PersonOnline(name)
        if force and not IsOnline(name) and PersonOnline(name) then skip = true end
        if not skip and not KnownOffline(name) then Sync.Hello(name) end
    end
end

-------------------------------------------------------------------------------
-- Handlers
-------------------------------------------------------------------------------
-- Common checks: returns the sender's family name, or nil to ignore.
local function From(sender)
    local name = ns.ResolveSender(sender)
    if not name or IsMe(name) then return nil end
    if not ns.People.IsKin(name) then return nil end -- brothers' characters only, never our own
    local first = not IsOnline(name)
    heard[name] = GetTime()
    if first then
        -- a /reload sends BYE then HI a few seconds later: don't announce that
        local reload = wentOffline[name] and GetTime() - wentOffline[name] < 120
        -- went quiet without logging out (e.g. was in an instance, where addons can't talk)
        local peer = ns.db.peers[name]
        local wasQuiet = not wentOffline[name] and peer and peer.lastSeen and GetServerTime() - peer.lastSeen < 3 * 3600
        wentOffline[name] = nil
        if not reload and not wasQuiet then ns.Notify(("%s is online"):format(ns.People.DisplayName(name)), "online") end
        ns.Fire("PEER_ONLINE", name)
    end
    return name
end

function Sync.MarkOffline(name)
    if not heard[name] then return end
    heard[name] = nil
    wentOffline[name] = GetTime()
    local peer = ns.db.peers[name]
    if peer then peer.lastSeen = GetServerTime() end
    ns.Fire("PEER_OFFLINE", name)
end

Sync.From = From
Sync.SendTo = SendTo
Sync.SendToOnline = SendToOnline
Sync.Brothers = Brothers

-- A brother on a character we haven't linked yet (e.g. a brand-new alt): accept
-- it if the HI carries a known brother account id and lists this character.
local function LinkNewChar(sender, acct)
    if type(acct) ~= "table" or type(acct.id) ~= "string" or type(acct.chars) ~= "table" then return end
    if acct.id == ns.People.MyId() or not ns.db.people[acct.id] then return end
    local listed = {}
    for _, c in ipairs(acct.chars) do
        local k = type(c) == "string" and ns.NameKey(c)
        if k then listed[k] = true end
    end
    for _, candidate in ipairs({ ns.NormalizeName(sender), ns.NormalizeName((sender:gsub("%-", " "))) }) do
        if candidate and listed[ns.NameKey(candidate)] and not ns.People.Of(candidate) then
            ns.People.Record(candidate, acct)
            return
        end
    end
end

-- Compare "0.10.2" style versions: -1, 0, 1, or nil if either isn't numeric (e.g. "dev").
function Sync.CompareVersions(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return nil end
    if not a:match("^%d+[%.%d]*$") or not b:match("^%d+[%.%d]*$") then return nil end
    local pa, pb = {}, {}
    for n in a:gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in b:gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

Sync.DOWNLOAD_URL = "github.com/alxric/fostbraedr/releases/latest"

-- Nudge once per newer version per session when a brother runs a newer addon.
function Sync.CheckVersion(name, theirVersion, theirSync)
    local cmp = Sync.CompareVersions(ns.version, theirVersion)
    local newer = cmp == -1 or (cmp == nil and tonumber(theirSync) and theirSync > SYNC_VERSION)
    if not newer then return end
    local key = tostring(theirVersion)
    if warnedNewer[key] then return end
    warnedNewer[key] = true
    ns.Notify(("Update available: Fostbraedr %s"):format(key), "info", {
        detail = ("%s has it, you have %s"):format(ns.People.DisplayName(name), tostring(ns.version)),
        force = true,
    })
    ns.Print("%s has Fostbraedr %s, you have %s. Download: %s", ns.People.DisplayName(name), key,
        tostring(ns.version), Sync.DOWNLOAD_URL)
end

-- Store account info before From() so the "online" notice already uses the person's name.
function Sync.LearnAccount(sender, acct)
    local pre = ns.ResolveSender(sender)
    if pre and ns.People.IsKin(pre) then ns.People.Record(pre, acct) end
end

Comm.On("HI", function(msg, sender)
    LinkNewChar(sender, msg.acct)
    Sync.LearnAccount(sender, msg.acct)
    local name = From(sender)
    if not name then return end
    Sync.ApplyStatus(name, msg.st, type(msg.av) == "string" and msg.av or nil)
    Sync.CheckVersion(name, msg.av, msg.sv)
    local sent = Sync.SendMissing(name, msg.hw)
    if sent > 0 then ns.Print("Sending %d chronicle entries to %s.", sent, ns.People.DisplayName(name)) end -- timeline ones only
    if not msg.r then Sync.Hello(name, true) end
end)

-- Summarise received entries once a burst is over, instead of per batch.
local received = {}   -- [name] = { count, last }
local function ReportReceived(name)
    local r = received[name]
    if not r then return end
    if GetTime() - r.last < 10 then
        C_Timer.After(1, function() ReportReceived(name) end)
        return
    end
    received[name] = nil
    ns.Print("Received %d chronicle entries from %s.", r.count, ns.People.DisplayName(name))
end

Comm.On("E", function(msg, sender)
    local name = From(sender)
    if not name or type(msg.l) ~= "table" then return end
    local added = 0
    for _, e in ipairs(msg.l) do
        local new = Sync.Accept(e)
        if new then
            -- announce only timeline entries that didn't get their own pop-up
            -- (fresh ones do; hidden stats/rolls never need announcing)
            local fresh = new.time and GetServerTime() - new.time < 10 * 60
            if ns.TIMELINE_KINDS[new.kind] and not fresh then added = added + 1 end
            ns.Fire("ENTRY_ADDED", new, name)
        end
    end
    if added > 0 then
        local r = received[name]
        if not r then
            r = { count = 0 }
            received[name] = r
            C_Timer.After(3, function() ReportReceived(name) end)
        end
        r.count, r.last = r.count + added, GetTime()
    end
end)

local pingSent = {}
Comm.On("PING", function(msg, sender)
    local name = From(sender)
    if not name then return end
    SendTo(name, { t = "PONG", s = msg.s })
end)

Comm.On("PONG", function(msg, sender)
    local name = From(sender)
    if not name then return end
    local sentAt = pingSent[msg.s]
    if sentAt then
        ns.Print("Pong from %s (%.1fs, via %s).", ns.People.DisplayName(name), GetTime() - sentAt, sender)
    else
        ns.Print("Pong from %s.", ns.People.DisplayName(name))
    end
end)

function Sync.Ping(target)
    local targets = target and { target } or Brothers()
    if #targets == 0 then return ns.Print("No brothers configured yet: /fost brother add First Last") end
    for _, name in ipairs(targets) do
        local s = tostring(math.random(1, 1e9))
        pingSent[s] = GetTime()
        Comm.Send({ t = "PING", s = s }, "WHISPER", name)
        ns.Print("Ping sent to %s...", name)
    end
end

-------------------------------------------------------------------------------
-- Live push of our new entries
-------------------------------------------------------------------------------
ns.Listen("ENTRY_ADDED", function(e, fromPeer)
    if fromPeer then return end
    SendToOnline({ t = "E", l = { WireCopy(e) } })
end)

-------------------------------------------------------------------------------
-- Offline whispers: hide "No player named X is currently playing" for our own
-- addon whispers, and stop sending to that character.
-------------------------------------------------------------------------------
local notFoundPattern
local function NotFoundName(msg)
    if not notFoundPattern then
        local fmt = ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
        notFoundPattern = "^" .. fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
    end
    return msg:match(notFoundPattern)
end

local function SystemFilter(_, _, msg, ...)
    if type(msg) ~= "string" or ns.IsSecret(msg) then return false end
    local who = NotFoundName(msg)
    if not who then return false end
    for target, t in pairs(lastWhisper) do
        if ns.NameKey(target) == ns.NameKey(who) and GetTime() - t < 15 then
            Sync.MarkOffline(target)
            Comm.DropTarget(target)
            return true
        end
    end
    return false
end

local function InstallFilter()
    local add = ChatFrame_AddMessageEventFilter
        or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if add then add("CHAT_MSG_SYSTEM", SystemFilter) end
end

-------------------------------------------------------------------------------
-- Timers
-------------------------------------------------------------------------------
local rosterPending = false
ns.On("GROUP_ROSTER_UPDATE", function()
    if rosterPending then return end
    rosterPending = true
    C_Timer.After(3, function()
        rosterPending = false
        -- grouped brothers we haven't heard from in the last minute: say hi via group
        for _, name in ipairs(ns.BrothersInGroup()) do
            if not heard[name] or GetTime() - heard[name] > 60 then Sync.Hello(name) end
        end
    end)
end)

-- Back out of an instance: catch up with online brothers right away.
ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    if isLogin or isReload then return end
    C_Timer.After(5, function()
        if Comm.MessagingBlocked() then return end
        for _, name in ipairs(Brothers()) do
            if IsOnline(name) then Sync.Hello(name) end
        end
    end)
end)

ns.On("PLAYER_LOGIN", function()
    InstallFilter()
    C_Timer.After(8, function() Sync.HelloAll(true) end)
    C_Timer.NewTicker(HELLO_INTERVAL, function() Sync.HelloAll(false) end)
end)

-------------------------------------------------------------------------------
-- Status for /fost peers
-------------------------------------------------------------------------------
function Sync.PrintPeers()
    local list = Brothers()
    if #list == 0 then return ns.Print("No brothers configured yet: /fost brother add First Last") end
    for _, name in ipairs(list) do
        local p = ns.db.peers[name]
        local state = IsOnline(name) and "|cff40ff40online|r" or "|cff999999not heard from|r"
        local extra = ""
        if p and p.lastSeen then
            extra = (" - last seen %s, level %s, %s, addon v%s"):format(date("%d %b %H:%M", p.lastSeen),
                tostring(p.level or "?"), p.zone or "?", p.version or "?")
        end
        ns.Print("%s: %s%s", name, state, extra)
    end
    ns.Print("Send queue: %d packets.", Comm.QueueLength())
end
