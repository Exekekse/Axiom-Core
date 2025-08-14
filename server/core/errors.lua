Axiom = Axiom or {}
Axiom.err = Axiom.err or {}

-- Fehler-Codes (Taxonomie)
Axiom.err.codes = {
  NOUID      = 'E_NOUID',
  BANNED     = 'E_BANNED',
  CONFLICT   = 'E_CONFLICT',
  EXISTS     = 'E_EXISTS',
  RATE_LIMIT = 'E_RATE_LIMIT',
  TX         = 'E_TX',
  SCHEMA     = 'E_SCHEMA',
  INVALID    = 'E_INVALID',
  FORBIDDEN  = 'E_FORBIDDEN',
  UNKNOWN    = 'E_UNKNOWN',
}

-- Ringpuffer für die letzten Fehler (max 50)
local MAX = 50
local ring = {}
local head, size = 0, 0
local counts = {}

local function newCid()
  return ('%08x'):format(math.random(0, 0xFFFFFFFF))
end
Axiom.err.newCid = newCid

local function push(scope, code, msg, data, cid)
  head = (head % MAX) + 1
  ring[head] = {
    ts = os.time(),
    scope = scope or 'core',
    code = code or 'error',
    msg = msg or '',
    data = data,
    cid  = cid,
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

function Axiom.err.ok(data)
  return { ok = true, data = data }
end

function Axiom.err.fail(code, msg, data)
  local cid = newCid()
  push('core', code, msg, data, cid)
  Axiom.metrics = Axiom.metrics or {}
  local errm = Axiom.metrics.error or {}
  errm[code or Axiom.err.codes.UNKNOWN] = (errm[code or Axiom.err.codes.UNKNOWN] or 0) + 1
  Axiom.metrics.error = errm
  return {
    ok = false,
    error = {
      code = code or Axiom.err.codes.UNKNOWN,
      message = msg or '',
      details = data,
      cid = cid,
    },
  }
end

exports('ErrOk',     function(data)                      return Axiom.err.ok(data) end)
exports('ErrFail',   function(code, msg, data)           return Axiom.err.fail(code, msg, data) end)
exports('ErrPush',   function(scope, code, msg, data, cid)    push(scope, code, msg, data, cid) end)
exports('ErrNewCid', function() return newCid() end)
exports('ErrList',   function(n)                         return list(n) end)
exports('ErrCounts', function()                          return countsCopy() end)
