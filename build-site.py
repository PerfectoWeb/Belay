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
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from landing import L, VERSION
from policy_text import LANGUAGES, T

CODES = [code for code, _, _ in LANGUAGES]

# Flip when the listing is approved and the link stops being a 404. Until then
# a button pointing at a page that does not exist is worse than no button.
APP_STORE_LIVE = False
APP_STORE_URL = "https://apps.apple.com/app/id6801207644"

# Flip when GitHub Sponsors is enabled on the account. Same reasoning.
SPONSORS_LIVE = False
SPONSORS_URL = "https://github.com/sponsors/PerfectoWeb"
DONATE_URL = "https://perfecto-web.com/d/"

GITHUB = ('<svg class="glyph" viewBox="0 0 16 16" aria-hidden="true">'
          '<path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38'
          ' 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53'
          '.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95'
          ' 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2'
          ' .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65'
          ' 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42'
          '-3.58-8-8-8Z"/></svg>')

HEART = ('<svg class="glyph" viewBox="0 0 16 16" aria-hidden="true">'
         '<path fill="currentColor" d="M8 14.25S1.5 10.5 1.5 5.94A3.44 3.44 0 0 1 8 4.2a3.44 3.44 0 0 1 6.5'
         ' 1.74C14.5 10.5 8 14.25 8 14.25Z"/></svg>')


# The real lockup from Resources/Brand, not a redrawing of it. Two files
# rather than one recoloured by CSS: the wordmark is a filled path, and a
# stylesheet cannot repaint the inside of an <img>.
def wordmark(up):
    return (
        f'''<img class="mark light" src="{up}brand/belay-wordmark-light.svg" alt="Belay" width="129" height="49">
    <img class="mark dark" src="{up}brand/belay-wordmark-dark.svg" alt="Belay" width="129" height="49">'''
    )


def head(code, title, meta, depth, page):
    """`depth` is how far this file sits below the site root."""
    up = "../" * depth
    lines = [
        "<!doctype html>",
        f'<html lang="{code}">',
        "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        f"<title>{title}</title>",
        f'<meta name="description" content="{meta}">',
        f'<link rel="stylesheet" href="{up}style.css">',
    ]
    for other in CODES:
        href = f"https://perfectoweb.github.io/Belay/{other}/{page}"
        lines.append(f'<link rel="alternate" hreflang="{other}" href="{href}">')
    lines.append(
        '<link rel="alternate" hreflang="x-default" '
        f'href="https://perfectoweb.github.io/Belay/en/{page}">')
    lines += ["</head>", "<body>", '<div class="wrap">', ""]
    return lines


def header(code, depth):
    up = "../" * depth
    return [
        "<header>",
        f'    <a href="{up}{code}/">{wordmark(up)}</a>',
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


def landing(code):
    t = L[code]
    lines = head(code, t["title"], t["meta"], 1, "")
    lines += header(code, 1)
    lines += [
        f'<h1>{t["h1"]}</h1>',
        "",
        f'<p class="lede">{t["lede"]}</p>',
        "",
        f'<p>{t["body"]}</p>',
        "",
        '<div class="actions">',
        '    <a class="button stacked" href="https://github.com/PerfectoWeb/Belay/releases/latest/download/Belay.dmg">'
        f'<span>{t["download"]}</span>'
        f'<span class="under">{t["version"].format(version=VERSION)}</span></a>',
    ] + ([
        f'    <a class="button appstore" href="{APP_STORE_URL}">'
        f'<span class="apple" aria-hidden="true">&#63743;</span>{t["appstore"]}</a>',
    ] if APP_STORE_LIVE else []) + [
        f'    <a class="button secondary" href="https://github.com/PerfectoWeb/Belay">{t["source"]}</a>',
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
        '<figure class="panel">',
        f'    <img src="../img/panel.png" alt="{t["modes_head"]}" width="1600" height="1000">',
        "</figure>",
        "",
        "",
        f'<h2>{t["support_head"]}</h2>',
        "",
        f'<p>{t["support_body"]}</p>',
        "",
        '<div class="actions">',
        f'    <a class="button" href="{DONATE_URL}">{HEART}{t["donate"]}</a>',
    ] + ([
        f'    <a class="button secondary" href="{SPONSORS_URL}">{t["sponsor"]}</a>',
    ] if SPONSORS_LIVE else []) + [
        f'    <a class="button secondary" href="https://github.com/PerfectoWeb/Belay">'
        f'{GITHUB}{t["star"]}</a>',
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
        '<a href="https://github.com/PerfectoWeb/Belay/blob/main/LICENSE">MIT licensed</a>.<br>'
        'All product names and logos are trademarks of their respective owners.</p>',
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
    return "\n".join(lines)


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
    return "\n".join(lines)


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
