-- Simulated WoW clients connected by a fake network. Run from the repo root: lua-5.1 tests/sync_test.lua
local ROOT = "./"
local FILES = {"Core.lua","People.lua","Serialize.lua","Comm.lua","Chronicle.lua","Sync.lua","Family.lua","Rivalry.lua"}
local clock = 0
local clients = {}
local network = {}   -- pending deliveries
local OFFLINE = {}   -- names that are offline

-- initialDB: saved variables to start with (to simulate an alt on the same account)
local function NewClient(first, last, senderFormat, initialDB)
  local c = { name = first.." "..last, timers = {}, tickers = {}, chat = {} }
  local env = setmetatable({}, { __index = _G })
  c.env = env
  env._G = env
  local evf
  env.CreateFrame = function() return { RegisterEvent=function() end, SetScript=function(self,k,f) if k=="OnEvent" then evf=f end end } end
  env.SlashCmdList = {}
  env.wipe = function(t) for k in pairs(t) do t[k]=nil end return t end
  env.GetServerTime = function() return 1795000000 + math.floor(clock) end
  env.GetTime = function() return clock end
  env.date = function(f, t) return os.date(f, t) end
  env.UnitName = function(u) if u=="player" then return first, last end if u=="party1" then return c.partyFirst, c.partyLast end end
  env.UnitLevel = function() return 20 end
  env.UnitClass = function() return "Warrior","WARRIOR" end
  env.GetRealZoneText = function() return "Elwynn Forest" end
  env.IsInGroup = function() return c.grouped or false end
  env.IsInRaid = function() return false end
  env.GetNumSubgroupMembers = function() return c.grouped and 1 or 0 end
  env.UnitIsUnit = function(a,b) return a==b end
  env.GetMoney = function() return 0 end
  env.InCombatLockdown = function() return c.combat or false end
  env.IsInInstance = function() return c.instance ~= nil, c.instance and "party" or "none" end
  env.GetInstanceInfo = function() return c.instance end
  env.UnitIsDeadOrGhost = function() return false end
  env.UnitIsAFK = function() return c.afk or false end
  env.UnitOnTaxi = function() return false end
  env.IsResting = function() return false end
  env.GetSubZoneText = function() return c.subzone or "" end
  env.UNKNOWNOBJECT = "Unknown"
  env.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
  env.Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3 } }
  env.C_Timer = { NewTicker = function(s, f) table.insert(c.tickers, {every=s, f=f, next=clock+s}) end,
                  After = function(s, f) table.insert(c.timers, {at=clock+s, f=f}) end }
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(prefix, text, channel, target)
      assert(#text <= 255, "packet too long "..#text)
      if c.loggedOut then return 0 end
      c.sent = (c.sent or 0) + 1
      local targetOnline = false
      for _, other in ipairs(clients) do
        if other.name == target and not other.loggedOut then targetOnline = true end
      end
      if channel == "WHISPER" and (OFFLINE[target] or not targetOnline) then
        table.insert(network, {sys=true, to=c, msg=("No player named '%s' is currently playing."):format(target)})
        return 0
      end
      for _, other in ipairs(clients) do
        if other ~= c then
          local ok = not other.loggedOut and ((channel=="WHISPER" and other.name==target) or (channel=="PARTY" and c.grouped and other.grouped))
          if ok then table.insert(network, {to=other, prefix=prefix, text=text, channel=channel, sender=senderFormat(first,last)}) end
        end
      end
      if channel=="PARTY" then table.insert(network, {to=c, prefix=prefix, text=text, channel=channel, sender=senderFormat(first,last)}) end
      return 0
    end }
  env.ChatFrame_AddMessageEventFilter = function(ev, f) c.sysFilter = f end
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(c.chat, m) print("["..first.."] "..m:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")) end }
  env.geterrorhandler = function() return function(e) print("ERROR", e) error(e) end end
  local ns = {}
  for _, f in ipairs(FILES) do local ch = assert(loadfile(ROOT..f)); setfenv(ch, env); ch("Fostbraedr", ns) end
  c.ns = ns
  c.toasts = {}
  if not ns.Notify then
    ns.Notify = function(text, kind, opts)
      table.insert(c.toasts, text)
      print("[" .. first .. "] TOAST " .. text .. ((opts and opts.detail) and (" / " .. opts.detail) or ""))
    end
  end
  c.fire = function(ev, ...) evf(nil, ev, ...) end
  env.FostbraedrDB = initialDB
  c.fire("ADDON_LOADED", "Fostbraedr")
  c.fire("PLAYER_LOGIN")
  table.insert(clients, c)
  return c
end

local function Step(dt)
  clock = clock + dt
  for _, c in ipairs(clients) do
    for _, t in ipairs(c.tickers) do if clock >= t.next then t.next = clock + t.every; t.f() end end
    local due = {}
    for i = #c.timers, 1, -1 do if clock >= c.timers[i].at then table.insert(due, table.remove(c.timers, i)) end end
    for _, t in ipairs(due) do t.f() end
  end
  local deliver = network; network = {}
  for _, m in ipairs(deliver) do
    if m.sys then
      local hidden = m.to.sysFilter and m.to.sysFilter(nil, "CHAT_MSG_SYSTEM", m.msg)
      print("  (system msg to "..m.to.name..": "..m.msg..(hidden and " -> HIDDEN" or " -> shown")..")")
    else
      m.to.fire("CHAT_MSG_ADDON", m.prefix, m.text, m.channel, m.sender)
    end
  end
end
local function Run(sec) for _ = 1, sec*5 do Step(0.2) end end

-- Deep copy, for handing one client's saved variables to another (same account).
local function Copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = Copy(v) end
  return c
end

return { NewClient = NewClient, Run = Run, clients = clients, OFFLINE = OFFLINE, Copy = Copy }
