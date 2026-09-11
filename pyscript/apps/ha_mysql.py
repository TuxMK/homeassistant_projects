"""
SQL-Connector (pyscript-App) für Home Assistant
================================================

Stellt die Aktion `pyscript.sql_execute` bereit.

Alles Fachliche kommt aus der HA-Automatisierung: Host, Port, Datenbank,
SQL-Befehl und Parameter. Nur Benutzername und Passwort liegen in der
App-Konfiguration (configuration.yaml / secrets.yaml) und werden über
einen Login-Namen ausgewählt.

Ablage:        /config/pyscript/apps/ha_mysql.py
Abhängigkeit:  /config/pyscript/requirements.txt  ->  PyMySQL
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
    """Läuft in einem eigenen Thread und blockiert Home Assistant nicht."""
    import datetime
    import decimal

    def jsonable(value):
        # Ergebnisse müssen für die HA-Antwortvariable serialisierbar sein
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
name: SQL ausführen
description: >-
  Führt einen SQL-Befehl auf einer MariaDB/MySQL-Datenbank aus.
  Benutzername und Passwort kommen aus der App-Konfiguration (login),
  alles andere aus dem Aufruf. Antwort: ok, error, affected_rows,
  lastrowid, rows.
fields:
  query:
    description: >-
      SQL-Befehl. Werte immer als Platzhalter übergeben (%s oder %(name)s),
      nie direkt in den Text einsetzen.
    required: true
    example: "INSERT INTO states (entity_id, ts, value) VALUES (%s, %s, %s)"
    selector:
      text:
        multiline: true
  params:
    description: Werte für die Platzhalter – Liste für %s, Dictionary für %(name)s.
    example: '["sensor.gaszaehler", "2026-09-11 10:00:00.000", 1234.5]'
    selector:
      object:
  database:
    description: Datenbank (in MariaDB gleichbedeutend mit Schema).
    example: ha_archiv
    selector:
      text:
  host:
    description: Datenbank-Host.
    default: core-mariadb
    selector:
      text:
  port:
    description: Port der Datenbank.
    default: 3306
    selector:
      number:
        min: 1
        max: 65535
        mode: box
  login:
    description: Name des Logins aus der App-Konfiguration.
    example: archiv
    selector:
      text:
  charset:
    description: Zeichensatz der Verbindung.
    default: utf8mb4
    selector:
      text:
  time_zone:
    description: Zeitzone der Sitzung, z. B. +00:00 (UTC) oder SYSTEM.
    default: "+00:00"
    selector:
      text:
  connect_timeout:
    description: Timeout für den Verbindungsaufbau in Sekunden.
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
        return _fail("Kein SQL-Befehl (query) übergeben.")
    if "username" not in creds or "password" not in creds:
        return _fail(f"Login '{login}' ist in der App-Konfiguration nicht vollständig definiert.")
    if not _TZ_PATTERN.match(str(time_zone)):
        return _fail(f"Ungültige Zeitzone '{time_zone}' (erlaubt: SYSTEM oder ±HH:MM).")

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
        # Passwort taucht hier nie auf, nur Login-Name, Host und Datenbank
        return _fail(f"{login}@{host}/{database or '-'}: {err}")

    result["ok"] = True
    return result