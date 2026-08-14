# Releasing Belay

How a release of the direct (Developer ID) build is cut, by hand or by CI, and
how to undo one that went wrong.

**Read this first.** This path has been run. v1.0.0 was cut on 2026-08-13 and
published on 2026-08-14: archived, signed with Developer ID, notarized, stapled,
packaged and attached to a GitHub Release. What follows describes what actually
happened, not what was intended.

What has been run, and what still has not:

| Step | State |
|---|---|
| Ad-hoc local build (`scripts/build-local.sh`) | run many times |
| Developer ID signing, hardened runtime, secure timestamp | run and verified (B1) |
| `xcodebuild archive` / `-exportArchive` with developer-id | run, for v1.0.0 |
| `dmgbuild` | run, for v1.0.0 |
| Notarization and stapling | run and accepted (B6 closed) |
| GitHub Release published | v1.0.0, by hand |
| `.github/workflows/release.yml` | still never run |
| Sparkle appcast (`scripts/sign-update.sh`) | never run, and blocked on B3 |
| Mac App Store submission | never; stays manual, see below |

Two things that cost time on the first real run and will cost it again:

**`dmgbuild` needs Python 3.10 or newer**, and the `python3` on `PATH` here is
Xcode's 3.9. `pipx install 'dmgbuild>=1.6.7'` is the documented route; a
virtualenv built on Homebrew's `python3.12` with its `bin` prepended to `PATH`
works just as well, and `scripts/release.sh` accepts either shape.

**Notarization does not need the keychain profile.** `scripts/notarize.sh`
prefers a `notarytool` profile and falls back to the App Store Connect key in
`.secrets/appstoreconnect.env`, which is what v1.1.0 was notarized with. A
missing `BelayNotary` profile is not a blocker.

---

## Repository secrets

Five, all under Settings > Secrets and variables > Actions > Repository secrets.
Nothing else in the release path is secret: the team ID and the version live in
`project.yml`, which is public.

Locally these same credentials live in `.secrets/`, which is gitignored and must
stay that way. CI cannot read that directory, which is the whole reason these
secrets exist.

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_P12_BASE64` | The Developer ID Application certificate and its private key, exported as a `.p12` and base64 encoded |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The password set when exporting that `.p12` |
| `APP_STORE_CONNECT_KEY_P8_BASE64` | The whole `AuthKey_<KEYID>.p8` file, base64 encoded |
| `APP_STORE_CONNECT_KEY_ID` | The key ID of that key, shown in the keys table |
| `APP_STORE_CONNECT_ISSUER_ID` | The issuer ID of the App Store Connect account, a UUID |

There is no keychain password secret. The workflow generates a random one per
run for a keychain it deletes before the job ends, so there is nothing to store
and nothing to rotate.

### Producing `DEVELOPER_ID_CERTIFICATE_P12_BASE64`

Confirm the identity is in the login keychain and note its exact name:

```bash
security find-identity -v -p codesigning
```

The line you want reads `Developer ID Application: <Name> (<TEAMID>)`. The team
ID in it must match `DEVELOPMENT_TEAM` in `project.yml`, which is `VSY2EB4Y9E`.

Export the certificate together with its private key. Keychain Access is the
reliable way: open it, select **login** > **My Certificates**, find the
`Developer ID Application` entry, expand it to confirm a private key is attached,
then right-click and choose Export. Save as Personal Information Exchange
(`.p12`) and set an export password. Both halves matter: a `.p12` exported from
the certificate alone, without the key, will import into CI and then fail at
`codesign` with an unhelpful error.

Then base64 it, with no line wrapping:

```bash
base64 -i DeveloperID.p12 | tr -d '\n' | pbcopy
```

Paste that as `DEVELOPER_ID_CERTIFICATE_P12_BASE64`. Put the export password in
`DEVELOPER_ID_CERTIFICATE_PASSWORD`. Delete the `.p12` from disk afterwards; the
`.gitignore` already refuses to commit one, but a stray private key on a laptop
is still a private key on a laptop.

### Producing the App Store Connect secrets

The key is created once, at App Store Connect > Users and Access >
Integrations > App Store Connect API. Create a **Team Key** with the **Developer**
role, which is enough for notarization. Apple lets you download the `.p8` exactly
once, so the copy in `.secrets/` is the only copy.

- **Key ID** is shown in the keys table next to the key.
- **Issuer ID** is the UUID printed above the table on that same page. It belongs
  to the account, not to the key, so every key shares it.
- Both values are already in `.secrets/appstoreconnect.env` on the machine that
  created the key.

Base64 the key file:

```bash
base64 -i .secrets/AuthKey_<KEY_ID>.p8 | tr -d '\n' | pbcopy
```

The workflow checks that this decodes to something containing
`BEGIN PRIVATE KEY` and fails immediately if it does not, so a truncated paste
is caught in seconds rather than after a build.

### What the workflow does with them

Both credentials go into a keychain created in `RUNNER_TEMP` for the duration of
the job:

1. The `.p12` is decoded to a file, imported with `security import`, and the file
   is deleted in the same step.
2. `security set-key-partition-list` grants `codesign` access, without which
   signing blocks on a GUI prompt that nothing will ever answer and the job hangs
   until it times out.
3. The `.p8` is decoded, handed to `xcrun notarytool store-credentials --keychain`,
   and deleted. Only the derived profile survives, so the raw key is not sitting
   on disk during the notarization wait.
4. A final step with `if: always()` runs `security delete-keychain`. It runs on
   failure too, which is the case that matters: a failed release is the run
   somebody re-triggers.

No step echoes a secret, and none of them may have `set -x` added. GitHub masks
the secret values themselves in logs but does not mask what they decode to.

---

## Cutting a release

### 1. Bump the version

Both version numbers live in `project.yml` under `settings.base` and nowhere
else. Everything downstream, including the DMG filename and the tag check, reads
them from there.

```yaml
settings:
  base:
    MARKETING_VERSION: "1.0.1"      # CFBundleShortVersionString, what users see
    CURRENT_PROJECT_VERSION: "2"    # CFBundleVersion, monotonic, never reused
