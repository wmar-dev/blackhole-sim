import Foundation
import Testing
@testable import BlackHoleKit

/// Spike S1 (research.md D12): a bare black hole traced on the GPU against the CPU reference.
/// The always-run test is the go/no-go agreement check; the benchmark (BHSIM_BENCH=1) measures speed and sweeps the tolerance.
@Suite struct MetalSpikeTests {
    static let context = try? MetalContext.make()
    static var hasGPU: Bool { context != nil }

    struct Scene {
        let spin: Double
        let inclination: Double
    }
    static let scenes = [Scene(spin: 0, inclination: 45), Scene(spin: 0, inclination: 85), Scene(spin: 0.9, inclination: 45), Scene(spin: 0.9, inclination: 85)]

    /// Camera rays (float64) for a size × size grid of pixel centres.
    static func rays(_ scene: Scene, size: Int) -> (config: RenderConfig, rays: [CameraRay]) {
        var config = RenderConfig()
        config.blackHole.spin = scene.spin
        config.observer.inclinationDegrees = scene.inclination
        config.observer.fieldOfViewDegrees = 30
        config.diskEnabled = false
        config.width = size
        config.height = size
        let camera = Camera(kerr: config.kerr, observer: config.observer, width: size, height: size)
        var rays: [CameraRay] = []
        for y in 0..<size { for x in 0..<size { rays.append(camera.ray(pixelX: Double(x) + 0.5, pixelY: Double(y) + 0.5)) } }
        return (config, rays)
    }

    static func parameters(_ config: RenderConfig, relativeTolerance: Float = Float(NumericalDefaults.gpuRelativeTolerance)) -> GPUKernelParameters {
        GPUKernelParameters(config: config, relativeTolerance: relativeTolerance, absoluteTolerance: Float(NumericalDefaults.gpuAbsoluteTolerance),
                            stepsPerPass: UInt32(NumericalDefaults.gpuStepsPerPass), stepBudget: UInt32(config.maxStepsPerRay))
    }

    struct Agreement {
        var rays = 0
        var delicate = 0
        var matching = 0
        var skyRays = 0
        var skyWithin = 0
        var maxSkyAngle = 0.0
        /// The same statistics over the rays the GPU handled on its own (not flagged delicate).
        var gpuOnlySkyRays = 0
        var gpuOnlySkyWithin = 0
        var gpuOnlyMaxSkyAngle = 0.0
    }

