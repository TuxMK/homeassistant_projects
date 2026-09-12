# Wallbox-Widget für Dashboard

Ein kompaktes Widget das den Lade- und Anschlussstatus der evcc-Wallbox anzeigt
und auf das evcc-Dashboard verlinkt.

## Features

- Dynamische Statusanzeige (lädt / angesteckt / frei)
- Farbcodierung (Primary/Orange/Grau) und Blitz-Badge während des Ladens
- Ladeleistung, SoC → Ladeziel und PV-Anteil auf einen Blick
- Fahrzeugname wird lesbar aufbereitet (z. B. `db:11` → `Skoda Elroq`)
- Unbekannte Fahrzeuge werden als `Gastfahrzeug` angezeigt (kein `null`)
- Mehrere Wallboxen über eine Liste erweiterbar
- Klick-Navigation zum evcc-Dashboard

## Voraussetzung

- [evcc](https://evcc.io/) mit der Home-Assistant-Integration
- [Mushroom Cards](https://github.com/piitaya/lovelace-mushroom) (via HACS)

Erwartete Entities (Beispiel Wallbox "Wohnung EG"):

| Zweck            | Entity                                                      |
|------------------|------------------------------------------------------------|
| Lädt             | `binary_sensor.hems_evcc_wallbox_wohnung_eg_charging`      |
| Angesteckt       | `binary_sensor.hems_evcc_wallbox_wohnung_eg_connected`     |
| Ladeleistung (W) | `sensor.hems_evcc_wallbox_wohnung_eg_charge_power`         |
| Fahrzeug-SoC     | `sensor.hems_evcc_wallbox_wohnung_eg_vehicle_soc`          |
| Ladeziel-SoC (evcc) | `number.hems_evcc_wallbox_wohnung_eg_limit_soc`         |
| Fahrzeug-Limit   | `sensor.hems_evcc_wallbox_wohnung_eg_vehicle_limit_soc`    |
| PV-Anteil (%)    | `sensor.hems_evcc_wallbox_wohnung_eg_session_solar_percentage` |
| Fahrzeugauswahl  | `select.hems_evcc_wallbox_wohnung_eg_vehicle_name`         |

## Installation

1. Mushroom Cards installieren (HACS)
2. Dashboard im UI-Editor öffnen
3. Neue Karte hinzufügen → "Manuell" wählen
4. Inhalt von [card.yaml](card.yaml) einfügen
5. Entity-IDs und `navigation_path` an die eigene Installation anpassen

## Konfiguration

### Weitere Wallbox ergänzen

Die Karte iteriert über die `wallboxes`-Liste im `secondary`-Template. Für eine
zweite Wallbox einen weiteren Eintrag mit den passenden Entity-IDs anhängen:

```yaml
{% set wallboxes = [
  {'name': 'Wohnung EG', 'charging': '...', 'connected': '...', ...},
  {'name': 'Garage',     'charging': '...', 'connected': '...', ...}
] %}
```

Hinweis: `icon`, `badge_icon` und `color` referenzieren derzeit fest die
Entity der ersten Wallbox. Bei mehreren Wallboxen ggf. auf einen neutralen
Ausdruck umstellen oder je Wallbox eine eigene Karte verwenden.

### Fahrzeugnamen

Der Anzeigename wird automatisch aus dem verschachtelten `vehicle`-Attribut der
`..._vehicle_name`-Auswahl gelesen (z. B. `Skoda Elroq von Max`):

```jinja
{% set info = state_attr(wb.vehicle, 'vehicle') %}
{% set vname = info.name if (info is mapping and info.name is string) else none %}
```

Damit ist kein manuelles Mapping nötig — der Name folgt dem in evcc
hinterlegten Fahrzeug-Titel, auch nach einem Neu-Einbinden. Der technische
`state` (z. B. `db:11`) wird ignoriert.

Liefern weder Attribut noch `state` einen Namen (`''`, `none`, `null`, `nil`,
`unknown`, `unavailable`), hängt die Anzeige am Anschlussstatus:

| Situation | Anzeige |
|-----------|---------|
| Angesteckt, evcc kennt das Fahrzeug nicht (z. B. Gastfahrzeug → `null`) | `Gastfahrzeug` |
| Nicht angesteckt | `kein Fahrzeug` |

Beim Gastfahrzeug meldet evcc in der Regel kein Ladeziel (`limit_soc` = 0) und
oft auch keinen SoC — diese Teile der Zeile entfallen dann automatisch, statt
`0%` oder `null` anzuzeigen.

### Navigation-Pfad

```yaml
tap_action:
  action: navigate
  navigation_path: /49686a9f_evcc   # Pfad zum eigenen evcc-Dashboard anpassen
```

### Grid-Größe

```yaml
grid_options:
  columns: 6   # Breite
  rows: 2      # Höhe
```

## Lizenz

MIT License
