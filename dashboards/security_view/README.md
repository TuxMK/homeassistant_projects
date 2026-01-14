# Sicherheits-Dashboard

Ein vollstaendiges Dashboard fuer die Sicherheitsueberwachung mit zentralen Entity-Listen.

## Features

- Alarm-Panel Steuerung (Einbruch, Feuer/CO, Leckage)
- Dynamische Entity-Listen aus `sensor.sicherheitsstatus`
- Farbcodierung je nach Status (gruen/gelb/orange/rot)
- Zentrale Pattern-Definition (keine Duplikate)

## Voraussetzungen

- Template-Sensor `sensor.sicherheitsstatus` (siehe [templates/security_status/](../../templates/security_status/))
- [auto-entities](https://github.com/thomasloven/lovelace-auto-entities) (via HACS)
- [card-mod](https://github.com/thomasloven/lovelace-card-mod) (via HACS, fuer Farbcodierung)

## Verwendung der Entity-Listen

Der Sensor `sensor.sicherheitsstatus` stellt folgende Attribute bereit:

| Attribut | Beschreibung |
|----------|--------------|
| `alarm_entities_rauch` | Liste aller Alarm-Rauch-Sensoren |
| `alarm_entities_co` | Liste aller Alarm-CO-Sensoren |
| `alarm_entities_batterie` | Liste aller Alarm-Batterie-Sensoren |
| `alarm_entities_fehler` | Liste aller Alarm-Fehler-Sensoren |
| `alarm_entities_panels` | Liste aller Alarm-Panels |

### Beispiel: auto-entities mit Entity-Liste

```yaml
type: custom:auto-entities
card:
  type: entities
filter:
  template: |
    [
    {% for e in state_attr('sensor.sicherheitsstatus', 'alarm_entities_rauch') | default([]) %}
      {"entity": "{{ e }}"}{{ "," if not loop.last else "" }}
    {% endfor %}
    ]
```

### Beispiel: Mit Farbcodierung (card-mod)

```yaml
type: custom:auto-entities
card:
  type: entities
filter:
  template: |
    [
    {% for e in state_attr('sensor.sicherheitsstatus', 'alarm_entities_batterie') | default([]) %}
      {% set color = 'green' if states(e)|float(0) > 50 else 'orange' if states(e)|float(0) > 25 else 'red' %}
      {"entity": "{{ e }}", "card_mod": {"style": ":host { --state-icon-color: {{ color }}; }"}}{{ "," if not loop.last else "" }}
    {% endfor %}
    ]
```

## Architektur

```
┌─────────────────────────────────────────────────────────────┐
│                    Dashboard (auto-entities)                 │
│  filter.template: state_attr('sensor...', 'alarm_entities_*')│
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              sensor.sicherheitsstatus                        │
│  Attribute: alarm_entities_rauch, alarm_entities_co, ...     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│           custom_templates/security_entities.jinja           │
│  Macros: alarm_rauch_sensoren(), alarm_co_sensoren(), ...    │
│  Pattern: 'co_alarm_.*_rauch', 'feueralarm_.*_smoke', ...    │
└─────────────────────────────────────────────────────────────┘
```

## Anpassung

### Neue Geraetekategorie hinzufuegen

1. Pattern in `security_entities.jinja` definieren
2. Attribut in `sensor.yaml` hinzufuegen
3. Im Dashboard referenzieren

### Schwellwerte anpassen

Die Schwellwerte fuer Farben sind im Dashboard definiert und koennen dort angepasst werden:

```yaml
# Batterie: > 50% gruen, > 25% orange, sonst rot
'green' if states(e)|float(0) > 50 else 'orange' if states(e)|float(0) > 25 else 'red'

# CO: < 30 gruen, < 50 gelb, < 100 orange, sonst rot
'green' if states(e)|float(0) < 30 else 'yellow' if states(e)|float(0) < 50 else 'orange' if states(e)|float(0) < 100 else 'red'
```

## Lizenz

MIT License
