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
}
