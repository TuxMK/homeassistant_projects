#!/usr/bin/env python3
"""
Migrate the Home Assistant recorder from SQLite to MariaDB
===========================================================

Copies the data of home-assistant_v2.db into a MariaDB database whose schema
Home Assistant created itself. Only data moves - column types, indexes and the
collation stay exactly as the recorder defines them for MariaDB.

Modes:
  full    copy everything. The target has to be empty, or --truncate empties
          it first (every table except schema_changes).
  delta   catch up on what the running Home Assistant wrote to SQLite since
          the full run: new rows by primary key, the small lookup tables as
          upsert, and last_reported_ts on states that already exist.

The source is read inside ONE read transaction. Home Assistant runs SQLite in
WAL mode, so that transaction sees a consistent snapshot while the recorder
keeps writing - Home Assistant does not have to be stopped. Run it on the HA
host itself (SSH add-on) or against a copy; WAL over a network share is not
safe.

Call:
  python3 recorder_sqlite_to_mariadb.py --sqlite /config/home-assistant_v2.db \\
      --host core-mariadb --user homeassistant --database homeassistant --truncate
  ... --mode delta                  # right before the restart onto MariaDB
  ... --only-statistics             # long-term statistics only, no history
  ... --dry-run                     # checks and row counts, writes nothing

Password: environment variable MARIADB_PASSWORD, otherwise it is prompted.
Dependency: PyMySQL (pip install pymysql / apk add py3-pymysql)
"""

import argparse
import getpass
import os
import pathlib
import re
import sqlite3
import sys
import time
from datetime import datetime

try:
    import pymysql
except ImportError:
    sys.exit("PyMySQL is missing: pip install pymysql  (SSH add-on: apk add py3-pymysql)")

# Copy order: referenced tables first. Foreign key checks are off during the
# import anyway - the order only keeps an interrupted run easy to read.
TABLE_ORDER = [
    "event_types",
    "event_data",
    "events",
    "states_meta",
    "state_attributes",
    "states",
    "statistics_meta",
    "statistics",
    "statistics_short_term",
    "statistics_runs",
    "recorder_runs",
    "migration_changes",
]

# --only-statistics: long-term statistics without history and logbook.
# migration_changes belongs to it, otherwise HA re-checks every data migration.
STATISTICS_TABLES = [
    "statistics_meta",
    "statistics",
    "statistics_short_term",
    "statistics_runs",
    "migration_changes",
]

# Never touched: the target keeps the schema version Home Assistant wrote.
SKIP_TABLES = {"schema_changes"}

# Small lookup tables that Home Assistant updates in place (entity renames,
# unit changes, the end of a run). The delta run upserts them completely.
UPSERT_TABLES = {"event_types", "states_meta", "statistics_meta", "recorder_runs", "migration_changes"}

# Unused legacy columns that are not CHAR(0) in MariaDB. Old contents would
# not fit the type (SMALLINT), so they stay NULL like every CHAR(0) column.
LEGACY_COLUMNS = {("states", "event_id")}

EXPECTED_COLLATION = "utf8mb4_bin"
DATETIME_PREFIX = re.compile(r"^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?)")


def log(msg=""):
    print(msg, flush=True)


def fail(msg):
    log("")
    log(f"ABORT: {msg}")
    sys.exit(1)


class Plan:
    """What gets copied from one table, and how the values are prepared."""

    def __init__(self, table):
        self.table = table
        self.columns = []  # copied columns, in target order
        self.pk = None
        self.varchar_limits = {}  # column index -> max length
        self.datetime_idx = set()  # column indexes of DATETIME columns
        self.legacy = []  # columns left NULL
        self.truncated = 0

    def convert(self, row):
        row = list(row)
        for i, limit in self.varchar_limits.items():
            value = row[i]
            if isinstance(value, str) and len(value) > limit:
                row[i] = value[:limit]
                self.truncated += 1
        for i in self.datetime_idx:
            value = row[i]
            if isinstance(value, str):
                # SQLite stores "YYYY-MM-DD HH:MM:SS.ffffff", sometimes with a
                # "T" or a zone suffix - MariaDB DATETIME takes neither
                m = DATETIME_PREFIX.match(value)
                row[i] = f"{m.group(1)} {m.group(2)}" if m else None
        return row

    @property
    def needs_convert(self):
        return bool(self.varchar_limits or self.datetime_idx)


