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

local function runFor(mod)
  local list = regs[mod]; if not list or #list==0 then return end
  for _,m in ipairs(list) do
    if not applied(mod, m.version) then
      log.info('Migration %s:%s wird angewendet …', mod, m.version)
      if Axiom.audit then Axiom.audit('migration.start', mod..':'..m.version, 'system') end
      local ok, err = pcall(function()
        if type(m.sql) == 'function' then
          return m.sql()
        else
          return DbExec(m.sql)
        end
      end)
      if not ok then
        local msg = err
        if type(err) == 'table' then msg = err.message or err.code or tostring(err) end
        log.error('Migration %s:%s FEHLER: %s', mod, m.version, tostring(msg))
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
