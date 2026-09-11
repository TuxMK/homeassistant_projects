#!/usr/bin/env bash
# ------------------------------------------------------------------
# Import line protocol dumps into the MariaDB metrics archive
#
# Reads the .lp files written by influx_export_monthly.sh, turns them
# into INSERT IGNORE statements and pipes them straight into the
# mysql client - no intermediate .sql files.
#
# Schema mapping:
#   tag domain + tag entity_id  ->  entity_id
#   time (ns, UTC)              ->  ts (DATETIME(3), UTC)
#   field value / field state   ->  value / state
#   measurement name            ->  unit (empty if it contains a dot)
#                               ->  source = 'import'
#
# INSERT IGNORE keeps whatever is already in the table: rows written
# by the automation and manual corrections are never overwritten, and
# running the same file twice does no harm.
#
# Call:    ./influx_import_mysql.sh <db-user> <db-password>
#          DRYRUN=1 ./influx_import_mysql.sh user pass   # print SQL only
# ------------------------------------------------------------------

set -e
set -o pipefail

# ============ CONFIG ============
LPDIR="./influx_export"         # directory holding the .lp / .lp.gz files
HOST="core-mariadb"
PORT=3306
DB="ha_metrics"
TABLE="states"

SOURCE="import"                 # value for the source column
UNTIL="2026-09-11 14:05:58.529" # cut-off (UTC): nothing from this moment on.
                                # Set it to the first row the archive
                                # automation wrote itself, so the import stops
                                # exactly where the live data begins.
                                # Empty = import everything.
                                # "YYYY-MM-DD", "... HH:MM:SS" and
                                # "... HH:MM:SS.mmm" are all accepted.
MIN_INTERVAL=0                  # seconds between two rows per entity, 0 = all
DOMAINS=""                      # e. g. "sensor" - empty = every domain
NUMERIC_ONLY=0                  # 1 = skip points without a numeric value
PRECISION="ns"                  # timestamp precision in the dump
BATCH=1000                      # rows per INSERT statement
# ================================

DRYRUN=${DRYRUN:-0}

USER_NAME=$1
PASSWORD=$2
if [ -z "$USER_NAME" ] || [ -z "$PASSWORD" ]; then
    echo "Usage: $0 <db-user> <db-password>"
    exit 1
fi

command -v awk >/dev/null || { echo "awk not found."; exit 1; }

# The comparison happens on the formatted timestamp, so the cut-off has to
# carry the same shape. A shorter form is filled up to the END of the period
# it names - "2026-09-11" therefore means the whole day, not midnight.
case "$UNTIL" in
    "")                                                          ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
        UNTIL="$UNTIL 23:59:59.999" ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "[0-9][0-9]:[0-9][0-9]:[0-9][0-9])
        UNTIL="$UNTIL.999" ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9])
        ;;
    *)
        echo "UNTIL='$UNTIL' is not a valid moment."
        echo "Expected YYYY-MM-DD, 'YYYY-MM-DD HH:MM:SS' or 'YYYY-MM-DD HH:MM:SS.mmm'."
        exit 1 ;;
esac

# MariaDB 11 renamed the client; the old name still works but warns on
# every single call, which would bury the progress output
if command -v mariadb >/dev/null 2>&1; then
    MYSQL_CMD="mariadb"
elif command -v mysql >/dev/null 2>&1; then
    MYSQL_CMD="mysql"
elif [ "$DRYRUN" != "1" ]; then
    echo "No mariadb/mysql client found - install it with: sudo apt install mariadb-client"
    exit 1
fi

# The password goes into a file with mode 600 instead of the command
# line, where `ps` would show it to every user on the machine
CNF=$(mktemp)
STATS=$(mktemp)
chmod 600 "$CNF"
trap 'rm -f "$CNF" "$STATS"' EXIT INT TERM
cat > "$CNF" <<EOF
[client]
user=$USER_NAME
password=$PASSWORD
host=$HOST
port=$PORT
default-character-set=utf8mb4
EOF