```

`MARKETING_VERSION` is semantic and is what the tag must match.
`CURRENT_PROJECT_VERSION` only has to increase. If a build is ever uploaded to
App Store Connect, that number is burned permanently, even if the upload is
rejected, so increment it for every attempt rather than every release.

Regenerate and confirm the project still builds:

```bash
xcodegen generate
scripts/test.sh
```

### 2. Write the CHANGELOG section

`CHANGELOG.md` follows Keep a Changelog. The release job extracts the notes by
matching a heading of exactly this shape:

```markdown
## [1.0.1] - 2026-09-04
```

Everything between that line and the next `## ` becomes the release body. The
job fails if the heading is missing or the section is empty, before it builds
anything. Use the standard subheadings (`### Added`, `### Changed`, `### Fixed`,
`### Security`, `### Removed`) and keep the link reference at the bottom of the
file up to date:

```markdown
[1.0.1]: https://github.com/perfectoweb/belay/releases/tag/v1.0.1
```

Write it for someone deciding whether to install the update. The commit log is
not release notes, which is why the job does not generate them from it.

### 3. Run a dry run first

Actions > Release > Run workflow, with the tag input left **empty**. That builds,
signs, notarizes, staples and verifies, uploads the DMG as a workflow artifact,
and publishes nothing. A failure costs nothing public.

Do this for the first release without exception, and after any change to
`scripts/release.sh`, `scripts/notarize.sh` or the runner image.

### 4. Verify by hand

CI proves the artefact is well formed. It cannot prove Belay works. Before
tagging, run the local gate and walk the manual list:

```bash
scripts/build-local.sh Release
scripts/verify-release.sh
```

That runs the tests, the sanitizer pass, the signature and `Info.plist` checks
and the MAS audit, and then prints every unchecked item in
`docs/QA-CHECKLIST.md`. Those items are the ones no machine can do: whether a
real Claude Code session is detected, whether the assertion is released when the
app is force-quit, and whether it behaves on macOS 14 and 15 (B5).

### 5. Tag

The tag must be `v` followed by `MARKETING_VERSION` exactly. The job compares
them and refuses to build if they disagree, because a DMG whose filename says
one version and whose `Info.plist` says another is a support problem forever.

```bash
git tag -a v1.0.1 -m "Belay 1.0.1"
git push origin v1.0.1
```

Pushing the tag starts the release job.

### 6. Check the result

On the workflow run:

- The verify step shows `codesign --verify --deep --strict`, `spctl -a -vvv`
  and two `xcrun stapler validate` calls, all passing. Any failure fails the job
  and nothing is published.
- The signing details line shows `TeamIdentifier=VSY2EB4Y9E`, an
  `Authority=Developer ID Application` chain, `flags=0x10000(runtime)` and a
  `Timestamp=`.
- The cleanup step ran and says the keychain was removed.

On the release page:

