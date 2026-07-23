# Abfall-Widget für Dashboard

Kompaktes Widget, das die nächste Müllabholung anzeigt und auf den
Abfallkalender verlinkt. Icon und Farbe des Badges richten sich nach der
Abfallart.

## Features

- Anzeige der nächsten Abholung (Text des Sensors)
- Abfallart-abhängiges Badge-Icon (Bio, Papier, Wertstoff/Gelb, Rest)
- Passende Badge-Farbe je Abfallart
- Klick-Navigation zum Abfallkalender (`/lovelace/trash-calendar`)

## Voraussetzung

- Sensor `sensor.nachste_abholung` mit der nächsten Abholung als Text
- [Mushroom Cards](https://github.com/piitaya/lovelace-mushroom) (via HACS)

## Installation

1. Mushroom Cards installieren (HACS)
2. Dashboard im UI-Editor öffnen
3. Neue Karte hinzufügen → "Manuell" wählen
4. Inhalt von [card.yaml](card.yaml) einfügen
5. Entity-ID `sensor.nachste_abholung` und `navigation_path` anpassen

## Konfiguration

### Abfallart-Erkennung (Badge)

Die Zuordnung erfolgt über Schlüsselwörter im (klein geschriebenen)
Sensor-Text:

| Schlüsselwort          | Icon                      | Farbe |
|------------------------|---------------------------|-------|
| `bio`                  | `mdi:flower`              | lime  |
| `papier`               | `mdi:newspaper`          | blue  |
| `wertstoff` / `gelb`   | `mdi:recycle-variant`    | amber |
| `rest`                 | `mdi:trash-can-outline`  | grey  |
| sonst                  | `mdi:dump-truck`         | green |

Weitere Abfallarten durch zusätzliche `elif`-Zweige in `badge_icon` /
`badge_color` ergänzen.

## Lizenz

MIT License
