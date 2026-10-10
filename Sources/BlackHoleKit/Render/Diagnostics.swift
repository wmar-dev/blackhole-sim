import Foundation

/// Render statistics (FR-008, SC-003). Merging is deterministic so results do not depend on thread count.
public struct Diagnostics: Sendable, Equatable {
    public var raysTotal = 0
    public var captured = 0
    public var disk = 0
    public var sky = 0
    public var unresolved = 0
    /// Rays whose normalized first-integral residual exceeded `NumericalDefaults.residualTolerance`.
    public var raysOverTolerance = 0
    public var maxResidual = 0.0
    public var wallTimeSeconds = 0.0

    // Log-spaced histogram of per-ray maximum residuals: `binsPerDecade` bins from 10^minExponent upward.
    static let minExponent = -16
    static let decades = 20
    static let binsPerDecade = 20
    private var histogram = [Int](repeating: 0, count: Diagnostics.decades * Diagnostics.binsPerDecade + 1)

    public init() {}

    private static func bin(for residual: Double) -> Int {
        guard residual > 0 else { return 0 }
        let position = (log10(residual) - Double(minExponent)) * Double(binsPerDecade)
        return min(max(Int(position.rounded(.down)) + 1, 0), decades * binsPerDecade)
    }

    /// Records one traced ray.
    public mutating func record(_ outcome: RayOutcome, residual: Double) {
        raysTotal += 1
        switch outcome {
        case .captured: captured += 1
        case .disk: disk += 1
        case .sky: sky += 1
        case .unresolved: unresolved += 1
        }
        let safe = residual.isFinite ? residual : Double.greatestFiniteMagnitude
        maxResidual = max(maxResidual, safe)
        if safe > NumericalDefaults.residualTolerance { raysOverTolerance += 1 }
        histogram[Self.bin(for: safe)] += 1
    }

    public mutating func merge(_ other: Diagnostics) {
        raysTotal += other.raysTotal
        captured += other.captured
        disk += other.disk
        sky += other.sky
        unresolved += other.unresolved
        raysOverTolerance += other.raysOverTolerance
        maxResidual = max(maxResidual, other.maxResidual)
        for i in histogram.indices { histogram[i] += other.histogram[i] }
    }

    /// 99.9th percentile of the per-ray maximum residual (resolution: one histogram bin, 1/20 decade).
    public var p999Residual: Double {
        guard raysTotal > 0 else { return 0 }
        let target = Int((0.999 * Double(raysTotal)).rounded(.up))
        var cumulative = 0
        for (i, count) in histogram.enumerated() {
            cumulative += count
            if cumulative >= target {
                if i == 0 { return 0 }
                return pow(10, Double(Self.minExponent) + Double(i) / Double(Self.binsPerDecade))
            }
        }
        return maxResidual
    }

    /// Fraction of rays that were unresolved or exceeded the residual tolerance (drives exit code 4).
    public var badRayFraction: Double {
        raysTotal == 0 ? 0 : Double(unresolved + raysOverTolerance) / Double(raysTotal)
    }
}
