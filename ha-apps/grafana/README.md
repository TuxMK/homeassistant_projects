# Grafana

Grafana-Dashboards neben Home Assistant: die **Energie-Abrechnung** (Verbrauch und Kosten
je Wohnung) — jedes Dashboard einmal gegen die InfluxDB und einmal gegen die MariaDB
`ha_metrics` — und ein **Test-Dashboard**, das die MariaDB-Verbindung und den
Datenbestand prüft.

Alle Dashboards lesen nur — es wird nichts zurückgeschrieben.

## Ordnerstruktur

```
ha-apps/grafana/
└── dashboards/
    ├── abrechnung/                                         # Abrechnungs-Dashboards, je Datenquelle eine Fassung
    │   ├── energie-abrechnung_gas_influx.json              # Gas gesamt: Wohnung EG + OG, Saldo, Abschlagsempfehlung
    │   ├── energie-abrechnung_gas_mysql.json
    │   ├── energie-abrechnung_gas_wohnungEG_influx.json    # Gas nur Wohnung EG, mit Verlaufs-Panels
    │   ├── energie-abrechnung_gas_wohnungEG_mysql.json
    │   ├── energie-abrechnung_strom_wohnungEG_influx.json  # Strom nur Wohnung EG
    │   └── energie-abrechnung_strom_wohnungEG_mysql.json
    └── test/
        └── ha-metrics_test.json                            # Verbindungs- und Datentest gegen ha_metrics (MariaDB)
```

Das Suffix benennt die Datenquelle, sonst ist der Dateiname identisch:

| Suffix | Datenquelle | Stand |
|--------|-------------|-------|
| `_influx` | InfluxDB der Home-Assistant-InfluxDB-Integration | Altbestand, bleibt als Vergleich liegen, solange die InfluxDB existiert |
| `_mysql` | Tabelle `states` in `ha_metrics` (MariaDB) | aktuelle Fassung |

Beide Fassungen haben eigene UIDs und Titel und lassen sich deshalb **gleichzeitig**
importieren — das ist der einzige belastbare Weg, die Migration zu prüfen: beide
Dashboards auf denselben Zeitraum stellen und die Zahlen vergleichen.

Der Ordnername gibt die Gliederung im Repo vor, **nicht** die Ablage in Grafana — dort
werden die Dashboards über die Import-Funktion angelegt.

## Übersicht

| Datei | Titel in Grafana | UID | Datenquelle |
|-------|------------------|-----|-------------|
| [dashboards/abrechnung/energie-abrechnung_gas_influx.json](dashboards/abrechnung/energie-abrechnung_gas_influx.json) | Energie-Abrechnung (Gas) | `d2b6d939-9271-4d45-8ad1-1771804f928f` | InfluxDB |
| [dashboards/abrechnung/energie-abrechnung_gas_wohnungEG_influx.json](dashboards/abrechnung/energie-abrechnung_gas_wohnungEG_influx.json) | Energie-Abrechnung (Gas) - Wohnung EG | `a8b2c9e4-1f3d-4b3f-9b0c-6e18f6c3d4a1` | InfluxDB |
| [dashboards/abrechnung/energie-abrechnung_strom_wohnungEG_influx.json](dashboards/abrechnung/energie-abrechnung_strom_wohnungEG_influx.json) | Energie-Abrechnung (Strom) - Wohnung EG | `1c67e81e-f469-42de-91ef-a62097529c79` | InfluxDB |
| [dashboards/abrechnung/energie-abrechnung_gas_mysql.json](dashboards/abrechnung/energie-abrechnung_gas_mysql.json) | Energie-Abrechnung (Gas) [MariaDB] | `energie-abrechnung-gas-mariadb` | MySQL/MariaDB |
| [dashboards/abrechnung/energie-abrechnung_gas_wohnungEG_mysql.json](dashboards/abrechnung/energie-abrechnung_gas_wohnungEG_mysql.json) | Energie-Abrechnung (Gas) - Wohnung EG [MariaDB] | `energie-abrechnung-gas-eg-mariadb` | MySQL/MariaDB |
| [dashboards/abrechnung/energie-abrechnung_strom_wohnungEG_mysql.json](dashboards/abrechnung/energie-abrechnung_strom_wohnungEG_mysql.json) | Energie-Abrechnung (Strom) - Wohnung EG [MariaDB] | `energie-abrechnung-strom-eg-mariadb` | MySQL/MariaDB |
| [dashboards/test/ha-metrics_test.json](dashboards/test/ha-metrics_test.json) | HA Metrics - Archiv-Test | `ha-metrics-archiv-test` | MySQL/MariaDB |

