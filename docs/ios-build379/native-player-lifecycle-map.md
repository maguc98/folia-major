# Folia iOS build 379 — Native playback lifecycle map

> Evidence basis: Swift symbol names and printable strings extracted from the supplied `Payload/App.app/App` arm64 Mach-O, correlated with the web-side player bridge. This is a symbol-level map. It does not recover method bodies or prove the exact order of every runtime transition.

## 1. Native player class and method inventory

The executable contains the Swift class `FoliaNativePlayer` and the following method symbols:

| Symbol / method | What the symbol establishes |
|---|---|
| `install(on: WKWebView)` | The player installs itself against a WebKit view. |
| `userContentController(_:didReceive:)` | The class receives WebKit script messages. |
| `handleCommand(_ body: [String: Any])` | A dictionary-based command dispatcher exists. |
| `adoptCommandSession(_:generation:)` | The native player tracks a web session and generation. |
| `load(url:position:autoplay:track:queue:previous:)` | Load accepts a URL, starting position, autoplay flag, track metadata, queue and previous items. |
| `play()` | Native play operation. |
| `pause(clearIntent:)` | Pause distinguishes whether playback intent should be cleared. |
| `seek(_:)` | Native seek operation. |
| `applyVolume()` | Volume application is a separate operation. |
| `syncUpcoming(_:requestedCurrentTrackKey:previous:)` | Upcoming queue and previous history are synchronized against a requested current track key. |
| `playQueueItem(_:queue:reason:)` | Queue item playback has a reason parameter. |
| `advanceToNextUpcoming(reason:)` | A dedicated next-item advance path exists. |
| `resumeEndedPlaybackWhenNextIsReady()` | There is a path to resume after an item ends while the next item is still preparing. |
| `scheduleAutoAdvance(expectedURL:delay:)` | Auto-advance is delayed and guarded by an expected URL. |
| `handleItemEnded`, `handleItemStalled`, `handleItemFailed` | Separate AVPlayer item lifecycle handlers exist. |
| `attachObservers(for:)`, `detachObservers()` | AVPlayerItem observers are explicitly managed. |
| `handleInterruption(_:) ` | Audio interruption handling is part of the player. |
| `scheduleResumeAfterInterruption()` | Resume after interruption is a separate scheduled path. |
| `currentTrackPayload()`, `emit(_:) ` | The native player builds track/event dictionaries and emits events to the web view. |
| `publishCurrentPlaybackState(reason:)` | Native state publication includes a reason string. |
| `recordCurrentInHistory()` | Current-track history recording exists. |
| `prepareForWebContentReload()` | The player has an explicit WebContent reload preparation path. |
| `restorePersistedPlaybackIfNeeded()`, `schedulePersistedPlaybackRecovery()` | Persisted playback recovery paths exist. |

The method signature for `load` is especially important: native load receives `queue` and `previous` separately, while the web layer sends `upcoming` and `previous` in its command payload. A replacement wrapper must map the web-side `upcoming` field to the native queue argument rather than rename or discard it.

## 2. Separate playback keeper

The binary also contains a separate `FoliaPlaybackKeeper` class. Its symbols include:

- `install(on: WKWebView)`
- `setupNowPlayingCommands()`
- `updateNowPlayingInfo(_ payload:)`
- `beginKeepAliveIfPlaying(reason:)`
- `endKeepAlive(reason:)`
- `remoteTransport(isPlaying:)`
- `snapshotSaysPlaying`
- `handleRouteChange(_:)`
- `userContentController(_:didReceive:)`

This is distinct from `FoliaNativePlayer`. It is responsible for a second layer of background/remote-control behavior and should not be collapsed into the basic play/pause/seek command dispatcher when designing a replacement host.

The binary also includes a `FoliaBackGuard` class with `install(on:)`, `coverTerminationReload(for:)`, `webViewWebContentProcessDidTerminate`, navigation-decision and gesture-control methods. The player and guard both contain WebContent-reload-related behavior, indicating that WebView process termination is an explicit lifecycle concern in this app.

## 3. Audio analysis path

The native executable includes:

- `NativeAudioTapAnalyzer`
- `MTAudioProcessingTap` / `MTAudioProcessingTapRef`
- `foliaAudioTapInit`
- `foliaAudioTapPrepare`
- `foliaAudioTapProcess`
- `foliaAudioTapUnprepare`
- `foliaAudioTapFinalize`
- `attachAudioAnalysis(to:)`
- `startAudioAnalysisUpdates()`
- `publishAudioAnalysis()`

This establishes a native audio-tap analysis path separate from the web visualizer's Pixi rendering. The web callback receives an `audio` event with the band fields `power`, `bass`, `lowMid`, `mid`, `vocal` and `treble`. The symbol list alone does not reveal the exact DSP algorithm, sampling window, smoothing or calibration.

## 4. Implications for a replacement wrapper

A wrapper that only forwards `play`, `pause` and `seek` would be incomplete. The symbol map identifies at least these additional responsibilities:

1. Session/generation adoption and stale-command rejection.
2. Current track metadata and queue/previous synchronization.
3. AVPlayerItem observation, stalled/failed/ended handling.
4. Guarded delayed auto-advance and next-item readiness.
5. Persisted playback restoration and WebContent reload recovery.
6. Audio interruption and route-change behavior.
7. Now Playing metadata, remote transport commands and background keep-alive.
8. Native audio analysis events for visualizer reactivity.
9. WebContent process termination handling.

## 5. Validation plan before claiming compatibility

| Test area | Required checks |
|---|---|
| Session lifecycle | New web session, generation increment, stale command rejection, WebView reload. |
| Load and queue | Initial position/autoplay, current item key, upcoming/previous mapping, queue replacement. |
| AVPlayer item | Ready, failed, stalled, ended, unplayable item, delayed next item. |
| Auto-advance | Expected-URL guard, queue update racing with item-ended notification, no duplicate advance. |
| Playback intent | User pause vs release intent; foreground/background transitions. |
| Audio session | Interruption began/ended, route change, media-services reset. |
| Background/remote | Now Playing metadata, remote play/pause/next/previous/seek, keep-alive lifecycle. |
| Audio analysis | Tap install/remove, event frequency, band range and cleanup on item replacement. |
| WebContent termination | Player state persistence, reload overlay, restoration without duplicate playback. |

## 6. Evidence limits

- Swift symbols prove that methods/classes were compiled into the executable, not their full semantics.
- No complete editable Swift source or Xcode project was present in the supplied IPA.
- The compatibility adapter and router scaffold are not implementations of these native behaviors.
- To reproduce the original behavior faithfully, obtain the original native project or capture controlled runtime traces on a test device, then implement and test each lifecycle area independently.
