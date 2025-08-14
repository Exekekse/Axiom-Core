Axiom = Axiom or {}
local log = Axiom.log or { warn=print, error=print, info=print }

local function ready()
  return type(MySQL) == 'table'
     and MySQL.scalar and MySQL.scalar.await
     and MySQL.query  and MySQL.query.await
     and MySQL.update and MySQL.update.await
end

local function need()
  if not ready() then log.warn('DB nicht verfügbar – Vorgang übersprungen'); return false end
  return true
end

local function scalar(q, p) if not need() then return nil end return MySQL.scalar.await(q, p or {}) end
local function single(q, p) if not need() then return nil end return MySQL.single.await(q, p or {}) end
local function query(q, p)  if not need() then return nil end return MySQL.query.await(q, p or {}) end
local function exec(q, p)   if not need() then return 0   end return MySQL.update.await(q, p or {}) end

local function tx(fn)
  if not need() then return false, 'no_db' end
  MySQL.update.await('START TRANSACTION')
  local ok, err = pcall(function()
    local sql = {
      exec   = function(q, p) return MySQL.update.await(q, p or {}) end,
      query  = function(q, p) return MySQL.query.await(q, p or {}) end,
      single = function(q, p) return MySQL.single.await(q, p or {}) end,
      scalar = function(q, p) return MySQL.scalar.await(q, p or {}) end,
    }
    return fn(sql)
  end)
  if not ok then MySQL.update.await('ROLLBACK'); return false, tostring(err) end
  MySQL.update.await('COMMIT'); return true
end

exports('DbScalar', scalar)
exports('DbSingle', single)
exports('DbQuery',  query)
exports('DbExec',   exec)
exports('DbTx',     tx)

local function health()
  if not need() then return false end
  local ok, res = pcall(function() return MySQL.scalar.await('SELECT 1', {}) end)
  return ok and res == 1
end

exports('DbHealth', health)
