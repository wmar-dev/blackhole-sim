import Foundation

/// Total frequency shift between disk gas and the static observer (research.md D5):
/// g = ν_obs/ν_emit = (−p·u_obs)/(−p·u_emit).
public enum ShiftFactor {
    /// - Parameters:
    ///   - radius: Boyer–Lindquist radius of the emitting gas (equatorial plane, prograde circular geodesic).
    ///   - angularMomentum: photon L in units where the photon's E = 1.
    ///   - observerEnergy: energy the static observer measures for that photon, in the same units
    ///     (`CameraRay.observerEnergy`); equals 1/√(−g_tt) at the observer.
    ///
    /// With u_emit = uᵗ(1, 0, 0, Ω) and u^t = [−g_tt − 2Ωg_tφ − Ω²g_φφ]^(−1/2), −p·u_emit = uᵗ(E − ΩL).
    public static func g(kerr: Kerr, radius r: Double, angularMomentum l: Double, observerEnergy: Double) -> Double {
        let omega = kerr.keplerianOmega(r: r)
        let m = kerr.metric(r: r, mu: 0)
        let normSquared = -(m.tt + 2 * omega * m.tphi + omega * omega * m.phiphi)  // 1/(uᵗ)²
        let ut = 1 / normSquared.squareRoot()
        return observerEnergy / (ut * (1 - omega * l))
    }
}
