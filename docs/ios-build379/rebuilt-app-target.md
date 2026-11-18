# Folia build 379 — rebuilt native app target

This is a **new, explicitly reconstructed host target**, not recovered upstream Xcode source. It uses the inspected build-379 app metadata and the public NodeMobile launcher API. It must not be represented as byte-for-byte equivalent to the original native app.

## Evidence recovered from the original IPA

- App bundle: `top.izuna.foliaios`
- App version/build: `3.0.6 (379)`
- Minimum iOS: `15.0`
- Embedded frameworks: `Capacitor.framework`, `Cordova.framework`, and `NodeMobile.framework`
- The embedded NodeMobile binary reports Node.js `v18.20.4`.
- The original app bundle contains `public/` and the complete `public/nodejs-project/` tree.
- The NodeMobile framework binary is device-only arm64 in the inspected IPA. The original IPA does not contain the framework's public headers or the upstream Xcode project.

Original IPA SHA-256:
`d2702706ff6dede4533ea895b9fd42c0f718ab1f4d1cfddbcf3e21b1500218de`

Sanitized public payload SHA-256:
`f8e08042914a01f63f8aabbadd9f61cca32dd92fd45cfe194495f1e40acbab32`

The source payload is kept outside this Git repository to avoid committing a 40+ MB dependency archive. The build workflow accepts an HTTPS URL and expected SHA-256 for the sanitized payload.

## Concrete NodeMobile entry point

The official Node.js Mobile iOS guide documents the Objective-C declaration:

```objc
void node_start(int argc, char* argv[]);
```

and starts Node on a dedicated thread with a 2 MB stack. The rebuilt Swift adapter calls this documented C entry point using the embedded NodeMobile framework and launches `node main.js` from the bundled `nodejs-project/` directory.

NodeMobile supports a single runtime instance per app process and does not expose a supported stop/restart operation. Accordingly, `FoliaNodeMobileRuntimeDriver.stop()` intentionally does not claim to terminate the event loop.

## Build contents

- `project.yml`: XcodeGen app target, iOS 15+, original bundle identifier/version, background audio mode.
- `App/`: SwiftUI entry, WKWebView host, concrete NodeMobile driver, app Info.plist.
- `scripts/prepare-node-mobile-ios.sh`: fetches the official NodeMobile v18.20.4 iOS release and stages its device framework.
- `compat/ios-bridge/ios/`: the existing reconstructed playback/provider compatibility scaffolds.
- `public/`: populated by the sanitized build-379 payload at CI time; it is not fabricated or replaced with a demo page.

## Remaining limitations

- The original Capacitor and Cordova frameworks are present in the IPA, but this rebuilt target currently uses a WKWebView host and does not claim full Capacitor plugin parity.
- The app target needs the sanitized payload URL at build time.
- The original native app source and Xcode project remain unrecovered.
- An unsigned IPA is only a packaging artifact; installation requires re-signing with a valid identity/provisioning profile.
- Physical-device tests are still required for Node service readiness, QQ/Kugou login, media streaming, Apple Music, background audio, and playback recovery.
