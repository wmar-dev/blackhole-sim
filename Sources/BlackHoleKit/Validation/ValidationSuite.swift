import Foundation

/// One validation check: a measured value compared with an independent reference (FR-011).
public struct ValidationCheck: Sendable {
    public enum Tolerance: Sendable {
        case relative(Double)
        case absolute(Double)
    }

    public let name: String
    public let measured: Double
    public let reference: Double
    public let tolerance: Tolerance

    public var passed: Bool {
        guard measured.isFinite else { return false }
        switch tolerance {
        case .relative(let t): return abs(measured - reference) <= t * max(abs(reference), 1e-300)
        case .absolute(let t): return abs(measured - reference) <= t
        }
    }
}

/// The built-in physics checks behind `bhsim validate`.
///
/// Reference values are literals from the independent high-precision computations in `tools/reference/`
/// or closed forms; none is computed by the code under test. The full test suite goes further (fixtures,
/// sweeps over spin and inclination); this is the quick end-to-end smoke test a user can run.
public enum ValidationSuite {
    public static func run() -> [ValidationCheck] {
        var checks: [ValidationCheck] = []
        func add(_ name: String, _ measured: Double, _ reference: Double, _ tolerance: ValidationCheck.Tolerance) {
            checks.append(ValidationCheck(name: name, measured: measured, reference: reference, tolerance: tolerance))
        }

        // Horizon, ISCO, circular photon orbit (kerr_basic.py).
        add("horizon radius, a = 0", Kerr(spin: 0).horizonRadius, 2.0, .relative(1e-12))
        add("horizon radius, a = 0.9", Kerr(spin: 0.9).horizonRadius, 1.4358898943540674, .relative(1e-12))
        add("ISCO radius, a = 0", Kerr(spin: 0).iscoRadius, 6.0, .relative(1e-12))
        add("ISCO radius, a = 0.9", Kerr(spin: 0.9).iscoRadius, 2.320883041761887, .relative(1e-12))
        add("ISCO radius, a = 0.998", Kerr(spin: 0.998).iscoRadius, 1.2369706551751842, .relative(1e-12))
        add("photon sphere radius, a = 0", Kerr(spin: 0).photonOrbitRadius(prograde: true), 3.0, .relative(1e-12))

        // Critical impact parameter 3√3, found by bisection on whether the ray is captured.
        add("critical impact parameter, a = 0", criticalImpactParameter(), 3 * 3.0.squareRoot(), .relative(1e-6))

        // Weak-field deflection vs. the exact value (schwarzschild_deflection.py): b = 100.
        add("light deflection at b = 100 (exact 0.041222…)", deflection(b: 100), 0.04122253974927365, .relative(1e-3))
        add("light deflection at b = 1000 vs. 4M/b (SC-004)", deflection(b: 1000), 4.0 / 1000, .relative(0.01))

        // Direction assigned to a ray reaching the sky (exact in-plane sweep, b = 10, observer at r = 100).
        add("sky direction error at b = 10 (rad)", skyDirectionError(b: 10, deltaPsi: 3.631823545), 0, .absolute(2e-4))

        // First-integral residuals along a sample of rays (FR-008).
        add("max first-integral residual over 64 rays", maxResidual(), 0, .absolute(1e-6))

        // Shadow outline (SC-001, SC-002): tangent-plane radius of the shadow edge, bisection on capture.
        let alpha = asin(3 * 3.0.squareRoot() * (1 - 2.0 / 100).squareRoot() / 100)
        add("shadow radius, a = 0 (tan of the angular radius)", shadowEdge(spin: 0, inclination: 90, direction: 0), tan(alpha), .relative(1e-3))
        add("shadow edge, a = 0.9, i = 90°, right", shadowEdge(spin: 0.9, inclination: 90, direction: 0), 0.06760569701753824, .relative(1e-3))
        add("shadow edge, a = 0.9, i = 90°, left", shadowEdge(spin: 0.9, inclination: 90, direction: Double.pi), 0.028350812380173774, .relative(1e-3))

        // Novikov–Thorne flux per unit accretion rate (novikov_thorne.py, 30-digit reference).
        let schwarzschild = NovikovThorne(kerr: Kerr(spin: 0), massSolar: 10, eddingtonFraction: 0.1)
        add("disk flux F(r_isco), a = 0 (zero torque)", schwarzschild.geometricFlux(r: 6), 0, .absolute(0))
        add("disk flux F(18), a = 0", schwarzschild.geometricFlux(r: 18), 5.8899390972448975e-06, .relative(1e-10))
        add("disk flux F(60), a = 0", schwarzschild.geometricFlux(r: 60), 3.12696632674882e-07, .relative(1e-10))
        let spinning = NovikovThorne(kerr: Kerr(spin: 0.9), massSolar: 10, eddingtonFraction: 0.1)
        add("disk flux F(23.2088…), a = 0.9", spinning.geometricFlux(r: 23.208830417618874), 5.336451876772117e-06, .relative(1e-10))
        add("radiative efficiency, a = 0 (1 − √(8/9))", schwarzschild.radiativeEfficiency, 1 - (8.0 / 9).squareRoot(), .relative(1e-12))

        // Shift factor of face-on Schwarzschild emission, √(1 − 3/r)/√(1 − 2/r_o) with r_o = 100.
        let flat = Kerr(spin: 0)
        let observerEnergy = 1 / (1 - 2.0 / 100).squareRoot()
        add("shift factor g, face-on, r = 6", ShiftFactor.g(kerr: flat, radius: 6, angularMomentum: 0, observerEnergy: observerEnergy), 0.7142857142857143, .relative(1e-12))
        add("shift factor g, face-on, r = 20", ShiftFactor.g(kerr: flat, radius: 20, angularMomentum: 0, observerEnergy: observerEnergy), 0.9313146293146641, .relative(1e-12))

        // Determinism (FR-009): two renders of a small image are bit-identical.
        add("determinism: pixels differing between two renders", determinismDifference(), 0, .absolute(0))
        return checks
    }

