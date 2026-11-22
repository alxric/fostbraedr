-- Fostbraedr: addon-message transport.
--
-- ns.Comm.Send(msgTable, channel, target) serializes a table, splits it into
-- packets that fit the 255-byte limit and queues them. The queue is drained by
-- our own throttle (burst of 5, then about 1 packet per second) and pauses while
-- in combat or when the client blocks addon messages.
--
-- Packet (this header format must never change):
--   "<proto>:<msgId>:<index>:<count>:<payload>"
-- proto is the wire-format version (1). Packets with another proto are ignored.
local ADDON, ns = ...

local Comm = {}
ns.Comm = Comm

local PREFIX = "Fostbraedr"     -- max 16 chars
local PROTO = 1
local MAX_PACKET = 250          -- a little below 255 for safety
local BURST, REFILL = 5, 1.0    -- tokens, seconds per token
local REASSEMBLY_TIMEOUT = 120

Comm.PREFIX, Comm.PROTO = PREFIX, PROTO

local queue = {}                -- { {channel, target, text}, ... }
local tokens = BURST
local lastRefill = 0
local nextMsgId = 0
local partial = {}              -- [sender..":"..msgId] = { count, got, parts = {}, started }
local handlers = {}             -- [msg.t] = function(msg, sender, channel)

Comm.debug = false
local function Debug(...)
    if Comm.debug then ns.Print("|cff999999[comm]|r " .. string.format(...)) end
end

local function NewMsgId()
    nextMsgId = (nextMsgId + 1) % 1679616 -- 36^4
    -- base36, 1-4 chars
    local n, s = nextMsgId, ""
    repeat
        local d = n % 36
        s = ("0123456789abcdefghijklmnopqrstuvwxyz"):sub(d + 1, d + 1) .. s
        n = math.floor(n / 36)
    until n == 0
    return s
end

