import Foundation
import Testing
@testable import BlackHoleKit

/// Static-observer tetrad and pinhole camera (FR-002a, research.md D4).
@Suite struct CameraTests {
    static let spins = [0.0, 0.5, 0.9]
    static let positions: [(r: Double, mu: Double)] = [(100, 0.17), (30, 0.0), (8, -0.6), (4, 0.95)]

    @Test func tetradIsOrthonormalAndTimeLikeLegIsStatic() {
        for a in Self.spins {
            for p in Self.positions {
                let kerr = Kerr(spin: a)
                guard p.r > kerr.ergosphereRadius(mu: p.mu) else { continue }
                let t = StaticTetrad(kerr: kerr, radius: p.r, mu: p.mu)
                let legs = [t.e0, t.er, t.etheta, t.ephi]
                let eta: [[Double]] = [[-1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
                for i in 0..<4 {
                    for j in 0..<4 {
                        #expect(abs(t.dot(legs[i], legs[j]) - eta[i][j]) < 1e-12, "a=\(a) r=\(p.r) mu=\(p.mu) (\(i),\(j))")
                    }
                }
                // e₀ ∝ ∂_t: a static observer has no spatial velocity.
                #expect(t.e0[1] == 0 && t.e0[2] == 0 && t.e0[3] == 0 && t.e0[0] > 0)
                // Spatial legs point along +r, +θ and (frame-corrected) +φ.
                #expect(t.er[1] > 0 && t.etheta[2] > 0 && t.ephi[3] > 0)
            }
        }
    }

    @Test func fieldOfViewMapsEdgePixelsToTheExpectedAngles() {
        let observer = Observer(distance: 100, inclinationDegrees: 80, fieldOfViewDegrees: 30)
        let camera = Camera(kerr: Kerr(spin: 0), observer: observer, width: 1920, height: 1080)
        let half = 15.0 * Double.pi / 180
        // Right edge of the image: angle from the optical axis is half the horizontal field of view.
        let right = camera.localDirection(ndcX: 1, ndcY: 0)
        #expect(abs(atan2(right.y, right.x) - half) < 1e-12)
        let left = camera.localDirection(ndcX: -1, ndcY: 0)
        #expect(abs(atan2(left.y, left.x) + half) < 1e-12)
        // Top edge: tan(angle) = tan(fov/2) · height/width.
        let top = camera.localDirection(ndcX: 0, ndcY: 1)
        #expect(abs(atan2(top.z, top.x) - atan(tan(half) * 1080.0 / 1920.0)) < 1e-12)
        for d in [right, left, top, camera.localDirection(ndcX: 0.3, ndcY: -0.7)] {
            #expect(abs(d.x * d.x + d.y * d.y + d.z * d.z - 1) < 1e-14)
        }
        // Centre looks along the optical axis.
        let centre = camera.localDirection(ndcX: 0, ndcY: 0)
        #expect(centre == SIMD3<Double>(1, 0, 0))
    }

    @Test func centreRayOfNonSpinningBlackHoleIsPurelyRadial() throws {
        let camera = Camera(kerr: Kerr(spin: 0), observer: Observer(), width: 64, height: 36)
        let ray = camera.ray(ndcX: 0, ndcY: 0)
        #expect(abs(ray.constants.angularMomentum) < 1e-14)
        #expect(abs(ray.constants.carter) < 1e-14)
        #expect(ray.constants.energy == 1)
        #expect(ray.state.vu > 0)  // traced backward the ray goes inward: u increases
        #expect(abs(ray.state.vmu) < 1e-14)
    }

    @Test func orientationUpIsNorthAndRightIsIncreasingPhi() {
        let camera = Camera(kerr: Kerr(spin: 0), observer: Observer(), width: 64, height: 36)
        // The physical photon from the top of the image moves southward (θ increasing) toward the observer.
        #expect(camera.ray(ndcX: 0, ndcY: 0.5).state.vmu > 0)
        #expect(camera.ray(ndcX: 0, ndcY: -0.5).state.vmu < 0)
        // Image right is +φ̂, so the photon from the right moves toward −φ̂: L < 0.
        #expect(camera.ray(ndcX: 0.5, ndcY: 0).constants.angularMomentum < 0)
        #expect(camera.ray(ndcX: -0.5, ndcY: 0).constants.angularMomentum > 0)
    }

    @Test func everyPixelRaySatisfiesTheNullConditionToMachinePrecision() {
        // The state is built from the tetrad momentum, not from the potentials, so a tiny residual
        // verifies both the tetrad construction and the (E, L, Q) extraction.
        for a in Self.spins {
            for inclination in [0.01, 30.0, 80.0, 90.0, 120.0, 179.0] {
                let observer = Observer(distance: 50, inclinationDegrees: inclination, fieldOfViewDegrees: 40)
                let kerr = Kerr(spin: a)
                guard observer.distance > kerr.ergosphereRadius(mu: observer.mu) else { continue }
                let camera = Camera(kerr: kerr, observer: observer, width: 200, height: 100)
                for (x, y) in [(0.0, 0.0), (0.5, 0.5), (-0.9, 0.4), (0.99, -0.99), (0.0, 0.8), (-0.3, -0.2)] {
                    let ray = camera.ray(ndcX: x, ndcY: y)
                    let integrator = GeodesicIntegrator(kerr: kerr, constants: ray.constants, settings: .standard(skyRadius: 1000))
                    let residual = integrator.residual(of: ray.state)
                    #expect(residual < 1e-12, "a=\(a) i=\(inclination) pixel=(\(x),\(y)) residual=\(residual)")
                    #expect(ray.state.u == 1 / 50 && ray.state.vu.isFinite && ray.state.vmu.isFinite)
                    #expect(ray.constants.energy == 1)
                    #expect(ray.observerEnergy > 0)
                }
            }
        }
    }

    @Test func observerEnergyIsTheStaticRedshiftOfTheCentreRay() {
        // For a non-spinning hole the centre ray has E_raw = √(1 − 2/r) · ω, so the energy measured by the
        // static observer relative to E = 1 is 1/√(1 − 2/r).
        let observer = Observer(distance: 10)
        let camera = Camera(kerr: Kerr(spin: 0), observer: observer, width: 64, height: 36)
        let ray = camera.ray(ndcX: 0, ndcY: 0)
        #expect(approxEqual(ray.observerEnergy, 1 / (1 - 2.0 / 10).squareRoot(), relative: 1e-13))
    }

    @Test func pixelCoordinatesMapToNormalizedDeviceCoordinates() {
        let camera = Camera(kerr: Kerr(spin: 0), observer: Observer(), width: 200, height: 100)
        let a = camera.ray(pixelX: 100, pixelY: 50)  // exact centre
        let b = camera.ray(ndcX: 0, ndcY: 0)
        #expect(a.constants == b.constants && a.state == b.state)
        let c = camera.ray(pixelX: 0, pixelY: 0)  // top-left corner
        let d = camera.ray(ndcX: -1, ndcY: 1)
        #expect(c.constants == d.constants && c.state == d.state)
    }
}
