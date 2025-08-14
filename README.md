# Axiom Core

Axiom Core ist das zentrale Skript des Axiom-Frameworks für RedM-Server. Es stellt grundlegende Funktionen für Serverressourcen bereit und sorgt damit für einen reibungslosen Einstieg in das Framework.

## Vorteile

- **Zentrale Spielerverwaltung**: Vergibt eindeutige UIDs, legt Charaktere automatisch an und aktualisiert den letzten Login.
- **Flexibles Logging**: Einstellbare Loglevel erlauben eine präzise Nachverfolgung von Ereignissen.
- **Datenbank-Migrationen**: Führt bei Bedarf automatisch SQL-Migrationen aus, um Datenstrukturen aktuell zu halten.
- **Wartungsmodus und Heartbeat**: Server können in den Wartungsmodus versetzt werden; ein automatischer Heartbeat überwacht den Zustand.
- **RPC und Ratelimits**: Integrierte RPC-Kommunikation zwischen Client und Server sowie Ratelimit-Mechanismen.

Dieses Repository enthält ausschließlich den Kern. Weitere Funktionen können auf Basis dieser Grundlage entwickelt werden.
