Axiom = Axiom or {}
Axiom.err = Axiom.err or {}

-- Ringpuffer für die letzten Fehler (max 50)
local MAX = 50
local ring = {}
local head, size = 0, 0

local function push(scope, code, message, details)
  head = (head % MAX) + 1
  ring[head] = {
    ts = os.time(),
    scope = scope or 'core',
    code = code or 'error',
    message = message or '',
    details = details,
  }
  if size < MAX then size = size + 1 end
end

local function list(n)
  local out = {}
  local cnt = math.min(n or MAX, size)
  for i = cnt, 1, -1 do
    local idx = ((head - (cnt - i)) - 1) % MAX + 1
    out[#out+1] = ring[idx]
  end
  return out
end

function Axiom.err.ok(data)  return { ok = true,  data = data } end
function Axiom.err.fail(code, message, details)
  push('rpc', code, message, details)
  return { ok = false, code = code or 'error', message = message or '', details = details }
end

exports('ErrOk',   function(data)                        return Axiom.err.ok(data) end)
exports('ErrFail', function(code, msg, details)          return Axiom.err.fail(code, msg, details) end)
exports('ErrPush', function(scope, code, msg, details)   push(scope, code, msg, details) end)
exports('ErrList', function(n)                           return list(n) end)
