# Sicherheitsstatus Template-Sensor

Ein Template-Sensor der alle sicherheitsrelevanten Entitaeten ueberwacht und einen Gesamtstatus zurueckgibt.

## Features

- Ueberwacht Alarm-Panels (Einbruch, Feuer/CO, Leckage)
- Erkennt aktive Rauch- und CO-Alarme
- Prueft Batteriestatus aller Sicherheitssensoren
- Erkennt Sensor-Fehler (life_end, fault)
- Gibt Gesamtstatus zurueck: "Sicher", "Warnung" oder "Alarm"
- Detaillierte Attribute mit Problemliste

## Ueberwachte Entitaeten

| Kategorie | Entity-Pattern | Schwellwerte |
|-----------|----------------|--------------|
| Alarm-Panels | `alarm_control_panel.alarm_zentrale` | triggered/pending = Alarm |
| | `alarm_control_panel.feuer_co_alarm` | |
| | `alarm_control_panel.leckage_alarm` | |
| Rauch-Sensoren | `binary_sensor.co_alarm_*_rauch` | on = Alarm |
| | `binary_sensor.feueralarm_*_smoke` | |
| | `binary_sensor.feueralarm_*_rauch` | |
| CO-Sensoren | `sensor.co_alarm_*_kohlenmonoxid` | >= 100 ppm = Alarm |
| | | >= 30 ppm = Warnung |
| Batterie | `sensor.co_alarm_*_batterie` | < 10% = Alarm |
| | `sensor.feueralarm_*_battery` | < 25% = Warnung |
| | `sensor.feueralarm_*_batterie` | |
| Fehler | `binary_sensor.co_alarm_*_is_life_end` | on = Alarm |
| | `binary_sensor.feueralarm_*_fault` | |

## Sensor-Attribute

| Attribut | Beschreibung | Beispiel |
|----------|--------------|----------|
| `alarm_count` | Anzahl kritischer Probleme | `2` |
| `warning_count` | Anzahl Warnungen | `1` |
| `details` | Liste aller Probleme | `['Batterie niedrig: Rauchmelder (15%)']` |
| `alarm_zentrale` | Status der Alarm-Zentrale | `disarmed` |
| `feuer_co_alarm` | Status Feuer/CO-Alarm | `armed_home` |
| `leckage_alarm` | Status Leckage-Alarm | `armed_home` |

## Installation

### Methode 1: Include (empfohlen)

1. Datei `sensor.yaml` in den Home Assistant Konfigurationsordner kopieren:
   ```
   config/
   └── templates/
       └── security_status/
           └── sensor.yaml
   ```

2. In `configuration.yaml` einbinden:
   ```yaml
   template: !include templates/security_status/sensor.yaml
   ```

3. Home Assistant neu starten

### Methode 2: Direkt in configuration.yaml

Den Inhalt von `sensor.yaml` (ohne die Kommentare am Anfang) direkt unter `template:` in der `configuration.yaml` einfuegen:

```yaml
template:
  - sensor:
      - name: "Sicherheitsstatus"
        unique_id: security_status_overview
        # ... Rest des Codes
```

## Anpassung

### Eigene Entitaeten hinzufuegen

Die Regex-Pattern in den `selectattr`-Filtern koennen angepasst werden:

```yaml
# Beispiel: Zusaetzliche Wassersensoren
{% for entity in states.binary_sensor | selectattr('entity_id', 'search', 'water_leak') %}
```

### Schwellwerte aendern

Die Schwellwerte fuer CO und Batterie sind direkt im Template definiert:

```yaml
# CO-Schwellwerte (in ppm)
{% if co_value >= 100 %}  # Alarm
{% elif co_value >= 30 %} # Warnung

# Batterie-Schwellwerte (in %)
{% if battery < 10 %}   # Alarm
{% elif battery < 25 %} # Warnung
```

## Verwendung

Der Sensor erscheint als `sensor.sicherheitsstatus` und kann in Automationen, Dashboards und Skripten verwendet werden.

### Beispiel-Automation

```yaml
automation:
  - alias: "Sicherheitswarnung senden"
    trigger:
      - platform: state
        entity_id: sensor.sicherheitsstatus
        to: "Warnung"
    action:
      - service: notify.mobile_app
        data:
          title: "Sicherheitswarnung"
          message: >
            {{ state_attr('sensor.sicherheitsstatus', 'details') | join(', ') }}
```

## Lizenz

MIT License
