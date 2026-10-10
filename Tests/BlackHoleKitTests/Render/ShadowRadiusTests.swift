import Foundation
import Testing
@testable import BlackHoleKit

/// SC-001: the non-spinning shadow has angular radius arcsin(3√3·√(1 − 2/r)/r) for a static observer at r.
@Suite struct ShadowRadiusTests {
    static func expectedAngularRadius(distance r: Double) -> Double {
        asin(3 * 3.0.squareRoot() * (1 - 2 / r).squareRoot() / r)
    }

    static func config(size: Int = 400, fov: Double = 12) -> RenderConfig {
        var c = RenderConfig()
        c.blackHole.spin = 0
        c.observer.inclinationDegrees = 90
        c.observer.fieldOfViewDegrees = fov
        c.width = size
        c.height = size
        c.samplesPerPixel = 1
        c.sky = SkyConfig(kind: .grid, seed: 1, starCount: 0)
        return c
    }

    @Test func shadowRadiusMatchesTheCriticalImpactParameter() throws {
        let config = Self.config()
        let renderer = try Renderer(config: config)
        let image = renderer.render()
        let outline = ShadowOutline(image: image, fieldOfViewDegrees: config.observer.fieldOfViewDegrees)
        let expected = Self.expectedAngularRadius(distance: config.observer.distance)
        #expect(outline.area > 0)
        #expect(approxEqual(outline.angularRadius, expected, relative: 0.01),
                "measured \(outline.angularRadius) rad vs expected \(expected) rad")
        // The shadow is centred on the optical axis for a non-spinning hole.
        let c = outline.centroid
        #expect(abs(c.x - Double(config.width) / 2) < 1 && abs(c.y - Double(config.height) / 2) < 1)
        #expect(image.diagnostics.unresolved == 0)
    }

    @Test func raysJustInsideAndOutsideTheEdgeChangeOutcome() throws {
        let config = Self.config()
        let renderer = try Renderer(config: config)
        let center = SIMD2(Double(config.width) / 2, Double(config.height) / 2)
        // Image-plane radius of the expected edge, in pixels.
        let alpha = Self.expectedAngularRadius(distance: config.observer.distance)
        let edgePixels = tan(alpha) / (2 * tan(config.observer.fieldOfViewDegrees * Double.pi / 360) / Double(config.width))
        for angle in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 6) {
            for (scale, shouldBeCaptured) in [(0.99, true), (1.01, false)] {
                let p = center + SIMD2(cos(angle), sin(angle)) * edgePixels * scale
                let result = renderer.trace(pixelX: p.x, pixelY: p.y)
                let captured = result.outcome == .captured
                #expect(captured == shouldBeCaptured, "angle \(angle) scale \(scale): \(result.outcome)")
            }
        }
    }

    @Test func nearerObserversSeeLargerShadows() throws {
        var radii: [Double] = []
        for distance in [30.0, 60.0, 120.0] {
            var config = Self.config()
            config.observer.distance = distance
            config.observer.fieldOfViewDegrees = 2 * Self.expectedAngularRadius(distance: distance) * 180 / Double.pi * 2.5
            config.width = 200
            config.height = 200
            let image = try Renderer(config: config).render()
            let outline = ShadowOutline(image: image, fieldOfViewDegrees: config.observer.fieldOfViewDegrees)
            #expect(approxEqual(outline.angularRadius, Self.expectedAngularRadius(distance: distance), relative: 0.02), "r=\(distance)")
            radii.append(outline.angularRadius)
        }
        #expect(radii[0] > radii[1] && radii[1] > radii[2])
    }
}
