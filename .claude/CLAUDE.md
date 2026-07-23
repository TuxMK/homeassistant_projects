# Home Assistant Collection

Dieses Repository ist eine Sammlung von Blueprints, Konfigurationen, Skripten und anderen Ressourcen fuer Home Assistant Projekte.

## Projektstruktur

```
/
├── blueprints/                       # Home Assistant Blueprints (je Modul: blueprint_*.yaml + README.md)
│   ├── climate_alarm/                # Klima-/Temperatur-Alarm
│   ├── device_fault_notification/    # Geraetefehlererkennung (Pattern-basiert, z.B. *_fault, *_is_life_end)
│   ├── entity_staleness_notification/# Erkennung "stiller Ausfaelle" (kein Update seit X Stunden)
│   └── low_battery/                  # Batteriewarnung
├── custom_templates/                 # Zentrale Jinja2-Macros (security_entities.jinja)
├── templates/                        # Template-Sensoren (security_status/ -> sensor.sicherheitsstatus)
├── dashboards/                       # Lovelace-Dashboards (je Modul: dashboard.yaml/card.yaml + README.md)
│   ├── security_view/                # Vollständiges Sicherheits-Dashboard
│   ├── security_widget/              # Sicherheitsstatus-Widget (Link zur Detail-Ansicht)
│   ├── wallbox_widget/               # evcc-Wallbox (Lade-/Anschlussstatus)
│   ├── energy_widget/                # SENEC-Energiefluss (PV/Netz/Akku)
│   ├── weather_widget/               # Wetterlage (Zustand, Temperatur, Wind)
│   ├── temperature_widget/           # Kühl-/Gefrierschrank-Temperaturen
│   ├── pool_widget/                  # Pool-Temperatur und Pumpenstatus
│   ├── waste_widget/                 # Nächste Müllabholung
│   ├── statistics_widget/            # Navigation zur Statistik-/Energie-Ansicht
│   └── billing_widget/               # Navigation zum Abrechnungs-Dashboard
├── automations/                      # Standalone-Automationen (mqtt_pulse_counter_cleanup)
├── zigbee2mqtt/                      # Zigbee2MQTT-Konfiguration und Overrides
├── LICENSE                           # MIT License
└── README.md                         # Projekt-Uebersicht
```

## Security-Status-Subsystem

Die Sicherheitsueberwachung haengt ueber drei Ebenen zusammen — Aenderungen an den
Entity-Patterns wirken zentral:

```
custom_templates/security_entities.jinja   Entity-Pattern (Regex-Macros: Rauch, CO, Leckage, Batterie, Fehler)
        -> templates/security_status/sensor.yaml   sensor.sicherheitsstatus (Status + alarm_entities_* Attribute)
                -> dashboards/security_view/dashboard.yaml   Anzeige (auto-entities liest die Attribute)
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

## Themenspezifische Anleitungen

- [blueprints.md](blueprints.md) — Blueprint-Konventionen und Verifikation

## Lizenz

MIT License
