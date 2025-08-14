Axiom = Axiom or {}
local cfg = (Axiom.config and Axiom.config.cache) or {}
local ttl = tonumber(cfg.ttl_sec) or 60

local store = {}
local metrics = { hits = 0, misses = 0, evictions = 0 }

local function now()
  return os.time()
end

local function size()
  local c = 0
  for _ in pairs(store) do c = c + 1 end
  return c
end

local function get(key)
  local e = store[key]
  if e then
    if e.exp > now() then
      metrics.hits = metrics.hits + 1
      return e.val
    else
      store[key] = nil
      metrics.evictions = metrics.evictions + 1
    end
  end
  metrics.misses = metrics.misses + 1
  return nil
end

local function set(key, val, t)
  store[key] = { val = val, exp = now() + (t or ttl) }
end

local function del(key)
  if store[key] then
    store[key] = nil
    metrics.evictions = metrics.evictions + 1
  end
end

local function bust()
  store = {}
end

local function metricsCopy()
  return { hits = metrics.hits, misses = metrics.misses, size = size(), evictions = metrics.evictions }
end

Axiom.cache = {
  get = get,
  set = set,
  del = del,
  metrics = metricsCopy,
  bust = bust,
}

exports('CacheGet', function(key) return get(key) end)
exports('CacheSet', function(key, val, t) set(key, val, t) end)
exports('CacheDel', function(key) del(key) end)
exports('CacheMetrics', function() return metricsCopy() end)
exports('CacheBust', function() bust() end)

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  bust()
end)
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  bust()
end)
