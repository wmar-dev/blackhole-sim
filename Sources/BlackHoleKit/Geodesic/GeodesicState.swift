import Foundation

/// State of a null geodesic in Mino time, parameterised for **backward** tracing from the observer.
///
/// The physical photon travels toward the observer. We trace it backward, so the integration variable
/// is λ′ = −λ and every derivative below is with respect to λ′. The photon constants (E, L, Q) are those
/// of the physical photon and never change along the ray.
///
/// The radial coordinate is carried as the inverse radius u = 1/r. In Mino time u′ → −E at large r,
/// so u, u′ and φ′ stay O(1) from the sky radius down to the horizon. This keeps absolute integration
/// error uniform across the whole range of scales (see research.md D2).
public struct RayState: Sendable, Equatable {
    /// Inverse Boyer–Lindquist radius u = 1/r.
    public var u: Double
    /// du/dλ′.
    public var vu: Double
    /// μ = cos θ.
    public var mu: Double
    /// dμ/dλ′.
    public var vmu: Double
    /// Boyer–Lindquist azimuth, accumulated (not wrapped).
    public var phi: Double

    public init(u: Double, vu: Double, mu: Double, vmu: Double, phi: Double) {
        self.u = u
        self.vu = vu
        self.mu = mu
        self.vmu = vmu
        self.phi = phi
    }

    /// Boyer–Lindquist radius.
    public var r: Double { 1 / u }
    /// dr/dλ′ = −(du/dλ′)/u².
    public var vr: Double { -vu / (u * u) }
}

/// Why a ray stopped.
public enum RayTermination: Sendable, Equatable {
    /// Reached r ≤ r₊ + horizonCutoff: the pixel is inside the shadow.
    case horizon
    /// Reached the sky radius moving outward.
    case sky
    /// The step budget was exhausted before the ray terminated.
    case stepBudget
    /// The step size collapsed or the state became non-finite.
    case failed
    /// The caller's stop condition fired (e.g. the ray hit the disk).
    case stopped
}

public struct IntegrationResult: Sendable {
    public var state: RayState
    public var termination: RayTermination
    /// Accepted steps taken.
    public var steps: Int
    /// Maximum normalized first-integral residual seen along the ray (see `GeodesicIntegrator.residual`).
    public var maxResidual: Double
}

public struct IntegratorSettings: Sendable {
    public var relativeTolerance: Double
    public var absoluteTolerance: Double
    public var stepBudget: Int
    public var horizonCutoff: Double
    /// Radius at which an outgoing ray is declared to have reached the sky.
    public var skyRadius: Double

    public init(relativeTolerance: Double, absoluteTolerance: Double, stepBudget: Int,
                horizonCutoff: Double, skyRadius: Double) {
        self.relativeTolerance = relativeTolerance
        self.absoluteTolerance = absoluteTolerance
        self.stepBudget = stepBudget
        self.horizonCutoff = horizonCutoff
        self.skyRadius = skyRadius
    }

    /// Defaults from `NumericalDefaults`.
    public static func standard(skyRadius: Double) -> IntegratorSettings {
        IntegratorSettings(
            relativeTolerance: NumericalDefaults.relativeTolerance,
            absoluteTolerance: NumericalDefaults.absoluteTolerance,
            stepBudget: NumericalDefaults.stepBudget,
            horizonCutoff: NumericalDefaults.horizonCutoff,
            skyRadius: skyRadius
        )
    }
}
