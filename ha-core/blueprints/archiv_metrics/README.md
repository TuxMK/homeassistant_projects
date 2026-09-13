# Metrik-Archiv (MariaDB)

Home-Assistant-Blueprint, das Sensorwerte über den Pyscript-Connector
`pyscript.sql_execute` in eine eigene MariaDB-Datenbank schreibt.

Gedacht als Ersatz für die InfluxDB-Integration: Die Langzeitdaten liegen dann in einer
gewöhnlichen SQL-Datenbank, lassen sich mit `mysqldump` sichern, in phpMyAdmin korrigieren
und in Grafana über die MySQL-Datenquelle abfragen.

Alles Anwendungsspezifische wird in der Automation eingestellt — Entitäten, Datenbank,
Tabelle, Login, Host, Port, Mindestabstand und Sammelintervall. Nichts davon ist im
Blueprint fest verdrahtet, die angezeigten Werte sind nur Vorgaben. Dasselbe Blueprint
lässt sich deshalb mehrfach verwenden, etwa mit getrennten Tabellen oder Intervallen je
Sensorgruppe.

**Version: 1.4**

## Features

- Archiviert beliebig viele Sensoren, ausgewählt in der Automation
- Speichert den echten Änderungszeitpunkt (`last_changed`, UTC), nicht den Schreibzeitpunkt
- Drosselung pro Entität: höchstens ein Wert pro Intervall, der **neueste** gewinnt
- Die erste Änderung nach einer Ruhephase wird ohne Verzögerung geschrieben
- Keine Änderung, kein Schreibvorgang — und auch keine Leerläufe
- Nicht-numerische Zustände (`unknown`, `unavailable`, Text) werden übersprungen
- Datenbank, Tabelle, Login, Host und Port kommen vollständig aus der Automation
- Ein einziges `SELECT` pro Lauf, danach ein `INSERT` pro tatsächlich fälligem Wert — jedes
  Statement hat eine feste Form, nichts am SQL hängt von der Anzahl der Entitäten ab

## Schreiblogik

| Situation | Verhalten |
|-----------|----------|
| Erste Änderung nach einer Ruhephase | wird sofort geschrieben |
| Weitere Änderungen innerhalb des Intervalls | werden gesammelt, nur der neueste Wert wird geschrieben, sobald das Intervall abgelaufen ist |
| Keine Änderung | es wird nichts geschrieben |

Das funktioniert ohne Hilfsentitäten: Das Archiv selbst ist der Zustandsspeicher.

Jeder Lauf — egal ob eine Zustandsänderung oder der Sammellauf ihn ausgelöst hat — betrachtet
**alle** Entitäten. Ein `SELECT entity_id, UNIX_TIMESTAMP(MAX(ts))` liefert für jede von
ihnen den zuletzt archivierten Zeitstempel, und eine Entität wird nur geschrieben, wenn ihr
`last_changed` neuer ist als dieser Zeitstempel (es also tatsächlich etwas Neues gibt)
**und** seit dem zuletzt archivierten Wert mindestens der Mindestabstand vergangen ist.

Daraus ergeben sich die drei Regeln oben: Nach einer Ruhephase ist der zuletzt archivierte
Wert älter als der Mindestabstand, also wird die Änderung sofort geschrieben; in einer
aktiven Phase blockiert der Abstand das Schreiben, bis ein späterer Lauf den dann aktuellen
Wert aufgreift; und eine Entität, die sich nicht geändert hat, besteht die Prüfung auf
„etwas Neues“ nie.

**Warum jeder Lauf alle Entitäten abdeckt:** Sensoren ändern sich häufig in derselben
Millisekunde — ein Summensensor aktualisiert sich im selben Augenblick wie eine seiner
Quellen. Die Automation läuft im Modus `single`, solche nahezu gleichzeitigen Trigger
werden also verworfen. Würde ein Lauf nur für die auslösende Entität schreiben, verlöre ein
abgeleiteter Sensor jedes Mal seinen Platz und würde nie archiviert. Weil jeder Lauf
stellvertretend für alle schreibt, spielt es keine Rolle mehr, welcher Trigger das Rennen
gewinnt.

So geht auch der Endstand eines Ladevorgangs nicht verloren: Sobald die Wallbox aufhört zu
zählen, ergänzt der nächste Sammellauf den letzten Wert.

