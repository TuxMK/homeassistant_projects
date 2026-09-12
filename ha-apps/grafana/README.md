# Grafana

Grafana-Dashboards neben Home Assistant: die **Energie-Abrechnung** (Verbrauch und Kosten
je Wohnung, Datenquelle InfluxDB) und ein **Test-Dashboard** gegen die Archivdatenbank
`ha_metrics` (Datenquelle MariaDB).

Alle Dashboards lesen nur — es wird nichts zurückgeschrieben.

## Ordnerstruktur

```
ha-apps/grafana/
└── dashboards/
    ├── abrechnung/                                  # Abrechnungs-Dashboards (InfluxDB)
    │   ├── energie-abrechnung_gas.json              # Gas gesamt: Wohnung EG + OG, Saldo, Abschlagsempfehlung
    │   ├── energie-abrechnung_gas_wohnungEG.json    # Gas nur Wohnung EG, mit Verlaufs-Panels
    │   └── energie-abrechnung_strom_wohnungEG.json  # Platzhalter (noch leer)
    └── test/
        └── ha-metrics_test.json                     # Archiv-Test gegen ha_metrics (MariaDB)
```

Der Ordnername gibt die Gliederung im Repo vor, **nicht** die Ablage in Grafana — dort
werden die Dashboards über die Import-Funktion angelegt.

## Übersicht

| Datei | Titel in Grafana | UID | Datenquelle |
|-------|------------------|-----|-------------|
| [dashboards/abrechnung/energie-abrechnung_gas.json](dashboards/abrechnung/energie-abrechnung_gas.json) | Energie-Abrechnung (Gas) | `d2b6d939-9271-4d45-8ad1-1771804f928f` | InfluxDB |
| [dashboards/abrechnung/energie-abrechnung_gas_wohnungEG.json](dashboards/abrechnung/energie-abrechnung_gas_wohnungEG.json) | Energie-Abrechnung (Gas) - Wohnung EG | `a8b2c9e4-1f3d-4b3f-9b0c-6e18f6c3d4a1` | InfluxDB |
| dashboards/abrechnung/energie-abrechnung_strom_wohnungEG.json | — | — | — |
| [dashboards/test/ha-metrics_test.json](dashboards/test/ha-metrics_test.json) | HA Metrics - Archiv-Test | `ha-metrics-archiv-test` | MySQL/MariaDB |

Die feste UID sorgt dafür, dass ein erneuter Import derselben Datei das vorhandene
Dashboard aktualisiert (Grafana fragt nach, ob überschrieben werden soll) statt eine
zweite Kopie anzulegen.

Die beiden Abrechnungs-Dashboards liegen im **Schema v2**
(`apiVersion: dashboard.grafana.app/v2`, erzeugt mit Grafana 13.2.1); die UID steht dort
unter `metadata.name`. Eine Grafana-Version, die Schema v2 nicht kennt, lehnt den Import
ab. Das Test-Dashboard ist klassisches Schema v1 und lässt sich überall importieren.

---

## Abrechnung

Die Abrechnungs-Dashboards rechnen den Zählerstand eines Flüssiggas-Zählers in Verbrauch,
Energiemenge und Kosten um — pro Wohnung und für den im Zeitpicker gewählten
Abrechnungszeitraum.

Datenquelle ist die **InfluxDB** der Home-Assistant-InfluxDB-Integration: Die Integration
legt je Einheit ein Measurement an, der Gaszähler landet also in `m³`, und die Entity
steht als Tag `entity_id` daran (ohne Domain-Präfix, z. B.
`gaszahler_wohnung_eg_total_gas_consumption_cleaned`).

### Installation

**Dashboards > New > Import**, den Inhalt der JSON-Datei einfügen, **Load**, dann
**Import**.

Die Datasource ist in den Dateien fest über ihre UID `df2uui6kf6oe8e` verdrahtet — das
Schema v2 kennt keinen Import-Dialog für Datasources mehr. Passt die eigene InfluxDB-UID
nicht, gibt es zwei Wege: die UID in der JSON-Datei vor dem Import per Suchen-Ersetzen
austauschen, oder nach dem Import in jedem Panel die Datasource neu auswählen. Ersteres
ist deutlich weniger Arbeit.

