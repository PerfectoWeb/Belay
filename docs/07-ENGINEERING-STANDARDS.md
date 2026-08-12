# 07 — Engineering standards

## "Written by a senior engineer, not by a model"

This is a real requirement, so here is what it concretely means.

**Do:**
- Name things after domain concepts, not patterns. `ActivityCoordinator`, not
  `ActivityManagerService`. `hold(reason:)`, not `executeHoldOperation()`.
- Let types be small and specific. `SessionID` beats `String` everywhere.
- Use `guard` for preconditions and get to the point.
- Comment the *why*: "IOKit returns kIOReturnNotPermitted here when the machine
  is in clamshell; treat as non-fatal." Never "// create the assertion".
- Prefer deleting code to adding an option.
- Keep files under ~250 lines. If one grows past that, it's doing two jobs.

**Don't:**
- No `// MARK: - Properties` / `// MARK: - Private Methods` scaffolding on small
  types. Use MARKs only where a file genuinely has sections worth jumping between.
- No doc comment on every private one-liner. Public API gets doc comments;
  internals get them only when non-obvious.
- No defensive `if let` around things that cannot be nil. Crash on programmer
  error; recover from environmental error.
- No emoji, no decorative box-drawing banners in source.
- No `Utils`, `Helpers`, `Common`, or `Manager` as a type or file name.
- No abstraction with exactly one implementation *unless* it exists to enable
  testing or the two-channel split (both are called out explicitly in the docs —
  anything else is speculation).
- No `print`. `os.Logger` only.

## Swift specifics

- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, warnings as
  errors in CI (not in local dev builds — that's just friction).
- `public` only where a package boundary requires it; default to `internal`.
- Value types by default; reference types when identity or lifecycle matters.
- `async`/`await` throughout. `AsyncStream` for event flows. No completion
  handlers in new code; wrap C callbacks at the edge and never let them leak inward.
- Errors: one `enum` per module conforming to `LocalizedError`, with messages
  that would make sense in a UI. No `NSError`, no stringly-typed failures.
- Force-unwrap only for genuinely-impossible cases, with a comment saying why,
  or use `preconditionFailure` with a real message.

## Memory & lifecycle

- Every closure captured by a long-lived object uses `[weak self]` unless the
  retain is intentional and noted.
- Every observer, FSEvent stream, `DispatchSource`, `NWListener` and IOKit
  assertion has a symmetric teardown, and there is a test proving it.
- `deinit` on the FSEvents wrapper must stop and release the stream. Run the
  test suite under the Address Sanitizer once per milestone.
- No retain cycles between actors and their continuation handlers — a common
  trap with `AsyncStream` is holding the continuation forever. Always call
  `continuation.onTermination` and clean up.

## Documentation

- Every module has a `README.md` beside its sources
  (`Packages/BelayKit/Sources/<Module>/README.md`): what it does, what it depends
  on, the one or two decisions that would surprise a newcomer. There is one
  package root for all modules (PROJECT_STATE D1), so the READMEs live next to
  the code rather than at a package root each.
- Public API uses DocC comments. Generate DocC in CI to catch broken references.
- Architectural decisions go in `docs/adr/NNN-title.md` using a four-section
  format: Context, Decision, Consequences, Alternatives considered. Write one
  for at least: the two-tier detection design, the assertion-timeout safety
  model, AppKit over MenuBarExtra, and the MAS/direct split.

## Tooling

- `swiftlint` with a checked-in `.swiftlint.yml` — enable `file_length`,
  `type_body_length`, `cyclomatic_complexity`, `force_unwrapping`,
  `implicitly_unwrapped_optional`, and the analyzer rules for unused imports.
- `swift-format` with a checked-in `.swift-format` config.
- `.editorconfig`, `.gitignore` (Xcode + macOS + SPM), `.gitattributes`.
- `.github/workflows/ci.yml`: build, test, lint on `macos-latest`. Written, not
  executed, and definitely not committed.

## Review gate

Before declaring a milestone done, re-read the diff as if you were reviewing a
colleague's PR and ask: would I approve this? Common things to catch — leftover
TODOs with no ticket, a protocol with one conformer and no test, a magic number
that should be a named default in `BelaySettings`, a `Task { }` with no
cancellation story.
