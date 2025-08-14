Axiom = Axiom or {}
local log  = Axiom.log
local cfg  = Axiom.config or {}
local hb   = tonumber(cfg.heartbeat_ms) or 60000
local RES  = GetCurrentResourceName()
local ax   = exports[RES]
local CORE = 'Axiom-Core'
local allowedRoles = (cfg.roles and cfg.roles.allow) or {}
local getTime = GetGameTimer
local Wait = Wait

pcall(function() ax:SetLogLevel((cfg.log_level or 'info'):lower()) end)

local running = true
CreateThread(function()
  log.info('Core %s gestartet (Resource: %s) – LogLevel=%s, Heartbeat=%dms',
    Axiom.version, RES, (cfg.log_level or 'info'), hb)
  pcall(function() ax:RunMigrations('axiom-core') end)
  while running do Wait(hb); log.trace('Heartbeat ok') end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= RES then return end
  running = false
end)

-- Identifier via Players service
local function getPreferredIdent(src)
  return ax:GetIdent(src)
end

-- UID-Vergabe (TX + Retry) für (id_kind,id_value)
math.randomseed(getTime() + os.time())
local CHARS='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
local function genUid(n) n=n or 10; local t={} for i=1,n do local k=math.random(#CHARS); t[i]=CHARS:sub(k,k) end; return table.concat(t) end
local function isValidUid(u) return type(u)=='string' and #u==10 and u:match('^[A-Za-z0-9]+$')~=nil end

local function ensureUidFor(kind, value, name)
  for _=1,20 do
    local ok, err = ax:DbTx(function(sql)
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
    if ok then local out=ax:DbSingle('SELECT uid FROM ax_players WHERE id_kind=? AND id_value=? LIMIT 1',{kind,value}); return out and out.uid or nil
    else local s=tostring(err or ''); if not (s:find('uid_collision') or s:find('invalid_uid')) then log.warn('ensureUidFor Tx-Fehler: %s',s); break end end
  end
  log.warn('ensureUidFor: UID konnte nicht zugewiesen werden (%s:%s)', tostring(kind), tostring(value))
  return nil
end

-- Lifecycle + KPIs
Axiom.kpi = { join_ms_sum=0, join_count=0, char_ms_sum=0, char_count=0 }

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
  local src = source
  local tJoin = getTime()
  local kind, value = getPreferredIdent(src); if not kind then return end

  local uid = ensureUidFor(kind, value, name)
  local function ensureChar(uid)
    local t0 = getTime()
    local cid = ax:CharEnsure(uid, { firstname = (name or ''):sub(1,30), lastname = '' })
    local dt = getTime() - t0
    Axiom.kpi.char_ms_sum = Axiom.kpi.char_ms_sum + dt
    Axiom.kpi.char_count  = Axiom.kpi.char_count + 1
    return cid
  end

  local mnt = cfg.maintenance or {}
  if mnt.enabled then
    deferrals.defer(); deferrals.update('Prüfe Zugangsberechtigung …')
    local allowed = uid and (ax:HasRole(uid,'admin') or false)
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

  local dtJoin = getTime() - tJoin
  Axiom.kpi.join_ms_sum = Axiom.kpi.join_ms_sum + dtJoin
  Axiom.kpi.join_count  = Axiom.kpi.join_count + 1
end)

AddEventHandler('playerDropped', function()
  local src = source
  local kind, value = getPreferredIdent(src); if not kind then return end
  local ok, err = pcall(function()
    ax:DbExec('UPDATE ax_players SET last_seen=CURRENT_TIMESTAMP WHERE id_kind=? AND id_value=?', { kind, value })
  end)
  if not ok then log.warn('playerDropped update error: %s', tostring(err)) end
end)

-- Smoke-Test Allowlist aus ENV
local ALLOW_SMOKE = {}
do
  local raw = os.getenv('ADMIN_UIDS_ALLOW_SMOKE')
  if raw and raw ~= '' then
    local ok, arr = pcall(json.decode, raw)
    if ok and type(arr)=='table' then for _,u in ipairs(arr) do ALLOW_SMOKE[u]=true end end
  end
end

local function smokeAllowed(src)
  if src==0 then return true end
  local kind,value = getPreferredIdent(src); if not kind then return false end
  local row = ax:DbSingle('SELECT uid FROM ax_players WHERE id_kind=? AND id_value=? LIMIT 1',{kind,value})
  local uid = row and row.uid
  if not uid then return false end
  if ALLOW_SMOKE[uid] then return true end
  return ax:HasRole(uid,'admin') or false
end

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
local function splitFirst(s, sep)
  local a,b = s:find(sep, 1, true); if not a then return s, nil end
  return s:sub(1, a-1), s:sub(b+1)
end
local function isUid(v) return type(v)=='string' and #v==10 and v:match('^[A-Za-z0-9]+$') end
local function isHex(v) return type(v)=='string' and v:match('^[0-9a-fA-F]+$') end

local function resolveUid(target)
  target = trim(target or '')
  if target == '' then return nil, 'invalid target: empty' end

  -- bare UID
  if isUid(target) then return target end

  -- bare Server-ID
  if target:match('^%d+$') then
    local sid = tonumber(target)
    if sid and sid >= 1 and sid <= 4096 then
      local uid = exports[CORE]:GetUid(sid)
      if not uid then return nil, ('no uid for server id %d (offline?)'):format(sid) end
      return uid
    end
  end

  -- bare license (hex 32–64)
  if #target >= 32 and #target <= 64 and isHex(target) then
    local row = exports[CORE]:DbSingle(
      'SELECT uid FROM ax_players WHERE id_kind=? AND id_value=? LIMIT 1',
      { 'license', target:lower() }
    )
    if not row or not row.uid then
      return nil, ('no player found for license:%s'):format(target)
    end
    return row.uid
  end

  -- prefixierte Formen
  local kind, value = splitFirst(target, ':')
  if not value then return nil, 'invalid target' end
  if value:find(':', 1, true) then
    local k2, v2 = splitFirst(value, ':'); if k2 == kind then value = v2 end
  end

  kind = kind:lower()
  if kind == 'uid' then
    if not isUid(value) then return nil, 'invalid uid' end
    return value
  elseif kind == 'id' then
    if not value:match('^%d+$') then return nil, 'invalid server id' end
    local sid = tonumber(value)
    local uid = exports[CORE]:GetUid(sid)
    if not uid then return nil, ('no uid for server id %d (offline?)'):format(sid) end
    return uid
  else
    local allowed = { license=true, steam=true, rockstar=true, fivem=true, discord=true, xbl=true, live=true }
    if not allowed[kind] then return nil, 'unknown identifier kind' end
    if value == '' then return nil, 'missing identifier value' end
    local row = exports[CORE]:DbSingle(
      'SELECT uid FROM ax_players WHERE id_kind=? AND id_value=? LIMIT 1',
      { kind, value }
    )
    if not row or not row.uid then
      return nil, ('no player found for %s:%s'):format(kind, value)
    end
    return row.uid
  end
end

-- Commands
RegisterCommand('axiom:ping', function(src) if src==0 then print('[Axiom] pong (server console)') else TriggerClientEvent('chat:addMessage',src,{args={'Axiom','^2pong'}}) end end,false)

RegisterCommand('axiom:modules', function(src)
  local list = ax:ListModules() or {}
  local text = (#list==0) and 'keine Module registriert' or table.concat((function() local t={}; for _,m in ipairs(list) do t[#t+1]=('%s (%s)'):format(m.name, m.version or '0.0.0') end; return t end)(), ', ')
  if src==0 then print('[Axiom] Module:', text) else TriggerClientEvent('chat:addMessage', src, { args={'Axiom', text} }) end
end, false)

RegisterCommand('axiom:dbtest', function(src, args)
  if args[1]=='smoke' then
    if not smokeAllowed(src) then
      local msg='smoke SKIPPED'
      if src==0 then print(msg) else TriggerClientEvent('chat:addMessage',src,{args={'Axiom',msg}}) end
      return
    end
    local note=('smoke-%d'):format(math.random(100000,999999))
    ax:DbExec('CREATE TABLE IF NOT EXISTS ax_smoke (id INT AUTO_INCREMENT PRIMARY KEY, note VARCHAR(50), created TIMESTAMP DEFAULT CURRENT_TIMESTAMP)')
    local okIns = ax:DbExec('INSERT INTO ax_smoke (note) VALUES (?)', {note}) > 0
    local row = ax:DbSingle('SELECT id, note FROM ax_smoke WHERE note=? ORDER BY id DESC LIMIT 1', {note}) or {}
    local msg = (okIns and row.note==note) and ('smoke id=%s note=%s'):format(row.id, row.note) or 'smoke NOK'
    if src==0 then print(msg) else TriggerClientEvent('chat:addMessage',src,{args={'Axiom',msg}}) end
    return
  end
  local t0=getTime()
  local ok,res=pcall(function() return ax:DbScalar('SELECT 1',{}) end)
  local dt=getTime()-t0
  local msg=(ok and res==1) and ('[DB] Health OK (%dms)'):format(dt) or '[DB] Health NOK'
  if src==0 then print(msg) else TriggerClientEvent('chat:addMessage',src,{args={'Axiom',msg}}) end
end,true)

RegisterCommand('axiom:health', function(src)
  local dbOK=false; local ok,res=pcall(function() return ax:DbScalar('SELECT 1',{}) end); dbOK=ok and (res==1)
  local summary = (('[Axiom] Health: DB=%s | Players=%d'):format(dbOK and 'OK' or 'NOK', #GetPlayers()))
  if src==0 then print(summary) else TriggerClientEvent('chat:addMessage', src, { args={'Axiom', summary} }) end
end, false)

RegisterCommand('axiom:metrics', function(src)
  local rpc = ax:RpcMetrics() or {}
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
  local row=ax:DbSingle('SELECT uid FROM ax_players WHERE id_kind=? AND id_value=? LIMIT 1',{kind,value})
  local uid=(row and row.uid) or 'n/a'
  TriggerClientEvent('chat:addMessage', src, { args={'Axiom', ('UID: ^3%s'):format(uid)} })
end,false)

-- Konsistenz-Check
RegisterCommand('axiom:check', function(src)
  if src ~= 0 then print('Nur Server-Konsole.') return end
  local missing = ax:DbQuery([[SELECT p.uid FROM ax_players p LEFT JOIN ax_characters c ON c.uid=p.uid WHERE c.uid IS NULL]]) or {}
  local extras  = ax:DbQuery([[SELECT uid, COUNT(*) AS n FROM ax_characters GROUP BY uid HAVING n <> 1]]) or {}
  local orphanRoles = ax:DbQuery([[SELECT r.uid FROM ax_perm_roles r LEFT JOIN ax_players p ON p.uid=r.uid WHERE p.uid IS NULL]]) or {}
  local orphanPMeta = ax:DbQuery([[SELECT m.uid FROM ax_player_meta m LEFT JOIN ax_players p ON p.uid=m.uid WHERE p.uid IS NULL]]) or {}
  local orphanCMeta = ax:DbQuery([[SELECT m.cid FROM ax_character_meta m LEFT JOIN ax_characters c ON c.cid=m.cid WHERE c.cid IS NULL]]) or {}
  local ok = (#missing==0 and #extras==0 and #orphanRoles==0 and #orphanPMeta==0 and #orphanCMeta==0)
  local status = ok and 'OK' or 'NOK'
  print(('[Axiom] Consistency %s: players_without_char=%d, chars_not_1to1=%d, orphan_roles=%d, orphan_player_meta=%d, orphan_character_meta=%d')
    :format(status, #missing, #extras, #orphanRoles, #orphanPMeta, #orphanCMeta))
  local function sample(rows, field)
    local out = {}
    for i=1,math.min(3,#rows) do out[#out+1] = rows[i][field] end
    return table.concat(out, ',')
  end
  if not ok then
    if #missing>0 then print('  missing uid:', sample(missing,'uid')) end
    if #extras>0 then print('  not_1to1 uid:', sample(extras,'uid')) end
    if #orphanRoles>0 then print('  orphan_roles uid:', sample(orphanRoles,'uid')) end
    if #orphanPMeta>0 then print('  orphan_player_meta uid:', sample(orphanPMeta,'uid')) end
    if #orphanCMeta>0 then print('  orphan_character_meta cid:', sample(orphanCMeta,'cid')) end
  end
end,false)

RegisterCommand('axiom:roles:add', function(src, args)
  if src~=0 then print('Nur Server-Konsole.') return end
  local target, role = args[1], args[2]
  if not target or not role then
    print('Usage: axiom:roles:add <uid|id|license|…> <role>')
    return
  end
  local uid, err = resolveUid(target)
  if not uid then
    print('Fehler: '..(err or 'UID nicht gefunden'))
    print('Usage: axiom:roles:add <uid|id|license|…> <role>')
    return
  end
  if ax:HasRole(uid, role) then
    print('Role existiert bereits')
    return
  end
  local ok, e = ax:AddRole(uid, role)
  if not ok and e == 'E_ROLE_UNKNOWN' then
    print('Role unbekannt. Erlaubt: '..table.concat(allowedRoles, ', '))
    return
  end
  ax:Audit('role.add', uid, 'console', ('role=%s'):format(role))
  print(('added role %s to uid=%s'):format(role, uid))
end,false)

RegisterCommand('axiom:roles:remove', function(src, args)
  if src~=0 then print('Nur Server-Konsole.') return end
  local target, role = args[1], args[2]
  if not target or not role then
    print('Usage: axiom:roles:remove <uid|id|license|…> <role>')
    return
  end
  local uid, err = resolveUid(target)
  if not uid then
    print('Fehler: '..(err or 'UID nicht gefunden'))
    print('Usage: axiom:roles:remove <uid|id|license|…> <role>')
    return
  end
  ax:RemoveRole(uid, role)
  ax:Audit('role.remove', uid, 'console', ('role=%s'):format(role))
  print(('removed role %s from uid=%s'):format(role, uid))
end,false)

RegisterCommand('axiom:roles:list', function(src, args)
  if src~=0 then print('Nur Server-Konsole.') return end
  local target = args[1]
  if not target then
    print('Usage: axiom:roles:list <uid|id|license|…>')
    return
  end
  local uid, err = resolveUid(target)
  if not uid then
    print('Fehler: '..(err or 'UID nicht gefunden'))
    print('Usage: axiom:roles:list <uid|id|license|…>')
    return
  end
  local roles = ax:ListRoles(uid) or {}
  if #roles==0 then
    print(('uid=%s roles: <none>'):format(uid))
  else
    print(('uid=%s roles: %s'):format(uid, table.concat(roles, ', ')))
  end
end,false)