### Variablen

Alles Rechnerische hängt an Dashboard-Variablen, es ist nichts in den Panels hart
kodiert. Die Werte stehen oben im Dashboard und gelten sofort für alle Panels.

| Variable | Beschriftung | Typ | Beispiel | Bedeutung |
|----------|--------------|-----|----------|-----------|
| `device` | Zähler / Gerät | Query | `gaszahler_wohnung_eg_total_gas_consumption_cleaned` | Entity des Gaszählers |
| `price` | Preis €/l | Text | `0.56` | Bezugspreis je Liter Flüssiggas |
| `heatingValue` | Brennwert (kWh / m³) | Text | `28.106` | Brennwert für die Umrechnung in kWh |
| `voumeConversionFactor` | m3 in L | Text | `3.94` | Liter je m³ Flüssiggas |
| `delivered_liters` | gelieferte Liter (l) | Text | `2100` | Tanklieferung im Zeitraum (nur Gesamt-Dashboard) |
| `tee_eg` / `tee_og` | Abschlag im Zeitraum (€) | Text | `720` | bereits gezahlte Abschläge je Wohnung (nur Gesamt-Dashboard) |

Die Auswahlliste für `device` kommt aus den Daten selbst:

```sql
SHOW TAG VALUES FROM "m³" WITH KEY = "entity_id"
```

### Berechnung

Grundlage ist immer der Zählerstand in m³. Daraus:

| Größe | Rechenweg |
|-------|-----------|
| Verbrauch (m³) | Zählerstand am Ende − Zählerstand am Anfang des Zeitraums |
| Verbrauch (l) | Verbrauch (m³) × `voumeConversionFactor` |
| Verbrauch (kWh) | Verbrauch (m³) × `heatingValue` |
| Kosten (€) | Verbrauch (m³) × `voumeConversionFactor` × `price` |
| Preis je m³ (€) | `price` × `voumeConversionFactor` |
| Preis je kWh (€) | `price` × `voumeConversionFactor` ÷ `heatingValue` |

Die Differenz „Ende − Anfang" macht bei den Stat-Panels nicht die Abfrage, sondern der
Reducer des Panels: **Gesamtverbrauch**-Panels reduzieren mit `range` (Maximum minus
Minimum im Zeitraum), **Zählerstand**-Panels mit `lastNotNull` (jüngster Wert). Beide
Panel-Paare liegen deshalb auf derselben Abfrage und unterscheiden sich nur in dieser
Einstellung.

Das Panel **Erläuterung der Berechnung** wiederholt die Umrechnungsfaktoren als
Text-Panel im Dashboard selbst — die Tabelle dort ist die Quelle für die Standardwerte
der Variablen.

### Wohnung OG: Verbrauch als Differenz

Nur die Wohnung EG hat einen Zähler. Der Verbrauch der Wohnung OG wird im
Gesamt-Dashboard deshalb als Rest der Tanklieferung bestimmt:

```
Verbrauch OG (l) = delivered_liters − Verbrauch EG (l)
```

Daraus folgen m³ (÷ `voumeConversionFactor`), kWh (× `heatingValue`) und Kosten
(× `price`) wie oben. Das heißt auch: `delivered_liters` muss genau die Liefermenge des
gewählten Zeitraums sein, sonst wandert der Fehler vollständig in die Wohnung OG.

### Saldo und Abschlagsempfehlung

Nur im Gesamt-Dashboard:

- **Saldo (€)** = Kosten im Zeitraum − gezahlte Abschläge (`tee_eg` bzw. `tee_og`).
  Ein positiver Wert ist eine Nachzahlung, ein negativer eine Rückzahlung.
- **Empfohlener monatlicher Abschlag (€)** = Kosten im Zeitraum ÷ Länge des Zeitraums in
  30-Tage-Monaten. Der Zeitraum kommt über `${__from}`/`${__to}` aus dem Zeitpicker, der
  Teiler `2592000000` sind die Millisekunden von 30 Tagen. Der gewählte Zeitraum sollte
  dafür ein volles Abrechnungsjahr sein.

### Panels

**Energie-Abrechnung (Gas) - Wohnung EG** — eine Wohnung, dafür mit Verlauf:

