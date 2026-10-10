import Foundation
import Testing
@testable import BlackHoleKit

/// GPU renders are reproducible (SC-005, FR-010), and do not depend on the band size.
@Suite struct MetalDeterminismTests {
    static let hasGPU = (try? MetalContext.make()) != nil

    private func config() -> RenderConfig {
        var c = RenderConfig()
        c.width = 120; c.height = 68; c.samplesPerPixel = 4; c.backend = .metal
        c.blackHole.spin = 0.9; c.observer.inclinationDegrees = 80
        return c
    }

    @Test(.enabled(if: MetalDeterminismTests.hasGPU)) func repeatedRendersAreIdentical() throws {
        let a = try Renderer(config: config()).renderOnBackend()
        let b = try Renderer(config: config()).renderOnBackend()
        #expect(a.hdr == b.hdr)
        #expect(a.diskFraction == b.diskFraction && a.capturedFraction == b.capturedFraction)
        var da = a.diagnostics, db = b.diagnostics
        da.wallTimeSeconds = 0; db.wallTimeSeconds = 0
        #expect(da == db)
    }

    @Test(.enabled(if: MetalDeterminismTests.hasGPU)) func theBandSizeDoesNotChangeTheImage() throws {
        let whole = try Renderer(config: config()).renderOnBackend()
        let small = try Renderer(config: config(), gpuBandSamples: 1000).renderOnBackend()
        let one = try Renderer(config: config(), gpuBandSamples: 1).renderOnBackend()
        #expect(whole.hdr == small.hdr && whole.hdr == one.hdr)
        #expect((small.gpuStatistics?.bands ?? 0) > (whole.gpuStatistics?.bands ?? 0))
    }

    @Test(.enabled(if: MetalDeterminismTests.hasGPU)) func outputFilesAreByteIdentical() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bhsim-det-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["g1", "g2"] {
            let run = try CLIRunner.run(["render", "--backend", "metal", "--width", "160", "--height", "90", "--out", dir.appendingPathComponent(name).path])
            #expect(run.status == 0, "\(run.stderr)")
        }
        for ext in ["png", "exr"] {
            let a = try Data(contentsOf: dir.appendingPathComponent("g1.\(ext)")), b = try Data(contentsOf: dir.appendingPathComponent("g2.\(ext)"))
            #expect(a == b, ".\(ext) differs between runs")
        }
    }
}
