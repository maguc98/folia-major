#!/usr/bin/env bash
set -euo pipefail

VERSION="${NODE_MOBILE_VERSION:-18.20.4}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/Frameworks/NodeMobile.framework"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

URL="https://github.com/nodejs-mobile/nodejs-mobile/releases/download/v${VERSION}/nodejs-mobile-v${VERSION}-ios.zip"
ARCHIVE="$TMP/nodejs-mobile-ios.zip"

echo "Downloading NodeMobile iOS v${VERSION} from the official nodejs-mobile release..."
curl --fail --location --retry 3 --retry-delay 2 "$URL" -o "$ARCHIVE"
mkdir -p "$TMP/unpacked"
unzip -q "$ARCHIVE" -d "$TMP/unpacked"

# Prefer the device-only XCFramework slice. The archive also contains a
# simulator slice, and selecting the first NodeMobile.framework by name can
# silently pick that incompatible binary for an iPhoneOS build.
SOURCE="$(find "$TMP/unpacked" -type d -path '*/NodeMobile.xcframework/ios-arm64/NodeMobile.framework' -print -quit)"
if [[ -z "$SOURCE" ]]; then
  SOURCE="$(find "$TMP/unpacked" -type d -path '*/Release-iphoneos/NodeMobile.framework' -print -quit)"
fi
if [[ -z "$SOURCE" || ! -f "$SOURCE/NodeMobile" || ! -f "$SOURCE/Info.plist" ]]; then
  echo "::error::Device-only NodeMobile.framework (ios-arm64) was not found in the official iOS archive."
  find "$TMP/unpacked" -maxdepth 5 -type d -name 'NodeMobile.framework' -print || true
  exit 1
fi

ARCHS="$(xcrun lipo -archs "$SOURCE/NodeMobile")"
echo "NodeMobile architectures: $ARCHS"
if [[ " $ARCHS " != *" arm64 "* ]]; then
  echo "::error::Selected NodeMobile.framework does not contain the arm64 device architecture."
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
ditto "$SOURCE" "$DEST"

echo "Prepared device-only NodeMobile.framework:"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DEST/Info.plist"
xcrun lipo -archs "$DEST/NodeMobile"