# --- arguments -------------------------------------------------------


def parse_args():
    p = argparse.ArgumentParser(
        description="Copy the Home Assistant recorder data from SQLite into a MariaDB schema created by Home Assistant."
    )
    p.add_argument("--sqlite", required=True, help="path to home-assistant_v2.db (live file or copy)")
    p.add_argument("--host", default="core-mariadb")
    p.add_argument("--port", type=int, default=3306)
    p.add_argument("--user", required=True)
    p.add_argument("--database", default="homeassistant")
    p.add_argument("--mode", choices=["full", "delta"], default="full")
    p.add_argument("--truncate", action="store_true", help="full: empty the target tables first")
    p.add_argument("--only-statistics", action="store_true", help="copy long-term statistics only")
    p.add_argument("--dry-run", action="store_true", help="run the checks and count rows, write nothing")
    p.add_argument("--batch", type=int, default=5000, help="rows per INSERT (default 5000)")
    return p.parse_args()


# --- SQLite ----------------------------------------------------------


def sqlite_open(path):
    file = pathlib.Path(path).absolute()
    if not file.is_file():
        fail(f"SQLite file not found: {file}")
    con = sqlite3.connect(f"{file.as_uri()}?mode=ro", uri=True, isolation_level=None)
    # Broken UTF-8 in an old attribute must not stop a run of hours
    con.text_factory = lambda b: b.decode("utf-8", errors="replace")
    journal = con.execute("PRAGMA journal_mode").fetchone()[0]
    # One read transaction for the whole run; the first read pins the snapshot
    con.execute("BEGIN")
    con.execute("SELECT COUNT(*) FROM sqlite_master").fetchone()
    return con, journal


def sqlite_tables(con):
    rows = con.execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
    return {r[0] for r in rows}


def sqlite_columns(con, table):
    return {r[1] for r in con.execute(f'PRAGMA table_info("{table}")')}


def sqlite_count(con, table, where="", params=()):
    return con.execute(f'SELECT COUNT(*) FROM "{table}" {where}', params).fetchone()[0]


def schema_version_sqlite(con):
    row = con.execute("SELECT schema_version FROM schema_changes ORDER BY change_id DESC LIMIT 1").fetchone()
    return row[0] if row else None


# --- MariaDB ---------------------------------------------------------


def maria_connect(args):
    password = os.environ.get("MARIADB_PASSWORD")
    if password is None:
        password = getpass.getpass(f"Password for {args.user}@{args.host}: ")
    try:
        return pymysql.connect(
            host=args.host,
            port=args.port,
            user=args.user,
            password=password,
            database=args.database,
            charset="utf8mb4",
            autocommit=False,
        )
    except pymysql.MySQLError as err:
        fail(f"no connection to {args.database} on {args.host}:{args.port}: {err}")


def maria_one(mcon, sql, params=()):
    with mcon.cursor() as cur:
        cur.execute(sql, params)
        row = cur.fetchone()
    return row[0] if row else None


def maria_columns(mcon, db, table):
    with mcon.cursor() as cur:
        cur.execute(
            """SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, COLUMN_KEY
               FROM information_schema.COLUMNS
               WHERE TABLE_SCHEMA = %s AND TABLE_NAME = %s
               ORDER BY ORDINAL_POSITION""",
            (db, table),
        )
        return cur.fetchall()


def maria_count(mcon, table):
    return maria_one(mcon, f"SELECT COUNT(*) FROM `{table}`")


