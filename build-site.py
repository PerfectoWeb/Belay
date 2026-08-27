#!/usr/bin/env python3
"""Builds the whole site: every language, two pages each, plus the redirects.

    python3 build-site.py .

Layout. The language is the first path segment, so every page has the same
shape and a seventh page or a seventh language is not a special case:

    /en/  /en/privacy/        /ru/  /ru/privacy/   … and so on

The root is a redirect stub. GitHub Pages serves static files and has no
server-side redirects, so it is done in the page: a script reads the browser's
preferred languages and replaces the location with one we have, and a
<noscript> meta refresh sends everyone else to English. That is the only script
on the site, it renders nothing, and it decides which door rather than what is
behind it. The privacy policy itself never depends on JavaScript running.

/privacy/ and /privacy/<lang>/ are kept as redirect stubs because those
addresses are already out in the world: the published 1.0.0 release notes link
to /privacy/, and a link somebody saved should not answer 404 because we moved
some folders.
"""

import datetime
import hashlib
import io
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from landing import L, VERSION
from stats import (
    APPSTORE as STATS_APPSTORE,
    DIRECT as STATS_DIRECT,
    FIRST_COMMIT,
    RELEASES as STATS_RELEASES,
)
from policy_text import LANGUAGES, T

CODES = [code for code, _, _ in LANGUAGES]

# What the markup declares, which is not always what the path is called. They
# match everywhere but Chinese: the path stays two letters because the root
# redirect matches on the first two of the browser's tag, while the language
# itself is a script rather than a country.
TAG = {code: tag for code, _, tag in LANGUAGES}

# False until the listing is approved: a button pointing at a page that does not
# exist is worse than no button. True since 17 Aug 2026.
APP_STORE_LIVE = True
APP_STORE_URL = "https://apps.apple.com/app/id6801207644"

# Flip when GitHub Sponsors is enabled on the account. Same reasoning.
SPONSORS_LIVE = False
SPONSORS_URL = "https://github.com/sponsors/PerfectoWeb"
# Drawn into the buttons rather than fetched. `currentColor` throughout, so a
# mark never has to be re-exported when a button changes colour or theme.
APPLE_MARK = (
    '<svg class="mark" viewBox="0 0 384 512" aria-hidden="true" fill="currentColor">'
    '<path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7'
    '-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9'
    '31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5'
    '-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/></svg>'
)

APPSTORE_MARK = (
    '<svg class="mark" viewBox="0 0 583 515" aria-hidden="true"'
    ' fill="currentColor"><path d="M290 46.36L306.2 18.36C316.2 0.860035 338.5 -5.03997 356 4.96003C373.5 14.96 379.4 37.26 369.4 54.76L213.3 324.96H326.2C362.8 324.96 383.3 367.96 367.4 397.76H36.4C16.2 397.76 0 381.56 0 361.36C0 341.16 16.2 324.96 36.4 324.96H129.2L248 119.06L210.9 54.66C200.9 37.16 206.8 15.06 224.3 4.86003C241.8 -5.13997 263.9 0.760029 274.1 18.26L290 46.36ZM149.6 435.26L114.6 495.96C104.6 513.46 82.3 519.36 64.8 509.36C47.3 499.36 41.4 477.06 51.4 459.56L77.4 414.56C106.8 405.46 130.7 412.46 149.6 435.26ZM451 325.16H545.7C565.9 325.16 582.1 341.36 582.1 361.56C582.1 381.76 565.9 397.96 545.7 397.96H493.1L528.6 459.56C538.6 477.06 532.7 499.16 515.2 509.36C497.7 519.36 475.6 513.46 465.4 495.96C405.6 392.26 360.7 314.66 330.9 262.96C300.4 210.36 322.2 157.56 343.7 139.66C367.6 180.66 403.3 242.56 451 325.16Z"/></svg>'
)

GITHUB_MARK = (
    '<svg class="mark" viewBox="0 0 16 16" aria-hidden="true" fill="currentColor">'
    '<path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49'
    '-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66'
    '.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82'
    '.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95'
    '.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z"/></svg>'
)

# The two sparks in the corner of the download button, as on the README's own.
# One path per sparkle and a class on each, so the two can turn on their own.
# Animating the group rotated them as one object, which is not what two sparkles
# side by side should do.
SPARKLE = (
    '<svg class="spark" viewBox="0 0 24 24" aria-hidden="true" fill="currentColor">'
    '<path class="big" d="M15 2l1.4 4.1L20.5 7.5 16.4 8.9 15 13l-1.4-4.1L9.5 7.5l4.1-1.4z"/>'
    '<path class="small" d="M7.5 13l.9 2.6 2.6.9-2.6.9-.9 2.6-.9-2.6L4 16.5l2.6-.9z"/></svg>'
)

DOWNLOAD_MARK = (
    '<svg class="mark alt" viewBox="0 0 24 24" aria-hidden="true" fill="none"'
    ' stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M12 3v12"/><path d="M6.5 10.5 12 16l5.5-5.5"/><path d="M4 20h16"/></svg>'
)

