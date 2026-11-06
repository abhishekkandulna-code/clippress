import AVFoundation
import AppKit

enum ClipError: LocalizedError {
    case noVideo
    case empty

    var errorDescription: String? {
        switch self {
        case .noVideo: return "The file has no video track."
        case .empty: return "The video is empty."
        }
    }
}

/// One source video, with everything the exporter and the UI need already loaded.
/// Immutable after `load`, so it is safe to hand across tasks.
struct Clip: Identifiable, @unchecked Sendable {
    let id = UUID()
    let url: URL
    let asset: AVURLAsset
    let video: AVAssetTrack
    let videoRange: CMTimeRange
    let naturalSize: CGSize
    let transform: CGAffineTransform
    let frameRate: Float
    let videoDataRate: Float
    /// Standard SDR (BT.709 or untagged). HDR and wide-gamut clips need a colour conversion pass.
    let isRec709: Bool
    let audio: AVAssetTrack?
    let audioRange: CMTimeRange
    let fileSize: Int64
    let thumbnail: NSImage?

    var name: String { url.lastPathComponent }
    var duration: CMTime { videoRange.duration }

    /// Size as it appears on screen, after rotation (portrait phone videos are stored sideways).
    var displaySize: CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    static func load(_ url: URL) async throws -> Clip {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw ClipError.noVideo
        }
        let (naturalSize, transform, frameRate, dataRate, videoRange, formats) = try await video.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate, .timeRange, .formatDescriptions
        )
        guard videoRange.duration.seconds > 0 else { throw ClipError.empty }

        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let audioRange = try await audio?.load(.timeRange) ?? .zero
        let fileSize = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 144)
        let posterTime = CMTime(seconds: min(1, videoRange.duration.seconds / 2), preferredTimescale: 600)
        let thumbnail = (try? await generator.image(at: posterTime).image)
            .map { NSImage(cgImage: $0, size: .zero) }

        return Clip(
            url: url, asset: asset, video: video, videoRange: videoRange,
            naturalSize: naturalSize, transform: transform, frameRate: frameRate,
            videoDataRate: dataRate, isRec709: formats.allSatisfy(hasStandardColor), audio: audio, audioRange: audioRange,
            fileSize: fileSize, thumbnail: thumbnail
        )
    }

    /// True when every colour tag is BT.709 or missing (untagged video is treated as BT.709).
    private static func hasStandardColor(_ format: CMFormatDescription) -> Bool {
        let expected: [(key: CFString, value: CFString)] = [
            (kCMFormatDescriptionExtension_ColorPrimaries, kCMFormatDescriptionColorPrimaries_ITU_R_709_2),
            (kCMFormatDescriptionExtension_TransferFunction, kCMFormatDescriptionTransferFunction_ITU_R_709_2),
            (kCMFormatDescriptionExtension_YCbCrMatrix, kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2),
        ]
        return expected.allSatisfy { tag in
            guard let value = CMFormatDescriptionGetExtension(format, extensionKey: tag.key) as? String else { return true }
            return value == tag.value as String
        }
    }
}
