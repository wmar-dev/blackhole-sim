import Foundation

/// Covariant Kerr metric components at a point, Boyer–Lindquist coordinates, signature (−,+,+,+).
/// `mu` is cos θ, so sin²θ = 1 − μ².
public struct KerrMetric: Sendable {
    public var tt: Double
    public var tphi: Double
    public var phiphi: Double
    public var rr: Double
    public var thth: Double

    public init(tt: Double, tphi: Double, phiphi: Double, rr: Double, thth: Double) {
        self.tt = tt
        self.tphi = tphi
        self.phiphi = phiphi
        self.rr = rr
        self.thth = thth
    }
}

/// Photon constants of motion: E = −p_t, L = p_φ, and the Carter constant Q.
public struct PhotonConstants: Sendable, Equatable {
    public var energy: Double
    public var angularMomentum: Double
    public var carter: Double

    public init(energy: Double, angularMomentum: Double, carter: Double) {
        self.energy = energy
        self.angularMomentum = angularMomentum
        self.carter = carter
    }
}

/// The Kerr spacetime of a black hole with M = 1 and dimensionless spin `spin` = a (0 ≤ a < 1).
public struct Kerr: Sendable {
    public let spin: Double

    public init(spin: Double) {
        precondition(spin >= 0 && spin < 1, "spin must satisfy 0 <= a < 1")
        self.spin = spin
    }

    // MARK: Metric functions

    /// Σ = r² + a²μ².
    public func sigma(r: Double, mu: Double) -> Double { r * r + spin * spin * mu * mu }

    /// Δ = r² − 2r + a².
    public func delta(r: Double) -> Double { r * r - 2 * r + spin * spin }

    public func metric(r: Double, mu: Double) -> KerrMetric {
        let a = spin
        let sin2 = 1 - mu * mu
        let sig = sigma(r: r, mu: mu)
        let dlt = delta(r: r)
        return KerrMetric(
            tt: -(1 - 2 * r / sig),
            tphi: -2 * a * r * sin2 / sig,
            phiphi: (r * r + a * a + 2 * a * a * r * sin2 / sig) * sin2,
            rr: sig / dlt,
            thth: sig
        )
    }

    // MARK: Characteristic radii

    /// Outer event horizon r₊ = 1 + √(1 − a²).
    public var horizonRadius: Double { 1 + (1 - spin * spin).squareRoot() }

    /// Outer boundary of the ergosphere at polar coordinate μ = cos θ: r = 1 + √(1 − a²μ²).
    public func ergosphereRadius(mu: Double) -> Double { 1 + (1 - spin * spin * mu * mu).squareRoot() }

    /// Prograde innermost stable circular orbit (Bardeen, Press & Teukolsky 1972).
    public var iscoRadius: Double {
        let a = spin
        let z1 = 1 + cbrt(1 - a * a) * (cbrt(1 + a) + cbrt(1 - a))
        let z2 = (3 * a * a + z1 * z1).squareRoot()
        return 3 + z2 - ((3 - z1) * (3 + z1 + 2 * z2)).squareRoot()
    }

    /// Equatorial circular photon orbit radius: r = 2[1 + cos((2/3) arccos(∓a))] (upper sign: prograde).
    public func photonOrbitRadius(prograde: Bool) -> Double {
        2 * (1 + cos(2.0 / 3.0 * acos(prograde ? -spin : spin)))
    }

    /// Angular velocity of a prograde circular equatorial geodesic: Ω = 1/(r^{3/2} + a).
    public func keplerianOmega(r: Double) -> Double { 1 / (r * r.squareRoot() + spin) }
}
