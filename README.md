# Home Assistant Collection

Eine Sammlung von Blueprints, Konfigurationen, Skripten und anderen Ressourcen aus meinen Home Assistant Projekten.

## Struktur

Das Repository ist nach Ziel-System gegliedert:

| Bereich | Inhalt |
|---------|--------|
| [ha-core/](ha-core/) | Alles, was direkt in die Home-Assistant-Konfiguration gehoert: Blueprints, Automationen, Templates, Custom Templates und Dashboards |
| [ha-plugins/](ha-plugins/) | Erweiterungen/Integrationen innerhalb von Home Assistant (Pyscript-Apps) |
| [ha-apps/](ha-apps/) | Eigenstaendige Anwendungen neben Home Assistant (Zigbee2MQTT, Grafana) |

## Inhalt

### ha-core — Blueprints

| Name | Beschreibung |
|------|--------------|
| [Device Fault Notification](ha-core/blueprints/device_fault_notification/) | Benachrichtigungen bei Geraetefehlern (basierend auf Binary Sensor Patterns) |
| [Entity Staleness Notification](ha-core/blueprints/entity_staleness_notification/) | Erkennung "stiller Ausfaelle": Entitaeten ohne Update seit X Stunden |
| [Low Battery](ha-core/blueprints/low_battery/) | Batteriewarnung fuer alle Geraete mit Batterie-Sensor |
| [Climate Alarm](ha-core/blueprints/climate_alarm/) | Echtzeit-Temperatur- & Feuchtigkeitsueberwachung mit Normbereichen, Hysterese und Prioritaetslogik |
| [Archiv Metrics](ha-core/blueprints/archiv_metrics/) | Archiviert Sensorwerte gedrosselt in einer eigenen MariaDB (Ersatz fuer die InfluxDB-Integration) |
| [Influx-Migration](ha-core/blueprints/archiv_metrics/tools/) | Exportiert die Historie der InfluxDB-Integration monatsweise und importiert sie ins MariaDB-Archiv |
| [Archiv Partitions](ha-core/blueprints/archiv_partitions/) | Pflegt die Monatspartitionen der Archivtabelle: legt neue an, verwirft alte |

### ha-core — Automationen

| Name | Beschreibung |
|------|--------------|
| [MQTT Pulse Counter Cleanup](ha-core/automations/mqtt_pulse_counter_cleanup/) | Bereinigt und verrechnet Zaehlerimpulse aus MQTT (Passthrough + Delta-Berechnung) |

### ha-core — Custom Templates

| Name | Beschreibung |
|------|--------------|
| [Security Entities](ha-core/custom_templates/) | Zentrale Jinja2-Macros fuer Sicherheits-Entity-Pattern |

### ha-core — Templates

| Name | Beschreibung |
|------|--------------|
| [Security Status](ha-core/templates/security_status/) | Template-Sensor der alle Sicherheits-Entitaeten ueberwacht und einen Gesamtstatus liefert |

### ha-core — Dashboards

| Name | Beschreibung |
|------|--------------|
| [Security View](ha-core/dashboards/security_view/) | Vollständiges Sicherheits-Dashboard mit dynamischen Entity-Listen |
| [Security Widget](ha-core/dashboards/security_widget/) | Kompaktes Widget für das Übersichts-Dashboard mit Sicherheitsstatus und Link zur Detail-Ansicht |
| [Wallbox Widget](ha-core/dashboards/wallbox_widget/) | evcc-Wallbox: Lade-/Anschlussstatus, SoC, Ladeziel und PV-Anteil |
| [Energy Widget](ha-core/dashboards/energy_widget/) | SENEC-Energiefluss: PV-Erzeugung, Netzbezug/-einspeisung und Akku-Ladestand |
| [Weather Widget](ha-core/dashboards/weather_widget/) | Aktuelle Wetterlage (Zustand, Temperatur, Wind) mit passendem Icon |
| [Temperature Widget](ha-core/dashboards/temperature_widget/) | Temperaturen der Kühl-/Gefrierschränke mit Schwellwert-Farbe |
| [Pool Widget](ha-core/dashboards/pool_widget/) | Pool-Temperatur und Pumpenstatus |
| [Waste Widget](ha-core/dashboards/waste_widget/) | Nächste Müllabholung mit Abfallart-Icon und Link zum Abfallkalender |
| [Statistics Widget](ha-core/dashboards/statistics_widget/) | Navigations-Button zur Statistik-/Energie-Ansicht |
| [Billing Widget](ha-core/dashboards/billing_widget/) | Navigations-Button zum Abrechnungs-Dashboard (Strom & Gas) |

### ha-plugins — Pyscript

| Name | Beschreibung |
|------|--------------|
| [SQL Connector](ha-plugins/pyscript/apps/ha_mysql.py) | Stellt `pyscript.sql_execute` bereit — fuehrt SQL auf MariaDB/MySQL aus, Zugangsdaten nur aus `secrets.yaml` |

### ha-apps — Zigbee2MQTT

| Name | Beschreibung |
|------|--------------|
| [External Converters](ha-apps/zigbee2mqtt/) | Angepasste Geraete-Definitionen zur Vermeidung von Binding Table Overflow bei EFR32MG21-basierten Coordinatoren |

### ha-apps — Grafana

| Name | Beschreibung |
|------|--------------|
| [Energie-Abrechnung](ha-apps/grafana/) | Gas- und Strom-Abrechnung je Wohnung: Verbrauch in m³/l/kWh, Kosten, Saldo und empfohlener monatlicher Abschlag — je Dashboard eine Fassung gegen InfluxDB (`_influx`, Altbestand) und gegen `ha_metrics` (`_mysql`) |
| [Test-Dashboard](ha-apps/grafana/) | Verbindungs- und Datentest gegen die MariaDB `ha_metrics`: prueft Verbindung, Session-Zeitzone und Datenbestand je Entity und Quelle |

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
