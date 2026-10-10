import Foundation
import Testing
@testable import BlackHoleKit

/// End-to-end GPU renders: outputs, metadata, diagnostics, shadow accuracy (US1 scenarios 1 and 3, FR-004/005/006).
@Suite struct MetalRenderTests {
    static let hasGPU = (try? MetalContext.make()) != nil

    @Test(.enabled(if: MetalRenderTests.hasGPU)) func rendersAndRecordsTheBackend() throws {
        var config = RenderConfig()
        config.width = 96; config.height = 54; config.samplesPerPixel = 4; config.backend = .metal
        let image = try Renderer(config: config).renderOnBackend()
        #expect(image.backend == .metal)
        #expect(image.hdr.count == 96 * 54)
        #expect(image.diagnostics.raysTotal == 96 * 54 * 4)
        #expect(image.diagnostics.unresolved == 0)
        #expect(image.diagnostics.badRayFraction < 1e-3)
        #expect(image.gpuStatistics != nil)
        #expect(image.hdr.contains { $0.x > 0.1 })
    }

    @Test(.enabled(if: MetalRenderTests.hasGPU)) func shadowRadiusOfASchwarzschildHoleIsWithinOnePercent() throws {
        var config = RenderConfig()
        config.width = 200; config.height = 200; config.samplesPerPixel = 1
        config.blackHole.spin = 0; config.observer.inclinationDegrees = 90; config.observer.fieldOfViewDegrees = 12
        config.diskEnabled = false; config.sky.kind = .grid; config.backend = .metal
        let image = try Renderer(config: config).renderOnBackend()
        let captured = image.capturedFraction.reduce(0, +)
        let radiusPixels = (Double(captured) / Double.pi).squareRoot()
        let pixelAngle = 2 * tan(6 * Double.pi / 180) / 200
        let angular = radiusPixels * pixelAngle
        let d = config.observer.distance
        let analytic = asin(27.0.squareRoot() / d * (1 - 2 / d).squareRoot())
        #expect(abs(angular - analytic) / analytic < 0.01, "shadow \(angular) vs \(analytic)")
    }

    @Test(.enabled(if: MetalRenderTests.hasGPU)) func tinyStepBudgetGivesUnresolvedRaysLikeTheCPU() throws {
        var config = RenderConfig()
        config.width = 24; config.height = 14; config.samplesPerPixel = 1; config.maxStepsPerRay = 5; config.backend = .metal
        let image = try Renderer(config: config).renderOnBackend()
        #expect(image.diagnostics.unresolved > 0)
    }
}
