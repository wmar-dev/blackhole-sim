import Foundation
import Testing
@testable import BlackHoleKit

/// Equatorial-plane crossing detection, refinement and disk-hit classification (FR-004).
///
/// Reference: a Schwarzschild ray stays in one plane through the origin. In that plane the orbit
/// equation is d²u/dχ² + u = 3u² (u = 1/r, χ = angle along the path), integrated here with an
/// independent RK4. Equatorial crossings happen where the in-plane angle ψ from the ascending node is
/// a multiple of π.
@Suite struct PlaneCrossingTests {
    static let farAway = 1e5  // disk annulus placed beyond the sky radius: never hit

    /// Test ray: orbital-plane inclination `inclination`, impact parameter `b`, observer at r = 50.
    struct Orbit {
        let b: Double
        let inclination: Double  // radians, angle between the orbital angular momentum and +z; 0 < i < π
        let mu0: Double
        let polarSign: Double
        var constants: PhotonConstants {
            let l = b * cos(inclination)
            return PhotonConstants(energy: 1, angularMomentum: l, carter: b * b - l * l)
        }
    }

    static func makeRay(_ orbit: Orbit, observerRadius: Double = 50) -> CameraRay? {
        let integrator = GeodesicIntegrator(kerr: Kerr(spin: 0), constants: orbit.constants, settings: .standard(skyRadius: 1000))
        guard let state = integrator.initialState(r: observerRadius, mu: orbit.mu0, radialSign: -1, polarSign: orbit.polarSign) else { return nil }
        return CameraRay(constants: orbit.constants, state: state, observerEnergy: 1)
    }

    /// Independent prediction of the radii at the first `count` equatorial crossings.
    static func binetCrossingRadii(_ orbit: Orbit, ray: CameraRay, count: Int) -> [(radius: Double, face: DiskFace)] {
        let b = orbit.b
        let sinI = sin(orbit.inclination)
        let l = orbit.constants.angularMomentum
        // Backward tracing reverses the motion: the in-plane angle ψ changes by −sign(L) per unit path.
        let direction: Double = l > 0 ? -1 : 1
        let sinPsi0 = orbit.mu0 / sinI
        let cosPsi0 = ray.state.vmu / (b * sinI * direction)  // dμ/dχ = sin i cos ψ · dψ/dχ, and dχ/dλ′ = b
        let psi0 = atan2(sinPsi0, cosPsi0)

        // Path lengths χ_k at which ψ = kπ, ascending, strictly positive.
        var targets: [Double] = []
        var k = -10
        while targets.count < count + 12 && k < 60 {
            let chi = direction * (Double(k) * Double.pi - psi0)
            if chi > 1e-9 { targets.append(chi) }
            k += 1
        }
        targets.sort()
        targets = Array(targets.prefix(count))

        // RK4 on (u, w = du/dχ).
        var u = 1 / 50.0
        var w = (1 / (b * b) - u * u * (1 - 2 * u)).squareRoot()  // inbound at the start
        var chi = 0.0
        var radii: [(Double, DiskFace)] = []
        let h = 5e-5
        func f(_ u: Double, _ w: Double) -> (Double, Double) { (w, -u + 3 * u * u) }
        // The first crossing is approached from the side the ray starts on (or is moving toward, if it starts in the plane).
        var side: Double = orbit.mu0 != 0 ? (orbit.mu0 > 0 ? 1 : -1) : (ray.state.vmu > 0 ? 1 : -1)
        for target in targets {
            while chi < target {
                let step = min(h, target - chi)
                let (k1u, k1w) = f(u, w)
                let (k2u, k2w) = f(u + 0.5 * step * k1u, w + 0.5 * step * k1w)
                let (k3u, k3w) = f(u + 0.5 * step * k2u, w + 0.5 * step * k2w)
                let (k4u, k4w) = f(u + step * k3u, w + step * k3w)
                u += step / 6 * (k1u + 2 * k2u + 2 * k3u + k4u)
                w += step / 6 * (k1w + 2 * k2w + 2 * k3w + k4w)
                chi += step
            }
            radii.append((1 / u, side > 0 ? .upper : .lower))
            side = -side
        }
        return radii
    }

    static let tracerFar = RayTracer(kerr: Kerr(spin: 0), diskInnerRadius: farAway, diskOuterRadius: farAway + 1, skyRadius: 1000)

    static let criticalB = 3 * 3.0.squareRoot()

    /// b = b_c(1 + 10⁻³): the ray loops once around the photon sphere and crosses the plane three times.
    static let winding = Orbit(b: criticalB * (1 + 1e-3), inclination: 60 * Double.pi / 180,
                               mu0: 0.4 * sin(60 * Double.pi / 180), polarSign: 1)

