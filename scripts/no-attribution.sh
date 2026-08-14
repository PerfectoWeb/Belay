#!/usr/bin/env bash
# Fails if anything in this repository credits an AI for the work.
#
#   ./scripts/no-attribution.sh            # the whole history and the tree
#   ./scripts/no-attribution.sh --staged   # only what is about to be committed
#
# The repository is public and the work is the author's. A `Co-Authored-By`
# trailer is enough for GitHub to list a second contributor on the front page,
# which is how one got there and had to be removed by rewriting history on two
# branches and, in the end, by moving to a fresh repository. This runs in the
# gate and in a pre-commit hook so it cannot happen twice.
#
# What it looks for is *attribution*, not the word "Claude". Claude Code is one
# of the agents Belay watches: it is named in the interface, in six
# translations, in the App Store listing and on the site, and every one of those
# is correct. The patterns below only match a claim of authorship.
set -euo pipefail

cd "$(dirname "$0")/.."

# Each is anchored so an ordinary mention cannot trip it. The trailers are
# matched at the start of a line, the address is unmistakable on its own, and
# the two generator lines are matched as whole phrases.
PATTERNS=(
    '^[[:space:]]*Co-[Aa]uthored-[Bb]y:'
    '^[[:space:]]*Signed-off-by:.*([Cc]laude|[Aa]nthropic)'
    'noreply@anthropic\.com'
    '[Gg]enerated with \[?[Cc]laude'
    '🤖 [Gg]enerated'
    '[Cc]o-written (with|by) (an )?AI'
)

STAGED=0
[ "${1:-}" = "--staged" ] && STAGED=1

found=0
report() { echo "  $1" >&2; found=1; }

# --- what is about to be committed, or the whole working tree ----------------

if [ "$STAGED" = 1 ]; then
    files="$(git diff --cached --name-only --diff-filter=ACM)"
else
    files="$(git ls-files)"
fi

for pattern in "${PATTERNS[@]}"; do
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        [ -f "$file" ] || continue
        # Binary files cannot carry a trailer and grep -I skips them.
        if grep -InE "$pattern" -- "$file" >/dev/null 2>&1; then
            report "$(grep -InE "$pattern" -- "$file" | head -1 | sed "s|^|$file:|")"
        fi
    done <<<"$files"
done

# --- commit messages and the identities on them ------------------------------
#
# Skipped for --staged, where there is no commit yet; the hook checks the
# message separately through commit-msg.

if [ "$STAGED" = 0 ]; then
    for pattern in "${PATTERNS[@]}"; do
        while IFS= read -r sha; do
            [ -n "$sha" ] || continue
            report "commit $sha: $(git log -1 --format=%s "$sha" | cut -c1-60)"
        done <<<"$(git log --all --format=%H --grep="$pattern" --extended-regexp 2>/dev/null || true)"
    done

    while IFS= read -r who; do
        [ -n "$who" ] || continue
        report "author or committer: $who"
    done <<<"$(git log --all --format='%an <%ae>%n%cn <%ce>' 2>/dev/null \
        | sort -u | grep -iE 'claude|anthropic|copilot|assistant@' || true)"
fi

if [ "$found" = 1 ]; then
    cat >&2 <<'MSG'

Attribution to an AI found. Remove it before committing.

If a match above is a false positive, the pattern is too broad: tighten it in
scripts/no-attribution.sh rather than adding an exception, because an exception
list is the thing that quietly grows until the check means nothing.
MSG
    exit 1
fi

echo "  no AI attribution anywhere"
