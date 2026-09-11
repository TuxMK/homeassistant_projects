# Metrics Archive (MariaDB)

Home Assistant blueprint that writes sensor values into a dedicated MariaDB database
through the pyscript connector `pyscript.sql_execute`.

Meant as a replacement for the InfluxDB integration: the long-term data then lives in
a plain SQL database, can be backed up with `mysqldump`, corrected in phpMyAdmin and
queried in Grafana through the MySQL data source.

Everything domain specific is configured in the automation — entities, database, table,
login, host, port, minimum spacing and sweep interval. None of it is hardcoded in the
blueprint, the values shown are only defaults. The same blueprint can therefore be used
several times, for example with separate tables or intervals per group of sensors.

**Version: 1.1**

## Features

- Archives any number of sensors, selected in the automation
- Stores the real moment of change (`last_changed`, UTC), not the moment of writing
- Throttling per entity: at most one value per interval, the **latest** one wins
- The first change after a quiet period is written without delay
- No change, no write — and no empty runs either
- Non-numeric states (`unknown`, `unavailable`, text) are skipped
- Database, table, login, host and port come entirely from the automation
- One single `SELECT` and one single `INSERT` per run, regardless of the number of
  entities

## Write logic

| Situation | Behavior |
|-----------|----------|
| First change after a quiet period | written immediately |
| Further changes within the interval | collected, only the latest value is written once the interval has elapsed |
| No change | nothing is written |

This works without helper entities: the archive itself is the state store.

1. **State change of an entity.** The blueprint checks whether the *previous* value was
   stable for at least the minimum spacing. Only then was it certainly archived already,
   which makes the new change the "first one after the quiet period" — it is written
   immediately. Rapid successions of changes, on the other hand, cause no database
   access at all.
2. **Sweep run.** A `SELECT entity_id, UNIX_TIMESTAMP(MAX(ts))` returns the last
   archived timestamp for every entity. An entity is written only if its `last_changed`
   is newer than the archived timestamp (so there actually is something new) **and** at
   least the minimum spacing has passed since the last archived value.

This way the final reading of a charging session is not lost either: once the wallbox
stops counting, the next sweep run adds the last value.

**Note on accuracy:** the minimum spacing is checked against the timestamp of the last
archived value, not against the moment of writing. When going from a quiet period into
an active one, two rows can therefore end up closer together once. In continuous
operation it stays at one row per interval and entity.

## Requirements

### 1. MariaDB add-on

Official MariaDB add-on with its **own** database. The recorder stays untouched on
SQLite — **no** `db_url` is set under `recorder:` in the `configuration.yaml`.

```yaml
databases:
  - ha_metrics
logins:
  - username: homeassistant
    password: "STRONG_PASSWORD_1"
  - username: grafana
    password: "STRONG_PASSWORD_2"
rights:
  - username: homeassistant
    database: ha_metrics
  - username: grafana
    database: ha_metrics
    privileges:
      - SELECT
```

### 2. Table

Create it for example through the phpMyAdmin add-on:

```sql
CREATE TABLE states (
  entity_id VARCHAR(255)  NOT NULL,
  ts        DATETIME(3)   NOT NULL,                    -- always UTC
  value     DOUBLE        NULL,                        -- numeric value
  state     VARCHAR(255)  NULL,                        -- raw state as text
  unit      VARCHAR(32)   NULL,
  source    VARCHAR(16)   NOT NULL DEFAULT 'ha',       -- ha / import / manual
  PRIMARY KEY (entity_id, ts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

The primary key `(entity_id, ts)` is mandatory: it sorts the data physically by sensor
and time and prevents duplicates, for instance after a restart of Home Assistant.

The blueprint fills `entity_id`, `ts`, `value` and `unit`. `source` stays at its default
`ha`, so that rows corrected by hand or imported later remain recognizable through
`source = 'manual'` or `'import'`.

### 3. pyscript connector

The connector [`ha_mysql.py`](../../pyscript/apps/ha_mysql.py) belongs in
`/config/pyscript/apps/ha_mysql.py`, together with `/config/pyscript/requirements.txt`
containing the line `PyMySQL`.

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
```

The name under `apps:` has to match the file name. After a restart the action
**Run SQL** (`pyscript.sql_execute`) is available in the developer tools and can be
tested there with `SELECT 1`.

## Installation

### Through the UI

1. **Settings > Automations & scenes > Blueprints**
2. Click **Import blueprint**
3. Enter the raw URL of the file `blueprint_archiv_metrics.yaml`

### Manually

