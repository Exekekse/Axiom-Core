# Axiom Core

Aktuelle Version: **0.5.0**

Axiom Core ist das zentrale Skript des Axiom-Frameworks für RedM-Server. Es stellt grundlegende Funktionen für Serverressourcen bereit und sorgt damit für einen reibungslosen Einstieg in das Framework.

## Vorteile

- **Zentrale Spielerverwaltung**: Vergibt eindeutige UIDs, legt Charaktere automatisch an und aktualisiert den letzten Login.
- **Flexibles Logging**: Einstellbare Loglevel erlauben eine präzise Nachverfolgung von Ereignissen.
- **Datenbank-Migrationen**: Führt bei Bedarf automatisch SQL-Migrationen aus, um Datenstrukturen aktuell zu halten.
- **Wartungsmodus und Heartbeat**: Server können in den Wartungsmodus versetzt werden; ein automatischer Heartbeat überwacht den Zustand.
- **RPC und Ratelimits**: Integrierte RPC-Kommunikation zwischen Client und Server sowie Ratelimit-Mechanismen.

## Stable Contracts

| Export/Event | Signatur | Beschreibung | Seit Version | Status |
|--------------|----------|--------------|--------------|--------|
| `DbScalar` | `DbScalar(sql, params)` | Einfacher Wert aus Datenbank | 0.5.0 | stable |
| `DbSingle` | `DbSingle(sql, params)` | Erste Zeile als Tabelle | 0.5.0 | stable |
| `DbQuery` | `DbQuery(sql, params)` | Ergebnisliste | 0.5.0 | stable |
| `DbExec` | `DbExec(sql, params)` | Änderungen ausführen | 0.5.0 | stable |
| `DbTx` | `DbTx(fn)` | Transaktion ausführen | 0.5.0 | stable |
| `DbHealth` | `DbHealth()` | DB-Verfügbarkeit prüfen | 0.5.0 | stable |
| `Log` | `Log(level, msg, ...)` | Logging mit Level | 0.5.0 | stable |
| `SetLogLevel` | `SetLogLevel(level)` | Loglevel ändern | 0.5.0 | stable |
| `Audit` | `Audit(action, target?, actor?, details?)` | Sicherheitslog | 0.5.0 | stable |
| `RpcRegister` | `RpcRegister(name, fn)` | RPC registrieren | 0.5.0 | stable |
| `RpcMetrics` | `RpcMetrics()` | RPC-Statistiken | 0.5.0 | stable |
| `RateLimit` | `RateLimit(key, src)` | Ratelimit prüfen | 0.5.0 | stable |
| `GetIdent` | `GetIdent(src)` | Bevorzugten Identifier lesen | 0.5.0 | stable |
| `GetUid` | `GetUid(src)` | UID eines Spielers | 0.5.0 | stable |
| `GetSrc` | `GetSrc(uid)` | Quelle zu UID | 0.5.0 | stable |
| `ForEachPlayer` | `ForEachPlayer(cb)` | Alle Spieler iterieren | 0.5.0 | stable |
| `Count` | `Count()` | Anzahl Spieler | 0.5.0 | stable |
| `HasRole` | `HasRole(uid, role)` | Rolle prüfen | 0.5.0 | stable |
| `AddRole` | `AddRole(uid, role)` | Rolle vergeben | 0.5.0 | stable |
| `RemoveRole` | `RemoveRole(uid, role)` | Rolle entziehen | 0.5.0 | stable |
| `IsAdmin` | `IsAdmin(uid)` | Prüft Admin-Rolle | 0.5.0 | stable |
| `RequireRole` | `RequireRole(uid, role)` | Guard für Rollen | 0.5.0 | stable |
| `PlayerGetMeta` | `PlayerGetMeta(uid)` | Meta-Daten lesen | 0.5.0 | stable |
| `PlayerSetMetaKV` | `PlayerSetMetaKV(uid, k, v)` | Meta setzen | 0.5.0 | stable |
| `PlayerDelMetaKV` | `PlayerDelMetaKV(uid, k)` | Meta löschen | 0.5.0 | stable |
| `CharEnsure` | `CharEnsure(uid, defaults?)` | Charakter sicherstellen | 0.5.0 | stable |
| `CharGetByUid` | `CharGetByUid(uid)` | Charakter zu UID | 0.5.0 | stable |
| `CharGet` | `CharGet(cid)` | Charakter laden | 0.5.0 | stable |
| `CharGetMeta` | `CharGetMeta(cid)` | Character-Meta lesen | 0.5.0 | stable |
| `CharSetMetaKV` | `CharSetMetaKV(cid, k, v)` | Character-Meta setzen | 0.5.0 | stable |
| `CharDelMetaKV` | `CharDelMetaKV(cid, k)` | Character-Meta löschen | 0.5.0 | stable |
| Event `Axiom:character:ready` | `(cid, uid)` | Charakter bereit | 0.5.0 | stable |
| Event `Axiom:core:moduleReady` | `(mod)` | Modul bereit | 0.5.0 | stable |

## Deprecation Policy

Breaking Changes erfolgen nur in Minor- oder Major-Releases. Veraltete Exports werden markiert und erst nach mehreren Releases entfernt.

## Permissions-Helper

- `IsAdmin(uid)` – dünner Wrapper um `HasRole(uid, 'admin')`.
- `RequireRole(uid, role)` – gibt `{ok=true}` oder `{ok=false, code='E_FORBIDDEN'}` zurück.

## Audit & Logging

Sicherheitsrelevante Aktionen werden mit dem Tag `[SECURITY]` geloggt. Audit-Einträge enthalten Aktion, Ziel-UID, optional Actor (Konsole/RCON-IP) sowie Zeitstempel. Das Loglevel wird über `Axiom.config.log_level` gesteuert (`trace|debug|info|warn|error`).

## Indizes

Die Tabellen `ax_perm_roles`, `ax_player_meta` und `ax_character_meta` besitzen zusätzliche Indizes für `uid` bzw. `cid`. Diese verbessern Lookups und Joins bei Rollen- und Meta-Abfragen erheblich.

## Lifecycle Hooks

Beim Start der Resource werden interne Caches geleert und für bereits verbundene Spieler Charaktere gesichert und das Event `Axiom:character:ready` erneut ausgelöst. Beim Stoppen werden Threads beendet, Rate-Limit-Buckets und Caches geleert.

