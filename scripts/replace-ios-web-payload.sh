#!/usr/bin/env bash
# Replace only Payload/App.app/public in an already-extracted app bundle.
# This invalidates the app's existing code signature; re-sign before installation.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 /path/to/Payload/App.app /path/to/Folia-iOS-3.0.6-build379-public-sanitized-v2.zip" >&2
  exit 2
fi

APP_BUNDLE="$(cd "$1" && pwd)"
ARCHIVE="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERIFIER="$REPO_ROOT/tools/ios-build379/verify_payload.py"

[[ "$APP_BUNDLE" == *.app ]] || { echo "Target must be an extracted .app bundle." >&2; exit 2; }
[[ -d "$APP_BUNDLE/public" ]] || { echo "Target has no public/ directory; refusing to modify it." >&2; exit 1; }
[[ -f "$ARCHIVE" ]] || { echo "Archive not found: $ARCHIVE" >&2; exit 1; }
[[ -f "$VERIFIER" ]] || { echo "Verifier not found: $VERIFIER" >&2; exit 1; }

python3 "$VERIFIER" "$ARCHIVE"

STAGE="$(mktemp -d)"
BACKUP="$(mktemp -d)"
RESTORE_NEEDED=0
cleanup() {
  if [[ "$RESTORE_NEEDED" -eq 1 && -d "$BACKUP/public" ]]; then
    rm -rf "$APP_BUNDLE/public"
    mv "$BACKUP/public" "$APP_BUNDLE/public"
  fi
  rm -rf "$STAGE" "$BACKUP"
}
trap cleanup EXIT

python3 - "$ARCHIVE" "$STAGE" <<'PY'
import pathlib, sys, zipfile
archive, destination = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
with zipfile.ZipFile(archive) as zf:
    for info in zf.infolist():
        if info.is_dir():
            continue
        member = pathlib.PurePosixPath(info.filename)
        if member.is_absolute() or ".." in member.parts:
            raise SystemExit(f"Unsafe archive path: {info.filename}")
        target = destination.joinpath(*member.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        with zf.open(info) as source, target.open("wb") as output:
            output.write(source.read())
PY

[[ -d "$STAGE/public" ]] || { echo "Archive did not produce public/." >&2; exit 1; }
mv "$APP_BUNDLE/public" "$BACKUP/public"
RESTORE_NEEDED=1
mv "$STAGE/public" "$APP_BUNDLE/public"
RESTORE_NEEDED=0

echo "Web payload replaced successfully."
echo "IMPORTANT: the original iOS code signature is now invalid. Re-sign the app with your own authorized signing identity before installation."
echo "This operation does not rebuild or modify the native executable or embedded frameworks."
