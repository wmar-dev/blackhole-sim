import Foundation

/// Carter potentials and Mino-time rates for null geodesics (research.md D2).
///
/// Mino time λ is defined by dλ = dσ/Σ, with σ an affine parameter. With μ = cos θ:
///
///     (dr/dλ)² = R(r)       R(r)   = [E(r²+a²) − aL]² − Δ[(L − aE)² + Q]
///     (dμ/dλ)² = Θ_μ(μ)     Θ_μ(μ) = (1 − μ²)(Q + a²E²μ²) − L²μ²
///     dφ/dλ = L/(1 − μ²) − aE + a[E(r²+a²) − aL]/Δ
///     dt/dλ = a[L − aE(1 − μ²)] + (r²+a²)[E(r²+a²) − aL]/Δ
extension Kerr {
    /// P(r) = E(r² + a²) − aL.
    func radialP(r: Double, constants c: PhotonConstants) -> Double {
        c.energy * (r * r + spin * spin) - spin * c.angularMomentum
    }

    /// Radial potential R(r).
    public func radialPotential(r: Double, constants c: PhotonConstants) -> Double {
        let p = radialP(r: r, constants: c)
        let k = (c.angularMomentum - spin * c.energy) * (c.angularMomentum - spin * c.energy) + c.carter
        return p * p - delta(r: r) * k
    }

    /// dR/dr.
    public func radialPotentialDerivative(r: Double, constants c: PhotonConstants) -> Double {
        let p = radialP(r: r, constants: c)
        let k = (c.angularMomentum - spin * c.energy) * (c.angularMomentum - spin * c.energy) + c.carter
        return 4 * r * c.energy * p - (2 * r - 2) * k
    }

    /// Polar potential Θ_μ(μ), a polynomial in μ² so it is regular on the spin axis.
    public func polarPotential(mu: Double, constants c: PhotonConstants) -> Double {
        let a2e2 = spin * spin * c.energy * c.energy
        let m2 = mu * mu
        return c.carter + m2 * ((a2e2 - c.carter - c.angularMomentum * c.angularMomentum) - a2e2 * m2)
    }

    /// dΘ_μ/dμ.
    public func polarPotentialDerivative(mu: Double, constants c: PhotonConstants) -> Double {
        let a2e2 = spin * spin * c.energy * c.energy
        return 2 * mu * ((a2e2 - c.carter - c.angularMomentum * c.angularMomentum) - 2 * a2e2 * mu * mu)
    }

    /// dφ/dλ. The L/(1 − μ²) term is dropped when L = 0 (such rays never reach the axis with L ≠ 0).
    public func phiRate(r: Double, mu: Double, constants c: PhotonConstants) -> Double {
        let sin2 = 1 - mu * mu
        let axisTerm = c.angularMomentum == 0 ? 0 : c.angularMomentum / max(sin2, 1e-300)
        return axisTerm - spin * c.energy + spin * radialP(r: r, constants: c) / delta(r: r)
    }

    /// dt/dλ.
    public func timeRate(r: Double, mu: Double, constants c: PhotonConstants) -> Double {
        let sin2 = 1 - mu * mu
        return spin * (c.angularMomentum - spin * c.energy * sin2)
            + (r * r + spin * spin) * radialP(r: r, constants: c) / delta(r: r)
    }
}
