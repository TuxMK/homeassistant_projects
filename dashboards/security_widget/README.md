# Sicherheits-Widget fuer Dashboard

Ein kompaktes Widget das den Sicherheitsstatus anzeigt und auf die Sicherheits-Ansicht verlinkt.

## Features

- Dynamische Statusanzeige (Sicher/Warnung/Alarm)
- Farbcodierung (Gruen/Orange/Rot)
- Klick-Navigation zur Sicherheits-Ansicht
- 5 verschiedene Varianten verfuegbar
- Funktioniert mit Standard Home Assistant Karten

## Voraussetzung

Der Template-Sensor `sensor.sicherheitsstatus` muss eingerichtet sein.
Siehe: [templates/security_status/](../../templates/security_status/)

## Varianten

### Variante 1: Markdown-Karte (empfohlen)

Kompakte Anzeige mit Icon und Status-Text. Funktioniert ohne zusaetzliche Custom Cards.

```yaml
type: markdown
content: >
  {% set status = states('sensor.sicherheitsstatus') %}
  {% set alarm_count = state_attr('sensor.sicherheitsstatus', 'alarm_count') | int(0) %}
  {% set warning_count = state_attr('sensor.sicherheitsstatus', 'warning_count') | int(0) %}

  {% if status == 'Alarm' %}
  <ha-icon icon="mdi:shield-alert" style="color: var(--error-color, red);"></ha-icon>
  **{{ alarm_count }} Alarm{{ 'e' if alarm_count != 1 else '' }}**
  {% elif status == 'Warnung' %}
  <ha-icon icon="mdi:shield-half-full" style="color: var(--warning-color, orange);"></ha-icon>
  **{{ warning_count }} Warnung{{ 'en' if warning_count != 1 else '' }}**
  {% else %}
  <ha-icon icon="mdi:shield-check" style="color: var(--success-color, green);"></ha-icon>
  **Alles sicher**
  {% endif %}
tap_action:
  action: navigate
  navigation_path: /lovelace/sicherheit
```

### Variante 2: Tile-Karte (modern)

Moderner Look mit der Tile-Karte (ab HA 2023.3):

```yaml
type: tile
entity: sensor.sicherheitsstatus
name: Sicherheit
color: >
  {% if is_state('sensor.sicherheitsstatus', 'Alarm') %}
    red
  {% elif is_state('sensor.sicherheitsstatus', 'Warnung') %}
    orange
  {% else %}
    green
  {% endif %}
tap_action:
  action: navigate
  navigation_path: /lovelace/sicherheit
```

### Variante 3: Button-Karte

Kompakter Button, ideal fuer Grid-Layouts:

```yaml
type: button
entity: sensor.sicherheitsstatus
name: Sicherheit
show_state: true
tap_action:
  action: navigate
  navigation_path: /lovelace/sicherheit
```

### Variante 4: Entities-Karte

Einfache Zeile in einer Entities-Karte:

```yaml
type: entities
entities:
  - entity: sensor.sicherheitsstatus
    name: Sicherheit
    tap_action:
      action: navigate
      navigation_path: /lovelace/sicherheit
```

### Variante 5: Detaillierte Karte

Zeigt auch die Problemliste an:

```yaml
type: markdown
content: >
  {% set details = state_attr('sensor.sicherheitsstatus', 'details') | default([]) %}

  ## Sicherheitsstatus

  {% for issue in details %}
  - {{ issue }}
  {% endfor %}

  {% if not details %}
  Alle Sensoren OK
  {% endif %}
tap_action:
  action: navigate
  navigation_path: /lovelace/sicherheit
```

## Installation

1. Template-Sensor einrichten (siehe [templates/security_status/](../../templates/security_status/))

2. Dashboard im UI-Editor oeffnen

3. Neue Karte hinzufuegen → "Manuell" waehlen

4. YAML-Code einer Variante einfuegen

5. Navigation-Pfad anpassen falls noetig:
   ```yaml
   navigation_path: /lovelace/sicherheit  # Standard
   navigation_path: /dashboard-name/sicherheit  # Bei benutzerdefiniertem Dashboard-URL
   ```

## Anpassung

### Navigation-Pfad

Der Pfad zur Sicherheits-Ansicht kann angepasst werden:

```yaml
tap_action:
  action: navigate
  navigation_path: /lovelace/sicherheit
```

### Farben

Die Farben nutzen CSS-Variablen von Home Assistant:
- `var(--error-color, red)` - Rot fuer Alarm
- `var(--warning-color, orange)` - Orange fuer Warnung
- `var(--success-color, green)` - Gruen fuer Sicher

### Grid-Groesse

Bei Tile- oder Markdown-Karten kann die Groesse angepasst werden:

```yaml
grid_options:
  columns: 2  # Breite (1-4)
  rows: 1     # Hoehe
```

## Screenshots

### Status: Sicher
```
🛡️ Alles sicher
```

### Status: Warnung
```
⚠️ 1 Warnung
```

### Status: Alarm
```
🚨 2 Alarme
```

## Lizenz

MIT License
