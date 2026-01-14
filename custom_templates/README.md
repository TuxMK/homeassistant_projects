# Custom Templates - Zentrale Entity-Definitionen

Dieses Verzeichnis enthaelt Jinja2-Macros fuer die zentrale Verwaltung von Entity-Patterns.

## Uebersicht

| Datei | Beschreibung |
|-------|--------------|
| `security_entities.jinja` | Entity-Pattern fuer Sicherheitsgeraete (Rauch, CO, Batterie, Fehler) |

## Installation

1. Den Ordner `custom_templates` nach `/config/custom_templates/` kopieren

2. Home Assistant neu starten

3. Die Macros koennen nun in Templates verwendet werden

## Verwendung

### In Template-Sensoren

```yaml
template:
  - sensor:
      - name: "Mein Sensor"
        state: >
          {% from 'security_entities.jinja' import alarm_rauch_sensoren %}
          {% for entity_id in alarm_rauch_sensoren() | from_json %}
            {{ states(entity_id) }}
          {% endfor %}
```

### In Automationen

```yaml
automation:
  - alias: "Rauch erkannt"
    trigger:
      - platform: template
        value_template: >
          {% from 'security_entities.jinja' import alarm_rauch_sensoren %}
          {% for entity_id in alarm_rauch_sensoren() | from_json %}
            {% if states(entity_id) == 'on' %}true{% endif %}
          {% endfor %}
```

### In Dashboard-Cards (mit auto-entities)

Da auto-entities keine Jinja2-Imports unterstuetzt, nutze stattdessen die Sensor-Attribute:

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

Siehe [dashboards/security_view/](../dashboards/security_view/) fuer vollstaendige Beispiele.

## Verfuegbare Macros (security_entities.jinja)

| Macro | Beschreibung | Gibt zurueck |
|-------|--------------|--------------|
| `alarm_rauch_sensoren()` | Alarm-Rauch-Sensoren (CO-Alarm, Feueralarm) | Liste von entity_ids |
| `alarm_co_sensoren()` | Alarm-CO-Messwert-Sensoren | Liste von entity_ids |
| `alarm_batterie_sensoren()` | Alarm-Batterie-Sensoren der Sicherheitsgeraete | Liste von entity_ids |
| `alarm_fehler_sensoren()` | Alarm-Fehler-Sensoren (life_end, fault) | Liste von entity_ids |
| `alarm_panels()` | Alarm-Panels (die Alarm-Zentralen) | Liste von entity_ids |
| `alarm_alle_sensoren()` | Alle Alarm-Sensoren kombiniert | Liste von entity_ids |

## Eigene Macros hinzufuegen

Neue Kategorien koennen einfach hinzugefuegt werden:

```jinja
{# Alarm-Wasser-Sensoren #}
{% macro alarm_wasser_sensoren() %}
{{ states.binary_sensor
   | selectattr('entity_id', 'search', 'water_leak')
   | map(attribute='entity_id')
   | list
   | to_json }}
{% endmacro %}
```

## Wichtige Hinweise

- Macros geben JSON-Strings zurueck, daher `| from_json` beim Aufruf verwenden
- Pattern werden als Regex interpretiert (`.` = beliebiges Zeichen, `.*` = beliebig viele)
- Neue Geraete die dem Pattern entsprechen werden automatisch erkannt

## Lizenz

MIT License
