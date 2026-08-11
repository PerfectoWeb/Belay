#!/usr/bin/env bash
# Writes plausible Claude Code JSONL into a throwaway projects tree so the
# transcript watcher can be exercised without a real agent (docs/03, docs/08).
#
# The record shapes mirror docs/DISCOVERY.md §2: conversational `assistant`
# and `user` records, and the metadata records (`last-prompt`, `mode`) that
# real sessions append *after* a turn ends. Nothing here contains real content.
#
#   scripts/fake-agent.sh --mode steady --dir /tmp/vigil-fake --seconds 30
#
# Modes:
#   steady      alternating tool_use / tool_result records, then end_turn plus a
#               trailing metadata line (the tail case that breaks naive parsers)
#   tool-call   one tool_use record, then --quiet seconds of total silence
#   die         writes mid-turn and exits without an end_turn or any cleanup
#   truncate    writes, truncates its own file to zero, keeps writing
#   concurrent  two independent sessions writing at the same time
set -uo pipefail

MODE=steady
DIR="${TMPDIR:-/tmp}/vigil-fake-agent"
SECONDS_TO_RUN=20
CADENCE=0.5
QUIET=180
SESSION=""

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) MODE="$2"; shift 2 ;;
        --dir) DIR="$2"; shift 2 ;;
        --seconds) SECONDS_TO_RUN="$2"; shift 2 ;;
        --cadence) CADENCE="$2"; shift 2 ;;
        --quiet) QUIET="$2"; shift 2 ;;
        --session) SESSION="$2"; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

uuid() { uuidgen | tr 'A-Z' 'a-z'; }
stamp() { date -u +"%Y-%m-%dT%H:%M:%S.000Z"; }

# transcript_for <project-name> <session-uuid>
transcript_for() {
    local project="$DIR/projects/-fake-$1"
    mkdir -p "$project"
    printf '%s/%s.jsonl' "$project" "$2"
}

emit_assistant() {  # <file> <stop_reason> <session>
    printf '{"type":"assistant","uuid":"%s","sessionId":"%s","timestamp":"%s",' \
        "$(uuid)" "$3" "$(stamp)" >>"$1"
    printf '"message":{"role":"assistant","stop_reason":"%s","content":[]}}\n' "$2" >>"$1"
}

emit_user() {  # <file> <session>
    printf '{"type":"user","uuid":"%s","sessionId":"%s","timestamp":"%s",' \
        "$(uuid)" "$2" "$(stamp)" >>"$1"
    printf '"message":{"role":"user","content":[{"type":"tool_result"}]}}\n' >>"$1"
}

emit_metadata() {  # <file> <session>
    printf '{"type":"last-prompt","leafUuid":"%s","sessionId":"%s"}\n' "$(uuid)" "$2" >>"$1"
    printf '{"type":"mode","mode":"default","sessionId":"%s"}\n' "$2" >>"$1"
}

# run_turn <file> <session> <seconds>
run_turn() {
    local file="$1" session="$2" limit="$3" elapsed=0
    while awk "BEGIN{exit !($elapsed < $limit)}"; do
        emit_assistant "$file" tool_use "$session"
        sleep "$CADENCE"
        emit_user "$file" "$session"
        sleep "$CADENCE"
        elapsed=$(awk "BEGIN{print $elapsed + 2 * $CADENCE}")
    done
}

session_id="${SESSION:-$(uuid)}"

case "$MODE" in
    steady)
        file=$(transcript_for steady "$session_id")
        run_turn "$file" "$session_id" "$SECONDS_TO_RUN"
        emit_assistant "$file" end_turn "$session_id"
        emit_metadata "$file" "$session_id"
        echo "$file"
        ;;
    tool-call)
        file=$(transcript_for toolcall "$session_id")
        emit_assistant "$file" tool_use "$session_id"
        echo "$file"
        sleep "$QUIET"
        emit_user "$file" "$session_id"
        emit_assistant "$file" end_turn "$session_id"
        emit_metadata "$file" "$session_id"
        ;;
    die)
        file=$(transcript_for die "$session_id")
        run_turn "$file" "$session_id" "$SECONDS_TO_RUN"
        echo "$file"
        # No end_turn, no metadata, no cleanup: exactly what a SIGKILL leaves.
        kill -9 $$
        ;;
    truncate)
        file=$(transcript_for truncate "$session_id")
        run_turn "$file" "$session_id" "$SECONDS_TO_RUN"
        : >"$file"
        run_turn "$file" "$session_id" "$SECONDS_TO_RUN"
        emit_assistant "$file" end_turn "$session_id"
        echo "$file"
        ;;
    concurrent)
        one=$(uuid); two=$(uuid)
        "$0" --mode steady --dir "$DIR" --seconds "$SECONDS_TO_RUN" \
            --cadence "$CADENCE" --session "$one" &
        "$0" --mode steady --dir "$DIR" --seconds "$SECONDS_TO_RUN" \
            --cadence "$CADENCE" --session "$two" &
        wait
        ;;
    *)
        echo "unknown mode: $MODE" >&2
        exit 2
        ;;
esac
