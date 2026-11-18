import Foundation
import WebKit

/// New, explicit host bridge for the extracted MusicKit playback dispatcher.
/// The original binary's outer Swift/JavaScript envelope was not recoverable,
/// so this class defines and documents a replacement envelope rather than
/// pretending it is byte-for-byte compatible.
public final class FoliaAppleMusicPlaybackBridge {
    private weak var webView: WKWebView?
    private let supportedOperations: Set<String> = [
        "play", "pause", "stop", "resume", "seek", "volume", "repeat",
        "prepareNext", "next", "previous", "toggle", "status"
    ]

    public init(webView: WKWebView) {
        self.webView = webView
    }

    /// Inject the source of compat/ios-bridge/apple-music-playback.js once the
    /// WKWebView is created. The script installs window.__foliaAppleMusicPlaybackDispatch.
    public func install(dispatcherSource: String, completion: @escaping (Error?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let webView else {
            completion(NSError(domain: "FoliaAppleMusicPlaybackBridge", code: 1))
            return
        }
        webView.evaluateJavaScript(dispatcherSource) { _, error in completion(error) }
    }

    public func send(
        operation: String,
        params: [String: Any] = [:],
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard supportedOperations.contains(operation),
              JSONSerialization.isValidJSONObject(params),
              let webView else {
            completion(.failure(NSError(
                domain: "FoliaAppleMusicPlaybackBridge",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "invalid-operation-or-parameters"]
            )))
            return
        }

        let requestID = UUID().uuidString
        webView.callAsyncJavaScript(
            "return await window.__foliaAppleMusicPlaybackDispatch({ id: id, operation: operation, params: params });",
            arguments: ["id": requestID, "operation": operation, "params": params],
            in: nil,
            in: .page
        ) { result in
            switch result {
            case .success(let value):
                guard let payload = value as? [String: Any] else {
                    completion(.failure(NSError(
                        domain: "FoliaAppleMusicPlaybackBridge",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "invalid-dispatcher-reply"]
                    )))
                    return
                }
                completion(.success(payload))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
