import Foundation

/// Writes the three outputs of a render: tone-mapped PNG, physical-intensity EXR, and the JSON sidecar.
public enum RenderOutput {
    public struct Paths: Sendable, Equatable {
        public var png: URL
        public var exr: URL
        public var json: URL
    }

    /// Output paths for `basename` (extension-less); parent directories are created on write.
    public static func paths(basename: String) -> Paths {
        let base = URL(fileURLWithPath: basename)
        return Paths(png: base.appendingPathExtension("png"), exr: base.appendingPathExtension("exr"),
                     json: base.appendingPathExtension("json"))
    }

    /// Which of the three outputs to write.
    public struct Formats: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let png = Formats(rawValue: 1)
        public static let exr = Formats(rawValue: 2)
        public static let json = Formats(rawValue: 4)
        public static let all: Formats = [.png, .exr, .json]
    }

    /// Writes `url` through a temporary file in the same folder and renames it into place, so an interrupted write never
    /// leaves a truncated file under the final name.
    static func atomically(_ url: URL, _ body: (URL) throws -> Void) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).partial")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try body(temporary)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        do { try FileManager.default.moveItem(at: temporary, to: url) } catch {
            throw OutputError.writeFailed("could not write \(url.path): \(error.localizedDescription)")
        }
    }

    @discardableResult
    public static func write(image: RenderedImage, config: RenderConfig, basename: String, formats: Formats = .all) throws -> Paths {
        let paths = paths(basename: basename)
        do {
            try FileManager.default.createDirectory(at: paths.png.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw OutputError.writeFailed("could not create the output directory: \(error.localizedDescription)")
        }

        if formats.contains(.png) {
            try atomically(paths.png) {
                try PNGWriter.write(rgb8: ToneMap.rgb8(from: image.hdr, exposureStops: config.exposureStops),
                                    width: image.width, height: image.height, to: $0)
            }
        }
        if formats.contains(.exr) {
            let attributes: [String: EXRAttribute] = [
                "comments": .string("bhsim \(BlackHoleKit.version); linear Rec.709 radiance in reference units; shading=\(image.shading.rawValue)"),
                "referenceRadiance": .float(Float(image.referenceRadiance)),
            ]
            try atomically(paths.exr) {
                try EXRWriter.write(pixels: image.hdr, width: image.width, height: image.height, attributes: attributes, to: $0)
            }
        }
        if formats.contains(.json) {
            let metadata = RenderMetadata(config: config, shading: image.shading, referenceRadiance: image.referenceRadiance,
                                          diagnostics: image.diagnostics)
            do {
                try metadata.jsonData().write(to: paths.json, options: .atomic)
            } catch {
                throw OutputError.writeFailed("could not write \(paths.json.path): \(error.localizedDescription)")
            }
        }
        return paths
    }
}
