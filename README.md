<div align="center">

<picture><source media="(max-width: 500px)" srcset="Promo/Social/masthead-2x-mobile.png"><img src="Promo/Social/masthead-2x.png" alt="Belay: keeps your Mac awake while your AI agent works" width="100%"></picture>

<img src="Promo/Social/spacer.png" height="12" alt="">

[![Latest release](https://img.shields.io/github/v/release/PerfectoWeb/Belay?style=flat&label=release&color=1f6bff)](https://github.com/PerfectoWeb/Belay/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/PerfectoWeb/Belay/total?style=flat&color=1f6bff)](https://github.com/PerfectoWeb/Belay/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/PerfectoWeb/Belay/ci.yml?style=flat&label=CI)](https://github.com/PerfectoWeb/Belay/actions)<br>
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?style=flat&logo=apple&logoColor=white)
![Universal](https://img.shields.io/badge/universal-Apple%20silicon%20%26%20Intel-111?style=flat)<br>
[![Homebrew](https://img.shields.io/badge/homebrew-perfectoweb%2Ftap-1f6bff?style=flat&logo=homebrew&logoColor=white)](https://github.com/PerfectoWeb/homebrew-tap)
[![Mac App Store](https://img.shields.io/badge/Mac%20App%20Store-Belay-1f6bff?style=flat&logo=apple&logoColor=white)](https://apps.apple.com/app/belay-awake-for-ai-agents/id6801207644)
[![Notarized](https://img.shields.io/badge/notarized-by%20Apple-111?style=flat&logo=apple&logoColor=white)](#-verify-what-you-downloaded)

<img src="Promo/Social/spacer.png" height="12" alt="">

<a href="https://github.com/PerfectoWeb/Belay/releases/latest/download/Belay.dmg"><picture><source media="(min-width: 501px)" srcset="Promo/Social/btn-download-green-desk.png"><img src="Promo/Social/btn-download-green.png" alt="Download Belay for macOS" height="64"></picture></a><picture><source media="(max-width: 500px)" srcset="Promo/Social/spacer.png"><img src="Promo/Social/spacer-16.png" alt=""></picture><a href="https://perfectoweb.github.io/Belay/"><picture><source media="(min-width: 501px) and (prefers-color-scheme: dark)" srcset="Promo/Social/btn-site-dark-desk.png"><source media="(min-width: 501px)" srcset="Promo/Social/btn-site-light-desk.png"><source media="(prefers-color-scheme: dark)" srcset="Promo/Social/btn-site-dark.png"><img src="Promo/Social/btn-site-light.png" alt="Learn more on the Belay website" height="64"></picture></a>

</div>

## 📚 What is it?

You start a long Claude Code task and walk away. Ten minutes later your Mac
sleeps, the run dies, and you come back to nothing. So you set sleep to
**Never**, forget to change it back, and your laptop cooks itself for a week.

Belay is a macOS menu bar app that fixes exactly that, and nothing else. It
watches your local coding agents, holds the Mac awake **only while one is
genuinely working**, and hands sleep straight back the moment everything goes
quiet. Your System Settings are never touched — the one switch the opt-in lid
hold exists to hold is flipped back by itself, every time.

The trade-off it is tuned around is lopsided on purpose: sleeping sixty seconds
too early kills a long run silently and wastes an evening, while staying awake
sixty seconds too long costs nothing at all.

## ✨ Features

<table>
<tr><td width="21%">🎯&nbsp;<b>Zero&nbsp;setup</b></td><td>Claude Code is detected automatically. Nothing to configure, no key to paste.</td></tr>
<tr><td>🔌&nbsp;<b>Every&nbsp;agent</b></td><td>Codex, Gemini CLI, Cline, Aider and Pi ship as presets. Anything else: watch a folder, watch a process, or send a webhook.</td></tr>
<tr><td>🛡&nbsp;<b>Never&nbsp;stuck</b></td><td>Every hold expires by itself after 120 seconds unless Belay re-arms it. Crash it, force-quit it, kill it, and your Mac is back to normal within two minutes.</td></tr>
<tr><td>🔋&nbsp;<b>Your&nbsp;rails</b></td><td>A cap on continuous awake time, a battery floor, and release on sleep, quit and mode change.</td></tr>
<tr><td>👀&nbsp;<b>Subagents&nbsp;too</b></td><td>Parallel subagents are counted as the one session they belong to, not as noise.</td></tr>
<tr><td>📊&nbsp;<b>Time&nbsp;saved</b></td><td>It counts the time it held while you were away from the keyboard, which is the only time that was ever at risk.</td></tr>
<tr><td>🔒&nbsp;<b>Stays&nbsp;local</b></td><td>No account, no telemetry. One daily version check, carrying nothing about you, and one switch turns it off.</td></tr>
<tr><td>🌍&nbsp;<b>Multilingual</b></td><td>English, Русский, Deutsch, Español, Français, Italiano, 简体中文.</td></tr>
</table>

## 📦 Install

**1.** <a href="https://github.com/PerfectoWeb/Belay/releases/latest/download/Belay.dmg"><b>Download Now</b></a><sup><a href="https://github.com/PerfectoWeb/Belay/releases/latest"><img src="https://img.shields.io/github/v/release/PerfectoWeb/Belay?style=flat&label=&color=1f6bff" alt="latest version" align="middle" hspace="8"></a></sup> macOS 14 or later, Apple silicon and Intel, about 4 MB.

**2.** Open the disk image and drag **Belay** into Applications.

<picture><source media="(max-width: 768px) and (prefers-color-scheme: dark)" srcset="Promo/Social/dmg-window.png"><source media="(max-width: 768px)" srcset="Promo/Social/dmg-window-light.png"><source media="(prefers-color-scheme: dark)" srcset="Promo/Social/dmg-window-wide.png"><img src="Promo/Social/dmg-window-light-wide.png" alt="The Belay disk image: drag the app into Applications" width="100%"></picture>

**3.** That is the install. Launch it and it lives in the menu bar.

The app and the disk image are both signed with a Developer ID and **notarized
by Apple**, and both carry a stapled ticket, so the first launch works with no
network and without the right-click-Open dance.

<details>
<summary><b>Other ways to install</b></summary>

#### 🍺 Homebrew

```bash
brew install --cask perfectoweb/tap/belay
```

`brew upgrade` keeps it current afterwards. It installs the same signed,
notarized disk image the button above gives you, and Homebrew checks its
SHA-256 before it opens it.

The cask lives in [our own tap](https://github.com/PerfectoWeb/homebrew-tap)
rather than in homebrew-cask itself. Homebrew's main cask repository has a
notability bar. A project needs a certain number of stars, forks or watchers
before it is accepted, and Belay has not cleared it yet. Same command shape,
one extra word.

#### 🍎 From the Mac App Store

[**Belay - Awake for AI Agents**](https://apps.apple.com/app/belay-awake-for-ai-agents/id6801207644),
free, macOS 14 or later. The sandboxed build, so it updates through the store
rather than through Sparkle and has no network access at all.

#### 🔨 Build it yourself

No Apple Developer account needed:

```bash
git clone https://github.com/PerfectoWeb/Belay.git && cd Belay
scripts/build-local.sh
open build/Belay.app
```

Needs Xcode 16 or later, plus `xcodegen`, `swiftlint` and `swift-format` from
Homebrew. The result is ad-hoc signed, which means it runs on your Mac and will
not open on anyone else's without a right-click.

#### 🔎 Verify what you downloaded

```bash
spctl -a -vvv -t install /Applications/Belay.app
codesign -dv --verbose=2 /Applications/Belay.app
```

You should see `source=Notarized Developer ID` and team `VSY2EB4Y9E`.

</details>

## 🚀 How to Use

**1. Launch it.** One welcome screen explains what Belay reads. Then it lives in
the menu bar. There is no Dock icon and no window.

**2. Leave it in Auto.** That is the whole product. Belay holds the Mac awake
while an agent is working and lets it sleep when nothing is.

| Mode | What it does |
|---|---|
| 🪄 **Auto** *(default)* | Awake if and only if an agent is working |
| ☀️ **Always On** | A better `caffeinate`, with the same safety rails |
| 🌙 **Off** | Belay holds nothing |

**3. Left-click the menu bar icon** for the panel: what is running, for how
long, and, when Belay is *not* holding, the reason in plain language.
Right-click for a compact menu.

<p align="center">
  <img src="Promo/Social/panel.png" alt="The Belay panel, showing four agents working and the Mac being held awake" width="94%">
</p>

**4. Check it yourself, any time.** Belay never asks to be trusted:

```bash
pmset -g assertions | grep "pid $(pgrep -x Belay)("
```

You will see the assertion, a plain-English reason, and how long it has left.

> **Adding a tool Belay has never heard of** takes one line. If it can run a
> shell command, it can talk to Belay. See
> [`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md#talking-to-belay-from-anything).

## 🖼 Screenshots

<picture><source media="(max-width: 500px)" srcset="Promo/Social/shots/stack.png"><img src="Promo/Social/shots/grid.png" alt="Providers, Statistics, Behaviour and a multilingual interface" width="100%"></picture>

## 🧯 Troubleshooting

<details>
<summary><b>My Mac still went to sleep</b></summary>

Open the panel. It always says why in plain language. The usual answers are
the battery guard, the maximum awake time, or that Belay did not think anything
was running. If it is the last one and your agent *was* working, that is a bug
worth reporting: include the tool and the macOS version.

</details>

<details>
<summary><b>It does not work with the lid closed</b></summary>

Out of the box, no: an idle-sleep assertion does not keep a MacBook awake with
the lid shut. macOS enters clamshell sleep unless the machine is on AC power
with an external display attached.

Since 1.3 the direct build can, as an opt-in. **Keep working with the lid
closed** in Settings installs a system helper — macOS asks for your approval —
that holds
the OS's own sleep switch while an agent is working, and always lets go by
itself: when the work ends, when Belay stops asking for it, after a hard time
cap, or the moment the Mac runs hot with the lid shut. Proven on battery with
no display attached, and the control run without it slept in seventy seconds.

The App Store build cannot install a privileged helper (that is Apple's rule,
and a good one), so it does not offer the switch.

</details>

<details>
<summary><b>My screen still turns off</b></summary>

That is intentional and saves real power. Belay prevents *system* sleep; the
machine underneath keeps working. There is a setting to keep the display awake
too, off by default — and since 1.3, one to dim it to a glow at night while
it is kept awake, so a screen held for an overnight run does not light an
empty room. It brightens back the moment you return.

</details>

<details>
<summary><b>Belay does not see my agent</b></summary>

Claude Code needs no setup. Everything else is configured in **Settings ▸
Providers**: switch on a preset, or point the folder watcher at wherever your
tool writes while it works. If your tool can run a shell command, the webhook in
[`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md#talking-to-belay-from-anything) is
one line.

</details>

<details>
<summary><b>It says "needs setup"</b></summary>

A preset's path did not exist on your machine. Presets are configuration, not
code, so open Settings ▸ Providers and correct the path. A wrong preset costs one
edit, never a release.

</details>

<details>
<summary><b>Something else</b></summary>

[Open an issue.](https://github.com/PerfectoWeb/Belay/issues) The macOS version
and the agent you were running are the two things that make a report
actionable. [`docs/QA-CHECKLIST.md`](docs/QA-CHECKLIST.md) lists what has and
has not been exercised on a real machine; macOS 14, 15 and 26 have all been
run for real.

</details>

## 💬 Support & Contributions

Belay is free and always will be. The most useful things, in order:

⭐ **[Star it](https://github.com/PerfectoWeb/Belay)**. It costs nothing and it
is how other people find this.

🐛 **[Report a bug](https://github.com/PerfectoWeb/Belay/issues/new)**. The
macOS version and the agent you were running are what make a report actionable.

🌍 **[Fix a translation](Localization/)**. Belay is multilingual, and only
English and Russian have been read by a person who speaks them. One CSV per
language, and it is data rather than code. This is the most wanted contribution
here.

🔌 **[Add a preset](docs/CONTRIBUTING.md)** for an agent Belay does not know yet.
Also data, also no need to learn the codebase.

💛 **[Donate](https://perfecto-web.com/d/)**. Last on the list on purpose.

Start at [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md). Security reports go through
[`docs/SECURITY.md`](docs/SECURITY.md), not the issue tracker.

### 📖 Documentation

<table>
<tr><td width="24%"><a href="docs/HOW-IT-WORKS.md">How it works</a></td><td>Detection, the safety rails, privacy, and talking to Belay from anything</td></tr>
<tr><td width="24%"><a href="docs/FAQ.md">FAQ</a></td><td>Why not <code>caffeinate</code>, why not CPU, why not an API key</td></tr>
<tr><td width="24%"><a href="docs/CONTRIBUTING.md">Contributing</a></td><td>Building, testing, translating, adding a preset</td></tr>
<tr><td width="24%"><a href="docs/02-ARCHITECTURE.md">Architecture</a></td><td>How the app is put together</td></tr>
<tr><td width="24%"><a href="docs/SECURITY.md">Security</a></td><td>What Belay reads, what it cannot read, and how to verify it</td></tr>
<tr><td width="24%"><a href="CHANGELOG.md">Changelog</a></td><td>What changed, and why</td></tr>
<tr><td width="24%"><a href="docs/ROADMAP.md">Roadmap</a></td><td>Where Belay is going, and what has to be true first</td></tr>
</table>

## 📝 License

**[Belay Source-Available License 1.0](LICENSE)**. Use it anywhere, fork it,
build on it. Two conditions:

🚫 **You may not sell it.** Not the app, not a derivative, not access to it. Use
is free and stays free for everyone, including at work and for commercial work.
What is forbidden is charging other people for it.

📛 **Credit the original.** Anything built on Belay has to say so where its users
can see it: *Belay by PerfectoWeb*, with a link back here.

The **name and the mark** are separate again. [`docs/TRADEMARKS.md`](docs/TRADEMARKS.md)
says exactly what that does and does not stop you doing.

Belay shows each tool's own logo in the sessions list so you can tell at a
glance which agent is working. All product names, logos and trademarks are the
property of their respective owners, used only to identify those products, and
imply no affiliation or endorsement. See [`NOTICE.md`](NOTICE.md).

<div align="center">
<br>
<sub>Built for people who leave their agents running and go and do something else.</sub>
</div>
