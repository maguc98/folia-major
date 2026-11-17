# Playback keeper host scaffold

> Newly authored compatibility code based on the build-379 symbol map. This is not recovered upstream source and does not establish behavioral parity.

## Components

- `FoliaPlaybackTransport` is the narrow control/snapshot interface implemented by the AVPlayer engine.
- `FoliaPlaybackKeeper` publishes lock-screen/Control Center Now Playing metadata and registers remote transport commands.
- `FoliaAVPlayerEngine` maps those commands to its existing intent-aware transport and queue.

## Host wiring

Create and strongly retain the engine, router, and keeper for the WebView/player lifetime:

1. Construct `FoliaAVPlayerEngine`.
2. Construct `FoliaBridgeRouter(delegate: engine, ...)` and call `engine.attach(to: router)`.
3. Construct `FoliaPlaybackKeeper(transport: engine)` and call `keeper.install()` on the main queue.
4. Install the router on the WebView.
5. Set `engine.onPlaybackStateChanged = { [weak keeper] in keeper?.refreshNowPlayingInfo() }` after creating the keeper. This callback runs on the main queue whenever the engine emits state/time/track events, avoiding a separate timer. Clear the callback when tearing down the host.
6. Call `activatePlaybackAudioSession()` when playback ownership begins. Call `deactivatePlaybackAudioSession()` only when playback is genuinely stopped and the host relinquishes the audio session.

## Implemented

- Lock-screen/Control Center title, artist, album, duration, elapsed time, and playback rate.
- Play, pause, toggle, seek, next, and previous remote command handlers.
- Previous-track behavior seeks to the start when current position is over three seconds; otherwise it loads the most recent previous queue entry.
- The AVPlayer engine preserves explicit user intent for remote play/pause and uses its existing queue/event path for next/previous.
- Audio-session interruption and route-change notifications trigger metadata refresh; they do not silently rewrite the user's desired-playing intent.
- Audio session activation uses `.playback`; there is no silent audio loop or fabricated keep-alive.

## Host target requirements and limits

- Enable the app target's Background Modes > Audio, AirPlay, and Picture in Picture as required by the product's actual use case. The entitlement/capability and `Info.plist` configuration are Xcode target settings and cannot be supplied by these standalone Swift files.
- The host must refresh Now Playing metadata as the current item and timeline change. This scaffold deliberately does not create a second periodic timer.
- The remote next/previous controls are currently enabled at the command-center level; the transport safely no-ops when no queue entry exists. A future queue-capability callback can make this more precise.
- No artwork loading, lyrics, MusicKit-specific Now Playing behavior, audio tap, persisted playback recovery, or full interruption-resume policy is implemented.
- This is not a substitute for testing with a real iPhone, lock screen, wired/Bluetooth headphones, AirPlay route changes, calls, Siri, and background playback.

## Verification status

The repository workflow's macOS job performs Swift syntax parsing only. It does not type-check against the iOS SDK, link, build an IPA, or validate runtime command behavior. Run an Xcode host-target build and device test matrix before shipping.
