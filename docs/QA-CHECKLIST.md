# Manual QA checklist

Things that cannot be proven by `swift test`. Run all of it before calling a
build shippable. Record results and the date at the bottom.

Status key: **[x]** verified · **[ ]** not yet run · **[!]** blocked, see note.

---

## 0. Before you start

macOS already holds `PreventUserIdleSystemSleep` via `powerd` ("Prevent sleep
while display is on") whenever the display is awake. If you check assertions
with the screen on, **everything looks like a pass**. Either let the display
sleep first, or filter to our process:

```bash
pmset -g assertions | grep "pid $(pgrep -x Vigil)("
```

Grepping for the word "vigil" also matches `runningboardd`'s launch assertion
for our bundle ID, which is not ours. Match on the pid.

---

## 1. Power core (M1)

- [x] Auto mode, no sessions → no Vigil assertion held
- [x] Always on → `PreventUserIdleSystemSleep` named "Vigil", details string set
- [x] Assertion carries `Timeout will fire in N secs Action=TimeoutActionRelease`
- [x] **Invariant 2, observed 2026-08-12.** `kill -9` on Vigil while it held
      both assertions: `pmset -g assertions | grep "pid <pid>("` listed
      `PreventUserIdleSystemSleep` and `PreventUserIdleDisplaySleep` before, and
      nothing at all one second after. SIGKILL on purpose — a graceful quit only
      exercises the cleanup code we already test; this is the crash case, where
      no handler of ours runs and the kernel has to be the one that releases.
- [x] Refresh re-arms before expiry (observed 100→85→70→55→40, then 117)
- [x] Quit while holding → assertion count drops to 0
- [x] Off mode → nothing held
- [x] Idle CPU 0.0% over a 200 s sample
- [ ] Force-quit (`kill -9`) while holding → assertion self-releases within the
      timeout window. **This is invariant 2 and the single most important check
      in this document.**
- [ ] `SIGTERM` → releases and exits
- [ ] Sleep the Mac manually, wake it → state resyncs, no stale hold
- [ ] Battery guard: unplug below the floor → releases, panel says why; plug back
      in → re-arms

## 2. Detection (M2/M3)

- [x] **FSEvents on `~/.claude` delivers.** Verified in M2 against the real
      directory: start in 3 ms over 45 transcripts, zero signals for the 44
      stale ones, live session tracked. TCC does not interfere.
- [x] A real Claude Code session is detected with zero configuration →
      `Details: An agent is working in <project>`
- [x] Several concurrent sessions aggregate → `2 agent sessions are working`
- [ ] Start a real long Claude Code task → assertion appears within ~5 s
- [ ] Assertion persists through the whole run, including a long tool call with
      no transcript growth (`docs/DISCOVERY.md` §2.2 shows a real 10 s silence)
- [ ] Assertion **disappears** within grace + 10 s of the run finishing
- [ ] Set system sleep to 1 minute, run a 10-minute task → no sleep during, then
      the Mac sleeps ~1 minute after it ends
- [ ] `kill -9` the `claude` process mid-task → release within TTL
- [x] Launch Vigil with 45 old transcripts present → does **not** discover them
      as active sessions and pin the Mac awake
- [ ] Hook events beyond `UserPromptSubmit`/`SessionEnd` observed for real.
      Only those two were captured during discovery; the rest are mapped from
      the live reference. Verify `PreToolUse`, `PostToolUse`, `Stop`,
      `PermissionRequest`, `Notification` against an interactive session.
- [ ] Installing hooks does not measurably slow a Claude Code turn (time a turn
      with and without)
- [ ] Uninstalling hooks restores `settings.json` exactly
- [x] Receiver binds `127.0.0.1` only (`lsof` shows no `*:port`)
- [x] `bridge.json` is 0600 with a 256-bit token
- [x] A wrong bearer token is rejected 401 and the body is never parsed
- [x] A `prompt` field sent to the receiver is retained nowhere
- [x] Hook `SessionEnd` removes the session from the aggregate count

## 3. UI

- [ ] **Panel opens on left-click and dismisses on click-away.** Cannot be
      automated: the XCTest host's status bar window has no screen, so
      `NSPopover` cannot present there, and AppleScript's synthetic press is not
      a reliable substitute. Click it yourself.
- [ ] Right-click opens the compact menu with Mode, Quit
- [ ] Icon is legible at a glance in **both** appearances — is it obvious
      whether the Mac is being held awake?
- [ ] Light mode, dark mode, tinted menu bar, Reduce Transparency
- [ ] Reduce Motion → popover does not animate
- [ ] Second display with different scaling
- [ ] Full keyboard navigation through the panel
- [ ] VoiceOver reads the status item state and every panel control
- [ ] Settings window opens (Cmd+, with Vigil active, or the panel footer link)
      and all five panes render (General, Providers, Behaviour,
      Notifications, About)
- [ ] "Open at login" toggle actually registers with `SMAppService`, survives a
      restart, and reflects the truth after being revoked in System Settings
- [ ] Turning the battery guard off and on again restores the previous
      threshold rather than resetting to the default
- [ ] Notification permission is requested only when a notification first fires,
      never at launch
- [ ] "An agent is waiting for you" fires exactly once per blocked session, not
      once per poll (needs hooks installed to be reachable at all)

- [x] Onboarding shows once on a clean install, dismisses, and does **not**
      reappear on the next launch (verified: 1 window → 0, flag persisted)

> Note: on a machine with a crowded menu bar, macOS hides overflow status items.
> The item can exist and be unreachable. If you cannot find it, free some space
> before concluding it is broken.
>
> **Do not verify UI with `screencapture`.** It photographs the whole screen,
> including whatever private windows the user has open, and on this machine it
> captured a personal chat before anyone noticed. Inspect the app through the
> accessibility API instead — it can only see our own process:
>
> ```bash
> osascript -e 'tell application "System Events" to tell process "Vigil" \
>   to get {count of windows, description of menu bar item 1 of menu bar 2}'
> ```

## 4. Performance (`docs/08` budgets)

- [x] Active CPU < 1.0% during a real run — measured 0.072%
- [!] Idle CPU < 0.1% — not yet measurable: real Claude Code sessions ran
      throughout every soak, so no interval was idle. Needs a quiet machine.
- [x] Memory < 40 MB — `footprint` reports **23 MB** `phys_footprint` with every
      provider and the hook receiver running (15 MB at M1, before Tier B and the
      generic provider existed).
      Measure with `footprint -p <pid>`, **not** `ps -o rss=`: RSS counts shared
      framework pages every app maps and reads ~75 MB here, which is misleading.
- [ ] Footprint flat between the 30-minute and 8-hour marks
- [!] Wakeups/s < 3 idle — `powermetrics` is root-only and there is no
      passwordless sudo here, so `scripts/perf-soak.sh` skips it. Close with
      `sudo scripts/perf-soak.sh`.
- [ ] Cold launch to menu bar icon < 300 ms
- [ ] 30-minute idle soak: no assertion held, no memory growth

## 4b. Sanitizers

- [x] Address sanitizer clean (`scripts/leak-check.sh`) — 118 results, 0 reports
- [x] Thread sanitizer clean (`scripts/leak-check.sh --thread`) — 0 reports
- [ ] Leak check proper. Darwin's ASan ships **without** LeakSanitizer, so the
      clean run above proves no use-after-free or overflow, not no leaks. Use
      Instruments Leaks for the real thing.

## 5. Platform coverage

- [x] macOS 26.4 (host)
- [ ] macOS 14 (VM) — see `BLOCKERS.md` B5
- [ ] macOS 15 (VM)

---

**Last run:** 2026-08-12, M1 and M2 items, on macOS 26.4 / Xcode 26.6.

---

## 9. The App Store build's sandbox (B8)

`Tests/VigilSandboxTests` runs inside the sandbox on every gate and covers
everything except the click. This is the click.

- [ ] Build **without the test bundle** (`-scheme Vigil-MAS -configuration Release`),
      or the harness grants the app read access to `/` and the next two items
      pass for the wrong reason. See BLOCKERS B8.
- [ ] With no grant yet, the app cannot read a file under `~/.claude`
- [ ] Build and run the MAS channel: `xcodebuild -scheme Vigil-MAS -configuration Debug ...`,
      then open `build/DerivedData-MAS/Build/Products/Debug/Vigil-MAS.app`
- [ ] Providers pane shows Claude Code as needing access, not as ready
- [ ] Press the button, pick `~/.claude` in the open panel, allow
- [ ] The pane now says ready, and the panel lists a Claude Code session while
      one is running
- [ ] Quit and reopen. Still ready, with no second panel: this is the bookmark,
      and it is the half that dies silently if only the panel grant was kept
