# Social artwork

Hand-drawn, and that is the point: there is no generator for anything in here
any more. `scripts/make-social.swift` used to render the masthead, the Open
Graph card and the buttons, and it was deleted once they were redrawn by hand.
It had become a loaded gun — running it overwrote the real artwork with its own
older idea of it, which is exactly what happened once.

| File | Where it is used |
|---|---|
| `masthead-2x.png` | The top of `README.md`, on a wide screen |
| `masthead-2x-mobile.png` | The same, under 500 px |
| `masthead.png` | The 1x masthead, kept as a source |
| `og.png` | The card GitHub, Slack and iMessage unfurl. Set under Settings, General, Social preview |
| `btn-download.png` | The download button. One file: it reads on both GitHub themes |
| `btn-site-dark.png`, `btn-site-light.png` | The Learn More button, one per theme, swapped with `<picture>` |
| `btn-download-green.png` | Not used yet. Kept for the day the download button changes colour |
| `panel.png` | The annotated panel, in How to Use |
| `dmg-window.png`, `dmg-window-wide.png` | The disk image, in Install. The wide one carries transparent margins so one width serves both screens |
| `shots/grid.png`, `shots/stack.png` | Screenshots, two by two on a wide screen and stacked under 500 px |
| `spacer.png` | One transparent pixel. GitHub strips `style`, so a sized spacer image is the only way to add an exact gap |

Two rules worth keeping. Rounded corners have to be baked into the file, because
GitHub removes a `border-radius` written in the README. And anything that has to
change with the screen or the theme goes through `<picture>`, which is the one
responsive tool the sanitiser leaves alone.
