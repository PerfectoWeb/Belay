# Contributing

Belay is a small macOS menu bar app with a strict safety story. Most of the rules
below exist because getting one of them wrong keeps somebody's Mac awake for nine
hours. Read [`docs/00-INVARIANTS.md`](00-INVARIANTS.md) for the non-negotiables and
[`docs/02-ARCHITECTURE.md`](02-ARCHITECTURE.md) for the shape; this file is
about how to build, test and style the thing.

Two contributions are wanted more than any other, and neither needs you to learn
the codebase: a **translation fix** and a **provider preset**. Both are data, not
code, and both have their own section below.

By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## What you need

- macOS 14 or later. That is the deployment target, and it is also the floor for
  the app you build.
- Xcode 16 or later with a Swift 6 toolchain. Built and verified here on
  Xcode 26.6 / Swift 6.3.3, macOS 26.4.
- `xcodegen`, `swiftlint` and `swift-format`, all from Homebrew. Verified against
  SwiftLint 0.65.0 and swift-format 603.0.0.

```bash
brew install xcodegen swiftlint swift-format
```

No Apple Developer account is needed. Every build in this repo uses ad-hoc
signing (`CODE_SIGN_IDENTITY = "-"`), which is enough to produce a runnable app.

## Build

```bash
xcodegen generate                                     # regenerate Belay.xcodeproj
xcodebuild -scheme Belay -destination 'platform=macOS' build
scripts/build-local.sh                                # ad-hoc signed .app in build/
```

**`Belay.xcodeproj` is generated and must never be hand-edited.** It is produced
by XcodeGen from [`project.yml`](../project.yml), it is not in the repository, and
an edit made in Xcode's project editor survives exactly until the next
`xcodegen generate`. Change `project.yml` instead. The bundle identifier, the
deployment target and the product name are defined there once, and in
`Sources/BelayApp/Branding.swift`, so a rename stays a two-file change.

## Test

```bash
scripts/test.sh
```

That script is the gate. If you only remember one command, remember that one. It
runs both test commands and both linters, in the order that fails fastest, and it
is exactly what CI runs. A change is not done until it prints `all green`.

Underneath, the tests run as **two** commands, on purpose:

```bash
swift test --package-path Packages/BelayKit                  # the module suites
xcodebuild -scheme Belay -destination 'platform=macOS' test   # the app target only
```

An Xcode scheme generated from a spec cannot reference a local SwiftPM package's
test targets, so `xcodebuild test` sees only `BelayAppTests`: bundle metadata,
the string catalogue check, and the handful of app-layer types worth testing.
Nearly all of the suite lives in `Packages/BelayKit/Tests` and runs under
`swift test`. Running only one of the two commands and calling it green is the
mistake this section exists to prevent. See `PROJECT_STATE.md` D2.

`BelayIntegrationTests` is the exception to the one-target-per-module rule: it
spans provider to bus to coordinator to a mock power backend, because no
single-module test target can import all four and the hold/release timeline is
only meaningful end to end.

Detection cannot be proved by unit tests alone. `scripts/fake-agent.sh` writes
plausible JSONL at a configurable rate, and
[`docs/QA-CHECKLIST.md`](QA-CHECKLIST.md) lists what still has to be checked
by hand against a real Claude Code session.

## Lint

```bash
swiftlint --strict
swift-format lint --recursive --strict Sources Packages/BelayKit/Sources Packages/BelayKit/Tests
```

Both must be clean before a change is done. `scripts/test.sh` runs them last, so
a lint failure never masks a real test failure.

## The non-negotiables

These are in [`docs/00-INVARIANTS.md`](00-INVARIANTS.md) because they are the ones a well-meaning
change breaks by accident. A pull request that touches power, detection or
`~/.claude/` will be read against this list first.

1. **At most one power assertion exists at any time, process-wide.** Not one per
   session, not one per provider. `PowerAssertionController` owns it and the UI
   never talks to IOKit.
