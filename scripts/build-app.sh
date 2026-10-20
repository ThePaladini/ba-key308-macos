#!/bin/bash
# Builds "BA-KEY Menu.app" and the `bakey` CLI into ./build.
# Usage: scripts/build-app.sh [--install | --release]
#   --install  copies the app to /Applications (and the CLI to ~/.local/bin), then launches it
#   --release  also writes zips + checksums to build/release for a GitHub release
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/BA-KEY Menu.app"

# Universal binary (Apple Silicon + Intel).
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" --product BAKeyMenu
swift build -c release "${ARCHS[@]}" --product bakey
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/BAKeyMenu" "$APP/Contents/MacOS/BAKeyMenu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate: swift tools/make-icon.swift Resources/AppIcon.icns
cp "$BIN/bakey" build/bakey

# Signing. A stable identity keeps macOS privacy permissions (Input Monitoring) across rebuilds;
# an ad-hoc signature changes every build and macOS then treats the app as a new one.
# Create the identity once with scripts/make-dev-cert.sh. Not notarized either way.
IDENTITY="BA-KEY Menu Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    SIGN="$IDENTITY"
else
    SIGN="-"
    echo "warning: '$IDENTITY' not found, using ad-hoc signing (permissions reset on every rebuild)"
fi
codesign --force --sign "$SIGN" "$APP"
codesign --force --sign "$SIGN" build/bakey

echo "Built: $APP"
echo "Built: build/bakey"

if [[ "${1:-}" == "--release" ]]; then
    # Zips for a GitHub release: build/release/BA-KEY-Menu-<version>.zip and bakey-<version>.zip
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
    mkdir -p build/release
    rm -f build/release/*.zip
    ditto -c -k --keepParent "$APP" "build/release/BA-KEY-Menu-$VERSION.zip"
    ditto -c -k build/bakey "build/release/bakey-$VERSION.zip"
    (cd build/release && shasum -a 256 *.zip > SHA256SUMS.txt)
    ls -la build/release
fi

if [[ "${1:-}" == "--install" ]]; then
    pkill -x BAKeyMenu 2>/dev/null && sleep 1 || true
    rm -rf "/Applications/BA-KEY Menu.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/BA-KEY Menu.app"
    # The CLI goes to ~/.local/bin when that directory is on PATH.
    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
        mkdir -p "$HOME/.local/bin" && cp build/bakey "$HOME/.local/bin/bakey"
        echo "Installed CLI to ~/.local/bin/bakey"
    else
        echo "CLI not installed (add ~/.local/bin to PATH, or copy build/bakey somewhere on PATH)"
    fi
    open "/Applications/BA-KEY Menu.app"
fi
