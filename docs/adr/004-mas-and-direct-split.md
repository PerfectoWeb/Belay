# 004 — Two schemes from one codebase, direct first

**Status:** accepted. The split shipped: two schemes, one codebase, direct
first.

Two things below no longer describe the tree. The monetisation seam is gone:
`TipJarProviding` and its two implementations were deleted on 2026-08-16,
because the account cannot register products and the code was never called from
anywhere. And `FileAccessProvider` is no longer a single implementation:
security-scoped bookmarks are resolved for folders the user picks, which is what
`docs/BLOCKERS.md (git history)` B8 was about.

## Context

Belay wants to ship through two channels that disagree about almost everything it
does.

The direct build is Developer ID signed and notarized, unsandboxed, updates
itself through Sparkle, and can point at a "buy me a coffee" link. The Mac App
Store build must be sandboxed, cannot ship a third-party updater at all, and must
use StoreKit consumables for tipping — a Ko-fi link inside a MAS build is a
guideline violation, not a grey area.

Worse, the sandbox lands directly on the one thing Belay exists to do. Reading
`~/.claude` unsandboxed is a `FileManager` call; sandboxed it needs the user to
grant the folder through an open panel and a security-scoped bookmark resolved on
every launch, with `startAccessingSecurityScopedResource()` balanced by a `defer`
or the per-process limit eventually runs out and detection dies with no visible
cause. The loopback listener needs `com.apple.security.network.server`. Risk
**R5** is exactly this: the sandbox breaking detection subtly rather than loudly.

And App Review will ask about two things — reading another application's
configuration directory, and holding a listening socket — either of which can
turn into a rejection loop (**R4**).

The tempting answers are both bad. Shipping only direct forfeits the audience
that installs everything from the App Store. Forking the source into two
repositories means every detection fix has to be made twice and the sandboxed
copy quietly rots, which is the failure mode that turns a "MAS version" into an
abandoned one.

## Decision

One codebase, one source tree, two XcodeGen schemes — `Belay` and `Belay-MAS` —
differing by a compile condition (`BELAY_MAS`) and an entitlements file. Do not
fork the source.

Every channel difference is isolated behind a protocol with two implementations,
and both protocols are defined by what the *product* needs rather than by which
build is running:

- **`FileAccessProvider`** (in `BelaySupport`) abstracts the only real difference
  in the detection path: whether reaching `~/.claude` needs a security-scoped
  bookmark. `DirectFileAccess` reads the path outright. Every provider, cursor
  and sweep takes a `FileAccessProvider` and asks `hasAccess(to:)` or
  `withAccess(to:)`; not one of them can tell which build it is in, and
  `withAccess` releases on the throwing path as well as the normal one.
- **Monetisation** was to be a third seam, `TipJarProviding` in `BelayTipJar`,
  with `isAvailable` false until real products existed. It was built and then
  deleted: see the status note above.

Ship direct first. It is the build that can be released without waiting on
anyone, it validates the product, and it carries no review risk. Submit to the
App Store after, with the review notes already written: user-granted access
through a standard open panel, only structural metadata read, nothing
transmitted, a functional mode without it, and — for the socket — loopback only,
token-authenticated, with the *absence* of `com.apple.security.network.client` as
the proof that there is nowhere to phone home to.

Because the compile condition gates the receiver rather than the code being
tangled around it, the fallback if App Review rejects the socket is dropping Tier
B from the MAS build and keeping it in the direct one. That has to stay a
one-line change rather than a refactor, which is the real reason the split is a
protocol boundary and not a set of `#if` blocks scattered through the detection
code.

## Consequences

- **A detection fix is made once.** The provider, the cursor, the classifier and
  the sweeps are channel-agnostic by construction, so the sandboxed build cannot
  drift behind the direct one on the part of the app that matters.
- **The sandbox is exercised from M2 onward, not discovered at M6.** R5 is the
  risk of finding out late that a bookmark went stale or FSEvents behaves
  differently on a scoped resource, and the only defence is building the second
  scheme early and running the detection tests under it.

  This is the one consequence that did not hold. The second scheme was built at
  M6 and checked for entitlements and the absence of Sparkle, never run against a
  real session, and the bookmark implementation the whole argument rests on was
  never written. R5 landed exactly as described: the failure is silent, and the
  build audit passes anyway. `docs/BLOCKERS.md (git history)` B8.
- **Nothing in the codebase asks "am I sandboxed?"** Types depend on
  `FileAccessProvider`, which is injectable, which is also why the provider suite
  can point the whole detection path at a temp tree.
- **`#if BELAY_MAS` is confined to composition.** Which implementation is handed
  in, which entitlements are attached, and whether Sparkle is linked. If the
  condition ever appears inside detection or power logic, the abstraction has
  failed and the fix is the abstraction.
- **Sparkle must be absent from the MAS build entirely** — dependency,
  entitlements and UI — and the only trustworthy check is grepping the built
  binary for Sparkle symbols rather than trusting the build settings.
- **Cost: two schemes to build, sign and test, and a review process to survive
  once.** Accepted. The alternative is one audience or two codebases.
- **Cost: the seams exist before their second implementations do.** `docs/07`
  forbids an abstraction with a single implementation, and both of these are
  explicitly excused by name because they exist for this split. That exemption
  should not be stretched to cover anything else.

## Alternatives considered

**Direct only.** Simplest, no review risk, no sandbox work, and it gives up the
users who will not install software from outside the App Store — which for a
background utility that asks to read another app's files is a meaningful share of
the people most likely to be reassured by Apple's review.

**Mac App Store only.** Forces the sandbox on every user, forfeits Sparkle, and
makes App Review a single point of failure for shipping at all. It also means the
loopback hook bridge — the tier that makes "an agent is waiting for you" possible
— is hostage to a reviewer's opinion.

**Two repositories, or a long-lived branch.** Every fix made twice, and the copy
that fewer people run silently falls behind. This is the failure mode this ADR
exists to prevent.

**`#if BELAY_MAS` inline wherever behaviour differs.** No new types, and it looks
cheaper right up to the point where the detection path has three conditionals in
it and only one of the two configurations is ever actually run. Protocol
boundaries mean the tests exercise both.

**Sandboxing the direct build too, for uniformity.** Would remove the divergence
by making everyone pay for it, including the users who never asked. It also
removes the fallback position: if the sandbox turns out to break something in
detection, there would be no unsandboxed build left to fall back to.
