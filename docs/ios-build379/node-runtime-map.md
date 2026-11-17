# Folia iOS Build 379 — Embedded Node Runtime Map

This document is based on direct inspection of the sanitized `public/nodejs-project/` files. JavaScript syntax checks passed under Node.js 22.16.0 for `main.js`, `qishui-bridge.js`, and `netease-fallback.js`. This is syntax validation only; it is not an iOS NodeMobile runtime test.

## 1. Runtime layout

- `package.json`: name `folia-node-backend`, version `0.1.0`, entry `main.js`; no dependencies declared in this small manifest.
- `main.js`: 19,789 bytes; embedded Node service bootstrap and local HTTP proxy.
- `qishui-bridge.js`: local Qishui protocol/session bridge.
- `netease-fallback.js`: Netease fallback adapter.
- `netease-fallback-routes.json`: fallback route metadata.
- `node_modules/`: packaged dependency tree; the sanitized archive contains 475 package.json files overall.

The native app links NodeMobile.framework. The observed architecture is therefore a NodeMobile runtime launched by the native shell, with a local HTTP service consumed by the Web frontend.

## 2. Local service ports

The backend binds to loopback only (`127.0.0.1`):

| Service | Default port | Purpose observed in source |
|---|---:|---|
| Kugou | 3211 | starts `kugoumusicapi/server.js` |
| QQ Music | 3212 | requires `@yakult-green-tea/qq-music-api`, which starts its listener |
| General proxy / Qishui bridge | 3213 | HTTP proxy, Qishui API/media endpoints, login page static serving |

All three ports can be shifted by `FOLIA_LOCAL_PORT_OFFSET`; each also has an individual environment override.

## 3. Startup compatibility patches

`main.js` includes explicit Node 18 compatibility work:

- Adds `globalThis.crypto = require('crypto').webcrypto` if absent.
- Adds an `AbortSignal.any` polyfill if missing.
- Sets `QQ_AUTH_STATE_PATH` under the native-provided `FOLIA_LOG_DIR` when available.
- Adds a missing QQ `/login/channels` route.
- Replaces the QQ auth session repository with a file-backed implementation.
- Limits log writes and swallows I/O failures to avoid stdout pipe errors or excessive disk writes terminating the app.

These comments describe fixes for NodeMobile/iOS constraints; preserve them during refactoring unless device testing proves a replacement is safe.

## 4. Qishui bridge

`qishui-bridge.js` creates a local Qishui API using `qishui-music-api`.

Observed endpoints handled by the bridge:

- `POST /__qishui-api/pair`: returns a persistent random pairing token.
- `POST /__qishui-api/reset`: logs out and clears pairing/session state.
- `POST /__qishui-api`: requires the `x-folia-qishui-token` header and an operation/params body.
- The bridge filters operations through `READ_ONLY_OPERATIONS`; playlist add/remove and dislike operations are excluded by the source.
- Session state is stored outside Documents, in a Library/Caches location derived from `FOLIA_LOG_DIR`; file permissions are set to 0700 for the directory and 0600 for the state file.
- Credentials are intended to remain in the Node process and app sandbox, not returned to the web frontend.

The Qishui media URL helper validates media URLs before the local media proxy fetches them.

## 5. General proxy and additional endpoints

The local HTTP server in `main.js` handles:

- `POST /__netease-fallback`: invokes the Netease fallback adapter.
- `GET|HEAD /__qishui-media?url=...`: fetches trusted Qishui media and forwards byte-range headers for streaming/seeking.
- `GET /__qishui-open-flag` and `POST /__qishui-open`: one-shot flag used to signal the native side to open Qishui login.
- `GET /qishui-login/*` and `GET /qishui-auth-v6/*`: serves bundled login/auth helper pages.
- `POST /__trace`: appends navigation trace lines to the configured log directory.
- Other POST requests are treated as generic HTTP(S) proxy requests and return upstream status, headers, and body.

### Review item

The generic proxy branch accepts the target URL from the POST body and does not show a hostname allowlist in this handler. The server is bound to loopback, which limits network exposure, but any untrusted page/script able to reach the local service could potentially use it to request arbitrary HTTP(S) targets. Before expanding the web content trust boundary, consider adding strict origin/host allowlists, method restrictions, request size/time limits, and explicit authentication for generic proxy requests. This is a static-review concern, not a confirmed exploit.

## 6. Rebuild implications

The Node service source is available in the sanitized payload and can be modified independently. However, rebuilding the complete iOS app still requires the native Xcode project/build settings, NodeMobile framework integration, environment-variable injection, resource-copy phases, and native launch/shutdown lifecycle code. The IPA alone does not provide those source project files.