# Six sparks, each with where it starts across the button, how big it is, how far
# it rises, how long it takes and when it begins. Written out rather than
# generated so the pattern is the same on every page and can be looked at.
SPARK_BED = (
    '<span class="sparks" aria-hidden="true">'
    '<i style="--x: 14%; --size: 6px; --rise: 30px; --dur: 2.4s; --delay: 0s"></i>'
    '<i style="--x: 31%; --size: 4px; --rise: 22px; --dur: 3.1s; --delay: 0.7s"></i>'
    '<i style="--x: 47%; --size: 7px; --rise: 34px; --dur: 2.7s; --delay: 1.5s"></i>'
    '<i style="--x: 63%; --size: 3px; --rise: 25px; --dur: 3.6s; --delay: 0.3s"></i>'
    '<i style="--x: 78%; --size: 5px; --rise: 28px; --dur: 2.2s; --delay: 1.1s"></i>'
    '<i style="--x: 92%; --size: 4px; --rise: 20px; --dur: 3.9s; --delay: 2s"></i>'
    '</span>'
)

DONATE_URL = "https://perfecto-web.com/d/"

GITHUB = ('<svg class="glyph" viewBox="0 0 16 16" aria-hidden="true">'
          '<path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38'
          ' 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53'
          '.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95'
          ' 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2'
          ' .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65'
          ' 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42'
          '-3.58-8-8-8Z"/></svg>')

STAR = ('<svg class="glyph" viewBox="0 0 16 16" aria-hidden="true">'
        '<path fill="currentColor" d="M8 1.4l1.9 4 4.4.6-3.2 3.1.8 4.4L8 11.4l-3.9 2.1'
        ' .8-4.4L1.7 6l4.4-.6z"/></svg>')


HEART = ('<svg class="glyph" viewBox="0 0 16 16" aria-hidden="true">'
         '<path fill="currentColor" d="M8 14.25S1.5 10.5 1.5 5.94A3.44 3.44 0 0 1 8 4.2a3.44 3.44 0 0 1 6.5'
         ' 1.74C14.5 10.5 8 14.25 8 14.25Z"/></svg>')


# The real lockup from Resources/Brand, not a redrawing of it: the file is read
# here and taken apart, so the drawing has one home and this is not a second
# copy of it that can drift.
#
# It goes into the page inline rather than through <img>, because the three
# stars turn on three different centres and a stylesheet cannot reach inside an
# image. One copy now serves both themes: the letters take `currentColor`, so
# the theme sets them the way it sets every other piece of text, and the mark
# keeps its blue in both because that is the product's colour, not the page's.
BRAND = os.path.join(os.path.dirname(os.path.abspath(__file__)), "brand",
                     "belay-wordmark-dark.svg")

# The three stars in the order the file draws them, which is not the order of
# their size: middle, large, small.
STARS = ["star-mid", "star-big", "star-small"]


def _attr(tag, name):
    found = re.search(rf'{name}="([^"]*)"', tag)
    if not found:
        raise SystemExit(f"{BRAND}: no {name} where one is required")
    return found.group(1)


def wordmark():
    """The lockup as inline SVG, with each star its own element.

    The shape of the file is asserted rather than assumed. If the brand asset
    is ever redrawn with a different number of paths, this stops the build
    instead of quietly shipping a lockup with the wrong pieces moving.
    """
    svg = io.open(BRAND, encoding="utf-8").read()
    box = _attr(svg, "viewBox")
    paths = re.findall(r"<path\b[^>]*?/>", svg)
    if len(paths) != 2:
        raise SystemExit(f"{BRAND}: expected two paths, found {len(paths)}")
    letters, mark = paths

    stars = [d for d in re.split(r"(?=M)", _attr(mark, "d")) if d]
    if len(stars) != len(STARS):
        raise SystemExit(f"{BRAND}: expected three stars, found {len(stars)}")

    lines = [
        f'<svg class="mark" viewBox="{box}" width="129" height="48.52"'
        ' role="img" aria-label="Belay">',
        f'        <path fill="currentColor"'
        f' transform="{_attr(letters, "transform")}" d="{_attr(letters, "d")}"/>',
        f'        <g fill="{_attr(mark, "fill")}" transform="{_attr(mark, "transform")}">',
    ]
    lines += [f'            <path class="{name}" d="{d}"/>'
              for name, d in zip(STARS, stars)]
    lines += ["        </g>", "    </svg>"]
    return "\n".join(lines)


# Appended to the stylesheet link so that a reader who has the old one gets the
# new one on their next visit. It is the file's own hash rather than a counter or
# a date: the address changes when the bytes change and not one build sooner, so
# a rebuild that touched nothing leaves every cache intact. Every script on this
# site is inline in the page it belongs to, and a page is revalidated anyway, so
# the stylesheet is the only file that needs this.
# Cloudflare Web Analytics, on every page except the privacy policy. Cookieless
# and stores nothing on the visitor's machine, which is why this site carries no
# consent banner; what it records is spelled out in the policy itself, in every
# language. A beacon on the page that promises nobody is watching would be
# an embarrassing thing to serve, which is the rule the stylesheet already
# follows about fonts.
ANALYTICS_TOKEN = "8999ea5c44b046c19a08dcf09d5b4336"

STYLE_STAMP = ""
TEMPLATE = None

# The same treatment for the social card, and for a sharper reason: Slack,
# iMessage, X and Facebook each keep their own copy of whatever was at this
# address the first time somebody posted it. Changing the address is the only way
# to make them fetch the new one.
OG_STAMP = ""


