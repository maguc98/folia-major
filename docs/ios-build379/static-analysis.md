# Build 379 — Initial static analysis notes

## Verified container architecture

The app is a hybrid iOS package:
- Native executable: `Payload/App.app/App`
- Embedded `Capacitor.framework`
- Embedded `Cordova.framework`
- Embedded `NodeMobile.framework`
- Web app entry: `public/index.html`
- Front-end entry bundle: `public/assets/main-D3qKLyAO.js`
- Runtime configuration stub: `public/runtime-config.js`

The main executable links Capacitor, Cordova, NodeMobile, and Apple's MediaPlayer framework. Binary strings expose the following native Swift class names:
- `FoliaMemoryProbe`
- `FoliaBackGuard`
- `FoliaPlaybackKeeper`
- `FoliaNativePlayer`
- `FoliaMusicProviderBridge`

These names are evidence of native components, not a substitute for source-level implementation. The executable is stripped of ordinary exported symbols in the inspection environment; deeper work will require disassembly/decompilation and runtime testing.

## Front-end and iOS adaptation

- `index.html` loads `runtime-config.js`, the hashed main JS bundle, `ios-fix/mobile-fix.css`, and `ios-fix/scale.js`.
- `runtime-config.js` is an empty runtime-config placeholder; it does not reveal actual deployment secrets.
- `ios-fix/scale.js` includes explicit iPad detection, persisted scale settings, viewport rewriting, orientation handling, and resize nudges.
- The scale script's header comment says this adaptation layer is injected by a local preview service / NAS gateway rather than changing upstream source. Preserve this provenance note when modifying it; verify whether the file is part of the author's intended release pipeline.
- The inspected script defines iPad scale defaults and bounds (default 0.9, min 0.45, max 0.9); these are code constants, not a statement about every device's observed runtime scale.

## Renderer inventory

The asset directory contains separately named renderer bundles including Tempera, Partita, Sonnet, Lumiere, Hanabi, Machi, Nebbia, Diorama, Monet, Cappella, Cadenza, Pendolo, and others. This confirms bundled renderer modules exist; their behavior and feature completeness require per-module analysis.

## Security finding

The package includes `public/nodejs-project/.auth-state/qq-device.json`. Only its filename, size, and top-level key names were inspected; its values were not printed or copied. It is authentication/device state and must remain excluded from any public source import.

## Buildability conclusion

This IPA is useful as a runnable binary reference and contains substantial editable web assets, but it is not a complete Xcode project. The presence of Capacitor/Cordova/NodeMobile frameworks does not itself provide the missing project settings, native source, plugin source, or signing/build pipeline. A reproducible native build cannot yet be claimed.

## Next analysis sequence

1. Map native plugin registration and JavaScript bridge entry points.
2. Trace startup from App/SceneDelegate to WKWebView and local asset loading.
3. Map NodeMobile bootstrap, nodejs-project entry point, and runtime module dependencies.
4. Inspect renderer modules individually, starting with Tempera and Partita.
5. Establish a clean, sanitized source snapshot and a separate native project reconstruction plan.
