- **Precise Detection reconnects automatically.** If the local bridge drops, Belay reconnects and updates agent hooks. No relaunch needed.

- **Back-to-back tool calls keep the hold.** A late return from one call no longer cancels the hold for the next.

- **Watched Cline sessions end properly.** Sessions under `/tmp` or `/var` now disappear when their state files are deleted.

- **Imported conversations stay quiet.** Old conversations touched during an import no longer appear as active.

- **One summary when you return.** Belay shows how long it kept your Mac awake and how many runs finished. Statistics now also includes a sortable list of your 50 most recent sessions, with folder names only.

- **A few rough edges are fixed.** Statistics no longer flicker on hover, past Until times no longer schedule tomorrow, timer sheets stay put, and diagnostics remain fully off when Local Reports is off.