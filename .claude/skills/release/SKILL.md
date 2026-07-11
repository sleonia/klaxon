---
name: release
description: Use when cutting or publishing a new Klaxon release — bump the version, build and publish the ad-hoc-signed DMG as a GitHub Release, and bump the Homebrew cask in sleonia/homebrew-tap so `brew install --cask sleonia/tap/klaxon` picks up the new version. Trigger on "release Klaxon", "ship a new version", "publish v1.x", "update the cask".
---

# Cut a Klaxon release

End to end: bump version → build + ad-hoc-sign the DMG → publish a GitHub Release →
bump the Homebrew cask.

Klaxon has **no paid Apple Developer Program**, so the DMG is *ad-hoc signed* and
**not notarized**. A downloaded copy therefore hits a one-time macOS Gatekeeper
prompt (documented in the README and the cask `caveats`). This is expected — do
**not** attempt to notarize or sign with a Developer ID; there is no certificate.

## Preconditions

- `gh auth status` → logged in as `sleonia` (repo scope).
- Working tree clean, on the branch you're releasing from.
- The tap is cloned locally: `$(brew --repository sleonia/homebrew-tap)` exists
  (created once with `brew tap-new sleonia/homebrew-tap`; the repo lives at
  github.com/sleonia/homebrew-tap).

## Steps

Pick the new version once (semver, no leading `v`):

```sh
VERSION=1.1.0
```

**1 — Bump the app version** in `Resources/Info.plist`, then commit it:

```sh
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Resources/Info.plist
git commit -am "chore: bump version to $VERSION"
```

**2 — Build the DMG** (ad-hoc signed; prints the SHA-256 the cask needs):

```sh
./Scripts/make-dmg.sh        # → build/Klaxon-$VERSION.dmg  +  "SHA-256: <hash>"
```

**3 — Publish the GitHub Release** with the DMG attached:

```sh
gh release create "v$VERSION" "build/Klaxon-$VERSION.dmg" \
  --title "Klaxon v$VERSION" \
  --notes "<highlights>

## Install
Download the DMG, drag Klaxon to Applications. First launch of a downloaded copy
is blocked by Gatekeeper (unsigned/un-notarized); bypass once with
\`xattr -dr com.apple.quarantine /Applications/Klaxon.app\` or right-click → Open."
```

Push the branch/tag if not already: `git push && git push --tags` (or the release
tag is created by `gh` on the target commit — make sure that commit is pushed).

**4 — Bump the Homebrew cask.** Preferred (recomputes the SHA from the new release):

```sh
brew bump-cask-pr --version "$VERSION" sleonia/homebrew-tap/klaxon
```

Or by hand — edit `$(brew --repository sleonia/homebrew-tap)/Casks/klaxon.rb`,
setting `version` and the `sha256` printed in step 2, then:

```sh
brew style --fix sleonia/homebrew-tap/klaxon
brew audit --cask sleonia/homebrew-tap/klaxon
TAP="$(brew --repository sleonia/homebrew-tap)"
git -C "$TAP" commit -am "klaxon $VERSION" && git -C "$TAP" push
```

**5 — Verify** the user-facing command resolves the new version:

```sh
brew fetch --cask sleonia/tap/klaxon     # downloads + checksum-verifies, no install
```

## Notes

- The DMG is **never committed to git** — it exists only as a Release asset. The
  cask pins the versioned URL `…/releases/download/v#{version}/Klaxon-#{version}.dmg`
  plus the SHA-256; humans download from `/releases/latest`.
- `livecheck` (`strategy :github_latest`) lets `brew bump-cask-pr` / `brew livecheck`
  find new versions automatically — mark each GitHub Release **"Latest"**.
- Homebrew 6.0+ requires trusting third-party taps. First-time users run the
  one-liner `brew install --cask sleonia/tap/klaxon` and confirm the trust prompt
  once; `brew install --cask klaxon` (bare) will **not** find it — the tap name is
  required.
- The versioned asset filename must match the cask's `url` (`Klaxon-#{version}.dmg`).
