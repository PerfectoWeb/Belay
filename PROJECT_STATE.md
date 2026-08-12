# Project state

Source of truth for progress. Updated at the end of every milestone.

**Status:** v1.0 complete. All milestones done; outstanding items are
manual-QA and Apple-account blockers, both listed explicitly below.
**Last updated:** 2026-08-10.

---

## Milestones

| | Milestone | State |
|---|---|---|
| M0 | Discovery & scaffold | **done** |
| M1 | Power core | **done** |
| M2 | Claude Code detection (Tier A) | **done** |
| M3 | Hook bridge (Tier B) | **done** |
| M4 | Product polish | **done** |
| M5 | Additional providers | **done** |
| M6 | Distribution | **done** |
| M7 | Hardening & handoff | **done** |

### M0 — done

Toolchain verified (Xcode 26.6, Swift 6.3.3, macOS 26.4); `swiftlint` 0.65.0 and
`swift-format` 603.0.0 installed via Homebrew, `xcodegen` was already present.
Empirical discovery pass written to `docs/DISCOVERY.md`. Scaffold builds, the app
runs as a menu-bar-only item with no Dock presence, holds no assertion, and quits
cleanly. `swiftlint --strict` and `swift-format lint --strict` are clean.

Verified at M0 exit:

```
build/Belay.app                     ad-hoc signed, satisfies its Designated Requirement
LSUIElement                         no Dock icon confirmed via System Events
pmset -g assertions | grep -i belay no assertion held (correct at M0)
```

### M1 — done

`BelayPower` (assertion controller, IOKit backend + mock, refresh loop, power
source, sleep/wake, signal handling), `BelaySettings` (typed store, clamping,
migration) and `BelayCore` (the state machine, ledger, driver) are built and
wired into the app through `BelayController`. 56 module tests plus 3 app tests,
all green; `swiftlint --strict` and `swift-format lint --strict` clean.

Verified on the real machine, not just in tests:

```
Auto mode, no sessions      no assertion held                       correct
Always on                   PreventUserIdleSystemSleep, named "Belay"
                            Details: Always on
                            Timeout will fire in 116 secs Action=TimeoutActionRelease
Refresh loop                remaining counted 100→85→70→55→40 then jumped to 117
                            re-armed at 75% of the 120 s timeout, ~30 s margin
Quit while holding          assertion count dropped to 0            invariant 4
Off mode                    no assertion held                       correct
Idle CPU                    0.0% across a 200 s sample              budget < 0.1%
```

Two bugs the milestone found, both fixed:

- **Nothing evaluated at startup.** A persisted Always-on mode did nothing for up
  to a minute, because the coordinator is purely reactive and the driver's first
  tick is its idle interval away. `BelayController.start()` now seeds power
  conditions and forces one evaluation.
- **The `Observation` name collision.** `BelayCore` declared a `public struct
  Observation`, which shadowed the Observation *module* inside the `@Observable`
  macro expansion and broke any module that used both. Renamed to `Reading`.

**Memory is inside budget.** An earlier reading of ~72 MB came from
`ps -o rss=`, which counts shared, already-resident framework pages that every
app on the system maps. The tool `docs/08` actually specifies, `footprint`,
reports a **`phys_footprint` of 15.1 MB** against the < 40 MB budget:

```
footprint -p <pid>   →  TOTAL 15 MB,  phys_footprint: 15 MB (peak 15 MB)
vmmap --summary      →  Physical footprint: 15.1M
                        Writable regions: written=10.4M(4%) of 261.6M
```

So there is no memory problem and no SwiftUI-removal work for M7. Use
`footprint`, never `ps -o rss=`, for this budget.

### M2 — done

`BelayProviders` (FSEvents watcher, incremental transcript cursors, classifier,
process presence) and the panel UI are built and wired through `SignalBus` into
the coordinator. 101 module tests + 17 app tests, lint clean.

**FSEvents works.** The discovery-era crash was the throwaway probe's bug, not
the platform's: against the real `~/.claude/projects`, `start()` returned in 3 ms
across 45 transcripts in 19 project directories, emitted **zero** signals for the
44 stale ones, and then tracked a live session. TCC does not interfere.
`docs/DISCOVERY.md` §6 updated.

**The corrected classifier was replayed over 14 real transcripts** (0.01–86 MB):
12 of 14 end in a metadata record, so `docs/03`'s "classify the tail record"
yields no signal for 12 of them, while the reverse-scan rule from
`docs/DISCOVERY.md` §2.1 correctly returns `.idle` for all 14.

**M2 exit criterion met on the real machine.** With default settings and zero
configuration, Belay detected a live Claude Code session and held:

```
Details: An agent is working in Belay
```

A second, unrelated live session in another project appeared as
`2 agent sessions are working`, then resolved to just that project when this one
went quiet — aggregation across sessions (PRD R3) working unprompted.

New end-to-end suite `BelayIntegrationTests` runs the full pipeline (real file →
provider → bus → coordinator → mock power backend) and asserts the hold/release
timeline `docs/08` §3 asks for, including the metadata-tail case, work resuming
inside the grace period, and stale transcripts at startup.

### QA tooling and measured results

