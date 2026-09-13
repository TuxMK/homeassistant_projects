# Recorder-Migration SQLite → MariaDB

Überträgt die Daten des Home-Assistant-Recorders aus `home-assistant_v2.db` in eine
MariaDB-Datenbank, ohne dass Verlauf, Logbuch oder Langzeitstatistik verloren gehen.
Eine offizielle Migration gibt es nicht. Das Script schließt diese Lücke, **ohne Home
Assistant stoppen zu müssen**.

| Datei | Zweck |
|-------|-------|
| [`recorder_sqlite_to_mariadb.py`](recorder_sqlite_to_mariadb.py) | Kopiert die Recorder-Tabellen: Voll-Lauf, Delta-Lauf, Trockenlauf |
| [`run_migration.sh`](run_migration.sh) | Wrapper für das SSH-Add-on: Einstellungen oben im Script, ein Befehl je Schritt |

## Kurzfassung mit dem Wrapper

Beide Dateien in denselben Ordner legen, z. B. `/share/scripts/`. Den Konfigurationsblock
oben in `run_migration.sh` anpassen: Pfad, Host, Benutzer, Datenbank. Das Passwort
liest der Wrapper aus `secrets.yaml` (`SECRET_KEY`). Fehlt es dort, fragt er danach.

| Befehl | Schritt |
|--------|---------|
| `bash run_migration.sh check` | Trockenlauf (Schritt 2) |
| `bash run_migration.sh full` | Voll-Lauf im Hintergrund, übersteht ein geschlossenes Terminal (Schritt 3) |
| `bash run_migration.sh status` | Läuft noch etwas? Die letzten Zeilen des neuesten Logs |
| `bash run_migration.sh log` | Neuestes Log live verfolgen. Strg+C beendet nur das Mitlesen |
| `bash run_migration.sh delta` | Fragt vorab nach dem Neustart, führt dann `ha core check` aus, danach den Delta-Lauf und direkt `ha core restart` (Schritt 4) |

Zusätzliche Optionen reicht der Wrapper an das Python-Script durch, z. B.
`bash run_migration.sh full --only-statistics`. Die Logs landen in
`/share/recorder_migration/`, der Exit-Code steht jeweils in der letzten Zeile. Fehlen
Python oder PyMySQL, installiert der Wrapper sie per `apk` in den Add-on-Container.

`delta` prüft vorher, ob `db_url` in der `configuration.yaml` aktiv ist. Frage und
Konfigurationsprüfung liegen **vor** dem Delta-Lauf, denn der SQLite-Stand wird beim
Start des Deltas festgehalten. Alles, was bis zum Neustart noch passiert, verlängert die
Lücke. Neu gestartet wird nur, wenn die Prüfung bestanden und das Delta fehlerfrei war.
Wer zwei Deltas fährt, antwortet beim ersten mit `n` und beim zweiten mit `y`.

Die folgenden Abschnitte beschreiben dieselben Schritte mit dem Python-Script direkt.

## Features

- **Schema von Home Assistant, Daten aus SQLite:** Das Script legt keine Tabellen an.
  Spaltentypen, Indizes und Collation (`utf8mb4_bin`) bleiben so, wie der Recorder sie
  für MariaDB definiert.
- **Im laufenden Betrieb:** Die SQLite-Datei wird in einer einzigen Lesetransaktion
  gelesen. Home Assistant betreibt SQLite im WAL-Modus, deshalb sieht diese Transaktion
  einen konsistenten Stand, während der Recorder weiterschreibt.
- **Delta-Lauf vor dem Neustart:** Holt nach, was seit dem Voll-Lauf in SQLite
  hinzugekommen ist. Die Lücke bei der Umstellung schrumpft so auf wenige Sekunden.
- **Nur Statistik** (`--only-statistics`): Übernimmt nur die Langzeitstatistik
  (Energie-Dashboard). Der Verlauf beginnt dann neu.
- **Prüfungen vor dem ersten Schreiben:** Schema-Version gleich, Tabellen vorhanden,
  Ziel leer. Beim Delta außerdem: Home Assistant schreibt noch nicht in MariaDB.
- **Abgleich am Ende:** Zeilenzahl je Tabelle im SQLite-Stand gegen MariaDB.

## Voraussetzungen

- MariaDB ab 10.3, besser ab **10.5.17 bzw. 10.6.9**. Ältere Versionen haben einen
  Performance-Fehler mit dem Recorder-Schema.
- Eine eigene, leere Datenbank samt Benutzer, **nicht** `ha_metrics`. Beim
  MariaDB-Add-on:
  ```yaml
  databases:
    - homeassistant
  logins:
    - username: homeassistant
      password: "…"
  rights:
    - username: homeassistant
      database: homeassistant
  ```
