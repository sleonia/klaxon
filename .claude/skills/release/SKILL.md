---
name: release
description: Use when cutting or publishing a new Klaxon release — bump the version, build the ad-hoc-signed DMG, and publish it as a GitHub Release with the stable `Klaxon.dmg` asset the download buttons depend on. Trigger on "release Klaxon", "ship a new version", "publish v1.x".
---

# Cut a Klaxon release

End to end: bump version → build + ad-hoc-sign the DMG → publish a GitHub Release
with **two** assets (versioned + stable-named).

Klaxon has **no paid Apple Developer Program**, so the DMG is *ad-hoc signed* and
**not notarized**. A downloaded copy therefore hits a one-time macOS Gatekeeper
prompt (documented in the README). This is expected — do **not** attempt to
notarize or sign with a Developer ID; there is no certificate.

There is **no Homebrew distribution** — distribution is the DMG only.

## Preconditions

- `gh auth status` → logged in as `sleonia` (repo scope).
- Working tree clean, on the branch you're releasing from.

## Steps

Pick the new version once (semver, no leading `v`):

```sh
VERSION=1.2.0
```

**1 — Bump the app version** in `Resources/Info.plist`, then commit it:

```sh
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Resources/Info.plist
git commit -am "chore: bump version to $VERSION"
```

**2 — Build the DMG** (ad-hoc signed):

```sh
./Scripts/make-dmg.sh        # → build/Klaxon-$VERSION.dmg  +  "SHA-256: <hash>"
```

**3 — Publish the GitHub Release** with BOTH assets — the versioned DMG for the
release page, and an unversioned `Klaxon.dmg` copy that the stable download URL
resolves to:

```sh
cp "build/Klaxon-$VERSION.dmg" build/Klaxon.dmg
gh release create "v$VERSION" "build/Klaxon-$VERSION.dmg" build/Klaxon.dmg \
  --title "Klaxon v$VERSION" \
  --latest \
  --notes "<highlights>

## Install
Download the DMG, drag Klaxon to Applications. First launch of a downloaded copy
is blocked by Gatekeeper (unsigned/un-notarized); bypass once with
\`xattr -dr com.apple.quarantine /Applications/Klaxon.app\` or right-click → Open."
```

Push the branch/tag if not already: `git push` (the release tag is created by
`gh` on the target commit — make sure that commit is pushed).

**4 — Verify** the stable download URL serves the new version:

```sh
curl -fsSLo /tmp/Klaxon-check.dmg https://github.com/sleonia/klaxon/releases/latest/download/Klaxon.dmg
shasum -a 256 /tmp/Klaxon-check.dmg   # must match the SHA-256 printed in step 2
```

## Notes

- The DMG is **never committed to git** — it exists only as a Release asset.
- **The unversioned `Klaxon.dmg` asset is load-bearing.** The download buttons in
  `README.md`, `README.ru.md`, and `site/index.html` all point at
  `https://github.com/sleonia/klaxon/releases/latest/download/Klaxon.dmg`, which
  GitHub resolves to the asset *with exactly that name* on the release marked
  **Latest**. Forget the asset (or the `--latest` flag) and every download button
  404s.
- Humans browsing older builds use the release page; the versioned
  `Klaxon-$VERSION.dmg` asset keeps downloads distinguishable.