| Panel | Typ |
|-------|-----|
| Zählerstand im Zeitraum (m³ / l / kWh) | Stat |
| Gesamtverbrauch im Zeitraum (m³ / l / kWh) | Stat |
| Kosten / Gesamtkosten im Zeitraum (€) | Stat |
| Zählerstand im Verlauf (m³ / €) | Timeseries |
| Verbrauch im Verlauf (m³ / l / kWh) | Barchart |
| Kosten im Verlauf (€) | Barchart |
| 💰weitere Preis-Informationen | Table |
| Erläuterung der Berechnung | Text |

**Energie-Abrechnung (Gas)** — beide Wohnungen, dafür ohne Verlaufs-Panels: dieselben
Stat-Panels je Wohnung (EG gemessen, OG als Differenz), zusätzlich Saldo und empfohlener
monatlicher Abschlag je Wohnung.

### Hinweise

- Der Variablenname `voumeConversionFactor` enthält einen Tippfehler (statt
  `volume…`). Er wird in allen Panels so referenziert — umbenennen nur zusammen mit allen
  `$voumeConversionFactor`-Vorkommen in der Datei.
- In den Builder-Abfragen steht unter `query` noch ein alter Abfragetext mit
  `FROM "homeassistant"."autogen"."kWh"`. Solange `rawQuery` nicht gesetzt ist, ist das
  ein folgenloser Rest: Grafana baut die Abfrage aus `measurement`, `select` und `tags`
  zusammen und fragt `m³` ab. Nur die OG-, Saldo- und Abschlags-Panels nutzen mit
  `rawQuery: true` tatsächlich eigenes InfluxQL.
- Die Abrechnungs-Dashboards lesen weiterhin aus der InfluxDB, nicht aus dem
  MariaDB-Archiv ([Archiv Metrics](../../ha-core/blueprints/archiv_metrics/)). Für eine
  Umstellung müssten die Abfragen auf SQL umgeschrieben werden.
- `energie-abrechnung_strom_wohnungEG.json` ist derzeit eine leere Datei — der
  Strom-Teil ist noch nicht gebaut.

---

## Test: Archiv-Test (`ha_metrics`)

Dashboard, das die Verbindung zur Archivdatenbank `ha_metrics` prüft und zeigt, was in
der Tabelle `states` tatsächlich liegt. Gedacht als erster Test nach der Migration von
der InfluxDB-Integration auf das MariaDB-Archiv
([Archiv Metrics](../../ha-core/blueprints/archiv_metrics/)) — und danach als Werkzeug,
wenn ein Dashboard keine Daten zeigt und die Frage ist, ob es an der Abfrage oder an den
Daten liegt.

**Version: 1.0**

### Features

- Prüft in einem Panel Erreichbarkeit, Datenbankname, angemeldeten Nutzer und
  Session-Zeitzone
- Macht die Zeitzonenumrechnung sichtbar: derselbe Zeitstempel einmal roh aus der
  Datenbank, einmal von Grafana umgerechnet
- Inventar je Entity **und** Quelle — damit ist die Naht zwischen importierter Historie
  (`source = 'import'`) und laufendem Betrieb (`source = 'ha'`) direkt ablesbar
- Zeitreihe mit Entity-Auswahl per Variable, ohne fest verdrahtete `entity_id`
- Unabhängig von der Datasource-UID: der Import fragt, welche MySQL-Datasource gemeint ist

### Voraussetzungen

#### 1. Lesender Datenbanknutzer

In den Optionen des **MariaDB**-Add-ons, danach Add-on neu starten:

```yaml
logins:
  - username: grafana
    password: "STARKES_PASSWORT"
rights:
  - username: grafana
    database: ha_metrics
    privileges:
      - SELECT
```

Mehr als `SELECT` braucht Grafana nicht — ein Tippfehler in einem Panel kann dann keine
Daten verändern.

#### 2. MySQL-Datasource

**Connections > Data sources > Add new data source > MySQL** (Kern-Datasource, kein
Plugin nötig):

