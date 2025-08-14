fx_version 'cerulean'
game 'rdr3'
lua54 'yes'

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'AxCore'
author 'Exe & Svipe'
version '0.4.0'
description 'Axiom Core – Identity, 1:1 Character, Roles/Meta(KV), RPC, DB, Migrations, Metrics'

shared_scripts {
  'shared/contracts.lua',
  'shared/config.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',

  'server/core/logger.lua',
  'server/core/registry.lua',
  'server/core/ratelimit.lua',
  'server/core/errors.lua',
  'server/core/rpc.lua',

  'server/core/db.lua',
  'server/core/migrations.lua',
  'server/core/migrations_core.lua',

  'server/core/validator.lua',      -- neu (Payload-Validator)
  'server/services/players_svc.lua',
  'server/services/characters_svc.lua',

  'server/main.lua'
}

client_scripts {
  'client/rpc.lua',
  'client/main.lua'
}

