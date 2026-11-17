import Foundation
import WebKit

/// Strong owner that wires the separately authored native playback scaffolds.
/// The host application must retain this object for the lifetime of its WKWebView.
public final class FoliaNativePlaybackHost {
    public let engine: FoliaAVPlayerEngine
    public let router: FoliaBridgeRouter
    public let keeper: FoliaPlaybackKeeper
    public let recovery: FoliaWebContentRecoveryCoordinator
    public let snapshotStore: FoliaPlaybackSnapshotStore
    public let appleMusicPlaybackBridge: FoliaAppleMusicPlaybackBridge

    private weak var webView: WKWebView?

    public var onAudioSessionError: ((Error) -> Void)?
    public var onPersistenceError: ((Error) -> Void)?

    public init(
        webView: WKWebView,
        isTrustedFrame: @escaping (WKFrameInfo) -> Bool,
        isAllowedMediaURL: @escaping (URL) -> Bool = { url in
            guard let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  url.host?.isEmpty == false,
                  url.user == nil, url.password == nil else { return false }
            return true
        },
        snapshotStore: FoliaPlaybackSnapshotStore = FoliaPlaybackSnapshotStore(),
        onProviderRequest: (([String: Any], @escaping ([String: Any]) -> Void) -> Void)? = nil
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.webView = webView
        self.snapshotStore = snapshotStore
        self.appleMusicPlaybackBridge = FoliaAppleMusicPlaybackBridge(webView: webView)

        let engine = FoliaAVPlayerEngine(isAllowedMediaURL: isAllowedMediaURL)
        let router = FoliaBridgeRouter(
            delegate: engine,
            isTrustedFrame: isTrustedFrame,
            isAllowedMediaURL: isAllowedMediaURL
        )
        let keeper = FoliaPlaybackKeeper(transport: engine)
        let recovery = FoliaWebContentRecoveryCoordinator(
            engine: engine,
            store: snapshotStore
        )

        self.engine = engine
        self.router = router
        self.keeper = keeper
        self.recovery = recovery

        engine.attach(to: router)
        engine.onProviderRequest = onProviderRequest
        engine.onPlaybackStateChanged = { [weak keeper] in
            keeper?.refreshNowPlayingInfo()
        }
        keeper.onApplicationLifecycleChanged = { [weak self] event in
            guard let self else { return }
            switch event {
            case .didEnterBackground:
                do { try self.savePlaybackSnapshot() }
                catch { self.onPersistenceError?(error) }
            case .willEnterForeground:
                self.keeper.refreshNowPlayingInfo()
            }
        }
        keeper.onAudioSessionError = { [weak self] error in
            self?.onAudioSessionError?(error)
        }

        keeper.install()
        router.install(on: webView)
    }

    /// Install the separate MusicKit playback dispatcher JavaScript source.
    /// Supply the UTF-8 source from compat/ios-bridge/apple-music-playback.js.
    public func installAppleMusicPlaybackDispatcher(source: String, completion: @escaping (Error?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        appleMusicPlaybackBridge.install(dispatcherSource: source, completion: completion)
    }

    /// Send a MusicKit operation through the explicit replacement bridge envelope.
    public func sendAppleMusicPlayback(
        operation: String, params: [String: Any] = [:],
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        appleMusicPlaybackBridge.send(operation: operation, params: params, completion: completion)
    }

    /// Activate the playback audio session when the host begins playback ownership.
    public func activateAudioSession() throws {
        dispatchPrecondition(condition: .onQueue(.main))
        try keeper.activatePlaybackAudioSession()
    }

    /// Call from the app's existing WKNavigationDelegate method.
    /// This class intentionally does not replace the host's navigation delegate.
    @discardableResult
    public func handleWebContentProcessTermination() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let webView else { return false }
        return recovery.handleWebContentProcessTermination(of: webView)
    }

    /// Call only after the reloaded page has initialized its bridge and exposes
    /// the new session/generation. The host decides whether resuming is appropriate.
    @discardableResult
    public func restoreAfterWebContentReady(
        session: String,
        generation: Int,
        resumePlayback: Bool
    ) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return recovery.restoreAfterWebContentReady(
            session: session,
            generation: generation,
            resumePlayback: resumePlayback
        )
    }

    public func savePlaybackSnapshot() throws {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let snapshot = engine.makePlaybackPersistenceSnapshot() else { return }
        try snapshotStore.save(snapshot)
    }

    public func setProviderRequestHandler(
        _ handler: (([String: Any], @escaping ([String: Any]) -> Void) -> Void)?
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        engine.onProviderRequest = handler
    }

    /// Call from the host's teardown path on the main queue before releasing the WebView.
    public func shutdown() {
        dispatchPrecondition(condition: .onQueue(.main))
        engine.onPlaybackStateChanged = nil
        engine.onProviderRequest = nil
        keeper.onApplicationLifecycleChanged = nil
        keeper.onAudioSessionError = nil
        router.uninstall()
        keeper.uninstall()
    }
}
