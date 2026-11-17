# NodeMobile runtime and local services host contract

> This document is based on direct inspection of the sanitized build-379 `public/nodejs-project/main.js`, `qishui-bridge.js`, `netease-fallback.js`, and their small package manifest. It does not recover the missing native NodeMobile launcher implementation.

## Node project entry and runtime assumptions

- Package: `folia-node-backend@0.1.0`
- Entry point: `main.js`
- Runtime assumed by the source: Node.js 18 inside NodeMobile.
- Required packaged tree: the complete `public/nodejs-project/`, including `main.js`, `qishui-bridge.js`, `netease-fallback.js`, route/config JSON, login assets referenced by the server, and the entire `node_modules/` tree.
- The original IPA contains `NodeMobile.framework` and a compiled `NodeRunner.start(projectDirectoryName:)` symbol, but no native Swift launcher source or framework headers. The exact call ABI, arguments, stdout/stderr wiring, lifecycle, and resource-copy phases cannot be proven from the IPA.

## Environment contract visible in main.js

| Variable | Purpose |
|---|---|
| `FOLIA_LOG_DIR` | Writable app-owned directory for service logs and QQ auth/device state paths |
| `FOLIA_LOCAL_PORT_OFFSET` | Offset applied to default loopback ports |
| `FOLIA_KUGOU_PORT` | Optional explicit Kugou port, default 3211 + offset |
| `FOLIA_QQ_PORT` | Optional explicit QQ Music port, default 3212 + offset |
| `FOLIA_PROXY_PORT` | Optional explicit general/Qishui proxy port, default 3213 + offset |
| `QQ_AUTH_STATE_PATH` | Optional QQ device-state path; when unset, main.js derives it from FOLIA_LOG_DIR |

All servers bind to `127.0.0.1`, not a LAN interface. Kugou is started with `kugoumusicapi/server.js` and `startService()`; QQ starts as a require-time side effect from `@yakult-green-tea/qq-music-api`. The Node entry adds a missing QQ `/login/channels` route and configures file-backed QQ auth-session persistence.

## Local endpoints observed in the source

- `127.0.0.1:3211`: Kugou API server.
- `127.0.0.1:3212`: QQ Music API server.
- `127.0.0.1:3213`: general HTTP proxy and Qishui bridge, unless overridden.
- `POST /__netease-fallback`: invokes the Netease fallback adapter; request body cap is 512 KiB.
- `GET|HEAD /__qishui-media?url=...`: streams allowlisted Qishui media and forwards Range headers.
- `POST /__qishui-api/pair`, `POST /__qishui-api/reset`, `POST /__qishui-api`: Qishui local bridge pairing, reset, and authenticated operation calls.
- `GET /__qishui-open-flag`, `POST /__qishui-open`: one-shot flag polled by native host to request opening Qishui login.
- `GET /qishui-login/*` and `GET /qishui-auth-v6/*`: static login/signature helper pages.
- `POST /__trace`: writes a navigation trace to the log folder.
- Other POST requests: generic HTTP/HTTPS proxy requests.

The generic proxy handler accepts a URL from its JSON body and does not show a host allowlist. Although bound to loopback, another local process or an untrusted page with access to the local port could try to use it for arbitrary outbound requests. A rebuilt host should add origin/token checks, destination allowlists, method/body/time limits, redirect policy, and safe header filtering before exposing this endpoint to web content.

## Node 18 compatibility and operational safeguards

The source installs WebCrypto if absent, a polyfill for `AbortSignal.any`, and a file-backed QQ auth repository because the NodeMobile working directory is read-only and the app restarts. It intentionally catches stdout pipe failures, drops nonessential request logs, and caps the log at approximately 2 MiB to avoid disk-write runaway behavior. Keep these safeguards unless reproduced device tests prove a safe replacement.

Qishui stores its pairing token, device identifier and account session under a Library/Caches path derived from `FOLIA_LOG_DIR`, uses a timing-safe token comparison, and rejects operations outside its read-only operation set. Its media proxy validates URLs through the package's `mediaUrl` helper and supports HTTPS fetch without Node's WebAssembly-dependent fetch implementation. Do not move these credential files into a public or repository directory.

## Recommended native-host integration sequence

1. Create or recover an iOS Xcode target that links the provided `NodeMobile.framework` and includes the full sanitized `nodejs-project` resource tree in the app bundle.
2. Resolve the bundled project directory at runtime and provide a writable app-container log directory. Set the environment variables above before calling the verified NodeMobile start API.
3. Use the actual NodeMobile header shipped with the framework or framework vendor documentation to implement the launcher. Do not guess C function signatures from a Swift symbol string.
4. Implement explicit startup/ready/failure/shutdown state and wait for the three loopback listeners before the WebView requests them. Use a bounded readiness timeout and clean up on app termination.
5. Pass the selected port configuration to the front end using the exact environment/config mechanism already expected by the web bundle.
6. Add request authentication and an outbound host/method allowlist to the general proxy before widening the trusted WebView origin set.
7. Validate Kugou, QQ QR login, QQ session persistence, Qishui pairing/login/media ranges, NetEase fallback, backgrounding, app restart and port collision on physical devices.

## Current implementation status

The repository has static maps and JS/Swift playback/provider scaffolds, but this checkout still does not have a native NodeMobile launcher, a complete imported `nodejs-project/` tree, the framework's build headers, or the original Xcode target configuration. Therefore the three Node services cannot truthfully be marked as started or integrated in an installable IPA. The binary IPA alone is not enough to rebuild that layer.


## Relationship to the native provider bridge

The Swift host can route `appleMusic*` requests into `apple-music-provider.js` once the host calls `installAppleMusicProviderDispatcher` (or the combined `installAppleMusicServices`) after the MusicKit script is configured. Non-Apple Music provider actions, including `fnmusic*`, continue to be delivered to the host's injected `onProviderRequest` callback. No Feiniu service has been invented or marked as available.


## Swift host coordinator

`compat/ios-bridge/ios/FoliaNodeRuntimeCoordinator.swift` defines the required NodeMobile driver contract and the startup/readiness lifecycle:

- The integrating app implements `FoliaNodeRuntimeDriver` against the actual NodeMobile header/framework ABI and passes that adapter into `FoliaNativePlaybackHost`.
- The coordinator creates the app-owned Application Support/FoliaNode directory and supplies the exact `FOLIA_*` and `QQ_AUTH_STATE_PATH` environment keys read by `main.js`.
- The driver starts project directory `nodejs-project`; the coordinator waits for the Kugou, QQ and proxy loopback listeners (3211/3212/3213 plus the selected offset) before reporting ready.
- Failed readiness stops the driver and reports a bounded failure state. Explicit host shutdown stops the Node runtime.

This does not provide the missing concrete NodeMobile driver. It is intentionally impossible to supply that driver accurately from the IPA alone because the embedded framework header/launcher ABI and a complete resource bundle are not present as editable source.


The latest coordinator stores logs and QQ auth-state files in the app's private Application Support directory (file-protected and excluded from backup), not the user-visible Documents directory.
