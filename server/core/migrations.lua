Axiom = Axiom or {}
local log = Axiom.log or { info=print, warn=print, error=print }
local RES = GetCurrentResourceName()
local ax  = exports[RES]
local DbScalar = function(q,p) return ax:DbScalar(q,p) end
local DbExec   = function(q,p) return ax:DbExec(q,p)   end

local regs = {} -- modul -> { {version, sql}, ... }

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

local function RegisterMigration(module, version, sql)
  regs[module] = regs[module] or {}
  regs[module][#regs[module]+1] = { version = version, sql = sql }
  table.sort(regs[module], function(a,b) return tostring(a.version) < tostring(b.version) end)
end

local function preview(sql)
  sql = (sql or ''):gsub('%s+',' ')
  if #sql > 120 then sql = sql:sub(1,120)..'…' end
  return sql
end

local function runFor(mod)
  local list = regs[mod]; if not list or #list==0 then return end
  for _,m in ipairs(list) do
    if not applied(mod, m.version) then
      log.info('Migration %s:%s wird angewendet …', mod, m.version)
      if Axiom.audit then Axiom.audit('migration.start', mod..':'..m.version, 'system') end
      local ok, err = pcall(function()
        if type(m.sql) == 'function' then
          local function helper(stage, fn)
            return function(sql, params)
              assert(type(sql)=='string', ('E_DB_BADSQL: expected string, got %s'):format(type(sql)))
              if params ~= nil and type(params) ~= 'table' then error(('E_DB_BADPARAMS: expected table, got %s'):format(type(params))) end
              local ok2, res2 = pcall(fn, sql, params)
              if not ok2 then error({ stage=stage, sql=sql, params_kind=type(params), err=tostring(res2) }) end
              return res2
            end
          end
          local ctx = {}
          ctx.scalar = helper('scalar', DbScalar)
          ctx.exec   = helper('exec',   DbExec)
          ctx.tx     = function(fn)
            assert(type(fn)=='function', ('E_DB_BADTXFN: expected function, got %s'):format(type(fn)))
            return ax:DbTx(function(tx)
              local txCtx = {
                scalar = helper('tx.scalar', tx.scalar),
                exec   = helper('tx.exec',   tx.exec),
              }
              return fn(txCtx)
            end)
          end
          return m.sql(ctx)
        else
          assert(type(m.sql)=='string', ('E_DB_BADSQL: expected string, got %s'):format(type(m.sql)))
          return DbExec(m.sql)
        end
      end)
      if not ok then
        local det = err
        local msg, stage, sqlPrev, paramsKind
        if type(det) == 'table' then
          msg        = det.err or det.message or det.code or tostring(det)
          stage      = det.stage
          sqlPrev    = preview(det.sql)
          paramsKind = det.params_kind
        else
          msg = tostring(det)
        end
        log.error('Migration %s:%s FEHLER stage=%s sql="%s" params=%s error=%s\n%s',
          mod, m.version, tostring(stage or '?'), tostring(sqlPrev or ''), tostring(paramsKind or 'nil'), tostring(msg), debug.traceback())
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
  if module then runFor(module) else for mod,_ in pairs(regs) do runFor(mod) end end
end

RegisterNetEvent(Axiom.ev.ModuleReady, function(mod) if type(mod)=='string' then RunMigrations(mod) end end)

exports('RegisterMigration', RegisterMigration)
exports('RunMigrations',     RunMigrations)
