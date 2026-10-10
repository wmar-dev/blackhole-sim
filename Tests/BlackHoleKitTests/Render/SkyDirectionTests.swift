import Foundation
import simd
import Testing
@testable import BlackHoleKit

struct DeflectionFixture: Decodable {
    struct Deflection: Decodable { let b: Double; let alpha: Double }
    struct Sweep: Decodable { let b: Double; let r_observer: Double; let delta_psi: Double }
    struct Ring: Decodable { let b: Double; let r_observer: Double; let local_angle: Double }
    let critical_b: Double
    let deflection: [Deflection]
    let sweeps: [Sweep]
    let einstein_ring: Ring
}

/// The direction assigned to a ray at the sky radius (research.md D6).
/// Reference: exact Schwarzschild in-plane sweep from tools/reference/schwarzschild_deflection.py.
@Suite struct SkyDirectionTests {
    let fixture: DeflectionFixture

    init() throws { fixture = try Fixture.load("schwarzschild_deflection") }

    /// Traces an equatorial ray (φ_o = 0) with impact parameter `b` from r = 100 to the sky radius.
    private func traced(b: Double, skyRadius: Double = 1000) -> (state: RayState, direction: SIMD3<Double>, constants: PhotonConstants) {
        let kerr = Kerr(spin: 0)
        let constants = PhotonConstants(energy: 1, angularMomentum: b, carter: 0)
        let integrator = GeodesicIntegrator(kerr: kerr, constants: constants, settings: .standard(skyRadius: skyRadius))
        let start = integrator.initialState(r: 100, mu: 0, radialSign: -1, polarSign: 1)!
        let result = integrator.integrate(from: start)
        precondition(result.termination == .sky)
        return (result.state, AsymptoticDirection.direction(of: result.state, constants: constants, kerr: kerr), constants)
    }

    @Test func fixtureIsConsistentWithWeakFieldDeflection() {
        for d in fixture.deflection where d.b >= 50 {
            #expect(approxEqual(d.alpha, 4 / d.b, relative: 0.1))
        }
        #expect(approxEqual(fixture.critical_b, 3 * 3.0.squareRoot(), relative: 1e-14))
    }

    @Test func directionOfTravelMatchesExactAsymptoticDirection() {
        var worst = 0.0
        for sweep in fixture.sweeps {
            let t = traced(b: sweep.b)
            // Equatorial ray from φ = 0: the exact outgoing direction is (cos Δψ, −sin Δψ, 0) (φ decreases along the trace).
            let expected = SIMD3(cos(sweep.delta_psi), -sin(sweep.delta_psi), 0)
            let error = simd_length(t.direction - expected)
            worst = max(worst, error)
            #expect(error < 2e-4, "b=\(sweep.b): direction error \(error) rad")
        }
        print("SKYDIR worst direction error: \(worst) rad")
    }

    @Test func assigningThePositionDirectionInsteadExceedsTheBound() {
        // The naive lookup (angles of the final position) is off by about b/r_sky, far above 1e-3 rad
        // for the impact parameters that matter.
        var exceeded = 0
        for sweep in fixture.sweeps where sweep.b >= 6 {
            let t = traced(b: sweep.b)
            let expected = SIMD3(cos(sweep.delta_psi), -sin(sweep.delta_psi), 0)
            let naive = AsymptoticDirection.positionDirection(of: t.state)
            let error = simd_length(naive - expected)
            if error > 1e-3 { exceeded += 1 }
            #expect(error > 0.5 * sweep.b / 1000, "b=\(sweep.b): naive error \(error)")
        }
        #expect(exceeded == fixture.sweeps.count)
    }

    @Test func largerSkyRadiusImprovesTheAssignedDirection() {
        let sweep = fixture.sweeps.first { $0.b == 10 }!
        let expected = SIMD3(cos(sweep.delta_psi), -sin(sweep.delta_psi), 0)
        let near = simd_length(traced(b: 10, skyRadius: 300).direction - expected)
        let far = simd_length(traced(b: 10, skyRadius: 3000).direction - expected)
        #expect(far < near)
    }
}
