# Climate Alarm - Temperatur & Feuchtigkeitsueberwachung

Home Assistant Blueprint zur Echtzeit-Ueberwachung von Temperatur- und Feuchtigkeitssensoren mit konfigurierbaren Normbereichen.

## Uebersicht

Dieser Blueprint ueberwacht ausgewaehlte Temperatur- und Feuchtigkeitssensoren in Echtzeit und loest Alarme aus, sobald ein Sensorwert den definierten Normbereich verlaesst. Eine konfigurierbare Hysterese verhindert Alarm-Flackern an den Grenzwerten. Temperaturalarme haben Vorrang vor Feuchtigkeitsalarmen.

## Features

- **Echtzeit-Ueberwachung**
  - Sofortige Reaktion auf Zustandsaenderungen
  - Mehrere Sensoren pro Automation moeglich
  - Getrennte Selektoren fuer Temperatur und Feuchtigkeit

- **Konfigurierbare Normbereiche**
  - Min/Max fuer Temperatur (z.B. 18-26 Grad C)
  - Min/Max fuer Feuchtigkeit (z.B. 30-70 %)
  - Ein Bereich fuer alle Sensoren je Automation
  - Fuer unterschiedliche Bereiche separate Automationen erstellen

- **Hysterese**
  - Getrennte Hysterese-Werte fuer Temperatur und Feuchtigkeit
  - Standard: 1 Grad C (Temperatur), 3 % (Feuchtigkeit)
  - Beispiel: Alarm bei >26 Grad C, Entwarnung erst bei <25 Grad C (1 Grad Hysterese)

- **Prioritaetslogik**
  - Temperaturalarme haben Vorrang vor Feuchtigkeitsalarmen
  - Bei gleichzeitigem Alarm werden nur Temperatur-Aktionen ausgefuehrt
  - Feuchtigkeitsalarme werden nachgeholt wenn der Temperaturalarm endet

- **Getrennte Aktionen fuer Alarm und Entwarnung**
  - Temperatur-Alarm Aktionen
  - Temperatur-Entwarnung Aktionen
  - Feuchtigkeits-Alarm Aktionen
  - Feuchtigkeits-Entwarnung Aktionen

- **Benachrichtigungsoptionen** (je Aktion)
  - Device Push-Benachrichtigungen (iOS/Android)
  - Notify-Entity-Auswahl (Gruppen, individuelle Entities)
  - UI-Benachrichtigungen (persistent_notification)
  - Dashboard-Anzeige via Text Helper
  - iOS: Interruption Level, Custom Sounds
  - Android: High Priority, Sticky, Custom Icons, Notification Channels

- **To-Do List Integration** (Alarm-Aktionen)
  - Action Buttons in Push-Benachrichtigungen
  - Automatisches Hinzufuegen zu To-Do Listen

- **Custom Actions**
  - Eigene Aktionen fuer jeden Alarm-/Entwarnungs-Typ
  - Template-Variablen fuer flexible Nachrichten

- **Akustischer Alarm** (Optional)
  - Automatisches Ein-/Ausschalten eines Input Boolean Helpers bei Alarm/Entwarnung
  - "Silence Alarm" Button in Push-Benachrichtigungen
  - Integration mit externen Alarmsystemen (Webhooks, Sirenen)

- **Globale Bedingungen**
  - Optionale Bedingungen fuer die gesamte Automation

## Installation

### Via Home Assistant UI

1. In Home Assistant zu **Einstellungen > Automatisierungen & Szenen > Blueprints** navigieren
2. **Blueprint importieren** klicken
3. URL eingeben:
   ```
   https://raw.githubusercontent.com/DEIN_USERNAME/homeassistant-collection/main/blueprints/climate_alarm/blueprint_climate_alarm.yaml
   ```

### Manuell

1. Datei `blueprint_climate_alarm.yaml` herunterladen
2. Nach `/config/blueprints/automation/custom/climate_alarm/` kopieren (Ordner ggf. erstellen)
3. Home Assistant neu starten oder Blueprints neu laden

## Konfiguration

### Sensor-Einstellungen

| Einstellung | Beschreibung | Standard |
|-------------|--------------|----------|
| Temperatursensoren | Sensoren mit device_class: temperature | - |
| Feuchtigkeitssensoren | Sensoren mit device_class: humidity | - |
| Temperatur Untergrenze | Minimale Temperatur in Grad C | 18 |
| Temperatur Obergrenze | Maximale Temperatur in Grad C | 26 |
| Feuchtigkeit Untergrenze | Minimale Feuchtigkeit in % | 30 |
| Feuchtigkeit Obergrenze | Maximale Feuchtigkeit in % | 70 |
| Temperatur Hysterese | Abstand fuer Temperatur-Entwarnung | 1.0 |
| Feuchtigkeits Hysterese | Abstand fuer Feuchtigkeits-Entwarnung | 3.0 |
| Akustischer Alarm Helper | Optionaler Input Boolean Helper fuer akustische Alarmsteuerung | - |

### Hysterese erklaert

```
Beispiel: Obergrenze = 26°C, Hysterese = 1°C

  27°C ─── Alarm ausloesen (> 26°C)
  26°C ─── Obergrenze
  25°C ─── Entwarnung (< 25°C = 26°C - 1°C Hysterese)

Zwischen 25°C und 26°C: Keine Zustandsaenderung (Totzone)
```

### Anwendungsbeispiele

| Anwendung | Temp Min | Temp Max | Hum Min | Hum Max | Temp Hyst. | Hum Hyst. |
|-----------|----------|----------|---------|---------|------------|-----------|
| Wohnraum | 18 | 26 | 30 | 70 | 1.0 | 3.0 |
| Kuehlschrank | 2 | 8 | - | - | 0.5 | - |
| Gefrierschrank | -22 | -16 | - | - | 1.0 | - |
| Serverraum | 18 | 27 | 20 | 60 | 1.0 | 3.0 |
| Weinkeller | 10 | 16 | 50 | 80 | 0.5 | 2.0 |

## Custom Actions

Verfuegbare Template-Variablen:

| Variable | Beschreibung |
|----------|--------------|
| `{{trigger_sensor_name}}` | Friendly Name des ausloesenden Sensors |
| `{{trigger_value}}` | Aktueller Messwert |
| `{{trigger_entity}}` | Entity ID des ausloesenden Sensors |
| `{{temp_min}}` / `{{temp_max}}` | Temperatur-Grenzwerte |
| `{{hum_min}}` / `{{hum_max}}` | Feuchtigkeits-Grenzwerte |
| `{{temp_hysteresis}}` | Temperatur-Hysterese-Wert |
| `{{hum_hysteresis}}` | Feuchtigkeits-Hysterese-Wert |
| `{{all_temp_alarm_sensors}}` | Alle Temperatursensoren im Alarm |
| `{{all_hum_alarm_sensors}}` | Alle Feuchtigkeitssensoren im Alarm |
| `{{any_temp_in_alarm}}` | Temperatursensor aktuell im Alarmbereich (true/false) |
| `{{any_hum_in_alarm}}` | Feuchtigkeitssensor aktuell im Alarmbereich (true/false) |
| `{{alarm_active_helper}}` | Entity ID des akustischen Alarm Helpers |

## Beispiel-Automatisierung

Nach dem Import des Blueprints:

1. Neue Automatisierung aus Blueprint erstellen
2. Sensoren auswaehlen
3. Normbereiche und Hysterese einstellen
4. Gewuenschte Benachrichtigungsmethoden aktivieren
5. Geraete fuer Push-Benachrichtigungen auswaehlen

## Lizenz

MIT License - siehe [LICENSE](../../LICENSE)
