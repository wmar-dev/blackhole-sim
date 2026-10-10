import Foundation

/// Unit system and conventions (Constitution Principle II).
///
/// All internal computation uses **geometrized units**: G = c = 1 and the black hole mass M = 1.
/// Lengths are in units of GM/c², times in units of GM/c³. Spin is the dimensionless a = J/(Mc)
/// along +z, with 0 ≤ a < 1.
///
/// Spacetime: Kerr, Boyer–Lindquist coordinates (t, r, θ, φ), signature (−,+,+,+).
/// Photon constants of motion: E = −p_t, L = p_φ, Carter constant Q.
///
/// Conversion to SI happens only at the radiometry/output boundary, using the constants below.
public enum PhysicalConstants {
    /// Speed of light in vacuum, m/s (exact, SI definition).
    public static let c = 299_792_458.0
    /// Newtonian constant of gravitation, m³ kg⁻¹ s⁻², CODATA 2018.
    public static let G = 6.674_30e-11
    /// Planck constant, J s (exact, SI definition).
    public static let h = 6.626_070_15e-34
    /// Boltzmann constant, J/K (exact, SI definition).
    public static let kB = 1.380_649e-23
    /// Stefan–Boltzmann constant, W m⁻² K⁻⁴, CODATA 2018.
    public static let sigmaSB = 5.670_374_419e-8
    /// Proton mass, kg, CODATA 2018.
    public static let protonMass = 1.672_621_923_69e-27
    /// Thomson cross section, m², CODATA 2018.
    public static let sigmaThomson = 6.652_458_732_1e-29
    /// Nominal solar mass parameter GM☉, m³ s⁻², IAU 2015 Resolution B3 (exact nominal value).
    public static let gmSun = 1.327_124_4e20

    /// Solar mass in kg, derived as GM☉ / G.
    public static var solarMass: Double { gmSun / G }

    /// Eddington luminosity in W for a black hole of `massSolar` solar masses:
    /// L_Edd = 4π G M m_p c / σ_T.
    public static func eddingtonLuminosity(massSolar: Double) -> Double {
        4 * Double.pi * G * (massSolar * solarMass) * protonMass * c / sigmaThomson
    }

    /// Gravitational radius GM/c² in metres for a black hole of `massSolar` solar masses.
    public static func gravitationalRadius(massSolar: Double) -> Double {
        gmSun * massSolar / (c * c)
    }
}
