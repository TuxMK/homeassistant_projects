# Monatspartitionen pflegen

Home-Assistant-Blueprint, das in einer partitionierten Archivtabelle die Partitionen der
kommenden Monate anlegt und auf Wunsch die ältesten entfernt.

Gegenstück zu [Metrics Archive (MariaDB)](../archiv_metrics/), das die Werte schreibt.
Warum sich die Partitionierung lohnt, steht dort unter
[Monatspartitionierung](../archiv_metrics/README.md#monatspartitionierung).

**Version: 1.0**

## Features

- Legt fehlende Monate vorab an, bevor der Monatswechsel sie braucht
- Entfernt alte Partitionen in konstanter Zeit statt mit einem langen `DELETE`
- Idempotent: Was schon existiert, bleibt unangetastet, verpasste Läufe holt der nächste nach
- Läuft täglich und zusätzlich nach jedem Neustart von Home Assistant
- Ändert nichts, solange die Tabelle nicht partitioniert ist — meldet das nur

## Was ein Lauf macht

1. Die vorhandenen Partitionen aus `information_schema.partitions` lesen.
2. Die Zielmonate bilden: aktueller Monat plus Vorlauf.
3. Die fehlenden Monate mit einem einzigen
   `ALTER TABLE … REORGANIZE PARTITION pmax INTO (…)` anlegen.
4. Falls eine Aufbewahrungsdauer gesetzt ist: jede Partition unterhalb der Grenze mit
   `ALTER TABLE … DROP PARTITION` entfernen.

Angelegt werden nur Monate **nach** der letzten vorhandenen Partition. Eine Lücke in der
Vergangenheit lässt sich über `pmax` nicht mehr schließen — dort stehen die Daten des
Folgemonats bereits im Weg.

So sieht das erzeugte SQL aus:

```sql
ALTER TABLE `states` REORGANIZE PARTITION pmax INTO (
  PARTITION p2026_12 VALUES LESS THAN (TO_DAYS('2027-01-01')),
  PARTITION p2027_01 VALUES LESS THAN (TO_DAYS('2027-02-01')),
  PARTITION pmax     VALUES LESS THAN MAXVALUE);

ALTER TABLE `states` DROP PARTITION p2025_09, p2025_10;
```

## Voraussetzungen

### 1. Tabelle einmalig partitionieren

Das erste `ALTER TABLE … PARTITION BY` schreibt die gesamte Tabelle neu. Bei einem
gewachsenen Archiv dauert das eine Weile und sperrt die Tabelle — deshalb bleibt dieser
Schritt bewusst manuell und gehört in eine ruhige Minute:

```sql
ALTER TABLE states PARTITION BY RANGE (TO_DAYS(ts)) (
  PARTITION p2026_09 VALUES LESS THAN (TO_DAYS('2026-10-01')),
  PARTITION pmax     VALUES LESS THAN MAXVALUE
);
```

Die erste Partition muss den ältesten vorhandenen Monat abdecken. Was bereits in der
Tabelle liegt, sortiert MariaDB selbst an die richtige Stelle. Alles Weitere übernimmt
die Automation.

`pmax` ist Pflicht: Ohne diese Auffang-Partition schlägt jedes `INSERT` mit einem
Zeitstempel jenseits der letzten Grenze fehl — und genau über `pmax` legt die Automation
neue Monate an.

### 2. Ein Login mit ALTER

Das Schreib-Login des Archivs hat bewusst nur `SELECT`, `INSERT`, `UPDATE`, `DELETE`.
Für die Partitionspflege braucht es `ALTER`, für die Aufbewahrungsdauer zusätzlich
`DROP`. Ein eigenes Login ist sinnvoll — im MariaDB-Add-on:

```yaml
logins:
  - username: archiv_admin
    password: "STRONG_PASSWORD_3"
rights:
  - username: archiv_admin
    database: ha_metrics
    privileges:
      - SELECT
      - ALTER
      - DROP
```

und in der Konfiguration der pyscript-App:

```yaml
# configuration.yaml
pyscript:
  allow_all_imports: true
  apps:
    ha_mysql:
      default_login: archiv
      logins:
        archiv:
          username: !secret archiv_db_user
          password: !secret archiv_db_password
        archiv_admin:
          username: !secret archiv_admin_user
          password: !secret archiv_admin_password
```

## Installation

### Über die UI

1. **Einstellungen > Automationen & Szenen > Blueprints**
2. Auf **Blueprint importieren** klicken
3. Die Raw-URL der Datei `blueprint_archiv_partitions.yaml` eingeben

### Manuell

Die Datei nach `/config/blueprints/automation/archiv_partitions/` kopieren und die
Automationen in den Entwicklerwerkzeugen neu laden.

## Konfiguration

Die Spalte „Option“ nennt die Felder so, wie das Blueprint-Formular sie anzeigt, also auf Englisch; hinter dem Gedankenstrich der Überschriften steht der Abschnittsname aus dem Formular.

### Ziel – Target

| Option | Beschreibung | Standard |
|--------|-------------|---------|
| Database | Name der Datenbank in MariaDB | `ha_metrics` |
| Table | Die partitionierte Archivtabelle, Partitionsspalte `ts` | `states` |
| Login | Login aus der Konfiguration der pyscript-App, braucht `ALTER` | leer |

### Verhalten – Behavior

| Option | Beschreibung | Standard |
|--------|-------------|---------|
| Lead time | Wie viele Monate im Voraus bereitstehen | `2` Monate |
| Retention | Wie viele Monate behalten werden, `0` = unbegrenzt | `0` |
| Time of day | Wann der tägliche Lauf stattfindet | `04:17:00` |

**Die Aufbewahrungsdauer löscht Daten unwiderruflich.** Der Standard `0` rührt nichts an.
Erst wenn dort ein Wert steht, entfernt die Automation alte Partitionen — bei `24` bleiben
gut zwei Jahre erhalten.

Der Vorlauf darf großzügig sein: Leere Partitionen kosten so gut wie nichts, und
`REORGANIZE` ist nur so lange sofort erledigt, wie `pmax` leer ist. Läuft die Automation
erst, wenn dort schon Daten liegen, muss MariaDB diese Zeilen umschichten.

### Verbindung (erweitert) – Connection (advanced)

| Option | Beschreibung | Standard |
|--------|-------------|---------|
| Host | Datenbank-Host | `core-mariadb` |
| Port | Datenbank-Port | `3306` |

## Beispiel

Zwei Monate Vorlauf, drei Jahre aufbewahren:

```yaml
alias: Maintain archive partitions
use_blueprint:
  path: archiv_partitions/blueprint_archiv_partitions.yaml
  input:
    database: ha_metrics
    table: states
    login: archiv_admin
    lead_months: 2
    keep_months: 36
    run_at: "04:17:00"
```

## Ergebnis prüfen

Was tatsächlich angelegt wurde:

```sql
SELECT partition_name, table_rows,
       ROUND((data_length + index_length) / 1024 / 1024) AS mb
FROM information_schema.partitions
WHERE table_schema = 'ha_metrics' AND table_name = 'states'
ORDER BY partition_ordinal_position;
```

Bei InnoDB ist `table_rows` nur ein Schätzwert, für die Größenverteilung reicht das
aber aus.

## Hinweise

- **Partitionsnamen werden als Text verglichen.** Die Automation nimmt den höchsten
  vorhandenen Namen als oberes Ende und legt nur Monate darüber an. Ein Name außerhalb
  des Schemas `pYYYY_MM` — etwa `p_before` oder `pmin` — sortiert über jedem Monat und
  würde verhindern, dass sie je wieder einen anlegt. Eine Auffang-Partition für alte
  Daten braucht es ohnehin nicht: Die erste Partition nimmt alles unterhalb ihrer Grenze auf.
- Ist die Tabelle nicht partitioniert oder fehlt `pmax`, schreibt die Automation eine
  Warnung ins Log (Logger `archiv_partitions`) und ändert nichts. Das ist der Hinweis,
  dass die einmalige Partitionierung von oben noch fehlt.
- `ALTER TABLE` sperrt die Tabelle kurz. Eine leere Partition anzulegen dauert
  Millisekunden, `DROP PARTITION` ebenso — unabhängig davon, wie viele Zeilen darin
  liegen. Das laufende Archiv-Blueprint kommt damit zurecht, es versucht es einfach beim
  nächsten Durchlauf erneut.
- Die Automation schreibt keine Daten und liest nur `information_schema`, ein
  fehlgeschlagener Lauf kann also nichts beschädigen. Das einzige Risiko liegt in der
  Aufbewahrungsdauer.

## Lizenz

MIT License
