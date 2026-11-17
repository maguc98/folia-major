# Native player runtime test plan — build 379

This test plan is based on the supplied build-379 executable's printable strings and Swift symbols. It translates embedded self-test markers into repeatable device checks. It does not claim that the tests have been run.

## 1. Runtime state fields observed in the binary

The executable contains these stored-property names associated with the native player:

- `currentURL`, `currentGeneration`, `currentSessionId`
- `currentTrackKey`, `currentTrackTitle`, `currentTrackArtist`, `currentTrackArtworkURL`
- `playbackIntent`, `resumeOnForeground`, `interruptionActive`, `resumeAfterInterruption`
- `previousTracks`, `upcomingTracks`, `pendingAutoAdvanceWork`, `autoAdvanceCount`
- `timeObserver`, `timeObserverOwner`, `observedItem`, `itemStatusObservation`
- `pendingSeekSeconds`, `lastSentPosition`, `volume`, `muted`, `endedForURL`
- `wasPlayingBeforeInterruption`, `autoResumeTimer`, `autoResumeAttempts`

These names show that the native implementation tracks more than a single playing boolean. They do not expose the exact types, mutation rules, or persistence format.

## 2. Embedded self-test evidence

The binary includes these marker strings:

- `FOLIA_NATIVE_SELFTEST`
- `FOLIA_NATIVE_QUEUE_SELFTEST`
- `FOLIA_NATIVE_QUEUE_AHEAD_SELFTEST`
- `FOLIA_NATIVE_LATE_QUEUE_SELFTEST`
- `FOLIA_NATIVE_UNPLAYABLE_SELFTEST`
- `FOLIA_NATIVE_BACKGROUND_SELFTEST`
- `FOLIA_NATIVE_RESTART_PREP_SELFTEST`
- `FOLIA_NATIVE_REMOTE_SELFTEST`

It also includes diagnostic messages describing these intended checks:

| Embedded marker/message | Test intention supported by the string |
|---|---|
| `selftest: step2 load A + play` | Start item A |
| `selftest: step3 load B oldRate=` | Replace A with B and inspect old playback rate |
| `oldItemReleased=` / `dual oldStopped=` | Check old item release/stop after replacement |
| `step5 pauseStable=` / `step6 resume=` | Check pause stability and subsequent resume |
| `step7 sameUrlReload=` | Check same-URL reload behavior |
| `step9 userPauseCleared=` | Check explicit user-pause intent |
| `step10 programmaticPause=` / `foregroundRecovery=` | Check programmatic pause and foreground recovery |
| `step11 desiredRetainedAfterEnd=` | Check desired-playing state after item end |
| `queue-selftest: started A with B queued` | Start A with B already queued |
| `queue-selftest: started A with mismatched B-ahead queue` | Exercise queue identity mismatch |
| `ended -> next queue is playable` | End with a playable next item |
| `ended without queued next -> waiting for page` | End without a queued next item |
| `upcoming queued ahead generation=` | Receive upcoming queue before end |
| `late-queue-selftest` | Exercise queue arrival after the current item ends |
| `item unplayable source=` | Exercise an unplayable current item |
| `audio interruption ended -> intent cleared before resume` | Exercise interruption-end behavior |
| `native background deferred` / `native foreground deferred` | Exercise lifecycle work deferred during interruption |
| `remote commands ready next=` | Check remote transport command setup |

A string `selftest: PASS session=` is present. The executable also contains `selftest: step1 nan/inf payload survived`; this is a test diagnostic label, not proof that the validation outcome was safe. The binary does not reveal whether these self-tests were run in the supplied installation, or their actual output.

## 3. Device test matrix

