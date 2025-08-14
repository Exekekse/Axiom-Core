local RES = GetCurrentResourceName()
local ax  = exports[RES]
local RegisterMigration = function(...) return ax:RegisterMigration(...) end
local DbScalar = function(q,p) return ax:DbScalar(q,p) end
local DbExec   = function(q,p) return ax:DbExec(q,p) end
local DbTx     = function(fn) return ax:DbTx(fn) end

-- 0001: Spieler (kein JSON-Feld)
RegisterMigration('axiom-core', '0001_players', [[
  CREATE TABLE IF NOT EXISTS ax_players (
    uid         VARCHAR(10) COLLATE utf8mb4_bin NOT NULL,
    id_kind     VARCHAR(16)  NOT NULL,
    id_value    VARCHAR(64)  NOT NULL,
    name        VARCHAR(64)  NULL,
    first_seen  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (uid),
    UNIQUE KEY uq_ident (id_kind, id_value),
    KEY ix_players_last_seen (last_seen),
    KEY ix_players_name (name)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]])

-- 0010: Charakter (genau 1 pro uid)
RegisterMigration('axiom-core', '0010_characters', [[
  CREATE TABLE IF NOT EXISTS ax_characters (
    cid         VARCHAR(10) COLLATE utf8mb4_bin NOT NULL,
    uid         VARCHAR(10) COLLATE utf8mb4_bin NOT NULL,
    firstname   VARCHAR(30) NULL,
    lastname    VARCHAR(30) NULL,
    gender      TINYINT NULL,
    dob         DATE NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (cid),
    UNIQUE KEY uq_char_uid (uid),
    KEY ix_char_uid (uid)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]])

-- 0011: Rollen je Spieler
RegisterMigration('axiom-core', '0011_perm_roles', [[
  CREATE TABLE IF NOT EXISTS ax_perm_roles (
    uid   VARCHAR(10) COLLATE utf8mb4_bin NOT NULL,
    role  VARCHAR(32) NOT NULL,
    PRIMARY KEY (uid, role),
    KEY ix_role (role)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]])

-- 0012: Player-Meta (Key/Value)
RegisterMigration('axiom-core', '0012_player_meta', [[
  CREATE TABLE IF NOT EXISTS ax_player_meta (
    uid VARCHAR(10) COLLATE utf8mb4_bin NOT NULL,
    k   VARCHAR(48) NOT NULL,
    v   TEXT NULL,
    PRIMARY KEY (uid, k),
    KEY ix_meta_k (k)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]])

-- 0013: Character-Meta (Key/Value)
RegisterMigration('axiom-core', '0013_character_meta', [[
  CREATE TABLE IF NOT EXISTS ax_character_meta (
    cid VARCHAR(10) COLLATE utf8mb4_bin NOT NULL,
    k   VARCHAR(48) NOT NULL,
    v   TEXT NULL,
    PRIMARY KEY (cid, k),
    KEY ix_cmeta_k (k)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]])

-- 0014: Indexpflege
RegisterMigration('axiom-core', '0014_indexes', function(ctx)
  local log = Axiom.log or { info=print }
  local indexes = {
    { table='ax_perm_roles',    index='ix_uid', column='uid'  },
    { table='ax_perm_roles',    index='ix_role', column='role' },
    { table='ax_player_meta',   index='ix_uid', column='uid'  },
    { table='ax_character_meta',index='ix_cid', column='cid'  },
  }
  ctx.tx(function(tx)
    for _, ix in ipairs(indexes) do
      local exists = tx.scalar(
        [[SELECT COUNT(1) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ?]],
        {ix.table, ix.index}
      ) or 0
      if exists == 0 then
        tx.exec(('ALTER TABLE %s ADD INDEX %s (%s)'):format(ix.table, ix.index, ix.column))
        log.info('Migration 0014: created index %s on %s(%s)', ix.index, ix.table, ix.column)
      else
        log.info('Migration 0014: index %s already present', ix.index)
      end
    end
  end)
end)
