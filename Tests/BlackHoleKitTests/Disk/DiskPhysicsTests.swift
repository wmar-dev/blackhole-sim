import Foundation
import Testing
@testable import BlackHoleKit

struct NovikovThorneFixture: Decodable {
    struct Flux: Decodable { let r: Double; let closed: Double; let integral: Double }
    struct Shift: Decodable { let r: Double; let L: Double; let r_observer: Double; let g: Double }
    struct Scale: Decodable { let mass_solar: Double; let fraction: Double; let radii: [Double]; let T: [Double]; let mdot_kg_per_s: Double }
    struct Case: Decodable {
        let a: Double; let isco: Double; let efficiency: Double
        let flux: [Flux]; let shifts: [Shift]; let temperature_scale: Scale
    }
    struct FaceOn: Decodable { let r: Double; let r_observer: Double; let g: Double }
    let cases: [Case]
    let schwarzschild_face_on: [FaceOn]
}

/// Novikov–Thorne flux and the shift factor (FR-004, FR-006).
/// References: tools/reference/novikov_thorne.py (closed form and the conservation-law integral agree to 1e-25).
@Suite struct DiskPhysicsTests {
    let fixture: NovikovThorneFixture

    init() throws { fixture = try Fixture.load("novikov_thorne") }

    @Test func fluxVanishesAtTheInnermostStableOrbitAndOutsideTheDiskIsZero() {
        for c in fixture.cases {
            let nt = NovikovThorne(kerr: Kerr(spin: c.a), massSolar: 10, eddingtonFraction: 0.1)
            #expect(approxEqual(nt.iscoRadius, c.isco, relative: 1e-12))
            let reference = nt.geometricFlux(r: 1.5 * c.isco)
            #expect(reference > 0)
            #expect(nt.geometricFlux(r: c.isco) == 0, "zero-torque inner boundary at a=\(c.a)")
            #expect(nt.geometricFlux(r: 0.9 * c.isco) == 0)
            #expect(nt.temperature(r: c.isco) == 0)
        }
    }

    @Test func fluxMatchesTheIndependentReference() {
        for c in fixture.cases {
            let nt = NovikovThorne(kerr: Kerr(spin: c.a), massSolar: 10, eddingtonFraction: 0.1)
            for f in c.flux where f.r > c.isco * 1.0005 {
                let value = nt.geometricFlux(r: f.r)
                // Closed form (Swift, double precision) vs. the 30-digit reference; near the inner edge the
                // bracket cancels, so allow a little more.
                let tolerance = f.r < c.isco * 1.05 ? 1e-6 : 1e-10
                #expect(approxEqual(value, f.closed, relative: tolerance), "a=\(c.a) r=\(f.r): \(value) vs \(f.closed)")
                #expect(approxEqual(f.closed, f.integral, relative: 1e-12), "reference self-consistency a=\(c.a) r=\(f.r)")
            }
        }
    }

    @Test func fluxPeaksOutsideTheInnerEdgeAndFallsAsRMinusThreeFarAway() {
        let nt = NovikovThorne(kerr: Kerr(spin: 0), massSolar: 10, eddingtonFraction: 0.1)
        let values = stride(from: 6.05, through: 60.0, by: 0.05).map { nt.geometricFlux(r: $0) }
        let peak = values.indices.max { values[$0] < values[$1] }!
        #expect(peak > 0 && peak < values.count - 1)
        // Far away F → 3/(8π r³) (Shakura–Sunyaev); the correction is O(1/√r) because the logarithmic terms of the
        // relativistic bracket are of the same order as the usual √(r_in/r) term.
        for r in [1e8, 1e10, 1e12] {
            let ratio = nt.geometricFlux(r: r) * 8 * Double.pi * r * r * r / 3
            #expect(abs(ratio - 1) < 6 / r.squareRoot(), "r=\(r): ratio \(ratio)")
        }
    }

