#!/usr/bin/env bash
# Fails if a commit credits an AI tool as an author.
#
#   ./scripts/no-ai-authors.sh            # the whole history and the tree
#   ./scripts/no-ai-authors.sh --staged   # only what is about to be committed
#
# Contributors are wanted, and any number of them. What this refuses is a
# machine in the author field. A `Co-Authored-By` trailer is enough for the
# forge to list an assistant as a contributor on the front page of a public
# repository, and once it has done that, taking it back means rewriting history
# on every branch. Cheaper to refuse it going in.
#
# Two rules, and they catch different things. The first is about the message: a
# trailer or a generator line, whoever wrote the commit. The second is about the
# identity: a commit authored or committed by an assistant or a bot directly.
set -euo pipefail

cd "$(dirname "$0")/.."

# Trailers and generator lines, anchored so ordinary prose cannot trip them.
# The last one is built from its bytes rather than written out, because a file
# that contains the thing it forbids matches itself and fails every run.
ROBOT="$(printf '\xf0\x9f\xa4\x96')"
PATTERNS=(
    '^[[:space:]]*Co-[Aa]uthored-[Bb]y:'
    '^[[:space:]]*[Gg]enerated with \['
    "$ROBOT"
)

# Identities that are not people. Matched against "Name <email>", case
# insensitively, and deliberately anchored rather than loose: "Claude" is a
# French given name and "Codex" is a word, so a bare substring would one day
# reject a human being. What is matched instead is the shape these tools
# actually sign with — the exact handle, the vendor's own domain, or the
# `[bot]` suffix the forge appends.
ROBOT_IDENTITIES=(
    '^(claude|claude code|codex|chatgpt|copilot|github copilot|cursor|devin|aider|gemini|gemini cli|cline|windsurf|jules|amp) <'
    '<[^>]*@(anthropic|openai)\.com>'
    '<[^>]*(noreply\.)?(anthropic|openai)\.com>'
    '\[bot\] <'
    '<[0-9]+\+[^>]*\[bot\]@users\.noreply\.github\.com>'
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

# The staged run has no commit to inspect yet, so it checks the message the
# hook is about to write and the identity git would stamp on it.
if [ "$STAGED" = 1 ]; then
    who="$(git var GIT_AUTHOR_IDENT | sed -E 's/^(.*>).*$/\1/')"
    for pattern in "${ROBOT_IDENTITIES[@]}"; do
        if printf '%s\n' "$who" | grep -qiE "$pattern"; then
            report "about to commit as: $who"
        fi
    done
else
    for pattern in "${PATTERNS[@]}"; do
        while IFS= read -r sha; do
            [ -n "$sha" ] || continue
            report "commit $sha: $(git log -1 --format=%s "$sha" | cut -c1-60)"
        done <<<"$(git log --all --format=%H --grep="$pattern" --extended-regexp 2>/dev/null || true)"
    done

    # Nobody has to be on a list. What is refused is a machine.
    while IFS= read -r who; do
        [ -n "$who" ] || continue
        for pattern in "${ROBOT_IDENTITIES[@]}"; do
            if printf '%s\n' "$who" | grep -qiE "$pattern"; then
                report "not a person: $who"
                break
            fi
        done
    done <<<"$(git log --all --format='%an <%ae>%n%cn <%ce>' 2>/dev/null | sort -u)"
fi

if [ "$found" = 1 ]; then
    cat >&2 <<'MSG'

A commit credits an AI tool. Remove the trailer, or commit under your own name.
People are welcome here; assistants are not authors.
MSG
    exit 1
fi

echo "  no AI authors"
