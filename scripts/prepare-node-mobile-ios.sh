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

SOURCE="$(find "$TMP/unpacked" -type d -path '*/Release-iphoneos/NodeMobile.framework' -print -quit)"
if [[ -z "$SOURCE" ]]; then
  SOURCE="$(find "$TMP/unpacked" -type d -name 'NodeMobile.framework' -print -quit)"
fi
if [[ -z "$SOURCE" || ! -f "$SOURCE/NodeMobile" ]]; then
  echo "::error::NodeMobile.framework was not found in the official iOS archive."
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
ditto "$SOURCE" "$DEST"

echo "Prepared NodeMobile.framework:"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DEST/Info.plist"
