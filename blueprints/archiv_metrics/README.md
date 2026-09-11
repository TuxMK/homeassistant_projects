# SQL-Archiv (MariaDB)

Home Assistant Blueprint, der Sensorwerte über den pyscript-Connector
`pyscript.sql_execute` in eine eigene MariaDB-Datenbank schreibt.

Gedacht als Ersatz für die InfluxDB-Integration: Die Langzeitdaten liegen danach in
einer normalen SQL-Datenbank, lassen sich mit `mysqldump` sichern, in phpMyAdmin
korrigieren und in Grafana über die MySQL-Datenquelle auswerten.

Alles Fachliche wird in der Automatisierung gesetzt — Entitäten, Datenbank, Tabelle,
Login, Host, Port, Mindestabstand und Intervall. Im Blueprint steht davon nichts fest,
die angegebenen Werte sind nur Vorbelegungen. Dieselbe Vorlage lässt sich deshalb
mehrfach verwenden, etwa mit getrennten Tabellen oder Intervallen je Sensorgruppe.

**Version: 1.1**

## Features

- Archiviert beliebig viele Sensoren, die Auswahl erfolgt in der Automatisierung
- Schreibt den echten Änderungszeitpunkt (`last_changed`, UTC), nicht den Schreibzeitpunkt
- Drosselung je Entität: höchstens ein Wert pro Intervall, der **neueste** gewinnt
- Erste Änderung nach einer Ruhephase wird ohne Verzögerung geschrieben
- Keine Änderung, kein Schreibvorgang — auch keine leeren Durchläufe
- Nicht-numerische Zustände (`unknown`, `unavailable`, Text) werden übersprungen
- Datenbank, Tabelle, Login, Host und Port kommen komplett aus der Automatisierung
- Ein einziger `SELECT` und ein einziger `INSERT` je Durchlauf, unabhängig von der
  Anzahl der Entitäten

## Schreiblogik

| Situation | Verhalten |
|-----------|-----------|
| Erste Änderung nach einer Ruhephase | wird sofort geschrieben |
| Weitere Änderungen innerhalb des Intervalls | werden gesammelt, nach Ablauf des Intervalls wird nur der neueste Wert geschrieben |
| Keine Änderung | es wird nichts geschrieben |

Umgesetzt wird das ohne Helfer-Entitäten: Das Archiv selbst ist der Zustandsspeicher.

1. **Zustandswechsel einer Entität.** Der Blueprint prüft, ob der *vorherige* Wert
   mindestens den Mindestabstand lang stabil war. Nur dann war er sicher schon
   archiviert, und die neue Änderung ist die „erste nach der Ruhephase“ — sie wird
   sofort geschrieben. Änderungen in schneller Folge lösen dagegen keinen
   Datenbankzugriff aus.
2. **Intervall-Lauf.** Ein `SELECT entity_id, UNIX_TIMESTAMP(MAX(ts))` liefert für alle
   Entitäten den letzten archivierten Zeitstempel. Geschrieben wird eine Entität nur,
   wenn ihr `last_changed` neuer ist als der archivierte Zeitstempel (es gibt also
   etwas Neues) **und** seit dem letzten archivierten Wert mindestens der
   Mindestabstand vergangen ist.

Dadurch geht auch der Endstand eines Ladevorgangs nicht verloren: Hört die Wallbox
auf zu zählen, trägt der nächste Intervall-Lauf den letzten Wert nach.

**Hinweis zur Genauigkeit:** Der Mindestabstand wird gegen den Zeitstempel des zuletzt
archivierten Werts geprüft, nicht gegen den Zeitpunkt des Schreibens. Beim Übergang
von einer Ruhephase in eine aktive Phase können deshalb einmalig zwei Zeilen dichter
beieinander liegen. Im Dauerbetrieb bleibt es bei einer Zeile je Intervall und Entität.

## Voraussetzungen

### 1. MariaDB-Add-on

Offizielles MariaDB-Add-on mit einer **eigenen** Datenbank. Der Recorder bleibt dabei
unangetastet auf SQLite — in der `configuration.yaml` wird unter `recorder:` **kein**
`db_url` gesetzt.

```yaml
databases:
  - ha_metrics
logins:
  - username: homeassistant
    password: "STARKES_PASSWORT_1"
  - username: grafana
    password: "STARKES_PASSWORT_2"
rights:
  - username: homeassistant
    database: ha_metrics
  - username: grafana
    database: ha_metrics
    privileges:
      - SELECT
```

