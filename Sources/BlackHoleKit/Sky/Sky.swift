import Foundation

/// A source of distant light: radiance as a function of the direction on the sky.
///
/// Radiance is linear sRGB in the renderer's reference units, where 1.0 corresponds to the brightest
/// unshifted disk emission. Surface brightness is conserved along rays (up to the g⁴/g³ shift factors,
/// which are not applied to synthetic sources), so lensing magnification emerges from sampling.
public protocol SkyModel: Sendable {
    func radiance(direction: SIMD3<Double>) -> SIMD3<Double>
}

public enum Sky {
    /// Builds the sky selected by `config`.
    public static func make(_ config: SkyConfig) -> any SkyModel {
        switch config.kind {
        case .starfield: return StarField(seed: config.seed, count: config.starCount)
        case .grid: return ReferenceGrid()
        }
    }
}

/// SplitMix64: a small deterministic generator, identical on every platform, so a seed fixes the sky.
struct SplitMix64: Sendable {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func nextDouble() -> Double { Double(next() >> 11) * (1.0 / Double(1 << 53)) }
}
