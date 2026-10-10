import Foundation

/// Which face of the (two-sided) disk a ray met: the side the ray arrives from.
public enum DiskFace: Sendable, Equatable {
    /// The ray came from μ > 0 (the northern side, the spin-axis side).
    case upper
    case lower
}

public enum UnresolvedReason: Sendable, Equatable {
    case stepBudget
    case integrationFailure
}

/// Result of tracing one ray (data-model.md).
public enum RayOutcome: Sendable, Equatable {
    /// The ray fell into the horizon: the pixel is part of the shadow.
    case captured
    /// The ray hit the opaque disk annulus.
    /// - radius: Boyer–Lindquist r of the crossing point.
    /// - crossingIndex: which equatorial-plane crossing it was (1, 2 or 3).
    case disk(radius: Double, crossingIndex: Int, face: DiskFace)
    /// The ray reached the sky. `direction` is the asymptotic direction of travel of the traced ray as a
    /// unit vector in Cartesian coordinates built from Boyer–Lindquist angles (z along the spin axis).
    case sky(direction: SIMD3<Double>)
    /// The ray could not be resolved. These are counted and never silently coloured.
    case unresolved(UnresolvedReason)
}
