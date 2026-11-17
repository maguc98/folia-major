# Folia iOS Build 379 — Frontend / Native Bridge Map

This note is based on static inspection of the sanitized `public/` payload and string inspection of the original compiled iOS executable. It documents observed interfaces, not reconstructed Swift source.

## 1. Web application startup

Observed from `public/index.html`:

1. Loads `runtime-config.js`.
2. Loads the hashed entry bundle `assets/main-D3qKLyAO.js`.
3. Preloads shared runtime, worker, React, config, provider registry, stores, and playback helpers.
4. Loads `ios-fix/mobile-fix.css` and `ios-fix/scale.js`.

The JavaScript bundle is production/minified output. No source maps were found in `public/assets/`, so original TypeScript/React module boundaries are not fully recoverable from this payload alone.

## 2. Native WebKit message handlers observed in frontend

### `foliaPlayer`

The main bundle accesses:

```js
window.webkit?.messageHandlers?.foliaPlayer
```

Requests are posted as objects and include a `generation` and `session` value added by the frontend.

Observed command names:

| Command | Observed payload fields / purpose |
|---|---|
| `load` | `url`, `position`, `autoplay`, `volume`, `muted`, plus current/upcoming/previous queue state |
| `upcoming` | current track key, current track, upcoming queue, previous queue |
| `play` | resume native playback |
| `pause` | pause; sometimes `userIntent` or `releaseIntent` |
| `seek` | `position` |
| `volume` | `volume` |
| `muted` | `muted` |
| `status` | request native playback state/time |

The frontend installs `window.__foliaNativePlayerEvent` as the response callback. Event types handled by the frontend are:

- `loaded`
- `error`
- `ended`
- `auto-advanced`
- `audio`
- `state`
- `time`

The web layer mirrors HTML audio playback into AVPlayer: it tracks source URL and playback position, mutes the web audio element while native playback is active, sends transport/volume/seek commands, polls native status, and falls back to web playback if the native player does not respond or reports an error. The source code includes generation/session checks to ignore stale native events.

### `foliaProviderAuth`

The provider registry accesses:

```js
window.webkit?.messageHandlers?.foliaProviderAuth
```

The request shape observed in frontend is `{ id, action, ...payload }`. The frontend creates a request ID, waits for `window.__foliaProviderAuthReply({ id, payload })`, and applies a timeout.

Observed actions:

- Apple Music: `appleMusicOpen`, `appleMusicStatus`, `appleMusicClose`, `appleMusicLogout`, `appleMusicRequest`
- 飞牛音乐: `fnmusicLogin`, `fnmusicStatus`, `fnmusicLogout`, `fnmusicRequest`

Apple Music request operations include provider catalog/library operations (for example lyrics, search, playlist and library access). The exact native implementation and authorization flow are not available in the sanitized web payload.

### Other references

The frontend includes a Capacitor runtime shim and detects iOS through `window.Capacitor`. The original executable links Capacitor and Cordova frameworks and contains the `WKScriptMessageHandler` protocol. However, the main frontend bundle did not show direct Cordova API calls during this scan.

A generic `foliaPlayback` handler helper exists in the main bundle, but no call sites to that helper were found in the inspected bundle. It should not be treated as an active bridge without runtime evidence.

## 3. Native executable evidence

The original compiled executable contains these Swift class-name strings:

- `FoliaMemoryProbe`
- `FoliaBackGuard`
- `FoliaPlaybackKeeper`
- `FoliaNativePlayer`
- `FoliaMusicProviderBridge`

It also contains references to AVPlayer, WKScriptMessageHandler, MediaPlayer, and persistent keys such as:

- `folia.native.playback.snapshot.v1`
- `folia.native.playback.lastPlaying.v1`
- `folia.native.desired-playing.v1`

These are symbol/string-level observations only. They do not reveal the complete class implementations or prove every branch is active.

## 3.1 Native class method evidence from Mach-O symbols

The stripped app executable still exposes Swift symbol names for several methods. These names make the native responsibilities clearer, but they are not source code:

| Class | Symbol-level methods observed | Supported interpretation |
|---|---|---|
| `FoliaNativePlayer` | `install(on:)`, `handleCommand`, `load(url:position:autoplay:track:queue:previous:)`, `pause(clearIntent:)`, `remoteNext`, `remotePrevious`, `emit`, `restorePersistedPlaybackIfNeeded` | Owns AVPlayer playback, queue/remote commands, state events and persisted playback recovery |
| `FoliaPlaybackKeeper` | `install(on:)`, `setupNowPlayingCommands`, `updateNowPlayingInfo`, `beginKeepAliveIfPlaying`, `handleExternalAudioInterruption`, `prepareSessionAfterInterruption`, `handleRouteChange` | Coordinates lock-screen/Control Center metadata, remote controls, audio session and background keep-alive |
| `FoliaMusicProviderBridge` | `installOnMainWebView`, `loginFnMusic`, `requestFnMusic`, `showAppleMusicLogin`, `performAppleMusicRequest`, `requestApplePlayback`, `pollApplePlayback`, `reply` | Handles provider auth/request traffic, including FnMusic and Apple Music |
| `FoliaBackGuard` | `install(on:)`, `webViewWebContentProcessDidTerminate`, `coverTerminationReload`, `dismissTerminationSnapshot`, `disableGestures`, `startWatching` | Watches WKWebView lifecycle and presents/reloads around WebContent termination |
| `FoliaMemoryProbe` | `start`, `handleWarning` | Samples/handles memory pressure warnings |
| `QishuiOfficialLogin` | `startWatching`, `presentMfa`, `injectMfaScript`, `checkMfaResult`, `retryLoginPage`, `teardown` | Separate native login overlay and MFA/login-session handling for Qishui |

The executable also contains `node_start` / `_node_start` symbols and the literal `nodejs-project/main.js`, consistent with the NodeMobile startup path described in [node-runtime-map.md](node-runtime-map.md).

## 4. iOS adaptation script provenance

`public/ios-fix/scale.js` comments explicitly say the adaptation layer is injected by a local preview service / NAS gateway and does not modify upstream source. It contains viewport scaling, device-pixel-ratio capping, WebGL context limiting, and optional diagnostic harness code. Treat it as an injected deployment-side patch unless its provenance is independently confirmed.

`public/runtime-config.js` is a placeholder that preserves `window.__FOLIA_RUNTIME_CONFIG__`; the file comments say actual values come from Vite environment variables. No production secrets were found in that stub.

## 5. Build implications

- The sanitized archive contains the packaged web/runtime payload, not the original editable Xcode project or Swift source tree.
- The frontend can be modified as web assets, but a reproducible native IPA build still requires the original Xcode project/build settings, plugin registrations, entitlements, and native bridge implementations (or a deliberate reimplementation).
- Do not replace the native bridge with guessed JavaScript shims. Keep the observed message names and payload contracts stable until native-side behavior is confirmed.
- Preserve upstream/dependency notices and review AGPL-3.0 and dependency-specific obligations before redistributing modified source or binaries.
