import Dispatch
import Foundation
import Testing
@testable import BlackHoleKit

/// Early performance measurement (research.md §Risks). Skipped unless `BHSIM_BENCH=1`; run in release:
///
///     BHSIM_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter IntegratorBenchmark
@Suite struct IntegratorBenchmarkTests {
    /// Rays like those of a 30° field of view from r = 100 at 80° inclination, built directly from
    /// (E, L, Q) using Bardeen's celestial coordinates (α, β) for a distant observer.
    static func sampleConstants(spin: Double, count: Int) -> [(PhotonConstants, Double)] {
        let thetaO = 80.0 * Double.pi / 180
        let mu0 = cos(thetaO)
        let side = Int(Double(count).squareRoot())
        let half = 100 * tan(15.0 * Double.pi / 180)
        var out: [(PhotonConstants, Double)] = []
        for i in 0..<side {
            for j in 0..<side {
                let alpha = (Double(i) + 0.5) / Double(side) * 2 * half - half
                let beta = (Double(j) + 0.5) / Double(side) * 2 * half - half
                let l = -alpha * sin(thetaO)
                let q = beta * beta + (alpha * alpha - spin * spin) * mu0 * mu0
                out.append((PhotonConstants(energy: 1, angularMomentum: l, carter: q), mu0))
            }
        }
        return out
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["BHSIM_BENCH"] == "1"))
    func measureRaysPerSecond() {
        let spin = 0.9
        let kerr = Kerr(spin: spin)
        let rays = Self.sampleConstants(spin: spin, count: 1024)
        let clock = ContinuousClock()

        var totalSteps = 0
        var captured = 0
        let singleStart = clock.now
        for (constants, mu0) in rays {
            let integrator = GeodesicIntegrator(kerr: kerr, constants: constants, settings: .standard(skyRadius: 1000))
            guard let s = integrator.initialState(r: 100, mu: mu0, radialSign: -1, polarSign: 1) else { continue }
            let result = integrator.integrate(from: s)
            totalSteps += result.steps
            if result.termination == .horizon { captured += 1 }
        }
        let single = clock.now - singleStart
        let singleSeconds = Double(single.components.seconds) + Double(single.components.attoseconds) * 1e-18

        final class Counter: @unchecked Sendable { var value = 0 }
        _ = Counter()
        let parallelStart = clock.now
        let chunk = 16
        DispatchQueue.concurrentPerform(iterations: rays.count / chunk) { c in
            var local = 0
            for k in 0..<chunk {
                let (constants, mu0) = rays[c * chunk + k]
                let integrator = GeodesicIntegrator(kerr: kerr, constants: constants, settings: .standard(skyRadius: 1000))
                guard let s = integrator.initialState(r: 100, mu: mu0, radialSign: -1, polarSign: 1) else { continue }
                local += integrator.integrate(from: s).steps
            }
            _ = local
        }
        let parallel = clock.now - parallelStart
        let parallelSeconds = Double(parallel.components.seconds) + Double(parallel.components.attoseconds) * 1e-18

        let n = Double(rays.count)
        let raysPerSecondSingle = n / singleSeconds
        let raysPerSecondParallel = n / parallelSeconds
        let totalRays = 1920.0 * 1080.0 * 4
        print("BENCH rays=\(rays.count) captured=\(captured) meanSteps=\(Double(totalSteps) / n)")
        print("BENCH single-thread: \(raysPerSecondSingle) rays/s; parallel: \(raysPerSecondParallel) rays/s on \(ProcessInfo.processInfo.activeProcessorCount) cores")
        print("BENCH projected 1080p x 4spp integrate-only time: \(totalRays / raysPerSecondParallel) s")
    }
}