| Feld | Wert |
|------|------|
| Name | `HA Metrics` |
| Host URL | `core-mariadb:3306` |
| Database | `ha_metrics` |
| Username | `grafana` |
| Password | das Passwort aus Schritt 1 |
| Session timezone | `+00:00` |

**Session timezone ist der entscheidende Punkt.** Die Spalte `ts` ist ein `DATETIME(3)`
und enthält UTC — ein `DATETIME` trägt aber keine Zeitzoneninformation. Grafana
interpretiert die Werte deshalb in der Session-Zeitzone: steht die auf `+00:00`, werden
sowohl `ts` als auch der von `$__timeFilter()` erzeugte Bereich als UTC gelesen und
korrekt in die Anzeigezone umgerechnet. Fehlt die Einstellung, verschieben sich die Kurven
um den lokalen Offset — und weil der Zeitfilter mitverschoben wird, sieht das nicht nach
einem Zeitzonenfehler aus, sondern nach fehlenden Daten am Rand des Zeitbereichs.

### Installation

**Dashboards > New > Import**, den Inhalt von
[`dashboards/test/ha-metrics_test.json`](dashboards/test/ha-metrics_test.json) einfügen,
**Load**, dann unter `HA Metrics` die MySQL-Datasource wählen und **Import** klicken.

### Panels

| Panel | Abfrage | Zeitfilter |
|-------|---------|------------|
| Verbindung & Zeitzone | `VERSION()`, `DATABASE()`, `CURRENT_USER()`, `@@session.time_zone`, `UTC_TIMESTAMP()`, `NOW()` | nein |
| Zeilen im Zeitraum | `COUNT(*)` über `states` | ja |
| Entities im Archiv | `COUNT(DISTINCT entity_id)` | nein |
| Inventar: Entities und Quellen | je `entity_id` + `source`: Zeilen, erster und letzter Zeitstempel, Einheit | nein |
| Zeitreihe: `$entity` | `ts`, `entity_id`, `value` für die gewählten Entities | ja |
| Letzte 20 Rohzeilen | die 20 jüngsten Zeilen der gewählten Entities, alle Spalten | nein |

Die Panels sind so aufgeteilt, dass sich ein Fehler eingrenzen lässt: die Panels **ohne**
Zeitfilter beantworten „sind überhaupt Daten da", die **mit** Zeitfilter „findet Grafana
sie im gewählten Zeitbereich".

#### Verbindung & Zeitzone

`db_utc` und `db_session_now` müssen denselben Wert zeigen. Beide kommen als
vorformatierter Text aus der Datenbank, damit Grafana sie nicht umrechnet — der Vergleich
zeigt also die Zeitzone der Datenbanksitzung selbst. Unterscheiden sie sich, steht
**Session timezone** nicht auf `+00:00`.

#### Letzte 20 Rohzeilen

Hier steht derselbe Zeitstempel zweimal:

- `ts (UTC, roh)` — per `DATE_FORMAT` zu Text gemacht, also genau der in der Tabelle
  gespeicherte Wert
- `ts (Grafana)` — als Zeitstempel übergeben und von Grafana in die Anzeigezone
  umgerechnet

Der Abstand muss dem UTC-Offset der Anzeigezone entsprechen: in der Sommerzeit zwei
Stunden, in der Winterzeit eine. Stehen beide Spalten gleich, rechnet niemand um — dann
zeigt Grafana UTC an, und die Session-Zeitzone ist vermutlich auf die lokale Zone gesetzt.

#### Entity-Variable

Die Variable `entity` wird aus den Daten selbst gefüllt:

```sql
SELECT DISTINCT entity_id FROM states ORDER BY entity_id
```

Sie ist mehrfach auswählbar und wird in den Abfragen als `${entity:sqlstring}` eingesetzt.
Dieses Format setzt jeden Wert in Anführungszeichen und trennt mit Komma, sodass
`IN (${entity:sqlstring})` auch bei mehreren gewählten Entities gültiges SQL bleibt. Ein
einfaches `IN ($entity)` würde die Werte unquotiert einsetzen und mit einem Syntaxfehler
enden.

### Laufzeit

