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
        view.backgroundColor = UIColor(red: 9 / 255, green: 9 / 255, blue: 11 / 255, alpha: 1)

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

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.playbackHost?.startNodeRuntime()
            } catch {
                // Keep the UI available for diagnostics even if a local service fails.
                NSLog("[Folia] NodeMobile startup failed: %@", String(describing: error))
            }
            self.loadBundledWebAppIfPresent()
        }
    }

    private func loadBundledWebAppIfPresent() {
        guard !didLoadInitialPage else { return }
        didLoadInitialPage = true
        guard let publicDirectory = Bundle.main.resourceURL?.appendingPathComponent("public", isDirectory: true),
              let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "public") else {
            showMissingPayloadMessage()
            return
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: publicDirectory)
    }

    private func showMissingPayloadMessage() {
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{margin:0;background:#09090b;color:#fff;font:16px -apple-system;padding:32px}
        h2{font-size:22px}p{color:#aaa;line-height:1.6}</style></head>
        <body><h2>Folia 资源尚未打包</h2><p>原生容器已启动，但当前构建没有包含 public/index.html。请使用 build-379 清理资源包重新构建。</p></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let playbackHost else { return }
        let playbackURL = Bundle.main.url(forResource: "apple-music-playback", withExtension: "js")
        let providerURL = Bundle.main.url(forResource: "apple-music-provider", withExtension: "js")
        guard let playbackURL, let providerURL,
              let playbackSource = try? String(contentsOf: playbackURL, encoding: .utf8),
              let providerSource = try? String(contentsOf: providerURL, encoding: .utf8) else {
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

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard playbackHost?.handleWebContentProcessTermination() == true else {
            webView.reload()
            return
        }
        webView.reload()
    }

    deinit {
        // The playback host owns observers and message handlers tied to this WebView.
        // UIKit releases this controller on the main actor.
        playbackHost?.shutdown()
    }
}
