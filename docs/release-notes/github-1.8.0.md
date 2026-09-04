- **See stats for each project.** Open any session in Statistics to see that folder’s total agent time, sessions, tokens, and recent runs. Project totals stay intact even as older sessions roll off the list.

- **Sessions shows the bigger picture.** The headline now shows total agent time across all folders, and the list keeps the latest 100 sessions.

- **Background tasks hold more reliably.** Late or duplicate Stop events no longer end a newer hold or restart one that already finished.

- **Hooks recover after an interrupted quit.** If Belay is killed while closing, it restores any missing agent settings on the next launch.

- **The diagnostics log stays small.** Once it passes 3 MB, Belay trims it back to the most recent 1 MB.

- **Night dimming respects a video.** The screen no longer dims while another app is keeping the display awake (a fullscreen video, a call, a presentation), and it comes back if one starts mid-dim.

- **One ask, once.** After Belay has held your Mac through an hour of your absence, the panel asks for a GitHub star (or an App Store review in the store build), with the number it earned it by. Either answer ends it for good.

Also: more regression coverage for background tasks, activity badges, hook categories, Cline cleanup, and per-folder totals.
