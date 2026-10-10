import Foundation
import Testing
@testable import BlackHoleKit

/// Weak-field deflection and the Schwarzschild critical impact parameter (SC-004, FR-011).
@Suite struct DeflectionTests {
    /// Equatorial Schwarzschild ray with impact parameter `b`, started inbound at `r0`, traced until it
    /// returns to `r0`. Returns the deflection angle with the finite-radius straight-line baseline removed.
    private func deflection(b: Double, r0: Double) -> (alpha: Double, termination: RayTermination) {
        let kerr = Kerr(spin: 0)
        let constants = PhotonConstants(energy: 1, angularMomentum: b, carter: 0)
        var settings = IntegratorSettings.standard(skyRadius: r0)
        settings.stepBudget = 1_000_000
        let integrator = GeodesicIntegrator(kerr: kerr, constants: constants, settings: settings)
        let start = integrator.initialState(r: r0, mu: 0, radialSign: -1, polarSign: 1)!
        let result = integrator.integrate(from: start)
        // λ' runs backward along the physical ray, so φ' = −L/(1−μ²) and φ decreases.
        let swept = abs(result.state.phi - start.phi)
        // A straight line with impact parameter b, between radius r0 inbound and the actual exit radius,
        // subtends (π/2 − arcsin(b/r0)) + (π/2 − arcsin(b/r_exit)).
        let flatBaseline = Double.pi - asin(b / r0) - asin(b / result.state.r)
        return (swept - flatBaseline, result.termination)
    }

    @Test func weakFieldDeflectionMatchesFourMOverB() {
        for b in [500.0, 1000.0, 5000.0] {
            let (alpha, termination) = deflection(b: b, r0: 1e5)
            #expect(termination == .sky)
            #expect(approxEqual(alpha, 4 / b, relative: 0.01), "b=\(b): alpha=\(alpha) vs 4/b=\(4 / b)")
        }
    }

    @Test func weakFieldDeflectionMatchesHigherOrderExpansion() {
        // α = 4/b + (15π/4)/b² + (128/3)/b³ + O(b⁻⁴)  (Schwarzschild, M = 1)
        for b in [50.0, 100.0, 1000.0] {
            let series = 4 / b + 15 * Double.pi / 4 / (b * b) + 128.0 / 3.0 / (b * b * b)
            let (alpha, _) = deflection(b: b, r0: 1e5)
            #expect(approxEqual(alpha, series, relative: 1e-3), "b=\(b): alpha=\(alpha) vs series=\(series)")
        }
    }

    @Test func criticalImpactParameterSeparatesCaptureFromEscape() {
        let kerr = Kerr(spin: 0)
        let critical = 3 * 3.0.squareRoot()
        func outcome(_ b: Double) -> RayTermination {
            let constants = PhotonConstants(energy: 1, angularMomentum: b, carter: 0)
            let integrator = GeodesicIntegrator(kerr: kerr, constants: constants,
                                                settings: .standard(skyRadius: 1000))
            let start = integrator.initialState(r: 100, mu: 0, radialSign: -1, polarSign: 1)!
            return integrator.integrate(from: start).termination
        }
        #expect(outcome(critical * (1 - 1e-3)) == .horizon)
        #expect(outcome(critical * (1 + 1e-3)) == .sky)
        #expect(outcome(critical * (1 - 1e-6)) == .horizon)
        #expect(outcome(critical * (1 + 1e-6)) == .sky)
    }
}
