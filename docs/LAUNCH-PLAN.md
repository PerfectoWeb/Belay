# Launch plan

Getting the first users for Belay, published at `github.com/perfectoweb/belay` by
PerfectoWeb. Free, MIT, no telemetry, no accounts.

The App Store path is a separate document: [`APP-STORE.md`](APP-STORE.md). This
one is about the direct channel, which is the one that can actually ship, and
about telling people it exists.

---

## Part 1: what must be true before announcing anything

Every item here is a real gap in this repository today, not a formality. A launch
that happens before these are closed spends the one chance you get at a first
impression on a bug somebody else finds.

### The repository is not on GitHub

There is no `.git` directory in this working tree. Nothing has ever been
committed or pushed. `README.md` tells people to `git clone
https://github.com/perfectoweb/belay.git`, `CHANGELOG.md` links to a release tag,
and `ReleaseChecker` polls
`https://api.github.com/repos/perfectoweb/belay/releases/latest`. All three point
at a URL that does not resolve.

This is prerequisite zero. Nothing else on this page means anything until the
repository is public.

### CI has never run

[`../.github/workflows/ci.yml`](../.github/workflows/ci.yml) says so itself, in
its own header comment. It targets `macos-15` while development happened on macOS
26.4 with Xcode 26.6, so the first run should be treated as a debugging session.
Do that debugging before anyone is watching, not during a Show HN.

### There is no signed download

`BLOCKERS.md` B6: notarization has credentials in place and has never been run.
[`../scripts/release.sh`](../scripts/release.sh) has never been run either, and
says so in its header. Today the only install path is "clone this and build it
yourself", which is a fine developer story and a terrible launch story. Half the
audience will not have Xcode.

Worse, an unnotarized build handed to a stranger needs a right-click to open, and
the top comment on any post will be a Gatekeeper screenshot. That single comment
is worth more damage than the post is worth reach.

Run `scripts/release.sh`, produce a notarized and stapled DMG, download it on a
different Mac, and open it by double-clicking. If it opens without a prompt, this
item is closed.

### The safety claim is unverified

`docs/QA-CHECKLIST.md` section 1 has an item marked not-yet-run, with the note
that it is invariant 2 and the single most important check in the document:
force-quit the app while it is holding, and confirm the assertion self-releases
within the timeout window.

The whole pitch rests on that behaviour. The README says "there is no such thing
as a zombie caffeination". Nobody has watched it happen. Run it. It takes five
minutes and it is the difference between a claim and a fact.

While you are there, close the rest of section 1: `SIGTERM`, sleep and wake, and
the battery guard. Then section 2's real-session items. Thirty-one manual items
are still unproven overall (`PROJECT_STATE.md`); you do not need all of them, but
you need every one that a launch post makes a claim about.

### The translations have had no native review

`BLOCKERS.md` B7. Six languages ship, all 210 strings translated, mechanical
checks green, and nobody native has read any of the five non-English ones. The
copy is deliberately voicier than normal interface text, which is exactly the
register that goes wrong in translation.

The audience for a Show HN and for r/macapps includes native speakers of all five.
Two honest options:

1. **Ship all six and say so in the README and the release notes**, framed as a
   wanted contribution, which is what `CONTRIBUTING.md` already does. Then a
   correction is a contribution rather than an embarrassment.
2. **Ship English only for the launch build** and add the rest once reviewed.

Option 1 is better. It is already the repository's stated position, it is
truthful, and "help me fix the German" is a genuinely good first-issue ask. What
you must not do is stay quiet and let someone find it.

### macOS 14 and 15 are unverified

`BLOCKERS.md` B5. The README says macOS 14 or later and then says only macOS 26
on Apple silicon has been tested, which is the right way to say it. Keep that
sentence in every place the requirement appears. If someone on macOS 14 files the
first issue, that is a good outcome, but only if you did not claim it worked.

### The name has not been checked

`BLOCKERS.md` B4. The App Store search for "Belay" has not been done. Renaming
after launch costs the URL, the stars and the links. Renaming before launch costs
two files and `xcodegen generate`. Do the search.

### There are no pictures

The README has no screenshot. A menu bar app with no picture does not get
clicked, on any of the channels below. You need, at minimum:

- One screenshot of the panel with real sessions in it, for the README, sized so
  it is legible inline on GitHub.
- One short screen recording, under thirty seconds, showing a run starting, the
  assertion appearing in `pmset -g assertions`, the run ending, and the assertion
  going away. That recording is the entire pitch and it is the asset that will do
  the most work across every channel.

