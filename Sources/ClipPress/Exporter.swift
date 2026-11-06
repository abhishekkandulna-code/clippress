import AVFoundation
import CoreMedia
import VideoToolbox

// MARK: - Settings

protocol SegmentOption: Hashable, CaseIterable, Identifiable where AllCases == [Self] {
    var title: String { get }
}

extension SegmentOption {
    var id: Self { self }
}

enum Quality: SegmentOption {
    case smaller, balanced, better

    var title: String {
        switch self {
        case .smaller: return "Smaller"
        case .balanced: return "Balanced"
        case .better: return "Better"
        }
    }

    var hint: String {
        switch self {
        case .smaller: return "Smallest file. Fine for chat apps and email."
        case .balanced: return "Looks close to the original at a fraction of the size."
        case .better: return "Keeps fine detail. Larger file."
        }
    }

    /// H.264 bits per pixel per frame. Higher keeps more detail.
    var bitsPerPixel: Double {
        switch self {
        case .smaller: return 0.04
        case .balanced: return 0.07
        case .better: return 0.11
        }
    }

    /// VideoToolbox constant-quality value (0–1). Balanced matches the reference
    /// (HandBrake "Fast 1080p30", x264 CRF 22); HandBrake pairs CRF 22 with 0.60 on this encoder.
    var constantQuality: Double {
        switch self {
        case .smaller: return 0.50
        case .balanced: return 0.60
        case .better: return 0.70
        }
    }

    /// AAC-LC, 48 kHz stereo. The reference uses 160 kbps.
    var audioBitrate: Int { self == .smaller ? 96_000 : 160_000 }
}

enum Codec: SegmentOption {
    case h264, hevc

    var title: String { self == .h264 ? "H.264" : "HEVC" }

    var hint: String {
        switch self {
        case .h264: return "Plays on every device and website."
        case .hevc: return "About 40% smaller. Needs a 2017 or newer device."
        }
    }

    var avType: AVVideoCodecType { self == .h264 ? .h264 : .hevc }

    /// HEVC reaches the same quality with roughly 60% of H.264's bitrate.
    var efficiency: Double { self == .h264 ? 1.0 : 0.6 }
}

enum Resolution: SegmentOption {
    case original, p1080, p720, p480

    var title: String {
        switch self {
        case .original: return "Original"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        }
    }

    var shortSide: CGFloat? {
        switch self {
        case .original: return nil
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        }
    }
}

struct ExportSettings: Equatable {
    var quality: Quality = .balanced
    var codec: Codec = .h264
    var resolution: Resolution = .original
    /// Playback speed for the whole timeline: 2 plays twice as fast, 0.5 at half speed.
    var speed: Double = 1
    /// Audio gain for the whole timeline: 0 removes the sound, 1 keeps it as recorded.
    var volume: Double = 1

    static let speedRange: ClosedRange<Double> = 0.1...10
    static let volumeRange: ClosedRange<Double> = 0...4
}

// MARK: - Plan

/// The concrete output numbers for a set of clips. Drives both the size estimate and the encode.
struct ExportPlan {
    let renderSize: CGSize
    let frameRate: Double
    let videoBitrate: Int
    let audioBitrate: Int
    let constantQuality: Double
    /// Length of the output, after the speed change.
    let duration: Double
    let speed: Double
    let volume: Float
    let includesAudio: Bool

    /// Above this length the MP4 is not rewritten for fast web start: on multi-hour files that
    /// pass takes minutes with no progress and briefly needs twice the disk space.
    static let fastStartLimit: Double = 60 * 60

    var optimizesForStreaming: Bool { duration < Self.fastStartLimit }

    var estimatedBytes: Int64 {
        Int64(Double(videoBitrate + audioBitrate) * duration / 8 * 1.02)
    }

