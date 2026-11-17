# AVPlayer host scaffold — integration and verification notes

> This file documents newly authored compatibility code. It is not recovered upstream Folia source and does not establish full build-379 parity.

## Components

- `FoliaBridgeRouter.swift`: validates trusted main-frame WebKit messages and forwards player/provider requests.
- `FoliaAVPlayerEngine.swift`: owns an `AVPlayer`, the active `AVPlayerItem`, KVO/notification observers, queue state, and event publication through the router.
- The host must strongly retain both objects. The engine's router reference is weak to avoid a retain cycle.

## Required host wiring

1. Construct the engine with a media URL policy.
2. Construct `FoliaBridgeRouter(delegate: engine, isTrustedFrame: ...)`.
3. Call `engine.attach(to: router)`.
4. Call `router.install(on: webView)` before navigating to the Folia page.
5. On teardown, call `router.uninstall()`, release the WebView and then release the host-owned engine/router.

The URL policy supplied to the router and engine must agree. The default policy permits HTTP(S) URLs with a host and no embedded credentials. A host may opt into local files only after resolving symlinks and proving the URL remains inside an app-controlled sandbox directory. Do not simply allow every `file:` URL.

## Implemented in this scaffold

- Player commands: `load`, `play`, `pause`, `seek`, `volume`, `muted`, `status`, `upcoming`.
- Session/generation freshness checks.
- Current item KVO status observation and cleanup on item replacement.
- Ended, failed-to-end, stalled and periodic time notifications.
- Initial seek after item readiness.
- Current/upcoming/previous queue storage and basic immediate/late queue progression.
- Native event envelopes with session and generation.
- Build-379 web event fields for `state` (`playing`, `position`, `sentAtMs`), `time` (`playing`, `position`, `duration`, `sentAtMs`), `ended` (`url`, `autoAdvancePrepared`) and `auto-advanced` (`trackKey`, `url`, `position`).

The `auto-advanced` event is emitted after the next AVPlayer item is installed, not after it becomes ready. The web bundle uses it to cancel its delayed HTMLMediaElement ended fallback and update current track identity. Device testing must verify that this timing is sufficient for slow and unplayable sources.

## Known gaps — do not claim full compatibility

- No MusicKit native playback dispatcher or Apple Music login/session.
- No Feiniu authentication or provider API implementation; provider requests return `provider-service-not-installed`.
- No NodeMobile process or localhost services.
- No AVAudioSession interruption/route-change handling.
- No background audio mode/entitlement setup, Now Playing metadata, MPRemoteCommandCenter, or keep-alive keeper.
- No audio-tap DSP / `audio` events for the visualizer.
- No persisted playback snapshot or WebContent process termination/reload recovery.
- No delayed expected-URL auto-advance scheduler, preloaded next item, retry policy, or original failure semantics.
- The queue model assumes playable entries contain direct media URLs. The original web queue can contain entries with a null URL; provider resolution is not recreated here.
- The default URL policy intentionally excludes local files unless the host supplies a sandbox-aware allowlist.

## Verification status

The JavaScript contract/state tests run locally under Node.js 22.16.0. A manual GitHub Actions job now runs `swiftc -frontend -parse` on macOS for syntax parsing of the two Swift files. That check does not type-check against the iOS SDK, link AVFoundation/WebKit, compile an app, or run on a device.

Before using this scaffold, add an Xcode host target and compile against the intended iOS deployment target. Then run the device matrix in `native-player-runtime-test-plan.md`, including backgrounding, interruptions, same-URL reload, queue race conditions, duplicate ended notifications, and WebContent termination.
