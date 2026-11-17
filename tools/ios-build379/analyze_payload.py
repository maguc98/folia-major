#!/usr/bin/env python3
"""Analyze the sanitized public/ payload extracted from Folia iOS build 379."""
from __future__ import annotations
import argparse, collections, hashlib, json, os, pathlib, re, zipfile

def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

def safe_name(name: str) -> bool:
    p = pathlib.PurePosixPath(name)
    return not p.is_absolute() and ".." not in p.parts

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("archive", type=pathlib.Path)
    ap.add_argument("--output", type=pathlib.Path, default=pathlib.Path("analysis-output"))
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.archive
    findings = []
    with zipfile.ZipFile(archive) as z:
        infos = [i for i in z.infolist() if not i.is_dir()]
        unsafe = [i.filename for i in infos if not safe_name(i.filename)]
        if unsafe:
            raise SystemExit("Unsafe archive paths found; refusing extraction: " + ", ".join(unsafe[:10]))
        names = [i.filename for i in infos]
        ext_counts = collections.Counter(pathlib.PurePosixPath(n).suffix.lower() or "[no extension]" for n in names)
        total_uncompressed = sum(i.file_size for i in infos)
        root_prefix = "public/"
        public_names = [n for n in names if n.startswith(root_prefix)]
        if not public_names:
            raise SystemExit("Expected a sanitized ZIP containing a public/ directory.")
        forbidden = [n for n in names if ".auth-state" in n or "embedded.mobileprovision" in n or "_CodeSignature" in n]
        if forbidden:
            findings.append("WARNING: sensitive or signature-related paths detected: " + ", ".join(forbidden[:10]))
        else:
            findings.append("No .auth-state, embedded.mobileprovision, or _CodeSignature paths detected in the archive.")
        extract_root = args.output / "extracted"
        extract_root.mkdir(exist_ok=True)
        for info in infos:
            dest = extract_root / info.filename
            dest.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as src, dest.open("wb") as dst:
                dst.write(src.read())

    base = extract_root / "public"
    index = base / "index.html"
    html = index.read_text("utf-8", errors="replace") if index.exists() else ""
    refs = sorted(set(re.findall(r'''(?:src|href)=["']([^"']+)["']''', html)))
    js_files = sorted(str(p.relative_to(base)) for p in base.rglob("*.js"))
    css_files = sorted(str(p.relative_to(base)) for p in base.rglob("*.css"))
    package_files = sorted(str(p.relative_to(base)) for p in base.rglob("package.json"))
    visualizer_dir = base / "assets"\n    visualizers = sorted(p.name for p in visualizer_dir.glob("*") if re.search(r"visualizer|partita|sonnet|tempera|lumiere", p.name, re.I)) if visualizer_dir.exists() else []
    runtime = base / "runtime-config.js"
    scale = base / "ios-fix" / "scale.js"
    runtime_text = runtime.read_text("utf-8", errors="replace") if runtime.exists() else ""
    scale_text = scale.read_text("utf-8", errors="replace") if scale.exists() else ""
    if index.exists():
        findings.append("Web entry point public/index.html is present.")
    else:
        findings.append("WARNING: public/index.html is missing.")
    if "runtime-config.js" in html:
        findings.append("index.html references runtime-config.js.")
    if runtime.exists() and ("__FOLIA_RUNTIME_CONFIG__" in runtime_text):
        findings.append("runtime-config.js defines __FOLIA_RUNTIME_CONFIG__; inspect deployment-time injection before assuming configuration is complete.")
    if scale.exists():
        findings.append("iOS scale adaptation file public/ios-fix/scale.js is present.")
        if "NAS" in scale_text or "本机预览服务" in scale_text:
            findings.append("scale.js comments indicate injection by a local preview service/NAS gateway; provenance should be confirmed before treating it as upstream code.")
    largest = sorted(((p.stat().st_size, str(p.relative_to(base))) for p in base.rglob("*") if p.is_file()), reverse=True)[:30]
    manifest = {
        "archive": archive.name,
        "archive_bytes": archive.stat().st_size,
        "archive_sha256": sha256(archive),
        "file_count": len(infos),
        "uncompressed_bytes": total_uncompressed,
        "public_file_count": len(public_names),
        "extension_counts": dict(ext_counts.most_common()),
        "html_references": refs,
        "javascript_file_count": len(js_files),
        "css_file_count": len(css_files),
        "package_json_files": package_files,
        "visualizer_related_assets": visualizers,
        "largest_files": [{"bytes": n, "path": p} for n, p in largest],
        "findings": findings,
    }
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    lines = [
        "# Folia iOS Build 379 — Automated Payload Analysis",
        "",
        f"- Archive: `{archive.name}`",
        f"- Size: {archive.stat().st_size:,} bytes",
        f"- SHA-256: `{manifest['archive_sha256']}`",
        f"- Files: {len(infos):,}",
        f"- Uncompressed size: {total_uncompressed:,} bytes",
        f"- JavaScript files: {len(js_files):,}",
        f"- CSS files: {len(css_files):,}",
        "",
        "## Findings",
        *[f"- {x}" for x in findings],
        "",
        "## HTML resource references",
        *[f"- `{x}`" for x in refs],
        "",
        "## Package manifests",
        *([f"- `{x}`" for x in package_files] or ["- No package.json files found."]),
        "",
        "## Visualizer-related assets",
        *([f"- `{x}`" for x in visualizers] or ["- No matching asset names found."]),
        "",
        "## Largest files",
        "| Bytes | Path |",
        "|---:|---|",
        *[f"| {n:,} | `{p}` |" for n, p in largest],
        "",
        "## Extension counts",
        "| Extension | Files |",
        "|---|---:|",
        *[f"| `{ext}` | {count:,} |" for ext, count in ext_counts.most_common()],
        "",
        "> This workflow analyzes the sanitized web payload. It does not reconstruct the original Xcode/Swift project or produce a signed IPA.",
    ]
    (args.output / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines[:22]))

if __name__ == "__main__":
    main()
