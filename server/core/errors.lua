Axiom = Axiom or {}
Axiom.err = Axiom.err or {}

-- Ringpuffer für die letzten Fehler (max 50)
local MAX = 50
local ring = {}
local head, size = 0, 0
local counts = {}

local function push(scope, code, msg, data)
  head = (head % MAX) + 1
  ring[head] = {
    ts = os.time(),
    scope = scope or 'core',
    code = code or 'error',
    msg = msg or '',
    data = data,
  }
  counts[code or 'error'] = (counts[code or 'error'] or 0) + 1
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

local function countsCopy()
  local out = {}
  for k,v in pairs(counts) do out[k]=v end
  return out
end

function Axiom.err.ok(data)  return { ok = true, code = nil, data = data } end
function Axiom.err.fail(code, msg, data)
  push('core', code, msg, data)
  return { ok = false, code = code or 'E_UNKNOWN', msg = msg or '', data = data }
end

exports('ErrOk',     function(data)                      return Axiom.err.ok(data) end)
exports('ErrFail',   function(code, msg, data)           return Axiom.err.fail(code, msg, data) end)
exports('ErrPush',   function(scope, code, msg, data)    push(scope, code, msg, data) end)
exports('ErrList',   function(n)                         return list(n) end)
exports('ErrCounts', function()                          return countsCopy() end)
