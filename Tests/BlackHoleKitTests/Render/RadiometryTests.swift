import Foundation
import Testing
@testable import BlackHoleKit

/// Radiometric identities behind the shift factor (research.md D5).
@Suite struct RadiometryTests {
    /// Planck spectral radiance per unit frequency, W m⁻² sr⁻¹ Hz⁻¹.
    private func planckNu(_ nu: Double, _ t: Double) -> Double {
        let h = PhysicalConstants.h, c = PhysicalConstants.c, k = PhysicalConstants.kB
        return 2 * h * nu * nu * nu / (c * c) / expm1(h * nu / (k * t))
    }

    @Test func aShiftedBlackbodyIsExactlyABlackbodyAtTheShiftedTemperature() {
        // I_ν/ν³ is invariant along a ray, so I_obs(ν) = g³ B_{ν/g}(T) = B_ν(gT).
        for t in [3000.0, 1e4, 1e6] {
            for g in [0.3, 0.8, 1.0, 1.5, 2.2] {
                for nu in [1e13, 5e14, 1e15, 1e16] {
                    let lhs = g * g * g * planckNu(nu / g, t)
                    let rhs = planckNu(nu, g * t)
                    #expect(approxEqual(lhs, rhs, relative: 1e-12), "T=\(t) g=\(g) ν=\(nu)")
                }
            }
        }
    }

    @Test func bolometricIntensityIsSigmaTFourthOverPiAndScalesAsGFourth() {
        func bolometric(_ t: Double) -> Double {
            // Integrate B_ν over ν with a log-spaced trapezoid wide enough to contain the spectrum.
            let n = 20000
            let lo = log(1e10), hi = log(1e19)
            var sum = 0.0
            for i in 0...n {
                let nu = exp(lo + (hi - lo) * Double(i) / Double(n))
                let w = (i == 0 || i == n) ? 0.5 : 1.0
                sum += w * planckNu(nu, t) * nu  // dν = ν d(ln ν)
            }
            return sum * (hi - lo) / Double(n)
        }
        let t = 1e4
        let expected = PhysicalConstants.sigmaSB * pow(t, 4) / Double.pi
        #expect(approxEqual(bolometric(t), expected, relative: 1e-5), "σT⁴/π")  // validates h, k_B, c and σ together
        for g in [0.5, 1.7] {
            #expect(approxEqual(bolometric(g * t), g * g * g * g * bolometric(t), relative: 1e-5), "g=\(g)")
        }
    }

    @Test func visibleBandBrightnessScalesLessSteeplyThanGFourthForHotBlackbodies() {
        // In the Rayleigh–Jeans tail (hν ≪ kT) the visible-band radiance is ∝ T, hence ∝ g, not g⁴: a physical
        // property of observing a hot disk with a visible-light camera (see docs/physics.md).
        let hot = 1e7
        let y1 = Blackbody.xyz(temperature: hot).y
        let y2 = Blackbody.xyz(temperature: 1.5 * hot).y
        #expect(approxEqual(y2 / y1, 1.5, relative: 0.02))
    }
}
