# Entity Staleness Notifications

Home Assistant Blueprint zur Ueberwachung von Entitaeten, die seit einer konfigurierbaren Zeitspanne keine Werte mehr gemeldet haben.

## Uebersicht

Dieser Blueprint erkennt "stille Ausfaelle" von Entitaeten, indem er den Zeitpunkt des letzten Updates (`last_updated`) mit einem konfigurierbaren Schwellwert vergleicht. Entitaeten koennen ueber vordefinierte Domain-Kategorien (z.B. Umwelt, Sicherheit, Energie, Batterie) oder einzeln ausgewaehlt werden.

**Basiert auf dem Pattern von:** [Device Fault Notifications & Actions](../device_fault_notification/)

## Features

- **Domain-Kategorien zur automatischen Entity-Erkennung**
  - Umwelt / Environment (Temperatur, Luftfeuchtigkeit, Druck, CO2, VOC, Feinstaub, etc.)
  - Sicherheit / Security (Tuer, Fenster, Bewegung, Rauch, Gas, Schloss, etc.)
  - Energie / Energy (Energie, Leistung, Spannung, Strom, etc.)
  - Batterie / Battery (Batterie-Sensoren und Binary Sensoren)

- **Staleness-Erkennung**
  - Konfigurierbarer Schwellwert in Stunden (z.B. 24 = 1 Tag, 48 = 2 Tage)
  - Vergleicht `now()` mit `state.last_updated`
  - Optionale Anzeige der verstrichenen Zeit (z.B. "3h 45m ago", "2d 5h ago")

- **Flexible Entity-Auswahl**
  - Vordefinierte Domain-Kategorien (Mehrfachauswahl)
  - Individuelle Entity-Auswahl (Entities, Areas, Devices, Labels)
  - Exclude-Funktionalitaet (Entities, Areas, Devices, Labels, Hidden Entities)
  - Option zum Ausschliessen von unavailable/unknown Entitaeten

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
   https://raw.githubusercontent.com/DEIN_USERNAME/homeassistant-collection/main/blueprints/entity_staleness_notification/blueprint_entity_staleness_notification.yaml
   ```

### Manuell

1. Datei `blueprint_entity_staleness_notification.yaml` herunterladen
2. Nach `/config/blueprints/automation/custom/` kopieren (Ordner ggf. erstellen)
3. Home Assistant neu starten oder Blueprints neu laden

## Konfiguration

### Domain-Kategorien

| Kategorie | Domain | Device Classes |
|-----------|--------|---------------|
| Umwelt / Environment | `sensor` | temperature, humidity, pressure, atmospheric_pressure, carbon_dioxide, carbon_monoxide, volatile_organic_compounds, volatile_organic_compounds_parts, pm1, pm10, pm25, nitrogen_dioxide, ozone, sulphur_dioxide, aqi |
| Sicherheit / Security | `binary_sensor` | door, window, motion, occupancy, vibration, tamper, smoke, gas, safety, lock |
| Sicherheit / Security | `lock` | (alle) |
| Energie / Energy | `sensor` | energy, power, voltage, current, power_factor, frequency, apparent_power, reactive_power |
| Batterie / Battery | `sensor` | battery |
| Batterie / Battery | `binary_sensor` | battery |

### Schwellwert

Der Schwellwert wird in Stunden angegeben:
- `0.5` = 30 Minuten
- `24` = 1 Tag
- `48` = 2 Tage
- `168` = 1 Woche

### Report Fields

Waehle welche Informationen in Benachrichtigungen angezeigt werden:
- Friendly Name
- Floor
- Area
- Device
- Entity ID
- Time Since Last Update

Format: `Friendly Name {Floor} (Area) [Device] - Entity ID - | 3h 45m ago`

### Unavailable/Unknown Ausschluss

Standardmaessig werden Entitaeten mit Status `unavailable` oder `unknown` ausgeschlossen. Diese haben zwar ein altes `last_updated`, sind aber aus einem anderen Grund nicht erreichbar. Diese Option kann deaktiviert werden, um auch disconnected Devices zu erkennen.

## Beispiel-Automatisierung

Nach dem Import des Blueprints:

1. Neue Automatisierung aus Blueprint erstellen
2. Trigger konfigurieren (Zeit oder Button)
3. Domain-Kategorien auswaehlen und/oder individuelle Entitaeten hinzufuegen
4. Schwellwert in Stunden festlegen
5. Benachrichtigungsmethode waehlen
6. Geraete fuer Push-Benachrichtigungen auswaehlen

## Custom Actions

Verfuegbare Template-Variablen fuer Custom Actions:

| Variable | Beschreibung |
|----------|--------------|
| `{{stale_sensors}}` | Alle stale Entitaeten mit vollstaendigen Report Fields |
| `{{stale_sensors_names}}` | Nur Friendly Names der stale Entitaeten |
| `{{stale_count}}` | Anzahl der stale Entitaeten |

## Lizenz

MIT License - siehe [LICENSE](../../LICENSE)
