#!/usr/bin/env python3
"""Builds the whole site: six languages, two pages each, plus the redirects.

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

import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from landing import L, VERSION
from policy_text import LANGUAGES, T

CODES = [code for code, _, _ in LANGUAGES]

# What the markup declares, which is not always what the path is called. They
# match everywhere but Chinese: the path stays two letters because the root
# redirect matches on the first two of the browser's tag, while the language
# itself is a script rather than a country.
TAG = {code: tag for code, _, tag in LANGUAGES}

# Flip when the listing is approved and the link stops being a 404. Until then
# a button pointing at a page that does not exist is worse than no button.
APP_STORE_LIVE = False
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

GITHUB_MARK = (
    '<svg class="mark" viewBox="0 0 16 16" aria-hidden="true" fill="currentColor">'
    '<path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49'
    '-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66'
    '.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82'
    '.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95'
    '.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z"/></svg>'
)

# The two sparks in the corner of the download button, as on the README's own.
SPARKLE = (
    '<svg class="spark" viewBox="0 0 24 24" aria-hidden="true" fill="currentColor">'
    '<path d="M15 2l1.4 4.1L20.5 7.5 16.4 8.9 15 13l-1.4-4.1L9.5 7.5l4.1-1.4z"/>'
    '<path d="M7.5 13l.9 2.6 2.6.9-2.6.9-.9 2.6-.9-2.6L4 16.5l2.6-.9z"/></svg>'
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


# The panel screenshot, in the language of the page it sits on. English,
# Russian and Chinese share the English shot: the app speaks all three, but the
# picture we have of it does not, and a screenshot in one language under a
# heading in another is worse than one that is plainly foreign.
PANEL = {
    "de": "panel-de.png",
    "es": "panel-es.png",
    "fr": "panel-fr.png",
    "it": "panel-it.png",
}


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
        f'<link rel="stylesheet" href="{up}style.css">',
        # Open Graph. Without these a link to this page unfurls in Slack,
        # iMessage, Discord and X as a bare URL, which is what it did for the
        # whole of 1.0. The card is 1280x640, rendered by
        # scripts/make-social.swift in the app's repository.
        '<meta property="og:type" content="website">',
        f'<meta property="og:title" content="{title}">',
        f'<meta property="og:description" content="{meta}">',
        f'<meta property="og:url" content="https://perfectoweb.github.io/Belay/{code}/{page}">',
        '<meta property="og:image" content="https://perfectoweb.github.io/Belay/img/og.png">',
        '<meta property="og:image:width" content="1280">',
        '<meta property="og:image:height" content="640">',
        '<meta property="og:site_name" content="Belay">',
        '<meta name="twitter:card" content="summary_large_image">',
    ]
    for other in CODES:
        href = f"https://perfectoweb.github.io/Belay/{other}/{page}"
        lines.append(f'<link rel="alternate" hreflang="{TAG[other]}" href="{href}">')
    lines.append(
        '<link rel="alternate" hreflang="x-default" '
        f'href="https://perfectoweb.github.io/Belay/en/{page}">')
    lines += ["</head>", "<body>", '<div class="wrap">', ""]
    return lines


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
SLIDE_SOURCE = "https://raw.githubusercontent.com/PerfectoWeb/Belay/main/Promo/AppStore"
SLIDE_COUNT = 5

# The slides were named before the site was, and Spanish disagrees: the files say
# `sp` and every locale code here says `es`. Mapped rather than renamed, because
# the files are also what App Store Connect was fed from.
SLIDE_CODE = {"es": "sp"}


def slides(code):
    """Every slide for this language, in order, as absolute URLs."""
    name = SLIDE_CODE.get(code, code)
    return [
        f"{SLIDE_SOURCE}/belay-appimage-{name}-{n}.png"
        for n in range(1, SLIDE_COUNT + 1)
    ]


def gallery(code, t):
    """The App Store slides for this language, with dots and two click zones.

    Enhanced rather than required. With no JavaScript this is the first slide and
    nothing else: the rest are hidden by the stylesheet, the dots are hidden, and
    what remains is one picture, which is what this section was before. That is
    the same rule the disclosure above follows.

    Only the first slide loads eagerly. The others are 2880 wide and about two
    megabytes each, so fetching all five on load would cost more than the rest of
    the page put together.
    """
    lines = ['<div class="gallery" data-gallery>', '    <div class="frames">']
    for index, url in enumerate(slides(code)):
        on = " is-on" if index == 0 else ""
        lazy = "" if index == 0 else ' loading="lazy"'
        lines.append(
            f'        <img class="frame{on}" src="{url}" '
            f'alt="{t["modes_head"]}" width="2880" height="1800"{lazy}>')
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
    for index in range(SLIDE_COUNT):
        lines.append(
            f'        <button class="dot{" is-on" if index == 0 else ""}" type="button"'
            f' role="tab" data-to="{index}"'
            f' aria-label="{t["gallery_dot"].format(n=index + 1)}"></button>')
    lines += ['    </div>', '</div>']
    return lines


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
    out = []
    step = 0
    for piece in re.split(r"(<[^>]+>)", text):
        if not piece:
            continue
        if piece.startswith("<"):
            out.append(piece)
            continue
        for word in piece.split(" "):
            if not word:
                continue
            out.append(f'<span class="word" style="--fill-step: {step}">{word}</span>')
            step += 1
    return " ".join(out)


def landing(code):
    t = L[code]
    lines = head(code, t["title"], t["meta"], 1, "")
    lines += header(code, 1)
    lines += [
        f'<h1>{filled_heading(t["h1"])}</h1>',
        "",
        f'<p class="lede">{t["lede"]}</p>',
        "",
        # The second paragraph is the one somebody reads only if the first one
        # interested them, so it is folded. `details` and not a script: the
        # page has no JavaScript, and a disclosure that needs some is a
        # paragraph that disappears when it fails.
        f'<details class="more"><summary>{t["more"]}</summary>',
        f'<p>{t["body"]}</p>',
        "</details>",
        "",
        '<div class="actions get">',
        '    <a class="button stacked primary" href="https://github.com/PerfectoWeb/Belay/releases/latest/download/Belay.dmg">'
        f'{APPLE_MARK}<span class="lines"><span class="lead">{t["download"]}</span>'
        f'<span class="under">{t["version"].format(version=VERSION)}</span></span>{SPARKLE}</a>',
    ] + ([
        f'    <a class="button appstore" href="{APP_STORE_URL}">'
        f'<span class="apple" aria-hidden="true">&#63743;</span>{t["appstore"]}</a>',
    ] if APP_STORE_LIVE else []) + [
        '    <a class="button stacked secondary" href="https://github.com/PerfectoWeb/Belay">'
        f'{GITHUB_MARK}<span class="lines"><span class="lead">{t["source"]}</span>'
        '<span class="under">PerfectoWeb/Belay</span></span></a>',
        "</div>",
        "",
        f'<p class="version">{t["free"]} '
        f'<a href="https://github.com/PerfectoWeb/Belay/releases/latest">{t["notes"]}</a></p>',
        "",
        '<ul class="badges">',
        '    <li><span class="apple" aria-hidden="true">&#63743;</span>macOS 14+</li>',
        '    <li class="outline"><svg class="chip-glyph" viewBox="0 0 20 20" aria-hidden="true">'
        '<rect x="5.2" y="5.2" width="9.6" height="9.6" rx="1.6" fill="none" stroke="currentColor" stroke-width="1.3"/>'
        '<path stroke="currentColor" stroke-width="1.2" stroke-linecap="round" d="M8 5.2V3M12 5.2V3M8 17v-2.2M12 17v-2.2M5.2 8H3M5.2 12H3M17 8h-2.2M17 12h-2.2"/>'
        '<text x="10" y="12.6" text-anchor="middle" font-size="6.4" font-weight="700" fill="currentColor">M</text>'
        '</svg>Apple silicon</li>',
        '    <li class="outline"><svg class="chip-glyph" viewBox="0 0 16 16" aria-hidden="true">'
        '<circle cx="8" cy="8" r="6.2" fill="none" stroke="currentColor" stroke-width="1.4"/>'
        '<path fill="currentColor" d="M5.6 5.9h1.5v4.2H5.6zM8.4 5.9h1.1v.7a1.4 1.4 0 0 1 1.2-.8c.9 0 1.4.6'
        ' 1.4 1.6v2.7h-1.5V7.8c0-.5-.2-.7-.6-.7s-.6.3-.6.8v2.2H8.4z"/></svg>Intel</li>',
        "</ul>",
        "",
        f'<h2 class="modes-head">{t["modes_head"]}</h2>',
    ] + gallery(code, t) + [
        "",
        "",
        f'<h2>{t["support_head"]}</h2>',
        "",
        f'<p>{t["support_body"]}</p>',
        "",
        '<div class="actions give">',
        f'    <a class="button donate" href="{DONATE_URL}">{HEART}{t["donate"]}</a>',
    ] + ([
        f'    <a class="button secondary" href="{SPONSORS_URL}">{t["sponsor"]}</a>',
    ] if SPONSORS_LIVE else []) + [
        f'    <a class="button secondary" href="https://github.com/PerfectoWeb/Belay">'
        f'{STAR}{t["star"]}</a>',
        "</div>",
        "",
        "<footer>",
        '    <div class="row">',
        "        <p>",
        f'            <a href="privacy/">{t["privacy"]}</a> &middot;',
        f'            <a href="https://github.com/PerfectoWeb/Belay/issues">{t["bug"]}</a> &middot;',
        '            <a href="https://perfecto-web.com">perfecto-web.com</a>',
        "        </p>",
    ]
    lines += language_picker(code, 1, t["language"], "")
    lines += [
        "    </div>",
        f'    <p class="fine">{T[code]["fine"]}</p>',
        '    <p class="fine copyright">&copy; 2026 PerfectoWeb. '
        f'<a href="https://github.com/PerfectoWeb/Belay/blob/main/LICENSE">'
        f'{L[code]["licence"]}</a>.<br>'
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
        # The gallery. Everything it does is add and remove two class names, and
        # the movement is the stylesheet's. It marks itself live first, which is
        # what reveals the dots and the click zones: they are hidden until
        # something can answer them, because a pointer cursor over a strip that
        # does nothing is a promise the page cannot keep.
        "<script>",
        "  document.querySelectorAll('[data-gallery]').forEach(function (gallery) {",
        "    var frames = gallery.querySelectorAll('.frame');",
        "    var dots = gallery.querySelectorAll('.dot');",
        "    if (frames.length < 2) { return; }",
        "    var at = 0;",
        "    gallery.classList.add('is-live');",
        "    function show(next) {",
        "      next = (next + frames.length) % frames.length;",
        "      if (next === at) { return; }",
        "      // Which way it is going, so the frame that leaves goes the other way.",
        "      if (next < at) { gallery.setAttribute('data-back', ''); }",
        "      else { gallery.removeAttribute('data-back'); }",
        "      frames[at].classList.remove('is-on');",
        "      dots[at].classList.remove('is-on');",
        "      at = next;",
        "      frames[at].classList.add('is-on');",
        "      dots[at].classList.add('is-on');",
        "    }",
        "    dots.forEach(function (dot) {",
        "      dot.addEventListener('click', function () { show(Number(dot.dataset.to)); });",
        "    });",
        "    gallery.querySelectorAll('.turn').forEach(function (zone) {",
        "      zone.addEventListener('click', function () { show(at + Number(zone.dataset.step)); });",
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
        ("sharing_head", ["sharing_1", "sharing_2"], False),
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
        '    <p class="fine copyright">&copy; 2026 PerfectoWeb. '
        f'<a href="https://github.com/PerfectoWeb/Belay/blob/main/LICENSE">'
        f'{L[code]["licence"]}</a>.<br>'
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
    written = []
    for code in CODES:
        folder = os.path.join(root, code)
        os.makedirs(folder, exist_ok=True)
        io.open(os.path.join(folder, "index.html"), "w", encoding="utf-8").write(landing(code))
        written.append(f"{code}/")

        folder = os.path.join(root, code, "privacy")
        os.makedirs(folder, exist_ok=True)
        io.open(os.path.join(folder, "index.html"), "w", encoding="utf-8").write(privacy(code))
        written.append(f"{code}/privacy/")

    io.open(os.path.join(root, "index.html"), "w", encoding="utf-8").write(
        redirect("en/", 0, "The site root. Sends the reader to their own language if we have it."))
    written.append("/")

    # The addresses that already exist in the world.
    os.makedirs(os.path.join(root, "privacy"), exist_ok=True)
    io.open(os.path.join(root, "privacy", "index.html"), "w", encoding="utf-8").write(
        redirect("en/privacy/", 1, "Kept: the published 1.0.0 release notes link here."))
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
