# Home Assistant Collection

Dieses Repository ist eine Sammlung von Blueprints, Konfigurationen, Skripten und anderen Ressourcen fuer Home Assistant Projekte.

## Projektstruktur

```
/
├── blueprints/                    # Home Assistant Blueprints
│   └── device_fault_notification/ # Geraetefehlererkennung
│       ├── blueprint.yaml         # Blueprint-Definition
│       └── README.md              # Dokumentation
├── LICENSE                        # MIT License
└── README.md                      # Projekt-Uebersicht
```

## Konventionen

### Sprache
- Dokumentation: Deutsch
- Code/YAML-Kommentare: Deutsch oder Englisch
- Umlaute in Dateien werden als ae, oe, ue geschrieben

### Blueprints
- Jeder Blueprint hat einen eigenen Ordner unter `/blueprints/`
- Jeder Blueprint-Ordner enthaelt:
  - `blueprint.yaml` - Die Blueprint-Definition
  - `README.md` - Dokumentation mit Features, Installation und Konfiguration
- Blueprints folgen dem Home Assistant Blueprint-Format
- Quellenangaben bei Community-basierten Blueprints erforderlich

### Dokumentation
- README.md fuer jeden Blueprint mit:
  - Uebersicht und Features
  - Installationsanleitung (UI und manuell)
  - Konfigurationsoptionen
  - Beispiele

## Aktueller Inhalt

### Device Fault Notifications
Blueprint zur Ueberwachung von Geraetefehlern anhand von Binary Sensor Entity-ID-Patterns (z.B. `*_fault`, `*_error`, `*_is_life_end`).

Features:
- Regex-basierte Entity-Erkennung
- Push-Benachrichtigungen (iOS/Android)
- UI-Benachrichtigungen
- To-Do List Integration
- Exclude-Funktionalitaet
- Custom Actions

## Lizenz

MIT License