**Hinweis zur Genauigkeit:** Der Mindestabstand wird gegen den Zeitstempel des zuletzt
archivierten Werts geprüft, nicht gegen den Schreibzeitpunkt. Beim Übergang von einer
Ruhephase in eine aktive Phase können zwei Zeilen daher einmalig näher beieinander liegen.
Im Dauerbetrieb bleibt es bei einer Zeile pro Intervall und Entität.

## Voraussetzungen

### 1. MariaDB-Add-on

Offizielles MariaDB-Add-on mit **eigener** Datenbank. Der Recorder bleibt unverändert auf
SQLite — unter `recorder:` in der `configuration.yaml` wird **keine** `db_url` gesetzt.

```yaml
databases:
  - ha_metrics
logins:
  - username: homeassistant
    password: "STRONG_PASSWORD_1"
  - username: grafana
    password: "STRONG_PASSWORD_2"
rights:
  - username: homeassistant
    database: ha_metrics
  - username: grafana
    database: ha_metrics
    privileges:
      - SELECT
```

### 2. Tabelle

Anlegen zum Beispiel über das phpMyAdmin-Add-on:

```sql
CREATE TABLE states (
  entity_id VARCHAR(255)  NOT NULL,
  ts        DATETIME(3)   NOT NULL,                    -- always UTC
  value     DOUBLE        NULL,                        -- numeric value
  state     VARCHAR(255)  NULL,                        -- raw state as text
  unit      VARCHAR(32)   NULL,
  source    VARCHAR(16)   NOT NULL DEFAULT 'ha',       -- ha / import / manual
  PRIMARY KEY (entity_id, ts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Der Primärschlüssel `(entity_id, ts)` ist Pflicht: Er sortiert die Daten physisch nach
Sensor und Zeit und verhindert Duplikate, etwa nach einem Neustart von Home Assistant.

Das Blueprint befüllt `entity_id`, `ts`, `value` und `unit`. `source` bleibt auf dem
Standardwert `ha`, damit von Hand korrigierte oder später importierte Zeilen über
`source = 'manual'` bzw. `'import'` erkennbar bleiben.

### 3. Pyscript-Connector

Der Connector [`ha_mysql.py`](../../../ha-plugins/pyscript/apps/ha_mysql.py) gehört nach
`/config/pyscript/apps/ha_mysql.py`, zusammen mit einer `/config/pyscript/requirements.txt`,
die die Zeile `PyMySQL` enthält.

```yaml
# configuration.yaml
pyscript:
  allow_all_imports: true
  apps:
    ha_mysql:
      default_login: archiv
      logins:
        archiv:
          username: !secret archiv_db_user
          password: !secret archiv_db_password
