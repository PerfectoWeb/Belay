# BelayHookBridge

Tier B: the loopback listener Claude Code's HTTP hooks post to, and the installer
that puts those hooks into `~/.claude/settings.json`. Every signal this module
emits is `.exact`, because the agent said what happened rather than a file watcher
inferring it.

`HookReceiver` runs the listener. `LoopbackListener` decides what it is reachable
from. `HookEvent` maps event names to activities. `HookInstaller`, `SettingsMerge`
and `SettingsDocument` are the write path; `BridgeEndpointStore` owns the port and
token record.

**Depends on:** `BelaySupport` and `BelayCore`.

## Things that might surprise you

**`HookEnvelope` is internal, has four fields, and must stay that way.** A
`UserPromptSubmit` body carries the user's entire prompt and a `PostToolUse` body
carries tool output. Neither has a `CodingKey` here, so neither can be decoded into
a Belay value, stored, or handed to a logger. It is not `public` precisely so that
nothing outside this module can construct or hold a value that came from a
prompt-bearing payload. Do not add a field.

**Request bytes never live in a property.** The receive buffer travels through the
closure chain and dies with it. That is what keeps prompts and tool output off the
receiver actor entirely, rather than relying on someone remembering not to store
them.

**Every request is answered, and an unusable body still gets 204.** Hooks are
registered `async`, but a receiver that stalls a connection is still in the user's
agent's way, and a hook that reports failure is a hook that can put an error in
front of the user's agent. `docs/00-INVARIANTS.md` invariant 5 says Belay does not get to do
that. Authorization is checked before anything looks at the body: a wrong bearer
token is 401 and the payload is never parsed.

**The ownership marker is a query item in Belay's own hook URL, not a JSON key.**
`http://127.0.0.1:<port>/hook?src=belay`. Two reasons. Claude Code validates the
shape of `settings.json`, and slipping an unrecognised key into a hook object is a
way to break the user's agent for our own bookkeeping — precisely risk R2. And a
URL is a string, so it survives `JSONSerialization` unchanged, where a marker
written as `true` comes back as an `NSNumber`, stops comparing equal, and makes
uninstall miss entries it owns.

**The order inside a write is fixed: parse, refuse if it is not plain JSON, merge,
back up, atomically replace.** A failure at any step leaves the user's file exactly
as it was. `preview` produces byte-for-byte what `install` would land, so the UI
can get consent first. Backups copy the raw bytes rather than a re-serialised
parse, so they restore faithfully even for a file we would have refused to write.

**`SettingsMerge` touches no files at all.** It is a pure function over a parsed
dictionary, which is how the dangerous cases — a user who already has their own
hooks on the same events — get tested exactly. Anything Belay does not recognise
is copied across untouched, including values of the wrong shape.

**`reconcile` is the one write with no button behind it.** It repoints hooks at a
changed ephemeral port, and it deliberately does nothing when Belay is not already
installed: fixing a stale record is worth doing silently, adding an integration the
user never consented to is not.

**`LoopbackListener` is its own file so the answer is hard to change by accident.**
`127.0.0.1`, ephemeral port, and the restriction is stated twice — once as
`requiredLocalEndpoint`, once as `requiredInterfaceType`. A hook receiver that
answered the network would be a remote "keep this Mac awake" button.
