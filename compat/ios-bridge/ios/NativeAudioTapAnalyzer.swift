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

/// AVPlayer audio-mix tap. It performs lightweight one-pole low-pass splits at
/// the same five cutoff labels visible in the supplied build-379 symbol table
/// (150, 400, 1200, 3500, 12000 Hz). Per-band energies are computed from the
/// differences between adjacent low-pass outputs.
///
/// The exact original DSP, sample scaling and smoothing constants are not
/// recoverable from symbol names alone. Host code must test values on-device.
public final class NativeAudioTapAnalyzer {
    private enum SampleKind {
        case float32
        case int16
        case int32
        case unsupported
    }

    private let lock = NSLock()
    private var activeTap: MTAudioProcessingTap?
    private var sampleKind: SampleKind = .unsupported
    private var sampleRate: Double = 44_100
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
    private var smoothed: [Float] = Array(repeating: 0, count: 6)

    /// Called on the main queue, throttled to at most 20 updates per second.
    public var onBands: ((FoliaAudioBands) -> Void)?

    public init() {}

    deinit {
        activeTap = nil
    }

    public func makeAudioMix(for track: AVAssetTrack) throws -> AVAudioMix {
        reset()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { _ in },
            prepare: { tap, _, processingFormat in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let analyzer = Unmanaged<NativeAudioTapAnalyzer>.fromOpaque(storage).takeUnretainedValue()
                analyzer.prepare(format: processingFormat.pointee)
            },
            unprepare: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let analyzer = Unmanaged<NativeAudioTapAnalyzer>.fromOpaque(storage).takeUnretainedValue()
                analyzer.reset()
            },
            process: { tap, frameCount, _, bufferList, frameCountOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(
                    tap, frameCount, bufferList, flagsOut, nil, frameCountOut
                )
                guard status == noErr,
                      status == noErr else { return }
                let storage = MTAudioProcessingTapGetStorage(tap)
                let analyzer = Unmanaged<NativeAudioTapAnalyzer>.fromOpaque(storage).takeUnretainedValue()
                analyzer.process(bufferList, frameCount: Int(frameCountOut.pointee))
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
            throw NSError(
                domain: "FoliaAudioTap",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "audio-tap-create-failed"]
            )
        }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = createdTap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        lock.lock()
        activeTap = createdTap
        lock.unlock()
        return mix
    }

    /// Release the analyzer's strong tap reference when its AVPlayerItem is replaced.
    public func reset() {
        lock.lock()
        lp150 = 0
        lp400 = 0
        lp1200 = 0
        lp3500 = 0
        lp12000 = 0
        smoothed = Array(repeating: 0, count: 6)
        lastPublishTime = 0
        lock.unlock()
        activeTap = nil
    }

    private func prepare(format: AudioStreamBasicDescription) {
        lock.lock()
        defer { lock.unlock() }
        sampleRate = format.mSampleRate.isFinite && format.mSampleRate > 0
            ? format.mSampleRate : 44_100
        let flags = format.mFormatFlags
        isNonInterleaved = (flags & kAudioFormatFlagIsNonInterleaved) != 0
        if (flags & kAudioFormatFlagIsFloat) != 0 && format.mBitsPerChannel == 32 {
            sampleKind = .float32
        } else if format.mBitsPerChannel == 16 {
            sampleKind = .int16
        } else if format.mBitsPerChannel == 32 {
            sampleKind = .int32
        } else {
            sampleKind = .unsupported
        }

        func coefficient(_ cutoff: Double) -> Float {
            let safeCutoff = min(cutoff, sampleRate * 0.45)
            return Float(1.0 - exp(-2.0 * Double.pi * safeCutoff / sampleRate))
        }
        alpha150 = coefficient(150)
        alpha400 = coefficient(400)
        alpha1200 = coefficient(1_200)
        alpha3500 = coefficient(3_500)
        alpha12000 = coefficient(12_000)
    }

    private func process(_ listPointer: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard frameCount > 0 else { return }
        var samples = [Float]()
        samples.reserveCapacity(min(frameCount, 8_192))

        lock.lock()
        let kind = sampleKind
        let nonInterleaved = isNonInterleaved
        lock.unlock()
        guard kind != .unsupported else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(listPointer)
        let framesToRead = min(frameCount, 8_192)
        for frame in 0..<framesToRead {
            var sum: Float = 0
            var channelCount = 0
            for buffer in buffers {
                guard let raw = buffer.mData else { continue }
                let channels = max(1, Int(buffer.mNumberChannels))
                let first = nonInterleaved ? frame : frame * channels
                for channel in 0..<(nonInterleaved ? 1 : channels) {
                    let index = first + channel
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
                        sum += max(-1, min(1, value))
                        channelCount += 1
                    }
                }
            }
            if channelCount > 0 { samples.append(sum / Float(channelCount)) }
        }

        guard !samples.isEmpty else { return }
        lock.lock()
        var sumPower: Float = 0
        var sumBass: Float = 0
        var sumLowMid: Float = 0
        var sumMid: Float = 0
        var sumVocal: Float = 0
        var sumTreble: Float = 0

        for sample in samples {
            let x = sample
            lp150 += alpha150 * (x - lp150)
            lp400 += alpha400 * (x - lp400)
            lp1200 += alpha1200 * (x - lp1200)
            lp3500 += alpha3500 * (x - lp3500)
            lp12000 += alpha12000 * (x - lp12000)

            let bands = [
                lp150,
                lp400 - lp150,
                lp1200 - lp400,
                lp3500 - lp1200,
                lp12000 - lp3500
            ]
            sumPower += x * x
            sumBass += bands[0] * bands[0]
            sumLowMid += bands[1] * bands[1]
            sumMid += bands[2] * bands[2]
            sumVocal += bands[3] * bands[3]
            sumTreble += bands[4] * bands[4]
        }

        let count = Float(samples.count)
        let raw: [Float] = [
            sqrt(sumPower / count),
            sqrt(sumBass / count),
            sqrt(sumLowMid / count),
            sqrt(sumMid / count),
            sqrt(sumVocal / count),
            sqrt(sumTreble / count)
        ]
        // Smooth the output envelope without changing the underlying audio buffers.
        let envelopeAlpha: Float = 0.28
        for index in raw.indices {
            smoothed[index] += envelopeAlpha * (raw[index] - smoothed[index])
        }
        let now = ProcessInfo.processInfo.systemUptime
        let shouldPublish = now - lastPublishTime >= 0.05
        if shouldPublish { lastPublishTime = now }
        let values = smoothed.map { Double(max(0, min(1, $0))) }
        lock.unlock()

        guard shouldPublish else { return }
        let result = FoliaAudioBands(
            power: values[0], bass: values[1], lowMid: values[2],
            mid: values[3], vocal: values[4], treble: values[5]
        )
        DispatchQueue.main.async { [weak self] in
            self?.onBands?(result)
        }
    }
}
