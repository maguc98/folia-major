import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// A compact, main-thread snapshot used to publish lock-screen metadata.
public struct FoliaPlaybackSnapshot {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval
    public let elapsedTime: TimeInterval
    public let isPlaying: Bool
    public let desiredPlaying: Bool

    public init(
        title: String?,
        artist: String?,
        album: String?,
        duration: TimeInterval,
        elapsedTime: TimeInterval,
        isPlaying: Bool,
        desiredPlaying: Bool
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.isPlaying = isPlaying
        self.desiredPlaying = desiredPlaying
    }
}

public enum FoliaApplicationLifecycleEvent {
    case didEnterBackground
    case willEnterForeground
}

/// The keeper talks to a transport protocol rather than owning an AVPlayer.
/// Implementations must be called on the main queue.
public protocol FoliaPlaybackTransport: AnyObject {
    func playbackSnapshot() -> FoliaPlaybackSnapshot
    func playbackPlayFromSystem()
    func playbackPauseFromSystem()
    func playbackSeekFromSystem(to seconds: Double)
    func playbackNextFromSystem()
    func playbackPreviousFromSystem()
    func playbackInterruptionBegan()
    func playbackInterruptionEnded(shouldResume: Bool)
    func playbackRouteChanged(outputWasDisconnected: Bool)
}

/// Publishes Now Playing metadata and forwards hardware/Control Center commands.
/// This class does not fake audio or create a silent keep-alive loop.
public final class FoliaPlaybackKeeper {
    private weak var transport: FoliaPlaybackTransport?
    private let commandCenter: MPRemoteCommandCenter
    private var commandTokens: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var isInstalled = false
    private var isAudioSessionActive = false

    /// Host hook for snapshot persistence or app-specific lifecycle coordination.
    public var onApplicationLifecycleChanged: ((FoliaApplicationLifecycleEvent) -> Void)?
    /// Host hook for audio-session activation failures during interruption recovery.
    public var onAudioSessionError: ((Error) -> Void)?

    public init(
        transport: FoliaPlaybackTransport,
        commandCenter: MPRemoteCommandCenter = .shared()
    ) {
        self.transport = transport
        self.commandCenter = commandCenter
    }

    deinit {
        for token in commandTokens { commandCenter.removeTarget(token) }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Install once after the host has created the transport.
    public func install() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isInstalled else { return }
        isInstalled = true
        installRemoteCommands()
        installAudioSessionObservers()
        installApplicationLifecycleObservers()
        refreshNowPlayingInfo()
    }

