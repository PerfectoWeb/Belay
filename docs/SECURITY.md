# Security and privacy

Belay reads local agent state to decide whether an AI coding agent is working.
That is a sensitive thing for an app to do, so this document states exactly what
it reads, what it never reads, and how you can check for yourself.

## The short version

- Belay makes **one** outbound connection, and only if you ask for it: an HTTPS
  GET to `api.github.com` to see whether a newer release exists. It is absent
  from the App Store build and sends nothing about you or your machine. It
  downloads nothing by itself: pressing **Update** is what fetches the signed
  disk image, and Sparkle checks it against the EdDSA public key compiled into
  the running build before installing anything. There is no telemetry and no
  crash reporter. With the update check off and Update unpressed, Belay opens no
  sockets at all except the loopback listener described below.
- It reads **structural fields only** from your agent's session files: whether a
  file grew, and a record's `type` and `stop_reason`.
- It **never reads your prompts, your model's responses, or your code**.
- It listens on **`127.0.0.1` only**, on an ephemeral port, and only to receive
  lifecycle events from Claude Code on your own machine.

## What Belay reads, precisely

### Transcript files (`~/.claude/projects/**/*.jsonl`)

Belay keeps a byte offset per file and reads only what was appended since it last
looked. From those bytes it decodes a deliberately tiny structure: the record
`type`, and for assistant records `message.stop_reason`. Nothing else is decoded
into a Belay value.

The primary signal is simply **that the file grew**. Structural parsing is a
refinement layered on top, and if it ever fails Belay falls back to "the file
grew, so something is happening" rather than reading more.

Transcripts on a working machine reach tens of megabytes and contain your entire
conversation. Belay never reads them from the beginning after the first sight of
a file, never re-reads history, and caps how much it will read in one go.

### Session records (`~/.claude/sessions/*.json`)

Belay reads `pid`, `sessionId` and `cwd` to know which agent processes are alive
and which project each belongs to. The project folder's **name** is shown in the
UI ("an agent is working in *acme-api*"). The path is not transmitted anywhere.

### Hook events (optional, off by default)

If you turn on precise detection, Claude Code POSTs lifecycle events to Belay's
loopback listener. Those payloads include a `prompt` field containing **your full
prompt text**.

Belay's decoder declares keys for exactly four fields, `session_id`,
`hook_event_name`, `cwd` and `transcript_path`, and has no property for `prompt`.
It is never decoded, never logged, never stored. A test sends a distinctive
string in the `prompt` field and asserts it appears in neither the emitted signal
nor any file Belay writes.

## What Belay writes

- `~/Library/Application Support/Belay/bridge.json`, the loopback port and a
  random per-install token, created `0600`.
- `~/Library/Application Support/Belay/backups/`, timestamped copies of your
  `~/.claude/settings.json`, taken before any change.
- `~/.claude/settings.json`, **only** when you explicitly enable precise
  detection, and only after showing you the exact JSON that will be added.

On that last one, the rules the code enforces:

1. A timestamped backup is taken first. If the backup fails, nothing is written.
2. If the file is not plain JSON, Belay **refuses to write it** and offers you a
   snippet to paste instead.
3. Writes are atomic (temp file in the same directory, then `replaceItem`).
4. Every entry Belay adds is marked as its own, so removal is exact and never
   touches a hook you added.

## The loopback listener

Only present while Belay is running. Bound to `127.0.0.1`, never `0.0.0.0`.
Requests without the correct `Authorization: Bearer` token are rejected with 401
and their body is never parsed.

One honest caveat: on macOS a socket bound to `127.0.0.1` is still reachable from
**the same machine** through other local interface addresses. This is kernel
behaviour, not something Belay chooses, and it is the same for any loopback
server. It is not reachable from the network. The bearer token is what protects
it from other local processes.

The App Store build ships **without** the `com.apple.security.network.client`
entitlement, so it is not merely that Belay does not phone home. It cannot.

## Verify it yourself

```bash
# What Belay is holding, and why, in plain language:
pmset -g assertions | grep "pid $(pgrep -x Belay)("

# What it is listening on. Expect 127.0.0.1, never *:
lsof -nP -iTCP -sTCP:LISTEN -a -p "$(pgrep -x Belay)"

# Any outbound connections at all. Expect none:
lsof -nP -i -a -p "$(pgrep -x Belay)" | grep -v LISTEN
```

## Reporting a vulnerability

Open a GitHub issue for anything non-sensitive. For something that should not be
public, contact the repository owner directly and give a reasonable window before
disclosure. There is no bug bounty; this is a free utility.

## Threat model, stated plainly

Belay is not a security product. It defends against accidental exposure of your
prompts and code by simply never reading them, and against another local process
driving its listener by requiring a token. It does not defend against an attacker
who already has your user account. Such an attacker can read `~/.claude`
directly and does not need Belay to do it.