    // MARK: Measurements

    private static func criticalImpactParameter() -> Double {
        let kerr = Kerr(spin: 0)
        func captured(_ b: Double) -> Bool {
            let integrator = GeodesicIntegrator(kerr: kerr, constants: PhotonConstants(energy: 1, angularMomentum: b, carter: 0),
                                                settings: .standard(skyRadius: 1000))
            let start = integrator.initialState(r: 100, mu: 0, radialSign: -1, polarSign: 1)!
            return integrator.integrate(from: start).termination == .horizon
        }
        var lo = 4.0, hi = 6.0
        for _ in 0..<50 {
            let mid = 0.5 * (lo + hi)
            if captured(mid) { lo = mid } else { hi = mid }
        }
        return 0.5 * (lo + hi)
    }

    private static func deflection(b: Double) -> Double {
        let r0 = 1e5
        let integrator = GeodesicIntegrator(kerr: Kerr(spin: 0), constants: PhotonConstants(energy: 1, angularMomentum: b, carter: 0),
                                            settings: .standard(skyRadius: r0))
        let start = integrator.initialState(r: r0, mu: 0, radialSign: -1, polarSign: 1)!
        let result = integrator.integrate(from: start)
        let swept = abs(result.state.phi - start.phi)
        return swept - (Double.pi - asin(b / r0) - asin(b / result.state.r))
    }

    private static func skyDirectionError(b: Double, deltaPsi: Double) -> Double {
        let kerr = Kerr(spin: 0)
        let constants = PhotonConstants(energy: 1, angularMomentum: b, carter: 0)
        let integrator = GeodesicIntegrator(kerr: kerr, constants: constants, settings: .standard(skyRadius: 1000))
        let start = integrator.initialState(r: 100, mu: 0, radialSign: -1, polarSign: 1)!
        let state = integrator.integrate(from: start).state
        let direction = AsymptoticDirection.direction(of: state, constants: constants, kerr: kerr)
        let expected = SIMD3(cos(deltaPsi), -sin(deltaPsi), 0)
        let d = direction - expected
        return (d * d).sum().squareRoot()
    }

    private static func maxResidual() -> Double {
        let kerr = Kerr(spin: 0.9)
        let mu0 = cos(80.0 * Double.pi / 180)
        var worst = 0.0
        for i in 0..<64 {
            let l = -9 + 18 * Double(i % 8) / 7
            let q = 1 + 12 * Double(i / 8)
            let constants = PhotonConstants(energy: 1, angularMomentum: l, carter: q)
            let integrator = GeodesicIntegrator(kerr: kerr, constants: constants, settings: .standard(skyRadius: 1000))
            guard let start = integrator.initialState(r: 100, mu: mu0, radialSign: -1, polarSign: 1) else { continue }
            worst = max(worst, integrator.integrate(from: start).maxResidual)
        }
        return worst
    }

    private static func shadowEdge(spin: Double, inclination: Double, direction: Double) -> Double {
        var config = RenderConfig()
        config.blackHole.spin = spin
        config.observer.inclinationDegrees = inclination
        config.diskEnabled = false
        config.width = 400
        config.height = 400
        let renderer = try! Renderer(config: config)
        let scale = 400 / (2 * tan(config.observer.fieldOfViewDegrees * Double.pi / 360))  // pixels per unit tangent
        let center = SIMD2(200.0, 200.0)
        let d = SIMD2(cos(direction), -sin(direction))
        func captured(_ rho: Double) -> Bool {
            let p = center + d * rho * scale
            return renderer.trace(pixelX: p.x, pixelY: p.y).outcome == .captured
        }
        var lo = 0.0, hi = 0.2
        for _ in 0..<40 {
            let mid = 0.5 * (lo + hi)
            if captured(mid) { lo = mid } else { hi = mid }
        }
        return 0.5 * (lo + hi)
    }

    private static func determinismDifference() -> Double {
        var config = RenderConfig()
        config.width = 32
        config.height = 18
        config.samplesPerPixel = 4
        config.sky = SkyConfig(kind: .starfield, seed: 3, starCount: 5000)
        let renderer = try! Renderer(config: config)
        let a = renderer.render(maxConcurrency: 1)
        let b = renderer.render()
        return Double(zip(a.hdr, b.hdr).filter { $0 != $1 }.count)
    }
}
