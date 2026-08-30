<div align="center">

<picture><source media="(max-width: 500px)" srcset="Promo/Social/masthead-2x-mobile.png"><img src="Promo/Social/masthead-2x.png" alt="Belay: keeps your Mac awake while your AI agent works" width="100%"></picture>

<img src="Promo/Social/spacer.png" height="12" alt="">

[![Latest release](https://img.shields.io/github/v/release/PerfectoWeb/Belay?style=flat&label=release&color=1f6bff)](https://github.com/PerfectoWeb/Belay/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/PerfectoWeb/Belay/total?style=flat&color=1f6bff)](https://github.com/PerfectoWeb/Belay/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/PerfectoWeb/Belay/ci.yml?style=flat&label=CI)](https://github.com/PerfectoWeb/Belay/actions)<br>
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?style=flat&logo=apple&logoColor=white)
![Universal](https://img.shields.io/badge/universal-Apple%20silicon%20%26%20Intel-111?style=flat)
[![Notarized](https://img.shields.io/badge/notarized-by%20Apple-111?style=flat&logo=apple&logoColor=white)](#-verify-what-you-downloaded)<br>
[![Homebrew](https://img.shields.io/badge/homebrew-perfectoweb%2Ftap-1f6bff?style=flat&logo=homebrew&logoColor=white)](https://github.com/PerfectoWeb/homebrew-tap)
[![Mac App Store](https://img.shields.io/badge/Mac%20App%20Store-Belay-1f6bff?style=flat&logo=apple&logoColor=white)](https://apps.apple.com/app/belay-awake-for-ai-agents/id6801207644)


<img src="Promo/Social/spacer.png" height="12" alt="">

<a href="https://github.com/PerfectoWeb/Belay/releases/latest/download/Belay.dmg"><picture><source media="(min-width: 501px)" srcset="Promo/Social/btn-download-green-desk.png"><img src="Promo/Social/btn-download-green.png" alt="Download Belay for macOS" height="64"></picture></a><picture><source media="(max-width: 500px)" srcset="Promo/Social/spacer.png"><img src="Promo/Social/spacer-16.png" alt=""></picture><a href="https://perfectoweb.github.io/Belay/"><picture><source media="(min-width: 501px) and (prefers-color-scheme: dark)" srcset="Promo/Social/btn-site-dark-desk.png"><source media="(min-width: 501px)" srcset="Promo/Social/btn-site-light-desk.png"><source media="(prefers-color-scheme: dark)" srcset="Promo/Social/btn-site-dark.png"><img src="Promo/Social/btn-site-light.png" alt="Learn more on the Belay website" height="64"></picture></a>

<a href="#-install">Install</a> • <a href="#-features">Features</a> • <a href="https://github.com/PerfectoWeb/Belay/blob/main/docs/SECURITY.md">Privacy</a> • <a href="https://github.com/PerfectoWeb/Belay/blob/main/CHANGELOG.md">Changelog</a>
</div>

## 📚 What is it?

You start a long Claude Code, Codex, Cline, or Copilot CLI task and walk away. Ten minutes later your Mac sleeps, the run stops making progress, and you come back to unfinished work.

Belay is a macOS menu bar app that fixes exactly that: **your Mac stays awake while the agent works – and goes back to sleep when the work stops.** No timer required. No sleep setting to remember to change back. And Belay is built to fail toward normal macOS sleep – never toward a Mac that stays awake forever.

<details>
<summary><b>How Belay knows?</b></summary>

Belay is not a `~/.claude` folder watcher with a power cord. There are two independent detection tiers, and a power layer deliberately separated from both:

- **Passive detection** – follows each agent's local session state: whether a
  file grew, and a few structural fields. Never your prompts, responses or
  code. Works out of the box for Claude Code, Codex, Cline and Copilot CLI,
  in any config folder you point it at.
- **Precise Detection** – optional, in the direct build: the agent's own hooks
  report the exact moment a turn starts working, waits for you, or finishes –
  over a loopback port that never leaves your Mac.
- **Everything else** – presets for Gemini CLI, OpenCode, Aider and Pi, plus
  watch-a-folder, watch-a-process, and a local webhook for anything that can
  send one HTTP request.

Whichever tier speaks, the power layer maps it to the same thing: a temporary
macOS power assertion that expires after 120 seconds unless Belay renews it.
If Belay crashes, detection breaks, or you quit it – the Mac just sleeps.
`~/.claude` is only Claude Code's default location, not Belay's architecture:
the details live in [docs/03-DETECTION.md](docs/03-DETECTION.md) and
[docs/SECURITY.md](docs/SECURITY.md).

</details>


## ✨ Features

<table>
<tr><td width="24%" nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/zero-setup-dark.svg"><img src="docs/icons/zero-setup-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Zero&nbsp;setup</b></td><td>Claude Code, Codex, Cline and Copilot are detected automatically. Nothing to configure, no key to paste.</td></tr>
<tr><td nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/more-agents-dark.svg"><img src="docs/icons/more-agents-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>More&nbsp;agents</b></td><td>Gemini CLI, OpenCode, Cline (VS Code), Aider and Pi ship as presets. For anything else, watch a folder or process, or connect it yourself in the direct build.</td></tr>
<tr><td nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/custom-folder-dark.svg"><img src="docs/icons/custom-folder-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Custom&nbsp;folders</b></td><td>Using a custom config folder or multiple profiles? Add each folder in the agent's settings and Belay watches them all.</td></tr>
<tr><td nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/precise-dark.svg"><img src="docs/icons/precise-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Precise&nbsp;detection</b></td><td>In the direct build, every built-in agent can report the exact moment work starts, finishes or waits for you – Copilot does it out of the box, the rest with one click in Settings and a full preview before anything is written.</td></tr>
<tr><td nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/lets-go-dark.svg"><img src="docs/icons/lets-go-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Lets&nbsp;go</b></td><td>Normal holds expire after 120 seconds unless Belay renews them. If Belay disappears, the Mac goes back to normal by itself.</td></tr>
<tr><td nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/timer-dark.svg"><img src="docs/icons/timer-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Timed&nbsp;keep</b></td><td>Always On can run for a set duration or until a specific time, with the countdown in the panel and on the dimmed screen. The timer survives a relaunch.</td></tr>
<tr><td nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/safety-limits-dark.svg"><img src="docs/icons/safety-limits-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Safety&nbsp;limits</b></td><td>Set a maximum awake time and a battery floor. Belay also lets go on sleep, quit and mode changes.</td></tr>
<tr><td nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/agent-teams-dark.svg"><img src="docs/icons/agent-teams-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Agent&nbsp;teams&nbsp;too</b></td><td>Claude Code subagents and Cline teammate agents appear under their session in the panel, and count as part of it, not as noise.</td></tr>
<tr><td nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/dimming-dark.svg"><img src="docs/icons/dimming-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Night&nbsp;dimming</b></td><td>While holding at night, Belay can dim the display to a chosen level on your schedule, show the timer's countdown on the dark screen, and restore brightness the moment you come back.</td></tr>
<tr><td nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/closed-lid-dark.svg"><img src="docs/icons/closed-lid-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Closed‑lid&nbsp;hold</b></td><td>Opt-in for the direct build: keep working with the lid closed, ending at the awake limit or if the Mac runs hot.</td></tr>
<tr><td nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/stats-dark.svg"><img src="docs/icons/stats-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Time&nbsp;saved</b></td><td>Belay counts the time it kept your Mac awake while you were away, when sleep could actually have interrupted the work.</td></tr>
<tr><td nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/speaks-up-dark.svg"><img src="docs/icons/speaks-up-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Speaks&nbsp;up</b></td><td>Optional notifications when an agent finishes, waits for you, or goes quiet – and one summary of what ran while you were away. Safety stops explain themselves too, including the lid hold ending because the Mac ran hot.</td></tr>
<tr><td nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/local-dark.svg"><img src="docs/icons/local-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Stays&nbsp;local</b></td><td>Agent detection stays on your Mac. No account, analytics or telemetry. Direct builds can check GitHub once a day for updates; you can turn that off.</td></tr>
<tr><td nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/multilingual-dark.svg"><img src="docs/icons/multilingual-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Multilingual</b></td><td>English, Русский, Deutsch, Español, Français, Italiano, 简体中文.</td></tr>
</table>

## 📦 Install

**1.** <a href="https://github.com/PerfectoWeb/Belay/releases/latest/download/Belay.dmg"><b>Download Now</b></a><sup><a href="https://github.com/PerfectoWeb/Belay/releases/latest"><img src="https://img.shields.io/github/v/release/PerfectoWeb/Belay?style=flat&label=&color=1f6bff" alt="latest version" align="middle" hspace="8"></a></sup> macOS 14 or later, Apple silicon and Intel, under 10 MB.

**2.** Open the disk image and drag **Belay** into Applications.

<picture><source media="(max-width: 768px) and (prefers-color-scheme: dark)" srcset="Promo/Social/dmg-window.png"><source media="(max-width: 768px)" srcset="Promo/Social/dmg-window-light.png"><source media="(prefers-color-scheme: dark)" srcset="Promo/Social/dmg-window-wide.png"><img src="Promo/Social/dmg-window-light-wide.png" alt="The Belay disk image: drag the app into Applications" width="100%"></picture>

**3.** That is the install. Launch it and it lives in the menu bar.

The app and the disk image are both signed with a Developer ID and **notarized
by Apple**, and both carry a stapled ticket, so the first launch works with no
network and without the right-click-Open dance.

<details>
<summary><b>Other ways to install</b></summary>

### 🍺 Homebrew

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

### 🍎 Mac App Store

[**Belay - Awake for AI Agents**](https://apps.apple.com/app/belay-awake-for-ai-agents/id6801207644),
free, macOS 14 or later. The sandboxed build, so it updates through the store
rather than through Sparkle and has no network access at all.

### 🔨 Build it yourself

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

### 📚 What is different between versions?

Belay ships in two builds that share the same app and the same detection. The Mac App Store build runs sandboxed with no network access at all; the direct build adds the few things a sandbox cannot do.

| Capability | App Store | Direct |
| :--- | :---: | :---: |
| Claude Code, Codex, Cline and Copilot CLI detection | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> |
| Idle sleep protection with fail-safe holds | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> |
| Presets and generic folder / process detection | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> |
| Watched folders for custom config dirs (`CLAUDE_CONFIG_DIR` and friends) | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> |
| Always On timer, by duration or end time | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> |
| Night dimming, statistics, CSV export | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> |
| Precise Detection (agent hooks) | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> |
| Local webhook for connecting any tool | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> |
| Closed-lid hold (privileged helper) | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture> |

</details>

## ☕️ Why not just caffeinate?
Caffeinate is great when you know exactly what process or command should keep the Mac awake.

**Belay is for the opposite workflow:** coding agents start, wait, resume and finish on their own. Belay follows that work state and releases the Mac automatically.

<table>
<tr><th>Features</th><th><img src="docs/logos/logo-caffeine.webp" width="24" height="24" align="middle" alt="">&nbsp;caffeinate</th><th><img src="docs/logos/logo-amphetamine.webp" width="24" height="24" align="middle" alt="">&nbsp;Amphetamine</th><th><img src="docs/logos/logo-belay.webp" width="24" height="24" align="middle" alt="">&nbsp;Belay</th></tr>
<tr><td>Keeps the Mac awake</td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td></tr>
<tr><td>Free</td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td></tr>
<tr><td>Timed sessions</td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td></tr>
<tr><td>Keeps awake while a given app or process runs</td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td></tr>
<tr><td>Lives in the menu bar</td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td></tr>
<tr><td>Battery safety limits</td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td></tr>
<tr><td>Knows when a coding agent is actually working</td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td></tr>
<tr><td>Lets go when the agent finishes or waits for you</td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td></tr>
<tr><td>Shows agent sessions and subagents live</td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td></tr>
<tr><td>Exact start / finish signals from agent hooks</td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td></tr>
<tr><td>Source available</td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/no-dark.svg"><img src="docs/icons/no-light.svg" width="18" alt="no"></picture></td><td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/check-dark.svg"><img src="docs/icons/check-light.svg" width="18" alt="yes"></picture></td></tr>
</table>

## 🚀 How to Use

**1. Launch it.** One welcome screen explains what Belay reads. Then it lives in
the menu bar. There is no Dock icon and no window.

**2. Leave it in Auto.** That is the whole product. Belay holds the Mac awake
while an agent is working and lets it sleep when nothing is.

<table>
<tr><th>Mode</th><th>What it does</th></tr>
<tr><td width="150" nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/auto-dark.svg"><img src="docs/icons/auto-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Auto</b> <i>(def)</i></td><td>Keeps your Mac awake while an agent is working</td></tr>
<tr><td width="150" nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/always-on-dark.svg"><img src="docs/icons/always-on-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Always On</b></td><td>Keeps it awake until you turn it off or by timer</td></tr>
<tr><td width="150" nowrap><sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/off-dark.svg"><img src="docs/icons/off-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;<b>Off</b></td><td>Belay stays out of the way</td></tr>
</table>

**3. Left-click the menu bar icon** for the panel: what is running, for how
long, and, when Belay is *not* holding, the reason in plain language.
Right-click for a compact menu.

<p align="center">
  <img src="Promo/Social/panel.png" alt="The Belay panel, showing four agents working and the Mac being held awake" width="94%">
</p>

**4. Want to verify it?** macOS can show the assertion Belay is holding:

```bash
pmset -g assertions | grep "pid $(pgrep -x Belay)("
```

You will see the assertion, a plain-English reason, and how long it has left.

> **Adding a tool Belay has never heard of** takes one line. If it can run a
> shell command, it can talk to Belay. See
> [`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md#talking-to-belay-from-anything).

## 🖼 Screenshots

<picture><source media="(max-width: 500px)" srcset="Promo/Social/shots/stack.png"><img src="Promo/Social/shots/grid.png" alt="Agents, Statistics, Behaviour and a multilingual interface" width="100%"></picture>


## 🧯 Troubleshooting

<details>
<summary><b>My Mac still went to sleep</b></summary>

Open the panel. It always says why in plain language. The usual answers are
the battery guard, the maximum awake time, or that Belay did not think anything
was running. If it is the last one and your agent *was* working, that is a bug
worth reporting: include the tool and the macOS version.

</details>

<details>
<summary><b>Can Belay work with the lid closed?</b></summary>

Out of the box, no: an idle-sleep assertion does not keep a MacBook awake with
the lid shut. macOS enters clamshell sleep unless the machine is on AC power
with an external display attached.

Since 1.3, the direct build can keep working with the lid closed as an opt-in.
Enable **Closed-lid hold** in Settings and approve the system helper when macOS
asks.

Belay lets go automatically when the work ends, the awake limit is reached,
or the Mac gets too warm.

The App Store build cannot install a privileged helper (that is Apple's rule,
and a good one), so it does not offer the switch.

</details>

<details>
<summary><b>My screen still turns off</b></summary>

That is intentional and saves real power. Belay prevents *system* sleep; the
machine underneath keeps working. There is a setting to keep the display awake
too, off by default – and since 1.3, one to dim it to a glow at night while
it is kept awake, so a screen held for an overnight run does not light an
empty room. It brightens back the moment you return.

</details>

<details>
<summary><b>Belay does not see my agent</b></summary>

Claude Code, Codex, Cline and Copilot CLI need no setup, and if yours runs
from a custom config folder or a second profile, add that folder from the
agent's own settings. Everything else is configured in **Settings ▸ Agents**:
switch on a preset – Gemini CLI, OpenCode, Aider, Cline (VS Code) and Pi ship
ready-made – or point Belay at a folder or process your tool uses while it
works.

In the direct build, tools that can run a shell command can also talk to Belay
directly. See
[`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md#talking-to-belay-from-anything).

</details>

<details>
<summary><b>It says "needs setup"</b></summary>

Since 1.3.2 the badge says which case you are in: a folder that does not exist
yet simply has not been created by the tool (it appears after the first run),
and only a folder that exists but cannot be read is an access question.
Presets are configuration, not code, so open Settings ▸ Agents and correct
the path if yours lives elsewhere.

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

⭐ **[Star it](https://github.com/PerfectoWeb/Belay)**. It costs nothing and
helps other people find it.

🐛 **[Report a bug](https://github.com/PerfectoWeb/Belay/issues/new)**. The
macOS version and the agent you were running are what make a report actionable.

🌍 **[Fix a translation](Localization/)**. One CSV per language, this is the 
most wanted contribution here.

🔌 **[Add a preset](docs/CONTRIBUTING.md)** for an agent Belay does not know yet.
Also data, also no need to learn the codebase.

💛 **[Donate](https://perfecto-web.com/d/)**. Last on the list on purpose.

> Start at [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md). Security reports go through
[`docs/SECURITY.md`](docs/SECURITY.md), not the issue tracker.

### 📖 Documentation

<table>
<tr><td width="24%"><a href="docs/HOW-IT-WORKS.md">How it works</a></td><td>Detection, the safety rails and talking to Belay from anything</td></tr>
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

<sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/nosell-dark.svg"><img src="docs/icons/nosell-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;**You may not sell it.** Not the app, not a derivative, not access to it. Use
is free and stays free for everyone, including at work and for commercial work.
What is forbidden is charging other people for it.

<sup><picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/copyright-dark.svg"><img src="docs/icons/copyright-light.svg" width="18" align="middle" hspace="5" alt=""></picture></sup>&nbsp;**Credit the original.** Anything built on Belay has to say so where its users
can see it: *Belay by PerfectoWeb*, with a link back here.

The **name and the mark** are covered separately.
[`docs/TRADEMARKS.md`](docs/TRADEMARKS.md) explains what that does and does not
stop you doing.

Belay shows each tool's own logo in the sessions list so you can tell at a
glance which agent is working. All product names, logos and trademarks are the
property of their respective owners, used only to identify those products, and
imply no affiliation or endorsement. See [`NOTICE.md`](NOTICE.md).

<div align="center">
<br>
<sub>Built for people who leave their agents running and go and do something else.</sub>
</div>
