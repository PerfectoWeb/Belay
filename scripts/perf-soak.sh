#!/usr/bin/env bash
# Measure a running Vigil against the docs/08 budgets and print a pass/fail table.
#
# Two measurement traps this script exists to avoid (docs/QA-CHECKLIST.md §0, §4):
#
#   1. `ps -o rss=` is not the memory budget. RSS counts shared framework pages
#      that every app on the system maps; it reads ~75 MB here against a real
#      phys_footprint of ~15 MB, and it already produced one false alarm on this
#      project. This script uses `footprint -p <pid>` and reports phys_footprint.
#   2. `pmset -g assertions` must be matched on **pid**. The bundle id contains
#      "vigil", and runningboardd holds an unrelated launch assertion for it, so
#      grepping the word matches something that is not ours.
#
# CPU is gated on CPU-seconds actually consumed divided by wall time, not on the
# raw `ps -o %cpu=` number: %cpu is a decayed average whose meaning over a
# 30-minute window is unclear. Both are recorded; only the derived one is gated.
set -euo pipefail

readonly BUDGET_CPU_IDLE=0.1      # docs/08: < 0.1% avg, armed with no sessions
readonly BUDGET_CPU_ACTIVE=1.0    # docs/08: < 1.0% avg with one busy session
readonly BUDGET_FOOTPRINT_MB=40   # docs/08: < 40 MB phys_footprint, and flat
readonly BUDGET_WAKEUPS=3         # docs/08: < 3 idle wakeups/s
readonly MIN_INTERVAL=5           # docs/00-INVARIANTS.md: nothing on this project polls faster

readonly MEM_FLAT_PCT=5           # "flat" = no more than this much growth...
readonly MEM_FLAT_MB=2            # ...or this many MB, whichever is more generous
readonly MEM_FLAT_MIN_DURATION=600  # below this the growth check proves nothing

DURATION=1800
INTERVAL="$MIN_INTERVAL"
MODE=auto
OUT_DIR=""
WANT_WAKEUPS=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<'EOF'
perf-soak.sh - measure a running Vigil against the docs/08 performance budgets.

Usage: scripts/perf-soak.sh [options]

Options:
  -d, --duration SECS   How long to soak. Default 1800 (30 min).
  -i, --interval SECS   Sampling period. Default 5, and 5 is also the floor:
                        sampling faster would disturb what we are measuring.
  -m, --mode MODE       auto | idle | active. Which CPU budget to gate on.
                        auto (default) classifies each interval by whether Vigil
                        held an assertion during it, and gates idle intervals at
                        0.1% and active ones at 1.0%.
  -o, --out DIR         Where to write samples.csv and summary.txt.
                        Default build/qa/perf-soak-<timestamp>/.
      --no-wakeups      Skip the powermetrics wakeups sampler entirely.
  -h, --help            This text.

Measures: CPU (avg + peak), phys_footprint (first/last/peak, growth),
idle wakeups per second, and the Vigil power assertion (held, for how long,
with what timeout). Matches the assertion on pid, never on the string "vigil".

Exit status:
  0  every measured budget passed
  1  a budget was breached, or the soak was interrupted
  2  Vigil is not running, or the arguments do not make sense

Examples:
  scripts/perf-soak.sh                        # the real 30-minute soak
  scripts/perf-soak.sh -d 120 -i 5            # a quick smoke test of the script
  scripts/perf-soak.sh -d 1800 -m idle        # gate everything at the idle budget
EOF
}

die() { printf 'perf-soak: %s\n' "$1" >&2; exit "${2:-2}"; }

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--duration) DURATION="${2:-}"; shift 2 ;;
        -i|--interval) INTERVAL="${2:-}"; shift 2 ;;
        -m|--mode)     MODE="${2:-}"; shift 2 ;;
        -o|--out)      OUT_DIR="${2:-}"; shift 2 ;;
        --no-wakeups)  WANT_WAKEUPS=0; shift ;;
        -h|--help)     usage; exit 0 ;;
        *) die "unknown argument '$1'. Try --help." ;;
    esac