def head(code, title, meta, depth, page):
    """`depth` is how far this file sits below the site root."""
    up = "../" * depth
    lines = [
        "<!doctype html>",
        f'<html lang="{TAG[code]}">',
        "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        f"<title>{title}</title>",
        f'<meta name="description" content="{meta}">',
        f'<link rel="canonical" href="https://perfectoweb.github.io/Belay/{code}/{page}">',
        f'<link rel="stylesheet" href="{up}style.css{STYLE_STAMP}">',
    ]
    if page != "privacy/" and ANALYTICS_TOKEN:
        # Loaded rather than declared, so a blocker or a dead network is a
        # branch we handle instead of an unhandled failure. The browser still
        # notes the blocked request itself — no page can silence that — but
        # nothing of ours is left broken behind it.
        lines += [
            "<script>",
            "(function(){",
            "  var b=document.createElement('script');",
            "  b.src='https://static.cloudflareinsights.com/beacon.min.js';",
            "  b.defer=true;",
            f"  b.setAttribute('data-cf-beacon','{{\"token\":\"{ANALYTICS_TOKEN}\"}}');",
            "  b.onerror=function(){};",
            "  document.head.appendChild(b);",
            "})();",
            "</script>",
        ]
    lines += [
        # The icons. Paths are relative on purpose: this site lives under
        # /Belay/, so a root-absolute `/favicon.ico` would point at the domain
        # root, which is not ours. Declaring them explicitly is also what stops
        # the browser probing that root and logging the 404 that started this.
        #
        # Four links is the whole modern set. The SVG is what a current browser
        # picks, the .ico carries 16, 32 and 48 for everything older and for
        # Windows, the Apple one is opaque because iOS ignores transparency, and
        # the manifest holds the 192, 512 and maskable rasters for Android.
        f'<link rel="icon" href="{up}favicon.ico" sizes="32x32">',
        f'<link rel="icon" href="{up}icon.svg" type="image/svg+xml">',
        f'<link rel="apple-touch-icon" href="{up}apple-touch-icon.png">',
        f'<link rel="manifest" href="{up}manifest.webmanifest">',
        '<meta name="theme-color" content="#ffffff" media="(prefers-color-scheme: light)">',
        '<meta name="theme-color" content="#0d1016" media="(prefers-color-scheme: dark)">',
        # Open Graph. Without these a link to this page unfurls in Slack,
        # iMessage, Discord and X as a bare URL, which is what it did for the
        # whole of 1.0. The card is 1280x640, rendered by
        # scripts/make-social.swift in the app's repository.
        '<meta property="og:type" content="website">',
        f'<meta property="og:title" content="{title}">',
        f'<meta property="og:description" content="{meta}">',
        f'<meta property="og:url" content="https://perfectoweb.github.io/Belay/{code}/{page}">',
        f'<meta property="og:image" '
        f'content="https://perfectoweb.github.io/Belay/img/og.png{OG_STAMP}">',
        '<meta property="og:image:width" content="1280">',
        '<meta property="og:image:height" content="640">',
        '<meta property="og:site_name" content="Belay">',
        '<meta name="twitter:card" content="summary_large_image">',
        # Who made it. `rel="author"` is the machine-readable half and points at
        # the site rather than at a profile page, which is the only address that
        # will still be right in two years.
        '<meta name="author" content="PerfectoWeb">',
        '<meta name="copyright" content="PerfectoWeb">',
        '<link rel="author" href="https://perfecto-web.com">',
    ]
    for other in CODES:
        href = f"https://perfectoweb.github.io/Belay/{other}/{page}"
        lines.append(f'<link rel="alternate" hreflang="{TAG[other]}" href="{href}">')
    lines.append(
        '<link rel="alternate" hreflang="x-default" '
        f'href="https://perfectoweb.github.io/Belay/en/{page}">')
    if page != "privacy/":
        lines += structured_data(code, meta)
    lines += ["</head>", "<body>", '<div class="wrap">', ""]
    return lines


def structured_data(code, meta):
    """What the app is, in the vocabulary search engines read.

    Only facts that are already on the page: the name, the platform, the
    price, the licence and the current version. No rating — the app has no
    reviews to average, and an invented one is the kind of thing that gets a
    site's markup ignored entirely.
    """
    facts = {
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": "Belay",
        "applicationCategory": "DeveloperApplication",
        "operatingSystem": "macOS 14.0 or later",
        "description": meta,
        "url": f"https://perfectoweb.github.io/Belay/{code}/",
        "downloadUrl": "https://github.com/PerfectoWeb/Belay/releases/latest",
        "softwareVersion": VERSION,
        "inLanguage": TAG[code],
        "isAccessibleForFree": True,
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        "author": {
            "@type": "Organization",
            "name": "PerfectoWeb",
            "url": "https://perfecto-web.com",
        },
        "license": "https://github.com/PerfectoWeb/Belay/blob/main/LICENSE",
        "screenshot": f"https://perfectoweb.github.io/Belay/img/og.png{OG_STAMP}",
    }
    return [
        '<script type="application/ld+json">',
        json.dumps(facts, ensure_ascii=False, separators=(",", ":")),
        "</script>",
    ]


