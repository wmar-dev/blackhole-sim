import Foundation

/// The JSON written next to each animation frame; its presence marks the frame as complete (research D4).
public struct FrameRecord: Codable, Sendable {
    public var index: Int
    public var parameter: String
    public var value: Double
    /// Every input of the frame's configuration, as text; a kept frame is reused only if this matches exactly.
    public var configKey: String
    public var metadata: RenderMetadata
}

/// Ray statistics of a whole movie, summed over its frames (kept frames included).
public struct MovieDiagnostics: Sendable, Equatable, Codable {
    public var raysTotal = 0
    public var captured = 0
    public var disk = 0
    public var sky = 0
    public var unresolved = 0
    public var raysOverTolerance = 0
    public var maxResidual = 0.0
    public var wallTimeSeconds = 0.0

    public init() {}

    mutating func add(_ d: RenderMetadata.DiagnosticsInfo) {
        raysTotal += d.raysTotal; captured += d.captured; disk += d.disk; sky += d.sky
        unresolved += d.unresolved; raysOverTolerance += d.raysOverTolerance
        maxResidual = max(maxResidual, d.maxResidual); wallTimeSeconds += d.wallTimeSeconds
    }

    /// Fraction of rays that were unresolved or over the residual bound (drives exit code 4).
    public var badRayFraction: Double { raysTotal == 0 ? 0 : Double(unresolved + raysOverTolerance) / Double(raysTotal) }
}

/// Renders the frames of an animation in order, writing each to disk as it is finished (User Story 2).
public enum AnimationRunner {
    public struct Options: Sendable {
        public var framesFolder: URL
        public var keepEXR = false
        public init(framesFolder: URL, keepEXR: Bool = false) {
            self.framesFolder = framesFolder; self.keepEXR = keepEXR
        }
    }

    public struct FrameSummary: Sendable, Equatable {
        public var index: Int
        public var value: Double
        public var unresolvedFraction: Double
        public var badRayFraction: Double
    }

    public struct Result: Sendable {
        public var rendered: Int
        public var skipped: Int
        public var frames: [FrameSummary]
        public var diagnostics: MovieDiagnostics
    }

    /// Upper bound of the disk space the frames need: width × height × 3 bytes per PNG, plus 12 bytes per pixel for each
    /// EXR if they are kept.
    public static func diskEstimateBytes(_ animation: Animation, keepEXR: Bool) -> Int {
        animation.frameCount * animation.base.width * animation.base.height * (3 + (keepEXR ? 12 : 0))
    }

    static func name(_ index: Int, of count: Int) -> String {
        let width = max(4, String(count).count)
        return "frame_" + String(repeating: "0", count: max(0, width - String(index).count)) + String(index)
    }

    static func key(of config: RenderConfig) -> String { "bhsim \(BlackHoleKit.version) \(config)" }

    /// - Parameters:
    ///   - progress: called with (frame, total) after each frame, rendered or kept.
    ///   - isCancelled: polled before each frame; when true `cancelled` is thrown and the finished frames stay.
    public static func run(_ animation: Animation, options: Options, progress: (@Sendable (Int, Int) -> Void)? = nil,
                           isCancelled: (@Sendable () -> Bool)? = nil) throws -> Result {
        try animation.validate()
        let count = animation.frameCount
        let fileManager = FileManager.default
        do { try fileManager.createDirectory(at: options.framesFolder, withIntermediateDirectories: true) } catch {
            throw MovieError.cannotWrite("could not create \(options.framesFolder.path): \(error.localizedDescription)")
        }

        var result = Result(rendered: 0, skipped: 0, frames: [], diagnostics: MovieDiagnostics())
        for i in 0..<count {
            if isCancelled?() == true { throw MovieError.cancelled }
            let config = animation.frameConfig(i)
            let base = options.framesFolder.appendingPathComponent(name(i + 1, of: count))
            let record: FrameRecord
            if let kept = keptRecord(base: base, config: config, keepEXR: options.keepEXR) {
                record = kept
                result.skipped += 1
            } else {
                // A command-line loop never drains the main thread's autorelease pool; without this the Metal buffers of every
                // frame stayed alive (about 75 MB per 1280x720 frame, measured), so memory grew with the frame count.
                let image = try autoreleasepool { try Renderer(config: config).renderOnBackend() }
                var formats: RenderOutput.Formats = [.png]
                if options.keepEXR { formats.insert(.exr) }
                // Remove the old marker first, so a stop between the image and the new marker leaves an incomplete frame.
                try? fileManager.removeItem(at: base.appendingPathExtension("json"))
                try RenderOutput.write(image: image, config: config, basename: base.path, formats: formats)
                record = FrameRecord(index: i + 1, parameter: animation.parameter.rawValue, value: animation.value(at: i), configKey: key(of: config),
                                     metadata: RenderMetadata(config: config, shading: image.shading, referenceRadiance: image.referenceRadiance,
                                                              diagnostics: image.diagnostics))
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                do {
                    try RenderOutput.atomically(base.appendingPathExtension("json")) { try encoder.encode(record).write(to: $0) }
                } catch {
                    throw MovieError.cannotWrite("could not write the record of frame \(i + 1): \(error.localizedDescription)")
                }
                result.rendered += 1
            }
            let d = record.metadata.diagnostics
            result.diagnostics.add(d)
            let total = Double(max(d.raysTotal, 1))
            result.frames.append(FrameSummary(index: i + 1, value: record.value, unresolvedFraction: Double(d.unresolved) / total,
                                              badRayFraction: Double(d.unresolved + d.raysOverTolerance) / total))
            progress?(i + 1, count)
        }
        return result
    }

    /// The record of a frame that is complete and was made from exactly these inputs, or nil.
    private static func keptRecord(base: URL, config: RenderConfig, keepEXR: Bool) -> FrameRecord? {
        let fileManager = FileManager.default
        guard let data = try? Data(contentsOf: base.appendingPathExtension("json")),
              let record = try? JSONDecoder().decode(FrameRecord.self, from: data), record.configKey == key(of: config),
              let size = FrameSequence.pixelSize(of: base.appendingPathExtension("png")), size == (config.width, config.height) else { return nil }
        if keepEXR, !fileManager.fileExists(atPath: base.appendingPathExtension("exr").path) { return nil }
        return record
    }
}
