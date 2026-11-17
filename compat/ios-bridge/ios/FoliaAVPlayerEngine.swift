import Foundation
import AVFoundation
import CoreFoundation

/// A new AVPlayer-backed host implementation for the build-379 bridge contract.
///
/// This is replacement scaffolding, not recovered Folia source. It deliberately
/// implements only the AVPlayer transport path. MusicKit, provider authentication,
/// NodeMobile, background-audio entitlements and app lifecycle wiring remain host tasks.
public final class FoliaAVPlayerEngine: NSObject, FoliaBridgeRouterDelegate {
    private weak var router: FoliaBridgeRouter?
    private let player = AVPlayer()
    private var currentItemObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var currentURL: URL?
    private var currentTrack: [String: Any] = [:]
    private var upcoming: [[String: Any]] = []
    private var previous: [[String: Any]] = []
    private var session = ""
    private var generation: Int = -1
    private var desiredPlaying = false
    private var muted = false
    private var volume: Float = 1
    private var pendingSeek: Double?
    private var endedForURL: String?
    private let isAllowedMediaURL: (URL) -> Bool

    public init(isAllowedMediaURL: @escaping (URL) -> Bool = { url in
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "https" || scheme == "http" {
            return url.host?.isEmpty == false && url.user == nil && url.password == nil
        }
        // Hosts may opt into app-sandbox file URLs after validating the resolved path.
        return false
    }) {
        self.isAllowedMediaURL = isAllowedMediaURL
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = volume
        player.isMuted = muted
    }

    /// Call after constructing FoliaBridgeRouter(delegate: engine).
    /// The host must retain both the engine and router for the lifetime of the WebView.
    public func attach(to router: FoliaBridgeRouter) {
        self.router = router
    }

    deinit {
        detachCurrentItemObservers()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    // MARK: - FoliaBridgeRouterDelegate

    public func foliaBridgeRouter(_ router: FoliaBridgeRouter, didReceivePlayerCommand command: [String: Any]) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let cmd = command["cmd"] as? String else { return }
        if cmd == "startup_prompts_seen" { return }
        guard adoptSession(command) else { return }

        switch cmd {
        case "load":
            load(command)
        case "play":
            desiredPlaying = true
            if endedForURL == currentURL?.absoluteString, !upcoming.isEmpty {
                advanceIfPossible(reason: "user-resume-after-end")
            } else {
                player.play()
            }
            emitState()
        case "pause":
            // Explicit user intent is distinct from programmatic transport pauses.
            if bool(command["userIntent"]) ?? true { desiredPlaying = false }
            player.pause()
            emitState()
        case "seek":
            guard let seconds = finiteNonNegative(command["position"]) else { return }
            seek(seconds)
        case "volume":
            guard let value = finiteNumber(command["volume"]), (0...1).contains(value) else { return }
            volume = Float(value)
            player.volume = volume
        case "muted":
            guard let value = bool(command["muted"]) else { return }
            muted = value
            player.isMuted = muted
        case "status":
            publishStatus()
        case "upcoming":
            syncUpcoming(command)
        default:
            break
        }
    }

    public func foliaBridgeRouter(
        _ router: FoliaBridgeRouter,
        didReceiveProviderRequest request: [String: Any],
        reply: @escaping ([String: Any]) -> Void
    ) {
        // Provider implementations are intentionally not fabricated here.
        reply(["ok": false, "error": "provider-service-not-installed"])
    }

    // MARK: - Session and command handling

    private func adoptSession(_ command: [String: Any]) -> Bool {
        guard let nextSession = command["session"] as? String,
              let nextGeneration = integer(command["generation"]),
              !nextSession.isEmpty, nextGeneration >= 0 else { return false }

        if session != nextSession {
            session = nextSession
            generation = nextGeneration
            desiredPlaying = false
            upcoming.removeAll()
            previous.removeAll()
            endedForURL = nil
            return true
        }
        guard nextGeneration >= generation else { return false }
        generation = nextGeneration
        return true
    }

    private func load(_ command: [String: Any]) {
        guard let rawURL = command["url"] as? String,
              let url = URL(string: rawURL),
              isAllowedMediaURL(url),
              let position = finiteNonNegative(command["position"]) else { return }

        detachCurrentItemObservers()
        let item = AVPlayerItem(url: url)
        currentURL = url
        currentTrack = command["track"] as? [String: Any] ?? [:]
        if currentTrack["trackKey"] == nil {
            currentTrack["trackKey"] = command["trackKey"] as? String ?? rawURL
        }
        currentTrack["url"] = rawURL
        upcoming = normalizedQueue(command["upcoming"])
        previous = normalizedQueue(command["previous"])
        endedForURL = nil
        pendingSeek = position
        desiredPlaying = bool(command["autoplay"]) ?? false

        player.replaceCurrentItem(with: item)
        attachObservers(to: item)
        if desiredPlaying {
            player.play()
        } else {
            player.pause()
        }
        emitState()
    }

