# Privacy policy

**Belay, for macOS. Last updated 13 August 2026.**

Belay collects nothing about you. There is no account, no analytics, no crash
reporting service and no identifier of any kind. This page exists because the
App Store requires a privacy policy URL, not because there is much to disclose.

## What Belay reads

Belay's whole job is to tell whether a local AI coding agent is working right
now. To answer that it looks at the session files your agent already writes on
your own Mac:

- how large a session file is, and whether it grew
- when it was last written
- whether the last record says a turn ended
- whether the agent process has recently started a child process

It reads the smallest part of a session file that answers the question, from
where it last stopped. It does not read your prompts, your replies, your code
or your file names, and it does not keep a copy of anything it reads.

Which folders it looks at is up to you. `~/.claude` for Claude Code, and for
anything else only the folders you point it at yourself.

## What leaves your Mac

**On the Mac App Store version: nothing.** That build cannot make a network
connection at all.

**On the version downloaded from GitHub: one request a day, and only that.**
Belay asks the releases API whether a newer version exists. The request carries
no query, no identifier and nothing about you or your machine; the server sees
an IP address and a user agent, exactly as it would if you opened the releases
page in a browser. Nothing is installed without you asking. The check can be
turned off in Settings, under General, and once off it makes no request at all.

## What Belay stores, and where

Your settings and your usage counters, in your Mac's own preferences, in your
user account. The counters are durations and counts only: how long the Mac was
held awake, how many runs were watched, on which days. There are no names of
projects, no names of files and nothing that identifies a piece of work.

You can erase the counters at any time in Settings, under Statistics. Deleting
the app removes everything else.

## What Belay changes on your Mac

It holds a power assertion, which is macOS's own supported way of asking the
system to stay awake, and it releases it. It does not change your Energy Saver
settings, and it cannot: an assertion is a request that sits alongside your
settings rather than editing them.

If you switch on precise detection for Claude Code, Belay adds one hook entry
to Claude Code's own settings file, after showing you the exact text and asking.
Removing it is a button in the same place.

## Sharing

Nothing is shared with anyone. There are no third-party services in the app, no
advertising, and no data is sold, because none is collected.

The one exception is you: the Statistics pane can produce an image of your own
numbers to share, and that only happens when you press the button and choose
where it goes.

## Children

Belay is a developer tool. It is rated 4+ because it contains nothing
objectionable, not because it is aimed at children, and it collects nothing
from anyone regardless of age.

## Changes to this policy

If this ever changes it will change here first, with the date above updated,
and the release notes will say so.

## Contact

Questions about this policy: <https://github.com/perfectoweb/belay/issues> or
the address on <https://perfecto-web.com>.