```

Der Name unter `apps:` muss dem Dateinamen entsprechen. Nach einem Neustart steht die Aktion
**Run SQL** (`pyscript.sql_execute`) in den Entwicklerwerkzeugen zur Verfügung und lässt
sich dort mit `SELECT 1` testen.

## Installation

### Über die UI

1. **Einstellungen > Automationen & Szenen > Blueprints**
2. Auf **Blueprint importieren** klicken
3. Die Raw-URL der Datei `blueprint_archiv_metrics.yaml` eingeben

### Manuell

Die Datei nach `/config/blueprints/automation/archiv_metrics/` kopieren und die
Automationen in den Entwicklerwerkzeugen neu laden.

## Konfiguration

Die Spalte „Standard“ zeigt nur die Vorbelegung des Eingabefelds. Jeder Wert lässt sich pro
Automation überschreiben.

Die Spalte „Option“ nennt die Felder so, wie das Blueprint-Formular sie anzeigt, also auf Englisch; hinter dem Gedankenstrich der Überschriften steht der Abschnittsname aus dem Formular.

### Quelle – Source

| Option | Beschreibung | Standard |
|--------|-------------|---------|
| Entities | Die zu archivierenden Sensoren | — |

### Ziel – Target

| Option | Beschreibung | Standard |
|--------|-------------|---------|
| Database | Name der Datenbank in MariaDB | `ha_metrics` |
| Table | Zieltabelle mit Primärschlüssel `(entity_id, ts)` | `states` |
| Login | Login-Name aus der Pyscript-App-Konfiguration, leer = `default_login` | leer |

### Schreibverhalten – Write behavior

| Option | Beschreibung | Standard |
|--------|-------------|---------|
| Minimum spacing | Mindestabstand zwischen zwei archivierten Werten pro Entität, in Sekunden | `10` |
| Write first change immediately | Schreibt die erste Änderung nach einer Ruhephase ohne Verzögerung | `true` |
| Sweep interval | Wie oft gesammelte Änderungen geschrieben werden, in Sekunden | `10` |

Das Sammelintervall sollte nicht größer sein als der Mindestabstand, sonst bestimmt es den
tatsächlichen Abstand der archivierten Werte.

Das Sammelintervall ist eine feste Liste (5, 10, 15, 20, 30 oder 60 Sekunden) statt einer
freien Zahl: Es ist als `time_pattern`-Trigger umgesetzt, und der muss 60 Sekunden ohne Rest
teilen. Der Mindestabstand ist dagegen frei in Sekunden wählbar — er bestimmt, wie dicht die
Werte tatsächlich liegen, und damit das Wachstum der Tabelle.

### Wie viel Speicher das kostet

Bei rund 116 Byte pro Zeile (InnoDB inklusive Seitenfüllgrad) und **10 Entitäten**, die sich
fortlaufend ändern:

| Mindestabstand | Zeilen/Tag | Zeilen/Jahr | Pro Jahr | Nach 5 Jahren |
|---|---|---|---|---|
| 10 s | 86.400 | 31,5 Mio. | 3,4 GB | **17,0 GB** |
| 15 s | 57.600 | 21,0 Mio. | 2,3 GB | 11,4 GB |
| 30 s | 28.800 | 10,5 Mio. | 1,1 GB | 5,7 GB |
| 60 s | 14.400 | 5,3 Mio. | 581 MB | 2,8 GB |
| 300 s | 2.880 | 1,1 Mio. | 116 MB | 0,6 GB |

Das ist die Obergrenze. In der Praxis bleibt es darunter, weil Gas, Wallbox und Pool zeitweise
ruhen und dann nichts geschrieben wird.

Die Vorgabe von 10 Sekunden zielt auf Auflösung, nicht auf Sparsamkeit. Wer fünf Jahre
aufbewahren will, sollte entweder den Mindestabstand erhöhen oder die unten beschriebene
Monatspartitionierung einrichten und alte Partitionen verwerfen.

### Verbindung (erweitert) – Connection (advanced)

| Option | Beschreibung | Standard |
|--------|-------------|---------|
| Host | Datenbank-Host | `core-mariadb` |
| Port | Datenbank-Port | `3306` |

## Beispiel

Archiv der Strom-, Gas- und Wallbox-Zähler, einmal pro Minute:

```yaml
alias: Meter readings to archive
use_blueprint:
  path: archiv_metrics/blueprint_archiv_metrics.yaml
  input:
    entities:
      - sensor.wohnungeg_uv_1_total_active_energy
      - sensor.wohnungeg_uv_2_total_active_energy
      - sensor.wohnung_eg_uv_all_total_active_energy
      - sensor.gaszahler_wohnung_eg_total_gas_consumption_cleaned
      - sensor.hems_evcc_wallbox_wohnung_eg_charge_total_import
    database: ha_metrics
    table: states
    login: archiv
    throttle_seconds: 60
    sweep_seconds: "0"