- Python 3 mit PyMySQL, und zwar dort, wo sowohl die SQLite-Datei als auch MariaDB
  erreichbar sind. Am einfachsten im SSH-Add-on auf dem HA-Host:
  ```bash
  apk add python3 py3-pymysql
  ```
  Beim Add-on „Advanced SSH & Web Terminal" lassen sich beide Pakete dauerhaft unter
  `packages` eintragen. Am PC reicht `pip install pymysql`.

## Ablauf

### 1. Schema von Home Assistant anlegen lassen

In `secrets.yaml`:

```yaml
recorder_db_url: mysql://homeassistant:PASSWORT@core-mariadb/homeassistant?charset=utf8mb4
```

In `configuration.yaml`:

```yaml
recorder:
  db_url: !secret recorder_db_url
```

Home Assistant **neu starten** und warten, bis die Tabellen da sind:

```sql
SELECT schema_version FROM schema_changes;
```

Danach `db_url` wieder auskommentieren und **erneut neu starten**. Home Assistant
schreibt jetzt wieder in SQLite.

> **Ab hier kein Home-Assistant-Update bis zur Umstellung.** Die Schema-Version in
> MariaDB muss zur SQLite-Datei passen, sonst bricht das Script ab.

Die Zeilen, die Home Assistant beim Kurzstart in MariaDB geschrieben hat, räumt
`--truncate` im nächsten Schritt weg.

### 2. Trockenlauf

```bash
export MARIADB_PASSWORD='…'
python3 recorder_sqlite_to_mariadb.py \
  --sqlite /homeassistant/home-assistant_v2.db \
  --host core-mariadb --user homeassistant --database homeassistant \
  --truncate --dry-run
```

Das Script führt alle Prüfungen aus und zählt die Zeilen je Tabelle, schreibt aber
nichts. Der Pfad zur Datei hängt vom SSH-Add-on ab und lautet `/homeassistant/…` oder
`/config/…`.

### 3. Voll-Lauf – Home Assistant läuft weiter

```bash
python3 recorder_sqlite_to_mariadb.py \
  --sqlite /homeassistant/home-assistant_v2.db \
  --host core-mariadb --user homeassistant --database homeassistant \
  --truncate
```

Alle fünf Sekunden meldet das Script Fortschritt, Rate und Restzeit. Am Ende vergleicht
es die Zeilenzahlen. Steht bei jeder Tabelle `ok`, ist die Kopie vollständig, und zwar
auf dem Stand, zu dem der Lauf begonnen hat.

Der Voll-Lauf lässt sich beliebig oft wiederholen. `--truncate` fängt jedes Mal von
vorn an.

### 4. Umstellung: Delta und sofort neu starten

1. `db_url` in `configuration.yaml` wieder aktivieren, **noch nicht** neu starten.
2. Delta-Lauf:
   ```bash
   python3 recorder_sqlite_to_mariadb.py \
     --sqlite /homeassistant/home-assistant_v2.db \
     --host core-mariadb --user homeassistant --database homeassistant \
     --mode delta
   ```
3. **Direkt danach** Home Assistant neu starten.

Verloren geht nur, was Home Assistant zwischen dem Ende des Deltas und dem
Herunterfahren noch in SQLite schreibt, also einige Sekunden. Zähler wie Energie
verlieren dabei nichts: Die nächste Statistik rechnet ab dem letzten bekannten Stand
weiter.

### 5. Prüfen

- **Einstellungen > System > Protokolle**, nach `recorder` filtern: keine Fehler, keine
  Migration.
- Verlauf einer Entität über den Umstellungszeitpunkt hinweg ansehen.
- Energie-Dashboard: Tage vor der Umstellung vorhanden.

### Zurück zu SQLite

`db_url` entfernen und neu starten. Die SQLite-Datei enthält alles bis zur Umstellung.
Was Home Assistant danach in MariaDB geschrieben hat, bleibt nur dort.

## Optionen

| Option | Standard | Wirkung |
|--------|----------|---------|
| `--sqlite` | – | Pfad zur `home-assistant_v2.db`: Live-Datei oder Kopie |
| `--host`, `--port` | `core-mariadb`, `3306` | MariaDB-Server |
| `--user` | – | MariaDB-Benutzer. Das Passwort kommt aus `MARIADB_PASSWORD` oder wird abgefragt |
| `--database` | `homeassistant` | Zieldatenbank |
| `--mode` | `full` | `full` kopiert alles, `delta` holt Neues seit dem Voll-Lauf nach |
| `--truncate` | aus | Nur `full`: leert vorher alle Tabellen außer `schema_changes` |
| `--only-statistics` | aus | Nur `statistics_meta`, `statistics`, `statistics_short_term`, `statistics_runs`, `migration_changes` |
| `--dry-run` | aus | Prüfungen und Zeilenzahlen, keine Schreibzugriffe |
| `--batch` | `5000` | Zeilen je `INSERT` |

Exit-Code `0` = fertig und Zeilenzahlen stimmen. `1` = Abbruch. `2` = fertig, aber
mindestens eine Tabelle mit `MISMATCH`.

