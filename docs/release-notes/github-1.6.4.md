- **Precise Detection reconnects itself.** If the local bridge drops during sleep or at runtime, Belay now reconnects automatically and updates the agent hooks. No relaunch needed.

- **Back-to-back tool calls keep the hold.** Rapid tool activity no longer lets a late return from one call cancel the hold for the next.

- **Watched Cline sessions end properly.** Sessions under `/tmp` or `/var` now disappear when their state files are deleted.

- **Imported conversations stay quiet.** Old conversations touched during an import no longer appear as active sessions.

- **One summary when you come back.** If Belay held the Mac awake while you were away, returning brings a single notification: how long it held and how many runs finished. The statistics pane also gains a recent-sessions list – agent, folder, duration – capped at twelve, folder names only.

- **A few rough edges are fixed.** Statistics no longer flicker on hover, past Until times no longer schedule tomorrow, custom timer sheets stay put, and diagnostics remain fully off when Local Reports is off.