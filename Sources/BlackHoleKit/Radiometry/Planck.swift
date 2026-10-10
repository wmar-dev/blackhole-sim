import Foundation

/// Blackbody radiation and its colour (research.md D5, D7).
///
/// A blackbody at temperature T seen with total shift factor g is, exactly, a blackbody at gT:
/// I_ν/ν³ is invariant along rays, so I_ν,obs(ν) = g³ B_ν/g(T) = B_ν(gT). Colour therefore only needs
/// the Planck spectrum at the observed temperature.
public enum Blackbody {
    /// Spectral radiance B_λ(T) in W m⁻² sr⁻¹ m⁻¹ at `wavelength` metres.
    public static func spectralRadiance(wavelength: Double, temperature: Double) -> Double {
        guard temperature > 0, wavelength > 0 else { return 0 }
        let h = PhysicalConstants.h, c = PhysicalConstants.c, k = PhysicalConstants.kB
        let numerator = 2 * h * c * c / (wavelength * wavelength * wavelength * wavelength * wavelength)
        return numerator / expm1(h * c / (wavelength * k * temperature))
    }

    /// CIE 1931 XYZ of the blackbody spectrum, integrated over 380–780 nm (trapezoid, 5 nm):
    /// (X, Y, Z) = ∫ B_λ (x̄, ȳ, z̄) dλ, in W m⁻² sr⁻¹. Y is the radiometric luminance-weighted
    /// radiance (no 683 lm/W factor).
    public static func xyz(temperature: Double) -> SIMD3<Double> {
        guard temperature > 0 else { return .zero }
        let table = CIE1931.table
        let step = CIE1931.stepNanometers * 1e-9
        var sum = SIMD3<Double>.zero
        for (i, cmf) in table.enumerated() {
            let lambda = (CIE1931.firstWavelengthNanometers + Double(i) * CIE1931.stepNanometers) * 1e-9
            let weight = (i == 0 || i == table.count - 1) ? 0.5 : 1.0
            sum += weight * spectralRadiance(wavelength: lambda, temperature: temperature) * cmf
        }
        return sum * step
    }

    /// XYZ → linear sRGB (Rec. 709 primaries, D65 white), IEC 61966-2-1.
    public static func linearSRGB(fromXYZ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(3.2406 * v.x - 1.5372 * v.y - 0.4986 * v.z,
              -0.9689 * v.x + 1.8758 * v.y + 0.0415 * v.z,
              0.0557 * v.x - 0.2040 * v.y + 1.0570 * v.z)
    }

    /// Linear sRGB of a blackbody (components may be slightly negative outside the sRGB gamut).
    public static func linearSRGB(temperature: Double) -> SIMD3<Double> {
        linearSRGB(fromXYZ: xyz(temperature: temperature))
    }
}
