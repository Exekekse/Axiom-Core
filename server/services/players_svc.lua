Axiom = Axiom or {}
local log = Axiom.log or { info=print, warn=print, error=print }
local RES = GetCurrentResourceName()
local ax  = exports[RES]
local cfg = Axiom.config or {}
local cache = Axiom.cache or {}
local err = Axiom.err or { ok=function(d) return {ok=true,code=nil,data=d} end, fail=function(c,m,d) return {ok=false,code=c,msg=m,data=d} end }
local allowedRoles = (cfg.roles and cfg.roles.allow) or {}

local function roleAllowed(role)
  for _, r in ipairs(allowedRoles) do
    if r == role then return true end
  end
  return false
end

local PREFIX = {
  license='license:', rockstar='license:',
  steam='steam:', fivem='fivem:', discord='discord:',
  xbl='xbl:', live='live:', ip='ip:',
}
local preferred = (cfg.identifiers and cfg.identifiers.preferred) or { 'license' }

local function pickIdentifier(src)
  if not src or src == 0 then return nil end
  local found = {}
  for i=0, GetNumPlayerIdentifiers(src)-1 do
    local id = GetPlayerIdentifier(src, i)
    if id then for kind,pfx in pairs(PREFIX) do if id:sub(1,#pfx)==pfx then found[kind]=id end end end
  end
  for _,kind in ipairs(preferred) do
    local id = found[kind]
    if id then
      local val = id:sub(#(PREFIX[kind])+1)
      if cache.set then cache.set(('ident:%s:%s'):format(src, kind), val) end
      return kind, val
    end
  end
  for kind,id in pairs(found) do
    local val = id:sub(#(PREFIX[kind])+1)
    if cache.set then cache.set(('ident:%s:%s'):format(src, kind), val) end
    return kind, val
  end
  return nil
end

-- uid<->src Map
local uidBySrc, srcByUid = {}, {}
local function setMap(src, uid)
  uidBySrc[src]=uid; if uid then srcByUid[uid]=src end
  if cache.set then cache.set('uid:'..tostring(src), uid) end
end

AddEventHandler('playerJoining', function()
  local src=source; local kind,val=pickIdentifier(src); if not kind then return end
  local row = ax:DbSingle('SELECT uid FROM ax_players WHERE id_kind=? AND id_value=? LIMIT 1', { kind, val })
  setMap(src, row and row.uid or nil)
end)
AddEventHandler('playerDropped', function()
  local src=source; local uid=uidBySrc[src]; uidBySrc[src]=nil; if uid then srcByUid[uid]=nil end
  if cache.del then
    cache.del('uid:'..tostring(src))
    for kind,_ in pairs(PREFIX) do cache.del(('ident:%s:%s'):format(src, kind)) end
  end
end)

AddEventHandler('onResourceStart', function(res)
  if res ~= RES then return end
  uidBySrc, srcByUid = {}, {}
  if cache.bust then cache.bust() end
  for _, sid in ipairs(GetPlayers()) do
    local src = tonumber(sid)
    local kind, val = pickIdentifier(src)
    if kind then
      local row = ax:DbSingle('SELECT uid FROM ax_players WHERE id_kind=? AND id_value=? LIMIT 1', {kind, val})
      local uid = row and row.uid
      if uid then
        setMap(src, uid)
        local cid = ax:CharEnsure(uid, {})
        TriggerEvent(Axiom.ev.CharacterReady, cid, uid)
      end
    end
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= RES then return end
  uidBySrc, srcByUid = {}, {}
  if cache.bust then cache.bust() end
end)

-- Rollen in separater Tabelle (ax_perm_roles) mit Cache
local function listRoles(uid)
  local key = 'roles:'..tostring(uid)
  local cached = cache.get and cache.get(key)
  if cached then return cached end
  local rows = ax:DbQuery(
    'SELECT role FROM ax_perm_roles WHERE uid = ? ORDER BY role ASC',
    { uid }
  ) or {}
  local out = {}
  for _, r in ipairs(rows) do out[#out+1] = r.role end
  if cache.set then
    cache.set(key, out)
    for _,r in ipairs(out) do cache.set(('role:%s:%s'):format(uid, r), true) end
  end
  return out
end

local function hasRole(uid, role)
  local key = ('role:%s:%s'):format(uid, role)
  local hit = cache.get and cache.get(key)
  if hit ~= nil then return hit end
  local roles = listRoles(uid)
  for _,r in ipairs(roles) do if r == role then if cache.set then cache.set(key, true) end; return true end end
  if cache.set then cache.set(key, false) end
  return false
end

local function addRole(uid, role)
  if not roleAllowed(role) then
    log.warn('Unknown role %s', tostring(role))
    return err.fail('E_INVALID', 'role_unknown')
  end
  ax:DbExec(
    'INSERT IGNORE INTO ax_perm_roles (uid, role) VALUES (?, ?)',
    { uid, role }
  )
  if cache.del then
    cache.del(('roles:%s'):format(uid))
    cache.del(('role:%s:%s'):format(uid, role))
  end
  return err.ok()
end

local function removeRole(uid, role)
  ax:DbExec(
    'DELETE FROM ax_perm_roles WHERE uid = ? AND role = ?',
    { uid, role }
  )
  if cache.del then
    cache.del(('roles:%s'):format(uid))
    cache.del(('role:%s:%s'):format(uid, role))
  end
  return err.ok()
end

-- Player-Meta KV
local function playerGetMeta(uid) local rows=ax:DbQuery('SELECT k,v FROM ax_player_meta WHERE uid=?',{uid}) or {}; local t={}; for _,r in ipairs(rows) do t[r.k]=r.v end; return t end
local function playerSetMetaKV(uid,k,v) if v==nil or v=='' then ax:DbExec('DELETE FROM ax_player_meta WHERE uid=? AND k=?',{uid,k}) else ax:DbExec([[INSERT INTO ax_player_meta (uid,k,v) VALUES (?,?,?) ON DUPLICATE KEY UPDATE v=VALUES(v)]],{uid,k,tostring(v)}) end end
local function playerDelMetaKV(uid,k) ax:DbExec('DELETE FROM ax_player_meta WHERE uid=? AND k=?',{uid,k}) end

-- Exports
exports('GetIdent', function(src) return pickIdentifier(src) end)
exports('GetUid', function(src)
  local uid = uidBySrc[src]
  if not uid and cache.get then uid = cache.get('uid:'..tostring(src)) end
  if uid then return uid end
  local kind,val=pickIdentifier(src); if not kind then return nil end
  local row=ax:DbSingle('SELECT uid FROM ax_players WHERE id_kind=? AND id_value=? LIMIT 1',{kind,val}); uid=row and row.uid or nil;
  setMap(src,uid); return uid
end)
exports('GetSrc', function(uid) return srcByUid[uid] end)
exports('ForEachPlayer', function(cb) for s,u in pairs(uidBySrc) do if cb(s,u)==false then break end end end)
exports('Count', function() local c=0 for _ in pairs(uidBySrc) do c=c+1 end return c end)

exports('HasRole',   function(uid, role) return hasRole(uid, role) end)
exports('AddRole',   function(uid, role) return addRole(uid, role) end)
exports('RemoveRole',function(uid, role) return removeRole(uid, role) end)
exports('ListRoles', listRoles)
exports('RoleAllowed', roleAllowed)
exports('IsAdmin', function(uid) return hasRole(uid, 'admin') end)
exports('RequireRole', function(uid, role)
  return hasRole(uid, role) and { ok=true } or { ok=false, code='E_FORBIDDEN' }
end)

exports('PlayerGetMeta',   playerGetMeta)
exports('PlayerSetMetaKV', playerSetMetaKV)
exports('PlayerDelMetaKV', playerDelMetaKV)