2. **Every assertion carries a hard timeout and is refreshed while busy.** It is
   created with `IOPMAssertionCreateWithProperties`, a 120 s
   `kIOPMAssertionTimeoutKey` and `kIOPMAssertionTimeoutActionRelease`, and
   re-armed at 75% of that. This is what makes a crashed Belay harmless. Do not
   raise the timeout to avoid a refresh bug, and do not reach for `caffeinate` or
   `NSProcessInfo.beginActivity` as the mechanism.
3. **Every tracked session has a TTL.** A session with no signal for `sessionTTL`
   is dead, whatever its last signal claimed.
4. **The assertion is released** on idle transition, app termination,
   `SIGTERM`/`SIGINT`, user toggle off, battery guard trip and the maximum
   duration cap. Adding a code path that can hold means adding the release with
   it, and a test that proves the balance.
5. **A hook handler must never block or slow Claude Code down.** Hooks are
   registered `"async": true` and there is no exit code that could stall a turn.
   Keep it that way.
6. **Belay never writes to `~/.claude/` without explicit, per-action consent in
   the UI, and always makes a timestamped backup first.** If the file is not
   plain JSON it refuses to write at all and offers a snippet to paste.
7. **Nothing reads prompts, model responses or code.** The transcript reader
   decodes a record `type` and `stop_reason` and nothing else; the hook envelope
   decoder has no property for `prompt`, and a test asserts a distinctive prompt
   string reaches neither the signal nor any file Belay writes. A change that
   adds a field to either decoder needs a very good reason in the description.
8. **No API keys, ever.** Detection is local. There is no provider account to
   talk to and no endpoint that knows whether your agent is busy.
9. **No timer faster than 5 s**, and `DispatchSourceTimer` always gets generous
   leeway. The budgets are under 0.1% CPU and under 40 MB `phys_footprint` when
   idle. Measure the second one with `footprint -p <pid>`, never `ps -o rss=`,
   which counts shared framework pages and reads about five times too high.
   `scripts/perf-soak.sh` does the measuring.

## Adding a provider preset

This is the most likely first contribution and it is the easiest one, because a
preset is **data**. Claude Code and Codex are the only agents with bespoke code. Everything
else is the generic provider, which can watch a folder, require a named process
to be alive, or accept a routed local webhook, and treats any one of the three as
enough.

Adding Continue, Goose or whatever you use means one element in
`GenericPreset.all`, in
[`Packages/BelayKit/Sources/BelayProviders/GenericPreset.swift`](../Packages/BelayKit/Sources/BelayProviders/GenericPreset.swift):

```swift
GenericPreset(
    id: "gemini",
    displayName: "Gemini CLI",
    summary: "Watches ~/.gemini, where the CLI keeps its session state.",
    folder: .home(".gemini"),
    processName: "gemini"),
```

- `id` is the stable identifier. It is also the webhook identifier and the asset
  name for the logo, so keep it short and lowercase.
- `folder` is either `.home("relative/path")` when the preset can know where the
  agent writes, or `.userPicked("prompt shown in the open panel")` when it
  cannot, because the agent writes into whichever project you ran it in. Guessing
  a path you have not seen is worse than asking.
- `processName` is optional. Leave it `nil` when the process outlives the work,
  which is why the Cline preset has none: VS Code stays open long after the agent
  has stopped.
- `summary` is one or two sentences shown under the preset in Settings, in
  English. It says what is watched and what the user may need to change.

The Settings UI reads `GenericPreset.all` directly, so there is no view to touch.
`GenericPresetTests` will hold you to the rules that matter: unique ids, a target
that is actually configured, and the 45 s quiet period that
[`docs/DISCOVERY.md`](DISCOVERY.md) measured. Run `scripts/test.sh` and you
are done.