# --- checks ----------------------------------------------------------


def build_plans(scon, mcon, db, wanted):
    s_tables = sqlite_tables(scon)
    plans = []
    for table in wanted:
        if table not in s_tables:
            log(f"   {table:<24} not in SQLite, skipped")
            continue
        mcols = maria_columns(mcon, db, table)
        if not mcols:
            fail(f"table '{table}' is missing in MariaDB - let Home Assistant create the schema first")
        scols = sqlite_columns(scon, table)
        plan = Plan(table)
        for name, dtype, maxlen, key in mcols:
            if key == "PRI" and plan.pk is None:
                plan.pk = name
            if name not in scols:
                continue  # target-only column keeps its default
            if (dtype == "char" and maxlen == 0) or (table, name) in LEGACY_COLUMNS:
                plan.legacy.append(name)
                continue
            if dtype in ("varchar", "char") and maxlen:
                plan.varchar_limits[len(plan.columns)] = maxlen
            if dtype in ("datetime", "timestamp"):
                plan.datetime_idx.add(len(plan.columns))
            plan.columns.append(name)
        if plan.pk is None or plan.pk not in plan.columns:
            fail(f"table '{table}' has no usable primary key")
        only_sqlite = sorted(scols - {c[0] for c in mcols})
        if only_sqlite:
            log(f"   {table:<24} columns only in SQLite, not copied: {', '.join(only_sqlite)}")
        plans.append(plan)

    extra = sorted(s_tables - set(TABLE_ORDER) - SKIP_TABLES)
    if extra:
        log(f"   tables outside the recorder schema, not copied: {', '.join(extra)}")
    return plans


def check_versions(scon, mcon):
    s_ver = schema_version_sqlite(scon)
    m_ver = maria_one(mcon, "SELECT schema_version FROM schema_changes ORDER BY change_id DESC LIMIT 1")
    log(f"Schema:   SQLite {s_ver}   MariaDB {m_ver}")
    if m_ver is None:
        fail("schema_changes in MariaDB is empty - let Home Assistant create the schema first")
    if s_ver != m_ver:
        fail(
            "schema versions differ. Create the MariaDB schema with the same Home Assistant "
            "version the SQLite file comes from, and do not update in between."
        )


def check_collation(mcon, db):
    with mcon.cursor() as cur:
        cur.execute(
            "SELECT TABLE_NAME, TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_SCHEMA = %s",
            (db,),
        )
        wrong = [f"{t} ({c})" for t, c in cur.fetchall() if c != EXPECTED_COLLATION]
    if wrong:
        log(f"   Note: collation is not {EXPECTED_COLLATION} for {', '.join(wrong)}")
        log("         Home Assistant corrects this on start, but it rewrites the tables.")


def check_target_not_live(scon, mcon):
    """Delta only: refuse when Home Assistant already writes into MariaDB.

    Its runs would carry IDs that SQLite uses for different rows, so the delta
    would mix two histories. The newest statistics run in MariaDB has to be one
    that exists in SQLite with the same start.
    """
    with mcon.cursor() as cur:
        cur.execute("SELECT run_id, start FROM statistics_runs ORDER BY run_id DESC LIMIT 1")
        row = cur.fetchone()
    if row is None:
        fail("the target holds no statistics runs - run --mode full first")
    run_id, m_start = row
    s_row = scon.execute("SELECT start FROM statistics_runs WHERE run_id = ?", (run_id,)).fetchone()
    s_start = None
    if s_row and isinstance(s_row[0], str) and DATETIME_PREFIX.match(s_row[0]):
        m = DATETIME_PREFIX.match(s_row[0])
        s_start = datetime.fromisoformat(f"{m.group(1)} {m.group(2)}")
    if s_start is None or m_start is None or abs((s_start - m_start).total_seconds()) > 1:
        fail(
            f"statistics run {run_id} in MariaDB ({m_start}) does not match SQLite ({s_start}). "
            "Home Assistant seems to write into MariaDB already - a delta is no longer possible."
        )


