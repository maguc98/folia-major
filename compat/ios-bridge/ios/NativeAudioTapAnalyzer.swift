import Foundation
import AVFoundation
import MediaToolbox
import AudioToolbox

/// Normalized band-energy values sent through window.__foliaNativePlayerEvent.
/// Values are finite and constrained to 0...1; this is a compatibility DSP,
/// not a claim to reproduce the original build-379 calibration exactly.
public struct FoliaAudioBands {
    public let power: Double
    public let bass: Double
    public let lowMid: Double
    public let mid: Double
    public let vocal: Double
    public let treble: Double

    public var payload: [String: Any] {
        [
            "power": power, "bass": bass, "lowMid": lowMid,
            "mid": mid, "vocal": vocal, "treble": treble
        ]
    }
}

/// AVPlayer audio-mix tap. The cutoff labels match fields found in the build-379
/// executable (150, 400, 1200, 3500, 12000 Hz). The filter and normalization
/// below are a replacement model, not recovered original DSP.
public final class NativeAudioTapAnalyzer {
    private final class TapCookie {
        weak var analyzer: NativeAudioTapAnalyzer?
        init(analyzer: NativeAudioTapAnalyzer) { self.analyzer = analyzer }
    }

    private enum SampleKind {
        case float32
        case int16
        case int32
        case unsupported

        var bytesPerSample: Int {
            switch self {
            case .float32, .int32: return 4
            case .int16: return 2
            case .unsupported: return 0
            }
        }
    }

    private let lock = NSLock()
    private var sampleKind: SampleKind = .unsupported
    private var isNonInterleaved = false
    private var alpha150: Float = 0
    private var alpha400: Float = 0
    private var alpha1200: Float = 0
    private var alpha3500: Float = 0
    private var alpha12000: Float = 0
    private var lp150: Float = 0
    private var lp400: Float = 0
    private var lp1200: Float = 0
    private var lp3500: Float = 0
    private var lp12000: Float = 0
    private var lastPublishTime: TimeInterval = 0
    private var smoothedPower: Float = 0
    private var smoothedBass: Float = 0
    private var smoothedLowMid: Float = 0
    private var smoothedMid: Float = 0
    private var smoothedVocal: Float = 0
    private var smoothedTreble: Float = 0

    /// Called on the main queue, throttled to at most 20 updates per second.
    public var onBands: ((FoliaAudioBands) -> Void)?

    public init() {}

    public func makeAudioMix(for track: AVAssetTrack) throws -> AVAudioMix {
        let tap = try makeTap()
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    private func makeTap() throws -> MTAudioProcessingTap {
        reset()
        let retainedCookie = Unmanaged.passRetained(TapCookie(analyzer: self))
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: retainedCookie.toOpaque(),
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<TapCookie>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, processingFormat in
                let cookie = Unmanaged<TapCookie>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                cookie.analyzer?.prepare(format: processingFormat.pointee)
            },
            unprepare: { tap in
                let cookie = Unmanaged<TapCookie>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                cookie.analyzer?.reset()
            },
            process: { tap, frameCount, _, bufferList, frameCountOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(
                    tap, frameCount, bufferList, flagsOut, nil, frameCountOut
                )
                guard status == noErr else { return }
                let cookie = Unmanaged<TapCookie>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                cookie.analyzer?.process(bufferList, frameCount: Int(frameCountOut.pointee))
            }
        )

