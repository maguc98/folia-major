# Apple Music native playback bridge — build 379 static findings

This document records the embedded MusicKit playback JavaScript found inside the supplied build-379 native executable. It is a separate playback path from the web provider registry's `foliaProviderAuth` / `appleMusicRequest` catalog operations and from the AVPlayer-oriented `foliaPlayer` handler.

## 1. Evidence boundary

- The native executable contains an embedded JavaScript command dispatcher that obtains `window.MusicKit.getInstance()`.
- The dispatcher accepts an `operation` and a parameter object, and returns structured `{ok, data}` or `{ok, error}` results.
- The binary contains the callback string `window.__foliaAppleMusicPlaybackEvent`.
- The exact outer Swift-to-JavaScript message envelope and dispatch call site are not fully established by the printable-string extraction. Do not assume these commands are sent through `foliaProviderAuth` or `foliaPlayer` without runtime capture.

## 2. Operations and observed behavior

| Operation | Observed behavior |
|---|---|
| `play` | Requires a non-empty tracks array of at most 100 entries. Catalog IDs are validated. It aligns storefront when possible, sets a MusicKit queue, starts playback, and checks queue/current identity. |
| `pause` | Cancels an in-flight start request and calls MusicKit pause. |
| `stop` | Clears the current playback epoch, cancels an in-flight start request, then pauses. |
| `resume` | Clears the previous failure flag, attempts storefront alignment, creates a new start record, and calls MusicKit play. |
| `seek` | Requires finite non-negative seconds, then calls `seekToTime`. |
| `volume` | Requires a finite number and clamps the value to 0–1. |
| `repeat` | Accepts only `off`, `one`, or `all`, mapping to MusicKit repeat modes 0, 1, or 2 when supported. |
| `prepareNext` | Verifies that the current MusicKit item matches the requested catalog ID. Accepts at most two next IDs, checks existing queue tail, clears/rebuilds the tail when it does not match, and appends only missing IDs when the existing tail is a valid prefix. |
| `next` | Calls `skipToNextItem`. |
| `previous` | Attempts `skipToPreviousItem`; if that throws, seeks to time 0. |
| `toggle` | Pauses when MusicKit reports playing (also cancels pending start); otherwise calls play. |
| `status` | Returns current catalog ID, playing state, page visibility, SDK state, startup status, position, duration, ended state, preview-only state, storefront, subscription status and failure status. |

## 3. Validation and queue identity

Directly visible validation includes:

- `play.tracks`: array, non-empty, maximum 100 entries.
- Catalog IDs: bounded string matching `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`.
- `seek.seconds`: finite and non-negative.
- `volume.volume`: finite, then clamped to 0–1.
- `repeat.loopMode`: exactly `off`, `one`, or `all`.
- `prepareNext.nextIds`: array of at most two IDs, each matching the catalog-ID pattern.
- `prepareNext.catalogId`: must match the current MusicKit queue identity; otherwise returns `stale-request`.

The script resolves a playable catalog identity from the MusicKit now-playing item and queue position. It also has a narrow equivalent-ID mapping (`window.__foliaAppleEquivalent`) so a replacement catalog ID can map back to a logical/original ID.

For `prepareNext`, the current queue tail is compared with the requested next IDs:
- If the existing tail exactly matches, no queue mutation is needed.
- If the existing tail is a prefix of the requested IDs, only the missing suffix is appended.
- Otherwise the script calls `clearAfterCurrent` if available and rebuilds the upcoming tail.
- If required MusicKit queue APIs are unavailable, it returns `unsupported`.

## 4. Request cancellation and failure reporting

The embedded script tracks a start request object with fields including `cancelled`, `accepted`, `at`, `catalogId`, and later `started`.

- A newer start replaces the current start object.
- Pause/stop/toggle can cancel the in-flight start.
- After asynchronous MusicKit operations, the script checks whether the start object is still current and not cancelled; otherwise it returns `stale-request`.
- Failure details are normalized to a bounded error code and a short message with URL/token-like strings redacted.
- The status response marks a start as failed after a 45-second threshold if it remains unstarted, unaccepted and not cancelled.

These checks indicate explicit protection against late asynchronous completion. They do not reveal the complete native-side retry policy.

## 5. Storefront and subscription handling

The script attempts to align MusicKit's storefront with the cached storefront or account country code when authorized. If playback is in preview-only mode and subscription status is not known, it queries `hasMusicSubscription()` with a 3-second wait limit. When subscribed, it switches playback mode from preview-only to mixed content.

This is a best-effort asynchronous alignment path; failure to resolve within the wait does not itself prove that playback will fail.

## 6. Status response fields observed

The returned status data includes:

- `catalogId`
- optional `errorCode`
- `playing`
- `pageVisible`
- `sdkState`
- `starting`
- `position`
- `duration`
- `ended`
- `previewOnly`
- `storefront` (truncated to 8 characters)
- `subscribed`
- `failed`

Position is normalized to a finite non-negative value, otherwise 0. Duration is normalized to a finite positive value, otherwise 0.

## 7. Integration requirements for a replacement

1. Keep this MusicKit path separate from AVPlayer unless runtime evidence establishes a shared abstraction.
2. Preserve asynchronous start cancellation and stale-request checks.
3. Preserve current-item identity checks before queue mutation.
4. Do not blindly clear the MusicKit queue; retain the existing-tail prefix optimization.
5. Keep subscription/storefront lookups bounded so they cannot block playback indefinitely.
6. Redact URLs and credentials from failure logs.
7. Capture real message envelopes and event ordering from the original app before implementing the missing outer native dispatcher.

## 8. Limits

- This is static analysis of embedded JavaScript in a compiled IPA.
- It is not the complete Swift implementation.
- The outer native dispatch envelope is not fully known.
- No MusicKit account, subscription, queue or playback runtime test was executed.
