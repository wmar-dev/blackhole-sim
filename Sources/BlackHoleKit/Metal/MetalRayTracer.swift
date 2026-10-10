import Foundation
import Metal

// MARK: Buffer layouts (contracts/gpu-buffers.md). Only 4-byte scalars, so Swift and the kernel agree on offsets;
// MetalKernelTests checks the sizes and offsets against the kernel.

/// One ray handed to the GPU (host → GPU): the float32 conversion of a float64 camera ray, with E = 1.
public struct GPURayInput {
    public var u: Float
    public var vu: Float
    public var mu: Float
    public var vmu: Float
    public var phi: Float
    public var L: Float
    public var Q: Float
    public var pad: Float = 0

    public init(u: Float, vu: Float, mu: Float, vmu: Float, phi: Float, L: Float, Q: Float) {
        self.u = u; self.vu = vu; self.mu = mu; self.vmu = vmu; self.phi = phi; self.L = L; self.Q = Q
    }

    public init(_ ray: CameraRay) {
        self.init(u: Float(ray.state.u), vu: Float(ray.state.vu), mu: Float(ray.state.mu), vmu: Float(ray.state.vmu),
                  phi: Float(ray.state.phi), L: Float(ray.constants.angularMomentum), Q: Float(ray.constants.carter))
    }
}

/// Integration state of an unfinished ray, kept on the GPU between passes.
public struct GPURayState {
    public var u: Float = 0
    public var vu: Float = 0
    public var mu: Float = 0
    public var vmu: Float = 0
    public var phi: Float = 0
    public var step: Float = 0
    public var maxResidual: Float = 0
    /// Smallest sin²θ = 1 − μ² along the path so far (how close the ray came to a pole).
    public var minSin2: Float = 0
    public var steps: UInt32 = 0
    public var crossings: UInt32 = 0
    public var side: Int32 = 0
    public var landing: UInt32 = 0
    public var status: UInt32 = 0
    public var pad1: UInt32 = 0
    public var pad2: UInt32 = 0
    public var pad3: UInt32 = 0
}

/// The outcome of a ray (GPU → host).
public struct GPURayResult {
    public var outcome: UInt32 = 0
    public var crossingIndex: UInt32 = 0
    public var face: UInt32 = 0
    public var radius: Float = 0
    public var u: Float = 0
    public var vu: Float = 0
    public var mu: Float = 0
    public var vmu: Float = 0
    public var phi: Float = 0
    public var maxResidual: Float = 0
    public var steps: UInt32 = 0
    public var pad: UInt32 = 0

    /// `face` is a bit field: bit 0 = lower face (disk hits); bit 1 = delicate.
    public var isDelicate: Bool { face & 2 != 0 }

    /// Converts to the CPU's `RayOutcome`. For sky rays the direction of travel is computed here, in float64, from the
    /// float32 final state, with the same code the CPU backend uses.
    public func outcome(constants: PhotonConstants, kerr: Kerr) -> RayOutcome {
        switch outcome {
        case 1: return .captured
        case 2: return .disk(radius: Double(radius), crossingIndex: Int(crossingIndex), face: face & 1 == 0 ? .upper : .lower)
        case 3:
            let state = RayState(u: Double(u), vu: Double(vu), mu: Double(mu), vmu: Double(vmu), phi: Double(phi))
            return .sky(direction: AsymptoticDirection.direction(of: state, constants: constants, kerr: kerr))
        case 4: return .unresolved(.stepBudget)
        default: return .unresolved(.integrationFailure)
        }
    }
}

/// Constants of a render, shared by all rays (constant buffer).
public struct GPUKernelParameters {
    public var spin: Float
    public var skyU: Float
    public var horizonU: Float
    public var captureU: Float
    public var diskInner: Float
    public var diskOuter: Float
    public var relativeTolerance: Float
    public var absoluteTolerance: Float
    public var rayCount: UInt32 = 0
    public var stepsPerPass: UInt32
    public var stepBudget: UInt32
    public var maxCrossings: UInt32
    /// Relative tolerance of the angular components (μ, dμ/dλ′, φ), which alone fix the final direction.
    public var angleTolerance: Float
    /// Rays whose path comes closer to a pole than this sin²θ are flagged delicate (research.md D2, mitigation M3).
    public var polarFlagSin2: Float
    public var pad2: UInt32 = 0
    public var pad3: UInt32 = 0