        var createdTap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &createdTap
        )
        guard status == noErr, let createdTap else {
            // The tap never accepted ownership of clientInfo.
            retainedCookie.release()
            throw NSError(
                domain: "FoliaAudioTap",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "audio-tap-create-failed"]
            )
        }
        return createdTap
    }

    /// Reset band history when its AVPlayerItem is replaced or the tap is unprepared.
    public func reset() {
        lock.lock()
        resetLocked()
        lock.unlock()
    }

    private func resetLocked() {
        lp150 = 0
        lp400 = 0
        lp1200 = 0
        lp3500 = 0
        lp12000 = 0
        smoothedPower = 0
        smoothedBass = 0
        smoothedLowMid = 0
        smoothedMid = 0
        smoothedVocal = 0
        smoothedTreble = 0
        lastPublishTime = 0
    }

    private func prepare(format: AudioStreamBasicDescription) {
        lock.lock()
        defer { lock.unlock() }

        let rate = format.mSampleRate.isFinite && format.mSampleRate > 0
            ? format.mSampleRate : 44_100
        let flags = format.mFormatFlags
        isNonInterleaved = (flags & kAudioFormatFlagIsNonInterleaved) != 0
        if (flags & kAudioFormatFlagIsFloat) != 0 && format.mBitsPerChannel == 32 {
            sampleKind = .float32
        } else if (flags & kAudioFormatFlagIsSignedInteger) != 0 && format.mBitsPerChannel == 16 {
            sampleKind = .int16
        } else if (flags & kAudioFormatFlagIsSignedInteger) != 0 && format.mBitsPerChannel == 32 {
            sampleKind = .int32
        } else {
            sampleKind = .unsupported
        }

        func coefficient(_ cutoff: Double) -> Float {
            let safeCutoff = min(cutoff, rate * 0.45)
            return Float(1.0 - exp(-2.0 * Double.pi * safeCutoff / rate))
        }
        alpha150 = coefficient(150)
        alpha400 = coefficient(400)
        alpha1200 = coefficient(1_200)
        alpha3500 = coefficient(3_500)
        alpha12000 = coefficient(12_000)
        resetLocked()
    }

    /// Keep this real-time callback allocation-light: no per-frame arrays,
    /// no logging, and no UIKit/WebKit calls from the audio processing thread.
    private func process(_ listPointer: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard frameCount > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(listPointer)

        lock.lock()
        let kind = sampleKind
        let nonInterleaved = isNonInterleaved
        let bytesPerSample = kind.bytesPerSample
        guard bytesPerSample > 0 else {
            lock.unlock()
            return
        }

        var framesToRead = min(frameCount, 8_192)
        for buffer in buffers {
            guard buffer.mData != nil else { continue }
            let channels = max(1, Int(buffer.mNumberChannels))
            let availableSamples = Int(buffer.mDataByteSize) / bytesPerSample
            let availableFrames = nonInterleaved ? availableSamples : availableSamples / channels
            framesToRead = min(framesToRead, availableFrames)
        }
        guard framesToRead > 0 else {
            lock.unlock()
            return
        }

        var sumPower: Float = 0
        var sumBass: Float = 0
        var sumLowMid: Float = 0
        var sumMid: Float = 0
        var sumVocal: Float = 0
        var sumTreble: Float = 0
        var samplesProcessed = 0

        for frame in 0..<framesToRead {
            var channelSum: Float = 0
            var channelCount = 0

            for buffer in buffers {
                guard let raw = buffer.mData else { continue }
                let channels = max(1, Int(buffer.mNumberChannels))
                let firstIndex = nonInterleaved ? frame : frame * channels
                let channelLimit = nonInterleaved ? 1 : channels

                for channel in 0..<channelLimit {
                    let index = firstIndex + channel
                    let value: Float
                    switch kind {
                    case .float32:
                        value = raw.assumingMemoryBound(to: Float.self)[index]
                    case .int16:
                        value = Float(raw.assumingMemoryBound(to: Int16.self)[index]) / 32_768
                    case .int32:
                        value = Float(Double(raw.assumingMemoryBound(to: Int32.self)[index]) / 2_147_483_648.0)
                    case .unsupported:
                        value = 0
                    }
                    if value.isFinite {
                        channelSum += max(-1, min(1, value))
                        channelCount += 1
                    }
                }
            }

            guard channelCount > 0 else { continue }
            let x = channelSum / Float(channelCount)
            lp150 += alpha150 * (x - lp150)
            lp400 += alpha400 * (x - lp400)
            lp1200 += alpha1200 * (x - lp1200)
            lp3500 += alpha3500 * (x - lp3500)
            lp12000 += alpha12000 * (x - lp12000)

            let bass = lp150
            let lowMid = lp400 - lp150
            let mid = lp1200 - lp400
            let vocal = lp3500 - lp1200
            let treble = lp12000 - lp3500

            sumPower += x * x
            sumBass += bass * bass
            sumLowMid += lowMid * lowMid
            sumMid += mid * mid
            sumVocal += vocal * vocal
            sumTreble += treble * treble
            samplesProcessed += 1
        }

        guard samplesProcessed > 0 else {
            lock.unlock()
            return
        }

        let count = Float(samplesProcessed)
        let envelopeAlpha: Float = 0.28
        smoothedPower += envelopeAlpha * (sqrt(sumPower / count) - smoothedPower)
        smoothedBass += envelopeAlpha * (sqrt(sumBass / count) - smoothedBass)
        smoothedLowMid += envelopeAlpha * (sqrt(sumLowMid / count) - smoothedLowMid)
        smoothedMid += envelopeAlpha * (sqrt(sumMid / count) - smoothedMid)
        smoothedVocal += envelopeAlpha * (sqrt(sumVocal / count) - smoothedVocal)
        smoothedTreble += envelopeAlpha * (sqrt(sumTreble / count) - smoothedTreble)

        let now = ProcessInfo.processInfo.systemUptime
        let shouldPublish = now - lastPublishTime >= 0.05
        if shouldPublish { lastPublishTime = now }
        let result = FoliaAudioBands(
            power: Double(max(0, min(1, smoothedPower))),
            bass: Double(max(0, min(1, smoothedBass))),
            lowMid: Double(max(0, min(1, smoothedLowMid))),
            mid: Double(max(0, min(1, smoothedMid))),
            vocal: Double(max(0, min(1, smoothedVocal))),
            treble: Double(max(0, min(1, smoothedTreble)))
        )
        lock.unlock()

        guard shouldPublish else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onBands?(result)
        }
    }
}
