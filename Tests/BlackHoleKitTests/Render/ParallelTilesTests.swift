import Foundation
import Testing
@testable import BlackHoleKit

/// Determinism of the tiled parallel renderer (FR-009, SC-006).
@Suite struct ParallelTilesTests {
    /// A pure per-pixel function with some per-pixel work and jittered samples.
    private static func pixel(_ x: Int, _ y: Int, _ diagnostics: inout Diagnostics, seed: UInt64) -> SIMD3<Float> {
        var sum = SIMD3<Float>(repeating: 0)
        for s in 0..<4 {
            let j = SampleJitter.offset(seed: seed, pixelX: x, pixelY: y, sample: s)
            sum += SIMD3<Float>(Float(Double(x) + j.x), Float(Double(y) + j.y), Float(j.x * j.y))
        }
        diagnostics.record(x % 3 == 0 ? .captured : .sky(direction: SIMD3(0, 0, 1)), residual: 1e-9 * Double(x + y + 1))
        return sum / 4
    }

    private func render(threads: Int?, tile: Int = 8) -> ParallelTiles.Output<SIMD3<Float>> {
        ParallelTiles.render(width: 61, height: 37, tileSize: tile, maxConcurrency: threads, progress: nil) { x, y, d in
            Self.pixel(x, y, &d, seed: 42)
        }
    }

    @Test func buffersAreIdenticalAcrossThreadCounts() {
        let one = render(threads: 1)
        let two = render(threads: 2)
        let all = render(threads: nil)
        #expect(one.pixels == two.pixels)
        #expect(one.pixels == all.pixels)
        #expect(one.diagnostics == two.diagnostics)
        #expect(one.diagnostics == all.diagnostics)
    }

    @Test func repeatedRunsAreIdentical() {
        #expect(render(threads: nil).pixels == render(threads: nil).pixels)
    }

    @Test func tileSizeDoesNotChangeTheImage() {
        #expect(render(threads: nil, tile: 8).pixels == render(threads: nil, tile: 16).pixels)
        #expect(render(threads: nil, tile: 8).pixels == render(threads: nil, tile: 5).pixels)
    }

    @Test func coversEveryPixelExactlyOnceInRowMajorOrder() {
        let out = ParallelTiles.render(width: 13, height: 7, tileSize: 4, maxConcurrency: nil, progress: nil) { x, y, d in
            d.record(.captured, residual: 0)
            return SIMD3<Float>(Float(x), Float(y), 0)
        }
        #expect(out.pixels.count == 13 * 7)
        #expect(out.diagnostics.raysTotal == 13 * 7)
        for y in 0..<7 { for x in 0..<13 { #expect(out.pixels[y * 13 + x] == SIMD3<Float>(Float(x), Float(y), 0)) } }
    }

    @Test func progressReachesOne() {
        final class Last: @unchecked Sendable {
            let lock = NSLock(); var value = 0.0
            func set(_ v: Double) { lock.lock(); value = max(value, v); lock.unlock() }
        }
        let last = Last()
        _ = ParallelTiles.render(width: 40, height: 40, tileSize: 8, maxConcurrency: nil, progress: { last.set($0) }) { _, _, _ in SIMD3<Float>.zero }
        #expect(last.value == 1.0)
    }

    @Test func jitterIsDeterministicInRangeAndVaries() {
        let a = SampleJitter.offset(seed: 7, pixelX: 3, pixelY: 5, sample: 2)
        let b = SampleJitter.offset(seed: 7, pixelX: 3, pixelY: 5, sample: 2)
        #expect(a == b)
        #expect(a != SampleJitter.offset(seed: 8, pixelX: 3, pixelY: 5, sample: 2))
        #expect(a != SampleJitter.offset(seed: 7, pixelX: 4, pixelY: 5, sample: 2))
        #expect(a != SampleJitter.offset(seed: 7, pixelX: 3, pixelY: 5, sample: 3))
        var sums = SIMD2<Double>(0, 0)
        let n = 20000
        for i in 0..<n {
            let j = SampleJitter.offset(seed: 1, pixelX: i, pixelY: i / 7, sample: i % 4)
            #expect(j.x >= 0 && j.x < 1 && j.y >= 0 && j.y < 1)
            sums += j
        }
        #expect(abs(sums.x / Double(n) - 0.5) < 0.01 && abs(sums.y / Double(n) - 0.5) < 0.01)
    }
}

@Suite struct DiagnosticsTests {
    @Test func countsAndPercentile() {
        var d = Diagnostics()
        for i in 0..<1000 { d.record(i < 100 ? .captured : .sky(direction: SIMD3(1, 0, 0)), residual: 1e-9) }
        d.record(.unresolved(.stepBudget), residual: 0.5)
        #expect(d.raysTotal == 1001 && d.captured == 100 && d.sky == 900 && d.unresolved == 1)
        #expect(d.raysOverTolerance == 1)
        #expect(d.maxResidual == 0.5)
        #expect(d.p999Residual < 1e-3)  // the single bad ray is 0.1% of rays: just outside the 99.9th percentile
        #expect(abs(d.badRayFraction - 2.0 / 1001) < 1e-12)
    }

    @Test func mergeIsOrderIndependent() {
        var a = Diagnostics(), b = Diagnostics()
        a.record(.captured, residual: 1e-8)
        b.record(.sky(direction: SIMD3(0, 1, 0)), residual: 2e-7)
        var ab = a; ab.merge(b)
        var ba = b; ba.merge(a)
        #expect(ab == ba)
        #expect(ab.raysTotal == 2 && ab.maxResidual == 2e-7)
    }
}
