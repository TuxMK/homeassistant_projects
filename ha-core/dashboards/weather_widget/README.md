# Wetter-Widget für Dashboard

Kompaktes Widget mit aktueller Wetterlage: Zustand (übersetzt), Temperatur und
Windgeschwindigkeit. Klick öffnet die Detailansicht der Wetter-Entity.

## Features

- Deutscher Klartext-Zustand über ein Mapping der HA-Wetterzustände
- Passendes `mdi:weather-*`-Icon je Zustand
- Zustandsabhängige Icon-Farbe
- Temperatur und Wind in der zweiten Zeile
- Klick → `more-info` der Wetter-Entity

## Voraussetzung

- Wetter-Entity `weather.forecast_wetter` (Name in [card.yaml](card.yaml) anpassen)
- [Mushroom Cards](https://github.com/piitaya/lovelace-mushroom) (via HACS)

## Installation

1. Mushroom Cards installieren (HACS)
2. Dashboard im UI-Editor öffnen
3. Neue Karte hinzufügen → "Manuell" wählen
4. Inhalt von [card.yaml](card.yaml) einfügen
5. Entity-ID `weather.forecast_wetter` an die eigene Installation anpassen

## Konfiguration

### Zustands-Übersetzung

Das `map`-Dictionary im `primary`-Template bildet die HA-Wetterzustände auf
deutschen Text ab. Nicht gemappte Zustände erscheinen via `c | title`.

### Icon & Farbe

`icon` und `icon_color` werten denselben Zustand aus. Weitere Zustände einfach
in den `if/elif`-Ketten ergänzen.

## Lizenz

MIT License
