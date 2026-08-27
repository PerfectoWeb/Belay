"""The numbers under the hero, as they were when the site was last built.

Written by `.github/workflows/site-stats.yml`, which counts the release
assets on GitHub and rewrites this file on a schedule. Baked rather than
fetched for the same reason as VERSION: a visitor should not wait on
api.github.com, and a counter that only appears when a request succeeds is
worse than one that is simply true.

APPSTORE is None until an App Store Connect key with a reports role exists.
Apple publishes downloads once a day, never live, so the pair is honest only
as "as of the last build" — which is what the page says.
"""

DIRECT = 309
APPSTORE = None
RELEASES = 12
FIRST_COMMIT = "2026-08-11"
