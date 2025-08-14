Axiom = Axiom or {}

Axiom.config = {
  log_level     = 'info',
  heartbeat_ms  = 60000,

  -- Identifier-Policy
  identifiers = {
    -- Primärer Identifier (Quelle der Wahrheit)
    primary   = 'license',
    -- Sekundäre Identifier in deterministischer Reihenfolge
    secondary = { 'steam', 'rockstar', 'fivem', 'discord', 'xbl', 'live', 'ip' },
    store_kind = true,
    auto_link = {
      enabled = true,   -- zusätzliche Identifier beim Connect sammeln
      shadow  = true,   -- nur loggen, nicht automatisch verknüpfen
      types   = {},     -- opt-in je Identifier-Typ (z.B. {steam=true})
    },
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

  db = { slow_ms = 100 },

  cache = { ttl_sec = 60 },

  health = { errors_last_n = 5, top_rpc_n = 5 },

  roles = {
    allow = { 'admin', 'dev', 'staff' },
  },
}

return Axiom.config
