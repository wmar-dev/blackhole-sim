import Foundation

/// Named numerical constants (Constitution Principle II: no magic numbers).
/// Each value and its rationale is documented in `docs/physics.md` and `docs/tolerances.md`.
public enum NumericalDefaults {
    /// Rays are declared captured when r ≤ r₊ + `horizonCutoff` (units of M).
    /// Boyer–Lindquist φ and t diverge at the horizon, so tracing stops just outside it.
    public static let horizonCutoff = 1e-3

    /// Minimum sky-termination radius (units of M). The actual radius is
    /// `max(skyRadiusMinimum, skyRadiusObserverFactor · r_observer)`.
    public static let skyRadiusMinimum = 1000.0
    public static let skyRadiusObserverFactor = 10.0

    /// Dormand–Prince 5(4) error-control tolerances (see research.md D3).
    public static let relativeTolerance = 1e-9
    public static let absoluteTolerance = 1e-12

    /// Maximum accepted integrator steps per ray before the ray is flagged `unresolved`.
    public static let stepBudget = 100_000

    /// Disk-plane crossings tested against the disk annulus (spec clarification, FR-004).
    public static let maxPlaneCrossings = 3

    /// Normalized first-integral residual bound used for the SC-003 diagnostics.
    public static let residualTolerance = 1e-3
    /// Fraction of rays allowed to exceed `residualTolerance` or be unresolved (SC-003 / exit code 4).
    public static let allowedBadRayFraction = 1e-3

    // MARK: GPU backend (float32; provisional values, chosen by the tolerance sweep, tasks T013 and T022)

    /// Dormand–Prince error-control tolerances of the GPU kernel. Float32 cannot meet the CPU's 10⁻⁹.
    public static let gpuRelativeTolerance = 1e-5
    public static let gpuAbsoluteTolerance = 1e-8
    /// Relative tolerance of the angular state components (μ, dμ/dλ′, φ), which alone fix a ray's final direction.
    public static let gpuAngleTolerance = 1e-6
    /// A ray whose path comes closer to a pole than sin²θ = this is flagged delicate and re-traced on the CPU in
    /// float64 (float32 cannot follow φ accurately past a pole; research.md D2, mitigation M3).
    public static let gpuPolarFlagSin2 = 0.02
    /// Accepted steps a ray advances per GPU command (bounds each command's duration; research.md D3).
    public static let gpuStepsPerPass = 1024
    /// Samples traced per GPU band: bounds GPU and host memory regardless of image size (FR-009; research.md D4).
    public static let gpuBandSamples = 1_000_000
}