done

case "$DURATION" in ''|*[!0-9]*) die "duration must be whole seconds, got '$DURATION'" ;; esac
case "$INTERVAL" in ''|*[!0-9]*) die "interval must be whole seconds, got '$INTERVAL'" ;; esac
[ "$DURATION" -ge "$INTERVAL" ] || die "duration ($DURATION s) is shorter than one interval ($INTERVAL s)"
[ "$INTERVAL" -ge "$MIN_INTERVAL" ] || die "interval $INTERVAL s is below the ${MIN_INTERVAL}s floor; sampling that fast disturbs the measurement"
case "$MODE" in auto|idle|active) ;; *) die "mode must be auto, idle or active, got '$MODE'" ;; esac

# One pid, or nothing to measure. Two would make every number ambiguous.
PIDS="$(pgrep -x Vigil || true)"
[ -n "$PIDS" ] || die "Vigil is not running. Build and launch it first:
    scripts/build-local.sh Release && open build/Vigil.app
then re-run this script." 2
PID_COUNT="$(printf '%s\n' "$PIDS" | wc -l | tr -d ' ')"
[ "$PID_COUNT" -eq 1 ] || die "found $PID_COUNT Vigil processes ($(echo "$PIDS" | tr '\n' ' ')); quit all but one first" 2
PID="$PIDS"

STAMP="$(date '+%Y%m%d-%H%M%S')"
[ -n "$OUT_DIR" ] || OUT_DIR="$ROOT/build/qa/perf-soak-$STAMP"
mkdir -p "$OUT_DIR"
CSV="$OUT_DIR/samples.csv"
SUMMARY="$OUT_DIR/summary.txt"

now() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        printf '%s\n' "${EPOCHREALTIME/,/.}"
    elif command -v perl >/dev/null 2>&1; then
        perl -MTime::HiRes -e 'printf "%.3f\n", Time::HiRes::time()'
    else
        date +%s
    fi
}

# ps prints CPU time as [[DD-]HH:]MM:SS.CC. Everything downstream wants seconds.
cputime_seconds() {
    ps -o cputime= -p "$PID" 2>/dev/null | awk '
        { gsub(/^ +| +$/, "", $0); if ($0 == "") exit
          n = split($0, a, /[:-]/); s = 0
          for (i = 1; i <= n; i++) s = s * 60 + a[i]
          if (n == 4) s = a[1] * 86400 + ((a[2] * 60 + a[3]) * 60 + a[4])
          printf "%.2f\n", s }'
}

# Emits "count|age_s|timeout_s|type". Blocks are keyed on the pid, because the
# bundle id contains "vigil" and runningboardd holds a launch assertion for it.
sample_assertion() {
    pmset -g assertions 2>/dev/null | awk -v pid="$PID" '
        /^[^[:space:]]/ { inblock = 0 }
        $1 == "pid" {
            inblock = ($2 ~ "^" pid "\\(")
            if (inblock) {
                count++
                n = split($4, t, ":"); age = 0
                for (i = 1; i <= n; i++) age = age * 60 + t[i]
                type = $5
            }
            next
        }
        inblock && /Timeout will fire in/ {
            for (i = 1; i < NF; i++) if ($i == "in") timeout = $(i + 1)
        }
        END { printf "%d|%s|%s|%s\n", count + 0, (count ? age : ""), timeout, type }'
}

# powermetrics is root-only. Detect that once and skip cleanly rather than
# failing the whole soak over a sampler that is one line of the report.
WAKEUPS_STATUS="skipped (--no-wakeups)"
POWERMETRICS=""
if [ "$WANT_WAKEUPS" -eq 1 ]; then
    if [ "$(id -u)" -eq 0 ]; then
        POWERMETRICS="powermetrics"
    elif sudo -n true 2>/dev/null; then
        POWERMETRICS="sudo -n powermetrics"
    else
        WAKEUPS_STATUS="skipped (powermetrics needs root; re-run with sudo to measure wakeups)"
    fi
