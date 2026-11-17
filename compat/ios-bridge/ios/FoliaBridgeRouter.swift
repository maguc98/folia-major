import Foundation
import WebKit
import CoreFoundation

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
    private let isAllowedMediaURL: (URL) -> Bool
    private var proxies: [String: WeakFoliaScriptMessageHandler] = [:]

    public init(
        delegate: FoliaBridgeRouterDelegate,
        maximumMessageBytes: Int = 256 * 1024,
        isTrustedFrame: @escaping (WKFrameInfo) -> Bool,
        isAllowedMediaURL: @escaping (URL) -> Bool = { url in
            guard let scheme = url.scheme?.lowercased() else { return false }
            if scheme == "https" || scheme == "http" {
                return url.host?.isEmpty == false && url.user == nil && url.password == nil
            }
            // Local media is denied unless the host explicitly supplies a sandbox-aware policy.
            return false
        }
    ) {
        self.delegate = delegate
        self.maximumMessageBytes = max(1, maximumMessageBytes)
        self.isTrustedFrame = isTrustedFrame
        self.isAllowedMediaURL = isAllowedMediaURL
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
            guard Self.isValidPlayerCommand(body, isAllowedMediaURL: isAllowedMediaURL) else { return }
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

            guard Self.isBoolean(payload["ok"]), let ok = payload["ok"] as? Bool else { return }
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

    private static func isBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func finiteNumber(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number
    }

    private static func isValidPlayerCommand(
        _ body: [String: Any],
        isAllowedMediaURL: (URL) -> Bool
    ) -> Bool {
        guard let command = body["cmd"] as? String else { return false }
        if command == "startup_prompts_seen" { return true }

        guard let session = body["session"] as? String,
              !session.isEmpty, session.count <= 256,
              let generation = finiteNumber(body["generation"]),
              generation.doubleValue >= 0,
              generation.doubleValue.rounded(.towardZero) == generation.doubleValue,
              generation.doubleValue <= 9_007_199_254_740_991 else { return false }

        let commands: Set<String> = ["load", "play", "pause", "seek", "volume", "muted", "status", "upcoming"]
        guard commands.contains(command) else { return false }

        switch command {
        case "load":
            guard let rawURL = body["url"] as? String, rawURL.count <= 8192,
                  let url = URL(string: rawURL), isAllowedMediaURL(url),
                  let position = finiteNumber(body["position"]), position.doubleValue >= 0,
                  isBoolean(body["autoplay"]) else { return false }
            if let track = body["track"], !(track is [String: Any]) && !(track is NSNull) { return false }
            if let rawUpcoming = body["upcoming"] {
                guard let upcoming = rawUpcoming as? [Any], upcoming.count <= 500 else { return false }
            }
            if let rawPrevious = body["previous"] {
                guard let previous = rawPrevious as? [Any], previous.count <= 500 else { return false }
            }

        case "seek":
            guard let position = finiteNumber(body["position"]), position.doubleValue >= 0 else { return false }

        case "volume":
            guard let volume = finiteNumber(body["volume"]),
                  (0...1).contains(volume.doubleValue) else { return false }

        case "muted":
            guard isBoolean(body["muted"]) else { return false }

        case "pause":
            if let value = body["userIntent"], !isBoolean(value) { return false }
            if let value = body["releaseIntent"], !isBoolean(value) { return false }

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
            if let params = body["params"], !(params is [String: Any]) { return false }
            if let requestBody = body["body"],
               !(requestBody is [String: Any]) && !(requestBody is [Any]) { return false }
        }
        return true
    }
}