`docs/QA-CHECKLIST.md` warns that `screencapture` photographs the whole screen and
once captured a personal chat on this machine. Use a clean user account, a plain
wallpaper, and a fake project name. The panel shows project folder names.

### One thing to leave out

`PROJECT_STATE.md` describes a planned GitHub star prompt with a careful set of
rules about when it may appear. Do not ship it in the launch build. The rules are
right, but a utility whose whole pitch is that it stays out of the way should not
ask a stranger for a favour in its first week. Add it later, if at all.

---

## Part 2: where this audience is

Ordered by what they are actually worth. Read each community's current rules
before posting; the summaries below are the shape of the rules, not a substitute
for the sidebar, and they change.

### Hacker News, Show HN. Worth the most.

**The rules.** Show HN is for something you made that others can try. It has to
be a link to the thing itself, so link the repository. Do not editorialize the
title. Post it once. Never ask anyone to upvote it, anywhere, including private
messages; that is the fastest route to a penalty and it is detectable. A first
comment from the author giving context is expected and welcome.

**The best form of the post.** Title states what it is, without adjectives. First
comment gives the origin story in two or three short paragraphs, the design
decision that is actually interesting (the self-releasing assertion timeout), and
an explicit list of what it does not do. Then stay in the thread for several
hours and answer everything, including the hostile comments, without defending.

**What gets it flamed.** Three things, specifically for this app. Any hint of AI
marketing language, because HN has AI fatigue and this is a power management
utility that happens to watch an agent. Any privacy claim that cannot be checked
in one command, which is why `SECURITY.md`'s verification block matters more than
its prose. And "why not just use caffeinate", which will be the first comment
every time. The README's FAQ already answers it; answer it again in the thread,
briefly, without acting like it is a bad question, because it is not.

**What gets it removed.** Reposting, vote manipulation, and a link that does not
let people try the thing. If there is no download, the Show HN is premature.

Timing: a weekday morning, US eastern. Not a Friday. Not a holiday week.

### The Claude Code and Codex communities. Worth the most per person reached.

Anthropic's Discord, the Claude Code repository's discussions, and the
`awesome-claude-code` style lists. This is the exact audience: people who already
run long agent tasks and have already hit the problem.

**The rules.** Almost every Discord confines promotion to a showcase channel and
removes it anywhere else. Read the channel list before posting anything.

**The best form.** Not an announcement. A post that leads with the problem, "my
Mac slept in the middle of a two-hour refactor", and shows the webhook one-liner
from the README, which is the part that makes other tool authors care. Belay is
useful to them as an integration target, not just as an app.

**What gets it flamed.** Anything that reads as reading transcripts. Lead with
what it does not read. The distinction between "watches whether a file grew" and
"reads your conversation" is the whole thing, and this is the audience that will
check.

### r/macapps. Worth it.

**The rules.** Self-promotion is allowed, disclosure that you are the developer is
mandatory, and the subreddit uses flair to mark developer posts. No referral
links. No reposting the same app repeatedly.

**The best form.** A screenshot in the post body, a plain description, "free and
open source, MIT" in the first line, a direct link to the notarized download and
a link to the source. Answer every comment. This subreddit rewards developers who
stay in the thread and punishes drive-by posts.

**What gets it removed.** Undisclosed self-promotion, and posting again too soon.
One post per release, at most.

### r/ClaudeAI. Worth it, with care.

Exact audience overlap. Read the sidebar: rules on self-promotion and on
project-showcase flair vary and have changed more than once.

**The best form.** Same as the Discord: the problem first, the app second. This
audience does not need the concept of a long agent run explained to them, so skip
that part entirely and get to what Belay does about it.

**What gets it flamed.** The same privacy question, more sharply, plus a specific
one: does installing the hooks slow Claude Code down. The answer is in the README
(registered `"async": true`, so Claude Code never waits) and the honest
qualification is that the measurement in `docs/QA-CHECKLIST.md` has not been run
yet. Run it before posting here.

### Awesome-* lists on GitHub. Cheap, durable, worth it.

`awesome-mac`, `awesome-macos`, menu bar app lists, and the Claude Code tooling
lists.

**The rules.** Each list has a `CONTRIBUTING.md` with a required entry format,
usually one line, usually alphabetically sorted, often with a minimum star count
or a requirement that the project be non-trivial. Read it, match the format
exactly, one PR per list.

