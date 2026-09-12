# Temperatur-Widget für Dashboard

Breites Widget (12 Spalten), das die Temperaturen mehrerer Kühl-/Gefrier-
schränke in einer Zeile zeigt. Die Kartenfarbe warnt anhand der
Küche-Kühlschrank-Temperatur. Klick öffnet die Temperatur-Alarm-Ansicht.

## Features

- Drei Temperaturen in der zweiten Zeile (Küche, Keller, Gefrierschrank)
- Schwellwert-abhängige Kartenfarbe (rot bei zu warm)
- Klick-Navigation zur Temperatur-Alarm-Ansicht (`/lovelace/temprature-alarm`)

## Voraussetzung

- `sensor.kuhlschrank_wohnungeg_kuche_temperature`
- `sensor.kuhlschrank_wohnungeg_keller_temperature`
- `sensor.gefrierschrank_wohnungeg_keller_temperature`
- [Mushroom Cards](https://github.com/piitaya/lovelace-mushroom) (via HACS)

## Installation

1. Mushroom Cards installieren (HACS)
2. Dashboard im UI-Editor öffnen
3. Neue Karte hinzufügen → "Manuell" wählen
4. Inhalt von [card.yaml](card.yaml) einfügen
5. Entity-IDs und `navigation_path` anpassen

## Konfiguration

### Farb-Schwellwerte

Die Kartenfarbe richtet sich nach der Küche-Kühlschrank-Temperatur:

| Temperatur   | Farbe             |
|--------------|-------------------|
| `>= 12 °C`   | `#eb4d54` (rot)   |
| `>= 10 °C`   | `#1db954` (grün)  |
| sonst        | `#3a8df7` (blau)  |

### Sichtbarkeit

Diese Karte enthält bewusst **keinen** `visibility`-Block. Soll sie nur
bestimmten Nutzern angezeigt werden, kann er im UI ergänzt werden:

```yaml
visibility:
  - condition: user
    users:
      - <user-id-1>
      - <user-id-2>
```

## Lizenz

MIT License