def header(code, depth):
    up = "../" * depth
    return [
        "<header>",
        f'    <a href="{up}{code}/">{wordmark()}</a>',
        "</header>",
        "",
    ]


def language_picker(code, depth, label, page):
    """A disclosure, not a select. It needs no script, it is reachable from the
    keyboard, and it stays shut until someone wants it."""
    up = "../" * depth
    links = []
    for other in CODES:
        name = dict((c, n) for c, n, _ in LANGUAGES)[other]
        if other == code:
            links.append(f'<span class="here">{name}</span>')
        else:
            links.append(f'<a href="{up}{other}/{page}">{name}</a>')
    return [
        '    <details class="languages">',
        f'        <summary>{label}<svg class="chevron" viewBox="0 0 12 8" aria-hidden="true">'
        '<path fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" '
        'stroke-linejoin="round" d="M1 2.2 6 6.6 11 2.2"/></svg></summary>',
        '        <nav>' + " ".join(links) + "</nav>",
        "    </details>",
    ]


def external(markup):
    """Adds target and rel to every off-site link in a built line.

    Done here rather than at each call site because there are eleven of them
    and the eleventh is the one somebody forgets. `noopener` is not optional:
    without it the page being opened gets a handle back to this one.
    """
    return re.sub(
        r'<a ((?:class="[^"]*" )?href="https?://(?!perfectoweb\.github\.io)[^"]+")',
        r'<a \1 target="_blank" rel="noopener"', markup)




# The App Store slides, which is where these pictures already exist and are
# already translated. Linked to the repository rather than copied here, so there
# is one place to change them: edit `Promo/AppStore/` in the Belay repo and every
# page follows on the next hard refresh.
#
# Five of the six. The sixth asks for a rating on the Mac App Store, which is the
# right thing to say inside the store and the wrong thing to say on a page whose
# own download button is two sections up.
# Served from this site as WebP rather than fetched from the repository as PNG.
# The whole slide set, every language included, is 77 MB of PNG and 9.8 MB of WebP, and
# a reader was pulling six of the PNGs, about 11 MB, to look at one picture.
#
# The path is relative and assumes the gallery only ever appears one level down,
# which is where the landing page lives. It is the only page with a gallery.
SLIDE_SOURCE = "../img/slides"
# Zero is the panel that was here before the gallery, kept as the first frame;
# one to five are the App Store slides.
SLIDE_FIRST = 0
SLIDE_COUNT = 5

# The slides were named before the site was, and Spanish disagrees: the files say
# `sp` and every locale code here says `es`. Mapped rather than renamed, because
# the files are also what App Store Connect was fed from.
SLIDE_CODE = {"es": "sp"}

# Languages whose slide zero does not exist. Empty since 17 Aug 2026, when the
# Chinese one was drawn; kept because the next language added will need it before
# its slides are done, and pointing at a missing file shows a broken frame while
# borrowing English shows the wrong language.
SLIDE_ZERO_MISSING = set()


def slides(code):
    """Every slide for this language, in order, as absolute URLs."""
    name = SLIDE_CODE.get(code, code)
    first = 1 if code in SLIDE_ZERO_MISSING else SLIDE_FIRST
    return [
        f"{SLIDE_SOURCE}/belay-appimage-{name}-{n}.webp"
        for n in range(first, SLIDE_COUNT + 1)
    ]


def gallery(code, t):
    """The App Store slides for this language, with dots and two click zones.

    Enhanced rather than required. With no JavaScript this is the first slide and
    nothing else: the rest are hidden by the stylesheet, the dots are hidden, and
    what remains is one picture, which is what this section was before. That is
    the same rule the disclosure above follows.

    Only the first slide has a `src`. The rest carry `data-src` and are given a
    real one the first time they are needed, which the script does on the way to
    showing them.

    `loading="lazy"` was the obvious answer and does nothing here: the frames are
    stacked in one grid cell and differ only in opacity, so every one of them is
    in the viewport as far as the browser is concerned, and all six were fetched
    on load. Holding the address back is the only thing that actually defers it.
    """
    lines = ['<div class="gallery" data-gallery>', '    <div class="frames">']
    for index, url in enumerate(slides(code)):
        on = " is-on" if index == 0 else ""
        where = f'src="{url}"' if index == 0 else f'data-src="{url}"'
        lines.append(
            f'        <img class="frame{on}" {where} '
            f'alt="{t["modes_head"]}" width="2880" height="1800" decoding="async">')
    lines += ['    </div>']
    # The left and right fifths of the picture, transparent, pointer cursor.
    # Buttons rather than divs so a keyboard reaches them.
    lines += [
        f'    <button class="turn back" type="button" data-step="-1"'
        f' aria-label="{t["gallery_back"]}"></button>',
        f'    <button class="turn next" type="button" data-step="1"'
        f' aria-label="{t["gallery_next"]}"></button>',
        '    <div class="dots" role="tablist">',
    ]
    for index in range(len(slides(code))):
        lines.append(
            f'        <button class="dot{" is-on" if index == 0 else ""}" type="button"'
            f' role="tab" data-to="{index}"'
            f' aria-selected="{"true" if index == 0 else "false"}"'
            f' aria-label="{t["gallery_dot"].format(n=index + 1)}"></button>')
    lines += ['    </div>', '</div>']
    return lines



