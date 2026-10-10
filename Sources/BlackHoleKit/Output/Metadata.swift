import Foundation

/// How the disk is shaded: Novikov–Thorne temperature with the shift factor g applied (the only mode).
public enum Shading: String, Codable, Sendable {
    case physical
}

/// The JSON sidecar written next to every render. Mirrors `contracts/render-metadata.schema.json`.
public struct RenderMetadata: Codable, Sendable {
    public struct Units: Codable, Sendable {
        public var system = "geometrized G=c=M=1"
        public var metric = "Kerr, signature (-,+,+,+)"
        public var coordinates = "Boyer-Lindquist"
    }
    public struct BlackHoleInfo: Codable, Sendable {
        public var spin: Double
        public var massSolar: Double
        public var horizonRadius: Double
        public var iscoRadius: Double
    }
    public struct ObserverInfo: Codable, Sendable {
        public var distance: Double
        public var inclinationDeg: Double
        public var fovDeg: Double
    }
    public struct DiskInfo: Codable, Sendable {
        public var outerRadius: Double
        public var accretionRateEddington: Double
        public var model = "Novikov-Thorne"
        public var enabled = true
    }
    public struct SkyInfo: Codable, Sendable {
        public var kind: String
        public var seed: UInt64
    }
    public struct ImageInfo: Codable, Sendable {
        public var width: Int
        public var height: Int
        public var samplesPerPixel: Int
        public var maxPlaneCrossings: Int
    }
    public struct HDRInfo: Codable, Sendable {
        public var colorSpace = "linear sRGB (Rec.709 primaries, D65)"
        /// Y-weighted radiance (W m⁻² sr⁻¹) equal to 1.0 in the EXR: that of the hottest unshifted disk emission.
        public var referenceRadiance: Double
        public var shading: Shading

        public init(referenceRadiance: Double, shading: Shading) {
            self.referenceRadiance = referenceRadiance
            self.shading = shading
        }
    }
    public struct DiagnosticsInfo: Codable, Sendable {
        public var raysTotal: Int
        public var captured: Int
        public var disk: Int
        public var sky: Int
        public var unresolved: Int
        public var maxResidual: Double
        public var p999Residual: Double
        public var raysOverTolerance: Int
        public var wallTimeSeconds: Double
    }

    public var version = BlackHoleKit.version
    public var units = Units()
    public var blackHole: BlackHoleInfo
    public var observer: ObserverInfo
    public var disk: DiskInfo
    public var sky: SkyInfo
    public var image: ImageInfo
    public var hdr: HDRInfo
    public var diagnostics: DiagnosticsInfo

    public init(config: RenderConfig, shading: Shading, referenceRadiance: Double, diagnostics d: Diagnostics) {
        let kerr = config.kerr
        blackHole = BlackHoleInfo(spin: config.blackHole.spin, massSolar: config.blackHole.massSolar,
                                  horizonRadius: kerr.horizonRadius, iscoRadius: kerr.iscoRadius)
        observer = ObserverInfo(distance: config.observer.distance, inclinationDeg: config.observer.inclinationDegrees,
                                fovDeg: config.observer.fieldOfViewDegrees)
        disk = DiskInfo(outerRadius: config.disk.outerRadius, accretionRateEddington: config.disk.accretionRateEddington,
                        enabled: config.diskEnabled)
        sky = SkyInfo(kind: config.sky.kind.rawValue, seed: config.sky.seed)
        image = ImageInfo(width: config.width, height: config.height, samplesPerPixel: config.samplesPerPixel,
                          maxPlaneCrossings: NumericalDefaults.maxPlaneCrossings)
        hdr = HDRInfo(referenceRadiance: referenceRadiance, shading: shading)
        diagnostics = DiagnosticsInfo(raysTotal: d.raysTotal, captured: d.captured, disk: d.disk, sky: d.sky,
                                      unresolved: d.unresolved, maxResidual: d.maxResidual, p999Residual: d.p999Residual,
                                      raysOverTolerance: d.raysOverTolerance, wallTimeSeconds: d.wallTimeSeconds)
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