A logo is optional and separate: add a template imageset named `logo-<id>` under
`Resources/Assets.xcassets` and `ProviderMark` picks it up with no code change. A
preset with no artwork gets a drawn shape rather than a wrong logo. If you add
one, add the owner to the table in [`NOTICE.md`](../NOTICE.md) and only ship artwork
you have the right to ship.

Say in your pull request whether you actually ran the agent with the preset. "I
use this daily and the path is right" is worth more than the diff.

## Fixing or adding a translation

Belay ships in English, Russian, German, Spanish, French, Italian and Simplified
Chinese. **These have never been read by somebody who speaks them:** German,
Spanish, French, Italian and Chinese. The copy is deliberately voicier
than typical interface text, which is exactly the register a non-native
translation flattens, so a correction from someone who speaks the language is a
genuinely wanted contribution, including a one-string one.

The app reads
[`Resources/Localizable.xcstrings`](../Resources/Localizable.xcstrings), a String
Catalog with 290 keys, and that is not the file to edit. Translations are
written in [`Localization/`](../Localization/), one CSV per language, and the
catalogue is generated from them:

```bash
swift scripts/strings.swift export            # catalogue -> the CSVs
swift scripts/strings.swift import --dry-run  # check without writing
swift scripts/strings.swift import            # the CSVs -> catalogue
```

`translation` is the only column to edit, and a `status` of `needs_review` marks
a string no native speaker has read yet, which is where to start.
[`Localization/README.md`](../Localization/README.md) has the rest: every
column, the placeholder rules, how to retire a string, and why `en.csv` is the
odd one. The English text is the key, so rewriting it renames the key, and
import carries that rename through the catalogue, every other language and
the sources.

Rules that the tests enforce, in `Tests/BelayAppTests/LocalizationTests.swift`:

- Every language must have every string. A missing one falls back to English and
  looks like nothing is wrong, which is why the count is asserted.
- **Format specifiers must match the source exactly.** `%@` where the source has
  `%lld` reads a pointer as an integer, and it only breaks on a machine nobody
  testing the app is using.
- No empty values, and no language that is a wholesale copy of English.

