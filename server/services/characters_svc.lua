Axiom = Axiom or {}
local RES = GetCurrentResourceName()
local ax  = exports[RES]

math.randomseed(GetGameTimer() + os.time())
local CHARS='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
local function genId(n) n=n or 10; local t={} for i=1,n do local k=math.random(#CHARS); t[i]=CHARS:sub(k,k) end; return table.concat(t) end
local function validId(s) return type(s)=='string' and #s==10 and s:match('^[A-Za-z0-9]+$')~=nil end

-- 1:1 Character Ensure
local function CharEnsure(uid, defaults)
  defaults = defaults or {}
  local fn = (defaults.firstname or ''):sub(1,30)
  local ln = (defaults.lastname  or ''):sub(1,30)

  for _=1,20 do
    local ok, err = ax:DbTx(function(sql)
      local row = sql.single('SELECT cid FROM ax_characters WHERE uid=? LIMIT 1',{uid})
      if row and row.cid then return true end
      local cid = genId(10); if not validId(cid) then error('invalid_cid') end
      local ex = sql.scalar('SELECT 1 FROM ax_characters WHERE cid=? LIMIT 1',{cid}); if ex then error('cid_collision') end
      sql.exec('INSERT INTO ax_characters (cid, uid, firstname, lastname) VALUES (?,?,?,?)',{cid,uid,(#fn>0) and fn or nil,(#ln>0) and ln or nil})
      return true
    end)
    if ok then local r=ax:DbSingle('SELECT cid FROM ax_characters WHERE uid=? LIMIT 1',{uid}); return r and r.cid or nil
    else local s=tostring(err or ''); if not (s:find('cid_collision') or s:find('invalid_cid')) then Axiom.log.warn('CharEnsure Tx-Fehler: %s',s); break end end
  end
  Axiom.log.warn('CharEnsure: cid konnte nicht zugewiesen werden (uid=%s)', tostring(uid))
  return nil
end

local function CharGetByUid(uid) return ax:DbSingle('SELECT * FROM ax_characters WHERE uid=? LIMIT 1',{uid}) end
local function CharGet(cid)      return ax:DbSingle('SELECT * FROM ax_characters WHERE cid=? LIMIT 1',{cid}) end

-- Meta (Key/Value Tabellen)
local function CharGetMeta(cid) local rows=ax:DbQuery('SELECT k,v FROM ax_character_meta WHERE cid=?',{cid}) or {}; local t={}; for _,r in ipairs(rows) do t[r.k]=r.v end; return t end
local function CharSetMetaKV(cid,k,v) if v==nil or v=='' then ax:DbExec('DELETE FROM ax_character_meta WHERE cid=? AND k=?',{cid,k}) else ax:DbExec([[INSERT INTO ax_character_meta (cid,k,v) VALUES (?,?,?) ON DUPLICATE KEY UPDATE v=VALUES(v)]],{cid,k,tostring(v)}) end end
local function CharDelMetaKV(cid,k) ax:DbExec('DELETE FROM ax_character_meta WHERE cid=? AND k=?',{cid,k}) end
local function CharSetMeta(cid,meta) if type(meta)~='table' then return end for k,v in pairs(meta) do CharSetMetaKV(cid,k,v) end end

exports('CharEnsure',   CharEnsure)
exports('CharGetByUid', CharGetByUid)
exports('CharGet',      CharGet)
exports('CharGetMeta',  CharGetMeta)
exports('CharSetMetaKV',CharSetMetaKV)
exports('CharDelMetaKV',CharDelMetaKV)
exports('CharSetMeta',  CharSetMeta)