`scripts/perf-soak.sh`, `scripts/leak-check.sh` and `scripts/verify-release.sh`
exist and have been run.

```
CPU active avg        0.072%      budget < 1.0%    PASS
phys_footprint peak   15.50 MB    budget < 40 MB   PASS   (M2 build)
phys_footprint        23 MB       budget < 40 MB   PASS   (v1.0, all providers)
One assertion at a time            invariant 1     PASS
Every assertion carries a timeout   invariant 2    PASS  (0 of 12 samples lacked one)
ASan                  clean, 118 test results, no reports
TSan                  clean, 118 test results, no reports
```

Two budgets remain **unmeasured**, and are not passes:

- **Idle CPU (< 0.1%).** Every sample interval was "active" because real Claude
  Code sessions were running throughout. Needs a quiet machine.
- **Wakeups/s (< 3).** `powermetrics` is root-only here and there is no
  passwordless sudo, so the script skips it rather than inventing a number.
  Closed by `sudo scripts/perf-soak.sh`.

Honest caveat carried in the script's own output: Apple's ASan on Darwin ships
without LeakSanitizer, so a clean address run proves no use-after-free or
overflow — **not** no leaks. That is why the thread sanitizer is wired up too;
in a codebase this concurrent a data race is the likelier defect.

A useful measurement note: CPU is gated on CPU-seconds consumed over wall time,
not `ps -o %cpu=`, which is a decayed average and read 0.017% where the honest
figure was 0.072%.

### D12 — A test that only failed on fast machines

`FileEventStreamTests.deliversFileEvents` waited on an event *count* and then
asserted on event *contents*. Creating the scratch directory is itself a
filesystem event, and FSEvents delivers it for the watched root ~11 ms after the
stream starts despite `kFSEventStreamEventIdSinceNow` — so `count >= 1` was
already satisfied before the test wrote anything, and the assertion then raced
the real event by ~9 ms.

It failed 10 of 10 isolated runs on this machine and passed under the
sanitizers, which are slow enough that the event lands first. That is the worst
failure shape a test can have: green in CI, red on a fast laptop, or the
reverse. The wait now blocks on the specific filename. Verified 10 of 10 green.

### M3 — done

`BelayHookBridge` (loopback receiver, token auth, safe `settings.json`
installer) is built and wired through `ProviderHost`. The Providers settings
pane carries the diff-preview consent flow. 139 module tests + 22 app tests.

Verified against the running app, driving real HTTP hook events:

```
bridge.json            -rw-------  (0600), 256-bit hex token
socket                 TCP 127.0.0.1:58801 (LISTEN)   never *:58801
wrong bearer token     401, body never parsed
valid token            204
session lifecycle      2 real sessions -> 5 with 3 hook sessions -> 2 after SessionEnd
prompt privacy         a distinctive secret sent in the `prompt` field appears
                       in neither bridge.json nor any Belay log
~/.claude/settings.json  mtime still Jul 8 13:09 — untouched throughout
```

**Nothing is installed without consent.** Starting the receiver writes no hooks;
the listener is inert on its own. `HookPreviewSheet` shows the exact JSON that
would be written, and is the consent `docs/00-INVARIANTS.md` invariant 6 requires. Self-heal
(repointing a changed port) is the one write with no button behind it, and it is
deliberately narrow: it runs only when the user has already consented to an
installation and can only rewrite entries Belay owns.

The installer's marker is a query item in Belay's own hook URL
(`/hook?src=belay`) rather than an extra JSON key — an unrecognised key inside a
hook object is a way to break the user's agent for our own bookkeeping, which is
precisely risk R2. A string also survives `JSONSerialization` unchanged, where a
boolean marker returns as an `NSNumber` and can stop comparing equal, making
uninstall miss entries it owns.

### D13 — `ProviderHost` split out of `BelayController`

The controller crossed the 250-line rule after Tier B landed, which `docs/07`
treats as the signal that a file is doing two jobs — and it was: "where do
signals come from" and "what happens to them". `ProviderHost` owns the bus and
the providers; the controller owns the coordinator, power and UI wiring. Adding
a provider now touches one app-layer file.

### D11 — `CoordinatorDriver` needs an explicit nudge

Found by the integration suite. The driver naps until the coordinator's
`nextDeadline`, capped at 60 s. It computed that deadline *before* the newest
signal existed and had no way to be woken, so a release could land up to 60 s
late. Stacked on 45 s of idle inference plus a 90 s grace, that breaks the PRD
success criterion "within 2 minutes of the run finishing, `pmset` shows no Belay
assertion" (45 + 90 + 60 = 195 s).

`CoordinatorDriver.nudge()` now cancels the in-flight sleep so the loop
recomputes; `BelayController` calls it after every ingest, policy change and
power change. The metadata-tail test went from never releasing inside 12 s to
releasing in 1.5 s.

---

## Decisions

### D1 — One SwiftPM package, six targets, instead of six packages
`docs/02` lays out `Packages/BelayCore/`, `Packages/BelayPower/`, … as separate
packages. Built instead as one package `Packages/BelayKit` with one target per
module. The dependency rule from `docs/02` is enforced by the target graph in
`Package.swift`, which is exactly as strict as separate packages; module
boundaries and directory names are unchanged, so work still splits cleanly
along them, file-for-file. The win is one `swift test` for everything
and no cross-package resolution on every build. Reversible in an afternoon if a
module ever needs independent versioning.

