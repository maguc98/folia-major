#!/usr/bin/env python3
"""Verify the sanitized Folia iOS build 379 public payload before importing it.

This checks archive integrity and basic safety properties. It does not prove
that the payload is trustworthy or that the original iOS app can be rebuilt.
"""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import sys
import zipfile

EXPECTED_SHA256 = "f8e08042914a01f63f8aabbadd9f61cca32dd92fd45cfe194495f1e40acbab32"
SENSITIVE_PARTS = (
    ".auth-state",
    "embedded.mobileprovision",
    "_codesignature",
    "server.key",
    "server.crt",
    "ca.crt",
)
SENSITIVE_SUFFIXES = (".p12", ".pfx", ".mobileprovision")


def digest(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=pathlib.Path)
    parser.add_argument("--expected-sha256", default=EXPECTED_SHA256)
    args = parser.parse_args()

    archive = args.archive
    if not archive.is_file():
        fail(f"archive not found: {archive}")

    actual_hash = digest(archive)
    if actual_hash.lower() != args.expected_sha256.lower():
        fail(f"SHA-256 mismatch: expected {args.expected_sha256}, got {actual_hash}")

    try:
        with zipfile.ZipFile(archive) as zf:
            bad_member = zf.testzip()
            if bad_member:
                fail(f"CRC failure in archive member: {bad_member}")

            files = [item for item in zf.infolist() if not item.is_dir()]
            if not files:
                fail("archive contains no files")

            unsafe_paths: list[str] = []
            symlinks: list[str] = []
            sensitive_paths: list[str] = []
            for item in files:
                member = pathlib.PurePosixPath(item.filename)
                if member.is_absolute() or ".." in member.parts or "\\\\" in item.filename:
                    unsafe_paths.append(item.filename)

                mode = (item.external_attr >> 16) & 0xFFFF
                if mode and (mode & 0o170000) == 0o120000:
                    symlinks.append(item.filename)

                lower = item.filename.lower()
                if any(part in lower for part in SENSITIVE_PARTS) or lower.endswith(SENSITIVE_SUFFIXES):
                    sensitive_paths.append(item.filename)

            if unsafe_paths:
                fail("unsafe archive paths: " + ", ".join(unsafe_paths[:8]))
            if symlinks:
                fail("symbolic links are not accepted: " + ", ".join(symlinks[:8]))
            if sensitive_paths:
                fail("sensitive/signing paths detected: " + ", ".join(sensitive_paths[:8]))

            names = set(item.filename for item in files)
            required = {
                "public/index.html",
                "public/runtime-config.js",
                "public/nodejs-project/package.json",
                "public/nodejs-project/main.js",
            }
            missing = sorted(required - names)
            if missing:
                fail("required payload files missing: " + ", ".join(missing))

            index = zf.read("public/index.html").decode("utf-8", errors="replace")
            refs = sorted(set(re.findall(r'''(?:src|href)=["']([^"']+)["']''', index)))
            missing_refs: list[str] = []
            for ref in refs:
                if ref.startswith(("http:", "https:", "data:", "//", "#", "javascript:")):
                    continue
                relative = ref.split("?", 1)[0].split("#", 1)[0].lstrip("/")
                while relative.startswith("./"):
                    relative = relative[2:]
                if relative and f"public/{relative}" not in names:
                    missing_refs.append(ref)
            if missing_refs:
                fail("missing local index.html references: " + ", ".join(missing_refs))

            total_size = sum(item.file_size for item in files)
            print("PASS: sanitized payload verification")
            print(f"SHA-256: {actual_hash}")
            print(f"Files: {len(files):,}")
            print(f"Uncompressed bytes: {total_size:,}")
            print(f"Local HTML references checked: {len(refs)}")
            print("Unsafe paths: 0; symlinks: 0; sensitive/signing paths: 0")
            print("Required web and NodeMobile entry files: present")
            print("Note: this is archive validation, not an Xcode build or runtime test.")
    except zipfile.BadZipFile as exc:
        fail(f"invalid ZIP archive: {exc}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
