#!/usr/bin/env bash
# ------------------------------------------------------------------
# Wrapper for recorder_sqlite_to_mariadb.py - one command per step
#
#   check    dry run: checks and row counts, writes nothing
#   full     full copy in the background (survives a closed terminal)
#   status   is a run active? last lines of the newest log
#   log      follow the newest log (Ctrl+C only stops watching)
#   delta    catch up right before the switch, then offer the restart
#
# Extra arguments go straight to the Python script, e.g.
#   bash run_migration.sh full --only-statistics
#
# The password comes from MARIADB_PASSWORD, otherwise from secrets.yaml
# (SECRET_KEY), otherwise it is prompted.
#
# Call:    bash run_migration.sh <check|full|status|log|delta> [options]
# ------------------------------------------------------------------

set -euo pipefail

# ============ CONFIG ============
SQLITE="/homeassistant/home-assistant_v2.db"
HOST="core-mariadb"
PORT=3306
DB_USER="homeassistant"
DATABASE="ha_records"
SECRETS="/homeassistant/secrets.yaml"
SECRET_KEY="mysql_password"      # key in secrets.yaml, empty = always prompt
CONFIG_YAML="/homeassistant/configuration.yaml"
LOGDIR="/share/recorder_migration"
# ================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/recorder_sqlite_to_mariadb.py"
PIDFILE="$LOGDIR/run.pid"

MODE="${1:-}"
shift || true
EXTRA=("$@")

usage() {
    sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

# --- helpers ---------------------------------------------------------

ask() {  # ask "question" -> 0 on y/j
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[yYjJ]$ ]]
}

running_pid() {
    [ -f "$PIDFILE" ] || return 1
    local pid
    pid=$(cat "$PIDFILE")
    if kill -0 "$pid" 2>/dev/null; then
        echo "$pid"
        return 0
    fi
    rm -f "$PIDFILE"
    return 1
}

