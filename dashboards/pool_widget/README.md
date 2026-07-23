# Pool-Widget für Dashboard

Kompaktes Widget mit Pool-Temperatur und Pumpenstatus. Klick öffnet die
Pool-Ansicht.

## Features

- Pool-Temperatur in der Titelzeile
- Pumpenstatus (läuft / aus) in der zweiten Zeile
- Klick-Navigation zur Pool-Ansicht (`/lovelace/pool`)

## Voraussetzung

- `sensor.pool_pumpe_temperatur` (Pool-Temperatur)
- `binary_sensor.pool_pumpe_betriebszustand` (Pumpe an/aus)
- [Mushroom Cards](https://github.com/piitaya/lovelace-mushroom) (via HACS)

## Installation

1. Mushroom Cards installieren (HACS)
2. Dashboard im UI-Editor öffnen
3. Neue Karte hinzufügen → "Manuell" wählen
4. Inhalt von [card.yaml](card.yaml) einfügen
5. Entity-IDs und `navigation_path` anpassen

## Lizenz

MIT License
