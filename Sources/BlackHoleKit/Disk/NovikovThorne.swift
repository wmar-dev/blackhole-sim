import Foundation

/// Novikov–Thorne thin-disk emission (Page & Thorne 1974), research.md D5.
///
/// The disk is geometrically thin, optically thick, equatorial, on prograde circular geodesics from the
/// innermost stable orbit outward, with zero torque at the inner edge. Each face radiates a blackbody at the
/// local effective temperature T = (F/σ)^(1/4).
public struct NovikovThorne: Sendable {
    public let kerr: Kerr
    public let massSolar: Double
    /// Radiated luminosity as a fraction of the Eddington luminosity.
    public let eddingtonFraction: Double

    private let isco: Double
    private let x0: Double  // √r_isco
    private let roots: SIMD3<Double>  // x₁, x₂, x₃: roots of x³ − 3x + 2a = 0

    public init(kerr: Kerr, massSolar: Double, eddingtonFraction: Double) {
        self.kerr = kerr
        self.massSolar = massSolar
        self.eddingtonFraction = eddingtonFraction
        isco = kerr.iscoRadius
        x0 = isco.squareRoot()
        let a = kerr.spin
        if a == 0 {
            roots = SIMD3(3.0.squareRoot(), 0, -3.0.squareRoot())
        } else {
            let third = acos(a) / 3
            roots = SIMD3(2 * cos(third - Double.pi / 3), 2 * cos(third + Double.pi / 3), -2 * cos(third))
        }
    }

    public var iscoRadius: Double { isco }

    /// Specific energy E of a prograde circular geodesic at radius r (Bardeen, Press & Teukolsky 1972).
    public func specificEnergy(r: Double) -> Double {
        let a = kerr.spin
        let denominator = pow(r, 0.75) * (r * r.squareRoot() - 3 * r.squareRoot() + 2 * a).squareRoot()
        return (r * r.squareRoot() - 2 * r.squareRoot() + a) / denominator
    }

    /// Fraction of the rest-mass energy radiated: 1 − E(r_isco).
    public var radiativeEfficiency: Double { 1 - specificEnergy(r: isco) }

    /// Accretion rate in kg/s such that the radiated luminosity is `eddingtonFraction` × L_Edd.
    public var accretionRate: Double {
        let c = PhysicalConstants.c
        return eddingtonFraction * PhysicalConstants.eddingtonLuminosity(massSolar: massSolar) / (radiativeEfficiency * c * c)
    }

    /// Flux per face per unit accretion rate, in geometrized units (M = 1): F̂(r) with F = Ṁ F̂ / M².
    /// Page & Thorne (1974) eq. 15n; zero at and inside the inner edge.
    public func geometricFlux(r: Double) -> Double {
        guard r > isco else { return 0 }
        let a = kerr.spin
        let x = r.squareRoot()
        var bracket = x - x0
        if a != 0 { bracket -= 1.5 * a * log(x / x0) }
        for i in 0..<3 {
            let xi = roots[i]
            if a == 0 && xi == 0 { continue }  // (x₂ − a)²/x₂ → 0 as a → 0
            let xj = roots[(i + 1) % 3], xk = roots[(i + 2) % 3]
            bracket -= 3 * (xi - a) * (xi - a) / (xi * (xi - xj) * (xi - xk)) * log((x - xi) / (x0 - xi))
        }
        let value = 3 / (8 * Double.pi) * bracket / (x * x * x * x * (x * x * x - 3 * x + 2 * a))
        return max(value, 0)
    }

    /// Flux per face in W/m².
    public func flux(r: Double) -> Double {
        let c = PhysicalConstants.c
        let length = PhysicalConstants.gravitationalRadius(massSolar: massSolar)
        return accretionRate * c * c / (length * length) * geometricFlux(r: r)
    }

    /// Effective temperature in kelvin: (F/σ)^(1/4).
    public func temperature(r: Double) -> Double {
        pow(flux(r: r) / PhysicalConstants.sigmaSB, 0.25)
    }

    /// Highest temperature anywhere in the disk out to `outerRadius`.
    public func peakTemperature(upTo outerRadius: Double) -> Double {
        let samples = 4000
        let lo = log(isco), hi = log(outerRadius)
        var best = 0.0
        for i in 1...samples {
            let r = exp(lo + (hi - lo) * Double(i) / Double(samples))
            best = max(best, temperature(r: r))
        }
        return best
    }

    /// Reference luminance Y_ref (W m⁻² sr⁻¹, ∫B_λ ȳ dλ) of the hottest unshifted emission. It is 1.0 in the
    /// renderer's HDR output.
    public func referenceLuminance(upTo outerRadius: Double) -> Double {
        Blackbody.xyz(temperature: peakTemperature(upTo: outerRadius)).y
    }
}
