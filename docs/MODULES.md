# Modules

A module is something Belay can do beside keeping the Mac awake. It lives in
**Settings ▸ Modules**, it is off until somebody installs it, and it is written
by whoever needed it: three came with Belay 2.0, and the list is open to pull
requests.

This page is for the person who wants to write one, or change one. What the
existing modules do for a user is in [HOW-IT-WORKS.md](HOW-IT-WORKS.md#modules);
what they read and change is in [PRIVACY.md](PRIVACY.md).

## The modules today

| Module | What it does | App Store | Direct | macOS asks for |
| :--- | :--- | :---: | :---: | :--- |
| **Screenshot Cleaner** | Moves screenshots to the Trash once they pass the age you choose | yes | yes | the screenshots folder |
| **Warm Microphone** | Holds the microphone open so dictation hears the first word | yes | yes | the microphone |
| **Auto Allow** | Presses "Allow once" in the Claude and Codex desktop apps for requests about local sites | no | yes | Accessibility |
| **Nudge** | Plays a sound when an agent finishes, waits or goes quiet, and reminds you while one keeps waiting | yes | yes | notifications |
| **Orphan Watch** | Lists processes an agent left running after its session ended, and the ones running hot; ends them when you press End (direct build) | yes | yes | nothing |

## What a module is, and is not

**A module is code inside the app.** Installing one downloads nothing: it
records the choice and lets the module start. Three reasons, none of them
negotiable. The App Store forbids fetching executable code. A macOS permission
belongs to the signed app, not to something added to it later. And a channel
that delivers code is one more thing to defend next to a privileged helper.

So a module reaches users the way everything else does: it is merged, it ships
in the next release, and it sits switched off in Settings until somebody wants
it.

**A module is not a second app.** It fits when a person who leaves agents
running would reach for it on the same afternoon, when its card can say what it
does in one sentence, and when it does one thing. A desk that fills with
screenshots while an agent clicks through a site is that. A clipboard manager is
not.

## The rules every module keeps

These are what a review reads first. Each one exists because the opposite would
make Belay something its users did not agree to.

1. **Off until installed, and nothing before.** No timer, no question from
   macOS, no file touched until the user switches it on.
2. **One permission, asked at switch-on, for the reason on the card.** A
   refusal is a red line in the card that says what is missing. It is not asked
   again by itself.
3. **Removing a module forgets it.** Settings, folder grants, lists, counters:
   all gone, so that installing again starts from the defaults.
4. **It fails toward doing nothing.** A module that cannot do its work stops
   and says so in its card. It never retries in a loop, and it never guesses.
5. **No network.** The App Store build has no network entitlement at all, and
   the direct build uses the network for updates and for nothing else.
6. **The log can answer a bug report, and holds nothing personal.** Every
   change of state is written with its reason, as counts and codes. Never a
   path, a site, a device or session name, or a line of anybody's text.
7. **Anything it changes can be undone, and has a limit.** Screenshot Cleaner
   moves to the Trash and never deletes. Auto Allow answers local sites only by
   default and switches itself off after a set time.
8. **It says which build it runs in.** A module the sandbox forbids is not
   offered in the App Store build, rather than shown and greyed out.
9. **It stays away from sleep.** Holds, assertions and the rules in
   [00-INVARIANTS.md](00-INVARIANTS.md) belong to the core. A module neither
   takes a hold nor ends one.
10. **A module for one agent follows that agent's switch.** With the agent
    switched off in Settings ▸ Agents the module does nothing for it and says
    so in its card.
11. **Every string in seven languages**, like the rest of the interface.

## Propose it first

Open an issue with the **Module proposal** template before writing code. It
asks for the things a review would ask anyway: the one sentence, what the
module reads, what it changes, what macOS will ask the user, which builds it
can run in, and what happens when it cannot do its work. An idea that survives
those six questions is usually merged; one that does not saves you the
evening.

A fix or an improvement to a module that already exists needs no proposal.

## Where the parts live

A module has two halves, and the split is the same one the rest of Belay keeps:
what can be decided without the system goes into the package, where a test can
run it in a millisecond; what touches the system stays in the app, behind
something a test can replace.

```
Packages/BelayKit/Sources/BelayModules/     rules and decisions, no AppKit, no disk
Packages/BelayKit/Tests/BelayModulesTests/  their tests
Sources/BelayApp/Modules/                   the running half and the settings view
Tests/BelayAppTests/                        app tests, with doubles in ModuleDoubles.swift
```

Screenshot Cleaner is the one to read first. `ScreenshotRules` is what the user
chose, `ScreenshotSweep` decides which files are due and never touches a disk,
and `ScreenshotCleaner` in the app owns the timer and hands the package two
closures: list a folder, move a file to the Trash.

## Adding one, step by step

1. **The name.** One line in
   [`ModuleID.swift`](../Packages/BelayKit/Sources/BelayModules/ModuleID.swift).
   The raw value is lowercase with hyphens, and it is permanent: it is the key
   in the user's preferences and the name in the log.
2. **The rules and the decisions**, in `BelayModules`. The settings are a
   `Codable` struct that loads with defaults for anything missing, so a field
   added later does not reset what somebody already chose. The decisions are
   pure functions with the clock handed in.
3. **The running half**, in `Sources/BelayApp/Modules/`: a `@MainActor
   @Observable final class` with four entry points.

   | Method | Called when | What belongs there |
   | :--- | :--- | :--- |
   | `start()` | Belay launches and the module was left on | carry on quietly, ask nothing |
   | `activate()` | the user switches it on | ask macOS, start the clock, then `start()` |
   | `stop()` | switched off, or Belay quits | let go of everything it holds |
   | `forgetEverything()` | the module is removed | `stop()`, then erase settings and grants |

   Whatever reaches into the system (a folder, the microphone, another app's
   window) sits behind a protocol or a pair of closures, so the class can be
   tested with a double.
4. **The host.** In
   [`ModuleHost.swift`](../Sources/BelayApp/Modules/ModuleHost.swift): a
   property, a line in `stop()`, and one case in each of `run`, `activate`,
   `halt` and `remove`.
5. **The card.** A descriptor in
   [`ModuleDescriptor.swift`](../Sources/BelayApp/Modules/ModuleDescriptor.swift)
   with an SF Symbol, a tint of its own, a title, a summary short enough for
   one line in every language and the builds it runs in, added to `all`. The list, the search and the Installed filter read that
   array; there is no view to touch for them.
6. **The settings.** A `<Name>Settings` view, one case in
   [`ModuleCard.swift`](../Sources/BelayApp/Modules/ModuleCard.swift) and one in
   [`ModuleStatusLine.swift`](../Sources/BelayApp/Modules/ModuleStatusLine.swift),
   which is the line the card shows while it is closed.
7. **The strings.** Every new one in all seven languages in
   `Resources/Localizable.xcstrings`, then `swift scripts/strings.swift export`.
   Simplified Chinese follows
   [`Localization/zh-Hans-glossary.md`](../Localization/zh-Hans-glossary.md).
   How to translate is in
   [CONTRIBUTING.md](CONTRIBUTING.md#fixing-or-adding-a-translation); a machine
   translation marked as such in the pull request is better than a missing one.
8. **What macOS asks.** A usage description goes into `project.yml` and
   `Resources/InfoPlist.xcstrings`, in seven languages. An entitlement goes
   into the file of each build that needs it under `Resources/Entitlements/`,
   and the App Store one is added to the required list in
   `scripts/verify-mas-build.sh`, so a build that lost it fails.
9. **The paper.** A paragraph in [HOW-IT-WORKS.md](HOW-IT-WORKS.md#modules),
   what it reads and what it changes in [PRIVACY.md](PRIVACY.md), the hand
   checks in [QA-CHECKLIST.md](QA-CHECKLIST.md), a `CHANGELOG.md` entry, and a
   row in the table at the top of this page.

Then `scripts/test.sh`. It checks more of the above than it looks: a string
missing from one language fails it, and so does a string the code asks for that
the catalogue has never heard of.

## What the tests have to show

- The decisions, exhaustively, in the package: every rule the user can set,
  both sides of every threshold, and the defaults.
- The lifecycle, in the app, with a double: nothing happens before
  `activate()`, `stop()` lets go, `forgetEverything()` leaves no key behind,
  and a module left on comes back after a relaunch without asking again.
- The refusal: with the permission denied the module does nothing and says so.
- The card, by eye: `ModulesPaneFramesTests` draws the pane to image files when
  `TEST_RUNNER_BELAY_FRAMES` names a folder. Attach the light and the dark one
  to the pull request.

What no test can show goes into the pull request in words: which Mac, which
macOS, what you switched on and what you saw. A module that touches another
app, like Auto Allow, also says which version of that app it was run against.

## What the log says

A module cannot be watched from outside, so its log is what a bug report
stands on. Belay writes it only while **Settings ▸ General ▸ Keep crash reports
on this Mac** is on; "Show Reports" opens the file. A line is a subject, a verb
and `key=value` pairs, written when something changes and not on every tick.

| Line | When |
| :--- | :--- |
| `modules start installed=… on=…` | at launch |
| `module install`, `remove`, `on`, `off` with `id=…` | the user did that |
| `screenshots start age=… folders=… keepsTouched=… recordings=… grace=…` | the cleaner started |
| `screenshots rules …` | a setting changed |
| `screenshots trashed=… failed=… unreadable=… kept=… waiting=…` with `why=…` on a failure | a pass that moved or failed something, or left a different number alone than the pass before |
| `mic state=…` | `off`, `needsPermission`, `pausedOnBattery`, `pausedForBluetooth`, `noMicrophone` or `warm` |
| `mic opened kind=…`, `mic released` | a microphone was taken (`builtIn`, `usb`, `bluetooth`, `other`) or let go |
| `autoallow start scope=… behind=… duration=… minutesLeft=…`, `autoallow rules …` | it started, a setting changed |
| `autoallow standing=…` | `off`, `agentOff`, `needsAccess` or `watching` |
| `autoallow sees claude=… windows=… page=… session=… list=…`, `autoallow sees codex=…` | what it can read of an app changed |
| `autoallow approved=… held=… failed=… beaten=… presses=… took=… scope=… app=…` with `refused=…` when the app gave an error for a press | a look that found requests, in that app |
| `autoallow behind=… app=…`, `autoallow expired` | a session behind the window was visited, the time ran out |
| `autoallow front=…` | after a visit: the app that was in front before was `restored`, was still there (`kept`), was `left` because the Mac was in use, or the system `refused` to bring it back |
| `nudge start finish=… wait=… quiet=… names=… repeatMinutes=… repeatMax=… minimumRun=…`, `nudge rules …` | it started, a setting changed |
| `nudge sees session(…) working->other top=1` | a session's activity as the nudge sees it changed; `other` is idle or gone, `top=0` is a subagent |
| `nudge said kind=…` | one per event: `finished`, `waiting`, `quiet` or `reminder`, never a workspace or a session name; `quiet` only for a session a transcript or a process had seen at work, not one heard from a hook alone |
| `orphans start spinning=… percent=… minutes=… notifies=… ignored=…`, `orphans rules …` | it started, a setting changed |
| `orphans sweep roots=… tracked=… orphans=… hot=…` | a look whose numbers differ from the look before |
| `orphans ended=… failed=…` | after End or End All: what was gone two seconds later, and what was not |
| `sound silent reason=microphone-undecided` | once a launch, when sounds are held back |

A new module writes the same kind of lines: what it is set to when it starts,
every state with its reason, and what each piece of work came to.

## Changing a module that exists

- **Somebody already has it installed.** A new option defaults to what the
  module did before. A changed default applies to new installs only.
- **The name in `ModuleID` never changes**, and neither do the preference keys
  without a migration that is tested.
- **A module that depends on another app says what happens when that app
  changes.** Auto Allow finds the request by the names Claude and Codex give
  their interfaces; when those change it finds nothing and presses nothing.
  That is the required direction of failure, and the test for it is part of
  the change. What each app calls things lives in one place per app, its
  dialect in `AppDialect.swift`; the looking and the pressing are shared.
- A change users will notice gets a line in `CHANGELOG.md` under the release it
  ships in.

## The pull request

Everything in [CONTRIBUTING.md](CONTRIBUTING.md#pull-requests) applies, and the
template has a short list for modules on top of it. By opening the pull request
you agree to the [contributor terms](CONTRIBUTING.md#contributor-terms), the
same as for any other change.
