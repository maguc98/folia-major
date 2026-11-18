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
    private var player = AVPlayer()
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
    private var pendingFreshTrackEvent = false
    private var audioPreparingItemID: ObjectIdentifier?
    private var interruptedBySystem = false
    private let isAllowedMediaURL: (URL) -> Bool
    private let audioAnalyzer = NativeAudioTapAnalyzer()

    /// Optional host callback, invoked on the main queue whenever a native player event is emitted.
    /// A host can use it to keep Now Playing metadata synchronized without a second timer.
    public var onPlaybackStateChanged: (() -> Void)?
    /// Host-provided Apple Music / Feiniu provider bridge.
    public var onProviderRequest: (([String: Any], @escaping ([String: Any]) -> Void) -> Void)?

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
        audioAnalyzer.onBands = { [weak self] bands in
            guard let self, !self.session.isEmpty else { return }
            var payload: [String: Any] = ["type": "audio"]
            for (key, value) in bands.payload { payload[key] = value }
            self.emit(payload)
        }
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
            } else if player.currentItem?.status == .readyToPlay {
                player.play()
            }
            emitState()
        case "pause":
            // Explicit user intent is distinct from programmatic transport pauses.
            let userIntent = bool(command["userIntent"])
            let releaseIntent = bool(command["releaseIntent"]) ?? false
            if userIntent == true || releaseIntent || userIntent == nil { desiredPlaying = false }
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
        guard let onProviderRequest else {
            reply(["ok": false, "error": "provider-service-not-installed"])
            return
        }
        onProviderRequest(request) { payload in
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
        installMixedAudioTapBeforePlaybackIfSupported(on: item)
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

        player.pause()
        player.replaceCurrentItem(with: item)
        attachObservers(to: item)
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
                    self.attachAudioAnalysis(to: item) {
                        guard self.player.currentItem === item else { return }
                        let finishReady = {
                            guard self.player.currentItem === item else { return }
                            if self.desiredPlaying { self.player.play() }
                            else { self.player.pause() }
                            self.emit(["type": "loaded", "fresh": self.consumeFreshTrackFlag()])
                            self.emitState()
                        }
                        if let pending = self.pendingSeek {
                            self.pendingSeek = nil
                            let target = CMTime(seconds: pending, preferredTimescale: 600)
                            self.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                                DispatchQueue.main.async(execute: finishReady)
                            }
                        } else {
                            finishReady()
                        }
                    }
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
                    "sentAtMs": Date().timeIntervalSince1970 * 1000,
                    "fresh": self.consumeFreshTrackFlag()
                ])
            }
        }
    }

    private func installMixedAudioTapBeforePlaybackIfSupported(on item: AVPlayerItem) {
        // The all-tracks mix tap API is not exposed by the selected iOS 26.5 SDK.
        // attachAudioAnalysis(to:) installs the supported per-track tap after asset loading.
    }

    private func attachAudioAnalysis(to item: AVPlayerItem, completion: @escaping () -> Void) {
        let identifier = ObjectIdentifier(item)
        guard audioPreparingItemID != identifier else { return }
        audioPreparingItemID = identifier

        let asset = item.asset
        Task { [weak self, weak item] in
            do {
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                await MainActor.run {
                    guard let self, let item, self.player.currentItem === item else { return }
                    if let audioTrack = tracks.first, item.audioMix == nil {
                        do {
                            item.audioMix = try self.audioAnalyzer.makeAudioMix(for: audioTrack)
                        } catch {
                            self.emit(["type": "error", "message": "audio-analysis-unavailable"])
                        }
                    }
                    completion()
                }
            } catch {
                await MainActor.run {
                    guard let self, let item, self.player.currentItem === item else { return }
                    self.emit(["type": "error", "message": "audio-analysis-track-unavailable"])
                    completion()
                }
            }
        }
    }

    private func detachCurrentItemObservers() {
        player.currentItem?.audioMix = nil
        audioPreparingItemID = nil
        audioAnalyzer.reset()
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
              isAllowedMediaURL(url) else {
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
        pendingFreshTrackEvent = true
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

    private func consumeFreshTrackFlag() -> Bool {
        let value = pendingFreshTrackEvent
        pendingFreshTrackEvent = false
        return value
    }

    private func emitState() {
        let position = player.currentTime().seconds
        var payload: [String: Any] = [
            "type": "state",
            "playing": player.rate > 0,
            "sentAtMs": Date().timeIntervalSince1970 * 1000,
            "fresh": consumeFreshTrackFlag()
        ]
        if position.isFinite { payload["position"] = position }
        emit(payload)
    }

    private func publishStatus() {
        let position = player.currentTime().seconds
        var payload: [String: Any] = [
            "type": "state",
            "playing": player.rate > 0,
            "volume": volume,
            "muted": muted,
            "desiredPlaying": desiredPlaying,
            "sentAtMs": Date().timeIntervalSince1970 * 1000
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
        if event["type"] as? String != "audio" { onPlaybackStateChanged?() }
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


 // MARK: - System media transport integration

extension FoliaAVPlayerEngine: FoliaPlaybackTransport {
    public func playbackSnapshot() -> FoliaPlaybackSnapshot {
        dispatchPrecondition(condition: .onQueue(.main))
        let itemDuration = player.currentItem?.duration.seconds ?? 0
        let duration = itemDuration.isFinite && itemDuration > 0 ? itemDuration : 0
        let currentPosition = player.currentTime().seconds
        let position = currentPosition.isFinite && currentPosition >= 0 ? currentPosition : 0

        return FoliaPlaybackSnapshot(
            title: currentTrack["title"] as? String ?? currentTrack["name"] as? String,
            artist: currentTrack["artist"] as? String,
            album: currentTrack["album"] as? String,
            duration: duration,
            elapsedTime: position,
            isPlaying: player.rate > 0,
            desiredPlaying: desiredPlaying,
            canGoNext: !upcoming.isEmpty,
            canGoPrevious: !previous.isEmpty || position > 3
        )
    }

    public func playbackPlayFromSystem() {
        dispatchPrecondition(condition: .onQueue(.main))
        desiredPlaying = true
        if endedForURL == currentURL?.absoluteString, !upcoming.isEmpty {
            advanceIfPossible(reason: "remote-play-after-end")
        } else if player.currentItem?.status == .readyToPlay {
            player.play()
        }
        emitState()
    }

    public func playbackPauseFromSystem() {
        dispatchPrecondition(condition: .onQueue(.main))
        desiredPlaying = false
        player.pause()
        emitState()
    }

    public func playbackSeekFromSystem(to seconds: Double) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard seconds.isFinite, seconds >= 0 else { return }
        seek(seconds)
    }

    public func playbackNextFromSystem() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !upcoming.isEmpty else { return }
        desiredPlaying = true
        advanceIfPossible(reason: "remote-next")
    }

    public func shutdownTransport() {
        dispatchPrecondition(condition: .onQueue(.main))
        desiredPlaying = false
        player.pause()
        detachCurrentItemObservers()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
        currentTrack.removeAll()
        upcoming.removeAll()
        previous.removeAll()
        pendingSeek = nil
        endedForURL = nil
        pendingFreshTrackEvent = false
        audioAnalyzer.reset()
    }

    public func playbackMediaServicesWereReset() {
        dispatchPrecondition(condition: .onQueue(.main))
        let savedURL = currentURL
        let rawPosition = player.currentTime().seconds
        let position = rawPosition.isFinite && rawPosition >= 0 ? rawPosition : 0
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        detachCurrentItemObservers()

        let replacement = AVPlayer()
        replacement.automaticallyWaitsToMinimizeStalling = true
        replacement.volume = volume
        replacement.isMuted = muted
        player = replacement

        guard let savedURL else {
            replacement.pause()
            emitState()
            return
        }
        let item = AVPlayerItem(url: savedURL)
        installMixedAudioTapBeforePlaybackIfSupported(on: item)
        pendingSeek = position
        replacement.replaceCurrentItem(with: item)
        attachObservers(to: item)
        replacement.pause()
        emitState()
    }

    public func playbackInterruptionBegan() {
        dispatchPrecondition(condition: .onQueue(.main))
        interruptedBySystem = desiredPlaying || player.rate > 0
        player.pause()
        emitState()
    }

    public func playbackInterruptionEnded(shouldResume: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard interruptedBySystem else {
            emitState()
            return
        }
        interruptedBySystem = false
        // A system interruption is not a user pause. Preserve desiredPlaying,
        // but resume only when iOS explicitly grants the shouldResume option.
        if shouldResume && desiredPlaying {
            player.play()
        }
        emitState()
    }

    public func playbackRouteChanged(outputWasDisconnected: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        if outputWasDisconnected {
            // Headphones becoming unavailable is treated as an intentional
            // stop to avoid unexpectedly moving private audio to the speaker.
            desiredPlaying = false
            player.pause()
        }
        emitState()
    }

    public func playbackPreviousFromSystem() {
        dispatchPrecondition(condition: .onQueue(.main))
        let position = player.currentTime().seconds
        if position.isFinite && position > 3 {
            seek(0)
            return
        }
        guard let previousTrack = previous.popLast(),
              let rawURL = previousTrack["url"] as? String,
              let url = URL(string: rawURL),
              isAllowedMediaURL(url) else { return }

        if !currentTrack.isEmpty { upcoming.insert(currentTrack, at: 0) }
        desiredPlaying = true
        load([
            "url": rawURL,
            "position": 0,
            "autoplay": true,
            "track": previousTrack,
            "upcoming": upcoming,
            "previous": previous,
            "session": session,
            "generation": generation
        ])
        pendingFreshTrackEvent = true
        emit([
            "type": "auto-advanced",
            "trackKey": previousTrack["trackKey"] as? String ?? rawURL,
            "url": rawURL,
            "position": 0
        ])
    }
}

// MARK: - Persisted playback recovery

extension FoliaAVPlayerEngine {
    /// A bounded metadata/queue snapshot for the host's protected app-container store.
    /// Signed URLs may be rejected by FoliaPlaybackSnapshotStore's URL policy.
    public func makePlaybackPersistenceSnapshot() -> [String: Any]? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let url = currentURL?.absoluteString, !session.isEmpty, generation >= 0 else { return nil }
        let rawPosition = player.currentTime().seconds
        let position = rawPosition.isFinite && rawPosition >= 0 ? rawPosition : 0

        func metadata(_ track: [String: Any]) -> [String: Any] {
            var result: [String: Any] = [:]
            for key in ["trackKey", "title", "name", "artist", "album"] {
                if let value = track[key] as? String, value.count <= 2_048 { result[key] = value }
            }
            return result
        }

        func queue(_ tracks: [[String: Any]]) -> [[String: Any]] {
            tracks.compactMap { track in
                guard let raw = track["url"] as? String,
                      let candidate = URL(string: raw), isAllowedMediaURL(candidate) else { return nil }
                var value = metadata(track)
                value["url"] = raw
                return value
            }
        }

        return [
            "schemaVersion": 1, "savedAt": Date().timeIntervalSince1970,
            "url": url, "position": position, "desiredPlaying": desiredPlaying,
            "track": metadata(currentTrack), "upcoming": queue(upcoming),
            "previous": queue(previous), "session": session, "generation": generation
        ]
    }

    /// Restore only after the new Web runtime has supplied its current session/generation.
    /// The caller explicitly decides whether a previously-playing item may resume.
    @discardableResult
    public func restorePlaybackPersistenceSnapshot(
        _ snapshot: [String: Any], session newSession: String, generation newGeneration: Int,
        resumePlayback: Bool
    ) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !newSession.isEmpty, newSession.count <= 256, newGeneration >= 0,
              let rawURL = snapshot["url"] as? String,
              let url = URL(string: rawURL), isAllowedMediaURL(url),
              let position = finiteNonNegative(snapshot["position"]),
              let track = snapshot["track"] as? [String: Any] else { return false }
        let wantsPlayback = (snapshot["desiredPlaying"] as? Bool) == true
        self.session = newSession
        self.generation = newGeneration
        load([
            "url": url.absoluteString, "position": position,
            "autoplay": resumePlayback && wantsPlayback, "track": track,
            "upcoming": snapshot["upcoming"] as? [[String: Any]] ?? [],
            "previous": snapshot["previous"] as? [[String: Any]] ?? [],
            "session": newSession, "generation": newGeneration
        ])
        return currentURL == url
    }
}
