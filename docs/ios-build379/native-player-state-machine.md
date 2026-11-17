# Native player state-machine reconstruction (build 379)

This document is a static-analysis reconstruction of the shipped iOS binary. It is not recovered Swift source and does not claim that the implementation below is byte-for-byte or behaviorally identical to the original.

## Evidence standard

- **Direct binary evidence** means a symbol, selector, notification name, persisted key, or log string was found in the build-379 app executable.
- **Structural inference** means the likely ordering or responsibility inferred from those names. It must be confirmed against runtime traces or source before being treated as an exact implementation contract.
- The executable was extracted from `iPad-Folia-3.0.6-build379-正式版.ipa`; the app binary contains Swift symbols for the components below.

## Components and responsibilities

| Component | Directly observed symbols / strings | Supported interpretation |
|---|---|---|
| `FoliaNativePlayer` | `install`, `handleCommand`, `load`, `play`, `pause`, `seek`, `applyVolume`, `syncUpcoming` | Owns the native player command and queue path |
| `FoliaPlaybackKeeper` | `setupNowPlayingCommands`, `updateNowPlayingInfo`, `beginKeepAliveIfPlaying`, `endKeepAlive`, route/interruption handlers | Coordinates system playback controls and background keep-alive |
| `FoliaBackGuard` | Web-content termination and navigation/gesture-related symbols | Protects or recovers the WebView lifecycle; exact policy is not reconstructed here |
| `NativeAudioTapAnalyzer` | `MTAudioProcessingTap` callbacks and audio-analysis symbols | Reads audio buffers for visualizer analysis |

## Reconstructed lifecycle

1. **Bridge installation**
   - Direct evidence: `FoliaNativePlayer.install(on:)` and WebKit script-message callback symbols exist.
   - Inference: the WebView registers a native message handler and forwards player commands to `handleCommand`.

2. **Command-session adoption**
   - Direct evidence: `adoptCommandSession(_:generation:)`, log strings `status adopted generation=` and `native command session changed generation=`.
   - Direct evidence: `ignored stale load generation=` and `ignored stale upcoming generation=`.
   - Inference: the native player tracks a current session/generation pair and rejects at least some stale queue/load updates. Exact comparison rules and which commands trigger adoption require runtime verification.

3. **Load / item replacement**
   - Direct evidence: `load(url:position:autoplay:track:queue:previous:)`, `applyCurrentTrack`, `detachObservers`, `attachObservers(for:)`.
   - Inference: loading a new item replaces or updates the current AVPlayerItem, refreshes observers, and associates metadata and queue context with the selected track.
   - Binary self-test strings mention loading A then B, checking old-item release, and checking the old item stopped. These are test intentions, not proof that the tests passed on a user's device.

4. **Playback and state publication**
   - Direct evidence: `play()`, `pause(clearIntent:)`, `seek(_:)`, `applyVolume()`, `publishCurrentPlaybackState(reason:)`, `currentTrackPayload()`, and `emit(_:)`.
   - Direct evidence: persisted keys `folia.native.desired-playing.v1`, `folia.native.playback.snapshot.v1`, and `folia.native.playback.lastPlaying.v1`.
   - Inference: the app distinguishes playback intent from transient AVPlayer rate/state and persists enough state to attempt restoration. The precise snapshot schema is not recoverable from symbol names alone.

5. **Queue synchronization and end-of-item progression**
   - Direct evidence: `syncUpcoming(_:requestedCurrentTrackKey:previous:)`, `playQueueItem(_:queue:reason:)`, `advanceToNextUpcoming(reason:)`, and `resumeEndedPlaybackWhenNextIsReady()`.
   - Direct evidence: observers are associated with `AVPlayerItemDidPlayToEndTimeNotification`, `AVPlayerItemPlaybackStalledNotification`, and `AVPlayerItemFailedToPlayToEndTimeNotification`.
   - Direct evidence: log strings include `ended -> next queue is playable`, `ended without queued next -> waiting for page`, `upcoming queued ahead generation=`, and `upcoming ahead had no playable URL generation=`.
   - Inference: queue updates may arrive before or after an item ends; the player has explicit handling for a late-arriving next item and for waiting when no playable next URL is available. Do not assume the exact queue matching algorithm from these strings alone.

6. **Unplayable / stalled / failed items**
   - Direct evidence: `handleUnplayableCurrentItem(_:source:)`, `handleItemStalled`, `handleItemFailed`, and `scheduleAutoAdvance(expectedURL:delay:)`.
   - Inference: the player detects item failures and stalls and may schedule an automatic advance. The fallback behavior and retry timing must be established by runtime tests.

7. **App lifecycle and interruptions**
   - Direct evidence: `prepareForBackgroundPlayback(reason:)`, `resumePlaybackIfNeeded(reason:)`, `prepareForForegroundPlayback(reason:)`, `scheduleResumeAfterInterruption()`, and corresponding `FoliaPlaybackKeeper` methods.
   - Direct evidence: app delegate symbols include resign-active, enter-background, enter-foreground, and become-active callbacks.
   - Inference: foreground/background transitions and audio-session interruptions have separate recovery paths. A log string says playback intent is cleared before resume when an interruption ends; exact conditions remain unknown.