| ID | Setup/action | Record | Pass condition for the replacement implementation |
|---|---|---|---|
| NP-01 | Play A, then load B while A is playing | A/B item identity, observer callbacks, rate | A no longer advances playback or emits current-item events after B owns playback |
| NP-02 | Explicitly pause, then wait through multiple status/time ticks | intent, rate, emitted state | Playback remains paused; no autonomous resume |
| NP-03 | Play A with B queued before A ends | queue keys, ended/auto-advanced events | B starts once, in order, with no duplicate advance |
| NP-04 | Play A without B; send B after A ends | event timestamps, queue update, playback start | Player waits and starts B once it becomes available |
| NP-05 | Queue an item whose identity does not match the expected current item | current key, queue keys, logs | Mismatched queue is rejected or reconciled without skipping the wrong item |
| NP-06 | Load an invalid/unplayable item with and without a next item | error event, intent, queue | No false playing state; waits or advances only according to verified policy |
| NP-07 | Background during active playback, then foreground | position continuity, audio route, app lifecycle callback, background mode | Playback remains continuous where platform policy permits; foreground does not restart an already-playing item; host receives background/foreground callbacks |
| NP-08 | Explicitly pause, background, foreground | desired-playing and actual rate | Foreground recovery does not override explicit user pause |
| NP-09 | Trigger an audio interruption and end it with and without the iOS `shouldResume` option | interruption flags, audio-session activation result, desired-playing, rate | Resume occurs only when playback was intended, iOS supplies `shouldResume`, and audio-session reactivation succeeds; a user pause during interruption is never overridden |
| NP-10 | Reload WebView at same URL while playing | URL, position, generation, session, queue | Restore is bounded and does not duplicate playback or accept stale commands |
| NP-11 | Reload WebView at a different URL | old/new session, item, callbacks | Old session is invalidated; no old queue callback mutates new playback |
| NP-12 | Use lock-screen / headset next, previous, play, pause | remote command result, now-playing metadata | Remote commands reach the current native item and metadata remains consistent |
| NP-16 | Disconnect wired/Bluetooth headphones during playback | route-change reason, desired-playing, AVPlayer rate, output route | Playback pauses and clears desired intent; audio must not unexpectedly move to the speaker |
| NP-17 | Trigger interruption, press pause while interrupted, then end interruption | desired-playing, interruption flag, resume option, rate | Explicit pause wins; no automatic resume occurs |
| NP-18 | Trigger interruption while already paused, then end it | desired-playing, interruption flag, rate | No spurious playback start occurs |
| NP-19 | Enter background and foreground repeatedly while paused and while playing | lifecycle callbacks, playback position, intent, rate | Lifecycle notifications do not mutate user intent or create duplicate playback |
| NP-13 | Seek to 0, duration boundary, negative, NaN, Infinity | accepted/rejected payload and actual position | Invalid numeric inputs are rejected; valid seeks are bounded by player duration policy |
| NP-14 | Change volume and mute independently | volume, mute, audio output | Volume 0–1 and mute remain independent and consistent |
| NP-15 | Force WebContent process termination/reload | snapshot, restored item, position, intent | Recovery is deterministic and does not resurrect a stale session |

## 4. Required capture format

For every test, record:

- Device model and iOS build
- App version/build and whether the test is the original app or replacement
- Exact action sequence with timestamps
- Current URL and track key (redact private URLs/tokens)
- Session and generation values
- Native event type and payload, with personal data removed
- AVPlayer item status, rate, current time, duration
- Queue current/upcoming/previous identities
- App foreground/background and audio-interruption state
- Result: pass, fail, blocked, or not applicable

Do not include Apple Music cookies, provider tokens, account identifiers, or signed media URLs in logs.

## 5. Execution order

1. Run NP-01 through NP-06 first. These establish item ownership and queue correctness.
2. Run NP-07 through NP-11. These establish lifecycle recovery and stale-session isolation.
3. Run NP-12 through NP-14. These establish system controls and numeric/media controls.
4. Run NP-16 through NP-19 to verify the new route/interruption/lifecycle policy.
5. Run NP-15 last, because process termination may require reinstall/relaunch and can obscure earlier state.

## 6. Current status

- Static analysis of the IPA: complete for the symbol/string evidence summarized here.
- Test plan: documented.
- Original app self-test execution: not observed.
- Replacement host implementation: partial scaffold; interruption/route/background callbacks are now present but not device-verified.
- Xcode build and device execution: not performed.
