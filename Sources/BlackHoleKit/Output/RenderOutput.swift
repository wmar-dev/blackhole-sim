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

    @discardableResult
    public static func write(image: RenderedImage, config: RenderConfig, basename: String) throws -> Paths {
        let paths = paths(basename: basename)
        do {
            try FileManager.default.createDirectory(at: paths.png.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw OutputError.writeFailed("could not create the output directory: \(error.localizedDescription)")
        }

        try PNGWriter.write(rgb8: ToneMap.rgb8(from: image.hdr, exposureStops: config.exposureStops),
                            width: image.width, height: image.height, to: paths.png)

        let attributes: [String: EXRAttribute] = [
            "comments": .string("bhsim \(BlackHoleKit.version); linear Rec.709 radiance in reference units; shading=\(image.shading.rawValue)"),
            "referenceRadiance": .float(Float(image.referenceRadiance)),
        ]
        try EXRWriter.write(pixels: image.hdr, width: image.width, height: image.height, attributes: attributes, to: paths.exr)

        let metadata = RenderMetadata(config: config, shading: image.shading, referenceRadiance: image.referenceRadiance,
                                      diagnostics: image.diagnostics)
        do {
            try metadata.jsonData().write(to: paths.json, options: .atomic)
        } catch {
            throw OutputError.writeFailed("could not write \(paths.json.path): \(error.localizedDescription)")
        }
        return paths
    }
}