Copy the file to `/config/blueprints/automation/archiv_metrics/` and reload the
automations in the developer tools.

## Configuration

The "Default" column only shows the preset of the input. Every value can be overridden
per automation.

### Source

| Option | Description | Default |
|--------|-------------|---------|
| Entities | The sensors to archive | — |

### Target

| Option | Description | Default |
|--------|-------------|---------|
| Database | Name of the database in MariaDB | `ha_metrics` |
| Table | Target table with primary key `(entity_id, ts)` | `states` |
| Login | Login name from the pyscript app configuration, empty = `default_login` | empty |

### Write behavior

| Option | Description | Default |
|--------|-------------|---------|
| Minimum spacing | Minimum spacing between two archived values per entity, in seconds | `10` |
| Write first change immediately | Writes the first change after a quiet period without delay | `true` |
| Sweep interval | How often collected changes are written, in seconds | `10` |

The sweep interval should not be larger than the minimum spacing, otherwise it
determines the actual spacing of the archived values.

The sweep interval is a fixed list (5, 10, 15, 20, 30 or 60 seconds) instead of a free
number: it is implemented as a `time_pattern` trigger, and that one has to divide 60
seconds evenly. The minimum spacing, in contrast, is free in seconds — it determines how
densely the values actually sit, and with that the growth of the table.

### How much storage this costs

At roughly 116 bytes per row (InnoDB including page fill factor) and **10 entities**
that change continuously:

| Minimum spacing | Rows/day | Rows/year | Per year | After 5 years |
|---|---|---|---|---|
| 10 s | 86,400 | 31.5 M | 3.4 GB | **17.0 GB** |
| 15 s | 57,600 | 21.0 M | 2.3 GB | 11.4 GB |
| 30 s | 28,800 | 10.5 M | 1.1 GB | 5.7 GB |
| 60 s | 14,400 | 5.3 M | 581 MB | 2.8 GB |
| 300 s | 2,880 | 1.1 M | 116 MB | 0.6 GB |

That is the upper bound. In practice it stays below, because gas, wallbox and pool are
idle at times and then nothing is written.

The default of 10 seconds aims at resolution, not at frugality. Anyone who wants to keep
five years should either raise the minimum spacing or set up the monthly partitioning
described below and drop old partitions.

### Connection (advanced)

| Option | Description | Default |
|--------|-------------|---------|
| Host | Database host | `core-mariadb` |
| Port | Database port | `3306` |

## Example

Archive of the electricity, gas and wallbox meters, once a minute:

```yaml
alias: Meter readings to archive
use_blueprint:
  path: archiv_metrics/blueprint_archiv_metrics.yaml
  input:
    entities:
      - sensor.wohnungeg_uv_1_total_active_energy
      - sensor.wohnungeg_uv_2_total_active_energy
      - sensor.wohnung_eg_uv_all_total_active_energy
      - sensor.gaszahler_wohnung_eg_total_gas_consumption_cleaned
      - sensor.hems_evcc_wallbox_wohnung_eg_charge_total_import
    database: ha_metrics
    table: states
    login: archiv
    throttle_seconds: 60
    sweep_seconds: "0"
```

With five meters and throttling to one minute this produces at most about 7,200 rows per
day, so roughly 291 MB per year and 1.4 GB over five years. In practice clearly less,
because gas and wallbox are often idle.

## Monthly partitioning

A partitioned table looks like a single table to SQL — the blueprint, Grafana and
phpMyAdmin notice nothing of it. Internally InnoDB creates one file per partition and
sorts every row into the right one automatically, based on `ts`.

That buys two things:

- **Deleting in milliseconds.** `DELETE FROM states WHERE ts < …` has to touch every
  single row out of millions and write it to the transaction log — that can block a
  running Home Assistant instance for minutes. `ALTER TABLE … DROP PARTITION` deletes a
  whole file instead, no matter how many rows are in it.
