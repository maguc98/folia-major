# Folia iOS 3.0.6 (build 379) — Web ↔ Native Bridge Contract

> Evidence basis: the sanitized build-379 `public/` payload (compiled JavaScript) plus printable strings and Swift symbol names from the supplied IPA's `Payload/App.app/App` Mach-O. This is a static protocol map. It is not recovered Swift source and does not prove that every branch succeeds on a live device.

## 1. Bridge inventory

| WebKit message handler | Web-side implementation | Native-side evidence | Role |
|---|---|---|---|
| `foliaPlayer` | `assets/main-D3qKLyAO.js`; one additional startup-prompt message in `assets/bootstrap-FH45rHF5.js` | `FoliaNativePlayer`, `FoliaPlaybackKeeper`; `userContentController(_:didReceive:)`, `handleCommand` symbols | AVPlayer transport, queue synchronization, state/time/audio events, startup-prompt acknowledgement |
| `foliaProviderAuth` | `assets/providerRegistry-H9rGE1g_.js` | `FoliaMusicProviderBridge`; `userContentController(_:didReceive:)`, `reply(id:payload:)` symbols; native strings for handler and reply callback | Apple Music and Feiniu Music auth/API operations |

The two handlers are separate protocols. Do not route provider-auth messages through the player handler or assume that provider operations are served by NodeMobile.

## 2. Player protocol: `foliaPlayer`

### 2.1 Common envelope

The web sender is structurally:

```js
handler.postMessage({
  ...message,
  generation: currentGeneration,
  session: currentSession
});
```

- `session`: per-web-runtime random UUID when available, otherwise a generated fallback identifier.
- `generation`: monotonically updated playback generation used to reject stale events/commands around source changes and invalidation.
- Web sender increments its sent-command counter only when `postMessage` returns without throwing.
- A successful `postMessage` means only that the message was submitted to WebKit; it is not an acknowledgement that AVPlayer completed the operation.

### 2.2 Commands observed in the main web bundle

| Command | Observed payload | Notes |
|---|---|---|
| `load` | `url`, `position`, `autoplay`, queue fields from `Po()` | Queue fields: `currentTrackKey`, `track`, `upcoming`, `previous`. URL is accepted by the web layer only when it is null/empty where permitted or matches HTTP(S)/file URL checks. |
| `play` | common envelope | Resume current native item. |
| `pause` | common envelope; some calls add `userIntent` or `releaseIntent` | Distinguishes user pause and release of native playback intent in specific paths. |
| `seek` | `position` (seconds) | Sent when the mirrored web audio currentTime changes. |
| `volume` | `volume` (0–1) | Web layer clamps the value. |
| `muted` | `muted` (boolean) | Sent independently from volume. |
| `status` | common envelope | Requests/refreshes native playback state. Web layer polls/requests after focus, pageshow, visibility changes and stale status intervals. |
| `upcoming` | `currentTrackKey`, `track`, `upcoming`, `previous` | Synchronizes the native queue. |

The bootstrap bundle also sends `{cmd: "startup_prompts_seen"}` through `foliaPlayer`. This is a separate app-startup acknowledgement, not one of the eight transport commands emitted by the main player transport helper.

### 2.3 Native-to-web event types observed

The callback installed by the web layer is `window.__foliaNativePlayerEvent`.

| Event `type` | Fields read by the web callback | Web-side effect |
|---|---|---|
| `loaded` | `session`, `generation` | Marks native player alive, clears pending/failure state, resets audio-analysis snapshot and pauses the background web audio path. |
| `error` | `message`, `session`, `generation` | Marks native playback failed and falls back to web audio. |
| `state` | `playing`, `position`, `sentAtMs`, `session`, `generation` | Updates play/pause state, synchronizes position and dispatches corresponding HTML media events. |
| `time` | `playing`, `position`, `duration`, `sentAtMs`, `session`, `generation` | Updates timeline/duration and queue auto-advance bookkeeping. |
| `ended` | `url`, `autoAdvancePrepared`, `session`, `generation` | Completes current item; may dispatch a delayed HTML ended event when native auto-advance is prepared. |
| `auto-advanced` | `trackKey`, `url`, `session`, `generation` | Updates current track identity and starts position tracking for the next item. |
| `audio` | `power`, `bass`, `lowMid`, `mid`, `vocal`, `treble`, `session`, `generation` | Stores audio-analysis bands, each clamped to 0–255, for visual effects. |

The web callback rejects events from a different non-empty session and ignores stale generations in normal event handling. `ended` and `auto-advanced` have dedicated ordering/identity guards.