mysql_run() { "$MYSQL_CMD" --defaults-extra-file="$CNF" "$@"; }

# --- files ---------------------------------------------------------
shopt -s nullglob
FILES=()
while IFS= read -r line; do FILES+=("$line"); done < <(
    printf '%s\n' "$LPDIR"/*.lp "$LPDIR"/*.lp.gz 2>/dev/null | sort
)
shopt -u nullglob
if [ ${#FILES[@]} -eq 0 ]; then
    echo "No .lp or .lp.gz files in '$LPDIR'."
    exit 1
fi

# --- connection and table ------------------------------------------
if [ "$DRYRUN" != "1" ]; then
    mysql_run -e "SELECT 1" "$DB" >/dev/null 2>&1 || {
        echo "No connection to $DB on $HOST:$PORT as '$USER_NAME'."
        exit 1
    }
    mysql_run -N -e \
        "SELECT COUNT(*) FROM information_schema.tables
         WHERE table_schema='$DB' AND table_name='$TABLE'" | grep -q '^1$' || {
        echo "Table '$DB.$TABLE' does not exist. Create it with:"
        echo ""
        echo "  CREATE TABLE $TABLE ("
        echo "    entity_id VARCHAR(255) NOT NULL,"
        echo "    ts        DATETIME(3)  NOT NULL,"
        echo "    value     DOUBLE       NULL,"
        echo "    state     VARCHAR(255) NULL,"
        echo "    unit      VARCHAR(32)  NULL,"
        echo "    source    VARCHAR(16)  NOT NULL DEFAULT 'ha',"
        echo "    PRIMARY KEY (entity_id, ts)"
        echo "  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"
        exit 1
    }
    echo "Connected to $DB.$TABLE on $HOST:$PORT as '$USER_NAME'"
fi

echo "Files:    ${#FILES[@]} in $LPDIR"
echo "Throttle: ${MIN_INTERVAL}s   Domains: ${DOMAINS:-all}   Source: $SOURCE"
echo "Cut-off:  ${UNTIL:-none}"
echo ""

# --- the converter -------------------------------------------------
# Byte-wise locale: substr/length then work on bytes, which keeps
# multi-byte units such as °C and m³ intact and is noticeably faster.
LP_TO_SQL='
function q(s) {                           # MariaDB string literal
    if (index(s, "\\") || index(s, Q) || index(s, "\n") || index(s, "\r")) {
        gsub(/\\/, "\\\\&", s)          # one backslash -> two
        gsub(Q, "\\\\&", s)               # apostrophe -> \apostrophe
        gsub(/\n/, "\\n", s)
        gsub(/\r/, "\\r", s)
    }
    return Q s Q
}
function unesc(s) {                       # line protocol escapes
    if (index(s, "\\") == 0) return s   # the common case, untouched
    gsub(/\\,/, ",", s)
    gsub(/\\ /, " ", s)
    gsub(/\\=/, "=", s)
    return s
}
function unq(s) {                         # inside a quoted string
    gsub(/\\"/, "\"", s)
    gsub(/\\\\/, "\\", s)
    return s
}
# First separator that is not backslash-escaped
function unescaped(s, ch,   p, off) {
    off = 0
    while (1) {
        p = index(substr(s, off + 1), ch)
        if (p == 0) return 0
        p += off
        if (p == 1 || substr(s, p - 1, 1) != "\\") return p
        off = p
    }
}
# Milliseconds since the epoch -> "YYYY-MM-DD HH:MM:SS.mmm" in UTC.
# Own civil-date arithmetic: strftime() exists in gawk only, and this
# has to run under mawk and busybox awk as well.
function stamp(ms,   days, rem, z, era, doe, yoe, y, doy, mp, d, m, hh, mi, ss, msec) {
    days = int(ms / 86400000); rem = ms - days * 86400000
    if (rem < 0) { days -= 1; rem += 86400000 }
    z = days + 719468
    era = int(z / 146097); doe = z - era * 146097
    yoe = int((doe - int(doe/1460) + int(doe/36524) - int(doe/146096)) / 365)
    y = yoe + era * 400
    doy = doe - (365 * yoe + int(yoe/4) - int(yoe/100))
    mp = int((5 * doy + 2) / 153)
    d = doy - int((153 * mp + 2) / 5) + 1
    m = mp + (mp < 10 ? 3 : -9)
    if (m <= 2) y += 1
    msec = rem % 1000; rem = int(rem / 1000)
    ss = rem % 60; rem = int(rem / 60)
    mi = rem % 60; hh = int(rem / 60)
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d.%03d", y, m, d, hh, mi, ss, msec)
}
BEGIN {
    n = 0; kept = 0; stmts = 0
    print "SET NAMES utf8mb4;"
    print "SET time_zone=" Q "+00:00" Q ";"      # the timestamps are UTC
    print "SET autocommit=0;"
    print "SET unique_checks=0;"
}
/^#/ || /^[ \t]*$/ { next }
/^CREATE / || /^DROP / || /^ALTER / { next }          # the DDL block
{
    # timestamp: the trailing integer
    if (!match($0, / [0-9]+$/)) { bad++; next }
    tsraw = substr($0, RSTART + 1, RLENGTH - 1)
    head  = substr($0, 1, RSTART - 1)

    # Cut the digits down to milliseconds as a STRING: nanoseconds since
    # the epoch exceed 2^53, so going through a float would lose them
    if (DIGITS < 0) ms = tsraw * 1000                 # seconds
    else if (DIGITS == 0) ms = tsraw + 0
    else if (length(tsraw) > DIGITS) ms = substr(tsraw, 1, length(tsraw) - DIGITS) + 0
    else ms = 0

    # key part (measurement + tags) up to the first unescaped space
    sp = unescaped(head, " ")
    if (sp == 0) { bad++; next }
    key = substr(head, 1, sp - 1)
    fld = substr(head, sp + 1)

    ci = unescaped(key, ",")
    meas = unesc(ci ? substr(key, 1, ci - 1) : key)

    dom = ""; obj = ""
    if (match(key, /(^|,)domain=((\\.)|[^,\\])*/)) {
        dom = substr(key, RSTART, RLENGTH); sub(/^,?domain=/, "", dom); dom = unesc(dom)
    }
    if (match(key, /(^|,)entity_id=((\\.)|[^,\\])*/)) {
        obj = substr(key, RSTART, RLENGTH); sub(/^,?entity_id=/, "", obj); obj = unesc(obj)
    }
    if (dom == "" || obj == "") { skipped++; next }
    if (DOMAINS != "" && index(" " DOMAINS " ", " " dom " ") == 0) { skipped++; next }

    # field value: numeric, so it ends at the next comma
    val = ""; booltxt = ""
    if (match(fld, /(^|,)value=[^,]*/)) {
        val = substr(fld, RSTART, RLENGTH); sub(/^,?value=/, "", val)
        if (val ~ /^-?[0-9.]+[iu]$/) sub(/[iu]$/, "", val)
        else if (val ~ /^(t|T|true|True|TRUE)$/) { val = 1; booltxt = "true" }
        else if (val ~ /^(f|F|false|False|FALSE)$/) { val = 0; booltxt = "false" }
        else if (val !~ /^-?[0-9]/) val = ""
    }

    # field state: a quoted string, so it ends at the closing quote
    st = ""
    if (match(fld, /(^|,)state="/)) {
        rest = substr(fld, RSTART + RLENGTH)
        e = 0; i = 1
        while (i <= length(rest)) {
            c = substr(rest, i, 1)
            if (c == "\\") { i += 2; continue }
            if (c == "\"") { e = i; break }
            i++
        }
        if (e > 0) st = unq(substr(rest, 1, e - 1))
    }

    if (st == "" && booltxt != "") st = booltxt

    if (val == "" && (st == "" || NUMERIC_ONLY == 1)) { skipped++; next }

    eid = dom "." obj
    ts_str = stamp(ms)

    # Cut-off: everything from this moment on belongs to the live data that
    # the automation writes itself. String comparison is enough - the format
    # sorts chronologically, so no date arithmetic is needed here.
    if (UNTIL != "" && (ts_str "") > (UNTIL "")) { after++; next }

    # Throttling per entity - both dumps and the API deliver the points
    # of one entity in order, so the last timestamp is enough
    if (MININT > 0) {
        if (eid in last && ms >= last[eid] && ms - last[eid] < MININT * 1000) next
        last[eid] = ms
    }

    unit = (index(meas, ".") ? "" : meas)

    row = "(" q(eid) "," q(ts_str) ","
    row = row (val == "" ? "NULL" : val) ","
    row = row (st  == "" ? "NULL" : q(st)) ","
    row = row (unit == "" ? "NULL" : q(unit)) "," q(SRC) ")"

    if (n == 0) printf "INSERT IGNORE INTO `%s` (entity_id, ts, value, state, unit, source) VALUES\n", TABLE
    else printf ",\n"
    printf "%s", row
    n++; kept++
    if (n >= BATCH) {
        printf ";\n"; n = 0; stmts++
        if (stmts % 200 == 0) print "COMMIT;"
    }
}
END {
    if (n > 0) printf ";\n"
    printf "COMMIT;\n"
    printf "SET unique_checks=1;\n"
    printf "rows:%d skipped:%d after-cutoff:%d unparsable:%d\n",
           kept, skipped, after, bad > "/dev/stderr"
}
'

