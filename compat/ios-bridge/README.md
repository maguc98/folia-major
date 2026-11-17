# Build-379 bridge compatibility layer

This directory contains a small, dependency-free CommonJS adapter for projects that need to speak the observed Folia iOS build-379 WebKit bridge contract.

- `bridge-contract.js`: validates known player and provider message envelopes.
- `bridge-client.js`: injectable player/provider transports with session/generation stamping, request IDs, timeout cleanup and correlated replies.
- `../../tests/bridge-compat.test.js`: Node built-in tests (11 local cases in the current working test run).

Run:

```bash
node --test tests/bridge-compat.test.js
```

## Integration boundary

The adapter does not create a WKWebView, AVPlayer, MusicKit session, Apple Music login, Feiniu login, or NodeMobile server. The host application must register the native WebKit message handlers and implement the native actions. The adapter is a web-side protocol helper only.

The adapter rejects unsupported Apple Music operation names, unsafe Feiniu API paths (including traversal, query/fragment, backslash and control characters), malformed reply envelopes, invalid request IDs/timeouts, and stale/duplicate replies. The provider path check is defense in depth, not a security boundary. Native code must independently enforce action/path allowlists, origin/frame policy, payload size limits and credential-safe logging. The exact native implementation is not available as editable Swift source in the supplied IPA.

Do not use this adapter as a drop-in replacement for the original Folia player bundle without testing its call sites and event ordering on a device.
