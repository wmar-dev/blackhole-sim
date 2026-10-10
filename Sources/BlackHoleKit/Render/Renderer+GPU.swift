import Dispatch
import Foundation

/// What the GPU backend did during a render (reported by `bhsim compare` and the benchmarks).
public struct GPUStatistics: Sendable, Equatable {
    public var bands = 0
    public var passes = 0
    /// Rays flagged delicate by the kernel (path close to a pole) or not finished by it, re-traced on the CPU in float64.
    public var refinedRays = 0
    /// Longest single GPU command, in seconds (watchdog safety, FR-009).
    public var maxPassSeconds = 0.0
    public var gpuSeconds = 0.0
    /// Bytes of GPU memory held by the band buffers.
    public var bufferBytes = 0
}

/// Pointer wrapper for disjoint writes from parallel loops (each index is written by exactly one iteration).
struct SendablePointer<T>: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<T>
    init(_ pointer: UnsafeMutablePointer<T>) { self.pointer = pointer }
    subscript(_ i: Int) -> T {
        get { pointer[i] }
        nonmutating set { pointer[i] = newValue }
    }
}

extension Renderer {
    /// The GPU render path (research.md D1, D4): the image is cut into row bands of about `gpuBandSamples` samples. For
    /// each band the CPU builds the camera rays in float64, the GPU traces and classifies them in float32, the CPU
    /// re-traces in float64 the rays the GPU flagged delicate or did not finish, and then shades and averages in float64
    /// exactly as the CPU backend does. Every sample is computed independently, so the result does not depend on timing.
    func renderGPU(progress: (@Sendable (Double) -> Void)?) throws -> RenderedImage {
        let start = ContinuousClock.now
        guard let gpu else { preconditionFailure("renderGPU needs the GPU backend") }
        let width = config.width, height = config.height
        let samplesPerAxis = Int(Double(config.samplesPerPixel).squareRoot().rounded())
        let perPixel = samplesPerAxis * samplesPerAxis
        let seed = config.sky.seed
        let rowsPerBand = max(1, NumericalDefaults.gpuBandSamples / (width * perPixel))
        let parameters = GPUKernelParameters(
            config: config, relativeTolerance: Float(NumericalDefaults.gpuRelativeTolerance),
            absoluteTolerance: Float(NumericalDefaults.gpuAbsoluteTolerance),
            stepsPerPass: UInt32(NumericalDefaults.gpuStepsPerPass), stepBudget: UInt32(config.maxStepsPerRay))
        let buffers = try gpu.makeBuffers(capacity: min(rowsPerBand, height) * width * perPixel)
        var statistics = GPUStatistics()
        statistics.bufferBytes = buffers.byteCount

        let pixelCount = width * height
        let colors = UnsafeMutablePointer<SIMD3<Float>>.allocate(capacity: pixelCount)
        let fractions = UnsafeMutablePointer<SIMD4<Float>>.allocate(capacity: pixelCount)  // disk, captured, higher order, unresolved
        defer { colors.deallocate(); fractions.deallocate() }
        let rowDiagnostics = UnsafeMutablePointer<Diagnostics>.allocate(capacity: height)
        rowDiagnostics.initialize(repeating: Diagnostics(), count: height)
        defer { rowDiagnostics.deinitialize(count: height); rowDiagnostics.deallocate() }
        let rowRefined = UnsafeMutablePointer<Int>.allocate(capacity: height)
        rowRefined.initialize(repeating: 0, count: height)
        defer { rowRefined.deallocate() }

        let colorsOut = SendablePointer(colors), fractionsOut = SendablePointer(fractions)
        let diagnosticsOut = SendablePointer(rowDiagnostics), refinedOut = SendablePointer(rowRefined)
        let inputs = SendablePointer(buffers.inputPointer)
        let results = SendablePointer(buffers.resultPointer)
        let rays = UnsafeMutablePointer<CameraRay>.allocate(capacity: buffers.capacity)
        defer { rays.deallocate() }
        let raysOut = SendablePointer(rays)

        var y0 = 0
        while y0 < height {
            let rows = min(rowsPerBand, height - y0)
            let count = rows * width * perPixel
            let bandStart = y0

            // 1. Camera rays (float64) and their float32 images for the GPU.
            DispatchQueue.concurrentPerform(iterations: rows) { r in
                let y = bandStart + r
                for x in 0..<width {
                    for s in 0..<perPixel {
                        let index = (r * width + x) * perPixel + s
                        let jitter = SampleJitter.offset(seed: seed, pixelX: x, pixelY: y, sample: s)
                        let px = Double(x) + (Double(s % samplesPerAxis) + jitter.x) / Double(samplesPerAxis)
                        let py = Double(y) + (Double(s / samplesPerAxis) + jitter.y) / Double(samplesPerAxis)
                        let ray = camera.ray(pixelX: px, pixelY: py)
                        (raysOut.pointer + index).initialize(to: ray)
                        inputs[index] = GPURayInput(ray)
                    }
                }
            }

            // 2. Trace on the GPU.
            let run = try gpu.run(buffers: buffers, rayCount: count, parameters: parameters)
            statistics.bands += 1
            statistics.passes += run.passes
            statistics.gpuSeconds += run.gpuSeconds
            statistics.maxPassSeconds = max(statistics.maxPassSeconds, run.maxPassSeconds)

            // 3. Per row: re-trace the delicate and unfinished rays in float64, then shade and average (float64).
            DispatchQueue.concurrentPerform(iterations: rows) { r in
                let y = bandStart + r
                var diagnostics = Diagnostics()
                var refined = 0
                for x in 0..<width {
                    var sum = SIMD3<Double>.zero
                    var resolved = 0, disk = 0, captured = 0, higherOrder = 0, unresolved = 0
                    for s in 0..<perPixel {
                        let index = (r * width + x) * perPixel + s
                        let ray = raysOut[index]
                        let gpuResult = results[index]
                        let outcome: RayOutcome
                        let residual: Double
                        if gpuResult.isDelicate || gpuResult.outcome >= 4 {
                            let cpu = tracer.trace(ray)
                            outcome = cpu.outcome
                            residual = cpu.maxResidual
                            refined += 1
                        } else {
                            outcome = gpuResult.outcome(constants: ray.constants, kerr: config.kerr)
                            residual = Double(gpuResult.maxResidual)
                        }
                        diagnostics.record(outcome, residual: residual)
                        switch outcome {
                        case .disk(_, let index, _):
                            disk += 1
                            if index >= 2 { higherOrder += 1 }
                        case .captured: captured += 1
                        case .unresolved: unresolved += 1
                        case .sky: break
                        }
                        if let radiance = self.radiance(of: outcome, ray: ray) {
                            sum += radiance
                            resolved += 1
                        }
                    }
                    let total = Float(perPixel)
                    let pixel = y * width + x
                    colorsOut[pixel] = resolved > 0 ? SIMD3<Float>(sum / Double(resolved)) : .zero
                    fractionsOut[pixel] = SIMD4(Float(disk) / total, Float(captured) / total, Float(higherOrder) / total, Float(unresolved) / total)
                }
                diagnosticsOut[y] = diagnostics
                refinedOut[y] = refined
            }
            y0 += rows
            progress?(Double(y0) / Double(height))
        }

        var diagnostics = Diagnostics()
        for y in 0..<height {
            diagnostics.merge(rowDiagnostics[y])
            statistics.refinedRays += rowRefined[y]
        }
        let elapsed = ContinuousClock.now - start
        diagnostics.wallTimeSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        let fractionBuffer = UnsafeBufferPointer(start: fractions, count: pixelCount)
        return RenderedImage(width: width, height: height,
                             hdr: Array(UnsafeBufferPointer(start: colors, count: pixelCount)),
                             diskFraction: fractionBuffer.map(\.x), capturedFraction: fractionBuffer.map(\.y),
                             higherOrderFraction: fractionBuffer.map(\.z), unresolvedFraction: fractionBuffer.map(\.w),
                             diagnostics: diagnostics, shading: .physical, backend: .metal, referenceRadiance: referenceRadiance,
                             gpuStatistics: statistics)
    }
}
