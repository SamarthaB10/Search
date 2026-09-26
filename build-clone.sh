#!/bin/bash
# Build a local Search Clone app from the same sources as build.sh.
#
#   ./build-clone.sh              release build
#   ./build-clone.sh debug        debug build
#   open -n "build/Search Clone.app"
#
# The separate bundle ID keeps this copy away from the installed Search app.
# SEARCH_PROBE makes its settings, WebKit data, and keychain labels separate.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="${1:-release}"
case "$CONFIG" in
  debug|release) ;;
  *) echo "usage: $0 [debug|release]" >&2; exit 2 ;;
esac

./build.sh "$CONFIG"

SOURCE="build/Search.app"
CLONE="build/Search Clone.app"
PLIST="$CLONE/Contents/Info.plist"

rm -rf "$CLONE"
cp -R "$SOURCE" "$CLONE"

plutil -replace CFBundleName -string "Search Clone" "$PLIST"
plutil -replace CFBundleDisplayName -string "Search Clone" "$PLIST"
plutil -replace CFBundleIdentifier -string "com.samarthab.searchclone" "$PLIST"
plutil -replace NSHumanReadableCopyright -string "© SamarthaB10 · Search Clone" "$PLIST"
plutil -replace LSEnvironment -xml '<dict><key>SEARCH_PROBE</key><string>searchclone</string></dict>' "$PLIST"

if commit="$(git rev-parse HEAD 2>/dev/null)"; then
  plutil -replace SearchCloneSourceCommit -string "$commit" "$PLIST"
fi

# Changing the plist invalidates the signature made by build.sh. An ad-hoc
# signature is enough for this local development copy.
codesign --force --deep --sign - "$CLONE" >/dev/null
echo "built: $CLONE"
