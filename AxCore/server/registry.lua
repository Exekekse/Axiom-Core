Axiom = Axiom or {}
local log = Axiom.log or { info=print, warn=print, error=print, debug=print, trace=print }
local cfg = (Axiom.config and Axiom.config.dependencies) or { enforce = true }

-- -------- Event-Bus --------
local bus, nextId = {}, 0
local function genId() nextId = nextId + 1; return nextId end

local function On(event, fn)
  if type(event)~='string' or type(fn)~='function' then return nil end
  bus[event] = bus[event] or {}
  local id = genId()
  bus[event][#bus[event]+1] = { id=id, fn=fn }
  return id
end

local function Off(event, idOrFn)
  local list = bus[event]; if not list then return end
  for i=#list,1,-1 do
    local it = list[i]
    if (type(idOrFn)=='number' and it.id==idOrFn)
       or (type(idOrFn)=='function' and it.fn==idOrFn) then
      table.remove(list, i)
    end
  end
end

local function Once(event, fn)
  local id
  id = On(event, function(...) Off(event, id); fn(...) end)
  return id
end

local function Emit(event, ...)
  local list = bus[event]; if not list then return 0 end
  local okCount = 0
  for _,it in ipairs(list) do
    local ok, err = pcall(it.fn, ...)
    if not ok then log.error('Event "%s" handler error: %s', event, tostring(err))
    else okCount = okCount + 1 end
  end
  return okCount
end

-- -------- Modul-Registry + Dependencies --------
local modules, pending = {}, {}

local function splitVer(v)
  local t = {}; for n in tostring(v or '0'):gmatch('%d+') do t[#t+1] = tonumber(n) or 0 end; return t
end
local function cmpVer(a, b)
  local A, B = splitVer(a), splitVer(b)
  local n = math.max(#A, #B)
  for i=1,n do
    local x, y = A[i] or 0, B[i] or 0
    if x < y then return -1 elseif x > y then return 1 end
  end
  return 0
end
local function parseReq(s)
  s = tostring(s or '')
  local name, min = s:match('^%s*([^%s>=<]+)%s*>=%s*([%d%.]+)%s*$')
  if name then return { name=name, min=min } end
  name = s:match('^%s*([^%s>=<]+)%s*$')
  return { name = name, min = nil }
end
local function depSatisfied(req)
  if not req or not req.name then return true end
  if req.name == 'axiom-core' then
    if not req.min then return true end
    return cmpVer(Axiom.version or '0.0.0', req.min) >= 0
  end
  local m = modules[req.name]
  if not m then return false end
  if not req.min then return true end
  return cmpVer(m.version or '0.0.0', req.min) >= 0
end
local function depsOk(def)
  local missing = {}
  if type(def.requires) == 'table' then
    for _,s in ipairs(def.requires) do
      local r = parseReq(s)
      if not depSatisfied(r) then
        local want = r.min and (r.name .. '>=' .. r.min) or r.name
        missing[#missing+1] = want
      end
    end
  end
  return (#missing == 0), missing
end

local function startModule(def)
  modules[def.name] = def
  if def.onStart then
    local ok, err = pcall(def.onStart)
    if not ok then log.error('Module %s onStart error: %s', def.name, tostring(err)) end
  end
  Emit(Axiom.ev.ModuleReady, def.name, def.version or '0.0.0')
  log.info('Module %s gestartet (%s)', def.name, def.version or '0.0.0')
end

local function tryStart(def)
  local ok, miss = depsOk(def)
  if ok then
    startModule(def)
  else
    local msg = table.concat(miss, ', ')
    if cfg.enforce then
      pending[def.name] = def
      log.warn('Module %s wartet auf Abhängigkeiten: %s', def.name, msg)
    else
      log.warn('Module %s fehlende Abhängigkeiten (ignoriere): %s', def.name, msg)
      startModule(def)
    end
  end
end

local function RegisterModule(def)
  assert(type(def)=='table' and def.name, 'RegisterModule: def.name fehlt')
  if modules[def.name] then log.warn('Module %s wird überschrieben', def.name) end
  tryStart(def)
end

-- Wenn ein Modul ready wird, versuche Pending-Module zu starten
On(Axiom.ev.ModuleReady, function(name)
  for mod,def in pairs(pending) do
    local ok = depsOk(def)
    if ok then
      pending[mod] = nil
      startModule(def)
    end
  end
end)

local function GetModule(name) return modules[name] end
local function ListModules()
  local out = {}
  for name,def in pairs(modules) do out[#out+1] = { name=name, version=def.version or '0.0.0' } end
  table.sort(out, function(a,b) return a.name < b.name end)
  return out
end

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  for name,def in pairs(modules) do
    if def.onStop then pcall(def.onStop) end
    Emit(Axiom.ev.ModuleStop, name)
    log.info('Module %s gestoppt', name)
  end
end)

exports('RegisterModule', RegisterModule)
exports('GetModule',      GetModule)
exports('ListModules',    ListModules)
exports('On',             On)
exports('Once',           Once)
exports('Off',            Off)
exports('Emit',           Emit)
