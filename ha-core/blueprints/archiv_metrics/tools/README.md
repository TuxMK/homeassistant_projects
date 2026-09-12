# Migration InfluxDB 1.x -> MariaDB archive

Two scripts that move the history of the InfluxDB integration into the archive table
of the blueprint [Metrics Archive (MariaDB)](../). They get by with what is on the
machines anyway — `docker` for the export, `awk` and the `mysql` client for the import.
No Python, no `influxdb` package, no database driver.

| Script | Purpose |
|--------|---------|
| [`influx_export_monthly.sh`](influx_export_monthly.sh) | Exports everything unchanged as line protocol, one file per month |
| [`influx_import_mysql.sh`](influx_import_mysql.sh) | Converts the dumps and pipes them straight into MariaDB, without intermediate files |

`influx_export_monthly.sh` runs on the Home Assistant host (SSH add-on), because it needs
the container; `influx_import_mysql.sh` runs wherever the dump files end up, as long as
the database can be reached from there.

## How the schemas map onto each other

Home Assistant writes into InfluxDB in a shape that does not match the archive table
one to one. Two details matter:

- The tag `entity_id` holds **only the object id**, without the domain. The full entity
  id is `domain + '.' + entity_id`, and the import assembles it from both tags.
- The measurement name **is** the `unit_of_measurement`. Where a state carries no unit,
  Home Assistant falls back to the full entity id as the measurement name. Such a name
  contains a dot — the import recognizes it and leaves `unit` empty.

| InfluxDB | Archive table |
|----------|---------------|
| tag `domain` + tag `entity_id` | `entity_id` |
| `time` (UTC) | `ts` (`DATETIME(3)`, UTC) |
| field `value` | `value` |
| field `state` | `state` |
| measurement name | `unit` (empty if it contains a dot) |
| — | `source` = `import` |

`source = 'import'` is exactly what the column was made for: rows from the migration stay
distinguishable from those written by the running automation (`ha`) and from manual
corrections (`manual`).

## 1. Stop the writing, not the add-on

**Settings > Devices & services > InfluxDB > disable.** That stops Home Assistant from
writing while the export runs, and the container keeps running — which it has to, since
everything below goes through `docker exec`. Stopping the add-on would take the container
away with it.

## 2. Write the dump

[`influx_export_monthly.sh`](influx_export_monthly.sh) does it month by month. Adjust the
block at the top — `CONTAINER`, `DB`, `START`, `END` — and run it on the HA host:

```bash
zsh influx_export_monthly.sh
```

It finds the data directories inside the container by itself, exports one file per month
into `influx_export/`, skips months without data, and reports the number of points per
file — split into TSM and WAL. `DRYRUN=1` prints the commands instead of running them.

**Two traps it guards against.** If the data directory holds no `.tsm` files, the export
would silently produce files that look plausible but contain only the write-ahead log;
the script counts them up front and stops. And `influx_inspect` does not apply
`-start`/`-end` to the WAL in every version, so its rows — the most recent writes — would
land in *every* monthly file, including months from years back. The WAL belongs to the
newest month, so that is the only one exported with the real `waldir`.

A file reported as `!! WAL only, no stored data` means nothing stored was found for that
period — either the month genuinely holds no data, or `DATADIR` points at the wrong
place. If it says that for *every* month, locate the shards with
`docker exec <container> find / -name '*.tsm' 2>/dev/null | head` and set `DATADIR` and
`WALDIR` at the top of the script by hand.

Under the hood it is `influx_inspect export` with `-start`/`-end` per month. By hand, for
one period, that is:

```bash
docker exec addon_a0d7b954_influxdb \
  influx_inspect export \
    -datadir /data/influxdb/data \
    -waldir  /data/influxdb/wal \
    -database homeassistant \
    -start 2025-11-01T00:00:00Z -end 2025-11-30T23:59:59.999999999Z \
    -out /share/influx_export.lp \
    -compress
```

Should those paths not exist, `find /data -name '*.tsm' | head` names the real ones — the
add-on stores its data under `/data`, but the layout has changed across versions.

**Why not `influx -format csv`:** for a single known measurement, selecting the columns
by hand works fine. Across all measurements it does not: CSV carries no types, so `42i`
(integer) can no longer be told from `42` (float) or from a string on the way back, and a
`friendly_name` containing a comma shifts the columns. `influx_inspect` writes native line
protocol straight from the TSM files — types, escaping and all fields intact.

## 3. Import into MariaDB

[`influx_import_mysql.sh`](influx_import_mysql.sh) reads the `.lp` files, converts them
and pipes the statements into the `mysql` client — no `.sql` files in between. Everything
but the credentials sits in the config block at the top:

```bash
./influx_import_mysql.sh <db-user> <db-password>
DRYRUN=1 ./influx_import_mysql.sh <db-user> <db-password>   # print the SQL instead
```

It checks the connection and the table before writing anything, reports rows per file,
and stops at the first failing file instead of carrying on. `.gz` files are unpacked on
the fly, and the DDL header that `influx_inspect` puts in front of a dump is skipped.

