# Migration InfluxDB 1.x -> MariaDB-Archiv

Zwei Skripte, die den Verlauf der InfluxDB-Integration in die Archivtabelle des
Blueprints [Metrics Archive (MariaDB)](../) übertragen. Sie kommen mit dem aus, was auf den
Maschinen ohnehin vorhanden ist — `docker` für den Export, `awk` und der `mysql`-Client für
den Import. Kein Python, kein `influxdb`-Paket, kein Datenbanktreiber.

| Skript | Zweck |
|--------|-------|
| [`influx_export_monthly.sh`](influx_export_monthly.sh) | Exportiert alles unverändert als Line Protocol, eine Datei pro Monat |
| [`influx_import_mysql.sh`](influx_import_mysql.sh) | Wandelt die Dumps um und leitet sie direkt in MariaDB, ohne Zwischendateien |

`influx_export_monthly.sh` läuft auf dem Home-Assistant-Host (SSH-Add-on), weil es den
Container braucht; `influx_import_mysql.sh` läuft dort, wo die Dump-Dateien landen,
solange die Datenbank von dort aus erreichbar ist.

## Wie die Schemata zueinander passen

Home Assistant schreibt in InfluxDB in einer Form, die nicht eins zu eins zur Archivtabelle
passt. Zwei Details sind wichtig:

- Der Tag `entity_id` enthält **nur die Object-ID**, ohne Domain. Die vollständige
  Entity-ID ist `domain + '.' + entity_id`, und der Import setzt sie aus beiden Tags zusammen.
- Der Measurement-Name **ist** die `unit_of_measurement`. Hat ein Zustand keine Einheit,
  verwendet Home Assistant ersatzweise die vollständige Entity-ID als Measurement-Namen.
  Ein solcher Name enthält einen Punkt — der Import erkennt das und lässt `unit` leer.

| InfluxDB | Archivtabelle |
|----------|---------------|
| Tag `domain` + Tag `entity_id` | `entity_id` |
| `time` (UTC) | `ts` (`DATETIME(3)`, UTC) |
| Feld `value` | `value` |
| Feld `state` | `state` |
| Measurement-Name | `unit` (leer, wenn er einen Punkt enthält) |
| — | `source` = `import` |

`source = 'import'` ist genau das, wofür die Spalte gedacht ist: Zeilen aus der Migration
bleiben unterscheidbar von denen, die die laufende Automation schreibt (`ha`), und von
manuellen Korrekturen (`manual`).

## 1. Das Schreiben stoppen, nicht das Add-on

**Einstellungen > Geräte & Dienste > InfluxDB > Deaktivieren.** Damit hört Home Assistant
auf zu schreiben, während der Export läuft, und der Container läuft weiter — was er auch
muss, denn alles Weitere geht über `docker exec`. Das Add-on zu stoppen würde den
Container mitnehmen.

## 2. Den Dump schreiben

[`influx_export_monthly.sh`](influx_export_monthly.sh) erledigt das Monat für Monat. Passe
den Block oben an — `CONTAINER`, `DB`, `START`, `END` — und führe es auf dem HA-Host aus:

```bash
zsh influx_export_monthly.sh
```

Es findet die Datenverzeichnisse im Container selbst, exportiert eine Datei pro Monat
nach `influx_export/`, überspringt Monate ohne Daten und meldet die Anzahl der Punkte pro
Datei — aufgeteilt nach TSM und WAL. `DRYRUN=1` gibt die Befehle aus, statt sie auszuführen.

**Zwei Fallen, gegen die es sich absichert.** Enthält das Datenverzeichnis keine
`.tsm`-Dateien, würde der Export stillschweigend Dateien erzeugen, die plausibel aussehen,
aber nur das Write-Ahead-Log enthalten; das Skript zählt sie vorab und bricht ab. Und
`influx_inspect` wendet `-start`/`-end` nicht in jeder Version auf das WAL an, sodass dessen
Zeilen — die jüngsten Schreibvorgänge — in *jeder* Monatsdatei landen würden, auch in
Monaten von vor Jahren. Das WAL gehört zum neuesten Monat, deshalb wird nur dieser mit dem
echten `waldir` exportiert.

Eine Datei mit der Meldung `!! WAL only, no stored data` bedeutet, dass für diesen Zeitraum
nichts Gespeichertes gefunden wurde — entweder enthält der Monat tatsächlich keine Daten,
oder `DATADIR` zeigt an die falsche Stelle. Steht das bei *jedem* Monat, finde die Shards mit
`docker exec <container> find / -name '*.tsm' 2>/dev/null | head` und setze `DATADIR` und
`WALDIR` oben im Skript von Hand.

Unter der Haube ist das `influx_inspect export` mit `-start`/`-end` pro Monat. Von Hand, für
einen Zeitraum, sieht das so aus:

