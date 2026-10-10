import Foundation

/// The JSON record written next to every movie (`contracts/movie-record.schema.json`, data-model.md).
public struct MovieRecord: Codable, Sendable, Equatable {
    public struct Colour: Codable, Sendable, Equatable {
        public var primaries = "BT.709"
        public var matrix = "BT.709"
        public var transfer = "sRGB"
        public var range = "limited"
        public var chroma = "4:2:0"
    }

    public struct MovieInfo: Codable, Sendable, Equatable {
        public var file: String
        public var codec = "h264"
        public var container = "mp4"
        public var fps: Double
        public var frameCount: Int
        public var durationSeconds: Double
        public var width: Int
        public var height: Int
        public var encoder: EncoderInfo
        public var colour = Colour()

        public init(file: String, fps: Double, frameCount: Int, width: Int, height: Int, encoder: EncoderInfo) {
            self.file = file; self.fps = fps; self.frameCount = frameCount
            durationSeconds = Double(frameCount) / fps
            self.width = width; self.height = height; self.encoder = encoder
        }
    }

    public enum Source: String, Codable, Sendable { case assembled, animation }

    public struct AnimationInfo: Codable, Sendable, Equatable {
        public var parameter: String
        public var from: Double
        public var to: Double
        public var durationSeconds: Double
        public var fps: Double
        public var frameCount: Int
    }

    /// The render settings shared by all frames; the swept parameter (and the quantities derived from it) is omitted.
    public struct CommonSettings: Codable, Sendable, Equatable {
        public struct BlackHole: Codable, Sendable, Equatable {
            public var massSolar: Double
            public var spin: Double?
            public var horizonRadius: Double?
            public var iscoRadius: Double?
        }
        public struct Observer: Codable, Sendable, Equatable {
            public var fovDeg: Double
            public var distance: Double?
            public var inclinationDeg: Double?
        }
        public var units: RenderMetadata.Units
        public var blackHole: BlackHole
        public var observer: Observer
        public var disk: RenderMetadata.DiskInfo
        public var sky: RenderMetadata.SkyInfo
        public var image: RenderMetadata.ImageInfo

        /// The settings of `metadata` without the swept `parameter`.
        public init(_ metadata: RenderMetadata, omitting parameter: String?) {
            units = metadata.units
            blackHole = BlackHole(massSolar: metadata.blackHole.massSolar,
                                  spin: parameter == "spin" ? nil : metadata.blackHole.spin,
                                  horizonRadius: parameter == "spin" ? nil : metadata.blackHole.horizonRadius,
                                  iscoRadius: parameter == "spin" ? nil : metadata.blackHole.iscoRadius)
            observer = Observer(fovDeg: metadata.observer.fovDeg,
                                distance: parameter == "distance" ? nil : metadata.observer.distance,
                                inclinationDeg: parameter == "inclination" ? nil : metadata.observer.inclinationDeg)
            disk = metadata.disk; sky = metadata.sky; image = metadata.image
        }
    }

    public struct DiagnosticsSummary: Codable, Sendable, Equatable {
        public var raysTotal: Int
        public var captured: Int
        public var disk: Int
        public var sky: Int
        public var unresolved: Int
        public var raysOverResidualTolerance: Int
        public var maxResidual: Double
        public var wallTimeSeconds: Double

        public init(_ d: MovieDiagnostics) {
            raysTotal = d.raysTotal; captured = d.captured; disk = d.disk; sky = d.sky; unresolved = d.unresolved
            raysOverResidualTolerance = d.raysOverTolerance; maxResidual = d.maxResidual; wallTimeSeconds = d.wallTimeSeconds
        }
    }

    public struct FrameEntry: Codable, Sendable, Equatable {
        public var index: Int
        public var value: Double
        public var unresolvedFraction: Double
        public var badRayFraction: Double
    }

    public var version = BlackHoleKit.version
    public var movie: MovieInfo
    public var source: Source
    public var animation: AnimationInfo?
    public var common: CommonSettings?
    public var backend: BackendInfo?
    public var referenceRadiance: Double?
    public var seed: UInt64?
    public var diagnostics: DiagnosticsSummary?
    public var frames: [FrameEntry]?

    public init(movie: MovieInfo, source: Source) {
        self.movie = movie; self.source = source
    }

    /// Fills the render information from the records of the frames (animation runs and `assemble` of their folder).
    mutating func fill(from records: [FrameRecord], frames summaries: [AnimationRunner.FrameSummary]? = nil, omitting parameter: String?) {
        guard let first = records.first else { return }
        common = CommonSettings(first.metadata, omitting: parameter)
        backend = first.metadata.backend
        referenceRadiance = first.metadata.hdr.referenceRadiance
        seed = first.metadata.sky.seed
        var total = MovieDiagnostics()
        for record in records { total.add(record.metadata.diagnostics) }
        diagnostics = DiagnosticsSummary(total)
        frames = records.map { record in
            let d = record.metadata.diagnostics, n = Double(max(d.raysTotal, 1))
            return FrameEntry(index: record.index, value: record.value, unresolvedFraction: Double(d.unresolved) / n,
                              badRayFraction: Double(d.unresolved + d.raysOverTolerance) / n)
        }
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
