# WebContent termination and playback recovery scaffold

> This is a new host integration helper based on the lifecycle symbols and persisted-property names visible in build 379. It is not the recovered `FoliaBackGuard` implementation.

## Components

- `FoliaPlaybackSnapshotStore.swift`: versioned, size-bounded playback snapshot persistence in the app's Application Support directory.
- `FoliaWebContentRecoveryCoordinator.swift`: adapter for the host's `WKNavigationDelegate.webViewWebContentProcessDidTerminate(_:)` callback.
- `FoliaAVPlayerEngine.swift`: exports the current native item, position, desired intent, metadata, and playable queue context, then restores through a fresh Web runtime session/generation.

## Default persistence policy

The store defaults to refusing URLs with query strings, fragments, usernames, or passwords. This avoids writing common signed-media URLs and access tokens to disk. Queue URLs are subjected to the same policy. If media URLs contain credentials in their path, the host must provide a stricter allowlist or disable persistence for those URLs. The store uses atomic writes, a 512 KiB cap, schema version 1, a 24-hour default age limit, and iOS file protection until first unlock after reboot.

## Suggested host wiring

```swift
let snapshotStore = FoliaPlaybackSnapshotStore()
let recovery = FoliaWebContentRecoveryCoordinator(
    engine: engine,
    store: snapshotStore
)

// In the app's existing WKNavigationDelegate:
func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    _ = recovery.handleWebContentProcessTermination(of: webView)
}

// After the reloaded page has re-established its bridge and the host has
// obtained the new web session and generation:
let restored = recovery.restoreAfterWebContentReady(
    session: currentWebSession,
    generation: currentGeneration,
    resumePlayback: hostPolicyAllowsResume
)
```

The app must retain `recovery`, `store`, `engine`, and `router` strongly. The helper does not install a second navigation delegate.

## Background lifecycle persistence

Use `FoliaPlaybackKeeper.onApplicationLifecycleChanged` to save a snapshot when entering background, and to coordinate foreground checks. The callback is delivered on the main queue. Do not automatically resume solely because the app entered foreground; preserve explicit user pause and let the host apply a documented resume policy.

## Limits

- This snapshot stores only track metadata, raw playable URLs, position, queue and desired-play intent. It does not store provider cookies, MusicKit tokens, Feiniu credentials, or NodeMobile auth state.
- Signed URLs, provider-only queue entries, local sandbox files, and media URLs not accepted by the policy are not persisted by default. A host may resolve the logical track again after restore, but that provider-resolution integration is not included here.
- The coordinator reloads the existing WebView after process termination. It does not recreate the WKWebView, re-inject app-specific scripts, or recover the original Folia shadow-webview handoff.
- Restoring must use the newly created JS session and generation, not the previous page's identifiers.
- The `resumePlayback` argument is explicit. A stale snapshot cannot override a later user pause unless the host incorrectly passes `true`.
- The helper has not been built with Xcode or verified under actual WebContent process termination.


## Composition root

`FoliaNativePlaybackHost.swift` owns this coordinator and the snapshot store. The host still must call `handleWebContentProcessTermination()` from its existing WKNavigationDelegate callback, wait for the reloaded page to configure MusicKit and publish a new session/generation, then call `restoreAfterWebContentReadyAndReinstallServices(...)` when Apple Music scripts were installed. The old page session is never reused.