# --- copying ---------------------------------------------------------


def copy_rows(scon, mcon, plan, args, where="", params=(), upsert=None, label="rows"):
    """Stream rows from SQLite into MariaDB. Returns the number of rows sent."""
    expected = sqlite_count(scon, plan.table, where, params)
    if args.dry_run or expected == 0:
        return expected

    col_list = ", ".join(f"`{c}`" for c in plan.columns)
    marks = ", ".join(["%s"] * len(plan.columns))
    # PyMySQL turns executemany on this shape into multi-row INSERT statements
    sql = f"INSERT INTO `{plan.table}` ({col_list}) VALUES ({marks})"
    if upsert:
        sql += " ON DUPLICATE KEY UPDATE " + ", ".join(f"`{c}` = VALUES(`{c}`)" for c in upsert)

    select_cols = ", ".join(f'"{c}"' for c in plan.columns)
    src = scon.execute(f'SELECT {select_cols} FROM "{plan.table}" {where} ORDER BY "{plan.pk}"', params)

    sent = 0
    started = last_report = time.monotonic()
    with mcon.cursor() as cur:
        while True:
            rows = src.fetchmany(args.batch)
            if not rows:
                break
            if plan.needs_convert:
                rows = [plan.convert(r) for r in rows]
            cur.executemany(sql, rows)
            mcon.commit()
            sent += len(rows)
            now = time.monotonic()
            if now - last_report >= 5:
                rate = sent / (now - started)
                eta = (expected - sent) / rate if rate else 0
                log(f"   {plan.table:<24} {sent:>12,} / {expected:,} {label}  ({rate:,.0f}/s, ~{eta / 60:.0f} min left)")
                last_report = now
    return sent


def run_full(scon, mcon, plans, args):
    targets = [t for t in TABLE_ORDER if maria_columns(mcon, args.database, t)]
    filled = {t: n for t in targets if (n := maria_count(mcon, t))}
    if filled:
        listing = ", ".join(f"{t} {n:,}" for t, n in filled.items())
        if not args.truncate:
            fail(f"target is not empty ({listing}). Run with --truncate to empty it first.")
        log(f"Emptying: {listing}")
        # Always every table, also with --only-statistics: rows Home Assistant
        # wrote during the schema creation point at IDs that are about to change
        if not args.dry_run:
            with mcon.cursor() as cur:
                for t in filled:
                    cur.execute(f"TRUNCATE TABLE `{t}`")
            mcon.commit()

    log("")
    totals = {}
    for plan in plans:
        t0 = time.monotonic()
        totals[plan.table] = copy_rows(scon, mcon, plan, args)
        took = time.monotonic() - t0
        log(f"   {plan.table:<24} {totals[plan.table]:>12,} rows  ({took:,.0f}s)")
    return totals


def run_delta(scon, mcon, plans, args):
    check_target_not_live(scon, mcon)
    log("")
    totals = {}
    for plan in plans:
        t0 = time.monotonic()
        if plan.table in UPSERT_TABLES:
            others = [c for c in plan.columns if c != plan.pk]
            n = copy_rows(scon, mcon, plan, args, upsert=others or [plan.pk], label="upserted")
            note = "upserted"
        else:
            max_id = maria_one(mcon, f"SELECT COALESCE(MAX(`{plan.pk}`), 0) FROM `{plan.table}`")
            reported_since = None
            if plan.table == "states" and "last_reported_ts" in plan.columns:
                # Moment of the full run, as far as the target can tell
                reported_since = maria_one(
                    mcon,
                    "SELECT GREATEST(COALESCE(MAX(last_reported_ts), 0), COALESCE(MAX(last_updated_ts), 0)) "
                    "FROM states",
                )
            n = copy_rows(scon, mcon, plan, args, where=f'WHERE "{plan.pk}" > ?', params=(max_id,))
            note = "new"
            if reported_since is not None:
                # Home Assistant moves last_reported_ts forward on the newest
                # state of an entity instead of writing a new row
                u = copy_rows(
                    scon,
                    mcon,
                    plan,
                    args,
                    where='WHERE "state_id" <= ? AND "last_reported_ts" > ?',
                    params=(max_id, reported_since),
                    upsert=["last_reported_ts"],
                    label="refreshed",
                )
                note = f"new, {u:,} last_reported refreshed"
        totals[plan.table] = n
        log(f"   {plan.table:<24} {n:>12,} {note}  ({time.monotonic() - t0:,.0f}s)")
    return totals