    /// Parameters with an explicit disk annulus (used by tests; a `maxCrossings` of 0 disables the disk).
    public init(spin: Double, skyRadius: Double, diskInner: Double, diskOuter: Double, maxCrossings: Int,
                relativeTolerance: Float = Float(NumericalDefaults.gpuRelativeTolerance),
                angleTolerance: Float = Float(NumericalDefaults.gpuAngleTolerance),
                absoluteTolerance: Float = Float(NumericalDefaults.gpuAbsoluteTolerance),
                stepsPerPass: UInt32 = UInt32(NumericalDefaults.gpuStepsPerPass), stepBudget: UInt32 = UInt32(NumericalDefaults.stepBudget),
                polarFlagSin2: Float = Float(NumericalDefaults.gpuPolarFlagSin2)) {
        let kerr = Kerr(spin: spin)
        self.spin = Float(spin)
        skyU = Float(1 / skyRadius)
        horizonU = Float(1 / kerr.horizonRadius)
        captureU = Float(1 / (kerr.horizonRadius + NumericalDefaults.horizonCutoff))
        self.diskInner = Float(diskInner)
        self.diskOuter = Float(diskOuter)
        self.relativeTolerance = relativeTolerance
        self.angleTolerance = angleTolerance
        self.absoluteTolerance = absoluteTolerance
        self.stepsPerPass = stepsPerPass
        self.stepBudget = stepBudget
        self.maxCrossings = UInt32(maxCrossings)
        self.polarFlagSin2 = polarFlagSin2
    }

    public init(config: RenderConfig, relativeTolerance: Float, angleTolerance: Float? = nil, absoluteTolerance: Float, stepsPerPass: UInt32, stepBudget: UInt32,
                polarFlagSin2: Float = Float(NumericalDefaults.gpuPolarFlagSin2)) {
        let kerr = config.kerr
        spin = Float(config.blackHole.spin)
        skyU = Float(1 / config.skyRadius)
        horizonU = Float(1 / kerr.horizonRadius)
        captureU = Float(1 / (kerr.horizonRadius + NumericalDefaults.horizonCutoff))
        diskInner = Float(kerr.iscoRadius)
        diskOuter = Float(config.disk.outerRadius)
        self.relativeTolerance = relativeTolerance
        self.angleTolerance = angleTolerance ?? Float(NumericalDefaults.gpuAngleTolerance)
        self.polarFlagSin2 = polarFlagSin2
        self.absoluteTolerance = absoluteTolerance
        self.stepsPerPass = stepsPerPass
        self.stepBudget = stepBudget
        maxCrossings = config.diskEnabled ? UInt32(NumericalDefaults.maxPlaneCrossings) : 0
    }
}

/// Runs the ray-tracing kernels (research.md D3): initializes the ray states, then advances every unfinished ray by a
/// bounded number of steps per GPU command until all have finished, so that no command runs long enough to be cut off.
public final class MetalRayTracer: @unchecked Sendable {
    public let context: MetalContext

    /// Shared-memory buffers for one band of rays (unified memory: the CPU writes inputs and reads results in place).
    public final class Buffers: @unchecked Sendable {
        public let capacity: Int
        let inputs: MTLBuffer
        let states: MTLBuffer
        let results: MTLBuffer
        let counter: MTLBuffer

        init(device: MTLDevice, capacity: Int) throws {
            self.capacity = capacity
            func make(_ length: Int, _ what: String) throws -> MTLBuffer {
                guard let b = device.makeBuffer(length: max(length, 16), options: .storageModeShared) else {
                    throw BackendError.unavailable("could not allocate \(length) bytes of GPU memory for \(what)")
                }
                return b
            }
            inputs = try make(capacity * MemoryLayout<GPURayInput>.stride, "ray inputs")
            states = try make(capacity * MemoryLayout<GPURayState>.stride, "ray states")
            results = try make(capacity * MemoryLayout<GPURayResult>.stride, "ray results")
            counter = try make(MemoryLayout<UInt32>.stride, "the pass counter")
        }

        /// Bytes of GPU memory held by these buffers.
        public var byteCount: Int { inputs.length + states.length + results.length + counter.length }

        public var inputPointer: UnsafeMutablePointer<GPURayInput> {
            inputs.contents().bindMemory(to: GPURayInput.self, capacity: capacity)
        }
        public var resultPointer: UnsafeMutablePointer<GPURayResult> {
            results.contents().bindMemory(to: GPURayResult.self, capacity: capacity)
        }
    }