    @Test func radiativeEfficiencyMatchesTheReference() {
        for c in fixture.cases {
            let nt = NovikovThorne(kerr: Kerr(spin: c.a), massSolar: 10, eddingtonFraction: 0.1)
            #expect(approxEqual(nt.radiativeEfficiency, c.efficiency, relative: 1e-12), "a=\(c.a)")
        }
        // Known values: 5.72 % for a = 0, 32.1 % for a = 0.998.
        #expect(abs(NovikovThorne(kerr: Kerr(spin: 0), massSolar: 1, eddingtonFraction: 1).radiativeEfficiency - 0.0572) < 1e-4)
        #expect(abs(NovikovThorne(kerr: Kerr(spin: 0.998), massSolar: 1, eddingtonFraction: 1).radiativeEfficiency - 0.321) < 1e-3)
    }

    @Test func temperatureIsTheBlackbodyTemperatureOfTheFlux() {
        for c in fixture.cases {
            let s = c.temperature_scale
            let nt = NovikovThorne(kerr: Kerr(spin: c.a), massSolar: s.mass_solar, eddingtonFraction: s.fraction)
            #expect(approxEqual(nt.accretionRate, s.mdot_kg_per_s, relative: 1e-6), "mdot a=\(c.a)")
            for (r, expected) in zip(s.radii, s.T) {
                // 1e-6: the reference uses SciPy's CODATA values, the renderer CODATA 2018.
                #expect(approxEqual(nt.temperature(r: r), expected, relative: 1e-6), "T a=\(c.a) r=\(r)")
                let f = nt.flux(r: r)
                #expect(approxEqual(PhysicalConstants.sigmaSB * pow(nt.temperature(r: r), 4), f, relative: 1e-12))
            }
        }
    }

    @Test func peakTemperatureBoundsTheProfile() {
        let nt = NovikovThorne(kerr: Kerr(spin: 0.5), massSolar: 10, eddingtonFraction: 0.1)
        let peak = nt.peakTemperature(upTo: 50)
        for r in stride(from: nt.iscoRadius, through: 50, by: 0.1) { #expect(nt.temperature(r: r) <= peak * (1 + 1e-9)) }
        #expect(peak > nt.temperature(r: 50) && peak > nt.temperature(r: nt.iscoRadius * 1.01))
    }

    // MARK: Shift factor

    @Test func shiftFactorMatchesTheMetricTensorReference() {
        for c in fixture.cases {
            let kerr = Kerr(spin: c.a)
            for s in c.shifts {
                let observer = kerr.metric(r: s.r_observer, mu: 0)
                let g = ShiftFactor.g(kerr: kerr, radius: s.r, angularMomentum: s.L, observerEnergy: 1 / (-observer.tt).squareRoot())
                #expect(approxEqual(g, s.g, relative: 1e-12), "a=\(c.a) r=\(s.r) L=\(s.L): \(g) vs \(s.g)")
            }
        }
    }

    @Test func faceOnSchwarzschildShiftIsGravitationalPlusTransverseDoppler() {
        let kerr = Kerr(spin: 0)
        for f in fixture.schwarzschild_face_on {
            let observer = kerr.metric(r: f.r_observer, mu: 0)
            let g = ShiftFactor.g(kerr: kerr, radius: f.r, angularMomentum: 0, observerEnergy: 1 / (-observer.tt).squareRoot())
            #expect(approxEqual(g, f.g, relative: 1e-13), "r=\(f.r)")
            #expect(g < 1)  // always redshifted when seen face-on
        }
    }

    @Test func approachingSideIsBlueshiftedRecedingSideRedshifted() {
        // Prograde photons (L > 0) leave the side of the disk that moves toward the observer.
        let kerr = Kerr(spin: 0.5)
        let observerEnergy = 1.0
        for r in [8.0, 12.0, 30.0] {
            let approaching = ShiftFactor.g(kerr: kerr, radius: r, angularMomentum: 6, observerEnergy: observerEnergy)
            let middle = ShiftFactor.g(kerr: kerr, radius: r, angularMomentum: 0, observerEnergy: observerEnergy)
            let receding = ShiftFactor.g(kerr: kerr, radius: r, angularMomentum: -6, observerEnergy: observerEnergy)
            #expect(approaching > middle && middle > receding, "r=\(r)")
            // Where the orbital speed is high the Doppler shift outweighs the gravitational redshift.
            if r <= 12 { #expect(approaching > 1 && receding < 1, "r=\(r): g=\(approaching) / \(receding)") }
        }
    }
}
