import Foundation
import WebKit

/// Strong owner that wires the separately authored native playback scaffolds.
/// The host application must retain this object for the lifetime of its WKWebView.
@MainActor
public final class FoliaNativePlaybackHost {
    public let engine: FoliaAVPlayerEngine
    public let router: FoliaBridgeRouter
    public let keeper: FoliaPlaybackKeeper
    public let recovery: FoliaWebContentRecoveryCoordinator
    public let snapshotStore: FoliaPlaybackSnapshotStore
    public let appleMusicPlaybackBridge: FoliaAppleMusicPlaybackBridge
    public let appleMusicProviderBridge: FoliaAppleMusicProviderBridge
    public let nodeRuntime: FoliaNodeRuntimeCoordinator?

    private weak var webView: WKWebView?
    private var appleMusicPlaybackSource: String?
    private var appleMusicProviderSource: String?

    public var onAudioSessionError: ((Error) -> Void)?
    public var onPersistenceError: ((Error) -> Void)?
    private var externalProviderRequestHandler: (([String: Any], @escaping ([String: Any]) -> Void) -> Void)?

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
        onProviderRequest: (([String: Any], @escaping ([String: Any]) -> Void) -> Void)? = nil,
        nodeRuntimeDriver: FoliaNodeRuntimeDriver? = nil
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.webView = webView
        self.snapshotStore = snapshotStore
        self.appleMusicPlaybackBridge = FoliaAppleMusicPlaybackBridge(webView: webView)
        self.appleMusicProviderBridge = FoliaAppleMusicProviderBridge(webView: webView)
        self.externalProviderRequestHandler = onProviderRequest
        self.nodeRuntime = nodeRuntimeDriver.map { FoliaNodeRuntimeCoordinator(driver: $0) }

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
        engine.onProviderRequest = { [weak self] request, reply in
            guard let self else {
                reply(["ok": false, "error": "provider-host-unavailable"])
                return
            }
            let action = request["action"] as? String ?? ""
            if action.hasPrefix("appleMusic") {
                self.appleMusicProviderBridge.handle(request, reply: reply)
            } else if let handler = self.externalProviderRequestHandler {
                handler(request, reply)
            } else {
                reply(["ok": false, "error": "provider-service-not-installed"])
            }
        }
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
        appleMusicPlaybackSource = source
        appleMusicPlaybackBridge.install(dispatcherSource: source, completion: completion)
    }

    /// Install the Apple Music catalog/account provider JavaScript source.
    /// Supply UTF-8 source from compat/ios-bridge/apple-music-provider.js.
    public func installAppleMusicProviderDispatcher(source: String, completion: @escaping (Error?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        appleMusicProviderSource = source
        appleMusicProviderBridge.install(dispatcherSource: source, completion: completion)
    }

    /// Send a MusicKit operation through the explicit replacement bridge envelope.
    public func sendAppleMusicPlayback(
        operation: String, params: [String: Any] = [:],
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        appleMusicPlaybackBridge.send(operation: operation, params: params, completion: completion)
    }

    /// Install both Apple Music JavaScript services after the page has configured MusicKit.
    /// The source strings are the UTF-8 contents of apple-music-playback.js and
    /// apple-music-provider.js respectively.
    public func installAppleMusicServices(
        playbackSource: String,
        providerSource: String,
        completion: @escaping (Error?) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        appleMusicPlaybackSource = playbackSource
        appleMusicProviderSource = providerSource
        appleMusicPlaybackBridge.install(dispatcherSource: playbackSource) { [weak self] playbackError in
            guard let self else {
                completion(NSError(domain: "FoliaNativePlaybackHost", code: 1))
                return
            }
            guard playbackError == nil else {
                completion(playbackError)
                return
            }
            self.appleMusicProviderBridge.install(dispatcherSource: providerSource, completion: completion)
        }
    }

    /// Starts the extracted Node services through the host's NodeMobile driver.
    /// The driver must be implemented against the actual framework header/ABI.
    public func startNodeRuntime() async throws {
        guard let nodeRuntime else {
            throw NSError(
                domain: "FoliaNativePlaybackHost",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "nodemobile-driver-not-installed"]
            )
        }
        try await nodeRuntime.start()
    }

    public func stopNodeRuntime() {
        nodeRuntime?.stop()
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
        appleMusicProviderBridge.invalidate()
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

    /// Re-install MusicKit globals after the WebView reloads, then restore playback
    /// through the new page session/generation.
    public func restoreAfterWebContentReadyAndReinstallServices(
        session: String,
        generation: Int,
        resumePlayback: Bool,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let playbackSource = appleMusicPlaybackSource,
              let providerSource = appleMusicProviderSource else {
            completion(restoreAfterWebContentReady(session: session, generation: generation, resumePlayback: resumePlayback), nil)
            return
        }
        installAppleMusicServices(playbackSource: playbackSource, providerSource: providerSource) { [weak self] error in
            guard let self else {
                completion(false, NSError(domain: "FoliaNativePlaybackHost", code: 2))
                return
            }
            guard error == nil else { completion(false, error); return }
            let restored = self.restoreAfterWebContentReady(session: session, generation: generation, resumePlayback: resumePlayback)
            completion(restored, nil)
        }
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
        externalProviderRequestHandler = handler
    }

    /// Call from the host's teardown path on the main queue before releasing the WebView.
    public func shutdown() {
        dispatchPrecondition(condition: .onQueue(.main))
        engine.onPlaybackStateChanged = nil
        engine.onProviderRequest = nil
        externalProviderRequestHandler = nil
        appleMusicPlaybackSource = nil
        appleMusicProviderSource = nil
        keeper.onApplicationLifecycleChanged = nil
        keeper.onAudioSessionError = nil
        router.uninstall()
        nodeRuntime?.stop()
        engine.shutdownTransport()
        try? keeper.deactivatePlaybackAudioSession()
        keeper.uninstall()
    }
}