```bash
docker exec addon_a0d7b954_influxdb \
  influx_inspect export \
    -datadir /data/influxdb/data \
    -waldir  /data/influxdb/wal \
    -database homeassistant \
    -start 2025-11-01T00:00:00Z -end 2025-11-30T23:59:59.999999999Z \
    -out /share/influx_export.lp \
    -compress
```

Sollten diese Pfade nicht existieren, nennt `find /data -name '*.tsm' | head` die echten — das
Add-on legt seine Daten unter `/data` ab, aber die Struktur hat sich zwischen Versionen geändert.

**Warum nicht `influx -format csv`:** Für ein einzelnes, bekanntes Measurement funktioniert
es gut, die Spalten von Hand auszuwählen. Über alle Measurements hinweg nicht: CSV kennt keine
Typen, sodass sich `42i` (Integer) auf dem Rückweg nicht mehr von `42` (Float) oder einem
String unterscheiden lässt, und ein `friendly_name` mit Komma verschiebt die Spalten.
`influx_inspect` schreibt natives Line Protocol direkt aus den TSM-Dateien — Typen, Escaping
und alle Felder bleiben erhalten.

## 3. Import in MariaDB

[`influx_import_mysql.sh`](influx_import_mysql.sh) liest die `.lp`-Dateien, wandelt sie um
und leitet die Statements in den `mysql`-Client — ohne `.sql`-Dateien dazwischen. Alles
außer den Zugangsdaten steht im Konfigurationsblock oben:

```bash
./influx_import_mysql.sh <db-user> <db-password>
DRYRUN=1 ./influx_import_mysql.sh <db-user> <db-password>   # print the SQL instead
```

Es prüft Verbindung und Tabelle, bevor es irgendetwas schreibt, meldet die Zeilen pro Datei
und bricht bei der ersten fehlerhaften Datei ab, statt weiterzumachen. `.gz`-Dateien werden
im Durchlauf entpackt, und der DDL-Header, den `influx_inspect` einem Dump voranstellt, wird
übersprungen.

Es braucht den `mysql`-Client: `sudo apt install mariadb-client`. Unter MariaDB 11 wird der
Befehl `mariadb` verwendet, den das Skript selbst auswählt — der alte Name funktioniert noch,
warnt aber bei jedem Aufruf, was die Fortschrittsausgabe untergehen ließe.

### Der Konfigurationsblock

| Einstellung | Wirkung |
|-------------|---------|
| `LPDIR` | Verzeichnis mit den `.lp`- / `.lp.gz`-Dateien |
| `HOST`, `PORT`, `DB`, `TABLE` | Wohin die Zeilen gehen |
| `UNTIL` | Stichtag (UTC): nichts ab diesem Zeitpunkt. Leer = alles importieren |
| `MIN_INTERVAL` | Sekunden zwischen zwei Zeilen pro Entity, `0` = jeder Punkt |
| `DOMAINS` | Leerzeichengetrennt, z. B. `"sensor"` — leer = alle Domains, einschließlich `light`, `binary_sensor` und der übrigen |
| `NUMERIC_ONLY` | `1` überspringt Punkte ohne numerischen Wert — Schaltzustände und Text-Sensoren bleiben außen vor |
| `SOURCE` | Wert für die Spalte `source`, standardmäßig `import` |
| `PRECISION` | Zeitstempel-Genauigkeit im Dump, falls es nicht Nanosekunden sind |
| `BATCH` | Zeilen pro `INSERT`-Statement |

**Zu `MIN_INTERVAL`:** Das Ausdünnen passiert beim Umwandeln, nicht in InfluxDB. Ein
`GROUP BY time(60s)` würde jeden Wert auf die Bucket-Grenze setzen; so bleibt der echte
Zeitstempel jedes Punkts erhalten, genau wie die Automation es im Normalbetrieb macht.
Das setzt voraus, dass die Punkte einer Entity in Reihenfolge ankommen, was der Dump liefert.
Eingaben außer der Reihe behalten immer nur mehr Zeilen, nie weniger.

### Der Stichtag

`UNTIL` beendet den Import zu einem bestimmten Zeitpunkt, sodass er genau dort aufhört, wo
die Archiv-Automation übernommen hat, und sich beide nicht überschneiden:

```bash
UNTIL="2026-09-11 14:05:58.529"   # nothing from this moment on
```

Der richtige Wert ist die erste Zeile, die die Automation selbst geschrieben hat:

```sql
SELECT MIN(ts) FROM states WHERE source = 'ha';
```

