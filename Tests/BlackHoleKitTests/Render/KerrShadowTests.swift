import CryptoKit
import Foundation
import Testing
@testable import BlackHoleKit

struct KerrShadowFixture: Decodable {
    struct Case: Decodable {
        let a: Double
        let inclination_deg: Double
        let distance: Double
        let angles: [Double]
        let rho: [Double]
        let rho_left: Double
        let rho_right: Double
    }
    let distance: Double
    let cases: [Case]
}

/// Spinning black hole: shadow outline vs. the analytic Kerr curve (SC-002) and regression of the
/// non-spinning render.
@Suite struct KerrShadowTests {
    let fixture: KerrShadowFixture

    init() throws { fixture = try Fixture.load("kerr_shadow") }

    private func config(spin: Double, inclination: Double, size: Int = 400, fov: Double = 30) -> RenderConfig {
        var c = RenderConfig()
        c.blackHole.spin = spin
        c.observer.distance = fixture.distance
        c.observer.inclinationDegrees = inclination
        c.observer.fieldOfViewDegrees = fov
        c.diskEnabled = false
        c.width = size
        c.height = size
        c.samplesPerPixel = 1
        c.sky = SkyConfig(kind: .grid, seed: 1, starCount: 0)
        return c
    }

    /// Tangent-plane distance to the shadow edge along image direction φ, found by bisection on the ray outcome.
    private func tracedEdge(_ renderer: Renderer, config: RenderConfig, angle phi: Double) -> Double {
        let w = Double(config.width)
        let scale = w / (2 * tan(config.observer.fieldOfViewDegrees * Double.pi / 360))  // pixels per unit tangent
        let center = SIMD2(w / 2, Double(config.height) / 2)
        let direction = SIMD2(cos(phi), -sin(phi))  // image y points down
        var lo = 0.0, hi = 0.2
        func captured(_ rho: Double) -> Bool {
            let p = center + direction * rho * scale
            return renderer.trace(pixelX: p.x, pixelY: p.y).outcome == .captured
        }
        precondition(captured(lo) && !captured(hi), "bracket failed at angle \(phi)")
        for _ in 0..<40 {
            let mid = 0.5 * (lo + hi)
            if captured(mid) { lo = mid } else { hi = mid }
        }
        return 0.5 * (lo + hi)
    }

    @Test func rayLevelOutlineMatchesTheAnalyticKerrCurve() throws {
        var worst = 0.0
        for c in fixture.cases {
            let cfg = config(spin: c.a, inclination: c.inclination_deg)
            let renderer = try Renderer(config: cfg)
            for (angle, expected) in zip(c.angles, c.rho) {
                let measured = tracedEdge(renderer, config: cfg, angle: angle)
                let error = abs(measured - expected) / expected
                worst = max(worst, error)
                #expect(error < 5e-4, "a=\(c.a) i=\(c.inclination_deg) φ=\(angle): ρ=\(measured) vs analytic \(expected)")
            }
        }
        print("KERRSHADOW worst ray-level outline error: \(worst)")
    }

    @Test func renderedOutlineMatchesTheAnalyticCurveWithinTwoPercent() throws {
        // SC-002: spin 0.9 viewed at 85°.
        let c = try #require(fixture.cases.first { $0.a == 0.9 && $0.inclination_deg == 85 })
        var cfg = config(spin: 0.9, inclination: 85, fov: 12)
        cfg.samplesPerPixel = 4  // partial pixel coverage gives the edge sub-pixel resolution
        let image = try Renderer(config: cfg).render()
        let outline = ShadowOutline(image: image, fieldOfViewDegrees: cfg.observer.fieldOfViewDegrees)
        let measured = outline.outlineSamples(angles: c.angles)
        var worst = 0.0
        for (i, (m, expected)) in zip(measured, c.rho).enumerated() {
            let error = abs(m - expected) / expected
            worst = max(worst, error)
            #expect(error < 0.02, "direction \(i) (φ=\(c.angles[i])): ρ=\(m) vs analytic \(expected)")
        }
        print("KERRSHADOW worst image-level outline error (a=0.9, 85°): \(worst)")
    }

