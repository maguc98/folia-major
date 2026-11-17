import Foundation
import WebKit

/// Delegate implemented by a host app that owns the real AVPlayer/MusicKit/Feiniu services.
/// This router only validates and forwards bridge messages; it does not implement playback or login.
public protocol FoliaBridgeRouterDelegate: AnyObject {
    func foliaBridgeRouter(_ router: FoliaBridgeRouter, didReceivePlayerCommand command: [String: Any])
    func foliaBridgeRouter(
        _ router: FoliaBridgeRouter,
        didReceiveProviderRequest request: [String: Any],
        reply: @escaping ([String: Any]) -> Void
    )
}

private final class WeakFoliaScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: FoliaBridgeRouter?

    init(target: FoliaBridgeRouter) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.receive(message)
    }
}

/// Build-379-compatible WKWebView message router.
///
/// The host must provide an explicit frame validator and implement the delegate.
/// Native-side validation here is mandatory even if the web-side JS adapter is used.
public final class FoliaBridgeRouter: NSObject {
    public static let playerHandlerName = "foliaPlayer"
    public static let providerHandlerName = "foliaProviderAuth"

    private weak var webView: WKWebView?
    private weak var delegate: FoliaBridgeRouterDelegate?
    private let isTrustedFrame: (WKFrameInfo) -> Bool
    private let maximumMessageBytes: Int
    private var proxies: [String: WeakFoliaScriptMessageHandler] = [:]

    public init(
        delegate: FoliaBridgeRouterDelegate,
        maximumMessageBytes: Int = 256 * 1024,
        isTrustedFrame: @escaping (WKFrameInfo) -> Bool
    ) {
        self.delegate = delegate
        self.maximumMessageBytes = max(1, maximumMessageBytes)
        self.isTrustedFrame = isTrustedFrame
        super.init()
    }

    public func install(on webView: WKWebView) {
        uninstall()
        self.webView = webView
        let controller = webView.configuration.userContentController
        for name in [Self.playerHandlerName, Self.providerHandlerName] {
            let proxy = WeakFoliaScriptMessageHandler(target: self)
            proxies[name] = proxy
            controller.add(proxy, name: name)
        }
    }

    public func uninstall() {
        guard let webView else {
            proxies.removeAll()
            return
        }
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: Self.playerHandlerName)
        controller.removeScriptMessageHandler(forName: Self.providerHandlerName)
        proxies.removeAll()
        self.webView = nil
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, isTrustedFrame(message.frameInfo) else { return }
        guard let body = message.body as? [String: Any],
              JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body),
              data.count <= maximumMessageBytes else { return }

        switch message.name {
        case Self.playerHandlerName:
            guard Self.isValidPlayerCommand(body) else { return }
            delegate?.foliaBridgeRouter(self, didReceivePlayerCommand: body)
        case Self.providerHandlerName:
            guard Self.isValidProviderRequest(body) else { return }
            forwardProviderRequest(body)
        default:
            return
        }
    }

    /// Send an event to the shipped web callback window.__foliaNativePlayerEvent.
    public func emitPlayerEvent(_ event: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(event),
              let json = Self.javascriptLiteral(event) else { return }
        evaluate("window.__foliaNativePlayerEvent && window.__foliaNativePlayerEvent(\(json));")
    }

    private func forwardProviderRequest(_ request: [String: Any]) {
        guard let requestID = request["id"] as? String, !requestID.isEmpty else { return }
        let lock = NSLock()
        var hasReplied = false
        delegate?.foliaBridgeRouter(self, didReceiveProviderRequest: request) { [weak self] payload in
            lock.lock()
            let shouldReply = !hasReplied
            hasReplied = true
            lock.unlock()
            guard shouldReply else { return }

            guard let ok = payload["ok"] as? Bool else { return }
            if ok && !payload.keys.contains("data") { return }
            if !ok && !(payload["error"] is String) { return }
            let envelope: [String: Any] = ["id": requestID, "payload": payload]
            guard let json = Self.javascriptLiteral(envelope) else { return }
            self?.evaluate("window.__foliaProviderAuthReply && window.__foliaProviderAuthReply(\(json));")
        }
    }

    private func evaluate(_ script: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private static func javascriptLiteral(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]),
              var value = String(data: data, encoding: .utf8) else { return nil }
        value = value.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        value = value.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return value
    }

    private static func isValidPlayerCommand(_ body: [String: Any]) -> Bool {
        guard let command = body["cmd"] as? String else { return false }
        if command == "startup_prompts_seen" { return true }
        let commands: Set<String> = ["load", "play", "pause", "seek", "volume", "muted", "status", "upcoming"]
        guard commands.contains(command),
              let session = body["session"] as? String, !session.isEmpty, session.count <= 256,
              let generation = body["generation"] as? NSNumber, generation.int64Value >= 0 else { return false }

        switch command {
        case "load":
            guard let rawURL = body["url"] as? String,
                  let url = URL(string: rawURL),
                  ["http", "https", "file"].contains(url.scheme?.lowercased() ?? ""),
                  url.user == nil, url.password == nil,
                  let position = body["position"] as? NSNumber, position.doubleValue.isFinite, position.doubleValue >= 0,
                  body["autoplay"] is Bool else { return false }
        case "seek":
            guard let position = body["position"] as? NSNumber, position.doubleValue.isFinite, position.doubleValue >= 0 else { return false }
        case "volume":
            guard let volume = body["volume"] as? NSNumber, volume.doubleValue.isFinite, (0...1).contains(volume.doubleValue) else { return false }
        case "muted":
            guard body["muted"] is Bool else { return false }
        case "pause":
            if let value = body["userIntent"], !(value is Bool) { return false }
            if let value = body["releaseIntent"], !(value is Bool) { return false }
        case "upcoming":
            guard let key = body["currentTrackKey"] as? String, key.count <= 512,
                  body["track"] is [String: Any] || body["track"] is NSNull,
                  let upcoming = body["upcoming"] as? [Any], upcoming.count <= 500,
                  let previous = body["previous"] as? [Any], previous.count <= 500 else { return false }
        default:
            break
        }
        return true
    }

    private static func isValidProviderRequest(_ body: [String: Any]) -> Bool {
        guard let requestID = body["id"] as? String, !requestID.isEmpty, requestID.count <= 256,
              let action = body["action"] as? String else { return false }
        let actions: Set<String> = [
            "appleMusicOpen", "appleMusicClose", "appleMusicLogout", "appleMusicRequest",
            "appleMusicStatus", "fnmusicLogin", "fnmusicLogout", "fnmusicRequest", "fnmusicStatus"
        ]
        guard actions.contains(action) else { return false }

        if action == "appleMusicRequest" {
            let operations: Set<String> = [
                "search", "catalogSong", "catalogAlbum", "catalogAlbumTracks", "catalogArtist",
                "catalogArtistSongs", "catalogArtistAlbums", "personalFm", "playlists",
                "playlistTracks", "playlistTrackCount", "librarySongs", "libraryAlbums",
                "libraryAlbumTracks", "lyrics", "likeSong", "addPlaylistTracks"
            ]
            guard let operation = body["operation"] as? String, operations.contains(operation),
                  body["params"] is [String: Any] else { return false }
        }

        if action == "fnmusicRequest" {
            guard let path = body["path"] as? String, path.count <= 1024,
                  path.hasPrefix("/music/api/v1/"), !path.hasPrefix("//"),
                  !path.contains("\\"), !path.contains("?"), !path.contains("#"),
                  !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
                  let method = body["method"] as? String,
                  ["GET", "POST"].contains(method.uppercased()) else { return false }
        }
        return true
    }
}