```

Mit fünf Zählern und einer Drosselung auf eine Minute entstehen höchstens etwa 7.200 Zeilen
pro Tag, also rund 291 MB pro Jahr und 1,4 GB über fünf Jahre. In der Praxis deutlich
weniger, weil Gas und Wallbox oft ruhen.

## Monatspartitionierung

Eine partitionierte Tabelle sieht für SQL wie eine einzige Tabelle aus — Blueprint, Grafana
und phpMyAdmin merken nichts davon. Intern legt InnoDB pro Partition eine eigene Datei an und
sortiert jede Zeile anhand von `ts` automatisch in die richtige ein.

Das bringt zweierlei:

- **Löschen in Millisekunden.** `DELETE FROM states WHERE ts < …` muss jede einzelne von
  Millionen Zeilen anfassen und ins Transaktionslog schreiben — das kann eine laufende
  Home-Assistant-Instanz minutenlang blockieren. `ALTER TABLE … DROP PARTITION` löscht
  stattdessen eine ganze Datei, egal wie viele Zeilen darin stehen.
- **Kürzere Abfragen.** Bei `WHERE ts BETWEEN '2026-03-01' AND '2026-03-31'` erkennt
  MariaDB, dass nur die März-Partition infrage kommt, und ignoriert alle anderen
  („Partition Pruning“). Das hilft genau bei den Abfragen über alle Entitäten, die sonst
  einen vollständigen Tabellenscan auslösen würden.

Eine Regel von InnoDB ist dabei entscheidend: **Die Partitionsspalte muss Teil jedes
eindeutigen Schlüssels sein.** Der Primärschlüssel ist `(entity_id, ts)` und enthält `ts`
bereits — deshalb funktioniert die Partitionierung nach `ts` ohne jede Schemaänderung. Wäre
der Schlüssel nur `(entity_id)` oder gäbe es eine `id`-Spalte als Schlüssel, ginge es nicht.

### Einrichten

`TO_DAYS(ts)` wandelt das Datum in eine Zahl um, aus der sich Bereiche bilden lassen. Jede
Partition nimmt alles auf, was **kleiner als** ihre Grenze ist — `p2026_03` endet also am
1. April und enthält damit genau den März:

```sql
ALTER TABLE states PARTITION BY RANGE (TO_DAYS(ts)) (
  PARTITION p2026_01 VALUES LESS THAN (TO_DAYS('2026-02-01')),
  PARTITION p2026_02 VALUES LESS THAN (TO_DAYS('2026-03-01')),
  PARTITION p2026_03 VALUES LESS THAN (TO_DAYS('2026-04-01')),
  PARTITION p2026_04 VALUES LESS THAN (TO_DAYS('2026-05-01')),
  PARTITION pmax     VALUES LESS THAN MAXVALUE
);
```

`pmax` ist die Auffangpartition. Ohne sie würde ein `INSERT` mit einem Zeitstempel jenseits
der letzten Grenze mit „Table has no partition for value“ fehlschlagen — genau dann, wenn
der nächste Monat beginnt und niemand daran gedacht hat.

### Monate hinzufügen

Weil neue Monate nicht von selbst entstehen, muss vor jedem Monatswechsel eine Partition
hinzugefügt werden. Das Blueprint [Monatspartitionen pflegen](../archiv_partitions/) erledigt
das automatisch — es legt den Vorlauf an und verwirft optional alte Monate. Von Hand
funktioniert es so, indem `pmax` aufgeteilt wird:

```sql
ALTER TABLE states REORGANIZE PARTITION pmax INTO (
  PARTITION p2026_05 VALUES LESS THAN (TO_DAYS('2026-06-01')),
  PARTITION pmax     VALUES LESS THAN MAXVALUE
);
```

Solange `pmax` leer ist, geht das sofort. Läuft es erst, wenn dort schon Daten liegen, muss
MariaDB diese Zeilen umsortieren — dann dauert es eine Weile. Deshalb gehört das in eine
Automation, die zu Beginn jedes Monats den **übernächsten** Monat anlegt.

### Alte Daten verwerfen

```sql
ALTER TABLE states DROP PARTITION p2026_01;
```

Ein Aufruf, konstante Laufzeit, kein aufgeblähtes Transaktionslog. Das ist der eigentliche
Grund, warum sich die Partitionierung lohnt: Ohne sie gibt es keinen praktikablen Weg, ein
über Jahre gewachsenes Archiv wieder zu verkleinern.

### Nachsehen, was drin ist

```sql
SELECT partition_name, table_rows,
       ROUND((data_length + index_length) / 1024 / 1024) AS mb
FROM information_schema.partitions
WHERE table_schema = 'ha_metrics' AND table_name = 'states'
ORDER BY partition_ordinal_position;
```

Bei InnoDB ist `table_rows` nur ein Schätzwert, für die Größenverteilung reicht er aber aus.

## Migration aus InfluxDB

Die Historie, die bereits in der InfluxDB-Integration liegt, muss nicht zurückbleiben. Die
beiden Skripte in [`tools/`](tools/) übertragen sie: Eines exportiert die Punkte Monat für
Monat als Line Protocol, das andere schreibt sie in diese Tabelle. Mehr als `docker`, `awk`
und der `mysql`-Client wird nicht benötigt.

```bash
# on the HA host: dump the history, one file per month
zsh tools/influx_export_monthly.sh

