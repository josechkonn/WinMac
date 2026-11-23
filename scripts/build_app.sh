#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="WinMac"
VERSION="${1:-1.0.0}"
BUILD_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Building $APP_NAME v$VERSION (release)..."
cd "$PROJECT_DIR"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: compiled binary not found at $BIN_PATH"
    exit 1
fi

echo "Packaging $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Prefer local Apple Development identity so macOS Accessibility permissions persist across rebuilds
SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Signing with identity: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" --identifier "com.winmac.windowmanager" "$APP_BUNDLE"
else
    echo "Signing ad-hoc..."
    codesign --force --deep --sign - --identifier "com.winmac.windowmanager" "$APP_BUNDLE"
fi

echo "Built bundle successfully: $APP_BUNDLE"