latest_log() {
    ls -1t "$LOGDIR"/*.log 2>/dev/null | head -n 1
}

require_python() {
    [ -f "$PY_SCRIPT" ] || { echo "Not found: $PY_SCRIPT (both files belong in the same folder)"; exit 1; }
    [ -f "$SQLITE" ] || { echo "SQLite file not found: $SQLITE - adjust SQLITE at the top"; exit 1; }
    if python3 -c "import pymysql" 2>/dev/null; then
        return
    fi
    if command -v apk >/dev/null 2>&1; then
        echo "Installing python3 and PyMySQL into this add-on container ..."
        apk add --no-cache python3 py3-pymysql >/dev/null
    else
        echo "python3 with PyMySQL is missing: pip install pymysql"
        exit 1
    fi
}

load_password() {
    [ -n "${MARIADB_PASSWORD:-}" ] && return
    if [ -n "$SECRET_KEY" ] && [ -f "$SECRETS" ]; then
        local value
        value=$(sed -n "s/^${SECRET_KEY}:[[:space:]]*//p" "$SECRETS" | head -n 1 | tr -d '\r')
        value="${value%"${value##*[![:space:]]}"}"          # trailing blanks
        if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi
        if [ -n "$value" ]; then
            MARIADB_PASSWORD="$value"
            echo "Password: '$SECRET_KEY' from $SECRETS"
        fi
    fi
    if [ -z "${MARIADB_PASSWORD:-}" ]; then
        read -r -s -p "Password for $DB_USER@$HOST: " MARIADB_PASSWORD
        echo
    fi
    export MARIADB_PASSWORD
}

base_args() {
    ARGS=(--sqlite "$SQLITE" --host "$HOST" --port "$PORT"
          --user "$DB_USER" --database "$DATABASE")
}

refuse_if_running() {
    local pid
    if pid=$(running_pid); then
        echo "A run is still active (PID $pid). Follow it with: bash $0 log"
        exit 1
    fi
}

# --- modes -----------------------------------------------------------

mode_check() {
    refuse_if_running
    require_python
    load_password
    base_args
    python3 "$PY_SCRIPT" "${ARGS[@]}" --truncate --dry-run "${EXTRA[@]}"
}

mode_full() {
    refuse_if_running
    require_python
    load_password
    base_args
    echo ""
    echo "Full run: empties every table in '$DATABASE' (except schema_changes)"
    echo "and copies $SQLITE into it. Home Assistant keeps running."
    ask "Start?" || exit 0

    mkdir -p "$LOGDIR"
    local log="$LOGDIR/full_$(date +%Y%m%d_%H%M%S).log"
    # Own session (setsid) and nohup: closing the web terminal neither hangs
    # up nor kills the run. setsid may fork, so the runner writes its own PID.
    # The exit code lands at the end of the log.
    local detach=()
    command -v setsid >/dev/null 2>&1 && detach=(setsid)
    rm -f "$PIDFILE"
    nohup "${detach[@]}" bash -c '
        pidfile=$1; shift
        echo $$ >"$pidfile"
        python3 "$@"
        rc=$?
        echo ""
        echo "EXIT CODE: $rc"
    ' _ "$PIDFILE" "$PY_SCRIPT" "${ARGS[@]}" --truncate "${EXTRA[@]}" >"$log" 2>&1 </dev/null &
    disown 2>/dev/null || true

    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        [ -s "$PIDFILE" ] && break
        sleep 0.2
    done

    echo ""
    echo "Running in the background (PID $(cat "$PIDFILE" 2>/dev/null || echo ?)), log: $log"
    echo "Ctrl+C only stops watching - the run goes on."
    echo "Later:  bash $0 status   or   bash $0 log"
    echo ""
    tail -n +1 -f "$log"
}

mode_status() {
    local pid log
    log=$(latest_log || true)
    if pid=$(running_pid); then
        echo "Run active (PID $pid)"
    else
        echo "No run active"
    fi
    if [ -n "$log" ]; then
        echo "Newest log: $log"
        echo ""
        tail -n 25 "$log"
    fi
}

mode_log() {
    local log
    log=$(latest_log || true)
    [ -n "$log" ] || { echo "No log in $LOGDIR yet"; exit 1; }
    echo "Following $log (Ctrl+C stops watching)"
    tail -n 40 -f "$log"
}

mode_delta() {
    refuse_if_running
    require_python

    if ! grep -qE '^[[:space:]]*db_url:' "$CONFIG_YAML" 2>/dev/null; then
        echo "No active 'db_url:' in $CONFIG_YAML."
        echo "Enable it first (do not restart yet) - the restart right after the delta"
        echo "is what switches Home Assistant over."
        ask "Continue anyway (db_url lives in a package)?" || exit 1
    fi

    # Decide on the restart and check the configuration BEFORE the delta:
    # the snapshot is taken when the delta starts, so every second between
    # its start and the restart is history that stays behind in SQLite.
    local restart=0
    if command -v ha >/dev/null 2>&1; then
        if ask "Restart Home Assistant right after a clean delta?"; then
            echo "Checking the configuration first ..."
            if ! ha core check; then
                echo "Configuration check failed - fix it first, nothing was copied."
                exit 1
            fi
            restart=1
        fi
    fi

    load_password
    base_args
    mkdir -p "$LOGDIR"
    local log="$LOGDIR/delta_$(date +%Y%m%d_%H%M%S).log"

    # Foreground: the delta takes seconds to minutes and can simply be repeated
    set +e
    python3 "$PY_SCRIPT" "${ARGS[@]}" --mode delta "${EXTRA[@]}" 2>&1 | tee "$log"
    local rc=${PIPESTATUS[0]}
    set -e
    echo "EXIT CODE: $rc" >>"$log"

    if [ "$rc" -ne 0 ]; then
        echo ""
        echo "Delta did not finish cleanly (exit $rc) - no restart. Log: $log"
        exit "$rc"
    fi

    echo ""
    if [ "$restart" -eq 1 ]; then
        echo "Delta done - restarting Home Assistant ..."
        ha core restart
    else
        echo "Delta done, no restart. Run the next delta, or restart as soon as possible."
    fi
}

case "$MODE" in
    check)  mode_check ;;
    full)   mode_full ;;
    status) mode_status ;;
    log)    mode_log ;;
    delta)  mode_delta ;;
    *)      usage ;;
esac
