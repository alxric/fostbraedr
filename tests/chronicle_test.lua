-- Chronicle rows: one row per boss kill for everyone involved, no "with" on loot,
-- and no pop-up for a brother's boss kill we took part in. Run: lua-5.1 tests/chronicle_test.lua
package.path = "./tests/?.lua;" .. package.path
local sim = require("sim")
local A = sim.NewClient("Ragnar", "Stormfjord", function(f, l) return f .. " " .. l end)
local env, ns = A.env, A.ns
for _, f in ipairs({ "Theme.lua", "Toast.lua", "ChronicleUI.lua" }) do
    local ch = assert(loadfile("./" .. f)); setfenv(ch, env); ch("Fostbraedr", ns)
end
local toasts = {}
ns.Notify = function(text) toasts[#toasts + 1] = text end
env.SlashCmdList.FOSTBRAEDR("brother add Nomarak Stormfjord")
env.SlashCmdList.FOSTBRAEDR("brother add Tor Stormfjord")

local now = env.GetServerTime()
local mine = ns.AddEntry("boss", { name = "Tuten'kash", zone = "Razorfen Downs", with = { "Nomarak Stormfjord" } })
ns.AddEntry("loot", { link = "[Silky Spider Cape]", quality = 3, with = { "Nomarak Stormfjord" } })
local function Remote(author, n, fields)
    fields.author, fields.n, fields.time = author, n, fields.time or env.GetServerTime()
    local e = assert(ns.Sync.Accept(fields))
    ns.Fire("ENTRY_ADDED", e, author)
end
-- Nomarak's copy recorded the same kill (with us); Tor killed it too a bit later, same run
Remote("Nomarak Stormfjord", 1, { kind = "boss", name = "Tuten'kash", zone = "Razorfen Downs", with = { "Ragnar Stormfjord" } })
Remote("Tor Stormfjord", 1, { kind = "boss", name = "Tuten'kash", zone = "Razorfen Downs", time = now + 120 })
-- a kill of the same boss the next day is a separate row
Remote("Nomarak Stormfjord", 2, { kind = "boss", name = "Tuten'kash", zone = "Razorfen Downs", time = now + 86400 })
-- Nomarak kills something alone: toast
Remote("Nomarak Stormfjord", 3, { kind = "boss", name = "Hogger", zone = "Elwynn Forest", time = now + 90000 })

local rows = ns.BuildChronicleRows()
local texts = {}
for _, r in ipairs(rows) do texts[#texts + 1] = r.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") print(texts[#texts]) end
local function Count(pat) local n = 0 for _, t in ipairs(texts) do if t:find(pat) then n = n + 1 end end return n end
assert(Count("Tuten'kash") == 2, "same-run kills merged into one row; next day separate")
local merged
for _, t in ipairs(texts) do if t:find(" and Tor defeated Tuten'kash") then merged = t end end
assert(merged and merged:find("Ragnar") and merged:find("Nomarak"), "merged row names everyone")
assert(Count("Nomarak defeated Tuten'kash") == 1, "next day's kill on its own")
assert(Count("looted %[Silky Spider Cape%]$") == 1, "no 'together with' on loot")
-- toasts: none for the run we were in (Nomarak listed us; Tor's matches our own kill),
-- one for Nomarak's kill the next day, one for his Hogger kill
for _, t in ipairs(toasts) do print("toast:", t) end
assert(#toasts == 2, "expected 2 toasts, got " .. #toasts)
for _, t in ipairs(toasts) do assert(not t:find("Tor"), "no toast for Tor's kill in our run") end
print("ALL OK")
