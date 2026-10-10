import Foundation
import ImageIO

/// Errors of the movie feature. The messages name the problem and the first offending item (FR-004, spec edge cases).
public enum MovieError: Error, LocalizedError, Equatable, Sendable {
    case folderMissing(String)
    case noFrames(folder: String, prefix: String?)
    case mixedPrefixes([String])
    case gap(missing: Int, after: Int)
    case duplicateNumber(Int)
    case sizeMismatch(file: String, found: String, expected: String)
    case oddDimensions(width: Int, height: Int)
    case unreadableFrame(String)
    case invalidOption(String)
    case invalidAnimation(frame: Int, of: Int, parameter: String, value: Double, reason: String)
    case outputExists(String)
    case encoderUnavailable(String)
    case encodingFailed(String)
    case cannotWrite(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .folderMissing(let folder):
            return "the frames folder \(folder) does not exist"
        case .noFrames(let folder, let prefix):
            return "no frames found in \(folder): expected files named \(prefix ?? "<prefix>")<number>.png (for example frame_0001.png)"
        case .mixedPrefixes(let prefixes):
            return "the folder holds frames with different name prefixes (\(prefixes.map { "'\($0)'" }.joined(separator: ", "))); choose one with --prefix"
        case .gap(let missing, let after):
            return "frame number \(missing) is missing (the numbers jump after \(after)); add the frame or use --allow-gaps to play the frames that exist"
        case .duplicateNumber(let number):
            return "frame number \(number) appears in more than one file (for example frame_\(number).png and frame_0\(number).png)"
        case .sizeMismatch(let file, let found, let expected):
            return "\(file) is \(found) pixels but the first frame is \(expected); all frames must have the same size"
        case .oddDimensions(let width, let height):
            return "the frames are \(width)x\(height) pixels; the video format needs an even width and height (for example \(width + width % 2)x\(height + height % 2))"
        case .unreadableFrame(let file):
            return "could not read \(file) as a PNG image"
        case .invalidOption(let text):
            return text
        case .invalidAnimation(let frame, let total, let parameter, let value, let reason):
            return "frame \(frame) of \(total) (\(parameter) = \(String(format: "%.4g", value))) is not a valid render: \(reason)"
        case .outputExists(let path):
            return "\(path) already exists; choose another name or pass --force to overwrite it"
        case .encoderUnavailable(let text):
            return text
        case .encodingFailed(let text):
            return "the video could not be encoded: \(text)"
        case .cannotWrite(let text):
            return text
        case .cancelled:
            return "cancelled"
        }
    }
}

/// An ordered set of numbered PNG frames of equal, even size (data-model.md).
public struct FrameSequence: Sendable, Equatable {
    public let folder: URL
    public let prefix: String
    /// Frame numbers in playing order.
    public let numbers: [Int]
    /// Files in playing order, parallel to `numbers`.
    public let files: [URL]
    public let width: Int
    public let height: Int

    /// Finds, orders and validates the frames `<prefix><digits>.png` in `folder` (research D2).
    /// - Parameters:
    ///   - prefix: the common name prefix; detected from the files when nil.
    ///   - allowGaps: accept missing numbers (the frames present still play in numerical order).
    public static func discover(in folder: URL, prefix requestedPrefix: String? = nil, allowGaps: Bool = false) throws -> FrameSequence {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw MovieError.folderMissing(folder.path)
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var byPrefix: [String: [(number: Int, name: String)]] = [:]
        for name in names {
            guard let parsed = parse(name) else { continue }
            if let requestedPrefix, parsed.prefix != requestedPrefix { continue }
            byPrefix[parsed.prefix, default: []].append((parsed.number, name))
        }
        guard !byPrefix.isEmpty else { throw MovieError.noFrames(folder: folder.path, prefix: requestedPrefix) }
        guard byPrefix.count == 1, let (prefix, entries) = byPrefix.first else {
            throw MovieError.mixedPrefixes(byPrefix.keys.sorted())
        }

        let sorted = entries.sorted { $0.number < $1.number }
        for i in 1..<max(sorted.count, 1) where sorted[i].number == sorted[i - 1].number {
            throw MovieError.duplicateNumber(sorted[i].number)
        }
        if !allowGaps {
            for i in 1..<max(sorted.count, 1) where sorted[i].number != sorted[i - 1].number + 1 {
                throw MovieError.gap(missing: sorted[i - 1].number + 1, after: sorted[i - 1].number)
            }
        }

        let files = sorted.map { folder.appendingPathComponent($0.name) }
        var width = 0, height = 0
        for (i, file) in files.enumerated() {
            guard let size = pixelSize(of: file) else { throw MovieError.unreadableFrame(file.lastPathComponent) }
            if i == 0 { (width, height) = size }
            else if size != (width, height) {
                throw MovieError.sizeMismatch(file: file.lastPathComponent, found: "\(size.0)x\(size.1)", expected: "\(width)x\(height)")
            }
        }
        if width % 2 != 0 || height % 2 != 0 { throw MovieError.oddDimensions(width: width, height: height) }
        return FrameSequence(folder: folder, prefix: prefix, numbers: sorted.map(\.number), files: files, width: width, height: height)
    }

    /// Splits `<prefix><digits>.png` into prefix and number; nil for any other name.
    static func parse(_ name: String) -> (prefix: String, number: Int)? {
        guard name.lowercased().hasSuffix(".png") else { return nil }
        let stem = String(name.dropLast(4))
        let digits = stem.reversed().prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, let number = Int(String(digits.reversed())) else { return nil }
        return (String(stem.dropLast(digits.count)), number)
    }

    /// The pixel size from the PNG header, without decoding the pixels.
    static func pixelSize(of url: URL) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}
