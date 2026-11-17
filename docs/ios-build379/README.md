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
bash scripts/replace-ios-web-payload.sh /path/to/Payload/App.app /path/to/Folia-iOS-3.0.6-build379-public-sanitized-v2.zip
```

**Important:** replacing `public/` invalidates the original iOS code signature. The resulting app must be re-signed with an authorized signing identity before installation. This helper does not rebuild the native executable, restore missing Swift source, or produce an IPA.


## Native bridge protocol baseline

The WebKit bridge contract is documented in `docs/ios-build379/native-bridge-contract.md`. Machine-readable message definitions and synthetic compatibility fixtures are stored in:

- `schemas/native-bridge-build379.schema.json`
- `tests/fixtures/native-bridge-build379.json`
- `tests/test_native_bridge_build379.py`

Run the structural fixture tests:

```bash
python3 -m unittest discover -s tests -p 'test_native_bridge_build379.py' -v
```

The fixtures are synthetic contract examples, not captured production traffic. The suite currently contains seven positive/negative structural cases and is also run by the manual analysis workflow. Passing them validates message shape only; it does not emulate WebKit, AVPlayer, provider login, or the original Swift bridge.


## Web-side bridge compatibility adapter

A standalone adapter is available under `compat/ios-bridge/`. It includes player/provider message validators, injectable request transports, session/generation stamping, provider request correlation and timeout/teardown cleanup. It is deliberately separate from the immutable build-379 web payload.

Run its Node.js tests:

```bash
node --test tests/bridge-compat.test.js
```

The current suite has 9 tests and passed locally under Node.js 22. The manual GitHub Actions workflow now runs this suite as well as the Python fixture tests. A Swift WKWebView router scaffold is also provided at `compat/ios-bridge/ios/FoliaBridgeRouter.swift`; it registers the two handler names and forwards validated messages to a host delegate. It is new scaffolding, not recovered upstream code, and has not been compiled with Xcode or tested on iOS. The adapter/scaffold do not implement AVPlayer, MusicKit, Feiniu authentication or NodeMobile, and do not produce an IPA.


## Native player lifecycle reference

The native executable's Swift symbol map is documented in `docs/ios-build379/native-player-lifecycle-map.md`. It covers `FoliaNativePlayer`, the separate `FoliaPlaybackKeeper` and `FoliaBackGuard`, queue/auto-advance methods, WebContent reload recovery, Now Playing/remote controls and the native audio-tap analysis path. These are symbol-level findings, not recovered Swift method bodies.


## Native player state-machine reconstruction

The deeper static reconstruction is in `docs/ios-build379/native-player-state-machine.md`. It separates direct binary evidence from structural inference and records the observed session/generation guards, item observers, queue/late-queue paths, background/interruption recovery, WebView reload recovery, system media controls, audio-tap analysis, and embedded self-test markers. The embedded self-test strings are not evidence that a test ran or passed.

The Swift router scaffold has also been hardened: JSON booleans are distinguished from numeric `NSNumber` values, generation is constrained to a non-negative safe integer, seek/volume values must be finite, optional load queues are bounded, and media URL acceptance is delegated to an explicit host policy. Its default policy allows only HTTP(S) URLs with a host; local `file:` media is denied unless the integrating app supplies a sandbox-aware allowlist. This is a new security policy for the scaffold, not a claim about the original binary's URL policy.

The router remains uncompiled against the iOS SDK and has not been runtime-tested on a device.


## Native player runtime test plan

The executable also exposes stored-property names for the native player's current URL/session/generation, track identity, playback intent, queue, item observers, pending seek, interruption recovery and auto-advance bookkeeping. A repeatable device test matrix based on the embedded self-test markers is documented in `docs/ios-build379/native-player-runtime-test-plan.md`. It separates test intentions visible in the binary from tests actually executed: no original-app self-test run or replacement-device test is claimed.


## Deterministic player-state compatibility model

A proposed state coordinator is now available at `compat/ios-bridge/player-state.js`. It keeps transport state, desired play intent, queue state, lifecycle state, and session/generation freshness as separate fields. It models immediate queue advancement and late-queue arrival after an ended item, and intentionally does not implement AVPlayer or automatic interruption resume.

Eighteen deterministic tests are in `tests/player-state.test.js`. The `compat/ios-bridge/native-event-adapter.js` module maps the observed native `loaded`, `error`, `state`, and `ended` callbacks into the state model. Crucially, a native `state` callback changes actual transport state without overwriting the user's desired play intent; `time`, `audio`, and `auto-advanced` remain with their timeline/visualizer consumers rather than being treated as duplicate queue commands. The model also guards duplicate/late end notifications and prevents a late queue from auto-starting after an explicit pause; a later user `play` command can resume queue progression. The model uses an `endedForURL` guard, corresponding to a stored-property name visible in the original binary. The workflow runs all Node test files with `node --test tests/*.test.js`. Local verification on Node.js 22.16.0 completed **27/27 tests** (9 bridge-adapter tests and 18 state/event-adapter tests). These are unit tests for the new compatibility modules; they do not exercise the original IPA or iOS frameworks.


## AVPlayer host engine scaffold

A newly authored AVFoundation host implementation is now available at `compat/ios-bridge/ios/FoliaAVPlayerEngine.swift`. It owns an `AVPlayer`, observes the active `AVPlayerItem`, tears down item observers on replacement, handles the bridge transport commands, emits native state/time/end/error events, and supports immediate or late queue progression while respecting explicit pause intent.

Integration notes and the required host-retention wiring are documented in `docs/ios-build379/avplayer-host-scaffold.md`. The router and engine are weakly cross-referenced, so the host must strongly retain both. Provider requests deliberately return `provider-service-not-installed`; this engine does not implement MusicKit, Feiniu, NodeMobile, background audio configuration, Now Playing/remote commands, audio-tap analysis, or persisted WebView-reload recovery.

**Verification boundary:** this Swift implementation has not been compiled with Xcode/iOS SDK or run on a device. It is an AVPlayer-backed scaffold, not a verified IPA replacement. The original Xcode project and Swift sources remain unavailable from the supplied IPA.

The manual workflow now includes a macOS `swiftc -frontend -parse` job for both Swift scaffold files. This is syntax parsing only; it does not type-check or link against iOS frameworks. The workflow itself has not yet been dispatched.



## Apple Music native playback path

A separate static-analysis note documents the embedded MusicKit playback dispatcher, queue identity checks, asynchronous start cancellation, `prepareNext` tail reconciliation, storefront alignment, and status fields: `docs/ios-build379/apple-music-native-playback-bridge.md`. This path is distinct from web-side `appleMusicRequest` catalog operations and the AVPlayer-oriented `foliaPlayer` handler. The outer native dispatch envelope remains unverified.


## Playback keeper and lifecycle integration

The new `compat/ios-bridge/ios/FoliaPlaybackKeeper.swift` adds Now Playing metadata, remote transport commands, audio-session activation, interruption handling, route-change handling, and app background/foreground callbacks. `FoliaAVPlayerEngine.swift` implements the transport callbacks while keeping system interruption state separate from user playback intent. The current policy resumes only when the iOS interruption options request it and audio-session reactivation succeeds; disconnecting a headphone route pauses and clears playback intent to avoid unexpectedly switching audio to the speaker.

Host wiring and limits are documented in `docs/ios-build379/playback-keeper-host-scaffold.md`. Additional device scenarios NP-16 through NP-19 are in `docs/ios-build379/native-player-runtime-test-plan.md`. These changes remain uncompiled against the iOS SDK and untested on a physical device; background audio still requires the correct Xcode target capability and app configuration.


## Complete compatibility scaffold inventory

The current branch now includes the following newly authored host-side building blocks:

- `compat/ios-bridge/ios/FoliaAVPlayerEngine.swift`: AVPlayer transport, queue, native event, intent, audio-tap attachment, and playback snapshot export/restore.
- `compat/ios-bridge/ios/NativeAudioTapAnalyzer.swift`: MTAudioProcessingTap / AVAudioMix based band-energy analyzer, with six output fields. Its filter implementation and normalization are approximations; the exact build-379 DSP is not recovered.
- `compat/ios-bridge/ios/FoliaPlaybackKeeper.swift`: Now Playing, remote commands, iOS 27 audio-session lifecycle notifications, legacy interruption fallback, route changes, and media-services reset notifications.
- `compat/ios-bridge/ios/FoliaPlaybackSnapshotStore.swift` and `FoliaWebContentRecoveryCoordinator.swift`: protected bounded snapshots and a WKWebView WebContent termination recovery hook.
- `compat/ios-bridge/apple-music-playback.js` and `ios/FoliaAppleMusicPlaybackBridge.swift`: a separate MusicKit JavaScript playback dispatcher and new explicit host bridge. The original binary's outer dispatcher envelope is not fully recovered.
- `FoliaAVPlayerEngine.onProviderRequest`: an injected host callback for validated Apple Music / Feiniu provider requests. Provider services and NodeMobile still need real host wiring.
- `audio-event-adapter.js`, `tests/audio-event-adapter.test.js`, `tests/apple-music-playback.test.js`, and `schemas/native-audio-event.schema.json`: JS validation/tests and an audio event schema.
- Lifecycle and analysis notes: `native-audio-tap-scaffold.md`, `web-content-recovery-scaffold.md`, `playback-keeper-host-scaffold.md`, and `native-player-runtime-test-plan.md`.

## Remaining hard blockers before an installable IPA

1. The supplied IPA does not contain the original editable Xcode project or the original Swift sources. A new native host target still needs to be created or recovered.
2. NodeMobile framework linkage, copied Node project resources, startup/shutdown method implementation, and environment injection need the original or a new host target. The compiled binary exposes a `NodeRunner.start(projectDirectoryName:)` symbol, but its implementation is unavailable.
3. Feiniu authentication and API services require the actual Node service, local port configuration, pairing/session policy and safe credential storage. The current bridge offers an injection point but does not claim those services exist.
4. Apple Music playback has a separate JS adapter; the original outer Swift/JS dispatch and account behavior still need controlled runtime comparison.
5. Background audio mode, app delegate wiring, code signing, provisioning, and a reproducible Xcode build remain host-project tasks.

The GitHub Actions workflow runs on pushes and pull requests to `ios-build379-baseline`: a macOS Swift syntax parse and Ubuntu JavaScript/Python fixture tests. A syntax parse is not an iOS SDK type-check or app build. The manual archive-analysis job still requires a direct HTTPS URL for the sanitized v2 ZIP.

**Current output is a substantial compatibility source scaffold, not a built or installable IPA.** No Xcode/iOS SDK build, physical-device validation, signing, or IPA export has been completed.


## NodeMobile runtime host contract

The sanitized build-379 Node project was inspected directly. Its entry point assumes Node 18 and starts Kugou on 3211, QQ Music on 3212 and the general/Qishui proxy on 3213, all bound to 127.0.0.1 by default (ports can be shifted via environment variables). The entry point also configures QQ device/session persistence, Qishui paired-token session storage, a Node-18 WebCrypto and AbortSignal polyfill, a 2 MiB log cap, and an HTTPS-only Qishui fetch shim. See `docs/ios-build379/node-runtime-host-contract.md` for the complete environment, local HTTP routes, host setup sequence and proxy security hardening.

The IPA contains the NodeMobile framework binary and a compiled `NodeRunner.start(projectDirectoryName:)` symbol, but not the original native launcher source or framework headers. The full `public/nodejs-project/` tree (including 8,153 files under `node_modules/`) has not been imported into this repository. Node services are therefore **mapped but not launched by the compatibility host**.

## Integrated host and Apple Music playback helper

`compat/ios-bridge/ios/FoliaNativePlaybackHost.swift` owns and wires the AVPlayer engine, WebKit router, playback keeper, protected snapshot store, WebContent recovery coordinator, and optional provider callback. It also exposes methods for installing and sending commands to the separate MusicKit playback dispatcher. The dispatcher source must be supplied by the host from `compat/ios-bridge/apple-music-playback.js`. The original provider auth envelope, MusicKit authorization screen lifecycle and Feiniu account/backend service still require controlled host-side implementation and runtime comparison.


## Apple Music catalog/account bridge

The new `compat/ios-bridge/apple-music-provider.js` implements the extracted Apple Music provider operation set (catalog search/details, playlists/library, lyrics and the two explicit write operations). It is called by `FoliaAppleMusicProviderBridge.swift` through the provider envelope validated by `FoliaBridgeRouter`. `FoliaNativePlaybackHost.installAppleMusicServices(...)` installs the separate playback and provider scripts. The provider returns a stable SHA-256 pseudonymous account key, not a Music User Token. The `appleMusicClose` action remains unsupported because the original UI-close behavior was not recoverable.

Validation tests are in `tests/apple-music-provider.test.js` and `tests/apple-music-playback.test.js`. They use mocked MusicKit responses; they do not verify real account authorization, subscriptions, storefront writes or Apple service entitlements.


## Verification scope after the latest compatibility work

The Node suite now includes the bridge adapter, deterministic player state, native audio event validation, Apple Music playback dispatch and Apple Music catalog/account provider tests. It does not invoke AVFoundation, MediaToolbox, WebKit or NodeMobile. The Swift workflow step uses `swiftc -frontend -parse`, which checks syntax but does not type-check against the iOS SDK or build an app. Only a real host Xcode target and physical-device tests can close those gaps.
