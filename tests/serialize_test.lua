-- Serializer round-trips and rejects malformed input. Run: lua-5.1 tests/serialize_test.lua
local ns = {}
assert(loadfile("./Serialize.lua"))("Fostbraedr", ns)
local S = ns.Serialize
local function eq(a,b) if type(a)~=type(b) then return false end if type(a)~="table" then return a==b end
  for k,v in pairs(a) do if not eq(v,b[k]) then return false end end for k in pairs(b) do if a[k]==nil then return false end end return true end
local cases = {
  {id="Ragnar Stormfjord#5", author="Ragnar Stormfjord", n=5, time=1795000000, kind="death", level=14, zone="Westfall", with={"Thorgrim Stormfjord","Ålfrida Stormfjord"}},
  {link="|cnIQ4:|Hitem:1234::::|h[Sword ^ of ~1 Doom]|h|r", x=0.1, neg=-3, b=true, f=false, e=""},
  "plain ^~ string~2", 42, 3.14159, {}, {{{}}},
}
for i,c in ipairs(cases) do local enc=S.Encode(c); local dec,err=S.Decode(enc); assert(eq(c,dec), "case "..i.." failed: "..tostring(err)) end
for _,bad in ipairs{"", "T", "TSa", "X1", "N1^N2", "TN1t", "Nfoo", string.rep("T^",50)} do assert(S.Decode(bad) == nil, "accepted bad input "..bad) end
print("ALL OK")
