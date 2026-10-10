import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Reads a movie back for verification (tests and the `assemble` self-check). It does not depend on how the file was made.
public final class MovieReader: @unchecked Sendable {
    public struct ColourTags: Sendable, Equatable {
        public var primaries: String?
        public var transfer: String?
        public var matrix: String?
    }

    public let url: URL
    public let width: Int
    public let height: Int
    public let frameCount: Int
    public let duration: Double
    public let fps: Double
    public let colour: ColourTags
    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private let presentationTimes: [CMTime]

    private init(url: URL, asset: AVURLAsset, track: AVAssetTrack, size: CGSize, duration: Double, fps: Double, colour: ColourTags, times: [CMTime]) {
        self.url = url; self.asset = asset; self.track = track
        width = Int(size.width.rounded()); height = Int(size.height.rounded())
        frameCount = times.count; self.duration = duration; self.fps = fps; self.colour = colour; presentationTimes = times
    }

    public static func open(_ url: URL) async throws -> MovieReader {
        guard FileManager.default.fileExists(atPath: url.path) else { throw MovieError.cannotWrite("\(url.path) does not exist") }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MovieError.encodingFailed("\(url.path) has no video track")
        }
        let (size, rate, formats) = try await track.load(.naturalSize, .nominalFrameRate, .formatDescriptions)
        let duration = try await asset.load(.duration).seconds

        var tags = ColourTags()
        if let format = formats.first, let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any] {
            tags.primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
            tags.transfer = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
            tags.matrix = extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String
        }

        // Presentation times of the frames that are displayed: decode through the reader, which drops samples that are
        // not shown (compressed samples can include such frames).
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? MovieError.encodingFailed("cannot read \(url.path)") }
        var times: [CMTime] = []
        while let sample = output.copyNextSampleBuffer() { times.append(CMSampleBufferGetPresentationTimeStamp(sample)) }
        times.sort { $0.seconds < $1.seconds }
        return MovieReader(url: url, asset: asset, track: track, size: size, duration: duration, fps: Double(rate), colour: tags, times: times)
    }

    /// Decodes frame `index` (0-based, playing order) to RGB8 (sRGB, top row first).
    public func frame(at index: Int) async throws -> [UInt8] {
        guard presentationTimes.indices.contains(index) else { throw MovieError.encodingFailed("frame \(index) is outside the movie (\(frameCount) frames)") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        let start = presentationTimes[index]
        let end = index + 1 < presentationTimes.count ? presentationTimes[index + 1] : CMTimeAdd(start, CMTime(seconds: 1 / max(fps, 1), preferredTimescale: 600))
        reader.timeRange = CMTimeRange(start: start, end: end)
        guard reader.startReading() else { throw reader.error ?? MovieError.encodingFailed("cannot decode frame \(index)") }
        guard let sample = output.copyNextSampleBuffer(), let pixels = CMSampleBufferGetImageBuffer(sample) else {
            throw MovieError.encodingFailed("cannot decode frame \(index)")
        }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        var rgb = [UInt8](); rgb.reserveCapacity(width * height * 3)
        for y in 0..<height { for x in 0..<width {
            let p = base + y * stride + x * 4
            rgb.append(p[2]); rgb.append(p[1]); rgb.append(p[0])
        } }
        return rgb
    }
}
