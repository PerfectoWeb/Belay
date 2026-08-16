"""Rewrites an appcast's enclosure URLs to GitHub's per-tag release paths.

    python3 retag-appcast.py appcast.xml https://github.com/OWNER/REPO/releases/download/

`generate_appcast` builds every enclosure as prefix + filename, which suits a
directory of files on a plain web server. GitHub is not that: each release asset
lives under its own tag, so `Belay-1.2.0.dmg` is served from `.../download/
v1.2.0/Belay-1.2.0.dmg`.

The version is already in the file name, so the tag is read from it rather than
guessed. Anything that does not match the expected shape is left exactly as it
was and named on the way out: an appcast whose links 404 fails at the worst
possible moment, on somebody else's machine, halfway through an update.
"""

import io
import re
import sys


def main(path, prefix):
    xml = io.open(path, encoding="utf-8").read()
    missed = []

    def retag(match):
        url = match.group(1)
        if not url.startswith(prefix):
            return match.group(0)
        name = url[len(prefix):]
        # Already under a tag. Running this twice used to produce
        # `.../download/v1.2.0/v1.2.0/Belay-1.2.0.dmg`, which 404s at the moment
        # somebody tries to update.
        if re.match(r"^v\d", name):
            return match.group(0)
        version = re.search(r"-(\d+\.\d+(?:\.\d+)?)\.(?:dmg|zip)$", name)
        if not version:
            missed.append(url)
            return match.group(0)
        return match.group(0).replace(url, f"{prefix}v{version.group(1)}/{name}")

    xml = re.sub(r'url="([^"]+)"', retag, xml)

    # Nothing is written when anything was missed. The first version of this
    # wrote the file and *then* reported failure, so an aborted publish left a
    # half-rewritten appcast on disk for the next run to build on.
    if missed:
        for url in missed:
            print(f"  no version in the file name: {url}")
        print("  nothing was written")
        return 1

    io.open(path, "w", encoding="utf-8").write(xml)
    print(f"  {len(re.findall(r'releases/download/v', xml))} enclosures carry a tag")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