    /// Call when track metadata, timeline, or transport state changes.
    public func refreshNowPlayingInfo() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let snapshot = transport?.playbackSnapshot() else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: false
        ]
        if let title = snapshot.title, !title.isEmpty {
            info[MPMediaItemPropertyTitle] = title
        }
        if let artist = snapshot.artist, !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = snapshot.album, !album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if snapshot.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = snapshot.duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateCommandAvailability(snapshot)
    }

    /// Activates the playback audio session. The app target still needs the
    /// Audio, AirPlay, and Picture in Picture background mode where appropriate.
    public func activatePlaybackAudioSession() throws {
        dispatchPrecondition(condition: .onQueue(.main))
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default, options: [])
        try audioSession.setActive(true)
        isAudioSessionActive = true
    }

    /// Deactivate only when the host has actually stopped owning playback.
    public func deactivatePlaybackAudioSession() throws {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isAudioSessionActive else { return }
        try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isAudioSessionActive = false
    }

    public func clearNowPlayingInfo() {
        dispatchPrecondition(condition: .onQueue(.main))
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func installRemoteCommands() {
        let play = commandCenter.playCommand
        play.isEnabled = true
        commandTokens.append(play.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.transport?.playbackPlayFromSystem()
                self?.refreshNowPlayingInfo()
            }
            return .success
        })

        let pause = commandCenter.pauseCommand
        pause.isEnabled = true
        commandTokens.append(pause.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.transport?.playbackPauseFromSystem()
                self?.refreshNowPlayingInfo()
            }
            return .success
        })

        let toggle = commandCenter.togglePlayPauseCommand
        toggle.isEnabled = true
        commandTokens.append(toggle.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let snapshot = self.transport?.playbackSnapshot() else { return }
                if snapshot.isPlaying || snapshot.desiredPlaying {
                    self.transport?.playbackPauseFromSystem()
                } else {
                    self.transport?.playbackPlayFromSystem()
                }
                self.refreshNowPlayingInfo()
            }
            return .success
        })

        let next = commandCenter.nextTrackCommand
        next.isEnabled = false
        commandTokens.append(next.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.transport?.playbackNextFromSystem()
                self?.refreshNowPlayingInfo()
            }
            return .success
        })

        let previous = commandCenter.previousTrackCommand
        previous.isEnabled = true
        commandTokens.append(previous.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.transport?.playbackPreviousFromSystem()
                self?.refreshNowPlayingInfo()
            }
            return .success
        })

        let position = commandCenter.changePlaybackPositionCommand
        position.isEnabled = true
        commandTokens.append(position.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            DispatchQueue.main.async {
                self?.transport?.playbackSeekFromSystem(to: event.positionTime)
                self?.refreshNowPlayingInfo()
            }
            return .success
        })
    }

    private func updateCommandAvailability(_ snapshot: FoliaPlaybackSnapshot) {
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = snapshot.duration > 0
    }

    private func installApplicationLifecycleObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onApplicationLifecycleChanged?(.didEnterBackground)
            self?.refreshNowPlayingInfo()
        })
        observers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onApplicationLifecycleChanged?(.willEnterForeground)
            self?.refreshNowPlayingInfo()
        })
    }

    private func installAudioSessionObservers() {
        let center = NotificationCenter.default
        let audioSession = AVAudioSession.sharedInstance()

        if #available(iOS 27.0, *) {
            // iOS 27's lifecycle notifications replace the legacy began/ended
            // pair and avoid getting stuck when an interruption-end event is lost.
            observers.append(center.addObserver(
                forName: AVAudioSession.didBecomeInactiveNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let context = notification.userInfo?[AVAudioSession.deactivationContextKey]
                        as? AVAudioSession.DeactivationContext else { return }
                if context.source == .system {
                    self.isAudioSessionActive = false
                    self.transport?.playbackInterruptionBegan()
                    self.refreshNowPlayingInfo()
                }
            })

            observers.append(center.addObserver(
                forName: AVAudioSession.resumptionRecommendationNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let context = notification.userInfo?[AVAudioSession.resumptionContextKey]
                        as? AVAudioSession.ResumptionContext else { return }

                guard context.recommendation == .shouldResume else {
                    self.transport?.playbackInterruptionEnded(shouldResume: false)
                    self.refreshNowPlayingInfo()
                    return
                }

                Task { [weak self] in
                    do {
                        let activated = try await audioSession.activate()
                        await MainActor.run {
                            guard let self else { return }
                            self.isAudioSessionActive = activated
                            self.transport?.playbackInterruptionEnded(shouldResume: activated)
                            self.refreshNowPlayingInfo()
                        }
                    } catch {
                        await MainActor.run {
                            guard let self else { return }
                            self.onAudioSessionError?(error)
                            self.transport?.playbackInterruptionEnded(shouldResume: false)
                            self.refreshNowPlayingInfo()
                        }
                    }
                }
            })

            observers.append(center.addObserver(
                forName: AVAudioSession.didBecomeActiveNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] _ in
                self?.isAudioSessionActive = true
                self?.refreshNowPlayingInfo()
            })
        } else {
            // iOS 15–26 fallback. On newer systems the legacy shouldResume
            // option is deprecated in favor of ResumptionRecommendation.
            observers.append(center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let userInfo = notification.userInfo,
                      let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

                switch type {
                case .began:
                    self.isAudioSessionActive = false
                    self.transport?.playbackInterruptionBegan()
                case .ended:
                    let rawOptions = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                    let systemAllowsResume = options.contains(.shouldResume)
                    var sessionReactivated = false
                    if systemAllowsResume {
                        do {
                            try audioSession.setActive(true)
                            self.isAudioSessionActive = true
                            sessionReactivated = true
                        } catch {
                            self.onAudioSessionError?(error)
                        }
                    }
                    self.transport?.playbackInterruptionEnded(shouldResume: systemAllowsResume && sessionReactivated)
                @unknown default:
                    break
                }
                self.refreshNowPlayingInfo()
            })
        }

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
            self.transport?.playbackRouteChanged(outputWasDisconnected: reason == .oldDeviceUnavailable)
            self.refreshNowPlayingInfo()
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] _ in
            // Reconfigure the category after a media-services reset. Do not
            // auto-start: the transport's desired-playing intent is authoritative.
            do {
                try audioSession.setCategory(.playback, mode: .default, options: [])
                self?.isAudioSessionActive = false
                self?.refreshNowPlayingInfo()
            } catch {
                self?.onAudioSessionError?(error)
            }
        })
    }
}
