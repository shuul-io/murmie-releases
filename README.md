# Murmie releases

**Just say it. Murmie types it.**

Downloads for [Murmie](https://murmie.com). Private, on-device voice dictation for macOS. Requires an Apple silicon Mac running macOS 26 or later.

Only the latest release is kept. Its notes are on the [Releases page](https://github.com/shuul-io/murmie-releases/releases/latest).

## Install

**Download:** get `Murmie.dmg` from the [latest release](https://github.com/shuul-io/murmie-releases/releases/latest), open it and drag Murmie to Applications.

**Terminal:**

```sh
curl -fsSL https://raw.githubusercontent.com/shuul-io/murmie-releases/main/install.sh | bash
```

The script checks that the download matches its published checksum, that its code signature is valid and that Gatekeeper accepts it as notarized, and only then installs it. Read it first: [`install.sh`](install.sh).

**Homebrew:**

```sh
brew install --cask shuul-io/tap/murmie
```

## Updates

Murmie checks for updates about once a day (Settings › About) and installs them itself.

## Check a download by hand

```sh
shasum -a 256 -c SHA256SUMS      # with Murmie.dmg and the release's SHA256SUMS in the same folder
codesign --verify --deep --strict -v Murmie.app       # valid on disk
spctl --assess --type execute -v Murmie.app           # accepted, source=Notarized Developer ID
```

## Support

Found a bug or have an idea? [Send feedback](https://docs.google.com/forms/d/e/1FAIpQLSfUrZhSzuPhFYLApsgoAe5H9uoxGWTeSjjfvXB-pjX3Ll7KkA/viewform).