8. **Web-content reload / process termination**
   - Direct evidence: `prepareForWebContentReload`, `restorePersistedPlaybackIfNeeded`, and `schedulePersistedPlaybackRecovery`.
   - Direct evidence: a log string begins `reload same url pos=`.
   - Inference: the native player attempts to preserve or restore playback around WebView reloads. It is not established that every WebContent process termination is recoverable.

9. **System media controls and audio analysis**
   - Direct evidence: `FoliaPlaybackKeeper.setupNowPlayingCommands`, `updateNowPlayingInfo`, `remoteTransport`, and `handleRouteChange`.
   - Direct evidence: audio tap init/prepare/process/unprepare/finalize symbols and `publishAudioAnalysis`.
   - Inference: remote transport commands feed the native player, while an audio tap supplies analysis values to the web visualizer. Exact event fields and cadence need runtime capture.

## Important self-test markers

The executable contains marker strings for:
- `FOLIA_NATIVE_SELFTEST`
- `FOLIA_NATIVE_QUEUE_SELFTEST`
- `FOLIA_NATIVE_LATE_QUEUE_SELFTEST`
- `FOLIA_NATIVE_UNPLAYABLE_SELFTEST`
- `FOLIA_NATIVE_BACKGROUND_SELFTEST`
- `FOLIA_NATIVE_RESTART_PREP_SELFTEST`
- `FOLIA_NATIVE_REMOTE_SELFTEST`

It also contains messages describing test steps for session replacement, pause/resume, same-URL reload, foreground recovery, queue progression, and a NaN/Infinity payload probe. The presence of these strings proves only that test code/markers are embedded; it does **not** prove that a self-test ran or passed in the supplied IPA.

## State model for compatibility work

The following is a proposed model for the compatibility implementation, not a claim about the original internal enum:

```text
detached
  -> attached
  -> session-adopted
  -> item-loading
  -> ready / playing / paused
  -> ended
       -> next-item-ready -> item-loading
       -> waiting-for-queue
  -> stalled / failed
       -> recovery-or-advance
  -> background / interrupted
       -> foreground-or-interruption-recovery
  -> web-content-reload
       -> restore-from-snapshot
```

The model deliberately separates:
- **transport state** (loading, ready, playing, paused, ended, failed);
- **user intent** (desired-playing vs explicit pause);
- **queue state** (current identity, upcoming, previous);
- **lifecycle state** (foreground, background, interrupted, WebView reloaded);
- **session freshness** (session and generation).

These dimensions should not be collapsed into one boolean such as `isPlaying`.

## Runtime verification checklist

- [ ] Send a command with an older generation after a newer session has been adopted; confirm it is ignored.
- [ ] Replace item A with B while A is playing; confirm A's observers are detached and A cannot advance the queue later.
- [ ] End an item with a playable next item already queued.
- [ ] End an item before the next queue item arrives; then send the queue update and confirm progression.
- [ ] End an item with no next item; confirm the player waits without inventing a URL.
- [ ] Trigger stalled and failed-to-end notifications; record retry/advance behavior.
- [ ] Explicitly pause, background/foreground, and verify that user pause is not overridden by recovery.
- [ ] Interrupt audio, end the interruption, and record whether resume is attempted or intentionally suppressed.
- [ ] Reload the WebView at the same URL and at a different URL; compare restored URL, position, queue, and desired-playing state.
- [ ] Capture actual event payloads emitted through `window.__foliaNativePlayerEvent`.

## Limits

- No complete Swift source project or Xcode project was recovered from the IPA.
- Symbol names and printable strings do not reveal complete method bodies.
- No AVPlayer/MusicKit runtime test was executed as part of this static analysis.
- The compatibility router in this repository is a host integration scaffold, not a replacement for the original player implementation.


## Executable compatibility model

The repository now contains a proposed deterministic coordinator at `compat/ios-bridge/player-state.js`, with tests in `tests/player-state.test.js`. Its normalized track shape is `{ trackKey, url }`; this is an internal compatibility-model shape, not a claim about the original full track payload.

The model keeps `transport`, `desiredPlaying`, `current/upcoming/previous`, `lifecycle`, `waitingForQueue`, and `session/generation` separate. It covers:
- a user pause received while an item is loading, followed by readiness;
- rejection of stale-generation events;
- clearing prior state when a new session attaches;
- immediate advancement when a next item is already queued;
- waiting after end-of-item and advancement when a late queue arrives, but only when playback intent remains active; a paused user must explicitly resume;
- preserving the desired-playing flag for the host to interpret after the next item becomes ready;
- rejecting duplicate or late end notifications using the current URL and the `endedForURL` guard (the binary exposes an `endedForURL` stored-property name);
- failure state recording without changing session identity.

This model intentionally does not call AVPlayer, schedule retries, decide interruption-resume policy, or claim to reproduce the original implementation. Thirteen state-model tests passed locally under Node.js 22.16.0. The combined bridge and state-model suite reports 22/22 passing (9 bridge-adapter tests and 13 state-model tests). The URL-based end guard is a compatibility-model choice informed by the binary's `endedForURL` property name; repeated queue entries that reuse the exact same URL still require device testing against the original behavior.