def typed_heading(text):
    """A heading that types itself, one letter at a time, with a cursor.

    Each letter is its own span carrying its index; the stylesheet turns the
    index into a delay. The letters are `display: none` until their turn, not
    merely transparent, so the cursor after them advances as the words appear:
    hidden letters that still take up space would leave the cursor sitting at
    the end from the first frame.

    Spaces become non-breaking, because a `display: none` run of letters either
    side of an ordinary space collapses it and the words jump together as they
    arrive.

    It starts when the heading is scrolled into view rather than on load; that is
    the one line of script this needs, and without the script the heading is
    simply there, which is the same bargain the gallery and the disclosure make.
    """
    out = []
    for index, letter in enumerate(text):
        shown = "&#160;" if letter == " " else letter
        out.append(f'<span class="ch" style="--ch: {index}">{shown}</span>')
    return "".join(out) + '<span class="caret" aria-hidden="true"></span>'


def filled_heading(text):
    """The h1, one span per word, each carrying its place in the order.

    The animation lives in the stylesheet; this only supplies the words and the
    index.

    Tags are stepped over rather than split on. The English headline carries a
    `<br class="turn">` in the middle of it, and splitting the whole string on
    spaces tore that into `<br` and `class="turn">while`, which is broken markup
    that a browser then guesses at. Anything inside angle brackets is passed
    through untouched and takes no delay of its own.

    A language with no spaces between words, Chinese here, comes out as one or
    two spans rather than ten. That is the right answer: the alternative is
    guessing where a word ends in a script this project has no business
    segmenting.
    """
    # Which words turn green later. The last two, whatever language this is: no
    # per-locale list to keep in step, and in every one of the seven the closing
    # two words are the ones about the agents working. They carry a second index
    # of their own so the green can arrive one word after the other, exactly as
    # the white does.
    words = [w for piece in re.split(r"(<[^>]+>)", text) if not piece.startswith("<")
             for w in piece.split(" ") if w]
    tinted = set(range(max(0, len(words) - 2), len(words)))

    out = []
    step = 0
    tint = 0
    for piece in re.split(r"(<[^>]+>)", text):
        if not piece:
            continue
        if piece.startswith("<"):
            out.append(piece)
            continue
        for word in piece.split(" "):
            if not word:
                continue
            if step in tinted:
                out.append(
                    f'<span class="word tint" '
                    f'style="--fill-step: {step}; --tint-step: {tint}">{word}</span>')
                tint += 1
            else:
                out.append(f'<span class="word" style="--fill-step: {step}">{word}</span>')
            step += 1
    return " ".join(out)


def clean(html):
    """The markup as a visitor should receive it: no notes to ourselves.

    Everything explaining *why* the page is built this way belongs in this
    file, where it is read by whoever changes it. Shipping the same notes
    inside every page in seven languages serves nobody: it is weight on the
    wire and reading over the reader's shoulder.

    Two passes, both conservative. HTML comments go whole. Script comments go
    only when the line is nothing but a comment, so a `//` inside a string —
    every URL, for one — is never touched.
    """
    html = re.sub(r"[ \t]*<!--.*?-->\n?", "", html, flags=re.S)
    kept = [line for line in html.split("\n") if not line.lstrip().startswith("//")]
    return re.sub(r"\n{3,}", "\n\n", "\n".join(kept))

def figures(code, t):
    """Three numbers under the hero: downloads, releases, and how long Belay
    has been going.

    Every figure carries a quiet second line: where the downloads came from,
    which version the releases end at, the date the days count from. It is
    printed rather than hidden behind a hover, because a phone has no hover
    and a fact worth knowing should not need a mouse to find.

    The day count is the one number that would go stale between builds, so it
    is worked out in the page from a fixed start date — arithmetic on a
    constant, not a request. Without JavaScript the figure printed at build
    time stands, and it is never more than a scheduled rebuild out of date.
    """
    total = STATS_DIRECT + (STATS_APPSTORE or 0)
    parts = [f'{t["direct_count"]} {STATS_DIRECT}']
    if STATS_APPSTORE is not None:
        parts.insert(0, f'{t["appstore_count"]} {STATS_APPSTORE}')
    start = datetime.date.fromisoformat(FIRST_COMMIT)
    days = (datetime.date.today() - start).days
    since = t["since_note"].format(date=start.strftime("%d.%m.%Y"))
    # The glyphs speak the same language as the app's own icon set: a 24-point
    # canvas, two-point round strokes, the violet accent carrying the main
    # shape and the ink carrying the detail. `pathLength="1"` lets the
    # stylesheet draw each stroke from nothing without knowing its true length.
    def glyph(accent, ink):
        return (
            '<svg class="glyph" viewBox="0 0 24 24" width="30" height="30"'
            ' fill="none" aria-hidden="true">'
            f'<path d="{accent}" stroke="#6E5DFF" pathLength="1"/>'
            f'<path d="{ink}" stroke="currentColor" pathLength="1"/>'
            "</svg>"
        )
    art = {
        "downloads": glyph("M12 4V14M7.5 9.5L12 14L16.5 9.5",
                           "M4 16.5V18.5C4 19.6 4.9 20.5 6 20.5H18C19.1 20.5 20 19.6 20 18.5V16.5"),
        "releases": glyph("M12 3L21 8V16L12 21L3 16V8L12 3Z",
                          "M3 8L12 13L21 8M12 13V21"),
        "days": glyph("M12 22C17.52 22 22 17.52 22 12C22 6.48 17.52 2 12 2C6.48 2 2 6.48 2 12C2 17.52 6.48 22 12 22Z",
                      "M12 6V12L16 14"),
    }
    return [
        '<ul class="figures">',
        f'    <li>{art["downloads"]}<span class="figure">{total}</span>'
        f'<span class="caption">{t["downloads"]}</span>'
        f'<span class="origin">{"".join(f"<span>{p}</span>" for p in parts)}</span></li>',
        f'    <li>{art["releases"]}<span class="figure">{STATS_RELEASES}</span>'
        f'<span class="caption">{t["releases"]}</span>'
        f'<span class="origin"><span>{t["version"].format(version=VERSION)}</span></span></li>',
        f'    <li>{art["days"]}<span class="figure" data-since="{FIRST_COMMIT}">{days}</span>'
        f'<span class="caption">{t["days"]}</span>'
        f'<span class="origin"><span>{since}</span></span></li>',
        "</ul>",
        "",
        "<script>",
        "(function(){",
        "  var el=document.querySelector('.figure[data-since]');",
        "  if(!el){return;}",
        "  var start=new Date(el.dataset.since+'T00:00:00');",
        "  var days=Math.floor((Date.now()-start.getTime())/86400000);",
        "  if(days>0){el.textContent=days;}",
        "})();",
        "</script>",
        "",
    ]