    init?(clips: [Clip], settings: ExportSettings) {
        guard let largest = clips.max(by: { $0.displaySize.width * $0.displaySize.height < $1.displaySize.width * $1.displaySize.height }) else {
            return nil
        }

        var size = largest.displaySize
        if let target = settings.resolution.shortSide {
            let shortSide = min(size.width, size.height)
            if shortSide > target {
                size = CGSize(width: size.width * target / shortSide, height: size.height * target / shortSide)
            }
        }
        renderSize = CGSize(width: Self.even(size.width), height: Self.even(size.height))

        let fastest = Double(clips.map(\.frameRate).max() ?? 0)
        // Peak frame rate 30, like the reference: 60 fps screen recordings drop to 30.
        frameRate = fastest > 0 ? min(fastest, Self.maxFrameRate) : Self.maxFrameRate
        let sourceDuration = clips.reduce(0) { $0 + $1.duration.seconds }
        speed = settings.speed
        duration = sourceDuration / settings.speed
        volume = Float(settings.volume)
        constantQuality = settings.quality.constantQuality

        includesAudio = settings.volume > 0 && clips.contains { $0.audio != nil }
        audioBitrate = includesAudio ? settings.quality.audioBitrate : 0

        var bitrate = Double(renderSize.width * renderSize.height) * frameRate
            * settings.quality.bitsPerPixel * settings.codec.efficiency
        // Never spend more bits than the sources already use; that only makes the file bigger.
        let sourceRate = clips.reduce(0.0) { $0 + Double($1.videoDataRate) * $1.duration.seconds } / max(sourceDuration, 0.001)
        if sourceRate > 0 {
            bitrate = min(bitrate, sourceRate * 0.9)
        }
        videoBitrate = Int(max(bitrate, 250_000))
    }

    static let maxFrameRate: Double = 30

    private static func even(_ value: CGFloat) -> CGFloat {
        max(2, (value / 2).rounded() * 2)
    }
}

// MARK: - Exporter

enum ExportError: LocalizedError {
    case failed

    var errorDescription: String? { "The video encoder stopped unexpectedly." }
}

