# Editing this site by hand

Two files are yours to edit directly. Nothing generates either of them, and
nothing rewrites them.

| File | What it is |
|---|---|
| `template.html` | The landing page, as HTML. Structure, classes, attributes, inline SVG. |
| `style.css` | The stylesheet, as CSS. Plain file, copied to the site untouched. |

Everything else on the page is words, and words live in `landing.py` because
one sentence has to appear in seven languages.

## The one piece of syntax

`{{name}}` is a hole the build fills in.

A name that is a text key takes that language's sentence: `{{lede}}`,
`{{download}}`, `{{star}}`. Move it, wrap it, put it in a different element —
it keeps working, because the build looks for the name and not for where it sat.

A few names are filled by code instead, because a template cannot express them:

| Name | Why it is not plain HTML |
|---|---|
| `{{head}}` | The whole `<head>`: per-language title, description, canonical link, structured data. |
| `{{header}}` | The top bar, which knows which language it is in. |
| `{{h1}}` | The heading with its highlighted words marked up. |
| `{{version_line}}` | Carries the current version number. |
| `{{figures}}` | The three counts, refreshed by a scheduled job. |
| `{{gallery}}` | The slide strip, its dots and its lightbox. |
| `{{support_head}}` | The heading that types itself out. |
| `{{language_picker}}` | The language list, minus the language you are on. |
| `{{appstore_button}}` | Exists only while the app is on the App Store. |
| `{{sponsor_button}}` | Exists only once there is a sponsors page. |
| `{{console}}` | The greeting printed in the browser console. |

A `{{name}}` the build does not recognise is **left in the page**, visible. That
is deliberate: a typo you can see is better than a sentence that quietly
disappeared.

## Rules that will bite otherwise

**Do not add `target="_blank"`.** The build adds it, with `rel="noopener"`, to
every link that leaves the site. Adding your own gets you both, twice.

**HTML comments are stripped** from the finished page, so write as many as you
like. Notes to yourself cost the reader nothing.

**No em dashes or en dashes** in text. House rule.

## The loop

```bash
python3 build-site.py .     # template.html + style.css + landing.py -> the site
```

Then open `en/index.html` in a browser. What you see is what the site will
serve: these are the same files GitHub Pages hands out.