    @Test func shadowIsFlattenedOnTheProgradeSideAndOffsetTheOtherWay() throws {
        let c = try #require(fixture.cases.first { $0.a == 0.9 && $0.inclination_deg == 90 })
        // Analytic: the left (approaching, prograde) edge is much closer to the axis than the right edge.
        #expect(c.rho_left < 0.5 * c.rho_right)
        var cfg = config(spin: 0.9, inclination: 90, fov: 12)
        cfg.samplesPerPixel = 4
        let image = try Renderer(config: cfg).render()
        let outline = ShadowOutline(image: image, fieldOfViewDegrees: 12)
        let centroid = outline.centroid
        let tangentPerPixel = 2 * tan(6.0 * Double.pi / 180) / Double(cfg.width)
        // Expected centroid offset toward the right: roughly (ρ_right − ρ_left)/2 in the tangent plane.
        #expect((centroid.x - Double(cfg.width) / 2) * tangentPerPixel > 0.5 * (c.rho_right - c.rho_left) / 2)
        #expect(abs(centroid.y - Double(cfg.height) / 2) < 1.5, "an equatorial observer sees a top-bottom symmetric shadow")
        // The measured left/right extents agree with the analytic values.
        let extents = outline.outlineSamples(angles: [0, Double.pi])
        #expect(approxEqual(extents[0], c.rho_right, relative: 0.01) && approxEqual(extents[1], c.rho_left, relative: 0.01))
    }

    @Test func shadowGrowsAndFlattensWithSpin() throws {
        func extents(_ spin: Double) -> (left: Double, right: Double) {
            let c = fixture.cases.first { $0.a == spin && $0.inclination_deg == 90 }!
            return (c.rho_left, c.rho_right)
        }
        let low = extents(0.5), mid = extents(0.9), high = extents(0.998)
        #expect(low.left > mid.left && mid.left > high.left)
        #expect(low.right < mid.right && mid.right < high.right)
    }

    // MARK: Regression: a = 0 is exactly the User Story 1 image

    private func geometryFingerprint(spin: Double) throws -> (digest: String, image: RenderedImage) {
        var c = RenderConfig()
        c.blackHole.spin = spin
        c.width = 64
        c.height = 36
        c.samplesPerPixel = 4
        c.sky = SkyConfig(kind: .grid, seed: 1, starCount: 0)
        let image = try Renderer(config: c).render()
        var data = Data()
        for map in [image.diskFraction, image.capturedFraction, image.higherOrderFraction, image.unresolvedFraction] {
            map.withUnsafeBytes { data.append(contentsOf: $0) }
        }
        return (SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), image)
    }

    @Test func nonSpinningRenderReproducesTheUserStoryOneGeometryBitForBit() throws {
        // Fingerprint of the disk/captured/higher-order/unresolved maps recorded when User Story 1 was
        // completed. Shading-independent, so it must survive User Story 3. If a deliberate change to the
        // geometry alters it, regenerate and say so in the commit.
        let recorded = "55c72cbb467768e38b5113e798680087c5fd86e113c201791503aca26d39dba5"
        #expect(try geometryFingerprint(spin: 0).digest == recorded)
    }

    @Test func spinZeroIsTheLimitOfSmallSpin() throws {
        let zero = try geometryFingerprint(spin: 0).image
        let tiny = try geometryFingerprint(spin: 1e-9).image
        var different = 0
        for i in 0..<zero.capturedFraction.count where zero.capturedFraction[i] != tiny.capturedFraction[i] || zero.diskFraction[i] != tiny.diskFraction[i] {
            different += 1
        }
        #expect(different <= 2, "\(different) of \(zero.capturedFraction.count) pixels differ between a = 0 and a = 1e-9")
    }

    @Test func observersInsideTheErgosphereAreRejectedWithTheStaticObserverMessage() {
        var c = RenderConfig()
        c.blackHole.spin = 0.9
        c.observer.inclinationDegrees = 85
        c.observer.distance = 1.9  // ergosphere radius at 85° is 1 + √(1 − 0.81 cos²85°) ≈ 1.997
        c.disk.outerRadius = 1.8
        do {
            _ = try Renderer(config: c)
            Issue.record("expected the observer to be rejected")
        } catch let error as ConfigError {
            #expect(error.option == "--distance")
            #expect(error.reason.contains("static observer"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