### D2 — `swift test` and `xcodebuild test` are two commands, not one
XcodeGen schemes cannot reference a local SwiftPM package's test targets, so
`xcodebuild -scheme Belay test` runs only `BelayAppTests` (bundle metadata and,
later, app-level integration). The module suites — which is nearly all of the
testing — run under `swift test --package-path Packages/BelayKit`.
`scripts/test.sh` runs both plus both linters, and is what CI calls.
`docs/00-INVARIANTS.md` was updated to match.

### D3 — `BelayHelperCLI` is cut
`docs/02` and `docs/03` B2 specify a `belay-hook` command shim as the fallback
delivery path for hook events, with a 50 ms budget and an absolute "always exit
0" rule. Discovery proved `type: "http"` hooks with `"async": true` work against
a loopback listener on this machine, with `Authorization: Bearer` headers
delivered verbatim. An async HTTP hook cannot block or slow Claude Code *by
construction* — no exit code, no wait — which satisfies invariant 5 more
strongly than any amount of hardening the shim. Dropping it removes a second
executable, a Unix socket, and the project's most dangerous failure mode.
Full reasoning in `docs/DISCOVERY.md` §3.1.

### D4 — Codex ships as a generic-provider preset, not bespoke code
`~/.codex` does not exist on this machine and the `codex` binary is not
installed, so nothing about its format can be verified. `docs/09` M5 permits
skipping it with documentation. It will be a preset configuration of the generic
provider rather than speculative parsing code. Revisit on a machine that has it.

### D5 — Tier A classifies the last *conversational* record, not the last record
Discovery found that the literal tail of a transcript is a metadata record
(`last-prompt`, `mode`, `custom-title`) in 12 of 13 finished sessions, and that
records are not strictly ordered by timestamp. `docs/03`'s "classify the tail
record" would therefore misfire on most real sessions. See `docs/DISCOVERY.md`
§2.1 for the replacement rule.

### D6 — Tier C reads `~/.claude/sessions/<pid>.json`
An undocumented directory that maps pid → sessionId → cwd directly, removing any
need for `KERN_PROCARGS2` argument inspection that `docs/03` warns is restricted
under sandbox. See `docs/DISCOVERY.md` §1.1.

### D8 — An expired awaiting-user budget releases directly, it does not cool down
`docs/02`'s state diagram routes `AwaitingUser --budget expires--> CoolingDown`.
PRD R7 describes the budget as a bounded window after which Belay gives up, and
stacking a further 90 s grace on top of a 15-minute wait contradicts that. The
budget now releases directly. Relatedly, an `awaitingUser` session deliberately
does **not** refresh the grace timer: letting it do so made the length of the
tail depend on how often the driver happened to tick, which is not something a
user-visible behaviour may depend on.

### D9 — Awaiting sessions get a bounded TTL exemption
Found by the test suite, and it would have shipped as a silent broken promise.
The default `sessionTTL` is 10 min and the default `awaitingUserBudget` is
15 min. A session waiting on the user emits no signals by definition, so the
plain TTL evicted it at 10 minutes and PRD R7's 15-minute window could never
actually be reached. Sessions in `awaitingUser` are now evicted at
`max(sessionTTL, awaitingUserBudget)` instead.

