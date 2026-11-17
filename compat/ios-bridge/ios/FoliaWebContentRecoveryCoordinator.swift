import Foundation
import WebKit

/// Host-side helper for the WKNavigationDelegate termination callback.
/// It deliberately does not replace the host's WKNavigationDelegate.
public final class FoliaWebContentRecoveryCoordinator {
    private weak var engine: FoliaAVPlayerEngine?
    private let store: FoliaPlaybackSnapshotStore
    private let maximumSnapshotAge: TimeInterval

    public init(
        engine: FoliaAVPlayerEngine,
        store: FoliaPlaybackSnapshotStore = FoliaPlaybackSnapshotStore(),
        maximumSnapshotAge: TimeInterval = 24 * 60 * 60
    ) {
        self.engine = engine
        self.store = store
        self.maximumSnapshotAge = max(60, maximumSnapshotAge)
    }

    /// Call from the host's webViewWebContentProcessDidTerminate(_:) delegate method.
    /// Saves native playback state before asking WebKit to reload the current page.
    @discardableResult
    public func handleWebContentProcessTermination(of webView: WKWebView) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let snapshot = engine?.makePlaybackPersistenceSnapshot() else {
            webView.reload()
            return false
        }
        do {
            try store.save(snapshot)
            webView.reload()
            return true
        } catch {
            webView.reload()
            return false
        }
    }

    /// Call only after the reloaded page has initialized its bridge and supplied
    /// its new session/generation. Resume remains an explicit host decision.
    @discardableResult
    public func restoreAfterWebContentReady(
        session: String,
        generation: Int,
        resumePlayback: Bool
    ) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let engine else { return false }
        do {
            guard let snapshot = try store.load(maxAge: maximumSnapshotAge) else { return false }
            let restored = engine.restorePlaybackPersistenceSnapshot(
                snapshot,
                session: session,
                generation: generation,
                resumePlayback: resumePlayback
            )
            if restored { try store.clear() }
            return restored
        } catch {
            return false
        }
    }

    public func clearSnapshot() throws {
        try store.clear()
    }
}
