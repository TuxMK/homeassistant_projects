#!/usr/bin/env zsh
# ------------------------------------------------------------------
# Full export InfluxDB 1.x (HA add-on) -> line protocol, month by month
#
# Exports EVERYTHING - every measurement, every series, every field -
# unchanged, one file per month. Nothing is rewritten, nothing is
# dropped: influx_inspect writes native line protocol straight from
# the TSM files, including the field types (42i stays an integer) and
# the escaping of tags and strings.
#
# That is the reason this does not go through `influx -format csv`:
# CSV has no types, so integers, floats and strings can no longer be
# told apart on the way back, and a friendly_name containing a comma
# would shift the columns.
#
# Before exporting, stop what writes into InfluxDB - Settings >
# Devices & services > InfluxDB > disable. Do NOT stop the add-on
# itself: the container has to keep running for `docker exec`.
#
# Call:    zsh influx_export_monthly.sh
# Result:  influx_export/influx_YYYY-MM.lp.gz, one per month
# ------------------------------------------------------------------

set -e

# zsh does not word-split unquoted variables the way sh and bash do -
# without this, `$DOCKER_BIN` as "sudo docker" and similar break
if [ -n "$ZSH_VERSION" ]; then setopt SH_WORD_SPLIT; fi

# ============ CONFIG ============
DB="homeassistant"
CONTAINER="app_a0d7b954_influxdb"

START="2023-01"                 # first month, YYYY-MM
END="2026-09"                   # last month, inclusive

OUTDIR="./influx_export"        # target directory on this host
COMPRESS=1                      # 1 = gzip the files
RETENTION=""                    # empty = every retention policy

DATADIR=""                      # empty = detect inside the container
WALDIR=""

DOCKER_BIN="docker"             # e. g. "sudo docker" where needed
CONTAINER_TMP="/data/_export_tmp"
DRYRUN=0                        # 1 = only print what would happen
# ================================

# --- month boundaries ----------------------------------------------
# Worked out here rather than handed to `date`: the -D option for the
# input format exists in BusyBox only, and a date that does not know it
# quietly answers with the current day instead of failing.
days_in_month() {   # $1 = year, $2 = month
    case "$2" in
        1|3|5|7|8|10|12) echo 31 ;;
        4|6|9|11)        echo 30 ;;
        2)  if [ $(( $1 % 4 )) -eq 0 ] &&
               { [ $(( $1 % 100 )) -ne 0 ] || [ $(( $1 % 400 )) -eq 0 ]; }
            then echo 29
            else echo 28
            fi ;;
    esac
}

# Reading an export file, compressed or not - as a function, because a
# command kept in a variable is not split into words by every shell
read_out() {
    case "$1" in
        *.gz) gzip -dc "$1" ;;
        *)    cat "$1" ;;
    esac
}

run() {
    if [ "$DRYRUN" = "1" ]; then
        echo "   [dry run] $*"
    else
        "$@"
    fi
}

# --- container and data directories --------------------------------
$DOCKER_BIN inspect "$CONTAINER" >/dev/null 2>&1 || {
    echo "Container '$CONTAINER' not found. Running containers:"
    $DOCKER_BIN ps --format '{{.Names}}' | grep -i influx || true
    exit 1
}

# The TSM files sit in <datadir>/<db>/<rp>/<shard>/*.tsm, so four
# levels up from any one of them is the data directory. Same shape
# for the write-ahead log.
detect_dir() {   # $1 = file extension
    found=$($DOCKER_BIN exec "$CONTAINER" sh -c \
        "find /data /var/lib/influxdb -name '*.$1' -path '*/$DB/*' \
         2>/dev/null | head -1")
    if [ -z "$found" ]; then
        # Not in the usual places - search the whole container
        found=$($DOCKER_BIN exec "$CONTAINER" sh -c \
            "find / -name '*.$1' -path '*/$DB/*' 2>/dev/null | head -1")
    fi
    [ -n "$found" ] || return 1
    $DOCKER_BIN exec "$CONTAINER" sh -c \
        "dirname \$(dirname \$(dirname \$(dirname '$found')))"
}

[ -n "$DATADIR" ] || DATADIR=$(detect_dir tsm) || {
    echo "No TSM files found for database '$DB' - set DATADIR by hand."
    exit 1
}
if [ -z "$WALDIR" ]; then
    # A freshly compacted InfluxDB can have no .wal files at all, so the
    # sibling of the data directory is the fallback
    WALDIR=$(detect_dir wal) || WALDIR="${DATADIR%/data}/wal"
fi

TSM_COUNT=$($DOCKER_BIN exec "$CONTAINER" sh -c \
    "find '$DATADIR' -name '*.tsm' 2>/dev/null | wc -l" | tr -d ' \r')

echo "Container: $CONTAINER"
echo "datadir:   $DATADIR  ($TSM_COUNT TSM files)"
echo "waldir:    $WALDIR"
echo "Period:    $START .. $END"
echo ""

if [ "${TSM_COUNT:-0}" -eq 0 ]; then
    echo "!! No TSM files under '$DATADIR'."
    echo "   Only the write-ahead log would be exported, which holds just the"
    echo "   most recent writes. Find the real directory with:"
    echo ""
    echo "   $DOCKER_BIN exec $CONTAINER find / -name '*.tsm' 2>/dev/null | head"
    echo ""
    echo "   Then set DATADIR and WALDIR by hand at the top of this script."
    exit 1
fi

