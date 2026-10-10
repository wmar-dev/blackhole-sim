import Foundation
import Testing
@testable import BlackHoleKit

/// First-integral residuals and convergence (FR-008, SC-003, Constitution Principle IV).
/// Bounds come from docs/tolerances.md.
@Suite struct ResidualTests {
    static let residualBound = 1e-6
    static let convergenceBound = 1e-6  // rad

    struct Scenario: CustomStringConvertible, Sendable {
        let name: String
        let spin: Double
        let constants: PhotonConstants
        let mu0: Double
        let r0: Double
        var description: String { name }
    }

    /// Finds L (at fixed Q/L²) at which the ray just barely escapes: a near-critical ray. Scans for the first
    /// captured → escaping transition among values where the ray exists at the observer, then bisects.
    /// Returns nil if the ray does not exist over the scanned range (e.g. large L near the spin axis).
    static func nearCriticalL(spin: Double, qRatio: Double, mu0: Double) -> Double? {
        enum Status { case none, captured, escapes }
        let kerr = Kerr(spin: spin)
        func status(_ l: Double) -> Status {
            let c = PhotonConstants(energy: 1, angularMomentum: l, carter: qRatio * l * l)
            let integ = GeodesicIntegrator(kerr: kerr, constants: c, settings: .standard(skyRadius: 1000))
            guard let s = integ.initialState(r: 100, mu: mu0, radialSign: -1, polarSign: 1) else { return .none }
            return integ.integrate(from: s).termination == .horizon ? .captured : .escapes
        }
        var previous: (l: Double, status: Status)?
        for l in stride(from: 0.5, through: 30.0, by: 0.25) {
            let now = status(l)
            defer { if now != .none { previous = (l, now) } }
            guard now == .escapes, let p = previous, p.status == .captured else { continue }
            var lo = p.l, hi = l
            for _ in 0..<45 {
                let mid = 0.5 * (lo + hi)
                switch status(mid) {
                case .captured: lo = mid
                case .escapes: hi = mid
                case .none: return nil
                }
            }
            return hi
        }
        return nil
    }

    static let scenarios: [Scenario] = {
        var list: [Scenario] = []
        let mu0 = cos(80.0 * Double.pi / 180)
        for a in [0.0, 0.9] {
            for (l, qr) in [(6.0, 0.1), (3.0, 1.0), (-4.0, 0.5), (9.0, 0.2), (1.0, 6.0)] {
                list.append(Scenario(name: "a=\(a) L=\(l) Q/L²=\(qr)", spin: a,
                                     constants: PhotonConstants(energy: 1, angularMomentum: l, carter: qr * l * l),
                                     mu0: mu0, r0: 100))
            }
            for qr in [0.1, 0.5] {
                guard let l = nearCriticalL(spin: a, qRatio: qr, mu0: mu0) else { continue }
                list.append(Scenario(name: "a=\(a) near-critical Q/L²=\(qr)", spin: a,
                                     constants: PhotonConstants(energy: 1, angularMomentum: l, carter: qr * l * l),
                                     mu0: mu0, r0: 100))
            }
            // Meridional ray through the spin axis: L = 0.
            list.append(Scenario(name: "a=\(a) axis L=0", spin: a,
                                 constants: PhotonConstants(energy: 1, angularMomentum: 0, carter: 20),
                                 mu0: 0.3, r0: 100))
            // Equatorial-plane ray (μ stays 0) and an observer exactly in the plane.
            list.append(Scenario(name: "a=\(a) equatorial", spin: a,
                                 constants: PhotonConstants(energy: 1, angularMomentum: 7, carter: 0),
                                 mu0: 0, r0: 100))
        }
        return list
    }()

    static func checkResidual(_ s: Scenario) throws {
        let integ = GeodesicIntegrator(kerr: Kerr(spin: s.spin), constants: s.constants,
                                       settings: .standard(skyRadius: 1000))
        let start = try #require(integ.initialState(r: s.r0, mu: s.mu0, radialSign: -1, polarSign: 1))
        let result = integ.integrate(from: start)
        #expect(result.termination == .sky || result.termination == .horizon, "\(s)")
        #expect(result.maxResidual < residualBound, "\(s): residual \(result.maxResidual)")
        #expect(result.steps < NumericalDefaults.stepBudget)
    }

    static func checkConvergence(_ s: Scenario) throws {
        func run(_ rtol: Double) -> (IntegrationResult, RayState)? {
            var settings = IntegratorSettings.standard(skyRadius: 1000)
            settings.relativeTolerance = rtol
            settings.absoluteTolerance = rtol * 1e-3
            let integ = GeodesicIntegrator(kerr: Kerr(spin: s.spin), constants: s.constants, settings: settings)
            guard let start = integ.initialState(r: s.r0, mu: s.mu0, radialSign: -1, polarSign: 1) else { return nil }
            return (integ.integrate(from: start), start)
        }
        let coarse = try #require(run(NumericalDefaults.relativeTolerance))
        let fine = try #require(run(NumericalDefaults.relativeTolerance / 10))
        guard coarse.0.termination == .sky, fine.0.termination == .sky else { return }  // captured rays have no exit angle
        let dMu = abs(coarse.0.state.mu - fine.0.state.mu)
        let dPhi = abs(coarse.0.state.phi - fine.0.state.phi)
        #expect(dMu < convergenceBound, "\(s): Δμ=\(dMu)")
        #expect(dPhi < convergenceBound, "\(s): Δφ=\(dPhi)")
    }

    @Test(arguments: scenarios)
    func residualsStayBelowBound(_ s: Scenario) throws { try Self.checkResidual(s) }

    @Test(arguments: scenarios)
    func tighteningToleranceChangesFinalAnglesLessThanBound(_ s: Scenario) throws { try Self.checkConvergence(s) }

    /// Spin sweep (task T047): rapidly spinning cases at several inclinations, including near-critical rays.
    static let spinScenarios: [Scenario] = {
        var list: [Scenario] = []
        for a in [0.5, 0.9, 0.998] {
            for inclination in [10.0, 45.0, 80.0, 90.0] {
                let mu0 = cos(inclination * Double.pi / 180)
                for (l, qr) in [(4.0, 0.5), (-5.0, 1.0), (8.0, 0.3), (1.5, 4.0)] {
                    let q = qr * l * l
                    // Skip combinations whose polar potential is negative at the observer.
                    let theta = Kerr(spin: a).polarPotential(mu: mu0, constants: PhotonConstants(energy: 1, angularMomentum: l, carter: q))
                    guard theta >= 0 else { continue }
                    list.append(Scenario(name: "a=\(a) i=\(inclination) L=\(l) Q/L²=\(qr)", spin: a,
                                         constants: PhotonConstants(energy: 1, angularMomentum: l, carter: q), mu0: mu0, r0: 100))
                }
                // Near-critical ray at this spin and inclination (fixed Q/L²).
                let qr = 0.6
                guard let l = nearCriticalL(spin: a, qRatio: qr, mu0: mu0) else { continue }
                list.append(Scenario(name: "a=\(a) i=\(inclination) near-critical", spin: a,
                                     constants: PhotonConstants(energy: 1, angularMomentum: l, carter: qr * l * l), mu0: mu0, r0: 100))
            }
        }
        return list
    }()

    @Test(arguments: spinScenarios)
    func spinSweepResidualsStayBelowBound(_ s: Scenario) throws { try Self.checkResidual(s) }

    @Test(arguments: spinScenarios)
    func spinSweepConvergence(_ s: Scenario) throws { try Self.checkConvergence(s) }
}