**What gets it rejected.** Wrong format, a project with no README picture and no
release, and submitting to ten lists on the same day, which maintainers notice
because they read each other's repositories.

Do these after the Show HN, not before. Several lists want traction, and the
traffic from a list arrives slowly and keeps arriving, which makes it the right
thing to do second.

### Mac blogs: Michael Tsai, MacStories, 9to5Mac. Low probability, high value.

Blunt: a free menu bar utility gets covered when the story is interesting, not
when it is useful. The interesting story here is the safety model, specifically
the decision to give every assertion a 120 second timeout and re-arm it, so that
a crashed app cannot pin the Mac awake. That is a real engineering argument
against how every other app in this category works, and it is worth a written
post of its own.

**The best form.** Write that post. Publish it on the project's own pages site.
Then, if it stands on its own, submit the post rather than the app. Michael Tsai
links Mac developer writing he finds worth linking, and the way in is to have
written something, not to have pitched something.

For MacStories and 9to5Mac, use the tips address each site publishes. Do not
guess at an address and do not email a writer personally about a free utility.
One short message, the recording linked, the download linked, and no follow-up.

Expect nothing. If it happens it is worth more than everything else on this list
combined, which is why it is worth one hour, and not more than one hour.

### Lobsters. Skip, unless you are already a member.

Posting requires an account, accounts require an invitation, and self-promotion is
constrained: your own work is allowed but should be a small share of what you
submit, and it gets tagged as authored by you. Seeking an invitation in order to
post your own project is exactly the behaviour the community is built to filter
out. If you already have an account and already participate, post it. Otherwise
this is not a channel, it is a trap.

### Product Hunt. Skip for now.

It rewards a polished landing page and a coordinated launch day. Belay has
neither, and a free MIT menu bar utility for a niche developer audience is not
what that audience is browsing for. Revisit only if a real landing page ever
exists, and even then treat it as optional.

### r/LocalLLaMA. Skip.

Named in the brief, so here is the honest read: it is a mismatch. That community
runs local models, mostly through tools Belay covers only via the generic
provider, which somebody has to configure by hand. Belay's zero-configuration
path is Claude Code specifically. Posting a Claude-first tool there reads as
audience-farming, self-promotion rules are enforced, and the response would be
correct to be cold.

If a genuinely good preset for a local-agent workflow ever ships, and it is tested
against that workflow, then there is something to post about. Not before.

---

## Part 3: the honest positioning

### What to claim

- It holds a system sleep assertion only while a local coding agent is working,
  and drops it when the work stops.
- Claude Code needs no configuration. Everything else is configured in Settings.
- Nothing leaves the Mac. The only outbound connection the app can make is an
  update check that is off by default, and the App Store build cannot make it at
  all.
- Every assertion carries a 120 second timeout and is re-armed while work
  continues, so a crashed or force-quit app cannot leave the Mac awake
  indefinitely.
- There are hard rails: a four-hour cap on one continuous hold, a battery guard,
  and release on sleep, quit and signals.
- It never touches System Settings.
- MIT, free, no account.

Every one of those is verifiable by the reader in one or two shell commands, and
`SECURITY.md` lists the commands. That is the strongest thing this project has.
Lead with it.

### The three claims to avoid, because they are not true

**"Works with the lid closed."** It does not, and no app can make it. An
idle-sleep assertion does not prevent clamshell sleep; a MacBook with the lid shut
sleeps unless it is on AC power with an external display attached. The README FAQ
already says this. Say it in the launch post too, before someone else does. Being
the one who names your own limitation is worth more than the limitation costs.

**"Replaces caffeinate entirely."** Always on mode is `caffeinate` with safety
rails, and that is a fair description of that one mode. It is not a replacement
for the tool: `caffeinate` runs over SSH, runs in scripts, can be scoped to a
process or a duration from a command line, and needs no GUI session. Belay is a
better default for a person at a Mac. Claim that, and nothing wider.

**"Keeps working after a force quit."** The opposite is the design, and the design
is the good part. After a force quit the assertion is not refreshed, it expires,
and the Mac returns to normal sleep behaviour. There is a window of up to 120
seconds during which the assertion is still held, and pretending otherwise turns
a well-designed safety property into an overstatement someone can disprove. Say
"within two minutes". And do not say even that until the force-quit check in
`docs/QA-CHECKLIST.md` has actually been run.

---

## Part 4: a Show HN draft