def console_note():
    """What a developer finds when they open the console on this page.

    A page like this one gets its markup read by exactly the sort of person
    the app is for, so the console is a place to say hello rather than a place
    that happens to be empty. It logs once, prints no data about the visitor,
    and holds no state.

    The picture is the site's own mark: three four-pointed stars, drawn as
    astroids in density shading, one colour per line so the light gathers at
    the core and falls off toward the edges. The drawing is generated, not
    typed; the generator lives with the session notes.
    """
    art = [
        ("                         \u00b7", "#1f5bd6"),
        ("   \u00b7            \u2591                  \u2592        \u00b7", "#3c72df"),
        ("           \u00b7   \u2591\u2592\u2591               \u2591\u2592\u2593\u2592\u2591", "#5788e7"),
        ("             \u2591\u2591\u2592\u2593\u2592\u2591\u2591          \u2591\u2591\u2592\u2593\u2593\u2588\u2593\u2593\u2592\u2591\u2591", "#709cee"),
        ("           \u2591\u2591\u2592\u2592\u2593\u2593\u2593\u2592\u2592\u2591\u2591            \u2591\u2593\u2591", "#87aff5"),
        ("     \u00b7  \u2591\u2591\u2591\u2592\u2592\u2593\u2593\u2593\u2588\u2593\u2593\u2593\u2592\u2592\u2591\u2591\u2591          \u2591", "#9bbefb"),
        ("  \u2591\u2591\u2591\u2592\u2592\u2592\u2593\u2593\u2593\u2593\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2593\u2593\u2593\u2593\u2592\u2592\u2592\u2591\u2591\u2591              \u00b7", "#a8c9ff"),
        (" \u00b7      \u2591\u2591\u2591\u2592\u2592\u2593\u2593\u2593\u2588\u2593\u2593\u2593\u2592\u2592\u2591\u2591\u2591", "#9bbefb"),
        ("           \u2591\u2591\u2592\u2592\u2593\u2593\u2593\u2592\u2592\u2591\u2591                 \u2591", "#87aff5"),
        ("             \u2591\u2591\u2592\u2593\u2592\u2591\u2591                  \u2591\u2593\u2591", "#709cee"),
        ("        \u00b7      \u2591\u2592\u2591                   \u2591\u2592\u2593\u2592\u2591", "#5788e7"),
        ("                \u2591           \u00b7          \u2591", "#3c72df"),
        ("                      \u00b7                    \u00b7", "#1f5bd6"),
    ]
    lines = [
        "<script>",
        "(function(){",
        "  var art=" + json.dumps("\n".join("%c" + row for row, _ in art)) + ";",
        "  var glow=[" + ",".join(
            f"'color:{col}'" for _, col in art) + "];",
        "  var quiet='color:#8a8f98';",
        "  console.log.apply(console,[art].concat(glow));",
        "  console.log('%cAgents can write the code. Deciding what deserves to exist is still yours. \u00a9 AI', quiet);",
        f"  console.log('%cv{VERSION}  \u00b7  source: https://github.com/PerfectoWeb/Belay', quiet);",
        "})();",
        "</script>",
        "",
    ]
    return lines

def appstore_button(t):
    """The App Store button, or nothing while the app is not on the store.

    A function rather than an inline conditional so the page's markup can live
    in `template.html`: a template has no way to express "only when true", and
    the honest place for that decision is here.

    The words inside are hidden on a phone, where the button shrinks to its
    glyph, so the name has to live on the link itself.
    """
    if not APP_STORE_LIVE:
        return []
    return [
        f'    <a class="button stacked secondary appstore" href="{APP_STORE_URL}" '
        f'aria-label="{t["appstore_top"]} {t["appstore_name"]}">'
        f'{APPSTORE_MARK}<span class="lines">'
        f'<span class="under">{t["appstore_top"]}</span>'
        f'<span class="lead">{t["appstore_name"]}</span></span></a>',
    ]


