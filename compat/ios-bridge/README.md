# Build-379 bridge compatibility layer

This directory contains a small, dependency-free CommonJS adapter for projects that need to speak the observed Folia iOS build-379 WebKit bridge contract.

- `bridge-contract.js`: validates known player and provider message envelopes.
- `bridge-client.js`: injectable player/provider transports with session/generation stamping, request IDs, timeout cleanup and correlated replies.
- `native-event-adapter.js`: maps the build-379 native `loaded`, `error`, `state`, and `ended` callbacks into the proposed deterministic player-state coordinator while leaving timeline/audio/auto-advanced events to their dedicated consumers.
- `player-state.js`: deterministic compatibility model for desired play intent, actual transport state, queue progression, lifecycle, and session/generation freshness.
- `ios/FoliaBridgeRouter.swift`: a WKWebView host-side router scaffold with weak message-handler proxies, main-frame/origin-policy hook, payload-size limits and native envelope validation.
- `ios/FoliaAVPlayerEngine.swift`: a newly authored AVFoundation-backed transport engine with AVPlayerItem observer lifecycle, basic commands, event publication and queue progression. It is a host scaffold, not recovered upstream code; MusicKit/Feiniu/NodeMobile and background/Now Playing integration are not included.
- `../../tests/bridge-compat.test.js`: Node built-in tests (9 bridge tests plus 18 state/event-adapter tests).

Run:

```bash
node --test tests/*.test.js
```

## Integration boundary

The JavaScript adapter does not create a WKWebView, AVPlayer, MusicKit session, Apple Music login, Feiniu login, or NodeMobile server. The Swift router is only a WKWebView routing scaffold. The separate AVPlayer engine implements basic playback transport, but does not implement MusicKit, provider login, NodeMobile, AVAudioSession policy, background-audio configuration, Now Playing/remote commands, audio-tap analysis or persisted playback recovery. The host application must register the native WebKit message handlers and implement the native actions. The adapter is a web-side protocol helper only.

The adapter rejects unsupported Apple Music operation names, unsafe Feiniu API paths (including traversal, query/fragment, backslash and control characters), malformed reply envelopes, invalid request IDs/timeouts, and stale/duplicate replies. The native event adapter keeps native transport state separate from desired user intent and deliberately does not convert `auto-advanced` into another queue-advance command. The provider path check is defense in depth, not a security boundary. Native code must independently enforce action/path allowlists, origin/frame policy, payload size limits and credential-safe logging. The exact original native implementation is not available as editable Swift source in the supplied IPA. Neither Swift file has been compiled against an Xcode/iOS SDK or run on a device; both must be reviewed and integrated into a real host project. The host must strongly retain both the engine and router.

Do not use this adapter as a drop-in replacement for the original Folia player bundle without testing its call sites and event ordering on a device.
