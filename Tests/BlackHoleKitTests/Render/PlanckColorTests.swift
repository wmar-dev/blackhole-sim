import Foundation
import Testing
@testable import BlackHoleKit

struct PlanckFixture: Decodable {
    struct Blackbody: Decodable {
        let T: Double, X: Double, Y: Double, Z: Double, x: Double, y: Double
        let rgb: [Double]
    }
    let matrix_XYZ_to_sRGB: [[Double]]
    let blackbodies: [Blackbody]
}

/// Planck spectrum → CIE XYZ → linear sRGB (Constitution Principle III; task T023).
/// References are integrated independently at 1 nm in tools/reference/color.py.
@Suite struct PlanckColorTests {
    let fixture: PlanckFixture

    init() throws { fixture = try Fixture.load("planck_color") }

    @Test func xyzMatchesIndependentReference() {
        for b in fixture.blackbodies {
            let xyz = Blackbody.xyz(temperature: b.T)
            // 5 nm trapezoid vs 1 nm reference.
            #expect(approxEqual(xyz.x, b.X, relative: 2e-3), "X at \(b.T) K: \(xyz.x) vs \(b.X)")
            #expect(approxEqual(xyz.y, b.Y, relative: 2e-3), "Y at \(b.T) K: \(xyz.y) vs \(b.Y)")
            #expect(approxEqual(xyz.z, b.Z, relative: 2e-3), "Z at \(b.T) K: \(xyz.z) vs \(b.Z)")
            let sum = xyz.x + xyz.y + xyz.z
            #expect(abs(xyz.x / sum - b.x) < 5e-4 && abs(xyz.y / sum - b.y) < 5e-4, "chromaticity at \(b.T) K")
        }
    }

    @Test func linearSRGBMatchesReference() {
        for b in fixture.blackbodies {
            let rgb = Blackbody.linearSRGB(temperature: b.T)
            for c in 0..<3 {
                // Blue/red can be near zero or slightly negative (out of gamut) at the temperature extremes.
                #expect(abs(rgb[c] - b.rgb[c]) <= 3e-3 * b.Y, "rgb[\(c)] at \(b.T) K: \(rgb[c]) vs \(b.rgb[c])")
            }
        }
    }

    @Test func sixThousandFiveHundredKelvinIsNearTheD65WhitePoint() {
        let xyz = Blackbody.xyz(temperature: 6504)
        let sum = xyz.x + xyz.y + xyz.z
        // D65 is (0.3127, 0.3290); the Planckian locus at 6504 K is (0.3135, 0.3237), about 0.005 away.
        #expect(abs(xyz.x / sum - 0.3127) < 0.006 && abs(xyz.y / sum - 0.3290) < 0.006)
        let rgb = Blackbody.linearSRGB(temperature: 6504)
        let normalized = rgb / rgb.y
        #expect(abs(normalized.x - 1) < 0.07 && abs(normalized.z - 1) < 0.07, "\(normalized)")
    }

    @Test func coolerIsRedderAndHotterIsBluer() {
        var previousRedToBlue = Double.infinity
        for t in [1500.0, 2700, 4000, 5500, 6504, 9000, 15000, 40000] {
            let rgb = Blackbody.linearSRGB(temperature: t)
            let ratio = rgb.x / max(rgb.z, 1e-12)
            #expect(ratio < previousRedToBlue, "red/blue ratio must fall as temperature rises (T=\(t))")
            previousRedToBlue = ratio
        }
        let cool = Blackbody.linearSRGB(temperature: 2000)
        let hot = Blackbody.linearSRGB(temperature: 20000)
        #expect(cool.x > cool.z && hot.z > hot.x)
    }

    @Test func hotterBlackbodiesAreBrighterInTheVisibleBand() {
        var previous = 0.0
        for t in [1500.0, 3000, 6000, 12000, 50000, 1e6] {
            let y = Blackbody.xyz(temperature: t).y
            #expect(y > previous)
            previous = y
        }
    }

    @Test func nonPositiveTemperatureGivesNoLight() {
        #expect(Blackbody.xyz(temperature: 0) == .zero)
        #expect(Blackbody.xyz(temperature: -5) == .zero)
    }

    @Test func spectralRadianceMatchesPlancksLaw() {
        // B_λ(500 nm, 5772 K): 2hc²/λ⁵ / (exp(hc/λkT) − 1)
        let h = 6.62607015e-34, c = 299792458.0, k = 1.380649e-23
        let lambda = 500e-9, t = 5772.0
        let expected = 2 * h * c * c / pow(lambda, 5) / (exp(h * c / (lambda * k * t)) - 1)
        #expect(approxEqual(Blackbody.spectralRadiance(wavelength: lambda, temperature: t), expected, relative: 1e-12))
    }
}
