# FAQ

Questions about *why Belay is built this way*. If you are looking for **what to
do when something is wrong**, that is the Troubleshooting section in
[`../README.md`](../README.md#-troubleshooting).

---

### Why not just use `caffeinate`?

Because you have to remember to stop it.

`caffeinate -i` holds until you kill it, so a forgotten terminal tab keeps the
Mac awake all week, and if it dies with the shell, your run dies with it.

Belay starts and stops on its own, its assertion expires by itself if the app is
not there to refresh it, and it will not hold past four hours or below 20%
battery no matter what your agent is doing. **Always On** mode is `caffeinate`
with those rails, if that is genuinely all you want.

### Why not ask the Anthropic API whether my agent is busy?

There is no such endpoint. The API has no knowledge of a local Claude Code
process, so asking it would cost money to learn nothing.

Any design that needs you to paste an API key is solving a different problem
from this one.

### Why not watch CPU usage?

It fails in both directions, which is the worst kind of signal.

An agent waiting ninety seconds on a network response uses no CPU but is very
much working. A language server in the same project can peg a core while
absolutely nothing is happening.

### What about Codex, Aider, Gemini CLI, Cline, DeepSeek?

Claude Code is first-class and needs no setup. Everything else goes through the
generic provider in **Settings ▸ Providers**: watch a folder, watch a process,
or send Belay a webhook.

Aider, Gemini CLI, Cline and Codex CLI ship as **presets**, which are
pre-filled configurations rather than code. That is deliberate: a wrong path in
a preset costs you one edit, never a release.

On DeepSeek specifically: there is no first-party DeepSeek CLI to hook into. It
is consumed through other tools, and those tools are what Belay watches.

### Will the hooks slow Claude Code down?

They cannot. They are registered `"async": true`, so Claude Code does not wait
for a response, and there is no exit code Belay could return that would block
anything.

### Why does it need to read my session files at all?

Because that is the only local, honest evidence that an agent is working. Belay
reads whether a file grew, plus a record's `type` and `stop_reason`, never your
prompts, your model's responses, or your code.
[`HOW-IT-WORKS.md`](HOW-IT-WORKS.md#privacy) has the detail and
[`SECURITY.md`](SECURITY.md) has the proof.

### Why is there no Dock icon or window?

Belay is a utility you should be able to forget about. It is `LSUIElement`: a
menu bar item, a panel on left-click, a compact menu on right-click. The status
glyph conveys state by **shape**, never by animation, so it does not pull your
eye while you are working.

### Why does changing the language restart the app?

The menu bar menu and the alerts are AppKit, and AppKit will not switch language
under a running process. Belay reopens itself rather than showing you a menu in
one language and a panel in another.

Belay follows your Mac's language by default and falls back to English when it
does not ship yours; **Settings ▸ General** has a picker.
