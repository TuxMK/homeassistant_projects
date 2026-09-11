"""
SQL connector (pyscript app) for Home Assistant
================================================

Provides the action `pyscript.sql_execute`.

Everything domain specific comes from the HA automation: host, port, database,
SQL statement and parameters. Only username and password live in the app
configuration (configuration.yaml / secrets.yaml) and are picked by a login
name.

Location:    /config/pyscript/apps/ha_mysql.py
Dependency:  /config/pyscript/requirements.txt  ->  PyMySQL
"""

import re

import pymysql
import pymysql.cursors

_CFG = pyscript.app_config or {}
_LOGINS = _CFG.get("logins", {})
_DEFAULT_LOGIN = _CFG.get("default_login")
_TZ_PATTERN = re.compile(r"^(SYSTEM|[+-]\d{2}:\d{2})$")


@pyscript_executor
def _run_sql(conn_args, query, params):
    """Runs in its own thread and does not block Home Assistant."""
    import datetime
    import decimal

    def jsonable(value):
        # Results have to be serializable for the HA response variable
        if isinstance(value, (datetime.datetime, datetime.date, datetime.time)):
            return value.isoformat()
        if isinstance(value, datetime.timedelta):
            return value.total_seconds()
        if isinstance(value, decimal.Decimal):
            return float(value)
        if isinstance(value, (bytes, bytearray)):
            return value.decode("utf-8", errors="replace")
        return value

    conn = pymysql.connect(cursorclass=pymysql.cursors.DictCursor, **conn_args)
    try:
        with conn.cursor() as cur:
            affected = cur.execute(query, params)
            rows = cur.fetchall() if cur.description else []
            lastrowid = cur.lastrowid
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    return {
        "affected_rows": affected,
        "lastrowid": lastrowid,
        "rows": [{k: jsonable(v) for k, v in row.items()} for row in rows],
    }


def _fail(message):
    log.error(f"sql_execute: {message}")
    return {"ok": False, "error": message}


@service(supports_response="optional")
def sql_execute(query=None, params=None, database=None, host="core-mariadb",
                port=3306, login=None, charset="utf8mb4", time_zone="+00:00",
                connect_timeout=5):
    """yaml
name: Run SQL
description: >-
  Runs a SQL statement on a MariaDB/MySQL database.
  Username and password come from the app configuration (login),
  everything else from the call. Response: ok, error, affected_rows,
  lastrowid, rows.
fields:
  query:
    description: >-
      SQL statement. Always pass values as placeholders (%s or %(name)s),
      never inline them into the text.
    required: true
    example: "INSERT INTO states (entity_id, ts, value) VALUES (%s, %s, %s)"
    selector:
      text:
        multiline: true
  params:
    description: Values for the placeholders - list for %s, dictionary for %(name)s.
    example: '["sensor.gaszaehler", "2026-09-11 10:00:00.000", 1234.5]'
    selector:
      object:
  database:
    description: Database (in MariaDB the same as schema).
    example: ha_metrics
    selector:
      text:
  host:
    description: Database host.
    default: core-mariadb
    selector:
      text:
  port:
    description: Database port.
    default: 3306
    selector:
      number:
        min: 1
        max: 65535
        mode: box
  login:
    description: Name of the login from the app configuration.
    example: archiv
    selector:
      text:
  charset:
    description: Character set of the connection.
    default: utf8mb4
    selector:
      text:
  time_zone:
    description: Session time zone, e. g. +00:00 (UTC) or SYSTEM.
    default: "+00:00"
    selector:
      text:
  connect_timeout:
    description: Timeout for establishing the connection, in seconds.
    default: 5
    selector:
      number:
        min: 1
        max: 60
        mode: box
"""
    login = login or _DEFAULT_LOGIN or next(iter(_LOGINS), None)
    creds = _LOGINS.get(login) or {}

    if not query:
        return _fail("No SQL statement (query) was passed.")
    if "username" not in creds or "password" not in creds:
        return _fail(f"Login '{login}' is not fully defined in the app configuration.")
    if not _TZ_PATTERN.match(str(time_zone)):
        return _fail(f"Invalid time zone '{time_zone}' (allowed: SYSTEM or +/-HH:MM).")

    conn_args = {
        "host": host,
        "port": int(port),
        "user": creds["username"],
        "password": creds["password"],
        "database": database,
        "charset": charset,
        "connect_timeout": int(connect_timeout),
        "init_command": f"SET time_zone = '{time_zone}'",
    }

    try:
        result = _run_sql(conn_args, query, params)
    except Exception as err:
        # The password never shows up here, only login name, host and database
        return _fail(f"{login}@{host}/{database or '-'}: {err}")

    result["ok"] = True
    return result