- `Belay-<version>.dmg` and `Belay-<version>.dmg.sha256` are both attached.
- The notes are the CHANGELOG section, not a list of commits.
- The SHA-256 in the notes matches the sidecar file.

Then, on a Mac that did not build it, ideally one that has never seen the source:

```bash
shasum -a 256 ~/Downloads/Belay-1.0.1.dmg          # matches the published digest
spctl -a -t open --context context:primary-signature ~/Downloads/Belay-1.0.1.dmg
xcrun stapler validate ~/Downloads/Belay-1.0.1.dmg
```

Turn the Wi-Fi off and open the DMG and the app. Offline is the real test of
stapling: if the ticket is missing, an online Mac quietly asks Apple and looks
fine, and an offline one shows the Gatekeeper block that a user would hit.

---

## Rolling back

Nothing is deleted, and no release is ever quietly amended. Users who already
downloaded a bad build cannot be un-downloaded, so the goal is to stop new
downloads and to make the fixed version obviously newer.

**Immediately.** Mark the release as a pre-release, or delete the release while
keeping the tag, so it stops being "latest":

```bash
gh release edit v1.0.1 --prerelease
# or
gh release delete v1.0.1 --yes            # leaves the tag in place
```

Add a line at the top of the release notes saying what is wrong and what to do.
Removing the assets is worth it only if the build is actively harmful; otherwise
leaving them lets anyone who already has one verify what they got.

**Do not** delete the tag and move it to a different commit. Anyone who fetched
it keeps the old object, and the two disagree forever with no signal that they
do.

**Then.** Fix the problem, bump to the next patch version, add a CHANGELOG
section that names the withdrawn version, and release again. `1.0.2` superseding
`1.0.1` is legible. Re-releasing `1.0.1` with different bytes is not.

Once Sparkle is wired up (B3) there is a third step: rerun
`scripts/sign-update.sh` so the appcast stops offering the withdrawn version.
Sparkle serves whatever the appcast says regardless of what the GitHub Release
page shows.

---

## What CI does not do

**No Mac App Store submission.** The upload is easy and is deliberately absent.
The MAS build is blocked on B2, the StoreKit consumable product IDs, which cannot
be registered without the account owner; every submission needs review notes and
a demo video written by hand, which `docs/06-DISTRIBUTION.md` describes and which
are prose rather than build settings; and an automated upload burns a build
number on every tag whether or not anybody meant to submit. What CI does own is
the machine-checkable half: `ci.yml` builds `Belay-MAS` and runs
`scripts/verify-mas-build.sh` on every push, so a Sparkle symbol or a stray
`network.client` entitlement is caught long before a human opens Transporter.

**No appcast.** Sparkle is not in the build (B3). When it is,
`scripts/sign-update.sh` still runs on the maintainer's machine, because the
EdDSA private key lives in their login Keychain by design. Copying it into a
repository secret would defeat the point of signing updates.

**No proof the app works.** `docs/QA-CHECKLIST.md` is that, and it is done by
hand on a real Mac with a real agent on it.

## When something fails

- **`no 'Developer ID Application' identity in the keychain`** from
  `scripts/release.sh` preflight. The `.p12` imported but has no private key, or
  the base64 was truncated. Re-export from Keychain Access, expanding the
  certificate first to confirm the key is attached.
- **The job hangs during signing.** `set-key-partition-list` did not take, and
  `codesign` is waiting on a prompt. This is why that step exists; check it ran.
- **`notarytool store-credentials` fails.** The issuer ID is wrong, the key was
  revoked, or the key lacks the Developer role. It validates against Apple before
  writing, so this fails fast and says which.
- **Notarization returns `Invalid`.** `scripts/notarize.sh` prints the full log
  rather than the summary. Usually a missing secure timestamp, a nested binary
  signed without hardened runtime, or an entitlement that Developer ID does not
  allow. Fix, then re-run just the notarize step locally on the DMG you already
  have instead of rebuilding:
  `scripts/notarize.sh dist/Belay-1.0.1.dmg`.
- **`create-dmg` stalls.** It configures the DMG window with AppleScript, which
  wants a Finder session. On a headless runner it can wait before giving up. If
  this turns out to be the recurring failure, replace the DMG with a signed zip
  in `scripts/release.sh`; the notarize, staple and verify steps accept a `.zip`
  unchanged.
- **`spctl` rejects a notarized build.** Check `stapler validate` first. If the
  ticket is there and `spctl` still rejects, the app was stapled but the DMG was
  not, or the other way round; the workflow validates both for this reason.