def sponsor_button(t):
    """The sponsors link, once there is somewhere for it to point."""
    if not SPONSORS_LIVE:
        return []
    return [f'    <a class="button secondary" href="{SPONSORS_URL}">{t["sponsor"]}</a>']


def landing(code):
    """The landing page, filled in from `template.html`.

    The markup lives in that file rather than in this one, so it can be opened,
    read and edited as the HTML it is. Everything here is data: the seven
    languages' words, and the handful of parts a template cannot express — the
    document head, the figures with their live counts, the gallery, a button
    that only exists while the app is on the App Store.

    `{{name}}` is the whole syntax. A name that is a text key is filled from
    the language's table; a name that is a block below is filled by the code
    that builds it. Anything else is left alone and shows up in the page, which
    is the loudest way to report a typo.
    """
    t = L[code]
    blocks = {
        "head": "\n".join(head(code, t["title"], t["meta"], 1, "")),
        "header": "\n".join(header(code, 1)),
        "h1": filled_heading(t["h1"]),
        "version_line": t["version"].format(version=VERSION),
        "appstore_button": "\n".join(appstore_button(t)),
        "sponsor_button": "\n".join(sponsor_button(t)),
        "figures": "\n".join(figures(code, t)),
        "gallery": "\n".join(gallery(code, t)),
        "support_head": typed_heading(t["support_head"]),
        "language_picker": "\n".join(language_picker(code, 1, t["language"], "")),
        "console": "\n".join(console_note()),
        "fine": T[code]["fine"],
    }
    return external(render(template(), blocks, t))


def template():
    """`template.html`, read once and kept for the other six languages."""
    global TEMPLATE
    if TEMPLATE is None:
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "template.html")
        # Exactly one newline at the end, however many the file was saved
        # with: an editor that adds a blank line should not add one to the
        # page, and an editor that strips them should not take the page's.
        TEMPLATE = io.open(path, encoding="utf-8").read().rstrip("\n") + "\n"
    return TEMPLATE


def render(markup, blocks, texts):
    """Fills `{{name}}` from the blocks first, then from the language's words.

    Blocks win, because a block named after a text key is the rendered form of
    that key — the heading with its highlight markup, the version line with a
    number in it — and the raw string would be the wrong half of the job.
    """
    def fill(match):
        name = match.group(1)
        if name in blocks:
            return blocks[name]
        if name in texts:
            return texts[name]
        # Left in place on purpose: a page that prints {{typo}} says where the
        # problem is, and a page that silently drops it does not.
        return match.group(0)

    out = []
    for line in markup.split("\n"):
        filled = re.sub(r"\{\{([a-z_0-9]+)\}\}", fill, line)
        # A block that came to nothing takes its line with it. Otherwise the
        # sponsors button nobody has yet would leave a blank line behind, and
        # the page would drift a little every time a block is switched off.
        if not filled.strip() and line.strip():
            continue
        out.append(filled)
    return "\n".join(out)


def privacy(code):
    t = T[code]
    lines = head(code, t["title"], t["meta"], 2, "privacy/")
    lines += header(code, 2)
    lines += [f'<h1>{t["h1"]}</h1>', f'<p class="stamp">{t["stamp"]}</p>', ""]
    if t["authoritative"]:
        lines += [f'<p class="stamp translated">{t["authoritative"]}</p>', ""]
    lines += [f'<p class="lede">{t["lede"]}</p>', ""]

    sections = [
        ("reads_head", ["reads_1", "reads_2", "reads_3", "reads_4"], False),
        ("leaves_head", ["leaves_mas", "leaves_direct"], True),
        ("stores_head", ["stores_1", "stores_2"], False),
        ("changes_head", ["changes_1", "changes_2"], False),
        ("sharing_head", ["sharing_1", "sharing_2", "sharing_site"], False),
        ("policy_head", ["policy_1"], False),
        ("contact_head", ["contact_1"], False),
    ]
    for heading, bodies, boxed in sections:
        lines += [f"<h2>{t[heading]}</h2>", ""]
        if boxed:
            lines.append('<div class="note">')
            lines += [f"    <p>{t[key]}</p>" for key in bodies]
            lines.append("</div>")
        else:
            for key in bodies:
                lines += [f"<p>{t[key]}</p>", ""]
            lines.pop()
        lines.append("")

    lines += [
        "<footer>",
        '    <div class="row">',
        "        <p>",
        f'            <a href="../">Belay</a> &middot;',
        f'            <a href="https://github.com/PerfectoWeb/Belay">{t["source"]}</a>',
        "        </p>",
    ]
    lines += language_picker(code, 2, L[code]["language"], "privacy/")
    lines += [
        "    </div>",
        f'    <p class="fine">{t["fine"]}</p>',
        '    <p class="fine copyright">&copy; 2026 '
        '<a href="https://perfecto-web.com">PerfectoWeb</a>. '
        f'<a href="https://github.com/PerfectoWeb/Belay/blob/main/LICENSE">'
        f'{L[code]["licence"]}</a>. {L[code]["made_by"]}<br>'
        f'{L[code]["trademarks"]}</p>',
        "</footer>",
        "",
        "<script>",
        "  // Closes the language picker when the click lands anywhere else.",
        "  // CSS cannot see a click outside an element, and the alternative was",
        "  // a hidden checkbox with a full-screen label over the page, which is",
        "  // more machinery in the markup than this is in script. Without it the",
        "  // picker still opens, still closes on its own summary, and every link",
        "  // in it works.",
        "  document.addEventListener('click', function (event) {",
        "    document.querySelectorAll('details.languages[open]').forEach(function (picker) {",
        "      if (!picker.contains(event.target)) { picker.open = false; }",
        "    });",
        "  });",
        "</script>",
        "",
        "</div>",
        "</body>",
        "</html>",
        "",
    ]
    return external("\n".join(lines))