fi

sample_wakeups() {
    [ -n "$POWERMETRICS" ] || return 0
    $POWERMETRICS --samplers tasks -n 1 -i 1000 2>/dev/null | awk -v pid="$PID" '
        # Find the wakeups column from the header, then read our row. Column
        # names move between macOS releases, so index by header text, never by
        # a hard-coded position, and print nothing at all if it cannot be found.
        /ms\/s/ && col == 0 {
            for (i = 1; i <= NF; i++) if (tolower($i) ~ /wakeup/) { col = i; break }
            next
        }
        col > 0 && $2 == pid { printf "%.2f\n", $col + 0; found = 1; exit }
        END { if (!found && col > 0) print "0.00" }'
}

if [ -n "$POWERMETRICS" ]; then
    if [ -n "$(sample_wakeups)" ]; then
        WAKEUPS_STATUS="measured"
    else
        WAKEUPS_STATUS="skipped (powermetrics ran but no wakeups column could be parsed)"
        POWERMETRICS=""
    fi
fi

printf 'iso_time,elapsed_s,cpu_interval_pct,ps_pct_cpu,cputime_s,phys_footprint_bytes,assertion_count,assertion_age_s,assertion_timeout_s,assertion_type,wakeups_per_s,vigil_processes\n' >"$CSV"

echo "==> soaking Vigil pid $PID for ${DURATION}s at ${INTERVAL}s intervals"
echo "    mode: $MODE   wakeups: $WAKEUPS_STATUS"
echo "    output: $OUT_DIR"
echo

INTERRUPTED=0
trap 'INTERRUPTED=1' INT TERM

START="$(now)"
PREV_T=""
PREV_CPU=""
SAMPLES=0

while :; do
    T="$(now)"
    ELAPSED="$(awk -v a="$T" -v b="$START" 'BEGIN { printf "%.2f", a - b }')"
    awk -v e="$ELAPSED" -v d="$DURATION" 'BEGIN { exit !(e > d) }' && break
    [ "$INTERRUPTED" -eq 0 ] || break

    kill -0 "$PID" 2>/dev/null || {
        echo "perf-soak: Vigil (pid $PID) exited after ${ELAPSED}s of the soak" >&2
        INTERRUPTED=1
        break
    }

    CPUTIME="$(cputime_seconds)"
    PSCPU="$(ps -o %cpu= -p "$PID" 2>/dev/null | tr -d ' ')"
    FOOTPRINT="$(footprint -p "$PID" --noCategories -f bytes 2>/dev/null |
        awk '/phys_footprint:/ && !/peak/ { print $2; exit }')"
    IFS='|' read -r A_COUNT A_AGE A_TIMEOUT A_TYPE <<<"$(sample_assertion)"
    WAKEUPS="$(sample_wakeups)"

    if [ -n "$PREV_T" ]; then
        CPU_PCT="$(awk -v c="$CPUTIME" -v pc="$PREV_CPU" -v t="$T" -v pt="$PREV_T" \
            'BEGIN { dt = t - pt; printf "%.3f", (dt > 0 ? 100 * (c - pc) / dt : 0) }')"
    else
        CPU_PCT=""
    fi
    PREV_T="$T"
    PREV_CPU="$CPUTIME"

    # Invariant 1 is about the assertion existing once, and a second Vigil
    # process would hold a second one. An xcodebuild test host counts.
    NPROC="$(pgrep -x Vigil 2>/dev/null | wc -l | tr -d ' ')"

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S')" "$ELAPSED" "$CPU_PCT" "${PSCPU:-}" "${CPUTIME:-}" \
        "${FOOTPRINT:-}" "${A_COUNT:-0}" "${A_AGE:-}" "${A_TIMEOUT:-}" "${A_TYPE:-}" \
        "${WAKEUPS:-}" "${NPROC:-1}" >>"$CSV"

    SAMPLES=$((SAMPLES + 1))
    if [ -t 1 ]; then
        printf '\r    %d samples, %ss elapsed, cpu %s%%, footprint %s MB, assertion %s   ' \
            "$SAMPLES" "${ELAPSED%.*}" "${CPU_PCT:--}" \
            "$(awk -v b="${FOOTPRINT:-0}" 'BEGIN { printf "%.1f", b / 1048576 }')" \
            "$([ "${A_COUNT:-0}" -gt 0 ] && echo held || echo none)"
    fi

    # Sleep the remainder of the period, so the loop's own cost does not drift
    # the sample cadence out from under the interval.
    REMAIN="$(awk -v n="$(now)" -v t="$T" -v i="$INTERVAL" 'BEGIN { r = i - (n - t); printf "%.2f", (r > 0 ? r : 0) }')"
    sleep "$REMAIN" || true
