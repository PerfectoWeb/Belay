# What only you can do: B4 and B5

Two blockers need a person, and one of them needs a second Mac. Everything else
on the pre-release list is mine. Notarization comes after both of these, because
a rename after notarizing means doing it again.

---

## B4 — Is the name free?

Twenty minutes, no second machine. Do this **before** notarizing: the bundle
identifier and the notarized ticket are tied to the name, and a rename after
launch is expensive in a way a rename today is not.

### 1. Mac App Store

Open App Store, search **belay**. You are looking for one thing only: a utility
that could be confused with this one. A game, a journal app, a security camera
service called Belay is not a conflict. Another menu bar app about sleep,
caffeine or keeping a Mac awake is.

Write down, for anything close: name, developer, category, last update.

### 2. Trademark registers

Both take a search box and a minute each.

- USPTO: <https://tmsearch.uspto.gov> — search `belay`, filter to live marks in
  class **009** (software) and **042** (SaaS).
- EUIPO: <https://euipo.europa.eu/eSearch/> — same term, same classes.

A live mark in 009/042 held by a software company is a real problem. A live mark
for belay candles is not.

### 3. The obvious ones

- `belay.app`, `getbelay.com`, `belayapp.com` — is any of them free, and is
  anything already at them?
- GitHub: is there a well-known `belay` doing something adjacent?
- Homebrew: `brew search belay`.

### What to send me

Either "clear" or the list of what you found. If it is not clear,
`docs/NAMING.md` has five ranked alternatives, and the rename is two files plus
`xcodegen generate` — under an hour, today. After launch it is a migration.

---

## B5 — Does it run on macOS 14 and 15?

This needs the second laptop. The deployment target is 14.0 and every newer API
is behind an `@available` guard, so this is a check, not an expedition. But it
has never been done, and the invariants file claims it.

### Get a build onto the other Mac

On this Mac:

```bash
scripts/build-local.sh && open build
```

Copy `build/Belay.app` across however you like. It is ad-hoc signed, so the
other Mac will refuse it on first open: **right-click the app → Open → Open**.
That is expected and is exactly what notarization removes later.

### What to run, in order

Full list is `docs/QA-CHECKLIST.md`. If you only have half an hour, these are
the ones that would actually change the release:

1. **It launches at all.** A menu bar icon appears. No crash, no dialog.
   A missing symbol from a newer SDK shows up here and nowhere else.
2. **Settings opens and every pane draws.** Six panes, no empty window, no
   clipped control. This is where an `@available` guard I forgot will show.
3. **The panel opens from the icon** and the three modes switch.
4. **Always On actually holds.** Switch to Always On, then in Terminal:
   ```bash
   pmset -g assertions | grep "pid $(pgrep -x Belay)("
   ```
   You want a `PreventUserIdleSystemSleep` line naming Belay, with
   `Timeout will fire in N secs Action=TimeoutActionRelease` after it.
5. **Off releases it.** Switch to Off, run the same command: no line.
6. **Claude Code detection**, if that Mac has Claude Code. Start a turn, watch
   the panel say an agent is working.
7. **Login item.** Tick "Open at login" in General, untick it. Both must stick.
   This one broke before, on this very machine, in a way only macOS could
   explain.

### What to send me

Which macOS version, and for each of the seven: pass, fail, or did not run.
A screenshot of anything that looks wrong. Do not try to fix it — the point of
the exercise is the list.

If step 1 fails, stop and send me the crash report from
`~/Library/Logs/DiagnosticReports/`. Everything after that is noise until it
launches.

---

## Then, and only then: notarization

Once the name is clear and 14 or 15 has run clean, I run `scripts/notarize.sh`
against the Developer ID certificate. It needs nothing from you except the
App Store Connect key already on this Mac, which stays on this Mac.
