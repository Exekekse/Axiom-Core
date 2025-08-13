fx_version 'cerulean'
game 'rdr3'
lua54 'yes'

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'AxCore'
author 'Louis & Svipe'
version '0.4.0'
description 'Axiom Core – Identity, 1:1 Character, Roles/Meta(KV), RPC, DB, Migrations, Metrics'

shared_scripts {
  'shared/contracts.lua',
  'shared/config.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',

  'server/logger.lua',
  'server/registry.lua',
  'server/ratelimit.lua',
  'server/errors.lua',
  'server/rpc.lua',

  'server/db.lua',
  'server/migrations.lua',
  'server/migrations_core.lua',

  'server/validator.lua',      -- neu (Payload-Validator)
  'server/players_svc.lua',
  'server/characters_svc.lua',

  'server/main.lua'
}

client_scripts {
  'client/rpc.lua',
  'client/main.lua'
}
