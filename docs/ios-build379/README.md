# Folia iOS 3.0.6 (Build 379) — Reference Baseline

This branch is reserved for the separately authored iOS version supplied by the repository owner for authorized study and modification. It is a binary-IPA reference, not the original Xcode source project.

## Verified package identity

- Input: `iPad-Folia-3.0.6-build379-正式版.ipa`
- Exact size: 60,939,068 bytes (approximately 58.1 MiB; 59 MB decimal)
- SHA-256: `d2702706ff6dede4533ea895b9fd42c0f718ab1f4d1cfddbcf3e21b1500218de`
- Display name: Folia
- Bundle identifier: `top.izuna.foliaios`
- Version / build: `3.0.6 (379)`
- Minimum OS: iOS 15.0
- SDK: iPhoneOS 27.0
- Xcode build metadata: 27.0 / 27A266a
- Device families: iPhone and iPad
- Main executable: `App`
- Embedded frameworks: `Capacitor.framework`, `Cordova.framework`, `NodeMobile.framework`
- Web entry point: `public/index.html`
- Front-end assets: `public/assets/` (234 files)
- iOS web adjustments: `public/ios-fix/scale.js`, `public/ios-fix/mobile-fix.css`
- Node runtime payload: `public/nodejs-project/`

## Archive inventory

- IPA archive entries: 9,715 (including directories)
- Files under sanitized v2 `public/` archive: 8,421
- Files under sanitized v2 `public/nodejs-project/node_modules/`: 8,153
- Extracted `public/` size: approximately 128 MiB

## Important distinction

The IPA contains a compiled native executable and packaged web/runtime assets. It does not contain a complete editable Xcode project, original Swift source tree, or the original frontend source tree. A clean rebuild from this package alone is not yet established.

## Security and licensing

- The original IPA contained `public/nodejs-project/.auth-state/qq-device.json`; this authentication/device-state file is excluded. The first clean pass also revealed a bundled private key/certificate set, a device-ID dataset, and backup snapshots. Sanitized v2 excludes those seven paths as well. Do not publish them.
- Do not commit `_CodeSignature`, provisioning profiles, signing identities, private keys, tokens, or user session state.
- Inspect runtime configuration and bundled resources for credentials, personal data, and private endpoints before importing.
- Preserve upstream and dependency license notices. The source repository's license is AGPL-3.0; review dependency-specific terms and comply with applicable attribution and source-availability obligations.
- The original IPA should remain immutable; modifications belong on this branch.

## GitHub Actions analysis

A workflow is available at `.github/workflows/ios-build379-analysis.yml`, with its scanner at `tools/ios-build379/analyze_payload.py`.

The workflow accepts a direct HTTPS URL to the sanitized public payload ZIP and verifies its SHA-256 before extraction. It then inventories the web entry point, JS/CSS files, package manifests, renderer-related assets, largest files, and potentially sensitive paths. The Markdown report and JSON manifest are uploaded as a GitHub Actions artifact named `folia-ios-build379-analysis`.

Expected sanitized archive:
- File: `Folia-iOS-3.0.6-build379-public-sanitized-v2.zip`
- Size: `41,823,396` bytes
- SHA-256: `f8e08042914a01f63f8aabbadd9f61cca32dd92fd45cfe194495f1e40acbab32`

The ZIP must first be placed at a stable HTTPS download location (for example, as a GitHub Release asset). The workflow default hash is pinned to the v2 archive above; do not use the superseded first-pass archive. The workflow does not accept the original IPA because it contains signing/authentication-related material that should not be published. This analysis job is not an Xcode build and does not recreate the original Swift project.

## Import status

The branch and baseline documentation exist. The complete IPA and extracted web resources have **not** been uploaded to this repository. A second sanitization pass removed the private key/certificate files, device-ID dataset, and three backup snapshots discovered during static scanning. The resulting web payload archive was prepared locally: `Folia-iOS-3.0.6-build379-public-sanitized-v2.zip` (41,823,396 bytes; SHA-256 `f8e08042914a01f63f8aabbadd9f61cca32dd92fd45cfe194495f1e40acbab32`). It contains the `public/` tree with the authentication-state directory removed. The connected GitHub operations available here do not expose a binary Git LFS or release-asset upload path, so the archive still needs to be uploaded through a binary-capable GitHub path. This is a prepared sanitized payload, not a completed repository import.

## Next engineering steps

1. Inventory native symbols, frameworks, startup flow, and Capacitor/Cordova/NodeMobile bridge behavior.
2. Map the web entry point, runtime configuration, iOS-specific CSS/JS, and renderer bundles.
3. Produce a clean source snapshot excluding authentication state, signing artifacts, and sensitive runtime data.
4. Obtain or reconstruct the editable native project/build configuration before claiming reproducible IPA builds.
5. Keep all modifications on this branch and record provenance, tests, and license notices.


## Local payload verification and replacement

A standalone verifier is available at `tools/ios-build379/verify_payload.py`. It checks the pinned SHA-256, ZIP CRCs, path traversal, symlink entries, known authentication/signing paths, required Web/NodeMobile entry files, and local references in `public/index.html`.

Run it before import:

```bash
python3 tools/ios-build379/verify_payload.py /path/to/Folia-iOS-3.0.6-build379-public-sanitized-v2.zip
```

A guarded replacement helper is available at `scripts/replace-ios-web-payload.sh`. It replaces only the `public/` directory inside an already-extracted `.app` bundle after running the verifier:

```bash
scripts/replace-ios-web-payload.sh /path/to/Payload/App.app /path/to/Folia-iOS-3.0.6-build379-public-sanitized-v2.zip
```

**Important:** replacing `public/` invalidates the original iOS code signature. The resulting app must be re-signed with an authorized signing identity before installation. This helper does not rebuild the native executable, restore missing Swift source, or produce an IPA.