### 2.4 Important playback behavior

- The web layer intercepts cross-origin HTML audio playback and mirrors it into native AVPlayer when the native bridge is available and enabled.
- The web audio element is used as a clock/state mirror while native AVPlayer supplies audio output; the web element is muted while native playback owns the audio.
- The layer falls back to web playback when native initialization/load fails or the source is not accepted by the native path.
- Native status is refreshed after visibility/focus transitions; web code also maintains a local estimated position between native time events.
- Queue identity is keyed by `trackKey`; the current item, upcoming list and previous list are sent together.

These are behaviors implemented by the compiled web bundle. The exact native-side validation and all AVPlayer error branches require source or device instrumentation to verify.

## 3. Provider protocol: `foliaProviderAuth`

### 3.1 Request/reply envelope

The provider bundle installs `window.__foliaProviderAuthReply` and sends:

```js
handler.postMessage({
  id: requestId,
  action,
  ...payload
});
```

- Request ID format observed: `provider-<timestamp>-<incrementing counter>`.
- Pending requests are held in a Map.
- Default timeout: 45 seconds.
- A reply is accepted only when it has a matching `id`.
- Expected reply shape: `{ id, payload: { ok: true, data } }` or `{ id, payload: { ok: false, error } }`.
- Success resolves to `payload.data`; failure rejects with `payload.error` or `native-provider-auth-failed`.

### 3.2 Exact actions observed

| Action | Additional payload | Web timeout / behavior |
|---|---|---|
| `appleMusicOpen` | none | 20 s |
| `appleMusicClose` | none | 5 s; close errors are swallowed |
| `appleMusicLogout` | none | 10 s; logout errors are swallowed |
| `appleMusicRequest` | `operation`, `params` | 30 s |
| `appleMusicStatus` | none | 20 s |
| `fnmusicLogin` | login form object supplied by caller | default 45 s |
| `fnmusicLogout` | none | default 45 s; logout errors are swallowed |
| `fnmusicRequest` | `path`, `method`, optional `params`, optional `body` | default 45 s |
| `fnmusicStatus` | none | default 45 s |

The `appleMusicRequest` operation names are dynamically supplied by the provider implementation; this scan establishes the envelope but does not establish a complete exhaustive operation list.

### 3.3 Provider-specific paths

**Apple Music**
- The web provider calls `appleMusicOpen`, `appleMusicStatus`, `appleMusicClose`, `appleMusicLogout` and `appleMusicRequest`.
- The request payload uses `operation` and `params`.
- The native binary contains `FoliaMusicProviderBridge` symbols for Apple web view setup, login UI, cookie identity resolution, account refresh, request execution, playback requests/polling and reply delivery.
- Native symbols establish that these implementation paths exist in the compiled binary; they do not expose the full Swift request allowlist or response schema.

**Feiniu Music**
- Login uses `fnmusicLogin`; status/logout use their matching actions.
- API requests use `fnmusicRequest` with `path`, `method`, optional `params` and `body`.
- The web provider maps these calls to Feiniu API paths such as `/music/api/v1/search/track`, `/music/api/v1/lyric/list`, playlist and album listing paths.
- The provider bundle explicitly marks `playback: false`; do not assume this provider's metadata/lyrics bridge also implements audio playback.

## 4. Relationship to NodeMobile

The two WebKit handlers above are native message handlers. The NodeMobile HTTP server is a distinct local service layer with its own localhost ports and routes.

- `foliaPlayer`: native AVPlayer/control path.
- `foliaProviderAuth`: native provider authentication/request path.
- NodeMobile: local HTTP endpoints for selected provider APIs, proxying, Qishui and fallback services.

A future wrapper must preserve each route independently. A generic replacement WebView with only a `foliaPlayer` stub will not satisfy the provider registry, and a NodeMobile process alone cannot replace the native AVPlayer bridge.

## 5. Compatibility checklist for a replacement wrapper

### Required handler registration
- [ ] Register `foliaPlayer` before loading the Folia web page.
- [ ] Register `foliaProviderAuth` before loading the Folia web page.
- [ ] Install the native callback delivery path for `__foliaNativePlayerEvent`.
- [ ] Install the native callback delivery path for `__foliaProviderAuthReply`.
- [ ] Preserve the request ID and session/generation values exactly; do not silently rename fields.