done

[ ! -t 1 ] || printf '\r%*s\r' 100 ''
trap - INT TERM

[ "$SAMPLES" -ge 2 ] || die "only $SAMPLES sample(s) collected; nothing to conclude from" 1

STATS="$OUT_DIR/stats.env"
awk -F, -v mode="$MODE" '
    NR == 1 { next }
    {
        n++
        elapsed[n] = $2 + 0; cpu[n] = $5 + 0; pscpu[n] = $4 + 0
        foot[n] = $6 + 0; acount[n] = $7 + 0; atimeout[n] = $9
        if ($7 + 0 > 0) { held++; if ($8 + 0 > age_max) age_max = $8 + 0 }
        if ($7 + 0 > 1) multi++
        if ($7 + 0 > 0 && $9 == "") no_timeout++
        if ($9 != "" && ($9 + 0 > timeout_max)) timeout_max = $9 + 0
        if ($11 != "") { wn++; wsum += $11 + 0; if ($11 + 0 > wmax) wmax = $11 + 0 }
        if ($12 + 0 > nproc_max) nproc_max = $12 + 0
        if (pscpu[n] > pscpu_max) pscpu_max = pscpu[n]
        pscpu_sum += pscpu[n]
        if (foot[n] > 0) {
            if (foot_first == 0) foot_first = foot[n]
            foot_last = foot[n]
            if (foot[n] > foot_max) foot_max = foot[n]
            if (foot_min == 0 || foot[n] < foot_min) foot_min = foot[n]
        }
    }
    END {
        for (i = 2; i <= n; i++) {
            dt = elapsed[i] - elapsed[i - 1]
            dc = cpu[i] - cpu[i - 1]
            if (dt <= 0 || dc < 0) continue
            pct = 100 * dc / dt
            class = (mode == "idle" ? "idle" : (mode == "active" ? "active" : \
                     ((acount[i] > 0 || acount[i - 1] > 0) ? "active" : "idle")))
            tdt += dt; tdc += dc
            if (pct > peak_all) peak_all = pct
            if (class == "idle") {
                idt += dt; idc += dc; in_++
                if (pct > peak_idle) peak_idle = pct
            } else {
                adt += dt; adc += dc; an++
                if (pct > peak_active) peak_active = pct
            }
        }
        printf "SAMPLES=%d\n", n
        printf "WINDOW_S=%.1f\n", elapsed[n] - elapsed[1]
        printf "CPU_AVG=%.4f\n", (tdt > 0 ? 100 * tdc / tdt : 0)
        printf "CPU_PEAK=%.3f\n", peak_all
        printf "CPU_IDLE_AVG=%.4f\n", (idt > 0 ? 100 * idc / idt : -1)
        printf "CPU_IDLE_PEAK=%.3f\n", peak_idle
        printf "CPU_IDLE_N=%d\n", in_
        printf "CPU_ACTIVE_AVG=%.4f\n", (adt > 0 ? 100 * adc / adt : -1)
        printf "CPU_ACTIVE_PEAK=%.3f\n", peak_active
        printf "CPU_ACTIVE_N=%d\n", an
        printf "PSCPU_AVG=%.3f\n", pscpu_sum / n
        printf "PSCPU_PEAK=%.3f\n", pscpu_max
        printf "MEM_FIRST_MB=%.2f\n", foot_first / 1048576
        printf "MEM_LAST_MB=%.2f\n", foot_last / 1048576
        printf "MEM_MIN_MB=%.2f\n", foot_min / 1048576
        printf "MEM_PEAK_MB=%.2f\n", foot_max / 1048576
        printf "MEM_GROWTH_MB=%.2f\n", (foot_last - foot_first) / 1048576
        printf "MEM_GROWTH_PCT=%.2f\n", (foot_first > 0 ? 100 * (foot_last - foot_first) / foot_first : 0)
        printf "ASSERT_HELD_N=%d\n", held
        printf "ASSERT_MAX_AGE_S=%d\n", age_max
        printf "ASSERT_MAX_TIMEOUT_S=%d\n", timeout_max
        printf "ASSERT_MULTI_N=%d\n", multi
        printf "ASSERT_NO_TIMEOUT_N=%d\n", no_timeout
        printf "WAKE_N=%d\n", wn
        printf "WAKE_AVG=%.2f\n", (wn > 0 ? wsum / wn : -1)
        printf "WAKE_PEAK=%.2f\n", wmax
        printf "PROC_MAX=%d\n", nproc_max
    }' "$CSV" >"$STATS"