It needs the `mysql` client: `sudo apt install mariadb-client`. On MariaDB 11 the
`mariadb` command is used, which the script picks by itself — the old name still works
but warns on every call, which would bury the progress output.

### The config block

| Setting | Effect |
|---------|--------|
| `LPDIR` | Directory holding the `.lp` / `.lp.gz` files |
| `HOST`, `PORT`, `DB`, `TABLE` | Where the rows go |
| `UNTIL` | Cut-off (UTC): nothing from this moment on. Empty = import everything |
| `MIN_INTERVAL` | Seconds between two rows per entity, `0` = every point |
| `DOMAINS` | Space-separated, e. g. `"sensor"` — empty = every domain, including `light`, `binary_sensor` and the rest |
| `NUMERIC_ONLY` | `1` skips points without a numeric value — switch states and text sensors stay behind |
| `SOURCE` | Value for the `source` column, `import` by default |
| `PRECISION` | Timestamp precision in the dump, if it is not nanoseconds |
| `BATCH` | Rows per `INSERT` statement |

**On `MIN_INTERVAL`:** the thinning happens while converting, not in InfluxDB. A
`GROUP BY time(60s)` would snap every value onto the bucket boundary; this way the real
timestamp of each point is kept, exactly like the automation does it in normal operation.
It relies on the points of an entity arriving in order, which the dump delivers. Input
that is out of order only ever keeps more rows, never fewer.

### The cut-off

`UNTIL` ends the import at a given moment, so it stops exactly where the archive
automation took over and the two do not overlap:

```bash
UNTIL="2026-09-11 14:05:58.529"   # nothing from this moment on
```

The right value is the first row the automation wrote itself:

```sql
SELECT MIN(ts) FROM states WHERE source = 'ha';
```

Take it from **that query**, not from the Home Assistant interface — the column is UTC,
while the interface shows local time, and in summer the two are two hours apart. A
cut-off read off the screen would cut two hours too late and let the import write over a
window the automation already covers.

`UNTIL` may be given as `YYYY-MM-DD`, `YYYY-MM-DD HH:MM:SS` or with milliseconds; a short
form is filled up to the end of the period it names, so a bare date means that whole day.
The named moment itself is still imported. Leave it empty to import everything.

A file that runs past the cut-off reports it: `3 rows (…, after cut-off 2)`. The password
goes into a temporary file with mode 600 rather than the command line, where `ps` would
show it to everyone on the machine.

The statements are `INSERT IGNORE`. Rows that are already in the table — written by the
automation, or corrected by hand — stay untouched; only genuinely missing history is
added. A file can therefore be imported twice without doing any harm.

## Before importing into a partitioned table

If the target table is already partitioned by month, its **oldest** partition determines
how far back a row may reach. An import from 2023 into a table whose first partition
starts in 2026 fails with `Table has no partition for value`.

Partitions for the past cannot be created through `pmax` — that one only covers the
future. The first partition has to be split up instead:

```sql
ALTER TABLE states REORGANIZE PARTITION p2026_01 INTO (
  PARTITION p2023 VALUES LESS THAN (TO_DAYS('2024-01-01')),
  PARTITION p2024 VALUES LESS THAN (TO_DAYS('2025-01-01')),
  PARTITION p2025 VALUES LESS THAN (TO_DAYS('2026-01-01')),
  PARTITION p2026_01 VALUES LESS THAN (TO_DAYS('2026-02-01'))
);
```

Whole years are enough for the imported past: those partitions never grow again, and the
point of the monthly cut — dropping old data in one go — is served just as well by a year.

The simplest order is the other way round, though: **import first, partition afterwards.**
The initial `ALTER TABLE … PARTITION BY` rewrites the table anyway and sorts everything
that is in there into the right partition on its own.

## Afterwards

```sql
-- How much arrived, per source
SELECT source, COUNT(*), MIN(ts), MAX(ts) FROM states GROUP BY source;

-- Refresh the index statistics after a bulk import
ANALYZE TABLE states;
```

If the InfluxDB integration is still running in parallel, both archives fill up for a
while — that is harmless. Once the MariaDB archive is complete, `influxdb:` can come out
of the `configuration.yaml` and the add-on can go.

## Notes

- **Timestamps** are UTC on both sides, so nothing is converted.
- **Milliseconds:** InfluxDB stores nanoseconds, `DATETIME(3)` stores milliseconds. Two
  points of the same entity within the same millisecond collapse into one row — the
  primary key `(entity_id, ts)` allows only one, and `INSERT IGNORE` keeps the first.
- **Duplicates in the dump:** `influx_inspect` writes the TSM data and the WAL data one
  after the other, so the same point can appear twice. `INSERT IGNORE` settles that.
- **Booleans** become `value = 1` / `0` with `state = 'true'` / `'false'`, so a
  `binary_sensor` stays usable in a graph.
- **Numbers** keep the notation from the dump: `42i` becomes `42`, `-3.25e2` stays
  `-3.25e2`. Both are valid `DOUBLE` literals and land in the column as the same number.
- **Entities that no longer exist** come across as well. Their rows are harmless, and
  `DELETE FROM states WHERE entity_id LIKE …` gets rid of them afterwards.

## License

MIT License
