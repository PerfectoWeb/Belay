- **Auto Allow in Codex.** Direct build only. Now clicks "Allow once" in the ChatGPT desktop app too. By default, approves only requests for sites on your Mac or local network, using the request's site link. Commands that merely mention `localhost` still need your approval. Supports Codex's interface languages and background sessions. Works when Codex is enabled in Settings › Agents.

- Auto Allow no longer mistakes embedded web pages in Claude or Codex for permission requests.

- **Nudge**, a new module for both builds. Plays a sound when an agent finishes, needs you, or goes quiet. Choose which sounds to play, plus the interval and number of reminders while an agent waits. Completion notifications can include the workspace name. Click a notification to bring the session's app, terminal, or editor to the front.

- **Orphan Watch**, a new module for both builds. Shows processes left running after a session ends, such as dev servers or MCP servers. Also flags sustained high CPU use while an agent is idle. Reads process metadata, never command lines or file contents. In the direct build, "End" and "End All" request termination after you confirm. Nothing is stopped automatically.

- Auto Allow returns you to your previous app after checking a background session, unless you've started using your Mac.

- With Precise Detection on, Auto Allow checks background Claude sessions only during a tool call. This avoids opening sessions unnecessarily after a turn ends.

- Precise Detection now finds Codex in ChatGPT 26.928's new `codex-cli` folder. If setup failed with "no codex binary was found", turn Codex off and on in Settings › Agents after updating Belay. Belay also checks trust for its hooks at launch and restores it when needed.

- Modules are easier to scan, with distinct colors, shorter summaries, and icons that animate on hover.
