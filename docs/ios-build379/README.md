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
- Extracted files under `public/`: 8,429
- Files under `public/nodejs-project/node_modules/`: 8,157
- Extracted `public/` size: approximately 128 MiB

## Important distinction

The IPA contains a compiled native executable and packaged web/runtime assets. It does not contain a complete editable Xcode project, original Swift source tree, or the original frontend source tree. A clean rebuild from this package alone is not yet established.

## Security and licensing

- The archive contains `public/nodejs-project/.auth-state/qq-device.json`; this authentication/device-state file is deliberately excluded from any source import. Do not publish it.
- Do not commit `_CodeSignature`, provisioning profiles, signing identities, private keys, tokens, or user session state.
- Inspect runtime configuration and bundled resources for credentials, personal data, and private endpoints before importing.
- Preserve upstream and dependency license notices. The source repository's license is AGPL-3.0; review dependency-specific terms and comply with applicable attribution and source-availability obligations.
- The original IPA should remain immutable; modifications belong on this branch.

## Import status

The branch and baseline documentation exist. The complete IPA and extracted web resources have **not** been uploaded to this repository. A sanitized web payload archive was prepared locally: `Folia-iOS-3.0.6-build379-public-clean.zip` (43,202,482 bytes; SHA-256 `7a633cf4abe7c5d805700a0ab06cdda1b033c8d03e15556291b7acd106e13cef`). It contains the `public/` tree with the authentication-state directory removed. The connected GitHub operations available here do not expose a binary Git LFS or release-asset upload path, so the archive still needs to be uploaded through a binary-capable GitHub path. This is a prepared sanitized payload, not a completed repository import.

## Next engineering steps

1. Inventory native symbols, frameworks, startup flow, and Capacitor/Cordova/NodeMobile bridge behavior.
2. Map the web entry point, runtime configuration, iOS-specific CSS/JS, and renderer bundles.
3. Produce a clean source snapshot excluding authentication state, signing artifacts, and sensitive runtime data.
4. Obtain or reconstruct the editable native project/build configuration before claiming reproducible IPA builds.
5. Keep all modifications on this branch and record provenance, tests, and license notices.
