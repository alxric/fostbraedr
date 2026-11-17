-- Fostbraedr: compact, printable serializer for addon messages.
-- Never runs code from the wire: the decoder is a plain token parser.
--
-- Format: tokens joined by "^". Each token is a type char + value:
--   N<number>  S<string>  B1/B0 boolean  T table start  t table end
-- Tables are written as key, value, key, value, ... between T and t.
-- In strings, "~" is escaped as "~2" and "^" as "~1".
local ADDON, ns = ...

local Serialize = {}
ns.Serialize = Serialize

local function EscapeString(s)
    return (s:gsub("~", "~2"):gsub("%^", "~1"))
end

local function UnescapeString(s)
    return (s:gsub("~([12])", function(c) return c == "1" and "^" or "~" end))
end

local function Encode(v, out, depth)
    local tv = type(v)
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then error("can't serialize nan/inf") end
        -- integers as plain digits; other numbers with %.17g, which round-trips doubles
        local isInt = v == math.floor(v) and math.abs(v) < 2^53
        out[#out + 1] = "N" .. (isInt and string.format("%d", v) or string.format("%.17g", v))
    elseif tv == "string" then
        out[#out + 1] = "S" .. EscapeString(v)
    elseif tv == "boolean" then
        out[#out + 1] = v and "B1" or "B0"
    elseif tv == "table" then
        if depth > 10 then error("table nested too deep") end
        out[#out + 1] = "T"
        for k, val in pairs(v) do
            local tk = type(k)
            if (tk == "string" or tk == "number") and type(val) ~= "function" and type(val) ~= "userdata" then
                Encode(k, out, depth + 1)
                Encode(val, out, depth + 1)
            end
        end
        out[#out + 1] = "t"
    else
        error("can't serialize a " .. tv)
    end
end

function Serialize.Encode(v)
    local out = {}
    Encode(v, out, 0)
    return table.concat(out, "^")
end

-- Returns the value, or nil plus an error message for malformed input.
function Serialize.Decode(str)
    if type(str) ~= "string" or str == "" then return nil, "empty" end
    local tokens = {}
    for tok in (str .. "^"):gmatch("([^%^]*)%^") do tokens[#tokens + 1] = tok end
    local pos = 1

    local function Read(depth)
        local tok = tokens[pos]
        if not tok then error("truncated", 0) end
        pos = pos + 1
        local tag, rest = tok:sub(1, 1), tok:sub(2)
        if tag == "N" then
            local n = tonumber(rest)
            if not n then error("bad number", 0) end
            return n
        elseif tag == "S" then
            return UnescapeString(rest)
        elseif tag == "B" then
            return rest == "1"
        elseif tag == "T" then
            if depth > 10 then error("too deep", 0) end
            local t = {}
            while tokens[pos] ~= "t" do
                if not tokens[pos] then error("unterminated table", 0) end
                local k = Read(depth + 1)
                local v = Read(depth + 1)
                if type(k) ~= "string" and type(k) ~= "number" then error("bad key", 0) end
                t[k] = v
            end
            pos = pos + 1
            return t
        else
            error("bad token " .. tag, 0)
        end
    end

    local ok, result = pcall(Read, 0)
    if not ok then return nil, result end
    if pos <= #tokens then return nil, "trailing data" end
    return result
end
