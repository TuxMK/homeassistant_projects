# Home Assistant Collection

Eine Sammlung von Blueprints, Konfigurationen, Skripten und anderen Ressourcen aus meinen Home Assistant Projekten.

## Inhalt

### Blueprints

| Name | Beschreibung |
|------|--------------|
| [Device Fault Notifications](blueprints/device_fault_notifications.yaml) | Benachrichtigungen bei Geraetefehlern (basierend auf Binary Sensor Patterns) |

### Weitere Ressourcen

*Weitere Inhalte folgen...*

---

## Blueprints

### Device Fault Notifications

Ueberwacht Binary Sensoren anhand von Entity-ID-Patterns und benachrichtigt bei Fehlerzustaenden.

**Features:**
- Regex-basierte Entity-Erkennung (z.B. `.*_fault$`, `.*_is_life_end$`, `.*_error$`)
- Benachrichtigung wenn Sensor nicht `off` ist (on, unavailable, unknown)
- Device Push-Benachrichtigungen (iOS/Android)
- UI-Benachrichtigungen (persistent_notification)
- Dashboard-Anzeige via Text Helper
- To-Do List Integration mit Action Buttons
- Custom Actions fuer Sprachassistenten (Google, Alexa, TTS)
- Exclude-Funktionalitaet (Sensoren, Areas, Devices, Labels)
- Custom Group mit separaten Patterns

**Installation:**
1. In Home Assistant zu **Einstellungen > Automatisierungen & Szenen > Blueprints** navigieren
2. **Blueprint importieren** klicken
3. URL eingeben: `https://raw.githubusercontent.com/DEIN_USERNAME/homeassistant-collection/main/blueprints/device_fault_notifications.yaml`

**Basiert auf:** [Low Battery Notifications & Actions](https://community.home-assistant.io/t/653754) von Blacky (Home Assistant Community)

---

## Installation

### Blueprints manuell installieren

1. Blueprint-Datei herunterladen
2. Nach `/config/blueprints/automation/custom/` kopieren (Ordner ggf. erstellen)
3. Home Assistant neu starten oder Blueprints neu laden

---

## Lizenz

Dieses Repository steht unter der [MIT License](LICENSE).

Einige Blueprints basieren auf Community-Beitraegen. Die entsprechenden Quellenangaben sind in den jeweiligen Dateien vermerkt.

---

## Mitwirken

Fehler gefunden oder Verbesserungsvorschlaege? Issues und Pull Requests sind willkommen.
