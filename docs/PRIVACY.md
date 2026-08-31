# Privacy policy

**Belay for macOS. Last updated 13 August 2026.**

Belay doesn't have accounts, analytics, advertising or crash reporting. It
doesn't build a profile of you or send your work to us. Most of what Belay needs
never leaves your Mac.

This file and <https://perfectoweb.github.io/Belay/en/privacy/> are the same
policy. Change one and change the other. The site carries it in every language the app
speaks, all generated from one source; the English is the authoritative text.

## What Belay reads

Belay needs to know one thing: is an agent working right now?

For the built-in agents – Claude Code, Codex, Cline and Copilot CLI – Belay
watches the session files each one already writes on your Mac. It looks at how
large a file is, whether it grew, when it was last written, and, in the part
that grew, only structural markers: what kind of record it is, whether a turn
started or ended, and the name of the project folder. Your prompts, your replies
and your code are not read out of those files and no copy of them is kept.

For any other tool, Belay can watch a folder you choose. macOS tells Belay which
files changed and when, and that is all Belay uses: it does not open those files
or read what is in them. The folder stays yours, and nothing in it is uploaded.

Which folders Belay looks at is up to you. `~/.claude`, `~/.codex`, `~/.cline`
and `~/.copilot` for the built-in agents, and for anything else only what you
point it at.

## What leaves your Mac

**Mac App Store.** Belay makes no outbound network connections. That build ships
without the entitlement macOS requires for them. Precise detection, if you turn
it on, uses a connection that begins and ends on your own Mac and sends nothing
over the internet.

**Direct download.** The version downloaded from GitHub can check for updates
once a day. It sends an ordinary HTTPS request to the GitHub releases API with
no account, no query and no Belay identifier; GitHub sees the request's IP
address and a user agent, as it would for any web request. You can turn
automatic checks off in Settings, under General, and Belay never installs an
update without you asking.

## What Belay stores

Belay stores its settings and simple usage counters in your Mac user
preferences. The counters hold durations, run counts and days. They don't hold
project names, prompts or code.

You can reset your statistics at any time in Settings, under Statistics.

## What Belay changes on your Mac

To keep your Mac awake, Belay uses the power assertion API macOS provides for
it. It doesn't rewrite your Energy Saver settings, and it can't: an assertion
sits alongside those settings rather than editing them.

If you turn on precise detection for an agent (Claude Code, Codex or Cline),
Belay shows you the exact configuration it would add before anything is written,
and only writes after you confirm. It takes a timestamped backup first, adds only
its own entry, and "Remove" on the same screen puts the file back.

## Sharing

Belay doesn't send your usage statistics, your settings or your work to us.
There are no analytics or advertising services in the app.

The Statistics pane can make an image of your own numbers. If you share one,
macOS asks you where it goes, and nothing is shared until you do that yourself.

## Changes to this policy

If this policy changes, we'll update the date above. Any meaningful privacy
change will also be mentioned in the release notes.

## Contact

Questions about this policy: <https://github.com/PerfectoWeb/Belay/issues>, or
the address on <https://perfecto-web.com>.

---

Claude Code, Codex, Cline, GitHub Copilot CLI, Gemini CLI and the other tools
Belay can watch are made by other people. Belay works alongside them and is not
affiliated with or endorsed by any of them.