    private func syncUpcoming(_ command: [String: Any]) {
        let requestedKey = command["currentTrackKey"] as? String
        let actualKey = currentTrack["trackKey"] as? String
        guard requestedKey == nil || actualKey == nil || requestedKey == actualKey else { return }
        upcoming = normalizedQueue(command["upcoming"])
        previous = normalizedQueue(command["previous"])
        if endedForURL == currentURL?.absoluteString, desiredPlaying {
            advanceIfPossible(reason: "late-queue")
        }
    }

    // MARK: - AVPlayer item lifecycle

    private func attachObservers(to item: AVPlayerItem) {
        currentItemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            DispatchQueue.main.async {
                guard let self, let item, self.player.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    if let pending = self.pendingSeek {
                        self.pendingSeek = nil
                        self.seek(pending)
                    }
                    if self.desiredPlaying { self.player.play() }
                    self.emit(["type": "loaded"])
                    self.emitState()
                case .failed:
                    self.emit(["type": "error", "message": item.error?.localizedDescription ?? "item-failed"])
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self, weak item] _ in
            guard let self, let item, self.player.currentItem === item else { return }
            self.handleEnded(url: self.currentURL?.absoluteString)
        }
        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self, weak item] note in
            guard let self, let item, self.player.currentItem === item else { return }
            let error = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "failed-to-play-to-end"
            self.emit(["type": "error", "message": error])
        }
        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self, weak item] _ in
            guard let self, let item, self.player.currentItem === item else { return }
            self.emit(["type": "error", "message": "playback-stalled"])
        }

        if timeObserver == nil {
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                guard let self, time.seconds.isFinite, self.player.currentItem != nil else { return }
                let duration = self.player.currentItem?.duration.seconds ?? .nan
                self.emit([
                    "type": "time",
                    "playing": self.player.rate > 0,
                    "position": time.seconds,
                    "duration": duration.isFinite && duration > 0 ? duration : 0,
                    "sentAtMs": Date().timeIntervalSince1970 * 1000
                ])
            }
        }
    }

    private func detachCurrentItemObservers() {
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        for token in [endObserver, failedObserver, stalledObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(token)
        }
        endObserver = nil
        failedObserver = nil
        stalledObserver = nil
    }

    private func handleEnded(url: String?) {
        guard let url, url == currentURL?.absoluteString, endedForURL != url else { return }
        endedForURL = url
        let canAdvance = desiredPlaying && !upcoming.isEmpty
        emit(["type": "ended", "url": url, "autoAdvancePrepared": canAdvance])
        if canAdvance { advanceIfPossible(reason: "ended") }
        else { emitState() }
    }

    private func advanceIfPossible(reason: String) {
        _ = reason // Retained for host-side diagnostics/integration logging.
        guard desiredPlaying, !upcoming.isEmpty else {
            emitState()
            return
        }
        if !currentTrack.isEmpty { previous.append(currentTrack) }
        let next = upcoming.removeFirst()
        guard let rawURL = next["url"] as? String,
              let url = URL(string: rawURL),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else {
            emit(["type": "error", "message": "next-track-url-invalid"])
            return
        }
        load([
            "url": rawURL,
            "position": 0,
            "autoplay": true,
            "track": next,
            "upcoming": upcoming,
            "previous": previous,
            "session": session,
            "generation": generation
        ])
        emit([
            "type": "auto-advanced",
            "trackKey": next["trackKey"] as? String ?? rawURL,
            "url": rawURL,
            "position": 0
        ])
    }

    // MARK: - Transport and event publication

    private func seek(_ seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self, finished else { return }
            self.pendingSeek = nil
            self.publishStatus()
        }
    }

    private func emitState() {
        emitState()
    }

    private func publishStatus() {
        let position = player.currentTime().seconds
        var payload: [String: Any] = [
            "type": "state",
            "playing": player.rate > 0,
            "volume": volume,
            "muted": muted,
            "desiredPlaying": desiredPlaying
        ]
        if position.isFinite { payload["position"] = position }
        if let url = currentURL?.absoluteString { payload["url"] = url }
        emit(payload)
    }

    private func emit(_ payload: [String: Any]) {
        guard !session.isEmpty, generation >= 0 else { return }
        var event = payload
        event["session"] = session
        event["generation"] = generation
        router?.emitPlayerEvent(event)
    }

    // MARK: - Input normalization

    private func normalizedQueue(_ value: Any?) -> [[String: Any]] {
        guard let entries = value as? [[String: Any]] else { return [] }
        return Array(entries.prefix(500)).filter { entry in
            guard let raw = entry["url"] as? String,
                  let url = URL(string: raw),
                  isAllowedMediaURL(url) else { return false }
            return true
        }
    }

    private func finiteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private func finiteNonNegative(_ value: Any?) -> Double? {
        guard let number = finiteNumber(value), number >= 0 else { return nil }
        return number
    }

    private func integer(_ value: Any?) -> Int? {
        guard let number = finiteNumber(value),
              number.rounded(.towardZero) == number,
              number <= Double(Int.max), number >= Double(Int.min) else { return nil }
        return Int(number)
    }

    private func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}