case "$PRECISION" in
    ns) DIGITS=6 ;;
    us) DIGITS=3 ;;
    ms) DIGITS=0 ;;
    s)  DIGITS=-1 ;;
    *)  echo "Unknown PRECISION '$PRECISION' (ns, us, ms, s)."; exit 1 ;;
esac

convert() {
    LC_ALL=C awk -v Q="'" -v TABLE="$TABLE" -v SRC="$SOURCE" -v BATCH="$BATCH" \
        -v MININT="$MIN_INTERVAL" -v DOMAINS="$DOMAINS" -v UNTIL="$UNTIL" \
        -v NUMERIC_ONLY="$NUMERIC_ONLY" -v DIGITS="$DIGITS" "$LP_TO_SQL"
}

read_file() {
    case "$1" in
        *.gz) gzip -dc "$1" ;;
        *)    cat "$1" ;;
    esac
}

# --- run ------------------------------------------------------------
total=0
for f in "${FILES[@]}"; do
    printf '>> %-28s ' "$(basename "$f")"

    if [ "$DRYRUN" = "1" ]; then
        echo ""
        read_file "$f" | convert
        continue
    fi

    read_file "$f" | convert 2>"$STATS" | mysql_run "$DB"
    rows=$(sed -n 's/^rows:\([0-9]*\).*/\1/p' "$STATS")
    skipped=$(sed -n 's/.*skipped:\([0-9]*\).*/\1/p' "$STATS")
    after=$(sed -n 's/.*after-cutoff:\([0-9]*\).*/\1/p' "$STATS")
    bad=$(sed -n 's/.*unparsable:\([0-9]*\).*/\1/p' "$STATS")
    note="skipped ${skipped:-0}, unparsable ${bad:-0}"
    if [ "${after:-0}" -gt 0 ]; then note="$note, after cut-off ${after:-0}"; fi
    echo "${rows:-0} rows ($note)"
    total=$((total + ${rows:-0}))
done

if [ "$DRYRUN" = "1" ]; then
    echo ""
    echo "(dry run - nothing was written)"
    exit 0
fi

echo ""
echo "Done. $total rows sent to $DB.$TABLE"
echo ""
mysql_run -t "$DB" -e \
    "SELECT source, COUNT(*) AS rows_total, MIN(ts) AS first_ts, MAX(ts) AS last_ts
     FROM \`$TABLE\` GROUP BY source"
echo "Refreshing the index statistics ..."
mysql_run "$DB" -e "ANALYZE TABLE \`$TABLE\`" >/dev/null
echo "Done."