Adding a language means the strings plus one case in `AppLanguage`
(`Sources/BelayApp/Settings/AppLanguage.swift`), whose `endonym` is written in
the language itself, because a picker that lists "German" to somebody who only
reads German is a picker they cannot use. The picker offering a language the
bundle does not have is a test failure, not a silent fallback. The full
procedure, in the order the tools require, is in
[`Localization/README.md`](../Localization/README.md#adding-a-language). The
step that is easy to miss is regenerating the project: XcodeGen writes
`knownRegions` from the catalogue, and without it the strings compile into
nothing and the app silently shows English.

Two things worth knowing before you translate: changing the language reopens the
app, because the menu bar menu and the alerts are AppKit and will not switch
under a running process; and the strings a new user meets first, the onboarding
pane, the panel status line and the About tagline, are the ones worth your
attention if you only have ten minutes.

## Modules and the dependency rule

The whole library lives in one SwiftPM package, `Packages/BelayKit`, with one
target per module. The original architecture doc describes six separate packages;
one package with six targets enforces exactly the same boundaries through the
target graph in `Package.swift`, while giving one `swift test` for everything and
no cross-package resolution on every build.

```
BelayApp ──▶ BelayCore ──────▶ BelaySupport
   │
   ├──▶ BelayPower  ─────────▶ BelaySupport
   ├──▶ BelayProviders ──────▶ BelayCore, BelaySupport
   ├──▶ BelayHookBridge ─────▶ BelayCore, BelaySupport
   └──▶ BelaySettings ───────▶ BelayCore, BelaySupport

BelayChannel ────────────────▶ BelaySupport
```

`BelayChannel` answers one question: which build is this, direct or App Store,
read from `Info.plist` rather than from a compile condition. See
[`docs/adr/004-mas-and-direct-split.md`](adr/004-mas-and-direct-split.md).

Three rules follow from that graph, and `Package.swift` will stop you if you
break them:

- **`BelayCore` knows nothing about IOKit, the filesystem, Claude Code or time of
  day.** It takes signals and a `Clock` and emits decisions. That is what lets
  the state machine simulate hours of behaviour in milliseconds with no I/O.
- **Nothing but `BelayApp` imports AppKit or SwiftUI.** Where a framework only
  speaks to AppKit, and `NSWorkspace`'s sleep notifications are the live example,
  the app layer observes and forwards a plain value inward.
- **Modules do not import each other sideways.** `BelayProviders` and
  `BelayHookBridge` both produce `ActivitySignal`s and neither knows the other
  exists; the app layer fans them together through `SignalBus`.

Adding a provider with real code, rather than a preset, should mean one new type
conforming to `ActivityProvider` plus registration in
`Sources/BelayApp/ProviderHost.swift`. If it needs more than that, the
abstraction is wrong: fix the abstraction rather than the caller.

Each module has a `README.md` next to its sources covering what it does, what it
depends on, and the decisions that would surprise a newcomer. Keep it current; it
is the first thing anyone reads.

## Style

The short version: write it like a senior macOS engineer who dislikes ceremony.
[`docs/07-ENGINEERING-STANDARDS.md`](07-ENGINEERING-STANDARDS.md) has the
argument. What follows is what the linters actually enforce, so it is what a
review will actually catch.

### Enforced by `.swiftlint.yml`

- **Line length** 110 warning, 140 error. Comments count; URLs do not.
- **File length** 250 warning, 320 error. A file past 250 lines is doing two
  jobs; that is how `ProviderHost` got split out of `BelayController`.
- **Type body** 200 / 280. **Function body** 50 / 80. **Cyclomatic complexity**
  10 / 15.
- **No force unwrapping and no implicitly unwrapped optionals.** Both are opt-in
  rules and both are on.
- **`print()` is an error.** Use `BelaySupport.Log`, which is `os.Logger` with one
  category per module.
- **No emoji anywhere in source.** Also an error.
- **No `Manager`, `Helper`, `Utils`, `Utility` or `Common`** in a type name. Name
  it after the domain concept.
- Type names are at least 3 characters, identifiers at least 2 (`id`, `up`, `on`
  and `ok` are excused), and types nest at most two deep.
- The analyzer rules `unused_import` and `unused_declaration` are configured in
  `.swiftlint.yml`, but `scripts/test.sh` runs `swiftlint --strict`, which does
  not execute them: analyzer rules need `swiftlint analyze` and a compiler log.
  So they are not a gate yet, whatever this file used to claim. Four unused
  imports and a dead 33-line view survived a green run before anyone checked.
- `todo` is deliberately disabled: work in flight is tracked in
  `PROJECT_STATE.md`, not by the linter.

### Enforced by `.swift-format`

- Four-space indentation, 110-column lines, at most one blank line in a row.
- Ordered imports, lower camel case, no semicolons, no block comments.
- `///` for documentation comments, and documentation that is validated against
  the signature it describes.
- No force `try`, no implicitly unwrapped optionals, early exits preferred, one
  case and one variable declaration per line.
- File-scoped declarations default to `private`.
- `AllPublicDeclarationsHaveDocumentation` is off on purpose. Public API that
  needs explaining gets a doc comment; a public one-liner does not need a
  ceremonial one.

### Not machine-checkable, still required

- Comments explain **why**, never what. "IOKit returns `kIOReturnNotPermitted`
  here in clamshell; treat as non-fatal" is a comment. "Create the assertion" is
  noise.
- Swift 6 language mode with complete strict concurrency. No
  `@unchecked Sendable` without a written justification in the file header.
- Every long-lived closure captures `[weak self]` unless the retain is deliberate
  and noted. Every `AsyncStream` continuation gets an `onTermination` that
  removes it: a held-forever continuation is the classic leak in this codebase.
- Every observer, FSEvents stream, `DispatchSource`, `NWListener` and IOKit
  assertion has a symmetric teardown and a test that proves it.
- One `LocalizedError` enum per module, with messages that would read sensibly in
  the UI.
- No abstraction with a single implementation unless it exists for testing or for
  the direct/App Store split. Both of those are called out in the docs; anything
  else is speculation.
- Any user-visible string is localized, and a new one means a value in every
  language rather than one.
- Never write how many languages there are. "Multilingual", or name them, but no
  count: a number is a fact stored in prose, and adding one language then means
  hunting it through the docs, the slides, the site and the source comments.

## Commits

Plain, imperative, and about the why.

```
Release the assertion when the battery guard trips mid-session

The guard was evaluated only on the poll that started a hold, so a machine
unplugged during a long run stayed awake to the 4-hour cap. Evaluate it on
every tick instead, and cover it in SafetyGateTests.
```

- Subject in the imperative, under about 72 characters, no trailing full stop.
  "Fix the leak", not "Fixed the leak" or "fixing leak".
- No prefixes, no ticket tags, no emoji, no conventional-commit ceremony.
- The body explains why the change is right. Anyone can read the diff for what.
- One logical change per commit. A refactor and a fix in one commit is two
  reviews pretending to be one.
- Do not credit tooling in the trailer. If a tool wrote it, you are still the
  author and the one who verified it.

## Pull requests

Open an issue first for anything that changes behaviour, so the design argument
happens before you have written it. A preset, a translation or an obvious bug fix
needs no issue.

In the description, say:

- What was wrong or missing, and why this is the right fix rather than a fix.
- **Which of the non-negotiables above the change could break, and what stops
  it**, if it touches detection, power or `~/.claude/settings.json`. This is the
  section that gets read closest.
- What you actually ran. `scripts/test.sh` output at minimum, plus the manual
  check if the change is one unit tests cannot prove. Detection and power changes
  come with a `pmset -g assertions` reading before and after.
- Which macOS version you are on. macOS 14 and 15 have never been exercised on
  real hardware here, so a report from one of those is useful on its own.

Then re-read the diff as if it were a colleague's. The things that come up most
often: a `Task { }` with no cancellation story, a magic number that should be a
clamped default in `BelaySettings`, a protocol with one conformer and no test,
and a comment that says what the next line already says.

Screenshots for anything visible, in light and dark appearance.

Finally: no AI provider API keys, ever, and `PROJECT_STATE.md` is updated at
every milestone.

## Contributor terms

Read this once before your first pull request. It is four sentences of substance
and it is the only paperwork here.

**You keep the copyright in what you write.** Nothing here asks you to sign it
away, and nothing here is exclusive: your contribution stays yours to use
elsewhere however you like.

**What you grant, by opening a pull request:**

> I certify that I wrote this contribution myself, or otherwise have the right to
> submit it, and that I am not knowingly including anyone else's work under terms
> that forbid it. Where my employer has rights in what I write, I have their
> permission to contribute it.
>
> I grant PerfectoWeb a perpetual, worldwide, non-exclusive, royalty-free and
> irrevocable licence to use, reproduce, modify, publish, distribute and
> sublicense my contribution, and to do so **under any licence terms**, including
> terms different from the ones this project uses today. I grant the same for any
> patent claims of mine that the contribution would otherwise infringe.

**Why this exists, plainly.** Belay is not under an OSI-approved licence: it is
source-available, and its terms forbid selling it. That is deliberate. The
licence is also something the copyright holder may need to change one day, or
grant differently to someone under a separate agreement. A project owned by one
author can do that. A project where five people each own a patch cannot, without
finding all five and getting every one of them to agree. This clause is what
keeps that door open, and it costs you nothing but the copyright you keep.

**How you agree.** Opening the pull request is the agreement, and the box in the
template is where you say so. Signing your commits off makes it a matter of
record rather than of memory:

```
git commit -s -m "Fix the leak"
```

which adds a `Signed-off-by:` line with the name and address in your git config.