-- Split a serialized message into packets.
function Comm.Packetize(text)
    local id = NewMsgId()
    local headerMax = #(("%d:%s:%d:%d:"):format(PROTO, id, 999, 999))
    local size = MAX_PACKET - headerMax
    local count = math.max(1, math.ceil(#text / size))
    if count > 999 then return nil end
    local packets = {}
    for i = 1, count do
        packets[i] = ("%d:%s:%d:%d:%s"):format(PROTO, id, i, count, text:sub((i - 1) * size + 1, i * size))
    end
    return packets
end

function Comm.Send(msg, channel, target)
    local ok, text = pcall(ns.Serialize.Encode, msg)
    if not ok then return Debug("encode failed: %s", tostring(text)) end
    local packets = Comm.Packetize(text)
    if not packets then return Debug("message too large (%d bytes)", #text) end
    -- Only the newest status matters: drop older queued ones for the same destination
    -- (they pile up while we're in an instance).
    if msg.t == "ST" then
        for i = #queue, 1, -1 do
            local q = queue[i]
            if q.kind == "ST" and q.channel == channel and q.target == target then table.remove(queue, i) end
        end
    end
    for _, p in ipairs(packets) do
        queue[#queue + 1] = { channel = channel, target = target, text = p, kind = msg.t }
    end
    Debug("queued %s to %s %s (%d packets, %d bytes)", tostring(msg.t), channel, tostring(target), #packets, #text)
end

-- Drop queued packets for a target (e.g. it turned out to be offline).
function Comm.DropTarget(target)
    for i = #queue, 1, -1 do
        if queue[i].target == target then table.remove(queue, i) end
    end
end

function Comm.QueueLength() return #queue end

function Comm.On(t, fn) handlers[t] = fn end

-- Inside instances (dungeons, raids, battlegrounds, arenas) Midnight-era clients
-- don't let addons message other players at all; we also hold off in combat.
-- Queued packets wait and go out once this returns false.
local function MessagingBlocked()
    if InCombatLockdown() then return true end
    local inInstance = IsInInstance()
    if inInstance and not ns.IsSecret(inInstance) then return true end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return true end
    return false
end
Comm.MessagingBlocked = MessagingBlocked
function Comm.QueueLength() return #queue end

local function IsSuccess(result)
    if result == true or result == nil then return true end -- older API: no return value / boolean
    if result == false then return false end
    local R = Enum.SendAddonMessageResult
    return R and result == R.Success or result == 0
end

-- Results worth retrying later (throttles, lockdowns), matched by enum name so
-- we also handle values that newer clients add.
local function IsRetryable(result)
    local R = Enum.SendAddonMessageResult
    if not R then return false end
    for name, value in pairs(R) do
        if value == result then
            return name:find("Throttle") or name:find("Lockdown") or name:find("Restrict") or false
        end
    end
    return false
end

-- Send a small message right away, bypassing the queue (used at logout, when
-- the queue won't get another chance to run). Returns true if it went out.
function Comm.SendNow(msg, channel, target)
    local ok, text = pcall(ns.Serialize.Encode, msg)
    if not ok then return false end
    local packets = Comm.Packetize(text)
    if not packets or #packets ~= 1 then return false end
    if MessagingBlocked() then return false end
    local sent, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, packets[1], channel, target)
    return sent and IsSuccess(result)
end

-- Counters for /fost synctest: what went out, what came in, what was dropped.
Comm.stats = { sent = 0, retried = 0, failed = 0, received = 0, secret = 0, malformed = 0, blockedPumps = 0 }
local stats = Comm.stats

local function Pump()
    local now = GetTime()
    if now - lastRefill >= REFILL then
        tokens = math.min(BURST, tokens + math.floor((now - lastRefill) / REFILL))
        lastRefill = now
    end
    while #queue > 0 and tokens >= 1 do
        if MessagingBlocked() then
            stats.blockedPumps = stats.blockedPumps + 1
            stats.lastBlocked = GetTime()
            return
        end
        local p = queue[1]
        if ns.OnBeforeSend then ns.OnBeforeSend(p.channel, p.target) end
        local called, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, p.text, p.channel, p.target)
        if called and IsSuccess(result) then
            table.remove(queue, 1)
            tokens = tokens - 1
            stats.sent = stats.sent + 1
        elseif not called or IsRetryable(result) then
            -- blocked or throttled: keep the packet and try again later
            tokens = 0
            stats.retried = stats.retried + 1
            stats.lastRetry = { result = tostring(result), target = tostring(p.target), time = GetTime() }
            Debug("send blocked (%s), will retry", tostring(result))
            return
        else
            table.remove(queue, 1)
            stats.failed = stats.failed + 1
            stats.lastFail = { result = tostring(result), target = tostring(p.target), time = GetTime() }
            Debug("send to %s %s failed: %s", p.channel, tostring(p.target), tostring(result))
        end
    end
end

-- Incoming
local function OnPacket(text, channel, sender)
    local proto, id, idx, count, payload = text:match("^(%d+):(%w+):(%d+):(%d+):(.*)$")
    if not proto then
        stats.malformed = stats.malformed + 1
        return Debug("malformed packet from %s", sender)
    end
    if tonumber(proto) ~= PROTO then return Debug("ignoring proto %s from %s", proto, sender) end
    idx, count = tonumber(idx), tonumber(count)
    if idx < 1 or idx > count or count > 999 then return end

    local full
    if count == 1 then
        full = payload
    else
        local key = sender .. ":" .. id
        local p = partial[key]
        if not p then
            p = { count = count, got = 0, parts = {}, started = GetTime() }
            partial[key] = p
        end
        if p.count ~= count then partial[key] = nil return end
        if not p.parts[idx] then
            p.parts[idx] = payload
            p.got = p.got + 1
        end
        if p.got < p.count then return end
        partial[key] = nil
        full = table.concat(p.parts)
    end

    local msg, err = ns.Serialize.Decode(full)
    if type(msg) ~= "table" or type(msg.t) ~= "string" then
        return Debug("undecodable message from %s: %s", sender, tostring(err))
    end
    local h = handlers[msg.t]
    if h then h(msg, sender, channel) else Debug("unknown message type %s from %s", msg.t, sender) end
end
Comm.OnPacket = OnPacket -- for tests

local function CleanupPartials()
    local now = GetTime()
    for k, p in pairs(partial) do
        if now - p.started > REASSEMBLY_TIMEOUT then partial[k] = nil end
    end
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if ns.IsSecret(prefix) or prefix ~= PREFIX then return end
    if ns.IsSecret(text) or ns.IsSecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then
        stats.secret = stats.secret + 1 -- ours, but the game hid the text or the sender's name
        return
    end
    stats.received = stats.received + 1
    if Comm.debug then Debug("packet via %s from '%s' (%d bytes)", channel, sender, #text) end
    OnPacket(text, channel, sender)
end)

ns.On("ADDON_LOADED", function(loaded)
    if loaded ~= ADDON then return end
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end)

ns.On("PLAYER_LOGIN", function()
    lastRefill = GetTime()
    C_Timer.NewTicker(0.2, Pump)
    C_Timer.NewTicker(30, CleanupPartials)
end)
