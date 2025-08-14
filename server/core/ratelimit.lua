Axiom = Axiom or {}

local rlc = (Axiom.config and Axiom.config.rate_limit) or {}
local DEFAULT_CAP  = tonumber(rlc.capacity)   or 5
local DEFAULT_MS   = tonumber(rlc.refill_ms)  or 10000
local OVERRIDES    = rlc.overrides or {}

local buckets = {}
local function now() return GetGameTimer() end
local function paramsFor(key)
  local o = OVERRIDES[key]; if o then return tonumber(o.capacity) or DEFAULT_CAP, tonumber(o.refill_ms) or DEFAULT_MS end
  return DEFAULT_CAP, DEFAULT_MS
end
local function allow(key)
  local cap, refill = paramsFor(key); local b = buckets[key]; local t = now()
  if not b then b = { tokens = cap, last = t, cap = cap, refill = refill }; buckets[key] = b
  else if b.cap ~= cap or b.refill ~= refill then b.tokens = math.min(cap, b.tokens); b.cap, b.refill = cap, refill end end
  local dt = t - b.last; if dt > 0 then local add = (dt / b.refill) * b.cap; if add > 0 then b.tokens = math.min(b.cap, b.tokens + add); b.last = t end end
  if b.tokens >= 1 then b.tokens = b.tokens - 1; return true end
  return false
end
function Axiom.RateLimit(key, src) key = tostring(key)..':'..tostring(src or 0); return allow(key) end
exports('RateLimit', function(key, src) return Axiom.RateLimit(key, src) end)

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  buckets = {}
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  buckets = {}
end)