### Player contract tests
- [ ] `load` with HTTP(S) source, initial position, autoplay and track queue.
- [ ] `play`, `pause`, `seek`, `volume`, `muted` round trips.
- [ ] `status` response/event updates the web state.
- [ ] `upcoming` queue sync, next-item advance and previous-item identity.
- [ ] `loaded`, `error`, `state`, `time`, `ended`, `auto-advanced`, `audio` events.
- [ ] Reject stale session/generation messages and test web-audio fallback.
- [ ] Background audio, lock-screen remote commands, interruptions and WebContent process reload.

### Provider contract tests
- [ ] Request/reply success and error envelopes.
- [ ] Unknown request ID is ignored safely.
- [ ] Timeout cleanup removes pending request entries.
- [ ] Apple Music open/status/request/close/logout.
- [ ] Feiniu login/status/request/logout.
- [ ] Validate native operation/path allowlists and prevent arbitrary URL forwarding.
- [ ] Verify no token, cookie, password or session state is emitted into JavaScript logs.

### Security and robustness observations
1. The bridge is exposed to JavaScript running in the WebView. The replacement wrapper should validate message body types, allowed actions, payload sizes and origin/frame trust before acting.
2. For Feiniu requests, validate `path` against a fixed API path allowlist and reject absolute URLs, traversal segments and unexpected schemes.
3. For Apple Music, validate `operation` against the native implementation's supported operation registry.
4. Never treat a client-provided request ID, session ID or generation as authentication.
5. Do not log credentials, cookies, auth response bodies or private user data.
6. Reply to every accepted provider request exactly once; always include the matching ID and the documented `payload.ok` envelope.
7. Preserve request timeouts and clean pending entries on both resolve and reject.



## 6. Additional native-side Apple Music playback bridge evidence

A second pass over the native executable's embedded printable JavaScript strings revealed a MusicKit command implementation associated with the native `FoliaMusicProviderBridge`. This is distinct from the web provider registry's `appleMusicRequest` operation envelope.

The embedded script checks for `window.MusicKit.getInstance()` and supports these command operations:

- `play`
- `pause` / `stop`
- `resume`
- `seek`
- `volume`
- `repeat`
- `prepareNext`
- `next`
- `previous`
- `toggle`
- `status`

Validation visible in the embedded script includes:

- `play`: non-empty `tracks` array, at most 100 entries; each `catalogId` must match the bounded alphanumeric/dot/underscore/hyphen pattern.
- `seek`: `seconds` must be finite and non-negative.
- `volume`: `volume` must be finite and is clamped to 0–1.
- `repeat`: `loopMode` must be one of `off`, `one`, `all`.
- `prepareNext`: `nextIds` must be an array of at most two IDs, and the requested current catalog identity must match the MusicKit queue identity.

The embedded script also contains queue-identity checks, stale-request/epoch cancellation, storefront alignment, and a narrowly scoped equivalent-catalog-ID recovery path. These are meaningful native implementation details visible in the binary's embedded JavaScript strings. They do **not** establish the exact outer WebKit message envelope for every MusicKit command, so the compatibility checklist should not invent one.

The native binary also contains the string `appleMusicPlayback`, while the shipped provider registry's direct WebKit request helper uses `appleMusicRequest`. Treat these as separate native-side concepts until the original Swift message dispatch source or runtime traces establish the exact mapping.

## 7. Evidence limits and next implementation step

- The JavaScript request and event envelopes above are directly visible in the shipped bundles.
- The IPA binary contains native class/method symbols consistent with the handlers and playback/provider responsibilities.
- The IPA does not include the editable Swift source. Binary symbols cannot establish every native branch, parameter validator, queue policy or failure response.
- Before implementing a replacement wrapper, obtain the author's native project or instrument the original app on a test device to capture representative message/reply pairs.
- Do not alter the production bridge protocol based only on guessed native behavior. First build a protocol harness that can replay captured fixtures and compare event ordering.

## 8. Synthetic contract fixtures and tests

The repository includes a JSON Schema at `schemas/native-bridge-build379.schema.json`, synthetic message fixtures at `tests/fixtures/native-bridge-build379.json`, and dependency-free structural tests at `tests/test_native_bridge_build379.py`. These fixtures are intentionally synthetic and contain no real account/session data. They test the observed web-side envelope shape only; they are not packet captures from the original app and do not verify native execution.

Run the structural checks with:

```bash
python3 -m unittest discover -s tests -p 'test_native_bridge_build379.py' -v
```

## 9. Source files examined

- `public/assets/main-D3qKLyAO.js`
- `public/assets/bootstrap-FH45rHF5.js`
- `public/assets/providerRegistry-H9rGE1g_.js`
- `Payload/App.app/App` (strings and Swift symbol names only)
