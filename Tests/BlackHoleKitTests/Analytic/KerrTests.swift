import Foundation
import Testing
@testable import BlackHoleKit

struct KerrBasicFixture: Decodable {
    struct Case: Decodable {
        struct OmegaSample: Decodable { let r: Double; let omega: Double }
        struct ErgoSample: Decodable { let mu: Double; let r: Double }
        let a: Double
        let horizon: Double
        let isco: Double
        let photon_orbit_prograde: Double
        let photon_orbit_retrograde: Double
        let omega: [OmegaSample]
        let ergosphere: [ErgoSample]
    }
    struct Potential: Decodable {
        let a: Double, E: Double, L: Double, Q: Double, r: Double, mu: Double, R: Double, theta_mu: Double
    }
    let cases: [Case]
    let potentials: [Potential]
}

@Suite struct KerrTests {
    let fixture: KerrBasicFixture

    init() throws {
        fixture = try Fixture.load("kerr_basic")
    }

    @Test func horizonIscoPhotonOrbitAndOmegaMatchReference() {
        for c in fixture.cases {
            let kerr = Kerr(spin: c.a)
            #expect(approxEqual(kerr.horizonRadius, c.horizon, relative: 1e-13), "horizon a=\(c.a)")
            #expect(approxEqual(kerr.iscoRadius, c.isco, relative: 1e-12), "isco a=\(c.a)")
            #expect(approxEqual(kerr.photonOrbitRadius(prograde: true), c.photon_orbit_prograde, relative: 1e-12))
            #expect(approxEqual(kerr.photonOrbitRadius(prograde: false), c.photon_orbit_retrograde, relative: 1e-12))
            for s in c.omega {
                #expect(approxEqual(kerr.keplerianOmega(r: s.r), s.omega, relative: 1e-13), "omega a=\(c.a) r=\(s.r)")
            }
            for s in c.ergosphere {
                #expect(approxEqual(kerr.ergosphereRadius(mu: s.mu), s.r, relative: 1e-13), "ergosphere a=\(c.a) mu=\(s.mu)")
            }
        }
    }

    @Test func schwarzschildClosedForms() {
        let kerr = Kerr(spin: 0)
        #expect(kerr.horizonRadius == 2)
        #expect(approxEqual(kerr.iscoRadius, 6, relative: 1e-14))
        #expect(approxEqual(kerr.photonOrbitRadius(prograde: true), 3, relative: 1e-14))

        // Critical impact parameter b_c = 3√3: R has a double root at the photon sphere r = 3.
        let critical = PhotonConstants(energy: 1, angularMomentum: 3 * 3.0.squareRoot(), carter: 0)
        #expect(abs(kerr.radialPotential(r: 3, constants: critical)) < 1e-12)
        #expect(abs(kerr.radialPotentialDerivative(r: 3, constants: critical)) < 1e-12)
        // Slightly smaller b: no turning point (R > 0 everywhere outside); slightly larger: turning point exists.
        let smaller = PhotonConstants(energy: 1, angularMomentum: 5.1, carter: 0)
        let larger = PhotonConstants(energy: 1, angularMomentum: 5.3, carter: 0)
        #expect(kerr.radialPotential(r: 3, constants: smaller) > 0)
        #expect(kerr.radialPotential(r: 3, constants: larger) < 0)
    }

    @Test func potentialsMatchHamiltonianReference() {
        #expect(!fixture.potentials.isEmpty)
        for p in fixture.potentials {
            let kerr = Kerr(spin: p.a)
            let c = PhotonConstants(energy: p.E, angularMomentum: p.L, carter: p.Q)
            let scale = (p.r * p.r + p.a * p.a) * (p.r * p.r + p.a * p.a)
            #expect(approxEqual(kerr.radialPotential(r: p.r, constants: c), p.R, relative: 1e-10, scale: scale * 1e-6),
                    "R a=\(p.a) r=\(p.r) L=\(p.L) Q=\(p.Q)")
            #expect(approxEqual(kerr.polarPotential(mu: p.mu, constants: c), p.theta_mu, relative: 1e-10, scale: 1e-9),
                    "Theta_mu a=\(p.a) mu=\(p.mu) L=\(p.L) Q=\(p.Q)")
        }
    }

    @Test func potentialDerivativesMatchFiniteDifferences() {
        let kerr = Kerr(spin: 0.9)
        let c = PhotonConstants(energy: 1, angularMomentum: 2.3, carter: 11.0)
        for r in [2.0, 3.7, 9.0, 40.0] {
            let h = 1e-6 * r
            let numeric = (kerr.radialPotential(r: r + h, constants: c) - kerr.radialPotential(r: r - h, constants: c)) / (2 * h)
            #expect(approxEqual(kerr.radialPotentialDerivative(r: r, constants: c), numeric, relative: 1e-7, scale: 1e-3), "R' r=\(r)")
        }
        for mu in [-0.8, -0.1, 0.0, 0.35, 0.9] {
            let h = 1e-6
            let numeric = (kerr.polarPotential(mu: mu + h, constants: c) - kerr.polarPotential(mu: mu - h, constants: c)) / (2 * h)
            #expect(approxEqual(kerr.polarPotentialDerivative(mu: mu, constants: c), numeric, relative: 1e-7, scale: 1e-3), "Theta' mu=\(mu)")
        }
    }

    @Test func metricIsSymmetricWithLorentzianSignature() {
        for a in [0.0, 0.5, 0.9, 0.998] {
            let kerr = Kerr(spin: a)
            for (r, mu) in [(3.0, 0.3), (10.0, 0.0), (50.0, -0.7), (2.5, 0.95)] {
                let g = kerr.metric(r: r, mu: mu)
                let sin2 = 1 - mu * mu
                let delta = kerr.delta(r: r)
                // det of the (t, φ) block is −Δ sin²θ; g_rr, g_θθ > 0 gives signature (−,+,+,+) when Δ > 0.
                let blockDet = g.tt * g.phiphi - g.tphi * g.tphi
                #expect(approxEqual(blockDet, -delta * sin2, relative: 1e-12), "block det a=\(a) r=\(r)")
                #expect(g.rr > 0 && g.thth > 0 && g.phiphi > 0)
            }
        }
    }

    @Test func keplerianAngularVelocityIsPrograde() {
        let kerr = Kerr(spin: 0.9)
        #expect(kerr.keplerianOmega(r: 6) > 0)
        #expect(kerr.keplerianOmega(r: 6) < kerr.keplerianOmega(r: 3))
    }
}