    /// Compares the *hybrid* outcome (GPU for ordinary rays, the CPU's float64 result for rays flagged as passing close
    /// to a pole) with the CPU reference ray by ray, and reports the GPU-only statistics for the unflagged rays.
    static func compare(_ scene: Scene, size: Int, relativeTolerance: Float = Float(NumericalDefaults.gpuRelativeTolerance),
                        angleTolerance: Float = Float(NumericalDefaults.gpuAngleTolerance)) throws -> Agreement {
        let (config, rays) = Self.rays(scene, size: size)
        let tracer = MetalRayTracer(context: try #require(Self.context))
        var p = parameters(config, relativeTolerance: relativeTolerance)
        p.angleTolerance = angleTolerance
        let results = try tracer.trace(inputs: rays.map(GPURayInput.init), parameters: p)
        let cpu = RayTracer(config: config)
        var a = Agreement()
        for (ray, gpuResult) in zip(rays, results) {
            let reference = cpu.trace(ray).outcome
            a.rays += 1
            let gpuOutcome = gpuResult.outcome(constants: ray.constants, kerr: config.kerr)
            let delicate = gpuResult.isDelicate
            if delicate { a.delicate += 1 }
            let outcome = delicate ? reference : gpuOutcome  // the hybrid result
            switch (reference, outcome) {
            case (.captured, .captured): a.matching += 1
            case (.sky(let d1), .sky(let d2)):
                a.matching += 1
                a.skyRays += 1
                let angle = acos(min(max((d1 * d2).sum(), -1), 1))
                a.maxSkyAngle = max(a.maxSkyAngle, angle)
                if angle <= 1e-4 { a.skyWithin += 1 }
            default: break
            }
            if !delicate, case .sky(let d1) = reference, case .sky(let d2) = gpuOutcome {
                a.gpuOnlySkyRays += 1
                let angle = acos(min(max((d1 * d2).sum(), -1), 1))
                a.gpuOnlyMaxSkyAngle = max(a.gpuOnlyMaxSkyAngle, angle)
                if angle <= 1e-4 { a.gpuOnlySkyWithin += 1 }
            }
        }
        return a
    }

    @Test(.enabled(if: MetalSpikeTests.hasGPU), arguments: scenes)
    func bareBlackHoleOutcomesAgreeWithTheCPU(_ scene: Scene) throws {
        let a = try Self.compare(scene, size: 64)
        let match = Double(a.matching) / Double(a.rays)
        let hybridWithin = Double(a.skyWithin) / Double(max(a.skyRays, 1))
        let gpuWithin = Double(a.gpuOnlySkyWithin) / Double(max(a.gpuOnlySkyRays, 1))
        print("SPIKE a=\(scene.spin) i=\(scene.inclination): outcome match \(match); flagged delicate \(Double(a.delicate) / Double(a.rays)); hybrid sky within 1e-4 rad \(hybridWithin) (max \(a.maxSkyAngle)); GPU-only on unflagged rays \(gpuWithin) (max \(a.gpuOnlyMaxSkyAngle))")
        #expect(match >= 0.999, "a=\(scene.spin) i=\(scene.inclination): only \(match) of rays agree")
        #expect(hybridWithin >= 0.999, "hybrid sky directions disagree: max \(a.maxSkyAngle) rad")
        #expect(gpuWithin >= 0.999, "GPU-only sky directions of unflagged rays disagree: \(gpuWithin), max \(a.gpuOnlyMaxSkyAngle) rad")
        #expect(Double(a.delicate) / Double(a.rays) < 0.25, "too many rays flagged delicate for the hybrid to pay off")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["BHSIM_BENCH"] == "1" && MetalSpikeTests.hasGPU))
    func measureThroughputAndSweepTheTolerance() throws {
        let clock = ContinuousClock()
        func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18 }
        let scene = Scene(spin: 0.9, inclination: 80)
        let (config, rays) = Self.rays(scene, size: 632)  // ≈ 4×10⁵ rays
        let cpu = RayTracer(config: config)
        let cpuStart = clock.now
        let cpuOutcomes = DispatchQueue.concurrentPerformMap(count: rays.count) { cpu.trace(rays[$0]).outcome }
        let cpuSeconds = seconds(clock.now - cpuStart)
        print("SPIKE CPU: \(Double(rays.count) / cpuSeconds) rays/s over \(rays.count) rays (\(cpuSeconds) s)")

        let tracer = MetalRayTracer(context: try #require(Self.context))
        let inputs = rays.map(GPURayInput.init)
        _ = try tracer.trace(inputs: inputs, parameters: Self.parameters(config))  // warm-up (pipeline, buffers)
        for (rtol, angle) in [(1e-4, 1e-5), (1e-5, 1e-5), (1e-5, 1e-6), (1e-5, 3e-7), (1e-6, 3e-7)] as [(Float, Float)] {
            var p = Self.parameters(config, relativeTolerance: rtol)
            p.angleTolerance = angle
            let start = clock.now
            let results = try tracer.trace(inputs: inputs, parameters: p)
            let gpuSeconds = seconds(clock.now - start)
            let flagged = results.indices.filter { results[$0].isDelicate }
            // Cost of re-tracing the flagged rays on the CPU.
            let refineStart = clock.now
            _ = DispatchQueue.concurrentPerformMap(count: flagged.count) { cpu.trace(rays[flagged[$0]]).outcome }
            let refineSeconds = seconds(clock.now - refineStart)
            var matching = 0, skyWithin = 0, sky = 0
            var steps = 0
            for (i, r) in results.enumerated() {
                steps += Int(r.steps)
                if r.isDelicate { matching += 1; continue }
                switch (cpuOutcomes[i], r.outcome(constants: rays[i].constants, kerr: config.kerr)) {
                case (.captured, .captured): matching += 1
                case (.sky(let a), .sky(let b)):
                    matching += 1; sky += 1
                    if acos(min(max((a * b).sum(), -1), 1)) <= 1e-4 { skyWithin += 1 }
                default: break
                }
            }
            let hybridSeconds = gpuSeconds + refineSeconds  // CPU refinement could overlap the next band; this is the serial bound
            print("SPIKE GPU rtol=\(rtol) angle=\(angle): GPU \(Double(rays.count) / gpuSeconds) rays/s (\(cpuSeconds / gpuSeconds)x CPU), steps/ray \(steps / rays.count), flagged \(Double(flagged.count) / Double(rays.count)), refine \(refineSeconds) s, hybrid serial speed-up \(cpuSeconds / hybridSeconds)x, outcome match \(Double(matching) / Double(rays.count)), unflagged sky within 1e-4 rad \(Double(skyWithin) / Double(max(sky, 1)))")
        }
    }
}

/// Backing store for `concurrentPerformMap`; each index is written by exactly one thread.
final class ParallelMapStorage<U>: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<U?>
    let count: Int
    init(_ n: Int) { count = n; pointer = .allocate(capacity: n); pointer.initialize(repeating: nil, count: n) }
    deinit { pointer.deinitialize(count: count); pointer.deallocate() }
}

extension DispatchQueue {
    /// Parallel map used by the benchmarks.
    static func concurrentPerformMap<T: Sendable>(count: Int, _ body: @escaping @Sendable (Int) -> T) -> [T] {
        let storage = ParallelMapStorage<T>(count)
        let chunk = 64
        DispatchQueue.concurrentPerform(iterations: (count + chunk - 1) / chunk) { c in
            for i in (c * chunk)..<min(count, (c + 1) * chunk) { storage.pointer[i] = body(i) }
        }
        return (0..<count).map { storage.pointer[$0]! }
    }
}
