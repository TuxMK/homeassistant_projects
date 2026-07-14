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
├── dashboards/                       # Lovelace-Dashboards (security_view, security_widget)
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
- Umlaute in Dateien werden als ae, oe, ue geschrieben

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
