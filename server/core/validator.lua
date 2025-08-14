Axiom = Axiom or {}
Axiom.v = {}
local err = (Axiom.err and Axiom.err.fail) or function(code,msg,data)
  return { ok=false, error={ code=code, message=msg, details=data } }
end

function Axiom.v.type(val, want) return (type(val) == want), ('expected '..want..', got '..type(val)) end
function Axiom.v.len(s, min, max) if type(s)~='string' then return false,'expected string' end local n=#s; if min and n<min then return false,'min '..min end if max and n>max then return false,'max '..max end return true end
function Axiom.v.range(n, min, max) if type(n)~='number' then return false,'expected number' end if min and n<min then return false,'min '..min end if max and n>max then return false,'max '..max end return true end
function Axiom.v.enum(val, list) for _,v in ipairs(list or {}) do if v==val then return true end end return false,'invalid enum' end

function Axiom.v.check(payload, spec)
  for _,rule in ipairs(spec or {}) do
    local ok, e = rule.check(payload[rule.key])
    if not ok then return false, err('E_INVALID', e or 'invalid', { key = rule.key }) end
  end
  return true
end
