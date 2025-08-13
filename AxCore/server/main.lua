Axiom = Axiom or {}
local log  = Axiom.log
local cfg  = Axiom.config or {}
local hb   = tonumber(cfg.heartbeat_ms) or 60000
local RES  = GetCurrentResourceName()

pcall(function() exports[RES]:SetLogLevel((cfg.log_level or 'info'):lower()) end)

CreateThread(function()
  log.info('Core %s gestartet (Resource: %s) – LogLevel=%s, Heartbeat=%dms',
    Axiom.version, RES, (cfg.log_level or 'info'), hb)
  pcall(function() exports[RES]:RunMigrations('axiom-core') end)
  while true do Wait(hb); log.trace('Heartbeat ok') end
end)

-- Identifier gem. Config
local PREFIX = { license='license:', rockstar='license:', steam='steam:', fivem='fivem:', discord='discord:', xbl='xbl:', live='live:', ip='ip:' }
local preferred = (cfg.identifiers and cfg.identifiers.preferred) or { 'license' }
local function getPreferredIdent(src)
  if not src or src==0 then return nil end
  local found={}
  for i=0,GetNumPlayerIdentifiers(src)-1 do local id=GetPlayerIdentifier(src,i); if id then for kind,pfx in pairs(PREFIX) do if id:sub(1,#pfx)==pfx then found[kind]=id end end end end
  for _,kind in ipairs(preferred) do local id=found[kind]; if id then return kind, id:sub(#(PREFIX[kind])+1) end end
  for kind,id in pairs(found) do return kind, id:sub(#(PREFIX[kind])+1) end
  return nil
end

-- UID-Vergabe (TX + Retry) für (id_kind,id_value)
math.randomseed(GetGameTimer() + os.time())
local CHARS='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
local function genUid(n) n=n or 10; local t={} for i=1,n do local k=math.random(#CHARS); t[i]=CHARS:sub(k,k) end; return table.concat(t) end
local function isValidUid(u) return type(u)=='string' and #u==10 and u:match('^[A-Za-z0-9]+$')~=nil end

local function ensureUidFor(kind, value, name)
  for _=1,20 do
    local ok, err = exports[RES]:DbTx(function(sql)
      local row = sql.single('SELECT uid FROM ax_players WHERE id_kind=? AND id_value=? LIMIT 1', { kind, value })
      if row and row.uid and row.uid~='' then
        sql.exec('UPDATE ax_players SET name=?, last_seen=CURRENT_TIMESTAMP WHERE id_kind=? AND id_value=?', { name, kind, value })
        return true
      end
      local uid = genUid(10); if not isValidUid(uid) then error('invalid_uid') end
      local ex = sql.scalar('SELECT 1 FROM ax_players WHERE uid=? LIMIT 1', { uid }); if ex then error('uid_collision') end
      sql.exec([[
        INSERT INTO ax_players (uid, id_kind, id_value, name)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE name=VALUES(name), last_seen=CURRENT_TIMESTAMP
      ]], { uid, kind, value, name })
      return true
    end)
    if ok then local out=exports[RES]:DbSingle('SELECT uid FROM ax_players WHERE id_kind=? AND id_value=? LIMIT 1',{kind,value}); return out and out.uid or nil
    else local s=tostring(err or ''); if not (s:find('uid_collision') or s:find('invalid_uid')) then log.warn('ensureUidFor Tx-Fehler: %s',s); break end end
  end
  log.warn('ensureUidFor: UID konnte nicht zugewiesen werden (%s:%s)', tostring(kind), tostring(value))
  return nil
end

-- Lifecycle + KPIs
Axiom.kpi = { join_ms_sum=0, join_count=0, char_ms_sum=0, char_count=0 }

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
  local src = source
  local tJoin = GetGameTimer()
  local kind, value = getPreferredIdent(src); if not kind then return end

  local uid = ensureUidFor(kind, value, name)
  local function ensureChar(uid)
    local t0 = GetGameTimer()
    local cid = exports[RES]:CharEnsure(uid, { firstname = (name or ''):sub(1,30), lastname = '' })
    local dt = GetGameTimer() - t0
    Axiom.kpi.char_ms_sum = Axiom.kpi.char_ms_sum + dt
    Axiom.kpi.char_count  = Axiom.kpi.char_count + 1
    return cid
  end

  local mnt = cfg.maintenance or {}
  if mnt.enabled then
    deferrals.defer(); deferrals.update('Prüfe Zugangsberechtigung …')
    local allowed = uid and (exports[RES]:HasRole(uid,'admin') or false)
    if not allowed and uid then for _,u in ipairs(mnt.allow_uids or {}) do if u==uid then allowed=true break end end end
    if not allowed then deferrals.done(mnt.message or 'Wartungsmodus'); return end
    local cid = ensureChar(uid); if not cid then deferrals.done('Charakter konnte nicht angelegt werden.'); return end
    TriggerEvent(Axiom.ev.CharacterReady, cid, uid)
    deferrals.done()
  else
    local ok, err = pcall(function()
      local cid = ensureChar(uid); if not cid then error('char_create_failed') end
      TriggerEvent(Axiom.ev.CharacterReady, cid, uid)
    end)
    if not ok then setKickReason('Charakter konnte nicht angelegt werden.'); CancelEvent(); return end
  end

  local dtJoin = GetGameTimer() - tJoin
  Axiom.kpi.join_ms_sum = Axiom.kpi.join_ms_sum + dtJoin
  Axiom.kpi.join_count  = Axiom.kpi.join_count + 1
end)

AddEventHandler('playerDropped', function()
  local src = source
  local kind, value = getPreferredIdent(src); if not kind then return end
  local ok, err = pcall(function()
    exports[RES]:DbExec('UPDATE ax_players SET last_seen=CURRENT_TIMESTAMP WHERE id_kind=? AND id_value=?', { kind, value })
  end)
  if not ok then log.warn('playerDropped update error: %s', tostring(err)) end
end)

-- Commands
RegisterCommand('axiom:ping', function(src) if src==0 then print('[Axiom] pong (server console)') else TriggerClientEvent('chat:addMessage',src,{args={'Axiom','^2pong'}}) end end,false)

RegisterCommand('axiom:modules', function(src)
  local list = exports[RES]:ListModules() or {}
  local text = (#list==0) and 'keine Module registriert' or table.concat((function() local t={}; for _,m in ipairs(list) do t[#t+1]=('%s (%s)'):format(m.name, m.version or '0.0.0') end; return t end)(), ', ')
  if src==0 then print('[Axiom] Module:', text) else TriggerClientEvent('chat:addMessage', src, { args={'Axiom', text} }) end
end, false)

RegisterCommand('axiom:health', function(src)
  local dbOK=false; local ok,res=pcall(function() return exports[RES]:DbScalar('SELECT 1',{}) end); dbOK=ok and (res==1)
  local summary = (('[Axiom] Health: DB=%s | Players=%d'):format(dbOK and 'OK' or 'NOK', #GetPlayers()))
  if src==0 then print(summary) else TriggerClientEvent('chat:addMessage', src, { args={'Axiom', summary} }) end
end, false)

RegisterCommand('axiom:metrics', function(src)
  local rpc = exports[RES]:RpcMetrics() or {}
  local rows = {}
  for name,st in pairs(rpc) do rows[#rows+1]={ name=name, calls=st.calls, ok=st.ok, fail=st.fail, rate=st.rate, exc=st.exc, avg=math.floor(st.avg_ms) } end
  table.sort(rows, function(a,b) return a.calls>b.calls end)
  local top = math.min(#rows, (cfg.health and cfg.health.top_rpc_n) or 5)
  local k = Axiom.kpi or {}; local join_avg=(k.join_count>0) and math.floor(k.join_ms_sum/k.join_count) or 0; local char_avg=(k.char_count>0) and math.floor(k.char_ms_sum/k.char_count) or 0
  if src==0 then
    print(('[Axiom] KPIs: join_avg=%dms char_avg=%dms'):format(join_avg,char_avg))
    print('[Axiom] Top RPCs:'); for i=1,top do local r=rows[i]; print(('- %s: calls=%d ok=%d fail=%d rate=%d exc=%d avg=%dms'):format(r.name,r.calls,r.ok,r.fail,r.rate,r.exc,r.avg)) end
  else
    local line=(('[Axiom] KPIs: join_avg=%dms · char_avg=%dms'):format(join_avg,char_avg))
    if top==0 then TriggerClientEvent('chat:addMessage',src,{args={'Axiom',line..' · Keine RPC-Daten.'}})
    else local rl={}; for i=1,top do local r=rows[i]; rl[#rl+1]=('%s(%d/%d,%dms)'):format(r.name,r.ok,r.calls,r.avg) end; TriggerClientEvent('chat:addMessage',src,{args={'Axiom',line..' · Top RPCs: '..table.concat(rl,' · ')}}) end
  end
end,false)

RegisterCommand('axiom:uid', function(src)
  if src==0 then print('Nur ingame.') return end
  local kind,value=getPreferredIdent(src); if not kind then return end
  local row=exports[RES]:DbSingle('SELECT uid FROM ax_players WHERE id_kind=? AND id_value=? LIMIT 1',{kind,value})
  local uid=(row and row.uid) or 'n/a'
  TriggerClientEvent('chat:addMessage', src, { args={'Axiom', ('UID: ^3%s'):format(uid)} })
end,false)

-- Konsistenz-Check: jede uid genau einen cid
RegisterCommand('axiom:check', function(src)
  local missing = exports[RES]:DbQuery([[SELECT p.uid FROM ax_players p LEFT JOIN ax_characters c ON c.uid=p.uid WHERE c.uid IS NULL]]) or {}
  local extras  = exports[RES]:DbQuery([[SELECT uid, COUNT(*) AS n FROM ax_characters GROUP BY uid HAVING n <> 1]]) or {}
  if src==0 then
    print(('[Axiom] Consistency: missing_chars=%d, not_1to1=%d'):format(#missing,#extras))
    if #missing>0 then print('Missing (uid):'); for _,r in ipairs(missing) do print('-',r.uid) end end
    if #extras>0 then print('Not 1:1 (uid,n):'); for _,r in ipairs(extras) do print('-',r.uid,r.n) end end
  else
    TriggerClientEvent('chat:addMessage', src, { args={'Axiom', ('Consistency: missing=%d, not_1to1=%d'):format(#missing,#extras)} })
  end
end,false)
