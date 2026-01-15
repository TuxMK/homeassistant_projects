# Zigbee2MQTT External Converters

Diese Sammlung enthaelt angepasste Geraete-Definitionen (External Converters) fuer Zigbee2MQTT.

## Das Problem: Binding Table Overflow

### Was ist das Binding Table Problem?

Wenn ein Zigbee-Geraet (z.B. ein Rauchmelder) dem Netzwerk beitritt, versucht Zigbee2MQTT automatisch sogenannte "Bindings" einzurichten. Bindings sind Verbindungen zwischen dem Geraet und dem Coordinator (dem zentralen Zigbee-Adapter), die fuer automatische Status-Updates benoetigt werden.

**Das Problem:** Der Zigbee-Coordinator hat nur begrenzt Speicherplatz fuer diese Bindings - die sogenannte "Binding Table". Bei Adaptern mit dem EFR32MG21 Chip (z.B. SLZB-06M, SLZB-06P7) ist diese Tabelle auf ca. 32-64 Eintraege begrenzt.

### Warum ist das ein Problem?

Jedes Geraet benoetigt mehrere Bindings:
- Rauchmelder (Develco SMSZB-120): **4 Bindings** (Batterie, Temperatur, Alarm-Zone, Sirene)
- Temperatur-Sensoren: 2-3 Bindings
- Tuer/Fenster-Sensoren: 2-3 Bindings

**Rechenbeispiel:**
- 10 Rauchmelder x 4 Bindings = 40 Bindings
- Die Tabelle ist voll -> Coordinator crasht!

### Symptome

Wenn die Binding Table voll ist, passiert folgendes:

1. Zigbee2MQTT zeigt im Log: `Configuring 'Geraetename'`
2. Kurz darauf erscheint: `TABLE_FULL` oder `ASH_ERROR_TIMEOUTS`
3. Zigbee2MQTT stoppt komplett
4. Der Coordinator muss oft neu gestartet werden (Strom trennen)

Beispiel-Fehlermeldung:
```
ERROR Transaction failure; status=ASH_ERROR_TIMEOUTS
Bind 0x0015bc00310513d0/35 ssIasWd from '0x8c8b48fffe519ec8/1' failed
```

## Die Loesung: External Converter

Ein External Converter ueberschreibt die Standard-Geraetedefinition von Zigbee2MQTT. Wir entfernen dabei die `configure`-Funktion, die fuer das Erstellen der Bindings verantwortlich ist.

**Vorteile:**
- Keine Bindings = kein TABLE_FULL Fehler
- Kein Crash beim Hinzufuegen neuer Geraete
- Mehr Geraete moeglich

**Nachteile:**
- Geraete senden Updates nicht proaktiv, sondern nur bei Statusaenderung
- Batteriestand wird nur bei Aenderung gemeldet (nicht regelmaessig)

In der Praxis funktionieren die Geraete trotzdem zuverlaessig, da Rauchmelder und Sensoren bei relevanten Events (Rauch erkannt, Batterie niedrig) immer sofort melden.

## Enthaltene Converter

### develco_override.js

Fuer: **Develco SMSZB-120** Rauchmelder mit Sirene

**Funktionen die erhalten bleiben:**
- Raucherkennung (smoke)
- Temperaturmessung
- Batteriestand und -spannung
- Batterie-Warnung (battery_low)
- Sirene ausloesen (warning)
- Manipulationserkennung (tamper)
- Test-Modus

## Installation

### 1. Converter-Datei kopieren

Kopiere die `.js` Datei in deinen Zigbee2MQTT Konfigurationsordner:

```
/config/zigbee2mqtt/           # Standard Home Assistant Add-on
/opt/zigbee2mqtt/data/         # Standalone Installation
```

### 2. configuration.yaml anpassen

Siehe [configuration.yaml.example](configuration.yaml.example) fuer eine vollstaendige Beispielkonfiguration.

Die wichtigsten Aenderungen:

```yaml
advanced:
  # Deaktiviert automatisches Reporting-Setup
  report: false

# Verhindert Configure beim Geraete-Beitritt
device_options:
  configure_on_join: false

# External Converter laden (MUSS vor 'devices:' stehen!)
external_converters:
  - develco_override.js

homeassistant:
  enabled: true

devices:
  # ... deine Geraete ...
```

**Wichtig:**
- Die Zeile `external_converters:` muss VOR `devices:` stehen
- `report: false` und `configure_on_join: false` alleine reichen NICHT aus - der External Converter ist zwingend erforderlich

### 3. Zigbee2MQTT neustarten

Nach dem Neustart sollte im Log **kein** `Configuring 'Geraetename'` mehr erscheinen fuer die betroffenen Geraete.

## Verifizieren

Nach erfolgreicher Installation:

1. Im Log sollte beim Start fuer Develco-Geraete **kein** `Configuring...` mehr erscheinen
2. Die Geraete sollten normal funktionieren (Rauch-Alarm, Temperatur, Batterie werden angezeigt)
3. Neue Geraete koennen ohne Crash hinzugefuegt werden

## Betroffene Hardware

Dieses Problem tritt vor allem bei folgenden Coordinatoren auf:

| Adapter | Chip | Binding Limit | Betroffen |
|---------|------|---------------|-----------|
| SLZB-06M | EFR32MG21 | ~32-64 | Ja |
| SLZB-06P7 | EFR32MG21 | ~32-64 | Ja |
| SONOFF ZBDongle-E | EFR32MG21 | ~32-64 | Ja |
| ConBee II/III | andere | hoeher | Weniger |
| CC2652 basiert | CC2652 | ~100+ | Selten |

## Alternative Loesungen

Falls der External Converter nicht ausreicht:

1. **Mehrere Zigbee-Netzwerke:** Verschiedene Coordinator auf verschiedene Zigbee2MQTT Instanzen aufteilen
2. **Anderen Coordinator kaufen:** CC2652-basierte Adapter haben groessere Binding Tables
3. **Weniger Geraete:** Die einfachste aber unschoenste Loesung

## Weitere Converter hinzufuegen

Falls du andere Geraete hast die das gleiche Problem verursachen, kann der Converter erweitert werden. Die Struktur ist:

```javascript
const definition = {
    zigbeeModel: ['MODELL-NAME'],  // Aus Z2M "About" Tab
    model: 'MODELL-NAME',
    vendor: 'Hersteller',
    description: 'Beschreibung',
    fromZigbee: [...],  // Empfangs-Converter
    toZigbee: [...],    // Sende-Converter
    exposes: [...],     // Verfuegbare Entitaeten
    // KEINE configure-Funktion!
};
```

## Lizenz

MIT License