Die feste UID sorgt dafür, dass ein erneuter Import derselben Datei das vorhandene
Dashboard aktualisiert (Grafana fragt nach, ob überschrieben werden soll) statt eine
zweite Kopie anzulegen.

Die sechs Abrechnungs-Dashboards liegen im **Schema v2**
(`apiVersion: dashboard.grafana.app/v2`, erzeugt mit Grafana 13.2.1); die UID steht dort
unter `metadata.name`. Eine Grafana-Version, die Schema v2 nicht kennt, lehnt den Import
ab. Das Test-Dashboard ist klassisches Schema v1 und lässt sich überall importieren.

---

## Abrechnung (InfluxDB)

Die Abrechnungs-Dashboards rechnen den Zählerstand eines Flüssiggas-Zählers in Verbrauch,
Energiemenge und Kosten um — pro Wohnung und für den im Zeitpicker gewählten
Abrechnungszeitraum. Dieser Abschnitt beschreibt die Fassungen mit dem Suffix `_influx`;
Aufbau und Rechenwege gelten unverändert auch für die `_mysql`-Fassungen.

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

Die Tabelle gilt für die Gas-Dashboards. Die Strom-Fassung kennt nur `device` und `price`
(dort der Arbeitspreis je kWh, Standardwert `0.32`) — Brennwert und Volumenumrechnung
braucht sie nicht, der Zähler zählt bereits kWh.

Die Auswahlliste für `device` kommt aus den Daten selbst:

```sql
SHOW TAG VALUES FROM "m³" WITH KEY = "entity_id"
```

Im Strom-Dashboard steht dort `FROM "kWh"` statt `FROM "m³"`.

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

**Energie-Abrechnung (Strom) - Wohnung EG** — derselbe Aufbau wie das Gas-Dashboard der
Wohnung EG, nur ohne die Umrechnungen: Zählerstand, Verbrauch und Kosten in kWh bzw. €,
je einmal als Stat-Panel und einmal im Verlauf.

### Hinweise

- Der Variablenname `voumeConversionFactor` enthält einen Tippfehler (statt
  `volume…`). Er wird in allen Panels so referenziert — umbenennen nur zusammen mit allen
  `$voumeConversionFactor`-Vorkommen in der Datei.
- In den Builder-Abfragen steht unter `query` noch ein alter Abfragetext mit
  `FROM "homeassistant"."autogen"."kWh"`. Solange `rawQuery` nicht gesetzt ist, ist das
  ein folgenloser Rest: Grafana baut die Abfrage aus `measurement`, `select` und `tags`
  zusammen und fragt `m³` ab. Nur die OG-, Saldo- und Abschlags-Panels nutzen mit
  `rawQuery: true` tatsächlich eigenes InfluxQL.
- Die `_influx`-Dateien lesen aus der InfluxDB. Die auf die MariaDB umgestellten
  Fassungen tragen dasselbe Präfix mit dem Suffix `_mysql` und sind unten beschrieben.

---

## Abrechnung (MariaDB `ha_metrics`)

Die drei `_mysql`-Dashboards in [`dashboards/abrechnung/`](dashboards/abrechnung/) sind die
auf SQL umgestellten Fassungen der oben beschriebenen Abrechnung. Aufbau, Layout,
Variablen, Einheiten und Rechenwege sind unverändert — getauscht ist nur die Datenquelle:
statt `m³`/`kWh`-Measurements der InfluxDB lesen sie die Tabelle `states` in `ha_metrics`
([Archiv Metrics](../../ha-core/blueprints/archiv_metrics/)).

**Version: 1.0**

### Installation

**Dashboards > New > Import**, den Inhalt der JSON-Datei einfügen, **Load**, **Import**.

Schema v2 kennt keinen Import-Dialog für Datasources, die UID steht deshalb fest in den
Dateien — eingetragen ist `afy0tg4a3q0hsc`, die MySQL-Datasource auf `ha_metrics`. In
einer anderen Grafana-Instanz ist das eine andere UID; sie steht in der URL der Datasource
(**Connections > Data sources >** die MySQL-Datasource anklicken):
`/connections/datasources/edit/<UID>`. Ersetzen dann so:

