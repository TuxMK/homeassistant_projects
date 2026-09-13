# Home Assistant Collection

Dieses Repository ist eine Sammlung von Blueprints, Konfigurationen, Skripten und anderen Ressourcen fuer Home Assistant Projekte.

## Projektstruktur

Oberste Ebene nach Ziel-System gegliedert:

- `ha-core/` — Inhalte der Home-Assistant-Konfiguration (Blueprints, Automationen, Templates, Dashboards, Scripts)
- `ha-plugins/` — Erweiterungen innerhalb von Home Assistant (Pyscript)
- `ha-apps/` — eigenstaendige Anwendungen neben Home Assistant (Zigbee2MQTT, Grafana)

```
/
├── ha-core/
│   ├── blueprints/                       # Home Assistant Blueprints (je Modul: blueprint_*.yaml + README.md)
│   │   ├── climate_alarm/                # Klima-/Temperatur-Alarm
│   │   ├── device_fault_notification/    # Geraetefehlererkennung (Pattern-basiert, z.B. *_fault, *_is_life_end)
│   │   ├── entity_staleness_notification/# Erkennung "stiller Ausfaelle" (kein Update seit X Stunden)
│   │   ├── low_battery/                  # Batteriewarnung
│   │   ├── archiv_metrics/               # Sensorwerte gedrosselt ins MariaDB-Langzeitarchiv (tools/: Influx-Migration)
│   │   └── archiv_partitions/            # Monatspartitionen der Archivtabelle pflegen
│   ├── custom_templates/                 # Zentrale Jinja2-Macros (security_entities.jinja)
│   ├── templates/                        # Template-Sensoren (security_status/ -> sensor.sicherheitsstatus)
│   ├── dashboards/                       # Lovelace-Dashboards (je Modul: dashboard.yaml/card.yaml + README.md)
│   │   ├── security_view/                # Vollständiges Sicherheits-Dashboard
│   │   ├── security_widget/              # Sicherheitsstatus-Widget (Link zur Detail-Ansicht)
│   │   ├── wallbox_widget/               # evcc-Wallbox (Lade-/Anschlussstatus)
│   │   ├── energy_widget/                # SENEC-Energiefluss (PV/Netz/Akku)
│   │   ├── weather_widget/               # Wetterlage (Zustand, Temperatur, Wind)
│   │   ├── temperature_widget/           # Kühl-/Gefrierschrank-Temperaturen
│   │   ├── pool_widget/                  # Pool-Temperatur und Pumpenstatus
│   │   ├── waste_widget/                 # Nächste Müllabholung
│   │   ├── statistics_widget/            # Navigation zur Statistik-/Energie-Ansicht
│   │   └── billing_widget/               # Navigation zum Abrechnungs-Dashboard
│   ├── automations/                      # Standalone-Automationen (mqtt_pulse_counter_cleanup)
│   └── scripts/
│       └── sqlite_to_mariadb/            # Recorder-Migration SQLite -> MariaDB (Python + Bash-Wrapper, im laufenden Betrieb)
├── ha-plugins/
│   └── pyscript/apps/                    # Pyscript-Apps (ha_mysql.py -> Aktion pyscript.sql_execute)
├── ha-apps/
│   ├── zigbee2mqtt/                      # Zigbee2MQTT-Konfiguration und Overrides
│   └── grafana/dashboards/               # Grafana-Dashboards (JSON, Import ueber die Grafana-UI)
│       ├── abrechnung/                   # Energie-Abrechnung je Wohnung (*_influx.json / *_mysql.json)
│       └── test/                         # Verbindungs-/Datentest gegen ha_metrics (MariaDB)
├── LICENSE                               # MIT License
└── README.md                             # Projekt-Uebersicht
```

Hinweis: Die Ordnernamen bilden die Repo-Struktur ab, **nicht** die Zielpfade in Home
Assistant. Installationspfade (`/config/blueprints/...`, `/config/pyscript/...`) bleiben
unveraendert und stehen in den jeweiligen Modul-READMEs.

## Security-Status-Subsystem

Die Sicherheitsueberwachung haengt ueber drei Ebenen zusammen — Aenderungen an den
Entity-Patterns wirken zentral:

```
ha-core/custom_templates/security_entities.jinja   Entity-Pattern (Regex-Macros: Rauch, CO, Leckage, Batterie, Fehler)
        -> ha-core/templates/security_status/sensor.yaml   sensor.sicherheitsstatus (Status + alarm_entities_* Attribute)
                -> ha-core/dashboards/security_view/dashboard.yaml   Anzeige (auto-entities liest die Attribute)
```

Konvention: In der **Fehler-Liste** wird der Zustand `unknown`/`unavailable` bewusst
ignoriert (grau statt rot) — unbekannte Melder sind kein Fehler.

## Konventionen

### Sprache
- Dokumentation: Deutsch
- Code/YAML-Kommentare: Deutsch oder Englisch
- Umlaute: In sichtbarem Text (Karten-Anzeige, Kommentare, Dokumentation) werden
  echte Umlaute (ä, ö, ü, ß) verwendet.
- Ausnahme: Technische Bezeichner bleiben unverändert bei ihrer eindeutigen
  ASCII-Schreibweise — Entity-IDs (z. B. `sensor.nachste_abholung`,
  `sensor.kuhlschrank_...`), Slugs, Datei-/Ordnernamen, CSS-Variablen. Diese
  nicht "umlautisieren".

### Dokumentation
- README.md fuer jedes Modul mit:
  - Uebersicht und Features
  - Installationsanleitung (UI und manuell)
  - Konfigurationsoptionen
  - Beispiele

### Grafana-Dashboards (`ha-apps/grafana/`)
- Gegliedert nach Zweck, nicht nach Datenquelle: `dashboards/abrechnung/` enthaelt die
  Energie-Abrechnung, `dashboards/test/` das Test-Dashboard.
- Die Datenquelle steht im Dateinamen-Suffix: `_influx` (InfluxDB, Altbestand) und
  `_mysql` (MariaDB `ha_metrics`). Beide Fassungen desselben Dashboards haben
  unterschiedliche UIDs und Titel und lassen sich parallel importieren.
- Sprachregelung: Die vorhandenen Dashboards heissen **Abrechnung**, nicht "Archiv".
  "Archiv" bezeichnet ausschliesslich die Datenhaltung — die MariaDB `ha_metrics` und
  die Blueprints `archiv_metrics`/`archiv_partitions`.
- Titel und UID stehen in der JSON-Datei (Schema v2: `spec.title` / `metadata.name`) und
  sind die Referenz fuer die Tabelle in [ha-apps/grafana/README.md](../ha-apps/grafana/README.md).

## Themenspezifische Anleitungen

- [blueprints.md](blueprints.md) — Blueprint-Konventionen und Verifikation

## Lizenz

MIT License
