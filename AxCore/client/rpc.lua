-- Client-Stub für RPC (Client -> Server)
Axiom = Axiom or {}
local EV = (Axiom.ev or {})

local pending = {}  -- id -> {cb, timeout}
local function newId() return tostring(math.random(10^9, 10^10-1)) end

RegisterNetEvent(EV.RpcRes, function(id, ok, res)
  local p = pending[id]; if not p then return end
  pending[id] = nil
  if p.cb then p.cb(ok, res) end
end)

-- Axiom.rpc('name', payload, function(ok,res) end, timeout_ms)
function Axiom.rpc(name, payload, cb, timeout)
  local id = newId()
  pending[id] = { cb = cb, timeout = GetGameTimer() + (timeout or 5000) }
  TriggerServerEvent(EV.RpcReq, id, name, payload)
end

-- Timeout-Sweeper
CreateThread(function()
  while true do
    Wait(500)
    local now = GetGameTimer()
    for id,p in pairs(pending) do
      if now > (p.timeout or 0) then
        local cb = p.cb; pending[id] = nil
        if cb then cb(false, 'timeout') end
      end
    end
  end
end)
