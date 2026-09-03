"""The numbers under the hero, as they were when the site was last built.

Written by `.github/workflows/site-stats.yml`, which counts the release
assets on GitHub and rewrites this file on a schedule. Baked rather than
fetched for the same reason as VERSION: a visitor should not wait on
api.github.com, and a counter that only appears when a request succeeds is
worse than one that is simply true.

APPSTORE counts installs — Apple's F1 (first download) plus F3 (re-download),
never F7, which is an update and not somebody getting the app. Apple publishes
it once a day and finalises it a day later, so the pair is honest only as "as
of the last build", which is what the page says.
"""

DIRECT = 436
APPSTORE = 187
RELEASES = 16
COMMITS = 480
STARS = 32
FIRST_COMMIT = "2026-08-11"
DIRECT_UPDATED = "2026-09-03"
APPSTORE_UPDATED = "2026-09-02"
