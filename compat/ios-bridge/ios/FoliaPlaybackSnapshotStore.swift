import Foundation

/// Stores a bounded, versioned playback snapshot inside the app sandbox.
/// By default it refuses media URLs containing query strings, fragments, or
/// embedded credentials because these commonly carry expiring access tokens.
/// Hosts may supply a stricter or explicitly reviewed persistence policy.
public final class FoliaPlaybackSnapshotStore {
    public typealias URLPersistencePolicy = (URL) -> Bool

    private let fileURL: URL
    private let fileManager: FileManager
    private let isPersistableURL: URLPersistencePolicy
    private let maximumBytes: Int

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        maximumBytes: Int = 512 * 1024,
        isPersistableURL: @escaping URLPersistencePolicy = { url in
            guard let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host?.isEmpty == false,
                  url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil else { return false }
            return true
        }
    ) {
        self.fileManager = fileManager
        self.maximumBytes = max(4_096, maximumBytes)
        self.isPersistableURL = isPersistableURL
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.fileURL = root.appendingPathComponent("Folia/Playback/playback-snapshot.json")
        }
    }

    public func save(_ snapshot: [String: Any]) throws {
        guard let urlString = snapshot["url"] as? String,
              let mediaURL = URL(string: urlString),
              isPersistableURL(mediaURL),
              let version = snapshot["schemaVersion"] as? Int, version == 1,
              let position = snapshot["position"] as? NSNumber,
              position.doubleValue.isFinite, position.doubleValue >= 0,
              let session = snapshot["session"] as? String, !session.isEmpty,
              let generation = snapshot["generation"] as? Int, generation >= 0,
              JSONSerialization.isValidJSONObject(snapshot) else {
            throw error("invalid-or-sensitive-snapshot")
        }

        for key in ["upcoming", "previous"] {
            if let tracks = snapshot[key] as? [[String: Any]] {
                for track in tracks {
                    guard let rawTrackURL = track["url"] as? String,
                          let trackURL = URL(string: rawTrackURL),
                          isPersistableURL(trackURL) else {
                        throw error("queue-contains-sensitive-or-invalid-url")
                    }
                }
            }
        }

        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
        guard data.count <= maximumBytes else { throw error("snapshot-too-large") }
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    public func load(maxAge: TimeInterval = 24 * 60 * 60) throws -> [String: Any]? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= maximumBytes else {
            try? clear()
            throw error("snapshot-size-invalid")
        }

        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["schemaVersion"] as? Int, version == 1,
              let savedAt = object["savedAt"] as? NSNumber,
              savedAt.doubleValue.isFinite,
              Date().timeIntervalSince1970 - savedAt.doubleValue >= -60,
              Date().timeIntervalSince1970 - savedAt.doubleValue <= maxAge,
              let rawURL = object["url"] as? String,
              let url = URL(string: rawURL), isPersistableURL(url),
              let position = object["position"] as? NSNumber,
              position.doubleValue.isFinite, position.doubleValue >= 0,
              let session = object["session"] as? String, !session.isEmpty,
              let generation = object["generation"] as? Int, generation >= 0 else {
            try? clear()
            return nil
        }
        return object
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func error(_ code: String) -> NSError {
        NSError(domain: "FoliaPlaybackSnapshotStore", code: 1,
                userInfo: [NSLocalizedDescriptionKey: code])
    }
}