```bash
sed -i 's/afy0tg4a3q0hsc/neue-uid/g' \
    ha-apps/grafana/dashboards/abrechnung/*_mysql.json
```

Passt die UID nicht, melden alle Panels „Datasource not found".

Voraussetzung ist dieselbe MySQL-Datasource wie beim Test-Dashboard, insbesondere
**Session timezone `+00:00`** — siehe unten. Ohne das verschiebt sich der Zeitraum des
Zeitpickers gegen die Daten, und eine Jahresabrechnung rechnet mit einem um eine bis zwei
Stunden verschobenen Fenster.

### Die drei Abfrageformen

Alle Panels verwenden eine von drei Formen. Gemeinsam ist ihnen der Filter auf eine
Entity und den Zeitraum des Zeitpickers.

**1. Zählerstand als Zeitreihe** — für alle Stat- und Timeseries-Panels:

```sql
SELECT $__timeGroupAlias(ts, $__interval),
       MAX(value) * $voumeConversionFactor * $price AS `€`
FROM states
WHERE entity_id = '$device'
  AND $__timeFilter(ts)
GROUP BY time
ORDER BY time
```

Die Differenz „Ende − Anfang" macht weiterhin der Reducer des Panels (`range` für
Verbrauch, `lastNotNull` für Zählerstand), genau wie bei der InfluxDB-Fassung. Die
Panel-Paare liegen deshalb auch hier auf identischem SQL und unterscheiden sich nur in
dieser Einstellung.

`MAX(value)` je Bucket entspricht bei einem monoton steigenden Zähler dem letzten Wert des
Buckets. Das ist der Grund, warum `range` und `lastNotNull` hier exakt rechnen — anders als
über `AVG`, das den ersten Bucket zu hoch und den letzten zu tief ansetzt.

**2. Verbrauch je Zeitabschnitt** — für die Balken-Panels „… im Verlauf":

```sql
SELECT bucket AS time,
       (reading - LAG(reading) OVER (ORDER BY bucket)) * $heatingValue AS `Verbrauch (kWh)`
FROM (
  SELECT $__timeGroup(ts, $__interval) AS bucket,
         MAX(value)                    AS reading
  FROM states
  WHERE entity_id = '$device'
    AND $__timeFilter(ts)
  GROUP BY bucket
) b
ORDER BY bucket
```

`LAG()` liefert den Zählerstand des vorherigen Buckets, die Differenz also den Verbrauch
in diesem Abschnitt. Der erste Balken bleibt leer — vor dem ersten Messpunkt gibt es
keinen Verbrauch zu berechnen. Die Anzahl der Balken steuert wie vorher
`maxDataPoints: 24` am Panel, die Balkenbreite ist damit ein Vierundzwanzigstel des
Zeitraums.

**3. Ein einzelner Wert** — Grundlage der OG-, Saldo- und Abschlags-Panels im
Gesamt-Dashboard:

```sql
SELECT MAX(ts) AS time,
       (MAX(value) - MIN(value)) * $voumeConversionFactor AS `verbrauch_eg_liter`
FROM states
WHERE entity_id = '$device'
  AND $__timeFilter(ts)
```

Das entspricht dem `last("value") - first("value")` der InfluxQL-Fassung. `MAX(ts)` hält
das Ergebnis als Zeitreihe mit einem Punkt, damit die nachgelagerten
`__expr__`-Berechnungen (`$delivered_liters - $A` usw.) **unverändert** weiterrechnen — die
sind nicht angetastet worden.

### Was sich gegenüber der InfluxDB-Fassung ändert

| Punkt | InfluxDB | MariaDB |
|-------|----------|---------|
| `entity_id` | ohne Domain (`gaszahler_…`) | mit Domain (`sensor.gaszahler_…`) |
| Auswahlliste `device` | `SHOW TAG VALUES FROM "m³"` | `SELECT DISTINCT entity_id FROM states WHERE unit = 'm³'` |
| Einheit | steckt im Measurement-Namen | steht in der Spalte `unit` |
| Bucket-Wert | `mean` bzw. `last` | `MAX(value)` |
| Auto-Refresh | jede Minute | aus |

