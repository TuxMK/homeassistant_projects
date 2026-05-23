# Low Battery Notifications & Actions (Fork)

Home Assistant Blueprint zur Ueberwachung niedriger Batteriestaende mit zusaetzlicher Option, Akkus von getrackten Geraeten (Phones, Tablets, Watches, etc.) automatisch auszuschliessen.

**Basiert auf:** [Low Battery Notifications & Actions v3.4](https://gist.github.com/Blackshome/4010fb83bb8c19b5fa1425526c6ff0e2) von Blacky (Home Assistant Community)

**Fork-Version:** 3.4-fork-1

## Was ist neu in diesem Fork

Der Original-Blueprint bietet bereits drei Ausschlussmechanismen:

- `exclude_sensors` — einzelne Entities/Devices/Areas/Labels
- `exclude_hidden_entities` — alle versteckten Battery-Sensoren

Dieser Fork ergaenzt eine vierte, dynamische Option:

### `exclude_device_tracker_batteries`

Wenn aktiviert, werden alle `device_class: battery` Sensoren automatisch ausgeschlossen, deren Geraet (Device Registry) auch mindestens eine Entity in der Domain `device_tracker` besitzt.

**Typischer Anwendungsfall:** Akkustaende von User-Geraeten (Companion-App-Phones, Tablets, Smartwatches, Laptops, OwnTracks-Geraete, Router-getrackte Geraete) sollen **nicht** in der Low-Battery-Benachrichtigung auftauchen, weil deren User ihre eigene Akku-Verantwortung haben.

**Zukunftssicher:** Die Erkennung laeuft zur Laufzeit. Neu hinzugefuegte Companion-App-Installationen oder andere getrackte Geraete werden automatisch beruecksichtigt, ohne dass der Blueprint neu konfiguriert werden muss.

## Features

Alle Features des Original-Blueprints bleiben erhalten:

- Trigger: Button Helper, Zeit + Wochentag
- Konfigurierbare Schwellenwerte (Standard + Custom Group)
- Easy Notify (Device, UI, Dashboard) mit drei Preset-Messages
- iOS- und Android-spezifische Optionen (Interruption Level, Sound, Sticky, High Priority)
- To-Do Listen Integration via Action Buttons
- Custom Actions (Sprachassistenten, TTS, etc.)
- Global Conditions
- Ausschluss: Sensoren, Hidden Entities, **getrackte Geraete (neu)**

## Installation

### Via Home Assistant UI

1. In Home Assistant zu **Einstellungen > Automatisierungen & Szenen > Blueprints** navigieren
2. **Blueprint importieren** klicken
3. URL eingeben:
   ```
   https://github.com/TuxMK/homeassistant_projects/blob/main/blueprints/low_battery/blueprint_low_battery.yaml
   ```

### Manuell

1. Datei `blueprint_low_battery.yaml` herunterladen
2. Nach `/config/blueprints/automation/custom/` kopieren (Ordner ggf. erstellen)
3. Home Assistant neu starten oder Blueprints neu laden

## Konfiguration der neuen Option

Im Abschnitt **Battery Settings** der Blueprint-Konfiguration:

| Feld | Werte | Standard | Beschreibung |
|------|-------|----------|--------------|
| Exclude Batteries Of Tracked Devices | `tracker_enabled` / `tracker_disabled` | `tracker_disabled` | Wenn aktiviert, werden alle Battery-Sensoren ausgeschlossen, deren Device ein `device_tracker` Entity hat. |

Die Option kombiniert sich mit den bestehenden Ausschlussmechanismen — die finale Ausschlussliste ist die Vereinigung (Union) aller vier Listen.

## Funktionsweise (Technisch)

Im Template `all_exclude_sensors` wird zusaetzlich folgendes ausgewertet:

```jinja
{% if exclude_device_tracker_batteries == 'tracker_enabled' %}
  {% set tracker_device_ids = states.device_tracker
       | map(attribute='entity_id') | map('device_id')
       | reject('none') | unique | list %}
  {% set tracker_device_entities = tracker_device_ids
       | map('device_entities') | sum(start=[]) | unique | list %}
  {% set tracker_battery_entities = tracker_device_entities
       | select('match', '^sensor\\.')
       | select('is_state_attr', 'device_class', 'battery')
       | list %}
{% endif %}
```

1. Alle Device-IDs sammeln, die mindestens ein `device_tracker.*` Entity haben
2. Alle Entities dieser Devices auflisten
3. Davon nur `sensor.*` Entities mit `device_class: battery` behalten
4. Diese Liste wird der finalen `all_exclude_sensors` Liste hinzugefuegt

## Beispiel

**Setup:** Drei Familien-Phones (HA Companion App), ein Tablet (Companion App), zwei Roboterstaubsauger, fuenf Tuer-/Fenster-Sensoren mit Batterie.

**Mit `tracker_enabled`:**

- Phones + Tablet werden automatisch ignoriert (sie haben `device_tracker.*` Entities)
- Roboter und Tuer-/Fenster-Sensoren werden ueberwacht
- Wenn morgen ein weiteres Familienmitglied die Companion App installiert, wird dessen Phone-Akku ebenfalls automatisch ignoriert

**Mit `tracker_disabled`:** Verhalten identisch zum Original-Blueprint.

## Verifikation

Siehe [`.claude/blueprints.md`](../../.claude/blueprints.md) fuer die Validierungsschritte (YAML, Struktur, Grep).

## Lizenz

MIT License — der Original-Blueprint wird ohne explizite Lizenzangabe vom Autor publiziert. Bei kommerzieller Nutzung den Original-Autor konsultieren.
