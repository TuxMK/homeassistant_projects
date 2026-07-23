# Energie-Widget für Dashboard

Kompaktes Widget mit dem aktuellen Energiefluss der SENEC-Anlage:
PV-Erzeugung, Netzbezug bzw. -einspeisung und Akku-Ladestand. Klick öffnet die
Energie-Ansicht.

## Features

- PV-Leistung, Bezug/Einspeisung und Akku-SoC in einer Zeile
- Dynamisches Badge-Icon je Energiefluss (Einspeisung, hoher Bezug, Akku-Entladung, PV)
- Zustandsabhängige Badge-Farbe (grün/orange/rot)
- Klick-Navigation zur Energie-Ansicht (`/lovelace/energy`)

## Voraussetzung

- SENEC-Integration mit den `solaranlage_senec_home_v3_hybrid_duo_*`-Entities
- [Mushroom Cards](https://github.com/piitaya/lovelace-mushroom) (via HACS)

Verwendete Entities:

| Zweck               | Entity                                                                  |
|---------------------|-------------------------------------------------------------------------|
| PV-Erzeugung (W)    | `sensor.solaranlage_senec_home_v3_hybrid_duo_solar_generated_power`     |
| Netzbezug (W)       | `sensor.solaranlage_senec_home_v3_hybrid_duo_grid_imported_power`       |
| Netzeinspeisung (W) | `sensor.solaranlage_senec_home_v3_hybrid_duo_grid_exported_power`       |
| Akku-Ladestand (%)  | `sensor.solaranlage_senec_home_v3_hybrid_duo_battery_charge_percent`    |
| Akku-Entladung (W)  | `sensor.solaranlage_senec_home_v3_hybrid_duo_battery_discharge_power`   |

## Installation

1. Mushroom Cards installieren (HACS)
2. Dashboard im UI-Editor öffnen
3. Neue Karte hinzufügen → "Manuell" wählen
4. Inhalt von [card.yaml](card.yaml) einfügen
5. Entity-IDs und `navigation_path` an die eigene Installation anpassen

## Konfiguration

### Schwellwerte (Badge)

Icon und Farbe des Badges richten sich nach Leistungs-Schwellwerten (in Watt):

| Bedingung   | Icon                             | Farbe       |
|-------------|----------------------------------|-------------|
| `exp > 200` | `mdi:transmission-tower-import`  | green       |
| `imp > 3000`| `mdi:transmission-tower-export`  | red         |
| `imp > 200` | `mdi:transmission-tower-export`  | orange      |
| `dis > 200` | `mdi:battery-charging-high`      | light-green |
| sonst       | `mdi:solar-power`                | green       |

Die Schwellwerte können in `badge_icon` / `badge_color` angepasst werden.

## Lizenz

MIT License
