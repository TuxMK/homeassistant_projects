# Device Fault Notifications

Home Assistant Blueprint zur Ueberwachung von Geraetefehlern anhand von Binary Sensor Entity-ID-Patterns.

## Uebersicht

Dieser Blueprint ueberwacht Binary Sensoren, deren Entity-IDs bestimmten Regex-Patterns entsprechen (z.B. `*_fault`, `*_error`, `*_is_life_end`), und sendet Benachrichtigungen wenn diese **nicht** im Zustand `off` sind.

**Basiert auf:** [Low Battery Notifications & Actions](https://community.home-assistant.io/t/653754) von Blacky (Home Assistant Community)

## Features

- **Regex-basierte Entity-Erkennung**
  - Konfigurierbare Patterns (z.B. `.*_fault$`, `.*_is_life_end$`, `.*_error$`)
  - Durchsucht alle `binary_sensor` Entities

- **Zustandsueberwachung**
  - Benachrichtigung wenn Sensor nicht `off` ist
  - Erkennt: `on`, `unavailable`, `unknown`

- **Benachrichtigungsoptionen**
  - Device Push-Benachrichtigungen (iOS/Android)
  - UI-Benachrichtigungen (persistent_notification)
  - Dashboard-Anzeige via Text Helper
  - iOS: Interruption Level, Custom Sounds
  - Android: High Priority, Sticky, Custom Icons, Notification Channels

- **To-Do List Integration**
  - Action Buttons in Benachrichtigungen
  - Automatisches Hinzufuegen zu To-Do Listen

- **Flexibilitaet**
  - Exclude-Funktionalitaet (Sensoren, Areas, Devices, Labels, Hidden Entities)
  - Custom Group mit separaten Patterns
  - Custom Actions fuer Sprachassistenten (Google, Alexa, TTS)
  - Global Conditions

- **Trigger-Optionen**
  - Button Helper (manueller Check)
  - Zeitbasiert mit Wochentags-Auswahl

## Installation

### Via Home Assistant UI

1. In Home Assistant zu **Einstellungen > Automatisierungen & Szenen > Blueprints** navigieren
2. **Blueprint importieren** klicken
3. URL eingeben:
   ```
   https://raw.githubusercontent.com/DEIN_USERNAME/homeassistant-collection/main/blueprints/device_fault_notifications/device_fault_notifications.yaml
   ```

### Manuell

1. Datei `device_fault_notifications.yaml` herunterladen
2. Nach `/config/blueprints/automation/custom/` kopieren (Ordner ggf. erstellen)
3. Home Assistant neu starten oder Blueprints neu laden

## Konfiguration

### Entity Patterns

Standard-Patterns (koennen angepasst werden):
```yaml
- ".*_is_life_end$"
- ".*_fault$"
- ".*_error$"
```

Diese Patterns matchen z.B.:
- `binary_sensor.waschmaschine_is_life_end`
- `binary_sensor.heizung_fault`
- `binary_sensor.sensor_error`

### Report Fields

Waehle welche Informationen in Benachrichtigungen angezeigt werden:
- Friendly Name
- Floor
- Area
- Device
- Entity ID

Format: `Friendly Name {Floor} (Area) [Device] - Entity ID`

### Sensor Selection

Drei Optionen fuer die Sensor-Auswahl:
1. **Custom Group** - Nur manuell ausgewaehlte Sensoren
2. **All Sensors** - Alle matchenden Sensoren minus Excludes
3. **All + Custom Group** - Kombination aus beiden

### Message Types

1. **All Faults** - on + unavailable + unknown
2. **Active Faults** - Nur `on` Status
3. **Unavailable/Unknown** - Nur nicht erreichbare Sensoren

## Beispiel-Automatisierung

Nach dem Import des Blueprints:

1. Neue Automatisierung aus Blueprint erstellen
2. Trigger konfigurieren (Zeit oder Button)
3. Entity Patterns anpassen falls noetig
4. Benachrichtigungsmethode waehlen
5. Geraete fuer Push-Benachrichtigungen auswaehlen

## Custom Actions

Verfuegbare Template-Variablen fuer Custom Actions:

| Variable | Beschreibung |
|----------|--------------|
| `{{all_sensors}}` | Alle Faults (on + unavailable + unknown) |
| `{{sensors}}` | Aktive Faults (on) |
| `{{unavailable_sensors}}` | Unavailable/Unknown Sensoren |
| `{{sensors_names}}` | Nur Friendly Names (aktive Faults) |
| `{{unavailable_sensors_names}}` | Nur Friendly Names (unavailable) |

Fuer Custom Group: `{{all_sensors_custom_group}}`, `{{sensors_custom_group}}`, etc.

## Lizenz

MIT License - siehe [LICENSE](../LICENSE)

Abgeleitet von "Low Battery Notifications & Actions" von Blacky.
