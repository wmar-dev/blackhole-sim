import Foundation

/// Orthonormal frame of a **static** observer (research.md D4), as contravariant components
/// (t, r, θ, φ) in Boyer–Lindquist coordinates. Built by Gram–Schmidt on (∂_t, ∂_r, ∂_θ, ∂_φ):
///
///     e₀ = ∂_t / √(−g_tt)          (the observer's 4-velocity: at rest in the coordinates)
///     e_r = ∂_r / √g_rr,   e_θ = ∂_θ / √g_θθ
///     e_φ = [∂_φ + (g_tφ/(−g_tt)) ∂_t] / √(g_φφ + g_tφ²/(−g_tt))
///
/// A static observer exists only where g_tt < 0, i.e. outside the ergosphere.
public struct StaticTetrad: Sendable {
    public let metric: KerrMetric
    public let e0: SIMD4<Double>
    public let er: SIMD4<Double>
    public let etheta: SIMD4<Double>
    public let ephi: SIMD4<Double>
    /// Normalization of e_φ: √(g_φφ + g_tφ²/(−g_tt)).
    public let phiNorm: Double

    public init(kerr: Kerr, radius: Double, mu: Double) {
        let g = kerr.metric(r: radius, mu: mu)
        precondition(g.tt < 0, "no static observer inside the ergosphere")
        metric = g
        let invSqrtMinusGtt = 1 / (-g.tt).squareRoot()
        e0 = SIMD4(invSqrtMinusGtt, 0, 0, 0)
        er = SIMD4(0, 1 / g.rr.squareRoot(), 0, 0)
        etheta = SIMD4(0, 0, 1 / g.thth.squareRoot(), 0)
        let norm = (g.phiphi + g.tphi * g.tphi / (-g.tt)).squareRoot()
        phiNorm = norm
        ephi = SIMD4((g.tphi / (-g.tt)) / norm, 0, 0, 1 / norm)
    }

    /// Metric inner product g_{μν} a^μ b^ν of two contravariant vectors.
    public func dot(_ a: SIMD4<Double>, _ b: SIMD4<Double>) -> Double {
        let g = metric
        return g.tt * a[0] * b[0] + g.tphi * (a[0] * b[3] + a[3] * b[0]) + g.phiphi * a[3] * b[3]
            + g.rr * a[1] * b[1] + g.thth * a[2] * b[2]
    }
}