This is a deliberate deviation from the literal wording of `docs/00-INVARIANTS.md`
invariant 3 ("a session with no signal for `sessionTTL` is treated as dead
regardless of what the last signal said"). The exemption is bounded by the
budget, so no session can outlive `max(sessionTTL, awaitingUserBudget)` and the
invariant's actual purpose — nothing stale may pin the Mac awake — is preserved.

### D10 — The hold reason is sticky through the grace period
`HoldReason` describes why the assertion is held and survives unchanged through
cooling-down; `BelayState` carries the change the UI renders. Swapping the reason
to "cooling down" the moment a turn ended re-emitted a decision on every pause
between two tool calls, which is exactly the churn `docs/08`'s flapping test
forbids. With this split, 50 working/idle flaps in 10 s produce exactly one hold
and one release.

### D7 — Bundle identifier `com.perfecto-web.belay`
Derived from the user's domain. Defined once in `project.yml`
(`ORG_IDENTIFIER`) and `Sources/BelayApp/Branding.swift`, per `docs/NAMING.md`.
The App Store name-conflict search is still outstanding — due before M6.

---

## Deliberately deferred to v1.1+

Per `docs/09`, not being built: per-session opt-out · menu bar elapsed-time text
· session history and stats · Shortcuts/AppleScript · a `belay` CLI · Focus mode
integration · Russian localisation · remote/SSH session detection.

### M4 and M5 — done

**M4:** Settings window (General, Providers, Behaviour, Notifications, About),
one-screen onboarding with the privacy statement, notifications for
needs-input / task-finished / safety-release, and launch at login via
`SMAppService`. Onboarding verified on a clean install: shown once, dismissed,
absent on the next launch, no assertion leaked.

**M5:** `GenericProvider` covers folder watching, process presence and the local
webhook, with Aider / Gemini CLI / Cline / Codex CLI shipping as presets — data,
not code. Wired into `ProviderHost`, configurable in Settings, persisted through
`GenericTargetStore`.

The webhook one-liner from `docs/03` works against the running app:

```
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:$PORT/hook?provider=generic&session=my-tool&state=working"

before          2 agent sessions are working
after working   3 agent sessions are working
after ended     2 agent sessions are working
```

The `state=` vocabulary moved into `BelayCore` (`SessionActivity(webhookState:)`)
so the receiver, the provider and the README cannot drift apart.

Two real bugs the provider's tests caught, both of which would have shipped
silently: `URL.resolvingSymlinksInPath()` returns `/var/folders/…` while FSEvents
delivers `/private/var/folders/…`, so prefix-matching the two forms matched
nothing and every `/tmp` or `/etc` watch would have been dead with no error
anywhere; and FSEvents reports the watched root's own creation, which made a
folder nobody touched emit `.working`.

175 module tests + 22 app tests, lint clean.

### M6 and M7 — done

**M6:** `Belay` and `Belay-MAS` are one XcodeGen target template instantiated
twice — no forked source, five attributes differ. Both build. `BelayTipJar`
carries `TipJarProviding` (link-based and StoreKit implementations) and
`UpdateChannel`. Release, notarize, sign-update and MAS-audit scripts are
written; none were run, as intended — there is no developer account here (B1).
CI workflow written, not run, not committed.

Verified:

```
xcodebuild -scheme Belay                    BUILD SUCCEEDED
xcodebuild -scheme Belay-MAS                BUILD SUCCEEDED
MAS entitlements  app-sandbox, files.user-selected.read-write,
                  files.bookmarks.app-scope, network.server
                  and NO network.client
MAS Sparkle scan  no framework, no load command, no symbols, no SUFeedURL
direct build      adhoc+runtime, runs, quits clean, no assertion left held
```

**M7:** `scripts/verify-release.sh` is the ship gate and now also audits the App
Store build. Full run: every automated check passes; 31 manual checklist items
are reported as **TODO**, never as passes.

### D15 — Compile conditions do not reach a local SwiftPM target

`docs/06` assumes a `#if BELAY_MAS` split. Probed with a `#warning` under
Xcode 26.6: `SWIFT_ACTIVE_COMPILATION_CONDITIONS` set on an app target **does not
propagate into a local SwiftPM target**. `#if BELAY_MAS` inside `BelayKit` is
therefore false in every build, including the App Store one — `StoreKitTipJar`
behind that gate would have been dead code everywhere and untestable, the exact
opposite of the safety property the split exists to provide.

The channel is instead resolved at runtime from an `Info.plist` key each target
sets, in one place (`TipJar.forCurrentChannel`). An unlabelled bundle resolves to
`.appStore`, deliberately: guessing wrong that way hides a tip button, while
guessing wrong the other way puts a payment link in a sandboxed App Store build,
which is a guideline violation. `#if BELAY_MAS` in the *app* target still works
and is used there.

### D14 — `docs/02`'s "one file to add a provider" claim does not hold

`docs/02` says: *"If adding a provider requires touching more than two files
outside its own folder, the abstraction is wrong — fix the abstraction."* The
generic provider was the first real test of that, and the honest answer is that
it held for a **fixed** provider and failed for a **configurable** one. Adding it
touched four files outside `BelayProviders/`:

1. `ProviderHost.swift` — construct, attach, start/stop, statuses. Expected.
2. `Settings/ProvidersSettingsPane.swift` — `ProviderDescriptor` carries name,
   summary, symbol and `supportsPreciseDetection`, and has nowhere to say
   "this provider has an editor, here are its fields, here are its presets".
3. `GenericTargetStore.swift` — nothing owned "where a provider's user
   configuration lives". `BelaySettings` models Belay's *policy*, not a
   provider's config, so this went in the app layer.
4. `BelayHookBridge/GenericWebhook.swift` — the receiver hardcoded
   `provider: .claudeCode`, so routing a generic webhook needed a change there.

The abstraction is right for providers that are pure code. The gap is that
`ProviderDescriptor` describes a provider but not its *configuration surface*.
The fix, if a future provider makes it worth doing, is an optional
configuration-metadata member on `ProviderDescriptor` (fields, presets, and a
`Codable` blob the settings store persists without inspecting). Not done for
v1.0: one configurable provider does not justify the machinery, and inventing it
now would be speculation of exactly the kind `docs/07` warns against.

Recorded rather than worked around, because a claim in an architecture doc that
is quietly false is worse than one that is openly qualified.

## Spec-versus-code audit

The documentation pass re-read the original specs against the finished code and
found nine places where they had drifted. All are now fixed; recorded here
because "the docs were updated" is worth being specific about.

Corrected in the specs, which are required to match what was built:

- `docs/02` still showed six packages and a `BelayHelperCLI` target (D1, D3), an
  `ActivityProvider` protocol that no longer matched the real one, a
  `ProviderRegistry` that does not exist, and the old
  `AwaitingUser → CoolingDown` edge (D8).
- `docs/03` Tier C specified `sysctl(KERN_PROC_UID)` enumeration; the code reads
  `~/.claude/sessions/<pid>.json` and calls `kill(pid, 0)`.
- `docs/06`'s `FileAccessProvider` sketch had a `requestAccess` method the real
  protocol never had.
- `docs/07` said each module has a README "at its package root"; with one package
  root for all modules they live beside the sources instead.

Corrected in my own files, which had the same problem:

- `docs/DISCOVERY.md` §1.1 claimed "we still enumerate pids via `sysctl`". The
  code does not. (`sysctl` does appear in `ProcessRoster`, serving the generic
  provider's watch-a-process-name option — a different job.)
- This file claimed Russian localisation was deferred but "the string catalog is
  ready for it". There is no string catalog. Claim removed; see the open item
  below.
- `docs/QA-CHECKLIST.md` said the Settings window has four panes. It has five.
- `BelayCore/ActivitySignal.swift` referenced `SessionState.apply`; the method is
  `record`. Exactly the broken DocC reference `docs/07` wants CI to catch.

### D19 — Six languages, and why switching one needs a relaunch

`AppleLanguages` in the app's own defaults domain is the preference. There is no
second stored setting, because `Bundle.main` reads that key when it picks a
`.lproj` at launch and would win over anything else we kept.

That forces a relaunch. SwiftUI alone could be pushed to re-read with a locale
override, but the status-item menu, the quit confirmation and every `NSAlert`
are AppKit and would keep the old language. Half-translated is worse than asking
the user to reopen, and System Settings' own per-app language control asks for
exactly the same thing. The relaunch spawns a detached `sh` that waits for this
pid to disappear before `open`ing the bundle, because `SingleInstance` refuses a
second copy — launching first would make the replacement defer to the copy on
its way out and the app would just vanish.

**Keys come from the compiler, not from a script.** A regex over the source got
the multi-line strings wrong by a few spaces, and a key that differs by a space
silently falls back to English — the failure is invisible in testing. The
catalogue is generated from the `.stringsdata` the Swift compiler emits under
`SWIFT_EMIT_LOC_STRINGS`, so every key is exactly what the runtime will look up.

Ten strings were found to be permanently English on the way: `Text(String)` is
verbatim, so `Promise.title`, the checkbox `spokenLabel`s and the panel's
disclosure titles looked localised and were not. They are now
`LocalizedStringResource`, which is `Sendable` where `LocalizedStringKey` is not
and so can live in a static table.

**No translation has had a native review.** All six were written with care, but
"written carefully by one person" is not review; the copy in this app is voicier
than typical UI text and that is exactly where a non-native translation slips.
`LocalizationTests` guards the mechanical half — every offered language present
in the bundle, no empty or wholesale-English tables, and format specifiers
matching the source, since a `%@` where the source has `%lld` reads a pointer as
an integer.

### D21 — The mode picker is a menu, and the panel resizes itself

`[Auto][Always on][Off]` gave three equal segments to three unequal choices.
Auto is what the app is for; Always on is a decision made for one evening; Off
is almost never. Equal weight is a claim, and it was the wrong one — and it cost
a full row of a panel that is only ever glanced at. Replaced with a small menu
on the headline's own line, the way Control Centre offers a Focus, each item
carrying one line of explanation because the three names do not explain
themselves. The old control is kept verbatim in `docs/design/` so going back is
one `cp`.

Two defects were found on the way and both were structural:

- **The panel judder.** SwiftUI animated the content's height while `NSPopover`
  resized the window to follow it, one frame behind, so the header jumped when a
  disclosure opened *below* it. `sizingOptions` is now empty: the content lays
  out at its final size and the window is what animates. Nothing above a
  disclosure can move, by construction rather than by tuning. The popover has to
  be seeded from `fittingSize`, or it opens at zero height — there is a test.
- **Auto and Always on looked identical.** `PanelStatus.look` collapsed
  `.working`, `.alwaysOn` and `.coolingDown` onto one mark, and `setMode` never
  refreshed the snapshot, so switching mode moved the picker and nothing else —
  the sentence still described the mode you had just left. A test now asserts
  the panel and the menu bar derive the same mark for the same state.

### D22 — A preset watches one place, so it can only be added once

Adding Cline twice does not watch Cline twice; it watches the same folder twice
and shows two identical tiles. Exhausted presets are disabled in the menu *and*
refused by `add`, because a disabled menu item is an affordance and this is a
rule. Presets that ask for a folder are the exception — Aider in two checkouts
is two real targets — so those are exhausted per folder, not outright.

The tiles moved out of the `SettingRow` control column and across the pane,
which fits three instead of two and lets each one be smaller. The Settings
window now grows to its content up to the screen height rather than scrolling at
640: a preferences pane that starts scrolling because you added a third tool
reads as running out of room, and the window has plenty.

### D27 — Three of the four macOS 15 findings were not what they looked like

The first clean-machine run reported a power failure, two interface faults, and
a permission loop. Only one of the four was the thing it appeared to be.

**`alwaysOn` held no assertion. It was the QA script.** A sandboxed build keeps
its preferences in its container; the script wrote `~/Library/Preferences`, so
the app launched on defaults having never seen the mode, and held nothing in
every mode including the two where holding nothing is correct. Reading the file
back afterwards confirmed only what the script itself had written. It now picks
the path out of the app's entitlements, and the app logs the mode it actually
read at launch, which settles the question without anyone knowing any of the
above. The power layer was never involved.

**The power log looked silent.** Every hold and release is logged at info level
and `log show` drops that level unless asked. One flag.

**The gear went missing at random.** Its two states were a `Color` and
`.secondary` behind `AnyShapeStyle` — different types, nothing between them to
interpolate — and a spring driving that leaves the symbol undrawn for the length
of the animation. This is the second time that exact pairing has produced a
visual fault in this app; the first was the tab hover flicker. One colour at two
opacities, and the spring drives only the rotation now.

**The title flew off centre.** The titlebar centres its label in its own layout
pass, the title was set before the frame changed, and macOS 15 does not reliably
run that pass afterwards, so the label kept the centre it was measured against.
Title last, then ask for the pass by name.

**The panel was clipped, and that was a third fault, not a symptom of the
other two.** The popover measured its own content through a preference and the
controller pushed the result in, which was written to stop the panel juddering
while a disclosure opened. On 15.0 the seed and the measurement never agreed
and the panel opened shorter than its contents, cutting the first line off
above the top edge and the footer below the bottom one. `sizingOptions` is
`.preferredContentSize` now, the path AppKit documents; the judder keeps its own
guard in the scan that fails if anything in the panel folder animates a layout.

Confirmed on the VM on 2026-08-12: panel, gear and window title all correct on
macOS 15.0. The notification icon is the one finding still open.

### D26 — Of the three recorded defects, one was a bug and two are trades

Recorded together after the concurrency pass; they are not the same kind of
thing, and treating them as one list was the mistake.

**Fixed (2026-08-12): Tier C fought the idle sweep.** Tier C reported `.working`
from a freshly started child without moving anything the idle sweep measures,
so five seconds later the sweep put the session back to `.idle`, and Tier C
revived it ten seconds after that. A session held alive by a long tool call
flipped working, idle, working for the whole call, and the panel flickered with
it. `TranscriptWatch` now carries `lastBusyChildAt` beside `lastWriteAt` —
different evidence, kept apart, because a running tool writes nothing — and the
sweep measures from the later of the two. The test for it is red without the
fix; that was checked rather than assumed.

**Not fixed, and deliberately not before a release: only direct children count.**
An agent that runs a tool through a wrapper shell older than the horizon has a
genuinely new grandchild that `AgentChildren.busy` does not see, so the tool
call does not register. Walking the parent chain is easy. What it changes is the
trade the age bound exists to make: today a long-lived direct child stops
counting once it ages out, and with ancestors it is any descendant, so a dev
server that respawns a worker every few seconds would read as continuous work
and pin the Mac awake next to an idle agent. That is the failure the bound was
written to prevent, reached one level down. Sleeping mid-tool-call is the worse
failure and the case for fixing it is real, but it is a behaviour change with a
new failure mode attached, and slipping one of those in under a release is how
the release goes wrong. Decide it deliberately, afterwards.

**Not fixed, and probably not a defect: `shutdown()`'s one-second budget.** A
release issued while a create is wedged in IOKit now waits for that create, so
the budget can expire slightly more often. What happens when it does is that the
app exits without a clean release — and the kernel then drops the assertion
anyway, which is exactly what was watched happening under SIGKILL on
2026-08-12. The budget exists so quitting is never slow; the correctness does
not depend on it.

### D23 — BelayKit localises against the app bundle, and a gate checks it

The panel's setup warning showed in English inside a Russian window because
`GenericProvider` returned a plain Swift `String`. Every user-facing string in
the package had the same problem: provider names and summaries, and all twenty
error descriptions. The fix is `String(localized:bundle: .main)` at each site
rather than an enum the app renders, because the package already produces prose
and moving twenty error sentences into the app layer would be a bigger lie about
where they live.

The reason it went unnoticed for so long is that package targets are not
extracted, so a catalogue with no entry for a key falls back to English in every
language, silently. `swift scripts/strings.swift check` now reads both the keys
the compiler extracted from the app target and the ones only visible in the
package sources, and fails if either is missing. It runs in `scripts/test.sh`.

The same script round-trips the catalogue through one CSV per language, so text
can be rewritten in a spreadsheet. Rewriting English renames the key — a key in
this catalogue *is* its English text — so import rewrites the catalogue, every
other language, and the Swift sources together. See `Localization/README.md`.

### D24 — The Settings switcher is drawn, because AppKit's cannot move

It was an `NSToolbar` in `.preference` style, which looked and behaved right but
draws its own selection: the highlight cut from one item to the next and there
is no supported way in. It is now a SwiftUI strip in a titlebar accessory, which
keeps the preferences shape — title above, separator below, no overflow chevron,
nothing that can resize the window from underneath — while leaving the highlight
ours.

The highlight's two edges do not travel together: the edge in front sets off
first and the one behind follows 70 ms later, so the pill stretches as it leaves
and gathers itself as it lands. With both edges on one animation it is a
rectangle sliding, which is what every segmented control already does.

### D25 — Sounds are generated by a script, and gated three ways

`scripts/make-sounds.swift` writes the five `.wav` files from sine partials
under an exponential decay. Synthesised rather than recorded for the same reason
the wordmark is outlined: they are a function of a file that can be read and
adjusted, and nothing in the repository is a binary nobody can reproduce.

Three gates before anything plays, in order of authority: macOS's own "play user
interface sound effects" preference, Belay's switch, then whether the file is
there. `NSSound` does not apply the first for us, so ignoring it would be a
choice rather than an oversight.

Every way this breaks is silent — a file left out of the bundle, a case renamed
without its file, two modes sharing a note — so `FeedbackTests` covers all
three.

### D20 — The login item toggle was bound to a question macOS answers late

"Open at login" switched on but not off. The binding's getter asked
`SMAppService.mainApp.status` on every redraw; `unregister()` returns
immediately but the status is served by `backgroundtaskmanagementd`, which still
said `.enabled` when the very next redraw asked. The tick went back on, with no
error, and the user was left clicking a control that undid itself.

`LoginItem` now treats the call as the source of truth for what the app just
did, and re-reads the service only on window-key — the moment the user could be
returning from System Settings having revoked it. A throw snaps the state back
to what macOS really thinks, because a control that claims a success it did not
have is worse than one that refuses.

There is no admin prompt anywhere in this: `SMAppService` is per-user. When
macOS says no, or reports `.requiresApproval`, all an app can do is say so and
open the right page — so it does, with a button rather than an instruction.

### D18 — Vendor logos, reversing D-nothing: the drawn marks were the wrong call

`ProviderMark` shipped invented shapes with a comment justifying them: real logos
were "a trademark question nobody needs" and would not sit together as a family.
That reasoning traded the column's only job — telling you *which* tool is
working — for a risk that nominative use does not actually carry. The user
supplied clean single-path SVGs and asked for 1:1 fidelity, which is the right
answer.

Shipped as **asset-catalogue imagesets with `preserves-vector-representation`
and `template-rendering-intent: template`**, not through the app's own SVG
parser. `actool` keeps the vector data, so the artwork is the original at any
size and no hand-ported path can drift from it; template mode means the row
recolours them (primary when live, secondary when not) with no per-logo work.
Verified in the built `Assets.car`: five Vector renditions plus template rasters.

- Logos are matched **by asset name from the preset id** (`logo-<id>`), so adding
  one is adding an imageset with no code change. A preset with no artwork keeps
  its drawn mark rather than getting a wrong logo or a blank.
- Generic sessions now carry their preset id in `ActivitySignal.kind`, so
  "Other agents" watching Gemini shows Gemini's mark. Webhook callers get the
  same for free: `?session=gemini` names the preset.
- Non-square artwork is aspect-fitted into the square box, never stretched.
  Cline's mark is 116×120 and a squashed trademark is worse than none.
- `logo-chatgpt` is bundled but unused: no preset targets ChatGPT today. It will
  light up the moment one is added.
- Attribution lives in three places, because a NOTICE file alone is not read by
  anyone installing an app: `NOTICE.md`, the README licence section, and a line
  in the About pane.
- Tested by name and by rendering. The failure mode is silent — a renamed
  imageset makes `NSImage(named:)` return nil, the drawn fallback appears, and
  everything still "works".

### D17 — Subagents are sessions in the model, children in the panel

A workflow of 54 agents on the user's machine produced 54 top-level rows in the
Active Sessions list, all called "9d2", with the session that started them
pushed off the end of a five-row list. Two separate defects (docs/DISCOVERY §1.2):
the workspace name was taken from the transcript's containing folder, which for
an agent is the workflow run folder, not the project; and nothing linked an
agent to the session that spawned it.

**Decided:** a subagent stays a full session everywhere below the UI. It works,
goes quiet and dies on its own schedule, and — the point of the whole app — its
work is exactly as good a reason to hold the Mac awake as a session's. Adding a
"parent" concept to the coordinator would have meant a policy that treats them
differently, which is the opposite of what is wanted. `ActivitySignal` and
`SessionState` carry `parent` as **presentation metadata only**; the policy layer
does not read it.

Consequences worth knowing:

- The panel's session rows show the **rollup** state (`max(self, children)`).
  A session whose own transcript is quiet while its agents run is not "Idle" —
  and it is their work holding the assertion, so a row saying otherwise
  contradicts the header directly above it.
- Nesting is **one level**. An agent that spawns agents lands under the session
  the user started, because that is the thing they recognise. Depth is capped at
  8 hops so a malformed cycle cannot hang the main thread.
- An orphaned agent — parent evicted by TTL while it is still running — stays at
  the top level rather than disappearing. Losing the grouping is cosmetic;
  losing a row that is holding the Mac awake is not.
- `agentType` is read from the `.meta.json` sidecar; the `description` beside it
  is **not**. It summarises the user's prompt, and the panel is on screen during
  screen shares. If it is ever wanted, it belongs behind an explicit setting.
- The list caps at five sessions and "+N more" is now a **button** that opens a
  scroller, and each session discloses its agents into a scroller of their own.
  Hiding work Belay is awake for, with no way to reach it, was the wrong trade.
  A test measures the whole panel at 50 sessions and fails if it would run off a
  13-inch screen.

### D16 — Three bugs found by using the app, and Demo mode removed

Building it and running it are not the same thing. Three defects survived every
green test run and appeared within a minute of a person actually using the app:

1. **The menu bar icon vanished in Off mode.** The Off state asked for the SF
   Symbol `moon.slash`, which does not exist on macOS 26.
   `NSImage(systemSymbolName:)` returned nil, the button got no image, and the
   status item disappeared — the app was running and completely invisible, with
   no error anywhere. Symbols are now **drawn**, not looked up (`BelayGlyph`), so
   the failure mode is structurally impossible, and a test renders every state
   and fails if any of them draws nothing.
2. **The Settings button did nothing.** SwiftUI's `Settings` scene never produced
   a window in this `LSUIElement` app — Cmd+, was inert too, so it was not the
   button. `SettingsWindow` now owns a real `NSWindow`, the same pattern
   `OnboardingWindow` already used, with tests.
3. **Demo mode was reachable by accident.** It was an alternate menu item behind
   Option, and a stray modifier turned it on; a fake "demo-project" session then
   appeared alongside real ones, which is exactly the wrong thing for a tool
   whose only job is to report the truth about what is running.

4. **The Settings window opened empty.** Fixing "it opens" was not fixing "it
   works": the window came up 40 pt tall, so SwiftUI folded the tab bar into a
   "more toolbar items" chevron and no pane was visible. Sizing it exposed a
   second problem — on macOS 26 a `TabView`'s tabs are rendered into the window
   toolbar and collapse whenever SwiftUI decides they do not fit, and
   `NSHostingController` overrode the window width that was set on it, so the
   chevron survived every width tried. The pane switcher is now a segmented
   `Picker`, which cannot collapse. Verified by clicking each of the five tabs
   in the running app and reading the rendered content back.

   Two process mistakes were mine and worth recording. The first assertion that
   Settings worked rested on a test proving only that *a window existed*. The
   second round of measurements was taken from a stale process: `pkill -f
   'Belay.app/…'` does not match `Belay-signed.app/…`, two builds were running
   at once, and the accessibility queries answered from the old one. There is now
   a single bundle at `build/Belay.app`.

Demo mode is **removed**, not fixed. `docs/06` wanted it for App Review, but a
reviewer-facing feature that can inject fake sessions into a real user's panel is
a bad trade, and the App Store build is not the channel shipping first anyway. If
review needs it later, it should be a build-time flag in a separate scheme, never
a menu item a user can hit.

## Planned: the GitHub star ask

Requested 2026-08-10. Two placements, one shared rule set.

**Where**
1. A modal (sheet, not a window) with the ask and a direct link to the repo.
2. A permanent, quiet line in About — no timing rules there, it is only visible
   to someone who went looking.

**When it may appear** — the constraint is the feature. A utility that begs is a
utility people uninstall, and this one's whole pitch is that it stays out of the
way.

- Never on first launch, and never before Belay has demonstrably done its job:
  gate on real use, e.g. the assertion has been held for a few hours in total or
  a handful of sessions have been detected. Asking before the user has seen the
  value is asking a stranger for a favour.
- Never while an agent is working. It would steal focus mid-run, which is the
  exact harm this app exists to prevent.
- Once shown: **at least 30 days** before it may appear again, and at most a
  small number of times ever (two or three).
- "No thanks" means never again, permanently. Not "ask me in a month".
- If the user follows the link, never ask again — treat it as done. There is no
  way to verify a star from the app, and trying would need network access this
  app deliberately does not have.
- Escape dismisses. No default button that stars anything by accident.

**State to persist** (`BelaySettings`): `starPromptLastShown: Date?`,
`starPromptShowCount: Int`, `starPromptSilenced: Bool`.

**Testable rules**: the prompt is a pure decision from (usage totals, last shown,
count, silenced, current activity) → show/don't. That function gets the tests;
the sheet itself needs none.

## What a v1.1 should tackle

In rough order of value:

1. **Close the two unmeasured budgets** — idle CPU and wakeups/s. Both need a
   quiet machine and `sudo scripts/perf-soak.sh`; neither is a known problem,
   just unproven.
2. **Run the manual QA checklist.** 31 items are still unproven, including the
   most important one in the document: force-quit while holding, to confirm the
   assertion self-releases. The design says it must; nobody has watched it.
3. **macOS 14 and 15 verification** (B5).
4. Per-session opt-out, and the rest of the deliberately deferred list.
5. `ProviderDescriptor` configuration metadata, if a second configurable
   provider ever justifies it (D14).
6. **Get the six translations read by somebody who speaks them** (B7). The
   catalogue and the picker shipped; the words in it have never been reviewed.
   `Localization/*.csv` is the format to hand them out in.
7. **Transparent brand PNGs.** `Resources/Brand/*.png` were rasterised onto a
   plate, which is wrong anywhere the lockup is composited. The SVGs are fine.

## Open questions

- App Store name-conflict search for "Belay" (`docs/NAMING.md`) — before M6.
- macOS 14 and 15 behaviour is unverified; only 26.4 was available.
- Hook events beyond `UserPromptSubmit`/`SessionEnd` are mapped from the live
  reference but not yet observed on this machine — headless `claude -p` cannot
  authenticate here. Re-verify during the M3 manual pass.