# shellcheck disable=SC1090
. "$STATS"

FAILED=0
ROWS=""
row() { # name | measured | budget | verdict
    ROWS="${ROWS}$(printf '%-24s %-30s %-16s %s' "$1" "$2" "$3" "$4")
"
    [ "$4" != "FAIL" ] || FAILED=1
}
lt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'; }

if [ "$CPU_IDLE_N" -gt 0 ]; then
    if lt "$CPU_IDLE_AVG" "$BUDGET_CPU_IDLE"; then V=PASS; else V=FAIL; fi
    row "CPU idle avg" "${CPU_IDLE_AVG}%  (n=$CPU_IDLE_N)" "< ${BUDGET_CPU_IDLE}%" "$V"
    row "CPU idle peak" "${CPU_IDLE_PEAK}%" "informational" "info"
else
    row "CPU idle avg" "no idle intervals" "< ${BUDGET_CPU_IDLE}%" "SKIP"
fi

if [ "$CPU_ACTIVE_N" -gt 0 ]; then
    if lt "$CPU_ACTIVE_AVG" "$BUDGET_CPU_ACTIVE"; then V=PASS; else V=FAIL; fi
    row "CPU active avg" "${CPU_ACTIVE_AVG}%  (n=$CPU_ACTIVE_N)" "< ${BUDGET_CPU_ACTIVE}%" "$V"
    row "CPU active peak" "${CPU_ACTIVE_PEAK}%" "informational" "info"
else
    row "CPU active avg" "no active intervals" "< ${BUDGET_CPU_ACTIVE}%" "SKIP"
fi
row "CPU ps %cpu avg/peak" "${PSCPU_AVG}% / ${PSCPU_PEAK}%" "cross-check only" "info"

if lt "$MEM_PEAK_MB" "$BUDGET_FOOTPRINT_MB"; then V=PASS; else V=FAIL; fi
row "phys_footprint peak" "${MEM_PEAK_MB} MB" "< ${BUDGET_FOOTPRINT_MB} MB" "$V"

if [ "$DURATION" -lt "$MEM_FLAT_MIN_DURATION" ]; then
    row "phys_footprint flat" "${MEM_FIRST_MB} -> ${MEM_LAST_MB} MB" "needs >= ${MEM_FLAT_MIN_DURATION}s" "SKIP"
else
    LIMIT="$(awk -v f="$MEM_FIRST_MB" -v p="$MEM_FLAT_PCT" -v m="$MEM_FLAT_MB" \
        'BEGIN { a = f * p / 100; print (a > m ? a : m) }')"
    if lt "$MEM_GROWTH_MB" "$LIMIT"; then V=PASS; else V=FAIL; fi
    row "phys_footprint flat" "${MEM_FIRST_MB} -> ${MEM_LAST_MB} MB (${MEM_GROWTH_PCT}%)" "growth < ${LIMIT} MB" "$V"
