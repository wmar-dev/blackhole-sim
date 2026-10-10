import Foundation
import Testing
@testable import BlackHoleKit

/// FR-009 / SC-006: identical inputs give identical images, for any thread count.
@Suite struct DeterminismTests {
    static func config(seed: UInt64 = 5) -> RenderConfig {
        var c = RenderConfig()
        c.blackHole.spin = 0.7
        c.width = 48
        c.height = 27
        c.samplesPerPixel = 4
        c.sky = SkyConfig(kind: .starfield, seed: seed, starCount: 20_000)
        return c
    }

    @Test func repeatedRendersAreIdentical() throws {
        let renderer = try Renderer(config: Self.config())
        let a = renderer.render()
        let b = renderer.render()
        #expect(a.hdr == b.hdr)
        #expect(a.diskFraction == b.diskFraction)
        var da = a.diagnostics, db = b.diagnostics
        da.wallTimeSeconds = 0
        db.wallTimeSeconds = 0
        #expect(da == db)
    }

    @Test func threadCountDoesNotChangeTheImage() throws {
        let renderer = try Renderer(config: Self.config())
        let one = renderer.render(maxConcurrency: 1)
        let two = renderer.render(maxConcurrency: 2)
        let all = renderer.render(maxConcurrency: nil)
        #expect(one.hdr == two.hdr)
        #expect(one.hdr == all.hdr)
        #expect(one.capturedFraction == all.capturedFraction)
    }

    @Test func separateRendererInstancesWithTheSameSeedAgree() throws {
        let a = try Renderer(config: Self.config(seed: 9)).render()
        let b = try Renderer(config: Self.config(seed: 9)).render()
        #expect(a.hdr == b.hdr)
    }

    @Test func aDifferentSeedChangesTheSkyAndTheSampling() throws {
        let a = try Renderer(config: Self.config(seed: 1)).render()
        let b = try Renderer(config: Self.config(seed: 2)).render()
        #expect(a.hdr != b.hdr)
    }

    @Test func metadataIsIdenticalExceptForWallTime() throws {
        let config = Self.config()
        let renderer = try Renderer(config: config)
        func metadata() throws -> Data {
            var image = renderer.render()
            image.diagnostics.wallTimeSeconds = 0
            return try RenderMetadata(config: config, shading: image.shading, referenceRadiance: image.referenceRadiance,
                                      diagnostics: image.diagnostics).jsonData()
        }
        #expect(try metadata() == metadata())
    }
}
