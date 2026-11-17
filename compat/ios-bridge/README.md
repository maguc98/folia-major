# Build-379 bridge compatibility layer

This directory contains a small, dependency-free CommonJS adapter for projects that need to speak the observed Folia iOS build-379 WebKit bridge contract.

- `bridge-contract.js`: validates known player and provider message envelopes.
- `bridge-client.js`: injectable player/provider transports with session/generation stamping, request IDs, timeout cleanup and correlated replies.
- `native-event-adapter.js`: maps `loaded`, `error`, `state`, and `ended` callbacks into the deterministic player-state coordinator.
- `audio-event-adapter.js`: validates the six-band audio-analysis event.
- `player-state.js`: deterministic compatibility model for desired play intent, actual transport state, queue progression, lifecycle, and session/generation freshness.
- `ios/FoliaBridgeRouter.swift`: a WKWebView host-side router scaffold with weak message-handler proxies, main-frame/origin-policy hook, payload-size limits and native envelope validation.
- `ios/FoliaAVPlayerEngine.swift`: AVPlayer transport, queue progression, audio-tap attachment, event publication, and bounded playback snapshot export/restore.
- `ios/NativeAudioTapAnalyzer.swift`: AVAudioMix / MTAudioProcessingTap analysis and six-band event generation.
- `ios/FoliaPlaybackKeeper.swift`: Now Playing, remote commands, audio-session lifecycle and route/interruption handling.
- `ios/FoliaPlaybackSnapshotStore.swift` + `ios/FoliaWebContentRecoveryCoordinator.swift`: protected snapshot persistence and WebContent recovery hooks.
- `ios/FoliaAppleMusicPlaybackBridge.swift` + `apple-music-playback.js`: a separate explicit MusicKit playback adapter; its host envelope is new because the original outer dispatch envelope was not recovered.
- `FoliaAVPlayerEngine.onProviderRequest`: host injection point for Apple Music / Feiniu provider services. No provider account or NodeMobile server is fabricated by default.
- `../../tests/bridge-compat.test.js`: Node built-in tests (9 bridge tests plus 18 state/event-adapter tests).

Run:

```bash
node --test tests/*.test.js
```

## Integration boundary

These files are host-side compatibility scaffolds, not recovered upstream source. The host still has to build and retain the WKWebView router, AVPlayer engine, playback keeper, snapshot store and recovery coordinator. It must supply the trusted-frame policy, a sandbox-aware media URL policy, background-audio target settings, and `onProviderRequest` handlers. `FoliaAppleMusicPlaybackBridge` exposes a new explicit host envelope; it is not the unknown original Swift-to-JavaScript MusicKit envelope. NodeMobile startup, Feiniu service implementation, credentials, provider sessions and server-side account flows are not supplied here.

The adapter rejects unsupported Apple Music operation names, unsafe Feiniu API paths (including traversal, query/fragment, backslash and control characters), malformed reply envelopes, invalid request IDs/timeouts, and stale/duplicate replies. The native event adapter keeps native transport state separate from desired user intent and deliberately does not convert `auto-advanced` into another queue-advance command. The provider path check is defense in depth, not a security boundary. Native code must independently enforce action/path allowlists, origin/frame policy, payload size limits and credential-safe logging. The exact original native implementation is not available as editable Swift source in the supplied IPA. Neither Swift file has been compiled against an Xcode/iOS SDK or run on a device; both must be reviewed and integrated into a real host project. The host must strongly retain both the engine and router.

Do not use this adapter as a drop-in replacement for the original Folia player bundle without testing its call sites and event ordering on a device.


### iOS system media controls

See `ios/FoliaPlaybackKeeper.swift` and `../../docs/ios-build379/playback-keeper-host-scaffold.md` for the separate Now Playing and remote-command integration scaffold.
