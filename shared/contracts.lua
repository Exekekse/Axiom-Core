Axiom = rawget(_G, 'Axiom') or {}
Axiom.name    = 'axiom-core'
Axiom.version = '0.5.0'

Axiom.ev = {
  ModuleReady     = 'Axiom:core:moduleReady',
  ModuleStop      = 'Axiom:core:moduleStop',
  RpcReq          = 'Axiom:core:rpc:req',
  RpcRes          = 'Axiom:core:rpc:res',
  CharacterReady  = 'Axiom:character:ready',   -- (cid, uid)
}

Axiom.ex = {
  -- Registry/Event-Bus
  RegisterModule   = 'RegisterModule',
  GetModule        = 'GetModule',
  ListModules      = 'ListModules',
  On               = 'On',
  Once             = 'Once',
  Off              = 'Off',
  Emit             = 'Emit', -- optional, falls dein Registry das anbietet

  -- Logger / Audit
  Log              = 'Log',
  SetLogLevel      = 'SetLogLevel',
  Audit            = 'Audit',

  -- RPC / RateLimit / Errors
  RpcRegister      = 'RpcRegister',
  RpcMetrics       = 'RpcMetrics',
  RateLimit        = 'RateLimit',
  ErrOk            = 'ErrOk',
  ErrFail          = 'ErrFail',

  -- DB & Migration
  DbScalar         = 'DbScalar',
  DbSingle         = 'DbSingle',
  DbQuery          = 'DbQuery',
  DbExec           = 'DbExec',
  DbTx             = 'DbTx',
  DbHealth         = 'DbHealth',
  RegisterMigration= 'RegisterMigration',
  RunMigrations    = 'RunMigrations',

  -- Players Service (Identity, Roles, Meta KV)
  GetUid           = 'GetUid',
  GetSrc           = 'GetSrc',
  ForEachPlayer    = 'ForEachPlayer',
  Count            = 'Count',
  GetIdent         = 'GetIdent',
  HasRole          = 'HasRole',
  AddRole          = 'AddRole',
  RemoveRole       = 'RemoveRole',
  IsAdmin          = 'IsAdmin',
  RequireRole      = 'RequireRole',
  PlayerGetMeta    = 'PlayerGetMeta',
  PlayerSetMetaKV  = 'PlayerSetMetaKV',
  PlayerDelMetaKV  = 'PlayerDelMetaKV',

  -- Characters Service (1:1)
  CharEnsure       = 'CharEnsure',
  CharGetByUid     = 'CharGetByUid',
  CharGet          = 'CharGet',
  CharGetMeta      = 'CharGetMeta',
  CharSetMeta      = 'CharSetMeta',
  CharSetMetaKV    = 'CharSetMetaKV',
  CharDelMetaKV    = 'CharDelMetaKV',
}