**Title** (77 characters, no adjectives, links to the repository):

```
Show HN: Belay, a Mac menu bar app that sleeps when your coding agent is done
```

**First comment:**

```
I kept starting long Claude Code runs and walking away, and my Mac kept going
to sleep in the middle of them. The usual fix is to set sleep to Never, which
I then forget about for a week, or to leave `caffeinate` running in a terminal
tab, which becomes load-bearing and dies with the shell.

Belay holds a system sleep assertion only while an agent is actually working.
It watches the JSONL transcripts Claude Code appends under ~/.claude/projects
with FSEvents and reads only the bytes added since it last looked. The primary
signal is that a file grew, which keeps working when the record format changes,
because it does not depend on the format. There is an optional hook bridge on
127.0.0.1 for exact, sub-second events; the hooks are registered async, so
Claude Code never waits on it.

The part I actually spent the time on is the failure mode. The thing that would
make you uninstall this is not "it let my Mac sleep", it is "it kept my Mac
awake for nine hours and I did not notice". So every assertion is created with
a 120 second timeout and re-armed while work continues. If the app crashes,
hangs, or is force-quit, the assertion expires on its own and the Mac goes back
to your normal sleep schedule. There is also a four-hour cap on one continuous
hold, a battery guard, and a TTL on every tracked session, so a stale session
cannot pin the machine.

You can check all of it without trusting me:

  pmset -g assertions | grep "pid $(pgrep -x Belay)("
  lsof -nP -i -a -p "$(pgrep -x Belay)" | grep -v LISTEN

The first prints what is held and why, in plain English, with the remaining
timeout. The second should print nothing.

What it does not do: it will not keep a MacBook awake with the lid closed. No
idle-sleep assertion can. It prevents system sleep, not display sleep, so your
screen still turns off, which is intentional. And it is not a caffeinate
replacement; there is an Always on mode that is caffeinate with the same rails,
but caffeinate works over SSH and in scripts and this does not.

Claude Code works with no setup. Codex CLI, Aider, Gemini CLI and Cline are
presets of a generic provider that watches a folder, a process, or accepts a
local webhook, so anything that can run a shell command can talk to it in one
line.

It reads structural fields only: whether a file grew, and a record's type and
stop_reason. Not your prompts, not the model's output, not your code. The hook
decoder has no field for the prompt text that UserPromptSubmit carries, and
there is a test that sends a distinctive string and asserts it lands nowhere.

MIT, no account, no telemetry. macOS 14 is the deployment target but only 26.4
has actually been tested, and the six translations have not had a native review
yet, both of which are written down in the repo. Happy to answer anything.
```

Adjust the last paragraph to match reality on the day. If macOS 14 has been
verified by then, say so. If it has not, leave it exactly as it is.

## Part 5: a one-paragraph directory blurb

For awesome lists, the r/macapps post body, and anywhere that wants a paragraph:

```
Belay is a free, open-source macOS menu bar app that holds a system sleep
assertion only while a local AI coding agent is working, then lets the Mac
return to its normal sleep schedule. It detects Claude Code with no
configuration by watching transcript files for growth, and covers other tools
through a generic provider that can watch a folder, watch a process, or accept
a local webhook. Every assertion carries a 120 second timeout and is re-armed
while work continues, so a crashed or force-quit app cannot leave the Mac
awake; there is also a cap on continuous awake time, a battery guard, and a TTL
on every tracked session. Nothing leaves the machine: no API key, no account,
no telemetry, and the App Store build ships without the network client
entitlement entirely. macOS 14 or later. MIT.
```

For a one-line entry where a list requires one:

```
Belay - keeps a Mac awake only while a local AI coding agent is working.
```

---

## Part 6: what to measure, without telemetry

Adding analytics to answer these questions would contradict the pitch. Everything
below is measurable from outside the app.

**GitHub stars.** A weak absolute signal and a useful relative one. What matters
is the shape around a post: a Show HN that produces a burst and then nothing means
people liked the idea, and a burst followed by a slow steady trickle means the
awesome-list entries and search are working. Record the count before each post so
the delta is attributable.

**Release asset download counts.** The releases API reports `download_count` per
asset. This is the closest thing to an install count that exists. The honest
caveats: it counts every fetch including bots, mirrors and CI, it says nothing
about whether the app was opened, and it says nothing about whether it is still
installed a week later. Treat it as an upper bound on interest, never as users.

