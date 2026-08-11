# VigilSupport

The floor everything else stands on. Two files, and it should stay about that
size — anything with real behaviour belongs in the module that owns the domain.

- `Log` — `os.Logger` with one category per module (`app`, `core`, `power`,
  `providers`, `bridge`, `settings`) plus an `OSSignposter` for Instruments.
- `FileAccessProvider` — the abstraction over "can we read this path right now",
  with `DirectFileAccess` for the unsandboxed build.

**Depends on:** nothing. That is deliberate; every other module depends on this
one, so a dependency here would become a dependency everywhere.

## Things that might surprise you

**`FileAccessProvider` is here rather than in `VigilProviders`, and it has one
implementation.** It is one of the two seams that make the direct and Mac App
Store builds a scheme difference instead of a fork (`docs/adr/004`): the direct
build reads `~/.claude` outright, the sandboxed build resolves a security-scoped
bookmark, and no detection code can tell which it got. `docs/07` bans
single-implementation abstractions and excuses this one by name. It also happens
to be how the provider tests point the whole detection path at a temp tree.

**The subsystem string is a literal, not derived from the bundle.**
`Log.subsystem` is `"com.perfecto-web.vigil"`, hardcoded — a module in a SwiftPM
package has no bundle identifier to read, and `Bundle.main` inside a test runner
is the test runner. It is one of the strings the rename procedure in
`docs/NAMING.md` has to touch.

**Nothing logged here may identify the user.** Session IDs go through
`%{private}@`; transcript content, prompts and paths inside user projects never
reach a logger at any level. `SessionID.description` truncates to eight
characters for the same reason.
