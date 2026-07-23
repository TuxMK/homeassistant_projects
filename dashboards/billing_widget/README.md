# Abrechnungs-Widget für Dashboard

Kompakter Navigations-Button, der auf das Abrechnungs-Dashboard (Strom & Gas)
verlinkt.

## Features

- Klick-Navigation zum Abrechnungs-Dashboard
- Icon `mdi:currency-eur`, Kartenfarbe Gold

## Voraussetzung

- [Mushroom Cards](https://github.com/piitaya/lovelace-mushroom) (via HACS)

## Installation

1. Mushroom Cards installieren (HACS)
2. Dashboard im UI-Editor öffnen
3. Neue Karte hinzufügen → "Manuell" wählen
4. Inhalt von [card.yaml](card.yaml) einfügen
5. `navigation_path` an das eigene Abrechnungs-Dashboard anpassen

## Konfiguration

### Navigation-Pfad

```yaml
tap_action:
  action: navigate
  navigation_path: /dashboard-abrechnung/0   # eigenen Dashboard-Pfad eintragen
```

## Lizenz

MIT License
