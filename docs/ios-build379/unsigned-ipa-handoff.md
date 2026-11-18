# Build Folia iOS 3.0.6 (379) — unsigned IPA

## Current verified state

- The reconstructed iOS app target compiles and links for `generic/platform=iOS` on GitHub Actions.
- Swift syntax parsing and JavaScript/native-fixture compatibility tests pass.
- The successful compile check is run `44271613752`: https://github.com/maguc98/folia-major/actions/runs/44271613752
- This is **not yet an IPA**. The compile-check workflow uses a small fixture and does not include the full Folia web/Node payload.
- The full resource archive is kept outside Git because it is a large binary dependency.

## One-time payload handoff

The sanitized archive is:

- Filename: `Folia-iOS-3.0.6-build379-public-sanitized-v2.zip`
- SHA-256: `f8e08042914a01f63f8aabbadd9f61cca32dd92fd45cfe194495f1e40acbab32`

Upload this ZIP as an asset attached to a GitHub Release in `maguc98/folia-major`. A draft release is sufficient; the asset must be downloadable via a stable HTTPS URL. Do not upload the original IPA, any .p12/.pfx, provisioning profile, private key, token, or authentication-state directory.

After uploading, copy the asset's direct download URL (it should start with `https://github.com/maguc98/folia-major/releases/download/...`).

## Dispatch the full unsigned build

1. Open https://github.com/maguc98/folia-major/actions/workflows/ios-build379-unsigned-ipa.yml
2. Select **Run workflow**.
3. Select branch `ios-build379-baseline`.
4. Paste the release asset URL into `payload_url`.
5. Keep `expected_sha256` equal to the hash above.
6. Run the workflow.

The workflow independently verifies the SHA-256 and ZIP contents, builds Release for generic iOS device with code signing disabled, checks bundle ID/version/build, packages `Payload/Folia.app` into an unsigned IPA, and uploads the IPA plus a SHA-256 sidecar as a 14-day Actions artifact.

## Signing and install

The artifact is intentionally unsigned. Re-sign it locally with the user's own certificate and provisioning profile. The private key and provisioning profile should remain on the user's machine; they are not needed by this build workflow. An unsigned IPA cannot be installed directly on an iPhone.

## Scope warning

A successful archive build proves packaging/linking, not runtime equivalence with the original IPA. The rebuilt host uses WKWebView and NodeMobile; full Capacitor/Cordova plugin parity and physical-device validation are still outstanding. Before treating it as a daily-use replacement, verify startup, local Node services, QQ/Kugou login, Apple Music, background playback, media controls, and WebView recovery on a real device.