**Repository traffic.** GitHub's Insights, Traffic page gives views, unique
visitors, clones and referring sites, but only for the last fourteen days. It is
the only place you will learn which channel actually sent people. Record it
weekly or lose it permanently.

**Issue quality, which is the real metric.** Count the issues by kind:

- "It did not detect my session" is the important one. Tier A works on this
  machine; whether it works on other people's is the single open question this
  release cannot answer alone. A handful of these is expected. A flood means
  `docs/11-RISKS.md` R1 has already happened.
- "It kept my Mac awake when it should not have" is the one that matters most,
  because it is invariant 3 or 4 failing. Zero of these is the target and any of
  them outrank everything else.
- "Here is a preset for X" and a pull request against
  [`../Resources/Localizable.xcstrings`](../Resources/Localizable.xcstrings) are
  the good ones. `CONTRIBUTING.md` already names both as the wanted
  contributions, and a translation PR is the only thing that closes `BLOCKERS.md`
  B7.

[`../.github/ISSUE_TEMPLATE/bug_report.yml`](../.github/ISSUE_TEMPLATE/bug_report.yml)
already asks for the panel's status line and the assertion state, which is what
makes a detection report actionable. One small fix before launch: the command it
tells people to run is `pmset -g assertions | grep -i belay`, and
`docs/QA-CHECKLIST.md` explains why that is the wrong grep. It also matches
`runningboardd`'s launch assertion for the bundle identifier, which is not ours,
so reporters will paste a line that looks like a stuck assertion and is not.
Change it to match on the pid, the way the checklist and the README both do.

**What you will not know, and should stop wanting to know.** Daily active users,
retention, which features get used, and whether people leave it in Auto or Always
on. That is the trade. It is the right trade for this app, and the answer to
anyone who suggests "just a little anonymous telemetry" is that the absence of it
is the product.

---

## Part 7: a realistic thirty-day timeline

Days, not dates, because the start depends on when the blockers above get closed.
The dependencies are real: nothing in week two is possible without week one.

**Days 0 to 5, unblock.**
Initialise the repository and push it. Get CI green on a runner, which will take
longer than expected. Do the name-conflict search. Run the manual QA items the
launch claims depend on, starting with the force-quit self-release check. Run
`scripts/release.sh` end to end, notarize, staple, and open the DMG on a Mac that
did not build it.

**Days 5 to 8, assets and honesty pass.**
Take the screenshots and record the thirty second clip. Put a picture in the
README. Re-read every claim in `README.md` against what section 1 of the QA
checklist now says is verified, and soften anything that outran the evidence.
Proofread `SECURITY.md`, which is the file the most skeptical readers will open
first and which currently has a mangled paragraph near the top: a bullet list
begins mid-sentence under "The short version", with an orphaned fragment reading
"telemetry, no crash reporter, no update ping in the App Store build." That is
the worst possible file to have a visible defect in. Decide the translation
question. Cut the v1.0.0 release with real notes.

**Days 8 to 10, quiet first contact.**
Give it to five people directly and watch them install it. Not a post, a
conversation. Everything they hit in the first ten minutes is what a thousand
strangers would hit, and it is far cheaper to fix now. Expect at least one thing
you did not predict; that is the point of the step.

**Days 10 to 12, Show HN.**
Weekday morning, US eastern. First comment ready before posting. Then be present
for six hours. Do not post anywhere else the same day.

**Days 12 to 16, the communities.**
r/macapps, then r/ClaudeAI, then one Discord showcase, spread across separate
days. Each one gets its own post written for that audience, not a copy of the
Show HN.

**Days 16 to 25, the durable channels.**
Awesome-list pull requests, one at a time, in each list's required format. Write
the post about the assertion timeout safety model and publish it. If it is good,
that is the thing to send to the Mac blogs.

**Days 25 to 30, respond.**
Ship v1.0.1 from what the launch actually surfaced. Merge the translation
corrections. Update `BLOCKERS.md` and `PROJECT_STATE.md` with what is now known.

Only after all of that is it worth reading [`APP-STORE.md`](APP-STORE.md) as a
plan rather than as a reference, and its blocker zero means the App Store is a
later quarter, not a later week.

### What not to do, at any point

Do not ask anyone to upvote anything. Do not post to five places in one day; it
looks like a campaign and each community can see the others. Do not argue with a
critical comment, especially a correct one. Do not add telemetry to find out how
it is going. Do not announce a v1.1 feature before v1.0 has run on somebody
else's machine for a week.