mkdir -p "$OUTDIR"
run $DOCKER_BIN exec "$CONTAINER" mkdir -p "$CONTAINER_TMP"
run $DOCKER_BIN exec "$CONTAINER" mkdir -p "$CONTAINER_TMP/empty_wal"

# --- month loop ----------------------------------------------------
# Plain year/month arithmetic, so no date library is needed for the
# steps; only the two boundaries of a month are turned into a date.
sy=${START%%-*}; sm=${START##*-}
ey=${END%%-*};   em=${END##*-}
sm=${sm#0}; em=${em#0}           # strip the leading zero, else octal

total_rows=0
total_tsm=0
total_files=0
y=$sy; m=$sm

while [ "$y" -lt "$ey" ] || { [ "$y" -eq "$ey" ] && [ "$m" -le "$em" ]; }; do
    ym=$(printf "%04d-%02d" "$y" "$m")

    ny=$y; nm=$((m + 1))
    if [ "$nm" -gt 12 ]; then nm=1; ny=$((y + 1)); fi

    # -end is inclusive, so the month ends one nanosecond before the
    # next one begins - otherwise the first point of the following
    # month would land in two files
    dim=$(days_in_month "$y" "$m")
    from_rfc=$(printf '%04d-%02d-01T00:00:00Z' "$y" "$m")
    to_rfc=$(printf '%04d-%02d-%02dT23:59:59.999999999Z' "$y" "$m" "$dim")

    name="influx_${ym}.lp"
    if [ "$COMPRESS" = "1" ]; then name="${name}.gz"; fi

    echo ">> $ym  ($from_rfc .. $to_rfc)"

    # Only the newest month reads the real WAL - see above
    if [ "$y" -eq "$ey" ] && [ "$m" -eq "$em" ]; then
        use_wal="$WALDIR"
    else
        use_wal="$CONTAINER_TMP/empty_wal"
    fi

    set -- influx_inspect export \
        -datadir "$DATADIR" -waldir "$use_wal" -database "$DB" \
        -start "$from_rfc" -end "$to_rfc" \
        -out "$CONTAINER_TMP/$name"
    if [ -n "$RETENTION" ]; then set -- "$@" -retention "$RETENTION"; fi
    if [ "$COMPRESS" = "1" ]; then set -- "$@" -compress; fi

    run $DOCKER_BIN exec "$CONTAINER" "$@"
    run $DOCKER_BIN cp "$CONTAINER:$CONTAINER_TMP/$name" "$OUTDIR/$name"
    run $DOCKER_BIN exec "$CONTAINER" rm -f "$CONTAINER_TMP/$name"

    if [ "$DRYRUN" = "1" ]; then
        y=$ny; m=$nm
        continue
    fi

    # Count the TSM and the WAL section separately: a file that carries
    # only WAL rows means the data directory is wrong, and that is worth
    # noticing here rather than after the import
    counts=$(read_out "$OUTDIR/$name" | awk '
        /^# writing tsm data/ { sec = "tsm"; next }
        /^# writing wal data/ { sec = "wal"; next }
        /^#/ || /^[ \t]*$/   { next }
        { n[sec]++ }
        END { printf "%d %d", n["tsm"] + 0, n["wal"] + 0 }')
    tsm_rows=${counts%% *}
    wal_rows=${counts##* }
    rows=$((tsm_rows + wal_rows))

    if [ "$rows" -eq 0 ]; then
        echo "   no data, file removed"
        rm -f "$OUTDIR/$name"
    else
        size=$(du -h "$OUTDIR/$name" | cut -f1)
        if [ "$tsm_rows" -eq 0 ]; then
            echo "   $rows points, $size   !! WAL only, no stored data"
        else
            echo "   $rows points, $size  (tsm $tsm_rows, wal $wal_rows)"
        fi
        total_rows=$((total_rows + rows))
        total_tsm=$((total_tsm + tsm_rows))
        total_files=$((total_files + 1))
    fi

    y=$ny; m=$nm
done

run $DOCKER_BIN exec "$CONTAINER" rmdir "$CONTAINER_TMP/empty_wal" 2>/dev/null || true
run $DOCKER_BIN exec "$CONTAINER" rmdir "$CONTAINER_TMP" 2>/dev/null || true

echo ""
echo "Done. $total_files file(s), $total_rows points in $OUTDIR"
if [ "$DRYRUN" != "1" ] && [ "$total_tsm" -eq 0 ] && [ "$total_rows" -gt 0 ]; then
    echo ""
    echo "!! Every point came from the write-ahead log, none from stored data."
    echo "   '$DATADIR' is not where this database keeps its shards. Locate it with:"
    echo "   $DOCKER_BIN exec $CONTAINER find / -name '*.tsm' 2>/dev/null | head"
fi
if [ "$DRYRUN" = "1" ]; then echo "(dry run - nothing was written)"; fi
echo ""
echo "Into the MariaDB archive:"
echo "  ./influx_import_mysql.sh <db-user> <db-password>   # LPDIR=$OUTDIR"
echo ""
echo "Back into an InfluxDB:"
echo "  $DOCKER_BIN cp $OUTDIR/influx_YYYY-MM.lp.gz $CONTAINER:/tmp/in.lp.gz"
echo "  $DOCKER_BIN exec $CONTAINER sh -c 'gzip -dc /tmp/in.lp.gz > /tmp/in.lp'"
echo "  $DOCKER_BIN exec $CONTAINER influx -import -path=/tmp/in.lp -precision=ns"
