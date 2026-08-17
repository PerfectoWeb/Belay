<!--
Keep this short. Delete any section that does not apply, including this comment.
The long version of what is expected is in docs/CONTRIBUTING.md.
-->

## What this changes

<!-- One or two sentences. What was wrong or missing. -->

## Why this way

<!-- The reasoning a reviewer cannot get from the diff: what else you tried, and
why this fix is the right one rather than a working one. -->

## What I ran

- [ ] `scripts/test.sh` passes, ending in `all green`
- [ ] Checked by hand, because unit tests cannot prove it (say what you did)

macOS version and Mac:

<!-- For a detection or power change, paste `pmset -g assertions | grep -i belay`
before and after. macOS 14 and 15 have had no testing on real hardware, so a run
on either is worth mentioning on its own. -->

## Invariants

<!-- Required if this touches detection, power, or ~/.claude/settings.json.
Which of the invariants in docs/00-INVARIANTS.md could this break, and what
stops it? "None of them, here is why" is a valid answer, but say it. -->

- [ ] Still at most one power assertion, and it still carries a timeout
- [ ] Every new hold path has its release, and a test that proves the balance
- [ ] No prompt, model response or source code is read, logged or stored
- [ ] Nothing writes to `~/.claude/` without consent in the UI and a backup first
- [ ] No new network access, and no timer faster than 5 s

## User-visible strings

- [ ] None
- [ ] Added or changed, and `Resources/Localizable.xcstrings` has all six
      languages filled in

<!-- Screenshots for anything visible, light and dark. -->
