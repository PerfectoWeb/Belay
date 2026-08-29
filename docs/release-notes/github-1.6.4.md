- **Precise Detection heals itself.** The bridge's retry machinery only existed at launch, so a listener that died at runtime – sleep/wake being the known way – left it silently down until relaunch while the hooks kept posting to a dead port. It now retries the same ladder, falls back to a slow loop, and repoints the hooks on every rebind.

- **Back-to-back tool calls keep their bracket.** Async hook delivery could land tool N's return just after tool N+1's start and wipe the bracket protecting a half-hour build. A return arriving within two seconds of an open now reads as the previous call's; Stop still closes unconditionally.

- **Watched-folder Cline sessions end properly.** FSEvents reports deletions under `/tmp`/`/var` with a `/private` prefix the resolver only strips from living paths, so a deleted session outlived its own state file.

- **Imported conversations stay quiet.** A rollout caught empty at `creat` used to route its first real bytes around the stale-record check, raising month-old conversations as working rows.

- **Small things, straightened.** The statistics caption no longer flickers under the cursor; an Until time that has already passed starts nothing instead of booking a day; the custom-duration sheet can no longer be taken down by its own popover; and `killall Belay` writes nothing for users who never enabled Local Reports.
