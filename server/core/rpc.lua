Axiom = Axiom or {}
local EV  = Axiom.ev
local log = Axiom.log or { error=print, debug=print }

local rate = function(key, src)
  local ok, retry = true, 0
  pcall(function() ok, retry = exports['axiom-core']:RateLimit(key, src) end)
  return ok, retry
end
local errPush = function(scope, code, msg, det)
  pcall(function() exports['axiom-core']:ErrPush(scope, code, msg, det) end)
end

-- RPC-Registry & Metrics
Axiom.RpcHandlers = Axiom.RpcHandlers or {}
local metrics = {}  -- name -> {calls, ok, fail, rate, exc, total_ms}

local function m(name) metrics[name] = metrics[name] or {calls=0,ok=0,fail=0,rate=0,exc=0,total_ms=0}; return metrics[name] end

RegisterNetEvent(EV.RpcReq, function(id, name, payload)
  local src = source
  local mt = m(name)
  local t0 = GetGameTimer()

  local allowed, retry = rate('rpc:'..tostring(name), src)
  if not allowed then
    mt.calls = mt.calls + 1; mt.rate = mt.rate + 1
    errPush('rpc', 'E_RATE_LIMIT', ('%s from %s'):format(name, src))
    TriggerClientEvent(EV.RpcRes, src, id, true, { ok=false, code='E_RATE_LIMIT', data={ retry_after=retry } })
    return
  end

  local fn = Axiom.RpcHandlers[name]
  if not fn then
    mt.calls = mt.calls + 1; mt.fail = mt.fail + 1
    errPush('rpc', 'E_NOT_FOUND', name)
    TriggerClientEvent(EV.RpcRes, src, id, true, { ok=false, code='E_NOT_FOUND' })
    return
  end

  local ok, res = pcall(fn, src, payload)
  local dt = (GetGameTimer() - t0)
  mt.calls = mt.calls + 1
  mt.total_ms = mt.total_ms + dt

  if not ok then
    mt.exc = mt.exc + 1
    errPush('rpc', 'E_EXCEPTION', name, tostring(res))
    TriggerClientEvent(EV.RpcRes, src, id, true, { ok=false, code='E_EXCEPTION' })
    return
  end

  if res and res.ok == false then
    mt.fail = mt.fail + 1
  else
    mt.ok = mt.ok + 1
  end

  TriggerClientEvent(EV.RpcRes, src, id, true, res)
end)

function Axiom.Rpc(name, fn)
  assert(type(name)=='string' and type(fn)=='function', 'Rpc(name, fn)')
  Axiom.RpcHandlers[name] = fn
end
exports('RpcRegister', function(name, fn) Axiom.Rpc(name, fn) end)

-- Metrics-Export (read-only Copy)
exports('RpcMetrics', function()
  local out = {}
  for k,v in pairs(metrics) do
    out[k] = { calls=v.calls, ok=v.ok, fail=v.fail, rate=v.rate, exc=v.exc,
               avg_ms = (v.calls>0 and (v.total_ms / v.calls)) or 0 }
  end
  return out
end)
