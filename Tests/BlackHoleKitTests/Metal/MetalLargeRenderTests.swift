import Foundation
import Testing
@testable import BlackHoleKit

/// Bounded duration and memory of the GPU backend (FR-009, SC-006).
@Suite struct MetalLargeRenderTests {
    static let context = try? MetalContext.make()
    static var hasGPU: Bool { context != nil }

    @Test(.enabled(if: MetalLargeRenderTests.hasGPU)) func aMillionNearCriticalRaysKeepEveryPassShort() throws {
        var config = RenderConfig()
        config.blackHole.spin = 0.998; config.observer.inclinationDegrees = 60
        let camera = Camera(kerr: config.kerr, observer: config.observer, width: 1000, height: 1000)
        // Rays on 1000 rings sweeping the whole image radius finely, so that many fall within 10^-3 of the shadow edge
        // (the critical curve) where the rays wind several times: the slowest rays.
        var inputs: [GPURayInput] = []
        inputs.reserveCapacity(1_000_000)
        let centre = SIMD2(500.0, 500.0)
        for i in 0..<1_000_000 {
            let angle = 2 * Double.pi * Double(i % 1000) / 1000
            let radius = 500.0 * (Double(i / 1000) + 0.5) / 1000
            let ray = camera.ray(pixelX: centre.x + radius * cos(angle), pixelY: centre.y + radius * sin(angle))
            inputs.append(GPURayInput(ray))
        }
        let tracer = MetalRayTracer(context: try #require(Self.context))
        let buffers = try tracer.makeBuffers(capacity: inputs.count)
        inputs.withUnsafeBufferPointer { buffers.inputPointer.update(from: $0.baseAddress!, count: inputs.count) }
        let parameters = GPUKernelParameters(config: config, relativeTolerance: Float(NumericalDefaults.gpuRelativeTolerance),
                                             absoluteTolerance: Float(NumericalDefaults.gpuAbsoluteTolerance),
                                             stepsPerPass: UInt32(NumericalDefaults.gpuStepsPerPass), stepBudget: UInt32(config.maxStepsPerRay))
        let stats = try tracer.run(buffers: buffers, rayCount: inputs.count, parameters: parameters)
        print("stress: \(stats.passes) passes, longest \(stats.maxPassSeconds * 1000) ms, total GPU \(stats.gpuSeconds) s")
        #expect(stats.maxPassSeconds < NumericalDefaults.gpuMaxPassSeconds, "longest pass \(stats.maxPassSeconds) s")
    }

    @Test(.enabled(if: MetalLargeRenderTests.hasGPU)) func bandBuffersAreBoundedWhateverTheImageSize() throws {
        var config = RenderConfig()
        config.width = 3840; config.height = 2160; config.samplesPerPixel = 16
        // A requested band far beyond the memory bound is clamped.
        let renderer = try Renderer(config: config.with(backend: .metal), gpuBandSamples: 1_000_000_000)
        #expect(renderer.gpuBandSamples * NumericalDefaults.gpuBytesPerSample <= NumericalDefaults.gpuMaxBufferBytes)
        let bytes = try MetalRayTracer(context: try #require(Self.context)).makeBuffers(capacity: renderer.gpuBandSamples).byteCount
        #expect(bytes <= 320_000_000, "bytes held by a band: \(bytes)")
        // The default band (about 10^6 samples) is also within bounds, and does not grow with the image.
        let normal = try Renderer(config: config.with(backend: .metal))
        #expect(normal.gpuBandSamples == NumericalDefaults.gpuBandSamples)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["BHSIM_BENCH"] == "1" && MetalLargeRenderTests.hasGPU))
    func fourKAtSixteenSamplesIsThreeTimesFasterThanTheBaseline() throws {
        var config = RenderConfig()
        config.width = 3840; config.height = 2160; config.samplesPerPixel = 16; config.backend = .metal
        let fractions = LockedBox<[Double]>([])
        let image = try Renderer(config: config).renderOnBackend(progress: { f in fractions.mutate { $0.append(f) } })
        let seconds = image.diagnostics.wallTimeSeconds
        let baseline = 331.9  // CPU, same render, research.md §Baseline
        print("4K x 16 spp: \(seconds) s, speed-up over baseline \(baseline / seconds), longest pass \(image.gpuStatistics?.maxPassSeconds ?? 0) s, bands \(image.gpuStatistics?.bands ?? 0)")
        #expect(seconds <= baseline / 3)
        #expect(fractions.value.count > 1 && fractions.value.last == 1)
        #expect(image.diagnostics.badRayFraction < 1e-3)
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ body: (inout T) -> Void) { lock.lock(); body(&stored); lock.unlock() }
}

extension RenderConfig {
    func with(backend: Backend) -> RenderConfig { var c = self; c.backend = backend; return c }
}
