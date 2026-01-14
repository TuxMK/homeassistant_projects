# Home Assistant Collection

Eine Sammlung von Blueprints, Konfigurationen, Skripten und anderen Ressourcen aus meinen Home Assistant Projekten.

## Inhalt

### Blueprints

| Name | Beschreibung |
|------|--------------|
| [Device Fault Notifications](blueprints/device_fault_notifications/) | Benachrichtigungen bei Geraetefehlern (basierend auf Binary Sensor Patterns) |

### Custom Templates

| Name | Beschreibung |
|------|--------------|
| [Security Entities](custom_templates/) | Zentrale Jinja2-Macros fuer Sicherheits-Entity-Pattern |

### Templates

| Name | Beschreibung |
|------|--------------|
| [Security Status](templates/security_status/) | Template-Sensor der alle Sicherheits-Entitaeten ueberwacht und einen Gesamtstatus liefert |

### Dashboards

| Name | Beschreibung |
|------|--------------|
| [Security Widget](dashboards/security_widget/) | Kompaktes Widget fuer das Uebersichts-Dashboard mit Sicherheitsstatus und Link zur Detail-Ansicht |
| [Security View](dashboards/security_view/) | Vollstaendiges Sicherheits-Dashboard mit dynamischen Entity-Listen |

---

## Installation

### Blueprints

1. In Home Assistant zu **Einstellungen > Automatisierungen & Szenen > Blueprints** navigieren
2. **Blueprint importieren** klicken
3. Die Raw-URL des gewuenschten Blueprints eingeben

Oder manuell die YAML-Datei nach `/config/blueprints/automation/` kopieren.

---

## Lizenz

Dieses Repository steht unter der [MIT License](LICENSE).

Einige Blueprints basieren auf Community-Beitraegen. Die entsprechenden Quellenangaben sind in den jeweiligen Dateien vermerkt.

---

## Mitwirken

Fehler gefunden oder Verbesserungsvorschlaege? Issues und Pull Requests sind willkommen.
