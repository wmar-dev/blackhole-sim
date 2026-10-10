import Foundation

/// Compression quality presets shared by both encoders (research D1).
public enum MovieQuality: String, CaseIterable, Sendable, Codable {
    case high, standard, small

    /// Constant rate factor of the ffmpeg (libx264) encoder; lower is better.
    public var crf: Int {
        switch self {
        case .high: return 16
        case .standard: return 18
        case .small: return 23
        }
    }

    /// Lowest average bit rate of the AVFoundation encoder in bits per second: small pictures need more bits per pixel
    /// than the proportional rule gives (calibrated in research.md, "AVFoundation bit-rate calibration").
    public var minimumBitRate: Int {
        switch self {
        case .high: return 2_000_000
        case .standard: return 1_000_000
        case .small: return 500_000
        }
    }

    /// Average bit rate of the AVFoundation encoder, in bits per pixel per frame (never below `minimumBitRate`).
    public var bitsPerPixelPerFrame: Double {
        switch self {
        case .high: return 0.35
        case .standard: return 0.25
        case .small: return 0.12
        }
    }
}

public enum EncoderChoice: String, CaseIterable, Sendable {
    case auto, ffmpeg, avfoundation
}

/// What an encoder is and what it guarantees; stored in the movie record.
public struct EncoderInfo: Sendable, Equatable, Codable {
    public var name: String
    public var version: String
    public var quality: String
    /// For example `crf=18` or `bitsPerPixel=0.25`.
    public var setting: String
    /// True if the file bytes repeat exactly for the same inputs, machine and encoder version.
    public var reproducibleFile: Bool
}

/// Turns PNG frames, given one at a time, into a movie file.
public protocol MovieEncoder: AnyObject, Sendable {
    func describe(quality: MovieQuality) -> EncoderInfo
    /// Starts a movie at `output` (which must not exist). Width and height are even.
    func begin(width: Int, height: Int, fps: Double, quality: MovieQuality, output: URL) throws
    func append(frame: URL) throws
    /// Completes the file. After an error or `cancel` no usable file is left at the output path.
    func finish() throws
    func cancel()
}

public enum EncoderSelection {
    /// Where to look for ffmpeg: the `PATH`, then the usual Homebrew and local install folders.
    public static var defaultSearchPaths: [String] {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return path + ["/opt/homebrew/bin", "/usr/local/bin"]
    }

    /// Chooses an encoder (research D1). `auto` prefers a usable ffmpeg and otherwise uses AVFoundation; `ffmpeg` fails
    /// with `encoderUnavailable` if none is usable (no silent fallback).
    public static func select(_ choice: EncoderChoice, ffmpegPath: String? = nil, searchPaths: [String]? = nil) throws -> any MovieEncoder {
        switch choice {
        case .avfoundation:
            return AVFoundationEncoder()
        case .ffmpeg:
            return FFmpegEncoder(location: try FFmpegEncoder.locate(explicit: ffmpegPath, searchPaths: searchPaths ?? defaultSearchPaths))
        case .auto:
            if let location = try? FFmpegEncoder.locate(explicit: ffmpegPath, searchPaths: searchPaths ?? defaultSearchPaths) {
                return FFmpegEncoder(location: location)
            }
            return AVFoundationEncoder()
        }
    }
}
