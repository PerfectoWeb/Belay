- **Copilot CLI is now built in.** Turn it on in Settings and Belay follows Copilot sessions on its own — reading its own turn markers, so starts and finishes are exact. Four agents, zero setup.
- **Watch an agent in any folder.** Custom config dirs (`CLAUDE_CONFIG_DIR`, `CODEX_HOME` and friends) and multi-profile setups: open an agent's settings and add every folder it works in. Belay even suggests sibling profiles it finds next to the default home, and Precise Detection covers each watched folder. Fixes #4.
- **The timer survives a relaunch.** An Always On timer picks up exactly where it was when Belay restarts — an expired one lands honestly in the pause with Hold Again.
- **Steadier everywhere.** A full audit of the codebase fixed dozens of faults: a crash a local process could trigger, main-thread stalls at launch and in Settings, sessions that outlived their agents, an awake limit that counted the Mac's own sleep, and more. Every fix landed with a regression test.

Also: agent tiles show live last-activity, switched-off tiles dim as one piece, the About footer now says what the licence means ("Free & open code"), and a round of small interface polish throughout.
