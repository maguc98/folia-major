# Folia iOS 3.0.6 Build 379 — Sanitized Payload Analysis

## Input integrity
- Archive: `Folia-iOS-3.0.6-build379-public-sanitized-v2.zip`
- Size: 41,823,396 bytes
- SHA-256: `f8e08042914a01f63f8aabbadd9f61cca32dd92fd45cfe194495f1e40acbab32`
- Archive path traversal checks: passed
- Files: 8,421
- Uncompressed bytes: 103,639,746

## Inventory
- JavaScript files: 4,939
- CSS files: 13
- package.json files: 475
- Web entry: `public/index.html`
- Main frontend entry: `assets/main-D3qKLyAO.js`
- Runtime config: `runtime-config.js`
- iOS adaptation: `ios-fix/mobile-fix.css`, `ios-fix/scale.js`

## Renderer modules detected
- VisualizerPartita-7QxuAJiJ.js
- VisualizerSonnet-D1_NnFeq.js
- VisualizerTempera-DFp2mVg4.js
- VisualizerLumiere-USapruAR.js
- Additional visualizers: Cadenza, Cappella, Claddagh, Diorama, Fume, Hanabi, Machi, Monet, Nebbia, Pendolo, Shell, Still, Tilt
- Renderer infrastructure: visualizerModes, visualizerRender, visualizerSeedHash, iosVisualizerPerformance
- Pixi runtime factories: createLumierePixiRuntime, createSonnetPixiRuntime, createTemperaPixiRuntime

## Security findings
- The v2 archive path scan found no .auth-state directory, provisioning profile, app signature directory, private key, certificate, device-ID dataset, or backup snapshots.
- The earlier v1 archive contained a bundled EC private key/certificate set, a device-ID data file, and backup snapshots. These were excluded from v2.
- This is a path-based hygiene check, not a complete semantic secret scan. Review source/configuration and runtime behavior before public release.

## Technical findings
- `runtime-config.js` contains the `__FOLIA_RUNTIME_CONFIG__` placeholder. Determine where production configuration is injected before attempting to run the web payload independently.
- Comments in `ios-fix/scale.js` indicate that the adaptation may be injected by a local preview service/NAS gateway. Confirm provenance before attributing it to the upstream iOS author.
- This payload is a web/runtime resource snapshot. It does not include the full editable Xcode project or original Swift source. A reproducible signed IPA build is not established.

## Next work
1. Map imports and exports in the hashed frontend bundles and identify app startup, routing, renderer registry, and state stores.
2. Inspect the native bridge contract between the web app and Capacitor/Cordova/NodeMobile.
3. Reconstruct a clean buildable wrapper only after the required native project and build configuration are available.
4. Keep secrets, user sessions, signing assets, and generated runtime state out of the repository.
