# Maintain monthly partitions

Home Assistant blueprint that creates the partitions of the upcoming months in a
partitioned archive table and optionally drops the oldest ones.

Counterpart to [Metrics Archive (MariaDB)](../archiv_metrics/), which writes the
values. Why partitioning is worth it is explained there under
[Monthly partitioning](../archiv_metrics/README.md#monthly-partitioning).

**Version: 1.0**

## Features

- Creates missing months ahead of time, before the change of month needs them
- Drops old partitions in constant time instead of with a long `DELETE`
- Idempotent: what already exists is left alone, missed runs are caught up by the next
- Runs daily and additionally after every restart of Home Assistant
- Changes nothing as long as the table is not partitioned — it only reports that

## What a run does

1. Read the existing partitions from `information_schema.partitions`.
2. Build the target months: current month plus lead time.
3. Create the missing months with a single
   `ALTER TABLE … REORGANIZE PARTITION pmax INTO (…)`.
4. If a retention is set: drop every partition below the threshold with
   `ALTER TABLE … DROP PARTITION`.

Only months **after** the last existing partition are created. A gap in the past can
no longer be closed through `pmax` — the data of the following month is already in
the way there.

This is the SQL that gets generated:

```sql
ALTER TABLE `states` REORGANIZE PARTITION pmax INTO (
  PARTITION p2026_12 VALUES LESS THAN (TO_DAYS('2027-01-01')),
  PARTITION p2027_01 VALUES LESS THAN (TO_DAYS('2027-02-01')),
  PARTITION pmax     VALUES LESS THAN MAXVALUE);

ALTER TABLE `states` DROP PARTITION p2025_09, p2025_10;
```

## Requirements

### 1. Partition the table once

The initial `ALTER TABLE … PARTITION BY` rewrites the whole table. On a grown archive
that takes a while and locks the table — which is why this step deliberately stays
manual, to be done in a quiet minute:

```sql
ALTER TABLE states PARTITION BY RANGE (TO_DAYS(ts)) (
  PARTITION p2026_09 VALUES LESS THAN (TO_DAYS('2026-10-01')),
  PARTITION pmax     VALUES LESS THAN MAXVALUE
);
```

The first partition has to cover the oldest month present. Whatever is already in the
table is sorted into place by MariaDB itself. Everything after that is handled by the
automation.

`pmax` is mandatory: without that catch-all partition every `INSERT` with a timestamp
beyond the last bound fails — and it is exactly through `pmax` that the automation
creates new months.

### 2. A login with ALTER

The archive's write login deliberately only has `SELECT`, `INSERT`, `UPDATE`,
`DELETE`. Maintaining partitions needs `ALTER`, and the retention additionally needs
`DROP`. A separate login makes sense — in the MariaDB add-on:

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

and in the pyscript app configuration:

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

### Through the UI

1. **Settings > Automations & scenes > Blueprints**
2. Click **Import blueprint**
3. Enter the raw URL of the file `blueprint_archiv_partitions.yaml`

### Manually

Copy the file to `/config/blueprints/automation/archiv_partitions/` and reload the
automations in the developer tools.

## Configuration

### Target

| Option | Description | Default |
|--------|-------------|---------|
| Database | Name of the database in MariaDB | `ha_metrics` |
| Table | The partitioned archive table, partition column `ts` | `states` |
| Login | Login from the pyscript app configuration, needs `ALTER` | empty |

### Behavior

| Option | Description | Default |
|--------|-------------|---------|
| Lead time | How many months are kept ready ahead | `2` months |
| Retention | How many months are kept, `0` = unlimited | `0` |
| Time of day | When the daily run happens | `04:17:00` |

**The retention deletes data irreversibly.** The default `0` touches nothing. Only once
a value is set there does the automation drop old partitions — at `24` a good two years
are kept.

The lead time can be generous: empty partitions cost next to nothing, and `REORGANIZE`
is only instant as long as `pmax` is empty. If the automation first runs when data is
already sitting there, MariaDB has to move those rows.

### Connection (advanced)

| Option | Description | Default |
|--------|-------------|---------|
| Host | Database host | `core-mariadb` |
| Port | Database port | `3306` |

## Example

Two months of lead time, keep three years:

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

## Checking the result

What actually got created:

```sql
SELECT partition_name, table_rows,
       ROUND((data_length + index_length) / 1024 / 1024) AS mb
FROM information_schema.partitions
WHERE table_schema = 'ha_metrics' AND table_name = 'states'
ORDER BY partition_ordinal_position;
```

With InnoDB `table_rows` is only an estimate, which is good enough for the size
distribution.

## Notes

- If the table is not partitioned or `pmax` is missing, the automation writes a warning
  to the log (logger `archiv_partitions`) and changes nothing. That is the hint that
  the one-time partitioning above is still missing.
- `ALTER TABLE` locks the table briefly. Creating an empty partition takes
  milliseconds, and so does `DROP PARTITION` — regardless of how many rows are in it.
  The running archive blueprint copes with that, it simply retries on the next sweep.
- The automation writes no data and only reads `information_schema`, so a failed run
  cannot corrupt anything. The only risk is in the retention.

## License

MIT License