Die Panels ohne Zeitfilter lesen die ganze Tabelle. `COUNT(DISTINCT entity_id)` und die
beiden `DATE_FORMAT(MIN/MAX(ts))` bedienen sich am Primärschlüssel `(entity_id, ts)` und
sind schnell; das Inventar gruppiert zusätzlich nach `source` und muss dafür einmal über
alle Zeilen. Bei einem Archiv mit einigen Millionen Zeilen dauert das ein paar Sekunden,
aber nur beim Laden des Dashboards — Auto-Refresh ist bewusst ausgeschaltet.

Wird das zu langsam, liefert `information_schema` eine Schätzung ohne Tabellenzugriff:

```sql
SELECT SUM(table_rows) AS `Zeilen (Schätzung)`
FROM information_schema.partitions
WHERE table_schema = 'ha_metrics' AND table_name = 'states'
```

Bei InnoDB ist `table_rows` nur eine Schätzung, für die Größenordnung aber ausreichend.

### Schema

Zur Erinnerung, die abgefragte Tabelle:

```sql
CREATE TABLE states (
  entity_id VARCHAR(255)  NOT NULL,
  ts        DATETIME(3)   NOT NULL,                    -- immer UTC
  value     DOUBLE        NULL,                        -- numerischer Wert
  state     VARCHAR(255)  NULL,                        -- Rohzustand als Text
  unit      VARCHAR(32)   NULL,
  source    VARCHAR(16)   NOT NULL DEFAULT 'ha',       -- ha / import / manual
  PRIMARY KEY (entity_id, ts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

`value` ist `NULL`, wenn der Zustand nicht numerisch war. Die Zeitreihen-Panels fragen
deshalb `value` ab, die Rohzeilen zeigen beide Spalten.

---

## Fehlersuche

### Archiv-Test (MariaDB)

| Symptom | Ursache |
|---------|---------|
| „Save & test" meldet `Access denied for user` | Nutzer oder Passwort falsch, oder das MariaDB-Add-on wurde nach der Änderung nicht neu gestartet |
| `Unknown database 'ha_metrics'` | Datenbankname vertippt, oder die Datenbank fehlt in `databases:` des Add-ons |
| `dial tcp: lookup core-mariadb` | Grafana läuft nicht als Add-on im selben Docker-Netz — dann statt des Namens die IP des HA-Hosts und den nach außen freigegebenen Port eintragen |
| Alle Panels leer, auch „Verbindung & Zeitzone" | Datasource nicht zugewiesen: beim Import wurde unter `HA Metrics` keine Datasource gewählt |
| Nur „Zeilen im Zeitraum" ist 0, Inventar zeigt Daten | Zeitbereich des Dashboards liegt neben den Daten, oder **Session timezone** steht nicht auf `+00:00` |
| Zeitreihe leer, Rohzeilen gefüllt | Die gewählte Entity hat im Zeitbereich keine Werte, oder `value` ist `NULL` — nicht numerische Zustände landen nur in `state` |
| `Table 'ha_metrics.states' doesn't exist` | Der Tabellenname weicht ab: die Automation kann auf eine andere Tabelle schreiben, dann in allen Panels ersetzen |

### Abrechnung (InfluxDB)

| Symptom | Ursache |
|---------|---------|
| Alle Panels leer, „Datasource not found" | Die in der Datei hinterlegte Datasource-UID `df2uui6kf6oe8e` existiert in dieser Grafana-Instanz nicht |
| Import schlägt mit Schema-Fehler fehl | Die Grafana-Version kennt `dashboard.grafana.app/v2` noch nicht |
| Auswahlliste `Zähler / Gerät` ist leer | Es gibt kein Measurement `m³` — der Zähler meldet eine andere Einheit, oder die InfluxDB-Integration schreibt ihn nicht mit |
| Verbrauch ist 0, Zählerstand steht | Im gewählten Zeitraum liegt nur ein Messpunkt (oder keiner) — der `range`-Reducer braucht zwei |
| Verbrauch OG ist negativ | `gelieferte Liter` ist kleiner als der EG-Verbrauch: falscher Zeitraum oder falsche Liefermenge |
| Kosten wirken um Faktor ~4 daneben | `Preis €/l` mit einem Preis je m³ befüllt (oder umgekehrt) — die Kostenformel rechnet über Liter |

## Lizenz

MIT License
