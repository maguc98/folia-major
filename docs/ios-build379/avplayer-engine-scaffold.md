# AVPlayer host engine scaffold

`compat/ios-bridge/ios/FoliaAVPlayerEngine.swift` is the first AVFoundation-backed implementation layer for the observed `foliaPlayer` bridge. Unlike `player-state.js`, it owns a real `AVPlayer` and `AVPlayerItem` objects. It is newly authored replacement code, not recovered Folia Swift source.

## Host wiring

The router and engine have a weak reference relationship. The host must retain both:

```swift
let engine = FoliaAVPlayerEngine()
let router = FoliaBridgeRouter(
    delegate: engine,
    isTrustedFrame: { frame in
        // Replace with the app's exact trusted-origin policy.
        frame.securityOrigin.host == "your-trusted-host.example"
    }
)
engine.attach(to: router)
router.install(on: webView)

// Keep strong properties/references to both engine and router.
```

Do not copy the example hostname literally. The host must use the actual production origin and should reject unexpected schemes, ports, subdomains, and opaque origins according to its deployment policy.

## Implemented in this scaffold

- `load`, `play`, `pause`, `seek`, `volume`, `muted`, `status`, and `upcoming` command handling.
- Session/generation freshness checks before stateful commands.
- AVPlayer item replacement and per-item KVO / end / failed-to-end / stalled observers.
- Observer teardown before replacing an item.
- Periodic time events and `loaded`, `error`, `state`, and `ended` notifications.
- Immediate queue progression when an item ends with a playable next item.
- Late queue progression after end-of-item, provided playback intent is still active.
- Explicit user pause is retained; if a next item arrives while paused, it waits for a later user `play`.
- URL allowlist limited to HTTP(S) in this scaffold.

## Deliberate limits / integration requirements

- Provider requests return `provider-service-not-installed`; Apple Music and Feiniu are not implemented here.
- The scaffold does not implement MusicKit, NodeMobile, credentials, app lifecycle restoration, `AVAudioSession` policy, background modes, Now Playing metadata, remote commands, audio-tap analysis, or persistent playback snapshots.
- The host must configure signing capabilities and background audio mode where appropriate; code alone cannot grant those entitlements.
- The host must own the engine and router strongly, install/uninstall handlers with the WebView lifecycle, and call router teardown when the WebView is discarded.
- The sample trusted-frame check is illustrative only. Production origin policy is security-critical.
- Only HTTP(S) media URLs are accepted. Signed URLs and provider-specific URL refresh must be handled by the host before sending `load`.
- `reason` labels are currently diagnostic placeholders; no logging of full media URLs or provider credentials should be added.
- This file has not been compiled against an Xcode/iOS SDK or run on a device. API availability, Swift concurrency warnings, background behavior, and actual event ordering remain to be verified.

## Required next device checks

Run the NP-01 through NP-15 matrix in `native-player-runtime-test-plan.md`, with priority on item replacement/observer teardown, duplicate end callbacks, paused late-queue behavior, interruptions, background audio, lock-screen controls, and WebView process termination. Capture native event payloads and compare them with the original app before treating this scaffold as behaviorally compatible.