    @Test func crossingRadiiMatchIndependentOrbitIntegration() throws {
        for polarSign in [1.0, -1.0] {
            for inclination in [60.0, 100.0] {
                let i = inclination * Double.pi / 180
                let orbit = Orbit(b: Self.criticalB * (1 + 1e-3), inclination: i, mu0: 0.4 * sin(i), polarSign: polarSign)
                let ray = try #require(Self.makeRay(orbit))
                let result = Self.tracerFar.trace(ray)
                #expect(result.crossings.count >= 2, "i=\(inclination) sign=\(polarSign): \(result.crossings.count) crossings")
                let reference = Self.binetCrossingRadii(orbit, ray: ray, count: result.crossings.count)
                for (found, expected) in zip(result.crossings, reference) {
                    #expect(approxEqual(found.radius, expected.radius, relative: 1e-7),
                            "crossing \(found.index): \(found.radius) vs \(expected.radius) (i=\(inclination), sign=\(polarSign))")
                    #expect(found.face == expected.face, "crossing \(found.index) face")
                    #expect(!found.insideDisk)
                }
                #expect(result.crossings.map(\.index) == Array(1...result.crossings.count))
            }
        }
    }

    @Test func faceAlternatesStartingFromTheObserversSide() throws {
        let above = try #require(Self.makeRay(Orbit(b: Self.criticalB * (1 + 1e-3), inclination: 1.0, mu0: 0.3, polarSign: 1)))
        let faces = Self.tracerFar.trace(above).crossings.map(\.face)
        #expect(faces.first == .upper)
        for (a, b) in zip(faces, faces.dropFirst()) { #expect(a != b) }
        let below = try #require(Self.makeRay(Orbit(b: Self.criticalB * (1 + 1e-3), inclination: 1.0, mu0: -0.3, polarSign: -1)))
        #expect(Self.tracerFar.trace(below).crossings.first?.face == .lower)
    }

    @Test func crossingInsideTheAnnulusEndsTheRayAtThatCrossing() throws {
        let ray = try #require(Self.makeRay(Self.winding))
        let radii = Self.tracerFar.trace(ray).crossings.map(\.radius)
        #expect(radii.count == 3)
        for target in 0..<3 {
            let others = radii.enumerated().filter { $0.offset != target }.map { abs($0.element - radii[target]) }
            let half = 0.3 * min(others.min() ?? 1, radii[target])
            let tracer = RayTracer(kerr: Kerr(spin: 0), diskInnerRadius: radii[target] - half, diskOuterRadius: radii[target] + half, skyRadius: 1000)
            let result = tracer.trace(ray)
            guard case .disk(let radius, let index, _) = result.outcome else {
                Issue.record("expected a disk hit at crossing \(target + 1), got \(result.outcome)")
                continue
            }
            #expect(index == target + 1)
            #expect(approxEqual(radius, radii[target], relative: 1e-12))
            #expect(result.crossings.count == target + 1, "the ray must stop at the hit")
            #expect(result.crossings.last?.insideDisk == true)
        }
    }

    @Test func crossingsOutsideTheAnnulusContinueAndTheCounterStopsDiskTestsAfterThree() throws {
        // Very close to critical: many loops, so more than three plane crossings are available.
        let manyLoops = Orbit(b: Self.criticalB * (1 + 1e-6), inclination: 60 * Double.pi / 180,
                              mu0: 0.4 * sin(60 * Double.pi / 180), polarSign: 1)
        let ray = try #require(Self.makeRay(manyLoops))
        // Use a tracer that records more crossings than it tests, to find the radius of the fourth crossing.
        let wide = RayTracer(kerr: Kerr(spin: 0), diskInnerRadius: Self.farAway, diskOuterRadius: Self.farAway + 1,
                             skyRadius: 1000, maxPlaneCrossings: 6)
        let radii = wide.trace(ray).crossings.map(\.radius)
        #expect(radii.count >= 5, "expected at least 5 crossings, got \(radii.count)")
        let fourth = radii[3]
        let narrow = 0.05 * min(abs(radii[3] - radii[2]), abs(radii[3] - radii[4]))
        let tracer = RayTracer(kerr: Kerr(spin: 0), diskInnerRadius: fourth - narrow, diskOuterRadius: fourth + narrow, skyRadius: 1000)
        let result = tracer.trace(ray)
        if case .disk = result.outcome { Issue.record("the fourth crossing must not be tested against the disk") }
        #expect(result.crossings.count == 3)
    }

    @Test func observerInThePlaneIsNotACrossingAtStart() throws {
        let orbit = Orbit(b: Self.criticalB * (1 + 1e-3), inclination: 60 * Double.pi / 180, mu0: 0, polarSign: 1)
        let ray = try #require(Self.makeRay(orbit))
        let result = Self.tracerFar.trace(ray)
        let reference = Self.binetCrossingRadii(orbit, ray: ray, count: result.crossings.count)
        #expect(result.crossings.count >= 2)
        for (found, expected) in zip(result.crossings, reference) {
            #expect(approxEqual(found.radius, expected.radius, relative: 1e-7), "crossing \(found.index)")
        }
    }

    @Test func equatorialRaysNeverCross() throws {
        for spin in [0.0, 0.9] {
            let kerr = Kerr(spin: spin)
            let constants = PhotonConstants(energy: 1, angularMomentum: 6, carter: 0)
            let integrator = GeodesicIntegrator(kerr: kerr, constants: constants, settings: .standard(skyRadius: 1000))
            let state = try #require(integrator.initialState(r: 50, mu: 0, radialSign: -1, polarSign: 1))
            let tracer = RayTracer(kerr: kerr, diskInnerRadius: Self.farAway, diskOuterRadius: Self.farAway + 1, skyRadius: 1000)
            let result = tracer.trace(CameraRay(constants: constants, state: state, observerEnergy: 1))
            #expect(result.crossings.isEmpty)
            if case .sky = result.outcome {} else { Issue.record("expected sky for a=\(spin), got \(result.outcome)") }
        }
    }

    @Test func plungingRayIsCaptured() throws {
        let constants = PhotonConstants(energy: 1, angularMomentum: 1, carter: 1)
        let integrator = GeodesicIntegrator(kerr: Kerr(spin: 0), constants: constants, settings: .standard(skyRadius: 1000))
        let state = try #require(integrator.initialState(r: 50, mu: 0.2, radialSign: -1, polarSign: 1))
        let result = Self.tracerFar.trace(CameraRay(constants: constants, state: state, observerEnergy: 1))
        #expect(result.outcome == .captured)
    }
}
