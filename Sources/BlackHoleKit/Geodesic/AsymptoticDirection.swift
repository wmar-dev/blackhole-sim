import Foundation

/// Direction on the sky assigned to a ray that has reached the sky radius (research.md D6).
///
/// A point's *position* direction differs from the ray's asymptotic direction by about b/r_sky, which is
/// not small for r_sky = 1000 and b ≈ 10. The direction of *travel* of a ray at large r is its asymptotic
/// direction up to the bending that remains beyond r_sky, about M·b/r_sky².
public enum AsymptoticDirection {
    /// Unit vector (Cartesian, z along the spin axis) along which the traced ray is travelling, taken in the
    /// static orthonormal frame at the ray's position.
    public static func direction(of state: RayState, constants: PhotonConstants, kerr: Kerr) -> SIMD3<Double> {
        let r = state.r
        let mu = state.mu
        let sin2 = max(1 - mu * mu, 1e-300)
        let sinTheta = sin2.squareRoot()
        let g = kerr.metric(r: r, mu: mu)
        let delta = kerr.delta(r: r)
        let sigma = g.thth

        // Components of the backward-ray tangent k′ = −p in the static tetrad (r̂, θ̂, φ̂):
        //   k′_(r) = k′_r/√g_rr with k′_r = v_r/Δ;  k′_(θ) = −p_θ/√Σ with p_θ = v_μ/sinθ;
        //   k′_(φ) = (k′_φ + g_tφ/(−g_tt) k′_t)/√N_φ with k′_t = E, k′_φ = −L.
        let kr = state.vr / (delta * sigma).squareRoot() * 1.0
        let kth = -state.vmu / (sinTheta * sigma.squareRoot())
        let phiNorm = (g.phiphi + g.tphi * g.tphi / (-g.tt)).squareRoot()
        let kph = (-constants.angularMomentum + (g.tphi / (-g.tt)) * constants.energy) / phiNorm

        let cosPhi = cos(state.phi), sinPhi = sin(state.phi)
        let rHat = SIMD3(sinTheta * cosPhi, sinTheta * sinPhi, mu)
        let thetaHat = SIMD3(mu * cosPhi, mu * sinPhi, -sinTheta)
        let phiHat = SIMD3(-sinPhi, cosPhi, 0)
        let d = kr * rHat + kth * thetaHat + kph * phiHat
        return d / (d * d).sum().squareRoot()
    }

    /// Unit vector pointing from the origin to the ray's current position (what a naive lookup would use).
    public static func positionDirection(of state: RayState) -> SIMD3<Double> {
        let sinTheta = max(1 - state.mu * state.mu, 0).squareRoot()
        return SIMD3(sinTheta * cos(state.phi), sinTheta * sin(state.phi), state.mu)
    }
}
