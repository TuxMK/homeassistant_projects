# Monatspartitionen pflegen

Home Assistant Blueprint, der in einer partitionierten Archivtabelle die Partitionen
der kommenden Monate anlegt und auf Wunsch die ältesten verwirft.

Gegenstück zu [SQL-Archiv (MariaDB)](../archiv_metrics/), das die Werte schreibt.
Warum sich Partitionierung lohnt, steht dort im Abschnitt
[Monatspartitionierung](../archiv_metrics/README.md#monatspartitionierung).

**Version: 1.0**

## Features

- Legt fehlende Monate im Voraus an, bevor der Monatswechsel sie braucht
- Verwirft alte Partitionen in konstanter Zeit statt mit einem langen `DELETE`
- Idempotent: Vorhandenes wird nicht angefasst, ausgefallene Läufe holt der
  nächste nach
- Läuft täglich und zusätzlich nach jedem Neustart von Home Assistant
- Ändert nichts, solange die Tabelle nicht partitioniert ist — meldet das nur

## Ablauf eines Laufs

1. Bestehende Partitionen aus `information_schema.partitions` lesen.
2. Zielmonate bilden: laufender Monat plus Vorlauf.
3. Fehlende Monate mit einem `ALTER TABLE … REORGANIZE PARTITION pmax INTO (…)`
   anlegen — alle in einer Anweisung.
4. Ist eine Aufbewahrung gesetzt: alle Partitionen unterhalb der Grenze mit
   `ALTER TABLE … DROP PARTITION` verwerfen.

Angelegt werden nur Monate **nach** der letzten vorhandenen Partition. Eine Lücke in
der Vergangenheit lässt sich über `pmax` nicht mehr schließen — dort stünden schon
Daten des Folgemonats im Weg.

Erzeugt wird dabei genau dieses SQL:

```sql
ALTER TABLE `states` REORGANIZE PARTITION pmax INTO (
  PARTITION p2026_12 VALUES LESS THAN (TO_DAYS('2027-01-01')),
  PARTITION p2027_01 VALUES LESS THAN (TO_DAYS('2027-02-01')),
  PARTITION pmax     VALUES LESS THAN MAXVALUE);

ALTER TABLE `states` DROP PARTITION p2025_09, p2025_10;
```

## Voraussetzungen

### 1. Tabelle einmalig partitionieren

Das erste `ALTER TABLE … PARTITION BY` schreibt die komplette Tabelle neu. Bei einem
gewachsenen Archiv dauert das und sperrt die Tabelle — deshalb bleibt dieser Schritt
bewusst von Hand, in einer ruhigen Minute:

```sql
ALTER TABLE states PARTITION BY RANGE (TO_DAYS(ts)) (
  PARTITION p2026_09 VALUES LESS THAN (TO_DAYS('2026-10-01')),
  PARTITION pmax     VALUES LESS THAN MAXVALUE
);
```

Die erste Partition muss den ältesten vorhandenen Monat abdecken. Was schon in der
Tabelle steht, sortiert MariaDB dabei selbst ein. Alles Weitere übernimmt danach die
Automatisierung.

`pmax` ist Pflicht: Ohne diese Auffangpartition scheitert jeder `INSERT` mit einem
Zeitstempel jenseits der letzten Grenze — und genau darüber legt die Automatisierung
neue Monate an.

### 2. Login mit ALTER-Recht

Der Schreib-Login des Archivs hat bewusst nur `SELECT`, `INSERT`, `UPDATE`, `DELETE`.
Für die Partitionspflege braucht es `ALTER`, für die Aufbewahrung zusätzlich `DROP`.
Sinnvoll ist ein eigener Login — im MariaDB-Add-on:

```yaml
logins:
  - username: archiv_admin
    password: "STARKES_PASSWORT_3"
rights:
  - username: archiv_admin
    database: ha_metrics
    privileges:
      - SELECT
      - ALTER
      - DROP
```

und in der pyscript-App-Konfiguration:

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

1. **Einstellungen > Automatisierungen & Szenen > Blueprints**
2. **Blueprint importieren** klicken
3. Raw-URL der Datei `blueprint_archiv_partitions.yaml` eingeben

### Manuell

Die Datei nach `/config/blueprints/automation/archiv_partitions/` kopieren und in den
Entwicklerwerkzeugen die Automatisierungen neu laden.

## Konfiguration

### Ziel

| Option | Beschreibung | Standard |
|--------|--------------|----------|
| Datenbank | Name der Datenbank in MariaDB | `ha_metrics` |
| Tabelle | Die partitionierte Archivtabelle, Partitionsspalte `ts` | `states` |
| Login | Login aus der pyscript-App-Konfiguration, braucht `ALTER` | leer |

### Verhalten

| Option | Beschreibung | Standard |
|--------|--------------|----------|
| Vorlauf | Wie viele Monate im Voraus bereitstehen | `2` Monate |
| Aufbewahrung | Wie viele Monate erhalten bleiben, `0` = unbegrenzt | `0` |
| Uhrzeit | Wann der tägliche Lauf stattfindet | `04:17:00` |

**Aufbewahrung löscht Daten unwiederbringlich.** Der Standard `0` rührt nichts an. Erst
wenn dort ein Wert steht, verwirft die Automatisierung alte Partitionen — bei `24` bleibt
gut zwei Jahre erhalten.

Der Vorlauf darf ruhig großzügig sein: Leere Partitionen kosten praktisch nichts, und
`REORGANIZE` ist nur solange sofort fertig, wie `pmax` leer ist. Läuft die Automatisierung
erst, wenn dort bereits Daten liegen, muss MariaDB diese Zeilen umsortieren.

### Verbindung (erweitert)

| Option | Beschreibung | Standard |
|--------|--------------|----------|
| Host | Datenbank-Host | `core-mariadb` |
| Port | Datenbank-Port | `3306` |

## Beispiel

Zwei Monate Vorlauf, drei Jahre aufbewahren:

```yaml
alias: Archiv-Partitionen pflegen
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

## Kontrolle

Was tatsächlich angelegt wurde:

```sql
SELECT partition_name, table_rows,
       ROUND((data_length + index_length) / 1024 / 1024) AS mb
FROM information_schema.partitions
WHERE table_schema = 'ha_metrics' AND table_name = 'states'
ORDER BY partition_ordinal_position;
```

`table_rows` ist bei InnoDB nur eine Schätzung, für die Größenverteilung reicht es.

## Hinweise

- Ist die Tabelle nicht partitioniert oder fehlt `pmax`, schreibt die Automatisierung
  eine Warnung ins Protokoll (Logger `archiv_partitions`) und ändert nichts. Das ist
  der Hinweis, dass die einmalige Partitionierung oben noch fehlt.
- `ALTER TABLE` sperrt die Tabelle kurz. Das Anlegen einer leeren Partition dauert
  Millisekunden, `DROP PARTITION` ebenso — unabhängig davon, wie viele Zeilen darin
  stehen. Der laufende Archiv-Blueprint verträgt das, er versucht es beim nächsten
  Intervall-Lauf erneut.
- Die Automatisierung schreibt keine Daten und liest nur `information_schema` —
  ein Fehllauf kann also nichts verfälschen. Das einzige Risiko steckt in der
  Aufbewahrung.

## Lizenz

MIT License
