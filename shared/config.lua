Axiom = Axiom or {}

Axiom.config = {
  log_level     = 'info',
  heartbeat_ms  = 60000,

  -- Identifier-Reihenfolge (welcher gespeichert wird)
  identifiers = {
    preferred = { 'license', 'steam', 'rockstar', 'fivem', 'discord', 'xbl', 'live', 'ip' },
    store_kind = true,
  },

  -- Maintenance: Admin-Rolle darf rein, plus optional Allowlist
  maintenance = {
    enabled    = false,
    message    = 'Wartungsmodus: Bitte später erneut versuchen.',
    allow_uids = {},
  },

  -- Rate-Limiter
  rate_limit = {
    capacity   = 5,
    refill_ms  = 10000,
    overrides  = {
      -- ['rpc:eco:transfer'] = { capacity = 2, refill_ms = 15000 },
    },
  },

  health = { errors_last_n = 5, top_rpc_n = 5 },

  roles = {
    allow = { 'admin', 'dev', 'staff' },
  },
}

return Axiom.config
