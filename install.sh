#!/bin/bash
# Murmie installer. Run with:
#   curl -fsSL https://raw.githubusercontent.com/shuul-io/murmie-releases/main/install.sh | bash
#
# Downloads the latest Murmie.dmg from this repo's GitHub releases, checks its checksum, signature and
# notarization, copies Murmie.app into /Applications and opens it.
#
# Everything runs inside main(), so a download cut short by the pipe never runs a partial script.
# Commands that could read stdin get </dev/null: under `curl | bash`, stdin is the script itself.
set -euo pipefail

BASE_URL="https://github.com/shuul-io/murmie-releases/releases/latest/download"
APP_NAME="Murmie.app"
BUNDLE_ID="com.murmie.app"
DEST="/Applications"

# Cleanup state lives at script level, not inside main(): the EXIT trap runs after main() has returned, when its
# local variables no longer exist.
WORK_DIR=""       # scratch folder with the download
MOUNT_DIR=""      # where the disk image is mounted
STAGED_APP=""     # the new app, copied next to the installed one
BACKUP_APP=""     # the previous app, set aside while the new one is moved into place
FINAL_APP=""      # where the app is installed
SUDO=""           # "sudo" when /Applications needs the administrator password

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf 'Murmie: %s\n' "$*" >&2; exit 1; }

# Runs on every exit, including errors and Ctrl-C. Puts the previous app back if the swap was interrupted,
# then removes everything this script created.
cleanup() {
  # An interrupted swap: the old app was set aside and the new one is not in place yet
  if [ -n "$BACKUP_APP" ] && [ -e "$BACKUP_APP" ] && [ ! -e "$FINAL_APP" ]; then
    $SUDO mv "$BACKUP_APP" "$FINAL_APP" 2>/dev/null || true
  fi
  if [ -n "$STAGED_APP" ]; then $SUDO rm -rf "$STAGED_APP" 2>/dev/null || true; fi
  if [ -n "$MOUNT_DIR" ]; then
    hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || hdiutil detach "$MOUNT_DIR" -force -quiet >/dev/null 2>&1 || true
  fi
  if [ -n "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

main() {
  # Requirements: macOS 26 or later on Apple silicon
  [ "$(uname -s)" = "Darwin" ] || fail "Murmie only runs on macOS."
  # hw.optional.arm64 is 1 on Apple silicon, even when this shell runs under Rosetta
  [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ] || fail "Murmie needs a Mac with Apple silicon."
  local version major
  version="$(sw_vers -productVersion)"
  major="${version%%.*}"
  [ "$major" -ge 26 ] 2>/dev/null || fail "Murmie needs macOS 26 or later (this Mac has $version)."

  # Ask for the administrator password up front only if /Applications is not writable by this user
  if [ ! -w "$DEST" ] || { [ -e "$DEST/$APP_NAME" ] && [ ! -O "$DEST/$APP_NAME" ]; }; then
    say "Installing into $DEST needs an administrator password."
    sudo -v </dev/tty || fail "Could not get administrator rights. Download the DMG from murmie.com instead."
    SUDO="sudo"
  fi

  # Scratch folder for the download; cleanup() unmounts the disk image and deletes the folder on exit
  WORK_DIR="$(mktemp -d)"
  MOUNT_DIR="$WORK_DIR/mnt"

  # Download the disk image and the release checksums (https only, retried)
  say "Downloading Murmie..."
  curl -fL --proto '=https' --tlsv1.2 --retry 3 --progress-bar "$BASE_URL/Murmie.dmg" -o "$WORK_DIR/Murmie.dmg" </dev/null \
    || fail "Download failed. Check your connection, or download the DMG from murmie.com."
  curl -fsSL --proto '=https' --tlsv1.2 --retry 3 "$BASE_URL/SHA256SUMS" -o "$WORK_DIR/SHA256SUMS" </dev/null \
    || fail "Could not download the checksum file. Nothing was installed."

  # The DMG must match the checksum published with the release
  local expected actual
  expected="$(awk '$2 == "Murmie.dmg" { print $1 }' "$WORK_DIR/SHA256SUMS")"
  actual="$(shasum -a 256 "$WORK_DIR/Murmie.dmg" | awk '{ print $1 }')"
  [ -n "$expected" ] && [ "$expected" = "$actual" ] || fail "The download does not match its published checksum. Nothing was installed."

  # Open the disk image read-only, without showing it in Finder
  mkdir -p "$MOUNT_DIR"
  hdiutil attach "$WORK_DIR/Murmie.dmg" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet </dev/null \
    || fail "Could not open the disk image."
  [ -d "$MOUNT_DIR/$APP_NAME" ] || fail "$APP_NAME was not found in the disk image."

  # curl does not quarantine files, so Gatekeeper would not check the app at first launch. Check it here:
  # a valid signature, and accepted by Gatekeeper as a notarized app.
  codesign --verify --deep --strict "$MOUNT_DIR/$APP_NAME" </dev/null 2>/dev/null \
    || fail "The app's code signature is invalid. Nothing was installed."
  spctl --assess --type execute "$MOUNT_DIR/$APP_NAME" </dev/null 2>/dev/null \
    || fail "macOS did not accept the app (not notarized). Nothing was installed."

  # Quit a running copy so it can be replaced; give it up to 10 seconds
  if pgrep -xq Murmie; then
    say "Quitting the running copy of Murmie..."
    osascript -e "quit app id \"$BUNDLE_ID\"" </dev/null >/dev/null 2>&1 || true
    local i=0
    while pgrep -xq Murmie && [ "$i" -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
    pgrep -xq Murmie && fail "Murmie is still running. Quit it from the menu bar and run this again."
  fi

  # Copy the new app next to the old one first, so a failed copy never touches the installed app
  say "Installing to $DEST..."
  FINAL_APP="$DEST/$APP_NAME"
  STAGED_APP="$DEST/.$APP_NAME.new"
  BACKUP_APP="$DEST/.$APP_NAME.previous"
  $SUDO rm -rf "$STAGED_APP" "$BACKUP_APP"
  $SUDO ditto "$MOUNT_DIR/$APP_NAME" "$STAGED_APP" </dev/null || fail "Copying the app failed."

  # Swap: set the old app aside, move the new one in, and only then delete the old one.
  # If the move fails (or the script is interrupted), cleanup() puts the old app back.
  if [ -e "$FINAL_APP" ]; then
    $SUDO mv "$FINAL_APP" "$BACKUP_APP" || fail "Could not replace the installed app. Nothing was changed."
  fi
  if ! $SUDO mv "$STAGED_APP" "$FINAL_APP"; then
    fail "Could not move the new app into place. The previous version was restored."
  fi
  $SUDO rm -rf "$BACKUP_APP"

  say "Done. Opening Murmie."
  open "$FINAL_APP"
}

main "$@"