## Was das Script mit den Daten macht

Tabellen und Spalten sind in SQLite und MariaDB gleich, nur die Typen unterscheiden sich
(`FLOAT`→`DOUBLE`, `TEXT`→`LONGTEXT`, `INTEGER`→`BIGINT`). Die Werte passen ohne
Umrechnung, auch die Zeitstempel: Das sind Unix-Sekunden als Float. Das Script kopiert
Spalte für Spalte nach Namen und behandelt nur die Stellen, an denen SQLite nachsichtiger
ist als MariaDB:

| Fall | Behandlung |
|------|------------|
| Alte, ungenutzte Spalten (`CHAR(0)` in MariaDB, `states.event_id`) | Bleiben `NULL`. In alten Datenbanken können sie noch Inhalte haben, die MariaDB ablehnen würde |
| Text länger als die Spalte (`VARCHAR(255)`) | Wird gekürzt und am Ende gezählt. SQLite erzwingt keine Längen |
| `DATETIME`-Spalten (`recorder_runs`, `statistics_runs`) | Werden auf `YYYY-MM-DD HH:MM:SS.ffffff` gebracht, ohne `T` und ohne Zonenangabe |
| Kaputtes UTF-8 in alten Attributen | Wird ersetzt statt den Lauf abzubrechen |
| `schema_changes` | Wird nie angefasst, das Ziel behält die Einträge von Home Assistant |
| Tabellen außerhalb des Recorder-Schemas | Werden gemeldet, aber nicht kopiert |

Fremdschlüssel-Prüfungen sind während des Imports für die eigene Sitzung abgeschaltet.
Die Zeilen kommen Tabelle für Tabelle, die Verweise sind erst am Ende vollständig.

### Was der Delta-Lauf übernimmt

| Tabellen | Verfahren |
|----------|-----------|
| `events`, `event_data`, `states`, `state_attributes`, `statistics`, `statistics_short_term`, `statistics_runs` | Neue Zeilen: Primärschlüssel größer als das Maximum in MariaDB |
| `states` zusätzlich | `last_reported_ts` bestehender Zeilen. Home Assistant schiebt diesen Wert beim neuesten Zustand einer Entität weiter, statt eine neue Zeile zu schreiben |
| `event_types`, `states_meta`, `statistics_meta`, `recorder_runs`, `migration_changes` | Vollständig als Upsert. Home Assistant ändert hier Zeilen direkt, z. B. bei umbenannten Entitäten, geänderten Einheiten oder dem Ende eines Laufs |

**Nicht übernommen** werden Löschungen und Änderungen an bestehenden Statistikzeilen.
Deshalb zwischen Voll-Lauf und Umstellung **keine** Statistiken löschen, korrigieren oder
importieren (Entwicklerwerkzeuge > Statistik). Dass der nächtliche Purge in SQLite
alte Zeilen löscht, ist harmlos: Home Assistant entfernt sie später auch aus MariaDB.

Der Delta-Lauf lässt sich wiederholen. Er bricht aber ab, sobald Home Assistant selbst
in MariaDB schreibt, denn dann vergäben SQLite und MariaDB dieselben IDs an
unterschiedliche Zeilen. Das Script erkennt das am neuesten Eintrag in
`statistics_runs`.

## Hinweise

- **Nicht über eine Netzwerkfreigabe:** Auf die Live-Datei nur lokal auf dem HA-Host
  zugreifen. WAL-Sperren funktionieren über Samba/SMB nicht zuverlässig. Wer am PC
  arbeiten will, nimmt eine Kopie, etwa die `home-assistant_v2.db` aus einem
  HA-Backup. Das Delta läuft dann gegen eine frische Kopie, und die Lücke reicht vom
  Zeitpunkt dieser Kopie bis zum Neustart.
- **Purge und Repack stören nicht:** Löscht oder komprimiert der Recorder während des
  Laufs, sieht das Script trotzdem den Stand vom Start. Die Lesetransaktion hält
  diesen Stand fest.
- **Die WAL-Datei wächst** während eines langen Laufs, weil SQLite nicht über den
  gelesenen Stand hinaus checkpointen kann. Etwas Platz auf dem Datenträger einplanen.
- **Dauer:** Der Großteil steckt in `states`. Wie lange es dauert, zeigt der
  Fortschritt des Voll-Laufs. Auf einem Raspberry Pi läuft Home Assistant währenddessen
  spürbar langsamer.
- **Warum kein CSV/JSON-Export** (etwa über SQLite Web): CSV kennt kein `NULL`. Bei
  Zählern sind `mean`/`min`/`max` in `statistics` aber `NULL`, und aus CSV kämen sie als
  `0` oder Leerstring zurück. Außerdem gehen BLOB-Spalten (`context_id_bin`) nicht sauber
  hinein, und nacheinander exportierte Tabellen passen nicht zusammen, während Home
  Assistant weiterschreibt.

## Lizenz

MIT License
