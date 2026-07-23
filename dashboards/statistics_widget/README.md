# Statistik-Widget für Dashboard

Kompakter Navigations-Button, der auf die Energie-/Statistik-Ansicht verlinkt.

## Features

- Klick-Navigation zur Energie-Ansicht (`/energy`)
- Icon `mdi:chart-box` in Blau

## Voraussetzung

- [Mushroom Cards](https://github.com/piitaya/lovelace-mushroom) (via HACS)

## Installation

1. Mushroom Cards installieren (HACS)
2. Dashboard im UI-Editor öffnen
3. Neue Karte hinzufügen → "Manuell" wählen
4. Inhalt von [card.yaml](card.yaml) einfügen
5. `navigation_path` bei Bedarf anpassen

## Konfiguration

### Navigation-Pfad

```yaml
tap_action:
  action: navigate
  navigation_path: /energy   # Ziel-Ansicht anpassen
```

## Lizenz

MIT License
