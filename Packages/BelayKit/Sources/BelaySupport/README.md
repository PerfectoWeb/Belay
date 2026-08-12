# BelaySupport

The floor everything else stands on. Small on purpose — anything with real
behaviour belongs in the module that owns the domain.

- `Log` — `os.Logger` with one category per module (`app`, `core`, `power`,
  `providers`, `bridge`, `settings`) plus an `OSSignposter` for Instruments.
- `FileAccessProvider` — the abstraction over "can we read this path right now",
  with `DirectFileAccess` for the unsandboxed build and `BookmarkFileAccess`,
  over a security-scoped bookmark, for the App Store one.
- `SecurityScopedBookmarks` / `BookmarkStore` — Foundation's bookmark calls and
  the bytes they produce, each behind a protocol so the parts that go wrong
  (balance, staleness) can be tested without a sandbox.
- `UserHome.real` — the account's home rather than the sandbox container.

**Depends on:** nothing. That is deliberate; every other module depends on this
one, so a dependency here would become a dependency everywhere.

## Things that might surprise you

**`FileAccessProvider` is here rather than in `BelayProviders`.** It is one of
the two seams that make the direct and Mac App Store builds a scheme difference
instead of a fork (`docs/adr/004`): the direct build reads `~/.claude` outright,
the sandboxed build resolves a security-scoped bookmark, and no detection code
can tell which it got. It is also how the provider tests point the whole
detection path at a temp tree. It had one implementation for most of the
project's life, which `docs/07` excused by name; it now has both.

**Nothing in this module decides which implementation is used.** It cannot:
`SWIFT_ACTIVE_COMPILATION_CONDITIONS` does not reach a local SwiftPM target, so
`#if BELAY_MAS` here is false in every build (`PROJECT_STATE.md` D15). The app
target chooses in `ClaudeAccess` and injects the result.

**`BookmarkFileAccess` holds one standing scope as well as bracketing reads.**
The brackets are what keep the count balanced; the standing scope is what makes
FSEvents and the `stat` calls outside any bracket work at all. Both are
deliberate and the reasoning is in that file's header and in `docs/06`.

**The subsystem string is a literal, not derived from the bundle.**
`Log.subsystem` is `"com.perfecto-web.belay"`, hardcoded — a module in a SwiftPM
package has no bundle identifier to read, and `Bundle.main` inside a test runner
is the test runner. It is one of the strings the rename procedure in
`docs/NAMING.md` has to touch.

**Nothing logged here may identify the user.** Session IDs go through
`%{private}@`; transcript content, prompts and paths inside user projects never
reach a logger at any level. `SessionID.description` truncates to eight
characters for the same reason.