    public struct RunStatistics {
        public var passes = 0
        /// Longest single GPU command, in seconds (watchdog safety, FR-009).
        public var maxPassSeconds = 0.0
        public var gpuSeconds = 0.0
    }

    private var cachedBuffers: Buffers?

    public init(context: MetalContext) {
        self.context = context
    }

    public func makeBuffers(capacity: Int) throws -> Buffers {
        try Buffers(device: context.device, capacity: capacity)
    }

    private func threadgroupWidth(for pipeline: MTLComputePipelineState) -> Int {
        let width = pipeline.threadExecutionWidth
        return max(width, min(pipeline.maxTotalThreadsPerThreadgroup, 128) / width * width)
    }

    /// Traces `rayCount` rays whose inputs are already in `buffers`; results are left in `buffers.resultPointer`.
    @discardableResult
    public func run(buffers: Buffers, rayCount: Int, parameters: GPUKernelParameters,
                    onPass: ((_ pass: Int, _ unfinished: Int) -> Void)? = nil) throws -> RunStatistics {
        precondition(rayCount <= buffers.capacity, "band larger than its buffers")
        var params = parameters
        params.rayCount = UInt32(rayCount)
        var statistics = RunStatistics()
        guard rayCount > 0 else { return statistics }

        let initialize = try context.pipeline(named: "initializeStates")
        let trace = try context.pipeline(named: "traceRays")

        func dispatch(_ pipeline: MTLComputePipelineState, bindings: (MTLComputeCommandEncoder) -> Void) throws -> MTLCommandBuffer {
            guard let commandBuffer = context.queue.makeCommandBuffer(), let encoder = commandBuffer.makeComputeCommandEncoder() else {
                throw BackendError.unavailable("could not create a GPU command")
            }
            encoder.setComputePipelineState(pipeline)
            encoder.setBytes(&params, length: MemoryLayout<GPUKernelParameters>.stride, index: 0)
            bindings(encoder)
            encoder.dispatchThreads(MTLSize(width: rayCount, height: 1, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: threadgroupWidth(for: pipeline), height: 1, depth: 1))
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            if let error = commandBuffer.error {
                throw BackendError.unavailable("a GPU command failed: \(error.localizedDescription)")
            }
            return commandBuffer
        }

        _ = try dispatch(initialize) { e in
            e.setBuffer(buffers.inputs, offset: 0, index: 1)
            e.setBuffer(buffers.states, offset: 0, index: 2)
            e.setBuffer(buffers.results, offset: 0, index: 3)
        }

        let maxPasses = Int(parameters.stepBudget) / max(Int(parameters.stepsPerPass), 1) + 64
        let counter = buffers.counter.contents().bindMemory(to: UInt32.self, capacity: 1)
        while statistics.passes < maxPasses {
            counter.pointee = 0
            let commandBuffer = try dispatch(trace) { e in
                e.setBuffer(buffers.inputs, offset: 0, index: 1)
                e.setBuffer(buffers.states, offset: 0, index: 2)
                e.setBuffer(buffers.results, offset: 0, index: 3)
                e.setBuffer(buffers.counter, offset: 0, index: 4)
            }
            let duration = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
            statistics.passes += 1
            statistics.gpuSeconds += duration
            statistics.maxPassSeconds = max(statistics.maxPassSeconds, duration)
            let unfinished = Int(counter.pointee)
            onPass?(statistics.passes, unfinished)
            if unfinished == 0 { return statistics }
        }
        throw BackendError.unavailable("the GPU kernel did not finish within \(maxPasses) passes")
    }

    /// Convenience for tests and the benchmark: traces `inputs` and returns the results.
    public func trace(inputs: [GPURayInput], parameters: GPUKernelParameters) throws -> [GPURayResult] {
        if cachedBuffers == nil || cachedBuffers!.capacity < inputs.count {
            cachedBuffers = try makeBuffers(capacity: max(inputs.count, 1))
        }
        let buffers = cachedBuffers!
        inputs.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { buffers.inputPointer.update(from: base, count: inputs.count) }
        }
        try run(buffers: buffers, rayCount: inputs.count, parameters: parameters)
        return Array(UnsafeBufferPointer(start: buffers.resultPointer, count: inputs.count))
    }
}