- **Shorter queries.** With `WHERE ts BETWEEN '2026-03-01' AND '2026-03-31'` MariaDB
  sees that only the March partition can qualify and ignores all others ("partition
  pruning"). That helps exactly with the queries across all entities, which would
  otherwise trigger a full table scan.

One rule of InnoDB matters here: **the partition column has to be part of every unique
key.** The primary key is `(entity_id, ts)` and already contains `ts` — which is why
partitioning by `ts` works without any change to the schema. If the key were just
`(entity_id)`, or if there were an `id` column as the key, it would not work.

### Setting it up

`TO_DAYS(ts)` turns the date into a number that ranges can be built from. Every
partition takes everything **less than** its boundary — so `p2026_03` ends on April 1st
and therefore contains exactly March:

```sql
ALTER TABLE states PARTITION BY RANGE (TO_DAYS(ts)) (
  PARTITION p2026_01 VALUES LESS THAN (TO_DAYS('2026-02-01')),
  PARTITION p2026_02 VALUES LESS THAN (TO_DAYS('2026-03-01')),
  PARTITION p2026_03 VALUES LESS THAN (TO_DAYS('2026-04-01')),
  PARTITION p2026_04 VALUES LESS THAN (TO_DAYS('2026-05-01')),
  PARTITION pmax     VALUES LESS THAN MAXVALUE
);
```

`pmax` is the catch-all partition. Without it an `INSERT` with a timestamp beyond the
last boundary would fail with "Table has no partition for value" — precisely when the
next month begins and nobody thought of it.

### Adding months

Because new months do not appear by themselves, a partition has to be added before every
change of month. The blueprint [Maintain monthly partitions](../archiv_partitions/) does
that automatically — it creates the lead time and optionally drops old months. By hand it
works like this, by splitting `pmax`:

```sql
ALTER TABLE states REORGANIZE PARTITION pmax INTO (
  PARTITION p2026_05 VALUES LESS THAN (TO_DAYS('2026-06-01')),
  PARTITION pmax     VALUES LESS THAN MAXVALUE
);
```

As long as `pmax` is empty this is instant. If it runs only once data already sits there,
MariaDB has to re-sort those rows — then it takes a while. That is why this belongs in an
automation that creates the month **after next** at the beginning of each month.

### Discarding old data

```sql
ALTER TABLE states DROP PARTITION p2026_01;
```

One call, constant runtime, no bloated transaction log. That is the actual reason why
partitioning pays off: without it there is no practical way to shrink an archive that
has grown over years.

### Looking at what is in there

```sql
SELECT partition_name, table_rows,
       ROUND((data_length + index_length) / 1024 / 1024) AS mb
FROM information_schema.partitions
WHERE table_schema = 'ha_metrics' AND table_name = 'states'
ORDER BY partition_ordinal_position;
```

With InnoDB `table_rows` is only an estimate, but it is good enough for the size
distribution.

## Querying in Grafana

Data source of type **MySQL**, host `core-mariadb:3306`, database `ha_metrics`, user
`grafana` (read-only).

Time series of one meter:

```sql
SELECT ts AS time, value AS "Gas meter"
FROM states
WHERE entity_id = 'sensor.gaszahler_wohnung_eg_total_gas_consumption_cleaned'
  AND $__timeFilter(ts)
ORDER BY ts
```

Monthly consumption (end-of-month reading minus previous month):

```sql
SELECT month AS time, reading - LAG(reading) OVER (ORDER BY month) AS consumption
FROM (
  SELECT DATE_FORMAT(ts, '%Y-%m-01') AS month, MAX(value) AS reading
  FROM states
  WHERE entity_id = 'sensor.gaszahler_wohnung_eg_total_gas_consumption_cleaned'
  GROUP BY month
) m
ORDER BY month
```

The timestamps are in UTC, so the month boundaries are one to two hours off compared to
German local time. For a yearly bill that is negligible.

## Corrections

Outliers and meter replacements are corrected directly in SQL, for example in
phpMyAdmin, and marked as manual while doing so:

```sql
UPDATE states SET value = 12345.6, source = 'manual'
WHERE entity_id = 'sensor.gaszahler_wohnung_eg_total_gas_consumption_cleaned'
  AND ts = '2026-03-14 10:02:13.000';
```

The blueprint does not overwrite such corrections: a row is only touched again if Home
Assistant delivers another value for exactly the same timestamp.

Independently of that, the long-term statistics of Home Assistant remain the safety net
for billing. They can be corrected under **Developer tools > Statistics**.

## Notes

- **Restart of Home Assistant:** `last_changed` is reset on start. The first sweep run
  afterwards writes the current reading once per meter with a new timestamp. That is
  harmless, the meter reading itself stays correct.
- **Database not reachable:** the run aborts and the error appears in the HA log. Meter
  readings are cumulative, so only intermediate points are missing — the next value
  written contains the correct total.
- **Attribute changes** (a new `friendly_name`, for instance) trigger no write, because
  they do not change `last_changed`.
- **Parallel runs:** the automation runs in mode `single` with `max_exceeded: silent`.
  Overlapping triggers are dropped without flooding the log — the next sweep run catches
  up on everything.

## License

MIT License