def fixed_redirect(target, depth, note):
    """For an address that already named its language. Somebody who saved
    /privacy/ru/ asked for Russian; guessing again from their browser would
    overrule a choice they had already made."""
    up = "../" * depth
    return "\n".join([
        "<!doctype html>",
        '<html lang="en">',
        "<head>",
        '<meta charset="utf-8">',
        f"<!-- {note} -->",
        f'<link rel="canonical" href="https://perfectoweb.github.io/Belay/{target}">',
        f'<link rel="icon" href="{up}favicon.ico" sizes="32x32">',
        f'<link rel="icon" href="{up}icon.svg" type="image/svg+xml">',
        f'<meta http-equiv="refresh" content="0; url={up}{target}">',
        "<title>Belay</title>",
        "</head>",
        f'<body><a href="{up}{target}">Belay</a></body>',
        "</html>",
        "",
    ])


def redirect(target, depth, note):
    """A page whose only job is to send the reader somewhere else.

    `location.replace` rather than an assignment, so Back does not land here
    again and bounce. The noscript refresh is the same destination for anyone
    without JavaScript, which is why the detection can afford to be simple.
    """
    up = "../" * depth
    return "\n".join([
        "<!doctype html>",
        '<html lang="en">',
        "<head>",
        '<meta charset="utf-8">',
        f"<!-- {note} -->",
        f'<link rel="canonical" href="https://perfectoweb.github.io/Belay/{target}">',
        f'<link rel="icon" href="{up}favicon.ico" sizes="32x32">',
        f'<link rel="icon" href="{up}icon.svg" type="image/svg+xml">',
        f'<noscript><meta http-equiv="refresh" content="0; url={up}{target}"></noscript>',
        "<title>Belay</title>",
        "<script>",
        f"  var known = {CODES!r};".replace("'", '"'),
        '  var wanted = (navigator.languages || [navigator.language || "en"])',
        '    .map(function (tag) { return String(tag).slice(0, 2).toLowerCase(); })',
        "    .filter(function (code) { return known.indexOf(code) !== -1; })[0];",
        f'  location.replace("{up}" + (wanted || "en") + "/{target.split("/", 1)[1] if "/" in target else ""}");',
        "</script>",
        "</head>",
        f'<body><a href="{up}{target}">Belay</a></body>',
        "</html>",
        "",
    ])


def main(root):
    global STYLE_STAMP, OG_STAMP
    style = os.path.join(root, "style.css")
    if os.path.exists(style):
        digest = hashlib.sha256(io.open(style, "rb").read()).hexdigest()[:10]
        STYLE_STAMP = f"?v={digest}"
        print(f"  style.css {STYLE_STAMP}")

    card = os.path.join(root, "img", "og.png")
    if os.path.exists(card):
        digest = hashlib.sha256(io.open(card, "rb").read()).hexdigest()[:10]
        OG_STAMP = f"?v={digest}"
        print(f"  img/og.png {OG_STAMP}")

    written = []
    for code in CODES:
        folder = os.path.join(root, code)
        os.makedirs(folder, exist_ok=True)
        io.open(os.path.join(folder, "index.html"), "w", encoding="utf-8").write(clean(landing(code)))
        written.append(f"{code}/")

        folder = os.path.join(root, code, "privacy")
        os.makedirs(folder, exist_ok=True)
        io.open(os.path.join(folder, "index.html"), "w", encoding="utf-8").write(clean(privacy(code)))
        written.append(f"{code}/privacy/")

    io.open(os.path.join(root, "index.html"), "w", encoding="utf-8").write(clean(
        redirect("en/", 0, "The site root. Sends the reader to their own language if we have it.")))
    written.append("/")

    # The addresses that already exist in the world.
    os.makedirs(os.path.join(root, "privacy"), exist_ok=True)
    io.open(os.path.join(root, "privacy", "index.html"), "w", encoding="utf-8").write(clean(
        redirect("en/privacy/", 1, "Kept: the published 1.0.0 release notes link here.")))
    written.append("privacy/")
    for code in CODES:
        if code == "en":
            continue
        folder = os.path.join(root, "privacy", code)
        os.makedirs(folder, exist_ok=True)
        io.open(os.path.join(folder, "index.html"), "w", encoding="utf-8").write(
            fixed_redirect(
                f"{code}/privacy/", 2, "Kept: this address was published for one evening."))
        written.append(f"privacy/{code}/")

    for path in written:
        print(f"  {path}")


if __name__ == "__main__":
    main(sys.argv[1])