/// Joins clips end to end and re-encodes them with the hardware encoder (VideoToolbox).
final class Exporter: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var reader: AVAssetReader?

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let reader = self.reader
        lock.unlock()
        reader?.cancelReading()
    }

    func export(
        _ clips: [Clip],
        plan: ExportPlan,
        codec: Codec,
        to url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let (composition, videoComposition) = try Self.makeComposition(clips, plan: plan)

        try? FileManager.default.removeItem(at: url)
        let reader = try AVAssetReader(asset: composition)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = plan.optimizesForStreaming

        let videoTracks = composition.tracks(withMediaType: .video)
        let videoOutput: AVAssetReaderOutput
        if Self.canSkipCompositing(clips, plan: plan), let track = videoTracks.first {
            // Fast path: hardware decoder → hardware encoder. No GPU render pass, no pixel copies.
            videoOutput = AVAssetReaderTrackOutput(track: track, outputSettings: Self.frameFormat)
        } else {
            let output = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: Self.frameFormat)
            output.videoComposition = videoComposition
            videoOutput = output
        }
        videoOutput.alwaysCopiesSampleData = false
        reader.add(videoOutput)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: Self.bestVideoSettings(plan, codec, for: writer))
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)

        var audio: (output: AVAssetReaderAudioMixOutput, input: AVAssetWriterInput)?
        let audioTracks = composition.tracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: Self.pcmSettings)
            // Own copies, because the volume change rewrites the samples in place.
            output.alwaysCopiesSampleData = true
            // Keep voices at their normal pitch when the speed changes.
            output.audioTimePitchAlgorithm = .spectral
            reader.add(output)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.aacSettings(plan.audioBitrate))
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audio = (output, input)
        }

        lock.lock()
        self.reader = reader
        let cancelledEarly = cancelled
        lock.unlock()
        if cancelledEarly { throw CancellationError() }

        guard reader.startReading() else { throw reader.error ?? ExportError.failed }
        guard writer.startWriting() else { throw writer.error ?? ExportError.failed }
        writer.startSession(atSourceTime: .zero)

        let total = max(plan.duration, 0.001)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()

            var lastReported = -1.0
            // Peak frame rate: skip frames that arrive sooner than 1/30 s after the last kept one,
            // so 60 fps sources encode half the frames. 1 ms of slack absorbs timestamp jitter.
            let minFrameGap = 1 / ExportPlan.maxFrameRate - 0.001
            var lastKept = -Double.infinity
            pump(videoOutput, into: videoInput, reader: reader, writer: writer,
                 queue: DispatchQueue(label: "ClipPress.video"), group: group) { sample in
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                let fraction = min(1, time / total)
                // 0.1% steps: on a 5-hour timeline that is still an update every 18 s of video.
                if fraction - lastReported >= 0.001 {
                    lastReported = fraction
                    progress(fraction)
                }
                guard time - lastKept >= minFrameGap else { return false }
                lastKept = time
                return true
            }
            if let audio {
                let gain = plan.volume
                pump(audio.output, into: audio.input, reader: reader, writer: writer,
                     queue: DispatchQueue(label: "ClipPress.audio"), group: group,
                     shouldAppend: gain == 1 ? nil : { sample in
                         Self.applyGain(gain, to: sample)
                         return true
                     })
            }

            group.notify(queue: .global(qos: .userInitiated)) { [self] in
                func abandon(_ error: Error) {
                    if writer.status == .writing { writer.cancelWriting() }
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(throwing: error)
                }

                if writer.status == .failed || reader.status == .failed {
                    abandon(writer.error ?? reader.error ?? ExportError.failed)
                } else if isCancelled || reader.status == .cancelled {
                    abandon(CancellationError())
                } else {
                    writer.finishWriting {
                        if writer.status == .completed {
                            progress(1)
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: writer.error ?? ExportError.failed)
                        }
                    }
                }
            }
        }
    }

    /// Moves samples from a reader output to a writer input until the source runs dry.
    /// `shouldAppend` sees every sample and can drop one by returning false.
    private func pump(
        _ output: AVAssetReaderOutput,
        into input: AVAssetWriterInput,
        reader: AVAssetReader,
        writer: AVAssetWriter,
        queue: DispatchQueue,
        group: DispatchGroup,
        shouldAppend: ((CMSampleBuffer) -> Bool)?
    ) {
        group.enter()
        let state = PumpState()
        input.requestMediaDataWhenReady(on: queue) {
            while !state.finished && input.isReadyForMoreMediaData {
                // Drain AVFoundation's temporary objects every sample, or a multi-hour export
                // keeps them alive until the writer pauses.
                let more = autoreleasepool { () -> Bool in
                    guard let sample = output.copyNextSampleBuffer() else {
                        if writer.status == .writing { input.markAsFinished() }
                        return false
                    }
                    if let shouldAppend, !shouldAppend(sample) { return true }
                    if !input.append(sample) {
                        // The writer failed; stop the other track too so the export can finish.
                        reader.cancelReading()
                        return false
                    }
                    return true
                }
                if !more {
                    state.finished = true
                    group.leave()
                    return
                }
            }
        }
    }

    /// Scales 32-bit float PCM in place, clipping anything boosted past full scale.
    private static func applyGain(_ gain: Float, to sample: CMSampleBuffer) {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
        guard count > 0 else { return }
        let byteCount = count * MemoryLayout<Float>.size

        var samples = [Float](repeating: 0, count: count)
        samples.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress,
                  CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: base) == kCMBlockBufferNoErr
            else { return }
            let floats = bytes.bindMemory(to: Float.self)
            for index in floats.indices {
                floats[index] = min(max(floats[index] * gain, -1), 1)
            }
            CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        }
    }

    /// Only touched from the pump's own serial queue.
    private final class PumpState: @unchecked Sendable {
        var finished = false
    }

    // MARK: Composition

    static func makeComposition(_ clips: [Clip], plan: ExportPlan) throws -> (AVMutableComposition, AVMutableVideoComposition) {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.failed
        }
        let audioTrack = plan.includesAudio
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

        var instructions: [AVVideoCompositionInstructionProtocol] = []
        var cursor = CMTime.zero

        for clip in clips {
            let length = clip.duration
            try videoTrack.insertTimeRange(clip.videoRange, of: clip.video, at: cursor)

            if let audioTrack {
                if let source = clip.audio, clip.audioRange.duration > .zero {
                    let audioLength = CMTimeMinimum(clip.audioRange.duration, length)
                    try audioTrack.insertTimeRange(
                        CMTimeRange(start: clip.audioRange.start, duration: audioLength), of: source, at: cursor
                    )
                    if audioLength < length {
                        audioTrack.insertEmptyTimeRange(CMTimeRange(start: cursor + audioLength, duration: length - audioLength))
                    }
                } else {
                    // Silent clip: keep the audio in step with the picture.
                    audioTrack.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: length))
                }
            }

            // Speed change: stretch or squeeze this clip's picture and sound together. A fine
            // timescale keeps the rounding error over a 5-hour timeline well under a frame.
            var outputLength = length
            if plan.speed != 1 {
                outputLength = CMTimeConvertScale(
                    CMTimeMultiplyByFloat64(length, multiplier: 1 / plan.speed),
                    timescale: 600_000, method: .roundHalfAwayFromZero
                )
                composition.scaleTimeRange(CMTimeRange(start: cursor, duration: length), toDuration: outputLength)
            }

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layer.setTransform(fitTransform(for: clip, in: plan.renderSize), at: cursor)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: outputLength)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)

            cursor = cursor + outputLength
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = plan.renderSize
        videoComposition.frameDuration = CMTime(seconds: 1 / plan.frameRate, preferredTimescale: 600_000)
        videoComposition.instructions = instructions
        // Render in standard SDR colour so HDR phone footage doesn't come out washed out.
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        return (composition, videoComposition)
    }

    /// Rotates the clip upright, then scales it to fit the frame, centred with black bars.
    private static func fitTransform(for clip: Clip, in renderSize: CGSize) -> CGAffineTransform {
        let rotated = CGRect(origin: .zero, size: clip.naturalSize).applying(clip.transform)
        let scale = min(renderSize.width / rotated.width, renderSize.height / rotated.height)
        let offsetX = (renderSize.width - rotated.width * scale) / 2
        let offsetY = (renderSize.height - rotated.height * scale) / 2
        return clip.transform
            .concatenating(CGAffineTransform(translationX: -rotated.minX, y: -rotated.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
    }

    // MARK: Encoder settings

    /// 4:2:0 video-range YUV: what the hardware decoder emits and the hardware encoder consumes,
    /// so no colour conversion happens in between. 12 bits per pixel instead of BGRA's 32,
    /// which matters on an 8 GB Mac: a 3360×2100 frame is 10.6 MB instead of 28 MB.
    private static let frameFormat: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ]

    /// Frames can skip the GPU render pass when it would change nothing: every clip is already
    /// the output size, upright, and standard SDR colour. A speed change always goes through the
    /// compositor, which resamples the stretched timeline onto an even frame grid.
    private static func canSkipCompositing(_ clips: [Clip], plan: ExportPlan) -> Bool {
        plan.speed == 1
            && clips.allSatisfy { $0.transform.isIdentity && $0.naturalSize == plan.renderSize && $0.isRec709 }
    }

    private static var supportsConstantQuality: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// Trade a little compression efficiency for encode speed (HandBrake's VideoToolbox presets do the same).
    private static let prioritizeSpeed = true

    /// The best settings this Mac's encoder accepts, most preferred first:
    /// constant quality needs Apple silicon, the speed hint needs macOS 12+.
    private static func bestVideoSettings(_ plan: ExportPlan, _ codec: Codec, for writer: AVAssetWriter) -> [String: Any] {
        let candidates = [(true, prioritizeSpeed), (true, false), (false, prioritizeSpeed), (false, false)]
            .filter { supportsConstantQuality || !$0.0 }
        for (quality, speed) in candidates {
            let settings = videoSettings(plan, codec, constantQuality: quality, prioritizeSpeed: speed)
            if writer.canApply(outputSettings: settings, forMediaType: .video) { return settings }
        }
        return videoSettings(plan, codec, constantQuality: false, prioritizeSpeed: false)
    }

    /// Mirrors the reference encode (HandBrake "Fast 1080p30") as closely as VideoToolbox allows:
    /// H.264 Main + CABAC + B-frames, keyframe at most every 10 s, constant quality, BT.709.
    /// The level is automatic because source-resolution output (e.g. 3360×2100) exceeds Main 4.0.
    private static func videoSettings(
        _ plan: ExportPlan, _ codec: Codec, constantQuality: Bool, prioritizeSpeed: Bool
    ) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoExpectedSourceFrameRateKey: plan.frameRate,
            AVVideoMaxKeyFrameIntervalKey: Int((plan.frameRate * 10).rounded()),
            AVVideoMaxKeyFrameIntervalDurationKey: 10,
            AVVideoAllowFrameReorderingKey: true,
        ]
        if constantQuality {
            compression[AVVideoQualityKey] = plan.constantQuality
        } else {
            compression[AVVideoAverageBitRateKey] = plan.videoBitrate
        }
        if prioritizeSpeed {
            compression[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] = true
        }
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264MainAutoLevel
            compression[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC
        }
        return [
            AVVideoCodecKey: codec.avType,
            AVVideoWidthKey: Int(plan.renderSize.width),
            AVVideoHeightKey: Int(plan.renderSize.height),
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
    }

    private static let stereoLayout: Data = {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }()

    /// Decode every clip to the same stereo 48 kHz PCM so clips with different audio can be joined.
    /// Float samples, so the volume change can boost and clip without integer overflow.
    private static let pcmSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVChannelLayoutKey: stereoLayout,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    private static func aacSettings(_ bitrate: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVChannelLayoutKey: stereoLayout,
            AVEncoderBitRateKey: bitrate,
        ]
    }
}
