import Foundation
import WebKit

/// Replacement WebKit provider bridge for Apple Music catalog/account actions.
/// It is intentionally separate from the native AVPlayer playback bridge.
public final class FoliaAppleMusicProviderBridge {
    private weak var webView: WKWebView?
    private let supportedActions: Set<String> = [
        "appleMusicOpen", "appleMusicClose", "appleMusicLogout",
        "appleMusicRequest", "appleMusicStatus"
    ]
    private var installed = false

    public init(webView: WKWebView) {
        self.webView = webView
    }

    /// Inject the source of compat/ios-bridge/apple-music-provider.js after
    /// the MusicKit script has been configured in the page.
    public func install(dispatcherSource: String, completion: @escaping (Error?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let webView else {
            completion(NSError(domain: "FoliaAppleMusicProviderBridge", code: 1))
            return
        }
        webView.evaluateJavaScript(dispatcherSource) { [weak self] _, error in
            if error == nil { self?.installed = true }
            completion(error)
        }
    }

    /// Implements FoliaBridgeRouter's provider delegate callback contract.
    /// The router independently validates the request and guards duplicate replies.
    public func handle(
        _ request: [String: Any],
        reply: @escaping ([String: Any]) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard installed,
              let webView,
              let action = request["action"] as? String,
              supportedActions.contains(action),
              JSONSerialization.isValidJSONObject(request) else {
            reply(["ok": false, "error": installed ? "unsupported-provider-action" : "provider-service-not-installed"])
            return
        }

        var replied = false
        func complete(_ payload: [String: Any]) {
            dispatchPrecondition(condition: .onQueue(.main))
            guard !replied else { return }
            replied = true
            guard let ok = payload["ok"] as? Bool else {
                reply(["ok": false, "error": "invalid-provider-reply"])
                return
            }
            if ok {
                guard payload["data"] != nil else {
                    reply(["ok": false, "error": "invalid-provider-reply"])
                    return
                }
            } else if !(payload["error"] is String) {
                reply(["ok": false, "error": "invalid-provider-reply"])
                return
            }
            reply(payload)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 40) {
            complete(["ok": false, "error": "provider-timeout"])
        }

        webView.callAsyncJavaScript(
            "guard typeof window.__foliaAppleMusicProviderDispatch === 'function' else { throw new Error('provider-dispatcher-not-ready'); }; return await window.__foliaAppleMusicProviderDispatch(request);",
            arguments: ["request": request],
            in: nil,
            contentWorld: .page
        ) { result in
            switch result {
            case .success(let value):
                guard let payload = value as? [String: Any] else {
                    complete(["ok": false, "error": "invalid-provider-reply"])
                    return
                }
                complete(payload)
            case .failure:
                complete(["ok": false, "error": "provider-request-failed"])
            }
        }
    }
}