# --- main ------------------------------------------------------------


def main():
    args = parse_args()
    if args.mode == "delta" and args.truncate:
        fail("--truncate belongs to --mode full; a delta builds on the full run")

    scon, journal = sqlite_open(args.sqlite)
    mcon = maria_connect(args)

    log(f"Source:   {args.sqlite}  (journal mode {journal})")
    log(f"Target:   {args.database} on {args.host}:{args.port} as '{args.user}'")
    log(f"Mode:     {args.mode}{', statistics only' if args.only_statistics else ''}{', DRY RUN' if args.dry_run else ''}")
    if journal.lower() != "wal":
        log("   Note: the file is not in WAL mode. If Home Assistant is writing to it, the")
        log("         read transaction blocks the recorder - use a copy instead.")

    check_versions(scon, mcon)
    check_collation(mcon, args.database)

    wanted = STATISTICS_TABLES if args.only_statistics else TABLE_ORDER
    plans = build_plans(scon, mcon, args.database, wanted)
    for plan in plans:
        if plan.legacy:
            log(f"   {plan.table:<24} legacy columns left NULL: {', '.join(plan.legacy)}")

    with mcon.cursor() as cur:
        # SQLite enforces no foreign keys on this data and the rows arrive
        # table by table - the references only close once everything is in
        cur.execute("SET SESSION foreign_key_checks = 0")

    started = time.monotonic()
    try:
        if args.mode == "full":
            run_full(scon, mcon, plans, args)
        else:
            run_delta(scon, mcon, plans, args)
    except (pymysql.MySQLError, KeyboardInterrupt) as err:
        mcon.rollback()
        # Every batch commits in primary key order, so a delta simply resumes;
        # a full run left a partial copy behind
        again = "--mode delta" if args.mode == "delta" else "--mode full --truncate"
        reason = "interrupted" if isinstance(err, KeyboardInterrupt) else f"MariaDB refused a write: {err}"
        fail(f"{reason}. The target is incomplete - start again with {again}.")

    truncated = sum(p.truncated for p in plans)
    if truncated:
        log(f"\n   {truncated:,} text values were longer than their column and were shortened")

    if args.dry_run:
        log("\n(dry run - nothing was written)")
        return

    # Counts within the snapshot against the target. After a delta the target
    # may hold more: rows SQLite purged since the full run stay in MariaDB
    # until Home Assistant purges them there.
    log("\nCheck (rows in the SQLite snapshot / in MariaDB):")
    mismatch = False
    for plan in plans:
        s_n = sqlite_count(scon, plan.table)
        m_n = maria_count(mcon, plan.table)
        ok = m_n == s_n if args.mode == "full" else m_n >= s_n
        mismatch |= not ok
        log(f"   {plan.table:<24} {s_n:>12,} / {m_n:>12,}  {'ok' if ok else 'MISMATCH'}")

    log("\nRefreshing the index statistics ...")
    with mcon.cursor() as cur:
        for plan in plans:
            cur.execute(f"ANALYZE TABLE `{plan.table}`")
            cur.fetchall()

    scon.execute("COMMIT")
    log(f"Done in {(time.monotonic() - started) / 60:,.1f} min.")
    if mismatch:
        sys.exit(2)


if __name__ == "__main__":
    main()
