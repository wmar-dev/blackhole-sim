import Foundation

/// A rejected input. `option` names the CLI option (e.g. `--spin`) and `reason` states the valid range.
public struct ConfigError: Error, LocalizedError, Equatable, Sendable {
    public let option: String
    public let reason: String

    public init(option: String, reason: String) {
        self.option = option
        self.reason = reason
    }

    public var errorDescription: String? { "\(option): \(reason)" }
}

public struct BlackHole: Sendable, Equatable {
    /// Dimensionless spin a = J/M, 0 ≤ a < 1.
    public var spin: Double
    /// Mass in solar masses. Sets the physical scale only; the geometry is independent of it.
    public var massSolar: Double

    public init(spin: Double = 0, massSolar: Double = 10) {
        self.spin = spin
        self.massSolar = massSolar
    }
}

public struct Observer: Sendable, Equatable {
    /// Boyer–Lindquist radius of the static observer, in units of M.
    public var distance: Double
    /// Polar angle θ of the observer, in degrees from the spin axis.
    public var inclinationDegrees: Double
    /// Horizontal field of view of the pinhole camera, in degrees.
    public var fieldOfViewDegrees: Double
    /// Azimuth of the observer, in degrees. Irrelevant to the axisymmetric black hole and disk; it only
    /// rotates the sky.
    public var azimuthDegrees: Double

    public init(distance: Double = 100, inclinationDegrees: Double = 80, fieldOfViewDegrees: Double = 30,
                azimuthDegrees: Double = 0) {
        self.distance = distance
        self.inclinationDegrees = inclinationDegrees
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.azimuthDegrees = azimuthDegrees
    }

    /// μ = cos θ of the observer.
    public var mu: Double { cos(inclinationDegrees * Double.pi / 180) }
}

public struct AccretionDisk: Sendable, Equatable {
    /// Outer edge of the disk, in units of M.
    public var outerRadius: Double
    /// L / L_Edd of the disk's radiated luminosity; sets the temperature scale.
    public var accretionRateEddington: Double

    public init(outerRadius: Double = 20, accretionRateEddington: Double = 0.1) {
        self.outerRadius = outerRadius
        self.accretionRateEddington = accretionRateEddington
    }
}

public enum SkyKind: String, Sendable, CaseIterable {
    case starfield
    case grid
}

public struct SkyConfig: Sendable, Equatable {
    public var kind: SkyKind
    public var seed: UInt64
    public var starCount: Int

    public init(kind: SkyKind = .starfield, seed: UInt64 = 1, starCount: Int = 200_000) {
        self.kind = kind
        self.seed = seed
        self.starCount = starCount
    }
}

/// Everything needed to render one image. Defaults match `contracts/cli.md`.
public struct RenderConfig: Sendable, Equatable {
    public var blackHole = BlackHole()
    public var observer = Observer()
    public var disk = AccretionDisk()
    public var sky = SkyConfig()
    /// When false the disk is omitted entirely (no plane crossings are tested): a bare black hole and sky.
    public var diskEnabled = true
    public var width = 1920
    public var height = 1080
    public var samplesPerPixel = 4
    /// Display exposure offset in stops (tone-mapped PNG only).
    public var exposureStops = 0.0
    /// Maximum accepted integrator steps per ray; rays that need more are reported as unresolved.
    public var maxStepsPerRay = NumericalDefaults.stepBudget

    public init() {}

    public var kerr: Kerr { Kerr(spin: blackHole.spin) }

    /// Radius at which outgoing rays are declared to have reached the sky.
    public var skyRadius: Double {
        max(NumericalDefaults.skyRadiusMinimum, NumericalDefaults.skyRadiusObserverFactor * observer.distance)
    }

    /// Checks every input and throws a `ConfigError` naming the offending option and the valid range.
    public func validate() throws {
        func require(_ condition: Bool, _ option: String, _ reason: @autoclosure () -> String) throws {
            if !condition { throw ConfigError(option: option, reason: reason()) }
        }
        func fmt(_ x: Double) -> String { String(format: "%.4g", x) }

        let a = blackHole.spin
        try require(a.isFinite && a >= 0 && a < 1, "--spin", "spin must satisfy 0 <= a < 1 (got \(fmt(a)))")
        try require(blackHole.massSolar.isFinite && blackHole.massSolar > 0, "--mass",
                    "mass must be positive (got \(fmt(blackHole.massSolar)))")
        try require(width > 0, "--width", "width must be a positive number of pixels (got \(width))")
        try require(height > 0, "--height", "height must be a positive number of pixels (got \(height))")
        let root = Int(Double(max(samplesPerPixel, 0)).squareRoot().rounded())
        try require(samplesPerPixel > 0 && root * root == samplesPerPixel, "--samples",
                    "samples per pixel must be a positive perfect square such as 1, 4, 9, 16 (got \(samplesPerPixel))")
        let fov = observer.fieldOfViewDegrees
        try require(fov.isFinite && fov > 0 && fov < 180, "--fov",
                    "field of view must satisfy 0 < fov < 180 degrees (got \(fmt(fov)))")
        let inc = observer.inclinationDegrees
        try require(inc.isFinite && inc > 0 && inc < 180, "--inclination",
                    "inclination must satisfy 0 < i < 180 degrees (got \(fmt(inc))); use a value such as 0.01 instead of exactly 0 or 180")
        try require(maxStepsPerRay > 0, "--max-steps", "step budget must be a positive number (got \(maxStepsPerRay))")
        try require(disk.accretionRateEddington.isFinite && disk.accretionRateEddington > 0, "--accretion-rate",
                    "accretion rate must be a positive Eddington fraction (got \(fmt(disk.accretionRateEddington)))")

        let kerr = Kerr(spin: a)
        let ergosphere = kerr.ergosphereRadius(mu: observer.mu)
        try require(observer.distance.isFinite && observer.distance > ergosphere, "--distance",
                    "no static observer exists at r = \(fmt(observer.distance)) M: the distance must exceed the ergosphere radius "
                        + "\(fmt(ergosphere)) M at this inclination (the horizon is at \(fmt(kerr.horizonRadius)) M)")
        let isco = kerr.iscoRadius
        guard diskEnabled else { return }
        try require(disk.outerRadius.isFinite && disk.outerRadius > isco, "--disk-outer",
                    "outer disk radius must exceed the innermost stable orbit r_isco = \(String(format: "%.3f", isco)) M (got \(fmt(disk.outerRadius)))")
        let inDiskPlane = abs(observer.mu) < 1e-12
        try require(!(inDiskPlane && observer.distance >= isco && observer.distance <= disk.outerRadius), "--distance",
                    "the observer would lie inside the disk (inclination 90 degrees with r between r_isco = "
                        + "\(String(format: "%.3f", isco)) M and the outer radius \(fmt(disk.outerRadius)) M); increase --distance or change --inclination")
    }
}