Nimm ihn aus **dieser Abfrage**, nicht aus der Home-Assistant-Oberfläche — die Spalte ist in
UTC, die Oberfläche zeigt Ortszeit, und im Sommer liegen die beiden zwei Stunden auseinander.
Ein vom Bildschirm abgelesener Stichtag würde zwei Stunden zu spät schneiden und den Import
über ein Zeitfenster schreiben lassen, das die Automation bereits abdeckt.

`UNTIL` kann als `YYYY-MM-DD`, `YYYY-MM-DD HH:MM:SS` oder mit Millisekunden angegeben werden;
eine Kurzform wird bis zum Ende des genannten Zeitraums aufgefüllt, ein reines Datum steht
also für den ganzen Tag. Der genannte Zeitpunkt selbst wird noch importiert. Leer lassen, um
alles zu importieren.

Eine Datei, die über den Stichtag hinausreicht, meldet das: `3 rows (…, after cut-off 2)`. Das
Passwort landet in einer temporären Datei mit Modus 600 statt auf der Kommandozeile, wo `ps`
es jedem auf der Maschine zeigen würde.

Die Statements sind `INSERT IGNORE`. Zeilen, die schon in der Tabelle stehen — von der
Automation geschrieben oder von Hand korrigiert —, bleiben unberührt; ergänzt wird nur
tatsächlich fehlender Verlauf. Eine Datei lässt sich daher zweimal importieren, ohne
Schaden anzurichten.

## Vor dem Import in eine partitionierte Tabelle

Ist die Zieltabelle bereits nach Monaten partitioniert, bestimmt ihre **älteste** Partition,
wie weit eine Zeile zurückreichen darf. Ein Import aus 2023 in eine Tabelle, deren erste
Partition 2026 beginnt, scheitert mit `Table has no partition for value`.

Partitionen für die Vergangenheit lassen sich nicht über `pmax` anlegen — die deckt nur die
Zukunft ab. Stattdessen muss die erste Partition aufgeteilt werden:

```sql
ALTER TABLE states REORGANIZE PARTITION p2026_01 INTO (
  PARTITION p2023 VALUES LESS THAN (TO_DAYS('2024-01-01')),
  PARTITION p2024 VALUES LESS THAN (TO_DAYS('2025-01-01')),
  PARTITION p2025 VALUES LESS THAN (TO_DAYS('2026-01-01')),
  PARTITION p2026_01 VALUES LESS THAN (TO_DAYS('2026-02-01'))
);
```

Ganze Jahre reichen für die importierte Vergangenheit: Diese Partitionen wachsen nie wieder,
und der Zweck des monatlichen Schnitts — alte Daten in einem Rutsch zu löschen — wird von
einem Jahr genauso gut erfüllt.

Am einfachsten ist allerdings die umgekehrte Reihenfolge: **erst importieren, dann
partitionieren.** Das erste `ALTER TABLE … PARTITION BY` schreibt die Tabelle ohnehin neu und
sortiert alles, was darin steht, von selbst in die richtige Partition.

## Danach

```sql
-- How much arrived, per source
SELECT source, COUNT(*), MIN(ts), MAX(ts) FROM states GROUP BY source;

-- Refresh the index statistics after a bulk import
ANALYZE TABLE states;
```

Läuft die InfluxDB-Integration noch parallel, füllen sich eine Weile beide Archive — das ist
unbedenklich. Sobald das MariaDB-Archiv vollständig ist, kann `influxdb:` aus der
`configuration.yaml` raus und das Add-on weg.

## Hinweise

- **Zeitstempel** sind auf beiden Seiten UTC, es wird also nichts umgerechnet.
- **Millisekunden:** InfluxDB speichert Nanosekunden, `DATETIME(3)` speichert Millisekunden.
  Zwei Punkte derselben Entity innerhalb derselben Millisekunde fallen zu einer Zeile
  zusammen — der Primärschlüssel `(entity_id, ts)` erlaubt nur eine, und `INSERT IGNORE`
  behält die erste.
- **Duplikate im Dump:** `influx_inspect` schreibt die TSM-Daten und die WAL-Daten
  nacheinander, sodass derselbe Punkt zweimal auftauchen kann. `INSERT IGNORE` regelt das.
- **Booleans** werden zu `value = 1` / `0` mit `state = 'true'` / `'false'`, sodass ein
  `binary_sensor` in einem Graphen nutzbar bleibt.
- **Zahlen** behalten die Schreibweise aus dem Dump: `42i` wird zu `42`, `-3.25e2` bleibt
  `-3.25e2`. Beides sind gültige `DOUBLE`-Literale und landen als dieselbe Zahl in der Spalte.
- **Nicht mehr existierende Entities** werden ebenfalls übernommen. Ihre Zeilen sind
  unbedenklich, und `DELETE FROM states WHERE entity_id LIKE …` entfernt sie nachträglich.

## Lizenz

MIT License
