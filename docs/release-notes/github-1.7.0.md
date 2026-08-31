- **The panel shows what agents are doing.** Small capsule badges beside each working session – shell, editing, search, bg task – built from the tool names the agent's own hooks report. Two at most, the rest a "+N"; categories only, never arguments, so a badge cannot leak a prompt or a path. Toggle in Settings → Behavior.

- **Background tasks keep the hold.** A turn that ends with monitors or shell jobs still running used to drift to Idle five minutes later while the IDE still showed a running task. It now holds the Mac awake – bounded by a thirty-minute budget, because no later hook can confirm the claim – and the panel says which kind of alive the session is.

- **Hooks tidy up after themselves.** Belay's entries leave `settings.json` on quit and return on launch, so an agent used while Belay is closed posts to nothing instead of filling its terminal with `ECONNREFUSED`. Settings backups now rotate at twenty.

- **Sharper returns.** Closing the lid is an input event, so the while-you-were-away summary used to fire into a closing lid and the real return got nothing – fixed. The summary also mentions when the Mac ran hot, in `ProcessInfo`'s own words.

- **Quieter diagnostics.** Dark wakes no longer log as main-thread stalls, two sessions trading turns no longer write a "hold on" line every few seconds, and a chronic helper error is rate-limited to one line in forty.
