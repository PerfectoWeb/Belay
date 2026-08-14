#!/usr/bin/env bash
# Fails if a commit claims more than one author.
#
#   ./scripts/one-author.sh            # the whole history and the tree
#   ./scripts/one-author.sh --staged   # only what is about to be committed
#
# This is a one-person project and the history should say so. A `Co-Authored-By`
# trailer is enough for the forge to list a second contributor on the front page
# of a public repository, and once it has done that, taking it back means
# rewriting history on every branch. Cheaper to refuse the trailer.
#
# The rule is about authorship, not about any particular tool: any co-author
# trailer, any commit whose author or committer is not on the list below, and
# any generator line in a message. Naming names would date badly and would need
# maintaining; this does not.
set -euo pipefail

cd "$(dirname "$0")/.."

# The people who write this. Add a line to add a person.
AUTHORS=(
    "David Build <manager@perfecto-web.com>"
)

# Trailers and generator lines, anchored so ordinary prose cannot trip them.
# The last one is built from its bytes rather than written out, because a file
# that contains the thing it forbids matches itself and fails every run.
ROBOT="$(printf '\xf0\x9f\xa4\x96')"
PATTERNS=(
    '^[[:space:]]*Co-[Aa]uthored-[Bb]y:'
    '^[[:space:]]*[Gg]enerated with \['
    "$ROBOT"
)

STAGED=0
[ "${1:-}" = "--staged" ] && STAGED=1

found=0
report() { echo "  $1" >&2; found=1; }

if [ "$STAGED" = 1 ]; then
    files="$(git diff --cached --name-only --diff-filter=ACM)"
else
    files="$(git ls-files)"
fi

for pattern in "${PATTERNS[@]}"; do
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        [ -f "$file" ] || continue
        if grep -InE "$pattern" -- "$file" >/dev/null 2>&1; then
            report "$(grep -InE "$pattern" -- "$file" | head -1 | sed "s|^|$file:|")"
        fi
    done <<<"$files"
done

if [ "$STAGED" = 0 ]; then
    for pattern in "${PATTERNS[@]}"; do
        while IFS= read -r sha; do
            [ -n "$sha" ] || continue
            report "commit $sha: $(git log -1 --format=%s "$sha" | cut -c1-60)"
        done <<<"$(git log --all --format=%H --grep="$pattern" --extended-regexp 2>/dev/null || true)"
    done

    # Everyone who has ever authored or committed here has to be on the list.
    while IFS= read -r who; do
        [ -n "$who" ] || continue
        for known in "${AUTHORS[@]}"; do
            [ "$who" = "$known" ] && continue 2
        done
        report "not on the author list: $who"
    done <<<"$(git log --all --format='%an <%ae>%n%cn <%ce>' 2>/dev/null | sort -u)"
fi

if [ "$found" = 1 ]; then
    cat >&2 <<'MSG'

A commit claims an author this project does not have. Remove the trailer, or
add the person to AUTHORS in scripts/one-author.sh if they are real.
MSG
    exit 1
fi

echo "  one author throughout"
