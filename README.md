# Home Assistant Collection

Eine Sammlung von Blueprints, Konfigurationen, Skripten und anderen Ressourcen aus meinen Home Assistant Projekten.

## Inhalt

### Blueprints

| Name | Beschreibung |
|------|--------------|
| [Device Fault Notifications](blueprints/device_fault_notifications/) | Benachrichtigungen bei Geraetefehlern (basierend auf Binary Sensor Patterns) |
| [Climate Alarm](blueprints/climate_alarm/) | Echtzeit-Temperatur- & Feuchtigkeitsueberwachung mit Normbereichen, Hysterese und Prioritaetslogik |

### Custom Templates

| Name | Beschreibung |
|------|--------------|
| [Security Entities](custom_templates/) | Zentrale Jinja2-Macros fuer Sicherheits-Entity-Pattern |

### Templates

| Name | Beschreibung |
|------|--------------|
| [Security Status](templates/security_status/) | Template-Sensor der alle Sicherheits-Entitaeten ueberwacht und einen Gesamtstatus liefert |

### Dashboards

| Name | Beschreibung |
|------|--------------|
| [Security View](dashboards/security_view/) | Vollständiges Sicherheits-Dashboard mit dynamischen Entity-Listen |
| [Security Widget](dashboards/security_widget/) | Kompaktes Widget für das Übersichts-Dashboard mit Sicherheitsstatus und Link zur Detail-Ansicht |
| [Wallbox Widget](dashboards/wallbox_widget/) | evcc-Wallbox: Lade-/Anschlussstatus, SoC, Ladeziel und PV-Anteil |
| [Energy Widget](dashboards/energy_widget/) | SENEC-Energiefluss: PV-Erzeugung, Netzbezug/-einspeisung und Akku-Ladestand |
| [Weather Widget](dashboards/weather_widget/) | Aktuelle Wetterlage (Zustand, Temperatur, Wind) mit passendem Icon |
| [Temperature Widget](dashboards/temperature_widget/) | Temperaturen der Kühl-/Gefrierschränke mit Schwellwert-Farbe |
| [Pool Widget](dashboards/pool_widget/) | Pool-Temperatur und Pumpenstatus |
| [Waste Widget](dashboards/waste_widget/) | Nächste Müllabholung mit Abfallart-Icon und Link zum Abfallkalender |
| [Statistics Widget](dashboards/statistics_widget/) | Navigations-Button zur Statistik-/Energie-Ansicht |
| [Billing Widget](dashboards/billing_widget/) | Navigations-Button zum Abrechnungs-Dashboard (Strom & Gas) |

### Zigbee2MQTT

| Name | Beschreibung |
|------|--------------|
| [External Converters](zigbee2mqtt/) | Angepasste Geraete-Definitionen zur Vermeidung von Binding Table Overflow bei EFR32MG21-basierten Coordinatoren |

---

## Installation

### Blueprints

1. In Home Assistant zu **Einstellungen > Automatisierungen & Szenen > Blueprints** navigieren
2. **Blueprint importieren** klicken
3. Die Raw-URL des gewuenschten Blueprints eingeben

Oder manuell die YAML-Datei nach `/config/blueprints/automation/` kopieren.

---

## Lizenz

Dieses Repository steht unter der [MIT License](LICENSE).

Einige Blueprints basieren auf Community-Beitraegen. Die entsprechenden Quellenangaben sind in den jeweiligen Dateien vermerkt.

---

## Mitwirken

Fehler gefunden oder Verbesserungsvorschlaege? Issues und Pull Requests sind willkommen.
