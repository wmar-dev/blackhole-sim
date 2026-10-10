import Foundation
import Metal

/// The GPU device, command queue, compiled kernels and pipelines.
///
/// Metal objects are not `Sendable`; this class is `@unchecked Sendable` on the rule that one context is used from one
/// place at a time (the render path uses one queue and waits for each command buffer; research.md R4).
public final class MetalContext: @unchecked Sendable {
    public let device: MTLDevice
    public let queue: MTLCommandQueue
    public let library: MTLLibrary
    private var pipelines: [String: MTLComputePipelineState] = [:]
    private let lock = NSLock()

    /// Environment variable that simulates a missing GPU, so the error path is testable on machines that have one.
    public static let forceNoGPUVariable = "BHSIM_FORCE_NO_GPU"

    private init(device: MTLDevice, queue: MTLCommandQueue, library: MTLLibrary) {
        self.device = device
        self.queue = queue
        self.library = library
    }

    /// Creates the context, or throws `BackendError.unavailable` with a specific reason.
    /// - Parameters:
    ///   - forceUnavailable: simulate a missing GPU (also done by `BHSIM_FORCE_NO_GPU=1`).
    ///   - includeTestKernels: also compile the test-only kernels (`BHSIM_TEST_KERNELS`), used by the unit tests.
    public static func make(forceUnavailable: Bool = false, includeTestKernels: Bool = false) throws -> MetalContext {
        if forceUnavailable || ProcessInfo.processInfo.environment[forceNoGPUVariable] == "1" {
            throw BackendError.unavailable("no GPU available: the GPU backend was disabled with \(forceNoGPUVariable)=1 (simulated missing GPU)")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw BackendError.unavailable("no Metal-capable GPU was found on this machine")
        }
        guard let queue = device.makeCommandQueue() else {
            throw BackendError.unavailable("could not create a command queue on the GPU '\(device.name)'")
        }
        let options = MTLCompileOptions()
        // IEEE-conforming arithmetic: no reordering, no assumption that values are finite (research.md D6).
        if #available(macOS 15.0, *) { options.mathMode = .safe } else { options.fastMathEnabled = false }
        if includeTestKernels { options.preprocessorMacros = ["BHSIM_TEST_KERNELS": NSNumber(value: 1)] }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: GeodesicKernelSource.source, options: options)
        } catch {
            throw BackendError.unavailable("the GPU kernels failed to compile: \(error.localizedDescription)")
        }
        let context = MetalContext(device: device, queue: queue, library: library)
        _ = try context.pipeline(named: "initializeStates")
        _ = try context.pipeline(named: "traceRays")
        return context
    }

    // MARK: Process-wide cache (research D9): an animation renders many frames and must not recompile the kernel each time.

    private static let sharedLock = NSLock()
    nonisolated(unsafe) private static var shared: MetalContext?
    nonisolated(unsafe) private static var sharedCreations = 0

    /// The process-wide context, created on first use. A simulated missing GPU is never cached.
    public static func cached(forceUnavailable: Bool = false) throws -> MetalContext {
        if forceUnavailable || ProcessInfo.processInfo.environment[forceNoGPUVariable] == "1" {
            return try make(forceUnavailable: forceUnavailable)
        }
        sharedLock.lock()
        defer { sharedLock.unlock() }
        if let shared { return shared }
        let context = try make()
        shared = context
        sharedCreations += 1
        return context
    }

    /// How many times the shared context has been created since the last reset (tests).
    public static var sharedCreationCount: Int {
        sharedLock.lock(); defer { sharedLock.unlock() }
        return sharedCreations
    }

    /// Forgets the shared context and the creation count (tests).
    public static func resetSharedForTesting() {
        sharedLock.lock(); defer { sharedLock.unlock() }
        shared = nil
        sharedCreations = 0
    }

    /// The compute pipeline for the kernel `name`, created on first use.
    public func pipeline(named name: String) throws -> MTLComputePipelineState {
        lock.lock()
        defer { lock.unlock() }
        if let existing = pipelines[name] { return existing }
        guard let function = library.makeFunction(name: name) else {
            throw BackendError.unavailable("the GPU kernel '\(name)' is missing")
        }
        do {
            let state = try device.makeComputePipelineState(function: function)
            pipelines[name] = state
            return state
        } catch {
            throw BackendError.unavailable("could not build the GPU pipeline '\(name)': \(error.localizedDescription)")
        }
    }
}
