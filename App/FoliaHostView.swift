import SwiftUI
import UIKit
import WebKit

struct FoliaHostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> FoliaHostViewController {
        FoliaHostViewController()
    }

    func updateUIViewController(_ controller: FoliaHostViewController, context: Context) {}
}

@MainActor
final class FoliaHostViewController: UIViewController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var playbackHost: FoliaNativePlaybackHost?
    private var didLoadInitialPage = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 9.0 / 255.0, green: 9.0 / 255.0, blue: 11.0 / 255.0, alpha: 1)

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        webView.scrollView.backgroundColor = view.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.webView = webView

        playbackHost = FoliaNativePlaybackHost(
            webView: webView,
            isTrustedFrame: { frame in
                frame.isMainFrame && frame.securityOrigin.protocol == "file"
            },
            nodeRuntimeDriver: FoliaNodeMobileRuntimeDriver()
        )

        // Do not make the first screen depend on NodeMobile's async readiness.
        // NodeMobile can keep its event loop alive indefinitely; awaiting its
        // service bootstrap here previously prevented WKWebView from navigating,
        // leaving the user on the native launch/logo screen with no diagnostics.
        // Start the runtime independently, then load the bundled UI immediately.
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.playbackHost?.startNodeRuntime()
                NSLog("[Folia] NodeMobile runtime startup completed")
            } catch {
                NSLog("[Folia] NodeMobile startup failed: %@", String(describing: error))
            }
        }

        loadBundledWebAppIfPresent()
    }

    private func loadBundledWebAppIfPresent() {
        guard !didLoadInitialPage else { return }
        didLoadInitialPage = true
        guard let publicDirectory = Bundle.main.resourceURL?.appendingPathComponent("public", isDirectory: true),
              let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "public") else {
            NSLog("[Folia] Bundled web payload missing: resourceURL=%@", String(describing: Bundle.main.resourceURL))
            showMissingPayloadMessage()
            return
        }
        NSLog("[Folia] Loading bundled web app: %@", indexURL.path)
        webView.loadFileURL(indexURL, allowingReadAccessTo: publicDirectory)
    }

    private func showMissingPayloadMessage() {
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{margin:0;background:#09090b;color:#fff;font:16px -apple-system;padding:32px}
        h2{font-size:22px}p{color:#aaa;line-height:1.6}</style></head>
        <body><h2>Folia 资源尚未打包</h2><p>原生容器已启动，但当前构建没有包含 public/index.html。请检查 IPA 内的 public 资源目录。</p></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        NSLog("[Folia] WebView navigation started: %@", webView.url?.absoluteString ?? "(pending URL)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("[Folia] WebView navigation finished: %@", webView.url?.absoluteString ?? "(unknown URL)")
        guard let playbackHost else { return }
        let playbackURL = Bundle.main.url(forResource: "apple-music-playback", withExtension: "js")
        let providerURL = Bundle.main.url(forResource: "apple-music-provider", withExtension: "js")
        guard let playbackURL, let providerURL,
              let playbackSource = try? String(contentsOf: playbackURL, encoding: .utf8),
              let providerSource = try? String(contentsOf: providerURL, encoding: .utf8) else {
            NSLog("[Folia] Apple Music bridge resources are missing")
            return
        }
        playbackHost.installAppleMusicServices(
            playbackSource: playbackSource,
            providerSource: providerSource
        ) { error in
            if let error {
                NSLog("[Folia] MusicKit bridge installation failed: %@", String(describing: error))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[Folia] WebView navigation failed: %@", String(describing: error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[Folia] WebView provisional navigation failed: %@", String(describing: error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("[Folia] WebView content process terminated")
        guard playbackHost?.handleWebContentProcessTermination() == true else {
            webView.reload()
            return
        }
        webView.reload()
    }

    deinit {
        // UIKit view controllers are released on the main thread. The host must remove
        // WKScriptMessageHandlers and MediaPlayer/NotificationCenter registrations there.
        MainActor.assumeIsolated {
            playbackHost?.shutdown()
        }
    }
}
