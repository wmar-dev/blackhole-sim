import Dispatch
import Foundation

/// Deterministic per-sample jitter: a pure function of (seed, pixel, sample), so images do not depend on
/// thread count or scheduling (FR-009, SC-006).
public enum SampleJitter {
    @inline(__always)
    static func mix(_ x: UInt64) -> UInt64 {  // SplitMix64 finalizer
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform offsets in [0, 1)².
    public static func offset(seed: UInt64, pixelX: Int, pixelY: Int, sample: Int) -> SIMD2<Double> {
        let pixelKey = mix(UInt64(truncatingIfNeeded: pixelX) << 32 | UInt64(truncatingIfNeeded: pixelY) & 0xFFFF_FFFF)
        let key = mix(seed ^ pixelKey ^ mix(UInt64(truncatingIfNeeded: sample) &+ 0xA5A5_1234))
        let scale = 1.0 / Double(1 << 53)
        return SIMD2(Double(mix(key) >> 11) * scale, Double(mix(key &+ 1) >> 11) * scale)
    }
}

/// Tiled parallel rendering. Each pixel is computed independently by a pure function, so the result is
/// identical for any thread count, tile size or schedule; diagnostics are merged in fixed tile order.
public enum ParallelTiles {
    public struct Output<Pixel: Sendable>: Sendable {
        /// Row-major, `width × height`, top row first.
        public var pixels: [Pixel]
        public var diagnostics: Diagnostics
    }

    private struct TileResult<Pixel: Sendable> {
        var pixels: [Pixel] = []
        var diagnostics = Diagnostics()
    }

    private final class ResultStore<Pixel: Sendable>: @unchecked Sendable {
        let results: UnsafeMutablePointer<TileResult<Pixel>>
        let count: Int
        init(count: Int) {
            self.count = count
            results = .allocate(capacity: count)
            results.initialize(repeating: TileResult<Pixel>(), count: count)
        }
        deinit {
            results.deinitialize(count: count)
            results.deallocate()
        }
    }

    private final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var done = 0
        let total: Int
        let callback: (@Sendable (Double) -> Void)?
        init(total: Int, callback: (@Sendable (Double) -> Void)?) {
            self.total = total
            self.callback = callback
        }
        func tileFinished() {
            guard let callback else { return }
            lock.lock()
            done += 1
            callback(Double(done) / Double(total))
            lock.unlock()
        }
    }

    /// - Parameters:
    ///   - maxConcurrency: limit on simultaneously running tiles; `nil` uses every core.
    ///   - progress: called with the completed fraction after each tile (calls are serialized, increasing).
    ///   - pixel: computes one pixel and records its rays into the tile-local `Diagnostics`.
    public static func render<Pixel: Sendable>(
        width: Int, height: Int, tileSize: Int = 16, maxConcurrency: Int? = nil,
        progress: (@Sendable (Double) -> Void)?,
        pixel: @escaping @Sendable (_ x: Int, _ y: Int, _ diagnostics: inout Diagnostics) -> Pixel
    ) -> Output<Pixel> {
        precondition(width > 0 && height > 0 && tileSize > 0)
        let columns = (width + tileSize - 1) / tileSize
        let rows = (height + tileSize - 1) / tileSize
        let tileCount = columns * rows
        let store = ResultStore<Pixel>(count: tileCount)
        let tracker = Progress(total: tileCount, callback: progress)

        let renderTile: @Sendable (Int) -> Void = { index in
            let x0 = (index % columns) * tileSize
            let y0 = (index / columns) * tileSize
            let x1 = min(x0 + tileSize, width)
            let y1 = min(y0 + tileSize, height)
            var result = TileResult<Pixel>()
            result.pixels.reserveCapacity((x1 - x0) * (y1 - y0))
            for y in y0..<y1 {
                for x in x0..<x1 {
                    result.pixels.append(pixel(x, y, &result.diagnostics))
                }
            }
            store.results[index] = result
            tracker.tileFinished()
        }

        if maxConcurrency == 1 {
            for index in 0..<tileCount { renderTile(index) }
        } else if let limit = maxConcurrency {
            let gate = DispatchSemaphore(value: limit)
            DispatchQueue.concurrentPerform(iterations: tileCount) { index in
                gate.wait()
                renderTile(index)
                gate.signal()
            }
        } else {
            DispatchQueue.concurrentPerform(iterations: tileCount, execute: renderTile)
        }

        // Assemble row-major, merging diagnostics in fixed tile order.
        var pixels: [Pixel] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            let tileRow = y / tileSize
            let y0 = tileRow * tileSize
            for tileColumn in 0..<columns {
                let x0 = tileColumn * tileSize
                let x1 = min(x0 + tileSize, width)
                let tile = store.results[tileRow * columns + tileColumn]
                let start = (y - y0) * (x1 - x0)
                pixels.append(contentsOf: tile.pixels[start..<(start + (x1 - x0))])
            }
        }
        var diagnostics = Diagnostics()
        for index in 0..<tileCount { diagnostics.merge(store.results[index].diagnostics) }
        return Output(pixels: pixels, diagnostics: diagnostics)
    }
}
