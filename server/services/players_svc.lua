Axiom = Axiom or {}
local RES = GetCurrentResourceName()
local ax  = exports[RES]
local cfg = Axiom.config or {}

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
    local id = found[kind]; if id then return kind, id:sub(#(PREFIX[kind])+1) end
  end
  for kind,id in pairs(found) do return kind, id:sub(#(PREFIX[kind])+1) end
  return nil
end

-- uid<->src Map
local uidBySrc, srcByUid = {}, {}
local function setMap(src, uid) uidBySrc[src]=uid; if uid then srcByUid[uid]=src end end

AddEventHandler('playerJoining', function()
  local src=source; local kind,val=pickIdentifier(src); if not kind then return end
  local row = ax:DbSingle('SELECT uid FROM ax_players WHERE id_kind=? AND id_value=? LIMIT 1', { kind, val })
  setMap(src, row and row.uid or nil)
end)
AddEventHandler('playerDropped', function() local src=source; local uid=uidBySrc[src]; uidBySrc[src]=nil; if uid then srcByUid[uid]=nil end end)

-- Rollen in separater Tabelle (ax_perm_roles)
local function hasRole(uid, role)
  local r = ax:DbScalar(
    'SELECT 1 FROM ax_perm_roles WHERE uid = ? AND role = ? LIMIT 1',
    { uid, role }
  )
  return r ~= nil
end

local function addRole(uid, role)
  ax:DbExec(
    'INSERT IGNORE INTO ax_perm_roles (uid, role) VALUES (?, ?)',
    { uid, role }
  )
  if Axiom.audit then Axiom.audit('role.add', 'uid=%s role=%s', uid, role) end
end

local function removeRole(uid, role)
  ax:DbExec(
    'DELETE FROM ax_perm_roles WHERE uid = ? AND role = ?',
    { uid, role }
  )
  if Axiom.audit then Axiom.audit('role.remove', 'uid=%s role=%s', uid, role) end
end

local function listRoles(uid)
  local rows = ax:DbQuery(
    'SELECT role FROM ax_perm_roles WHERE uid = ? ORDER BY role ASC',
    { uid }
  ) or {}
  local out = {}
  for _, r in ipairs(rows) do out[#out+1] = r.role end
  return out
end

-- Player-Meta KV
local function playerGetMeta(uid) local rows=ax:DbQuery('SELECT k,v FROM ax_player_meta WHERE uid=?',{uid}) or {}; local t={}; for _,r in ipairs(rows) do t[r.k]=r.v end; return t end
local function playerSetMetaKV(uid,k,v) if v==nil or v=='' then ax:DbExec('DELETE FROM ax_player_meta WHERE uid=? AND k=?',{uid,k}) else ax:DbExec([[INSERT INTO ax_player_meta (uid,k,v) VALUES (?,?,?) ON DUPLICATE KEY UPDATE v=VALUES(v)]],{uid,k,tostring(v)}) end end
local function playerDelMetaKV(uid,k) ax:DbExec('DELETE FROM ax_player_meta WHERE uid=? AND k=?',{uid,k}) end

-- Exports
exports('GetIdent', function(src) return pickIdentifier(src) end)
exports('GetUid', function(src) local uid=uidBySrc[src]; if uid then return uid end local kind,val=pickIdentifier(src); if not kind then return nil end local row=ax:DbSingle('SELECT uid FROM ax_players WHERE id_kind=? AND id_value=? LIMIT 1',{kind,val}); uid=row and row.uid or nil; setMap(src,uid); return uid end)
exports('GetSrc', function(uid) return srcByUid[uid] end)
exports('ForEachPlayer', function(cb) for s,u in pairs(uidBySrc) do if cb(s,u)==false then break end end end)
exports('Count', function() local c=0 for _ in pairs(uidBySrc) do c=c+1 end return c end)

exports('HasRole',   function(uid, role) return hasRole(uid, role) end)
exports('AddRole',   function(uid, role) addRole(uid, role) end)
exports('RemoveRole',function(uid, role) removeRole(uid, role) end)
exports('ListRoles', listRoles)

exports('PlayerGetMeta',   playerGetMeta)
exports('PlayerSetMetaKV', playerSetMetaKV)
exports('PlayerDelMetaKV', playerDelMetaKV)