### 2. Tabelle

Anlegen z. B. über das phpMyAdmin-Add-on:

```sql
CREATE TABLE states (
  entity_id VARCHAR(255)  NOT NULL,
  ts        DATETIME(3)   NOT NULL,                    -- immer UTC
  value     DOUBLE        NULL,                        -- numerischer Wert
  state     VARCHAR(255)  NULL,                        -- Rohzustand als Text
  unit      VARCHAR(32)   NULL,
  source    VARCHAR(16)   NOT NULL DEFAULT 'ha',       -- ha / import / manuell
  PRIMARY KEY (entity_id, ts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Der Primärschlüssel `(entity_id, ts)` ist Pflicht: Er sortiert die Daten physisch nach
Sensor und Zeit und verhindert Duplikate, etwa nach einem Neustart von Home Assistant.

Der Blueprint befüllt `entity_id`, `ts`, `value` und `unit`. `source` bleibt auf dem
Standardwert `ha`, sodass von Hand korrigierte oder importierte Zeilen später über
`source = 'manuell'` bzw. `'import'` erkennbar bleiben.

### 3. pyscript-Connector

Der Connector [`ha_mysql.py`](../../pyscript/apps/ha_mysql.py) gehört nach
`/config/pyscript/apps/ha_mysql.py`, dazu `/config/pyscript/requirements.txt` mit der
Zeile `PyMySQL`.

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

Der Name unter `apps:` muss dem Dateinamen entsprechen. Nach einem Neustart steht die
Aktion **SQL ausführen** (`pyscript.sql_execute`) in den Entwicklerwerkzeugen bereit
und lässt sich dort mit `SELECT 1` testen.

## Installation

### Über die UI

1. **Einstellungen > Automatisierungen & Szenen > Blueprints**
2. **Blueprint importieren** klicken
3. Raw-URL der Datei `blueprint_metrics.yaml` eingeben

### Manuell

Die Datei nach `/config/blueprints/automation/metrics/` kopieren und in den
Entwicklerwerkzeugen die Automatisierungen neu laden.

## Konfiguration

Die Spalte „Standard“ zeigt nur die Vorbelegung der Eingabe. Jeder Wert lässt sich je
Automatisierung überschreiben.

### Quelle

| Option | Beschreibung | Standard |
|--------|--------------|----------|
| Entitäten | Die zu archivierenden Sensoren | — |

### Ziel

| Option | Beschreibung | Standard |
|--------|--------------|----------|
| Datenbank | Name der Datenbank in MariaDB | `ha_metrics` |
| Tabelle | Zieltabelle mit Primärschlüssel `(entity_id, ts)` | `states` |
| Login | Login-Name aus der pyscript-App-Konfiguration, leer = `default_login` | leer |

### Schreibverhalten

| Option | Beschreibung | Standard |
|--------|--------------|----------|
| Mindestabstand | Mindestabstand zwischen zwei archivierten Werten je Entität, in Sekunden | `10` |
| Erste Änderung sofort schreiben | Schreibt die erste Änderung nach einer Ruhephase ohne Verzögerung | `true` |
| Intervall-Lauf | Wie oft gesammelte Änderungen nachgetragen werden, in Sekunden | `10` |

Der Intervall-Lauf sollte nicht größer als der Mindestabstand sein, sonst bestimmt er
den tatsächlichen Abstand der archivierten Werte.

Der Intervall-Lauf ist eine feste Auswahl (5, 10, 15, 20, 30 oder 60 Sekunden) statt
einer freien Zahl: Er wird als `time_pattern`-Auslöser umgesetzt, und der muss 60
Sekunden gleichmäßig teilen. Der Mindestabstand ist dagegen frei in Sekunden wählbar —
er bestimmt, wie dicht die Werte tatsächlich liegen, und damit direkt das Wachstum der
Tabelle.

### Wie viel Speicher das kostet

Bei rund 116 Byte je Zeile (InnoDB inklusive Seitenfüllgrad) und **10 Entitäten**, die
sich durchgehend ändern:

| Mindestabstand | Zeilen/Tag | Zeilen/Jahr | pro Jahr | nach 5 Jahren |
|---|---|---|---|---|
| 10 s | 86.400 | 31,5 Mio | 3,4 GB | **17,0 GB** |
| 15 s | 57.600 | 21,0 Mio | 2,3 GB | 11,4 GB |
| 30 s | 28.800 | 10,5 Mio | 1,1 GB | 5,7 GB |
| 60 s | 14.400 | 5,3 Mio | 581 MB | 2,8 GB |
| 300 s | 2.880 | 1,1 Mio | 116 MB | 0,6 GB |

Das ist die Obergrenze. In der Praxis liegt es darunter, weil Gas, Wallbox und Pool
zeitweise stillstehen und dann nichts geschrieben wird.

Der Standard von 10 Sekunden ist auf Auflösung ausgelegt, nicht auf Sparsamkeit.
Wer fünf Jahre aufheben will, sollte entweder den Mindestabstand hochsetzen oder die
Monatspartitionierung weiter unten einrichten und alte Partitionen verwerfen.

### Verbindung (erweitert)

| Option | Beschreibung | Standard |
|--------|--------------|----------|
| Host | Datenbank-Host | `core-mariadb` |
| Port | Datenbank-Port | `3306` |

## Beispiel

Archiv der Strom-, Gas- und Wallbox-Zähler, minütlich:

```yaml
alias: Zählerstände ins Archiv
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

