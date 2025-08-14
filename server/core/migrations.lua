Axiom = Axiom or {}
local log = Axiom.log or { info=print, warn=print, error=print }
local RES = GetCurrentResourceName()
local ax  = exports[RES]
local DbScalar = function(q,p) return ax:DbScalar(q,p) end
local DbExec   = function(q,p) return ax:DbExec(q,p)   end

local regs = {} -- modul -> { {version, steps}, ... }

local function ensureStateTable()
  DbExec([[
    CREATE TABLE IF NOT EXISTS axiom_migrations (
      module     VARCHAR(64)  NOT NULL,
      version    VARCHAR(64)  NOT NULL,
      applied_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (module, version)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  ]])
end

local function applied(mod, ver)
  return DbScalar('SELECT 1 FROM axiom_migrations WHERE module=? AND version=? LIMIT 1', {mod, ver}) ~= nil
end

local function mark(mod, ver)
  DbExec('INSERT IGNORE INTO axiom_migrations (module, version) VALUES (?,?)', {mod, ver})
end

local function RegisterMigration(module, version, steps)
  regs[module] = regs[module] or {}
  regs[module][#regs[module]+1] = { version = version, steps = steps }
  table.sort(regs[module], function(a,b) return tostring(a.version) < tostring(b.version) end)
end

local function preview(sql)
  if type(sql) ~= 'string' then return '<none>' end
  sql = sql:gsub('%s+', ' ')
  if #sql > 120 then sql = sql:sub(1, 120) .. '…' end
  return sql
end

local function makeCtx()
  local function helper(fn)
    return function(sql, params)
      assert(type(sql) == 'string', ('E_DB_BADSQL: expected string, got %s'):format(type(sql)))
      if params ~= nil and type(params) ~= 'table' then
        error(('E_DB_BADPARAMS: expected table, got %s'):format(type(params)))
      end
      local ok, res = pcall(fn, sql, params)
      if not ok then error({ stage = 'sql', sql = sql, params_kind = type(params), err = tostring(res) }) end
      return res
    end
  end
  local ctx = {}
  ctx.scalar = helper(DbScalar)
  ctx.exec   = helper(DbExec)
  ctx.tx     = function(fn)
    assert(type(fn) == 'function', ('E_DB_BADTXFN: expected function, got %s'):format(type(fn)))
    return ax:DbTx(function(tx)
      local txCtx = {
        scalar = helper(tx.scalar),
        exec   = helper(tx.exec),
      }
      return fn(txCtx)
    end)
  end
  return ctx
end
local function runFor(mig)
  local t = type(mig)
  if t == 'function' then
    local ctx = makeCtx()
    local ok, err = pcall(mig, ctx)
    if not ok then error({ stage = 'fn', sql = nil, params_kind = 'nil', err = tostring(err) }) end
    return
  elseif t == 'string' then
    local ok, res = pcall(DbExec, mig, nil)
    if not ok then error({ stage = 'sql', sql = mig, params_kind = 'nil', err = tostring(res) }) end
    return
  elseif t == 'table' then
    if type(mig.fn) == 'function' then
      runFor(mig.fn)
      return
    end
    if mig.sql ~= nil or mig.params ~= nil then
      assert(type(mig.sql) == 'string', ('E_DB_BADSQL: expected string, got %s'):format(type(mig.sql)))
      local params = mig.params
      if params ~= nil and type(params) ~= 'table' then
        error(('E_DB_BADPARAMS: expected table, got %s'):format(type(params)))
      end
      local ok, res = pcall(DbExec, mig.sql, params)
      if not ok then error({ stage = 'sql', sql = mig.sql, params_kind = type(params), err = tostring(res) }) end
      return
    end
    if next(mig) == nil then
      error('E_DB_BADSQL: empty step')
    end
    local ctx
    for i, step in ipairs(mig) do
      local ok, err = pcall(function()
        if type(step) == 'function' then
          ctx = ctx or makeCtx()
          local ok2, res2 = pcall(step, ctx)
          if not ok2 then error({ stage = 'fn', sql = nil, params_kind = 'nil', err = tostring(res2) }) end
        else
          runFor(step)
        end
      end)
      if not ok then
        local det = err
        if type(det) ~= 'table' then det = { sql = nil, params_kind = 'nil', err = tostring(det) } end
        det.stage = 'step:' .. i
        error(det)
      end
    end
    return
  end
  error(('E_MIG_BADSTEP: expected string/table/function, got %s'):format(t))
end

local function runModule(mod)
  local list = regs[mod]; if not list or #list==0 then return end
  for _,m in ipairs(list) do
    if not applied(mod, m.version) then
      log.info('Migration %s:%s wird angewendet …', mod, m.version)
      if Axiom.audit then Axiom.audit('migration.start', mod..':'..m.version, 'system') end
      local ok, err = pcall(function() runFor(m.steps) end)
      if not ok then
        local det = err
        local msg, stage, sqlPrev, paramsKind
        if type(det) == 'table' then
          msg        = det.err or det.message or det.code or tostring(det)
          stage      = det.stage or 'sql'
          sqlPrev    = preview(det.sql)
          paramsKind = det.params_kind or 'nil'
        else
          msg        = tostring(det)
          stage      = 'sql'
          sqlPrev    = preview(nil)
          paramsKind = 'nil'
        end
        log.error('Migration %s:%s FEHLER stage=%s sql_preview="%s" params=%s error=%s\n%s',
          mod, m.version, stage, sqlPrev, paramsKind, msg, debug.traceback())
        if Axiom.audit then Axiom.audit('migration.error', mod..':'..m.version, 'system', tostring(msg)) end
        return
      end
      mark(mod, m.version)
      if Axiom.audit then Axiom.audit('migration.done', mod..':'..m.version, 'system') end
      log.info('Migration %s:%s OK', mod, m.version)
    end
  end
end

local function RunMigrations(module)
  ensureStateTable()
  if module then runModule(module) else for mod,_ in pairs(regs) do runModule(mod) end end
end

RegisterNetEvent(Axiom.ev.ModuleReady, function(mod) if type(mod)=='string' then RunMigrations(mod) end end)

exports('RegisterMigration', RegisterMigration)
exports('RunMigrations',     RunMigrations)
