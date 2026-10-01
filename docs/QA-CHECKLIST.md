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
pmset -g assertions | grep "pid $(pgrep -x Belay)("
```

Grepping for the word "belay" also matches `runningboardd`'s launch assertion
for our bundle ID, which is not ours. Match on the pid.

---

## 1. Power core (M1)

- [x] Auto mode, no sessions → no Belay assertion held
- [x] Always on → `PreventUserIdleSystemSleep` named "Belay", details string set
- [x] Assertion carries `Timeout will fire in N secs Action=TimeoutActionRelease`
- [x] **Invariant 2, observed 2026-08-12.** `kill -9` on Belay while it held
      both assertions: `pmset -g assertions | grep "pid <pid>("` listed
      `PreventUserIdleSystemSleep` and `PreventUserIdleDisplaySleep` before, and
      nothing at all one second after. SIGKILL on purpose – a graceful quit only
      exercises the cleanup code we already test; this is the crash case, where
      no handler of ours runs and the kernel has to be the one that releases.
- [x] Refresh re-arms before expiry (observed 100→85→70→55→40, then 117)
- [x] Quit while holding → assertion count drops to 0
- [x] Off mode → nothing held
- [x] Idle CPU 0.0% over a 200 s sample
- [x] Force-quit (`kill -9`) while holding → assertion self-releases within the
      timeout window. **This is invariant 2 and the single most important check
      in this document.** Observed 2026-08-12 (see the invariant-2 row above).
- [x] `SIGTERM` → releases and exits. Observed 2026-08-31: three assertions
      (`system`, `display`, `network`) → none within two seconds, process gone,
      and the 1.7.0 parking wrote its "parked hooks for quit" line on the way
      out; the relaunch restored all fourteen entries on the same port.
- [x] Sleep the Mac, wake it → state resyncs, no stale hold. Observed in the
      2026-08-31 soak (13:05:56 sleep: all three assertions released at the
      notification; 13:09:35 wake: re-armed fresh, no stale hold in between).
- [ ] Battery guard: unplug below the floor → releases, panel says why; plug back
      in → re-arms

## 2. Detection (M2/M3)

- [x] **FSEvents on `~/.claude` delivers.** Verified in M2 against the real
      directory: start in 3 ms over 45 transcripts, zero signals for the 44
      stale ones, live session tracked. TCC does not interfere.
- [x] A real Claude Code session is detected with zero configuration →
      `Details: An agent is working in <project>`
- [x] Several concurrent sessions aggregate → `2 agent sessions are working`
- [x] Start a real long Claude Code task → assertion appears within ~5 s.
      2026-08-31 11:58:23: `UserPromptSubmit` and `hold on` share a timestamp.
- [x] Assertion persists through the whole run, including a long tool call with
      no transcript growth. 2026-08-31: repeated four-minute foreground
      `sleep` tool calls (the badge demos) held continuously — the open
      tool-call bracket carrying exactly this case.
- [ ] Assertion **disappears** within grace + 10 s of the run finishing
- [ ] Set system sleep to 1 minute, run a 10-minute task → no sleep during, then
      the Mac sleeps ~1 minute after it ends
- [ ] `kill -9` the `claude` process mid-task → release within TTL
- [x] Launch Belay with 45 old transcripts present → does **not** discover them
      as active sessions and pin the Mac awake
- [x] Hook events beyond `UserPromptSubmit`/`SessionEnd` observed for real.
      One 2026-08-31 soak day: `PreToolUse` ×1521, `PostToolUse` ×1513,
      `PostToolBatch` ×1437, `Stop` ×140, `SubagentStart` ×26,
      `StopFailure`, `PermissionRequest` and `Notification` ×1 each — every
      mapped event seen live, plus `background_tasks` payloads verified
      against a captured Stop.
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
- [ ] Icon is legible at a glance in **both** appearances – is it obvious
      whether the Mac is being held awake?
- [ ] Light mode, dark mode, tinted menu bar, Reduce Transparency
- [ ] Reduce Motion → popover does not animate
- [ ] Second display with different scaling
- [ ] Full keyboard navigation through the panel
- [ ] VoiceOver reads the status item state and every panel control
- [ ] Settings window opens (Cmd+, with Belay active, or the panel footer link)
      and all seven panes render (General, Agents, Behaviour,
      Notifications, Modules, Statistics, About), with the switcher on one row
      in every language
- [ ] Modules: Install on Screenshot Cleaner switches it on and lists the
      capture folder; the App Store build asks for the folder first, and
      cancelling that panel installs nothing
- [ ] Modules: the direct build's first pass raises the macOS folder question
      with Belay's explanation under it, in the app's language
- [ ] Modules: a screenshot older than the age goes to the Trash within five
      minutes once the grace has passed; a tagged one and an edited one stay
- [ ] Modules: with the Desktop kept in iCloud Drive, the direct build still
      moves a due screenshot to the Trash (`screenshots trashed=` with no
      `failed=` in the log); the App Store build is checked the same way
- [ ] Modules: "Clean Up Now" moves what is past its age at once, in both
      builds (the App Store build through its folder grant)
- [ ] Modules: Remove Module stops it, and installing again starts from the
      defaults
- [ ] Warm Microphone: the first switch-on raises the macOS microphone
      question with Belay's explanation, in both builds; the orange dot shows
      while it is on and goes within seconds of switching it off
- [ ] Warm Microphone never installed, output set to a device that also
      records (USB interface, headset): switching modes and opening What's New
      raise no microphone question and make no sound; on the built-in speakers
      the sounds play
- [ ] Warm Microphone: plugging in a headset, or changing the input in System
      Settings, moves the status line to the new microphone within five seconds
- [ ] Warm Microphone: connecting AirPods that take over the input moves the
      status line to "Paused for a Bluetooth microphone", the orange dot goes
      and music keeps its quality; disconnecting them brings the dot back. With
      "Leave Bluetooth headphones alone" off the AirPods microphone is held
- [ ] Modules: with "Keep crash reports on this Mac" on, a launch writes
      `modules start`, and each module writes its settings and every change of
      state; no line holds a path, a site, a process name or a device name
- [ ] Warm Microphone: after sleep and wake the dot is back; with "Pause on
      battery power" on, unplugging lets the microphone go and power brings it
      back
- [ ] Warm Microphone: refusing the microphone shows the red line and the
      button to System Settings, and nothing is opened
- [ ] Auto Allow (direct build): installing raises the macOS Accessibility
      question; without the grant the red line shows and nothing is pressed
- [ ] Auto Allow: a request for a local site in the Claude desktop app is
      answered within a few seconds and appears under "Recently approved"; a
      request for a site on the internet, and a request to run a command, wait
- [ ] Auto Allow: with "Answer in sessions behind the window" on and another
      app in front, a request in a session the window is not showing is
      answered and the window shows the same session as before; while you
      type or click, in any app, the window does not change until five
      seconds of stillness; when the visit pulled the agent's app to the
      front, the app you had in front comes back, and the log says
      `autoallow front=restored`
- [ ] Auto Allow: a session behind the window that waited for you, was
      answered by you and asks again is visited again, also when it moved on
      while you were typing
- [ ] Auto Allow: with the Claude window on another desktop (or behind a
      full-screen app) a request is still answered
- [ ] Auto Allow: "Everything the agent asks" shows the orange warning and
      answers both of those
- [ ] Nudge: installing asks for notification permission once; with it refused
      the card shows the red line and the button to System Settings, and the
      sounds still play
- [ ] Nudge: a run of a minute or more that ends plays the finished note and
      posts "An agent finished" naming the workspace; a run under "Ignore runs
      shorter than" does neither; each checkbox silences only its own sound
- [ ] Nudge: a session that waits for you plays the waiting note (a touch
      higher than the finished one), the card says "Waiting for you: 1", and a
      reminder comes after the chosen minutes, at most the chosen number of
      times; answering the session stops them and resets the count
- [ ] Nudge: killing an agent mid-run plays the lowest note
- [ ] Nudge: with "Your agent finished" also on in Notifications, a run that
      ends gives both banners and says so in the card's text
- [ ] Nudge: clicking a banner for a Claude Code session in the Claude desktop
      app brings that app forward; for one in a terminal or an editor, that
      terminal or editor; for Codex, the ChatGPT app; with none found, nothing
      moves
- [ ] Nudge: with the output on a device that also records and the microphone
      question unanswered, the three sounds stay silent
- [ ] Auto Allow: with "Switch off after" at one hour the switch is off an hour
      later, also when Belay was quit and opened again in between
- [ ] Auto Allow: with Claude Code switched off in Agents a request stays
      unanswered and the card says the agent is switched off; switching it
      back on answers the request
- [ ] Auto Allow: in Codex (the ChatGPT app, permissions set to "Ask for
      approval") a Browser request for a local site is answered within a few
      seconds and listed under "Recently approved"; a command whose text
      mentions `localhost` waits
- [ ] Auto Allow: a Codex session behind the window that shows "Awaiting
      approval" is opened, answered and the window shows the same session as
      before
- [ ] Auto Allow: with Codex switched off in Agents a Codex request waits and
      the card names Codex
- [ ] Auto Allow is absent from the App Store build's list
- [ ] Orphan Watch: installing it lists nothing and asks macOS for nothing; with
      a Claude Code session open, a `node` started in the background from it
      (`node -e "setInterval(()=>{},1000)"`) stays unlisted while the session
      lives, and after the session is closed the card shows "Left behind: 1"
      with `node`, its number, its age and Claude Code within a minute, and
      one banner "Left behind by an agent"; a click on it opens Settings ▸
      Modules
- [ ] Orphan Watch (direct build): End on that row asks first, and after
      Confirm the process is gone within seconds and the row with it; Cancel
      changes nothing; `orphans ended=1 failed=0` is in the log. End All names
      the count. A process that ignores SIGTERM (`trap '' TERM`) is reported as
      still running and is not killed
- [ ] Orphan Watch (App Store build): the list shows the same rows with no End
      button and the line "End it in Activity Monitor."
- [ ] Orphan Watch: "Ignore" on a row takes the name off the list at once and
      into "Ignored"; the minus beside it brings it back
- [ ] Orphan Watch: a process from an agent's tree that burns a core (`yes >
      /dev/null`) while no session of that agent is working shows under
      "Running hot" after the chosen time, with the percentage; while a
      session of that agent is working it does not
- [ ] Orphan Watch: with Codex switched off in Agents its processes are not
      listed and the card names Codex; the log holds no process name
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
> accessibility API instead – it can only see our own process:
>
> ```bash
> osascript -e 'tell application "System Events" to tell process "Belay" \
>   to get {count of windows, description of menu bar item 1 of menu bar 2}'
> ```

## 4. Performance (`docs/08` budgets)

- [!] Active CPU < 1.0% during a real run – 0.072% on the Release M1 build.
      2026-08-31, Debug build, two live sessions and ~1500 hook posts: 2.04%,
      traced by `sample` to the token counter running the full JSON decoder
      over every delta line; a `"usage"` substring pre-filter cut it to 1.47%.
      Debug carries the rest of the overhang — re-measure on the 1.7.0
      Release artifact before publishing.
- [!] Idle CPU < 0.1% – not yet measurable: real Claude Code sessions ran
      throughout every soak, so no interval was idle. Needs a quiet machine.
- [x] Memory < 40 MB – 2026-08-31, 1.7.0 Debug with badges, history, tokens
      and the away watch all live: **19 MB** `phys_footprint`, 20 MB peak
      (23 MB at 1.5.0, 15 MB at M1).
      Measure with `footprint -p <pid>`, **not** `ps -o rss=`: RSS counts shared
      framework pages every app maps and reads ~75 MB here, which is misleading.
- [ ] Footprint flat between the 30-minute and 8-hour marks
- [!] Wakeups/s < 3 idle – `powermetrics` is root-only and there is no
      passwordless sudo here, so `scripts/perf-soak.sh` skips it. Close with
      `sudo scripts/perf-soak.sh`.
- [ ] Cold launch to menu bar icon < 300 ms
- [ ] 30-minute idle soak: no assertion held, no memory growth

## 4b. Sanitizers

- [x] Address sanitizer clean (`scripts/leak-check.sh`) – 118 results, 0 reports
- [x] Thread sanitizer clean (`scripts/leak-check.sh --thread`) – 0 reports
- [x] Leak check proper. 2026-08-31: `leaks` against the live 1.7.0 process
      after a full soak day — 30 727 nodes, **0 leaks, 0 bytes**.

## 5. Platform coverage

- [x] macOS 26.4 (host)
- [x] macOS 14 (real install, 1.3.0 build) – 2026-08-19
- [x] macOS 15.0 (24A335, Parallels, Apple silicon) – 2026-08-16

---

**Last run:** 2026-08-31, power/detection/perf items re-run on the 1.7.0
Debug build during the soak day, macOS 26.4 / Xcode 26.6. Found and fixed one
regression in the act: the tokens counter was decoding every transcript line
(2.04% CPU against the 1% budget) — pre-filtered to `"usage"` carriers.
UI items (§3) remain eyes-only and are listed for a human pass.
**Last VM run:** 2026-08-16, macOS 15.0, `scripts/qa-vm.sh`. Every mode held or
released what it should, the 60-second cap fired at 60 seconds, no crash, and no
`shutdown release timed out` line – which is the fix from this round showing up.
The welcome screen and the paused mark were checked by eye and were right.

---

## 9. The App Store build's sandbox (B8) – run 2026-08-12, passed

`Tests/BelaySandboxTests` runs inside the sandbox on every gate and covers
everything except the click. This is the click.

- [x] Build **without the test bundle** (`-scheme Belay-MAS -configuration Release`),
      or the harness grants the app read access to `/` and the next two items
      pass for the wrong reason. See BLOCKERS B8.
- [x] With no grant yet, the app cannot read a file under `~/.claude`
- [x] Build and run the MAS channel: `xcodebuild -scheme Belay-MAS -configuration Debug ...`,
      then open `build/DerivedData-MAS/Build/Products/Debug/Belay-MAS.app`
- [x] Providers pane shows Claude Code as needing access, not as ready
- [x] Press the button, pick `~/.claude` in the open panel, allow
- [x] The pane now says ready, and the panel lists a Claude Code session while
      one is running
- [x] Quit and reopen. Still ready, with no second panel: this is the bookmark,
      and it is the half that dies silently if only the panel grant was kept

Evidence, not just a tick: `BelayClaudeFolderBookmark` (660 bytes) is in
`~/Library/Containers/com.perfectoweb.belay/Data/Library/Preferences/com.perfectoweb.belay.plist`,
written at the moment the panel was answered. A bookmark inside the container is
something only the sandboxed build can produce.