fi

if [ "$WAKE_N" -gt 0 ]; then
    if lt "$WAKE_AVG" "$BUDGET_WAKEUPS"; then V=PASS; else V=FAIL; fi
    row "Idle wakeups/s avg" "$WAKE_AVG (peak $WAKE_PEAK)" "< $BUDGET_WAKEUPS" "$V"
else
    row "Idle wakeups/s" "not measured" "< $BUDGET_WAKEUPS" "SKIP"
fi

# Invariants 1 and 2 are cheap to check from the same samples, and a soak is
# exactly when a missing timeout or a duplicate assertion would show up.
if [ "$ASSERT_MULTI_N" -eq 0 ] && [ "$PROC_MAX" -le 1 ]; then V=PASS; else V=FAIL; fi
if [ "$ASSERT_MULTI_N" -gt 0 ]; then
    DETAIL="2+ in $ASSERT_MULTI_N samples"
elif [ "$PROC_MAX" -gt 1 ]; then
    DETAIL="$PROC_MAX Vigil processes seen"
else
    DETAIL="max 1, in 1 process"
fi
row "One assertion at a time" "$DETAIL" "invariant 1" "$V"

if [ "$ASSERT_HELD_N" -eq 0 ]; then
    row "Assertion timeout set" "never held during soak" "invariant 2" "SKIP"
else
    if [ "$ASSERT_NO_TIMEOUT_N" -eq 0 ]; then V=PASS; else V=FAIL; fi
    row "Assertion timeout set" "$ASSERT_NO_TIMEOUT_N/$ASSERT_HELD_N held samples lacked one" "invariant 2" "$V"
fi

{
    echo "Vigil performance soak"
    echo "----------------------"
    printf 'when          %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf 'host          %s, macOS %s (%s)\n' "$(uname -m)" "$(sw_vers -productVersion)" "$(sw_vers -buildVersion)"
    printf 'pid           %s\n' "$PID"
    printf 'duration      %ss requested, %ss covered by %s samples every %ss\n' "$DURATION" "$WINDOW_S" "$SAMPLES" "$INTERVAL"
    printf 'mode          %s\n' "$MODE"
    printf 'wakeups       %s\n' "$WAKEUPS_STATUS"
    printf 'assertion     held in %s of %s samples' "$ASSERT_HELD_N" "$SAMPLES"
    if [ "$ASSERT_HELD_N" -gt 0 ]; then
        printf ', longest observed age %ss, largest timeout %ss\n' "$ASSERT_MAX_AGE_S" "$ASSERT_MAX_TIMEOUT_S"
    else
        printf '\n'
    fi
    echo
    printf '%-24s %-30s %-16s %s\n' "METRIC" "MEASURED" "BUDGET" "VERDICT"
    printf '%s' "$ROWS"
    echo
    # ps reports CPU time in hundredths, so a single interval can only resolve
    # 0.01s/INTERVAL. Peaks are quantised to that step; the averages are not,
    # because they divide the whole window's CPU time by the whole window.
    printf 'per-sample CPU resolution at a %ss interval: %s%%\n' \
        "$INTERVAL" "$(awk -v i="$INTERVAL" 'BEGIN { printf "%.2f", 100 * 0.01 / i }')"
    echo "samples: $CSV"
    if [ "$INTERRUPTED" -eq 1 ]; then
        echo
        echo "NOTE: the soak was cut short. These numbers cover less than the requested window."
    fi
} | tee "$SUMMARY"

if [ "$INTERRUPTED" -eq 1 ]; then
    echo
    echo "perf-soak: incomplete run, not treating it as a pass." >&2
    exit 1
fi
if [ "$FAILED" -eq 1 ]; then
    echo
    echo "perf-soak: at least one budget was breached. docs/08 says fix the design, not the number." >&2
    exit 1
fi
echo
echo "perf-soak: every measured budget passed. Anything marked SKIP was not measured and is not a pass."