Bei fünf Zählern und minütlicher Drosselung entstehen höchstens rund 7.200 Zeilen pro
Tag, also etwa 291 MB im Jahr und 1,4 GB in fünf Jahren. In der Praxis deutlich
weniger, weil Gas und Wallbox oft stillstehen.

## Monatspartitionierung

Eine partitionierte Tabelle sieht für SQL aus wie eine einzige Tabelle — der Blueprint,
Grafana und phpMyAdmin merken nichts davon. Intern legt InnoDB pro Partition eine
eigene Datei an und sortiert jede Zeile anhand von `ts` automatisch in die richtige ein.

Das bringt zwei Dinge:

- **Löschen in Millisekunden.** `DELETE FROM states WHERE ts < …` muss bei Millionen
  Zeilen jede einzelne anfassen und ins Transaktionslog schreiben — das kann eine
  laufende Home-Assistant-Instanz minutenlang blockieren. `ALTER TABLE … DROP PARTITION`
  löscht stattdessen eine ganze Datei, unabhängig davon, wie viele Zeilen darin stehen.
- **Kürzere Abfragen.** Bei `WHERE ts BETWEEN '2026-03-01' AND '2026-03-31'` sieht
  MariaDB, dass nur die März-Partition in Frage kommt, und ignoriert alle anderen
  („partition pruning"). Das hilft genau bei den Abfragen über alle Entitäten hinweg,
  die sonst einen vollständigen Tabellenscan auslösen.

Wichtig ist eine Regel von InnoDB: **Die Partitionsspalte muss Teil jedes eindeutigen
Schlüssels sein.** Der Primärschlüssel hier ist `(entity_id, ts)` und enthält `ts`
bereits — deshalb funktioniert die Partitionierung nach `ts` ohne jede Änderung am
Schema. Wäre der Schlüssel nur `(entity_id)` oder gäbe es eine `id`-Spalte als
Schlüssel, ginge es nicht.

### Einrichten

`TO_DAYS(ts)` wandelt das Datum in eine Zahl um, nach der sich Bereiche bilden lassen.
Jede Partition nimmt alles auf, was **kleiner** als ihr Grenzwert ist — `p2026_03` endet
also am 1. April und enthält damit genau den März:

```sql
ALTER TABLE states PARTITION BY RANGE (TO_DAYS(ts)) (
  PARTITION p2026_01 VALUES LESS THAN (TO_DAYS('2026-02-01')),
  PARTITION p2026_02 VALUES LESS THAN (TO_DAYS('2026-03-01')),
  PARTITION p2026_03 VALUES LESS THAN (TO_DAYS('2026-04-01')),
  PARTITION p2026_04 VALUES LESS THAN (TO_DAYS('2026-05-01')),
  PARTITION pmax     VALUES LESS THAN MAXVALUE
);
```

`pmax` ist die Auffangpartition. Ohne sie würde ein `INSERT` mit einem Zeitstempel
jenseits der letzten Grenze mit „Table has no partition for value" scheitern — also
genau dann, wenn der nächste Monat beginnt und niemand daran gedacht hat.

### Monatlich nachziehen

Weil neue Monate nicht von selbst entstehen, muss vor jedem Monatswechsel eine Partition
dazukommen. Der Weg dafür ist, `pmax` aufzuteilen:

```sql
ALTER TABLE states REORGANIZE PARTITION pmax INTO (
  PARTITION p2026_05 VALUES LESS THAN (TO_DAYS('2026-06-01')),
  PARTITION pmax     VALUES LESS THAN MAXVALUE
);
```

Solange `pmax` leer ist, geht das sofort. Läuft es dagegen erst, wenn dort schon Daten
liegen, muss MariaDB diese Zeilen umsortieren — dann dauert es. Deshalb gehört das in
eine Automatisierung, die am Monatsanfang den **übernächsten** Monat anlegt.

### Alte Daten verwerfen

```sql
ALTER TABLE states DROP PARTITION p2026_01;
```

Ein Aufruf, konstante Laufzeit, kein aufgeblähtes Transaktionslog. Das ist der
eigentliche Grund, warum sich die Partitionierung lohnt: Ohne sie gibt es keinen
praktikablen Weg, ein über Jahre gewachsenes Archiv wieder zu verkleinern.

### Was drin ist, nachsehen

```sql
SELECT partition_name, table_rows,
       ROUND((data_length + index_length) / 1024 / 1024) AS mb
FROM information_schema.partitions
WHERE table_schema = 'ha_metrics' AND table_name = 'states'
ORDER BY partition_ordinal_position;
```

`table_rows` ist bei InnoDB nur eine Schätzung, für die Größenverteilung reicht es.

## Auswertung in Grafana

Datenquelle vom Typ **MySQL**, Host `core-mariadb:3306`, Datenbank `ha_metrics`,
Benutzer `grafana_ro` (nur Leserechte).

Zeitverlauf eines Zählers:

```sql
SELECT ts AS time, value AS "Gaszähler"
FROM states
WHERE entity_id = 'sensor.gaszahler_wohnung_eg_total_gas_consumption_cleaned'
  AND $__timeFilter(ts)
ORDER BY ts
```

Monatsverbrauch (Monatsend-Stand minus Vormonat):

```sql
SELECT monat AS time, stand - LAG(stand) OVER (ORDER BY monat) AS verbrauch
FROM (
  SELECT DATE_FORMAT(ts, '%Y-%m-01') AS monat, MAX(value) AS stand
  FROM states
  WHERE entity_id = 'sensor.gaszahler_wohnung_eg_total_gas_consumption_cleaned'
  GROUP BY monat
) m
ORDER BY monat
```

Die Zeitstempel liegen in UTC, die Monatsgrenzen sind gegenüber der deutschen Zeit
also ein bis zwei Stunden versetzt. Für eine Jahresabrechnung ist das vernachlässigbar.

## Korrekturen

Ausreißer und Zählertausch werden direkt per SQL korrigiert, zum Beispiel in
phpMyAdmin, und dabei als manuell markiert:

```sql
UPDATE states SET value = 12345.6, source = 'manuell'
WHERE entity_id = 'sensor.gaszahler_wohnung_eg_total_gas_consumption_cleaned'
  AND ts = '2026-03-14 10:02:13.000';
```

Der Blueprint überschreibt solche Korrekturen nicht: Eine Zeile wird nur dann erneut
angefasst, wenn Home Assistant für exakt denselben Zeitstempel noch einmal einen Wert
liefert.

Unabhängig davon bleiben die Langzeitstatistiken von Home Assistant das Sicherheitsnetz
für die Abrechnung. Sie lassen sich unter **Entwicklerwerkzeuge > Statistik** korrigieren.

## Hinweise

- **Neustart von Home Assistant:** `last_changed` wird beim Start zurückgesetzt. Der
  erste Intervall-Lauf danach schreibt je Zähler einmal den aktuellen Stand mit neuem
  Zeitstempel. Das ist harmlos, der Zählerstand selbst bleibt korrekt.
- **Datenbank nicht erreichbar:** Der Durchlauf bricht ab und der Fehler steht im
  HA-Protokoll. Zählerstände sind kumulativ, es fehlen also nur Zwischenpunkte — der
  nächste geschriebene Wert enthält den korrekten Gesamtstand.
- **Attributänderungen** (z. B. ein neues `friendly_name`) lösen keinen Schreibvorgang
  aus, weil sie `last_changed` nicht verändern.
- **Parallele Läufe:** Die Automatisierung läuft im Modus `single` mit
  `max_exceeded: silent`. Überlappende Auslöser werden verworfen, ohne das Protokoll
  zu fluten — der nächste Intervall-Lauf holt alles nach.

## Lizenz

MIT License
