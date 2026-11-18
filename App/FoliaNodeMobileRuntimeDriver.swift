import Foundation
import Darwin

/// NodeMobile's documented iOS entry point. The matching NodeMobile.framework
/// is linked by the Xcode target; its public header declares:
///   void node_start(int argc, char* argv[]);
@_silgen_name("node_start")
private func folia_node_start(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
)

/// Concrete adapter for the NodeMobile 18.20.4 runtime embedded by Folia build 379.
/// NodeMobile supports one runtime instance per app process and exposes no stop API.
@MainActor
final class FoliaNodeMobileRuntimeDriver: FoliaNodeRuntimeDriver {
    private var didStart = false
    private var runtimeThread: Thread?

    func start(projectDirectoryName: String, environment: [String: String]) throws {
        guard !didStart else {
            throw NSError(
                domain: "FoliaNodeMobileRuntimeDriver",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "NodeMobile only supports one runtime instance per process."]
            )
        }

        guard let resourceURL = Bundle.main.resourceURL else {
            throw NSError(
                domain: "FoliaNodeMobileRuntimeDriver",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Application resource directory is unavailable."]
            )
        }

        let publicURL = resourceURL.appendingPathComponent("public", isDirectory: true)
        let projectURL = publicURL.appendingPathComponent(projectDirectoryName, isDirectory: true)
        let entryURL = projectURL.appendingPathComponent("main.js")
        guard FileManager.default.fileExists(atPath: entryURL.path) else {
            throw NSError(
                domain: "FoliaNodeMobileRuntimeDriver",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Bundled nodejs-project/main.js is missing."]
            )
        }

        for (key, value) in environment {
            guard setenv(key, value, 1) == 0 else {
                throw NSError(
                    domain: "FoliaNodeMobileRuntimeDriver",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to set NodeMobile environment variable: \(key)"]
                )
            }
        }

        // Resolve module paths relative to the bundled Node project, while keeping
        // mutable auth state and logs in the app-owned path supplied by the coordinator.
        let projectPath = projectURL.path
        let thread = Thread {
            guard FileManager.default.changeCurrentDirectoryPath(projectPath) else {
                NSLog("[Folia] NodeMobile could not change working directory to %@", projectPath)
                return
            }

            let encodedArguments = ["node", "main.js"].map { Array($0.utf8) }
            let storageSize = encodedArguments.reduce(0) { $0 + $1.count + 1 }
            guard let storage = calloc(storageSize, MemoryLayout<CChar>.stride) else {
                NSLog("[Folia] NodeMobile could not allocate argv storage")
                return
            }
            defer { free(storage) }

            // libuv requires argv strings to occupy one contiguous allocation.
            let storageBase = storage.assumingMemoryBound(to: CChar.self)
            var cursor = storageBase
            var argv: [UnsafeMutablePointer<CChar>?] = []
            for bytes in encodedArguments {
                argv.append(cursor)
                bytes.withUnsafeBufferPointer { source in
                    if let baseAddress = source.baseAddress {
                        memcpy(cursor, baseAddress, source.count)
                    }
                }
                cursor = cursor.advanced(by: bytes.count + 1)
            }
            argv.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                folia_node_start(Int32(buffer.count), baseAddress)
            }
        }
        thread.name = "com.folia.node-mobile"
        thread.stackSize = 2 * 1024 * 1024
        runtimeThread = thread
        didStart = true
        thread.start()
    }

    func stop() {
        // The upstream NodeMobile API has no supported stop/restart operation.
        // Keep the thread/runtime alive until process exit; callers must not infer
        // that this method has terminated the Node event loop.
    }
}
