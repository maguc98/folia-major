import Foundation

/// Adapter implemented by the actual NodeMobile framework integration in the app target.
/// The original NodeMobile launcher ABI/header was not present in the supplied IPA, so
/// this protocol deliberately does not guess a C function signature.
@MainActor
public protocol FoliaNodeRuntimeDriver: AnyObject {
    func start(projectDirectoryName: String, environment: [String: String]) throws
    func stop()
}

public enum FoliaNodeRuntimeState: Equatable {
    case stopped
    case starting
    case ready
    case failed(String)
}

/// Starts the extracted Node 18 service entry point through an injected NodeMobile driver,
/// then checks the three loopback listeners described by the supplied main.js.
@MainActor
public final class FoliaNodeRuntimeCoordinator {
    public struct Configuration {
        public var projectDirectoryName: String
        public var portOffset: Int
        public var readinessTimeout: TimeInterval
        public var pollInterval: TimeInterval

        public init(
            projectDirectoryName: String = "nodejs-project",
            portOffset: Int = 0,
            readinessTimeout: TimeInterval = 20,
            pollInterval: TimeInterval = 0.25
        ) {
            self.projectDirectoryName = projectDirectoryName
            self.portOffset = portOffset
            self.readinessTimeout = max(2, readinessTimeout)
            self.pollInterval = max(0.1, pollInterval)
        }
    }

    private let driver: FoliaNodeRuntimeDriver
    private let configuration: Configuration
    private let fileManager: FileManager
    private let urlSession: URLSession
    private let logDirectory: URL

    public private(set) var state: FoliaNodeRuntimeState = .stopped {
        didSet { onStateChanged?(state) }
    }
    public var onStateChanged: ((FoliaNodeRuntimeState) -> Void)?

    public init(
        driver: FoliaNodeRuntimeDriver,
        configuration: Configuration = Configuration(),
        fileManager: FileManager = .default,
        urlSession: URLSession = .shared
    ) {
        self.driver = driver
        self.configuration = configuration
        self.fileManager = fileManager
        self.urlSession = urlSession
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.logDirectory = documents.appendingPathComponent("FoliaNode", isDirectory: true)
    }

    /// Creates the app-owned state directory, starts NodeMobile with the exact
    /// environment keys expected by main.js, and waits for all three local services.
    public func start() async throws {
        dispatchPrecondition(condition: .onQueue(.main))
        guard state == .stopped || isFailed else { return }
        state = .starting
        do {
            try fileManager.createDirectory(
                at: logDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )

            let kugouPort = 3_211 + configuration.portOffset
            let qqPort = 3_212 + configuration.portOffset
            let proxyPort = 3_213 + configuration.portOffset
            guard [kugouPort, qqPort, proxyPort].allSatisfy({ (1_024...65_535).contains($0) }) else {
                throw error("invalid-local-port-configuration")
            }

            let environment = [
                "FOLIA_LOG_DIR": logDirectory.path,
                "FOLIA_LOCAL_PORT_OFFSET": String(configuration.portOffset),
                "FOLIA_KUGOU_PORT": String(kugouPort),
                "FOLIA_QQ_PORT": String(qqPort),
                "FOLIA_PROXY_PORT": String(proxyPort),
                "QQ_AUTH_STATE_PATH": logDirectory.appendingPathComponent("qq-device.json").path
            ]
            try driver.start(
                projectDirectoryName: configuration.projectDirectoryName,
                environment: environment
            )

            let ready = await waitForServices(
                endpoints: [
                    URL(string: "http://127.0.0.1:\(kugouPort)/")!,
                    URL(string: "http://127.0.0.1:\(qqPort)/")!,
                    // main.js returns 405 for an unknown GET path after reaching this listener.
                    URL(string: "http://127.0.0.1:\(proxyPort)/__folia-readiness-probe")!
                ]
            )
            guard ready else {
                driver.stop()
                throw error("node-services-readiness-timeout")
            }
            state = .ready
        } catch {
            state = .failed(String(describing: error).prefix(160).description)
            throw error
        }
    }

    public func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard state != .stopped else { return }
        driver.stop()
        state = .stopped
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func waitForServices(endpoints: [URL]) async -> Bool {
        let deadline = Date().addingTimeInterval(configuration.readinessTimeout)
        while Date() < deadline {
            let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
                for endpoint in endpoints {
                    group.addTask { [urlSession] in
                        var request = URLRequest(url: endpoint)
                        request.httpMethod = "GET"
                        request.timeoutInterval = 1
                        request.cachePolicy = .reloadIgnoringLocalCacheData
                        do {
                            let (_, response) = try await urlSession.data(for: request)
                            guard let response = response as? HTTPURLResponse else { return false }
                            // 3xx/4xx proves the loopback listener is alive; only server errors fail.
                            return (100..<500).contains(response.statusCode)
                        } catch {
                            return false
                        }
                    }
                }
                var values: [Bool] = []
                for await result in group { values.append(result) }
                return values
            }
            if results.count == endpoints.count && results.allSatisfy({ $0 }) { return true }
            try? await Task.sleep(nanoseconds: UInt64(configuration.pollInterval * 1_000_000_000))
        }
        return false
    }

    private func error(_ code: String) -> NSError {
        NSError(domain: "FoliaNodeRuntimeCoordinator", code: 1,
                userInfo: [NSLocalizedDescriptionKey: code])
    }
}