# wherever the dumps landed: straight into the archive table
tools/influx_import_mysql.sh <db-user> <db-password>
```

Die importierten Zeilen tragen `source = 'import'` und werden mit `INSERT IGNORE`
eingefügt, sodass nichts überschrieben wird, was dieses Blueprint oder eine manuelle
Korrektur bereits geschrieben hat. Der Stichtag, der verhindert, dass sich Import und
Live-Daten überschneiden, die Zuordnung der beiden Schemata und der Fallstrick bei einer
bereits partitionierten Tabelle stehen im [README der Tools](tools/).

## Abfragen in Grafana

Datenquelle vom Typ **MySQL**, Host `core-mariadb:3306`, Datenbank `ha_metrics`, Benutzer
`grafana` (nur lesend).

Zeitreihe eines Zählers:

```sql
SELECT ts AS time, value AS "Gas meter"
FROM states
WHERE entity_id = 'sensor.gaszahler_wohnung_eg_total_gas_consumption_cleaned'
  AND $__timeFilter(ts)
ORDER BY ts
```

Monatsverbrauch (Zählerstand am Monatsende minus Vormonat):

```sql
SELECT month AS time, reading - LAG(reading) OVER (ORDER BY month) AS consumption
FROM (
  SELECT DATE_FORMAT(ts, '%Y-%m-01') AS month, MAX(value) AS reading
  FROM states
  WHERE entity_id = 'sensor.gaszahler_wohnung_eg_total_gas_consumption_cleaned'
  GROUP BY month
) m
ORDER BY month
```

Die Zeitstempel liegen in UTC, die Monatsgrenzen sind gegenüber deutscher Ortszeit also um
ein bis zwei Stunden verschoben. Für eine Jahresabrechnung ist das vernachlässigbar.

## Korrekturen

Ausreißer und Zählerwechsel werden direkt per SQL korrigiert, zum Beispiel in phpMyAdmin,
und dabei als manuell markiert:

```sql
UPDATE states SET value = 12345.6, source = 'manual'
WHERE entity_id = 'sensor.gaszahler_wohnung_eg_total_gas_consumption_cleaned'
  AND ts = '2026-03-14 10:02:13.000';
```

Das Blueprint überschreibt solche Korrekturen nicht: Eine Zeile wird nur dann erneut
angefasst, wenn Home Assistant einen weiteren Wert für exakt denselben Zeitstempel liefert.

Unabhängig davon bleiben die Langzeitstatistiken von Home Assistant das Sicherheitsnetz für
die Abrechnung. Sie lassen sich unter **Entwicklerwerkzeuge > Statistiken** korrigieren.

## Hinweise

- **Neustart von Home Assistant:** `last_changed` wird beim Start zurückgesetzt. Der erste
  Sammellauf danach schreibt den aktuellen Stand einmal pro Zähler mit neuem Zeitstempel.
  Das ist harmlos, der Zählerstand selbst bleibt korrekt.
- **Datenbank nicht erreichbar:** Der Lauf bricht ab, und der Fehler erscheint im HA-Log.
  Zählerstände sind kumulativ, es fehlen also nur Zwischenpunkte — der nächste geschriebene
  Wert enthält die korrekte Summe.
- **Attributänderungen** (etwa ein neuer `friendly_name`) lösen keinen Schreibvorgang aus,
  weil sie `last_changed` nicht verändern.
- **Einheiten aus Enums:** Integrationen liefern `unit_of_measurement` mitunter als
  Enum-Member wie `UnitOfEnergy.KILO_WATT_HOUR` statt als einfachen String. Das Blueprint
  erzwingt deshalb per `~ ''` einen String, bevor der Wert in die Zeilenliste gelangt — ein
  `| string`-Filter reicht nicht, weil das Enum von `str` erbt und Jinja es unverändert
  durchreicht. Ohne das ist die gerenderte Liste keine gültige Python-Literal-Syntax, Home
  Assistant behält sie als Text, und der Lauf scheitert mit
  `Repeat 'for_each' must be a list of items`.
- **Parallele Läufe:** Die Automation läuft im Modus `single` mit `max_exceeded: silent`.
  Überlappende Trigger werden verworfen, ohne das Log zu fluten — der nächste Sammellauf
  holt alles nach.

## Lizenz

MIT License
