# Privacy policy

**Belay for macOS. Last updated 29 September 2026.**

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

The Screenshot Cleaner module, if you install it, lists the folder your
screenshots are saved in. For each file it reads two dates, the kind of file,
and the marks macOS and Finder leave on it: whether it is a screen capture, and
whether it carries a tag. It does not open a screenshot or look at what is in
the picture.

The Warm Microphone module, if you install it, opens the microphone and keeps
it open. The sound is discarded as it arrives. Belay does not record it,
measure it, keep any of it in memory or on disk, or send it anywhere, and
macOS shows its orange microphone dot for as long as the module is on.

The Auto Allow module, if you install it in the direct build, reads the
windows of the Claude desktop app and of Codex (the ChatGPT desktop app)
through the macOS Accessibility interface, looking for a permission request. Of what is on the screen it keeps only the text of that
request, for as long as it takes to decide, and of that it stores one thing:
the site that was approved and when, in a list of the latest fifty that you can
see in the module's settings. The rest of the window, your conversation
included, is passed over and not kept.

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

The Screenshot Cleaner module moves screenshots older than the age you chose to
the Trash, in the folders you gave it and nowhere else. It never deletes a file:
the Trash is where they stay until you empty it. Nothing happens unless the
module is installed and switched on.

The Auto Allow module presses "Allow once" in the Claude desktop app and in
Codex in your name: by default only for requests about sites on your own Mac
or network, and for everything the agent asks only if you choose that. In
Codex the press is the Return key, sent to the Codex process while the
"Allow once" button has the focus, and never otherwise. If you switch on
"Answer in sessions behind the window", it also presses a session in the
app's list to bring it into the window and the one you had open to bring that
back; for this it reads the names of your sessions and keeps them only for the
length of that look, never on disk and never in the log. It presses nothing
else, in these apps or in any other, and it stops when its time runs out or
you switch it off.

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
