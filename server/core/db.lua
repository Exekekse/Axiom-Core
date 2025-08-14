Axiom = Axiom or {}
local log = Axiom.log or { warn=print, error=print, info=print }
local cfg = (Axiom.config and Axiom.config.db) or {}
local slow_ms = tonumber(cfg.slow_ms) or 100

local stats = { calls = 0, total_ms = 0, slow = 0, samples = {}, top = {} }
local SAMPLE_MAX = 200

local function fingerprint(sql)
  sql = (sql or ''):gsub('%s+',' ')
  if #sql > 120 then sql = sql:sub(1,120)..'…' end
  return sql
end

local function record(op, sql, ms)
  stats.calls = stats.calls + 1
  stats.total_ms = stats.total_ms + ms
  stats.samples[#stats.samples+1] = ms
  if #stats.samples > SAMPLE_MAX then table.remove(stats.samples,1) end
  local fp = fingerprint(sql)
  local t = stats.top[fp] or { count = 0, total = 0 }
  t.count = t.count + 1
  t.total = t.total + ms
  stats.top[fp] = t
  if ms >= slow_ms then
    stats.slow = stats.slow + 1
    log.warn('[DB][slow] %dms %s %s', ms, op, fp)
  end
end

local function metrics()
  local avg = (stats.calls > 0) and (stats.total_ms / stats.calls) or 0
  local samples = { table.unpack(stats.samples) }
  table.sort(samples)
  local p95 = 0
  if #samples > 0 then
    local idx = math.ceil(#samples * 0.95)
    p95 = samples[idx]
  end
  local top = {}
  for k,v in pairs(stats.top) do top[#top+1] = { fingerprint=k, count=v.count, avg_ms=(v.total/v.count) } end
  table.sort(top, function(a,b) return a.count>b.count end)
  return { calls=stats.calls, slow_warnings=stats.slow, avg_ms=avg, p95_ms=p95, top_queries=top }
end

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

local function ensureSql(q)
  if type(q) ~= 'string' then error(('E_DB_BADSQL: expected string, got %s'):format(type(q))) end
end

local function ensureParams(p)
  if p ~= nil and type(p) ~= 'table' then error(('E_DB_BADPARAMS: expected table, got %s'):format(type(p))) end
end

local function run(op, q, p, fn)
  local t0 = GetGameTimer()
  local ok, res = pcall(fn, q, p or {})
  local ms = GetGameTimer() - t0
  record(op, q, ms)
  if not ok then
    local err = tostring(res)
    log.error('[DB][%s] %s sql="%s" params=%s', op, err, fingerprint(q), type(p))
    error(err)
  end
  return res
end

local mysql = {
  scalar = function(q,p) return MySQL.scalar.await(q,p) end,
  single = function(q,p) return MySQL.single.await(q,p) end,
  query  = function(q,p) return MySQL.query.await(q,p)  end,
  exec   = function(q,p) return MySQL.update.await(q,p) end,
}

local function scalar(q, p)
  ensureSql(q); ensureParams(p)
  if not need() then return nil end
  return run('scalar', q, p, mysql.scalar)
end
local function single(q, p)
  ensureSql(q); ensureParams(p)
  if not need() then return nil end
  return run('single', q, p, mysql.single)
end
local function query(q, p)
  ensureSql(q); ensureParams(p)
  if not need() then return nil end
  return run('query', q, p, mysql.query)
end
local function exec(q, p)
  ensureSql(q); ensureParams(p)
  if not need() then return 0 end
  return run('exec', q, p, mysql.exec)
end

local function tx(fn)
  if not need() then return false, 'no_db' end
  local t0 = GetGameTimer()
  MySQL.update.await('START TRANSACTION')
  local ok, err = pcall(function()
    local sql = {
      exec   = function(q, p) ensureSql(q); ensureParams(p); return run('tx.exec', q, p, mysql.exec) end,
      query  = function(q, p) ensureSql(q); ensureParams(p); return run('tx.query', q, p, mysql.query) end,
      single = function(q, p) ensureSql(q); ensureParams(p); return run('tx.single', q, p, mysql.single) end,
      scalar = function(q, p) ensureSql(q); ensureParams(p); return run('tx.scalar', q, p, mysql.scalar) end,
    }
    return fn(sql)
  end)
  if not ok then
    MySQL.update.await('ROLLBACK')
    record('tx', 'tx', GetGameTimer()-t0)
    log.error('[DB][tx] %s', tostring(err))
    return false, tostring(err)
  end
  MySQL.update.await('COMMIT')
  record('tx', 'tx', GetGameTimer()-t0)
  return true
end

exports('DbScalar', scalar)
exports('DbSingle', single)
exports('DbQuery',  query)
exports('DbExec',   exec)
exports('DbTx',     tx)

exports('DbMetrics', function() return metrics() end)

local function health()
  if not need() then return false end
  local ok, res = pcall(function() return MySQL.scalar.await('SELECT 1', {}) end)
  return ok and res == 1
end

exports('DbHealth', health)
