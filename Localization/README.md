# Localization

Every user-visible string in Belay, one CSV per language. These files are for
rewriting text; the app reads `Resources/Localizable.xcstrings`, which is
generated from them.

```bash
swift scripts/strings.swift export            # catalogue -> these files
swift scripts/strings.swift import --dry-run  # check without writing
swift scripts/strings.swift import            # these files -> catalogue
swift scripts/strings.swift import --prune     # ...and retire anything en.csv drops
```

## The columns

| Column | |
|---|---|
| `key` | The identifier. Never edit it. |
| `screen` | Where the string appears. `(unused)` means no source file asks for it. |
| `status` | `needs_review` means it has never been read by a person. Start there. |
| `placeholders` | Format specifiers, in order. See below. |
| `source` | The current English. Reference only, except in `en.csv`. |
| `translation` | **The only column to edit.** |

## Rules

**Placeholders must survive, in the same order.** `%@` is text, `%lld` is a
number. A translation that drops one or swaps two reads the wrong argument and
prints garbage or crashes, in a language nobody testing the app is using. Import
refuses the file rather than let that through, and `LocalizationTests` checks it
again against the compiled tables.

Word order can change. If a language needs the number first, use positional
specifiers: `%1$@` and `%2$lld`.

**No em dashes or en dashes.** House rule, and one a spreadsheet breaks on its
own: several editors turn a typed hyphen into an em dash without asking. Import
rejects both.

**Delete a row to retire a string,** then import with `--prune`. Without that
flag a missing row is ignored, which is what keeps a copy being reviewed
elsewhere from deleting strings added here in the meantime.

**Keep it short.** These are menu bar and popover strings. The panel is about
300 pt wide, so a line that grows by half in translation wraps or truncates.

## Rewriting English

`en.csv` is the odd one. A key in this catalogue *is* its English text, so
rewriting English renames the key, and that key is a string literal in the Swift
sources. Import does the whole rename: catalogue, every other language, and the
sources. Nothing else needs touching, but do run `scripts/test.sh` afterwards.