Die **Auswahlliste** hängt jetzt an der Spalte `unit`. Bleibt sie leer, führt die
Archivierungs-Automation für diesen Zähler keine Einheit mit; dann hilft ein Blick ins
Inventar-Panel des [Test-Dashboards](#test-dashboard-ha_metrics) und ersatzweise ein
Filter über den Namen:

```sql
SELECT DISTINCT entity_id FROM states WHERE entity_id LIKE '%gas%' ORDER BY entity_id
```

**Auto-Refresh ist ausgeschaltet.** Eine Abrechnung über ein ganzes Jahr liest je Panel
einen zusammenhängenden Bereich des Primärschlüssels — bei 14 Panels und
Minutentakt wäre das dauerhafte Last auf der MariaDB des HA-Hosts, für Daten, die sich
im Abrechnungszeitraum nicht mehr ändern. Wer den Takt zurück will, setzt
`timeSettings.autoRefresh` wieder auf `1m`.

### Der Stolperstein: alles, was auf Feldnamen zeigt

Die Felder heißen jetzt anders. InfluxDB benannte sie nach Measurement und
Aggregatfunktion — `kWh.mean`, `m³.last` —, das SQL benennt sie über den Alias der Spalte:
`kWh`, `l`, `€`, `Verbrauch (m³)`. Jede Einstellung, die einen Feldnamen **nennt**, zeigt
nach der Umstellung ins Leere. Bei Transformationen bleibt das Panel dann einfach leer,
bei Overrides greift die Regel plötzlich auf die falschen Serien.

Betroffen waren zwei Stellen, beide sind entfernt:

- **Die `calculateField`-Transformation der Balken-Panels.** Sie stand im Modus
  `windowFunctions` mit Reducer `stdDev` über ein 10-%-Fenster und berechnete damit eine
  gleitende Standardabweichung des Zählerstands — nicht den Verbrauch, den der
  Panel-Titel verspricht. Den liefert jetzt `LAG()` direkt aus dem SQL. Ihre Felder
  (`m³.last`, `kWh.last`) hätte sie ohnehin nicht mehr gefunden.
- **Der Override `hideSeriesFrom` in acht Panels.** Den legt Grafana an, wenn man in der
  Legende „alle außer dieser Serie ausblenden" klickt; er lautet wörtlich *alle Serien
  außer `kWh.mean` ausblenden*. Da nun keine Serie mehr so heißt, fiel die einzige
  vorhandene selbst unter „alle außer" und wurde per `hideFrom.viz` versteckt — die
  beiden „Zählerstand im Verlauf"-Panels des Strom-Dashboards zeigten deshalb eine leere
  Fläche. In den sechs Balken-Panels war derselbe Override wirkungslos, weil dort keine
  Eigenschaften gesetzt waren; entfernt sind sie trotzdem alle, sonst tritt man in
  dieselbe Falle beim nächsten Umbenennen.

Dazu ein Rechenfehler, der keine Folge des Datenbankwechsels ist:
- **„Kosten im Verlauf (€)" im Gas-Dashboard rechnet jetzt vollständig.** Dort stand als
  Faktor nur `* $price`, während alle anderen Kosten-Panels `* $voumeConversionFactor *
  $price` verwenden. Auf einem Zählerstand in m³ fehlte damit die Umrechnung in Liter,
  die Balken lagen um den Faktor 3,94 zu niedrig. Jetzt ist die Formel dieselbe wie in
  den Stat-Panels.

### Prüfen nach dem Import

Die `_influx`- und die `_mysql`-Fassung vertragen sich, weil UID und Titel verschieden
sind. Für den Vergleich beide auf **denselben** Zeitraum stellen und die Stat-Panels
gegenüberstellen:

- **Zählerstand** muss auf beiden Seiten gleich sein.
- **Gesamtverbrauch** darf minimal abweichen — die MariaDB-Fassung rechnet über `MAX`
  exakt, die InfluxDB-Fassung über `mean` leicht zu knapp. Die neue Zahl ist die richtige.
- **Verbrauch im Verlauf** sieht anders aus, und das ist beabsichtigt: vorher eine
  Standardabweichung, jetzt der Verbrauch.

Zeigt die `_mysql`-Fassung nichts, liegt es fast immer an einem von drei Dingen: einer
nicht passenden Datasource-UID, der Session-Zeitzone, oder daran dass der Zähler gar nicht
in `ha_metrics` steht — Letzteres beantwortet das Inventar-Panel des Test-Dashboards.

---

## Test-Dashboard (`ha_metrics`)

Dashboard, das die Verbindung zur Datenbank `ha_metrics` prüft und zeigt, was in
der Tabelle `states` tatsächlich liegt (Titel in Grafana: *HA Metrics - Archiv-Test*).
Gedacht als erster Test nach der Migration von der InfluxDB-Integration auf MariaDB
([Archiv Metrics](../../ha-core/blueprints/archiv_metrics/)) — und danach als Werkzeug,
wenn ein Abrechnungs-Dashboard keine Daten zeigt und die Frage ist, ob es an der Abfrage
oder an den Daten liegt.

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
alle Zeilen. Bei einer Tabelle mit einigen Millionen Zeilen dauert das ein paar Sekunden,
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
  ts        DATETIME(3)   NOT NULL,                    -- always UTC
  value     DOUBLE        NULL,                        -- numeric value
  state     VARCHAR(255)  NULL,                        -- raw state as text
  unit      VARCHAR(32)   NULL,
  source    VARCHAR(16)   NOT NULL DEFAULT 'ha',       -- ha / import / manual
  PRIMARY KEY (entity_id, ts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

`value` ist `NULL`, wenn der Zustand nicht numerisch war. Die Zeitreihen-Panels fragen
deshalb `value` ab, die Rohzeilen zeigen beide Spalten.

---

## Fehlersuche

### Test-Dashboard (MariaDB)

| Symptom | Ursache |
|---------|---------|
| „Save & test" meldet `Access denied for user` | Nutzer oder Passwort falsch, oder das MariaDB-Add-on wurde nach der Änderung nicht neu gestartet |
| `Unknown database 'ha_metrics'` | Datenbankname vertippt, oder die Datenbank fehlt in `databases:` des Add-ons |
| `dial tcp: lookup core-mariadb` | Grafana läuft nicht als Add-on im selben Docker-Netz — dann statt des Namens die IP des HA-Hosts und den nach außen freigegebenen Port eintragen |
| Alle Panels leer, auch „Verbindung & Zeitzone" | Datasource nicht zugewiesen: beim Import wurde unter `HA Metrics` keine Datasource gewählt |
| Nur „Zeilen im Zeitraum" ist 0, Inventar zeigt Daten | Zeitbereich des Dashboards liegt neben den Daten, oder **Session timezone** steht nicht auf `+00:00` |
| Zeitreihe leer, Rohzeilen gefüllt | Die gewählte Entity hat im Zeitbereich keine Werte, oder `value` ist `NULL` — nicht numerische Zustände landen nur in `state` |
| `Table 'ha_metrics.states' doesn't exist` | Der Tabellenname weicht ab: die Automation kann auf eine andere Tabelle schreiben, dann in allen Panels ersetzen |

### Abrechnung (MariaDB)

| Symptom | Ursache |
|---------|---------|
| Alle Panels „Datasource not found" | Die in der Datei hinterlegte UID `afy0tg4a3q0hsc` existiert in dieser Grafana-Instanz nicht |
| Auswahlliste `Zähler / Gerät` ist leer | Kein Eintrag mit `unit = 'm³'` bzw. `'kWh'` in `ha_metrics` — Einheit prüfen, ersatzweise über den Namen filtern |
| Alle Panels leer, Liste aber gefüllt | Der gewählte Zähler steht nicht in `ha_metrics`, oder der Zeitraum liegt neben den Daten |
| Verbrauch 0, Zählerstand steht | Im Zeitraum liegt nur ein Messpunkt — `range` braucht zwei |
| Werte um eine bis zwei Stunden verschoben | **Session timezone** der Datasource steht nicht auf `+00:00` |
| Erster Balken im Verlauf fehlt | So gewollt: vor dem ersten Messpunkt gibt es keinen Vorgänger für `LAG()` |
| Ein Timeseries-Panel bleibt leer, die Abfrage liefert aber Daten (Panel > Inspect > Data) | Ein Override blendet die Serie aus: im Panel-Editor unter **Overrides** einen Eintrag „All except: …" suchen und löschen. Er nennt einen Feldnamen, den es nach der Umstellung nicht mehr gibt |
| `You have an error in your SQL syntax` beim Speichern einer Variablen | Ein Textfeld wie `Preis €/l` ist leer — es wird direkt in die Abfrage eingesetzt |

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
