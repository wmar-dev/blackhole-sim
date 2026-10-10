import Foundation
import Metal

/// Access to the test-only kernels (compiled when the context is made with `includeTestKernels: true`).
extension MetalRayTracer {
    struct LayoutInfo {
        var sizes: [Int]
        var stateOffsets: [Int]
        var resultOffsets: [Int]
        var parameterOffsets: [Int]
    }

    /// Sizes and field offsets of the kernel's structs, as the kernel sees them.
    func queryLayout() throws -> LayoutInfo {
        let words = try runKernel(named: "queryLayout", input: [], count: 1, inputStride: 0, outputStride: 15, threads: 1) as [UInt32]
        let v = words.map(Int.init)
        return LayoutInfo(sizes: Array(v[0..<4]), stateOffsets: Array(v[4..<9]), resultOffsets: Array(v[9..<13]), parameterOffsets: Array(v[13..<15]))
    }

    private func caseFloats(_ cases: [(Double, PhotonConstants, RayState)], stepSize: Double) -> [Float] {
        var floats: [Float] = []
        for (spin, c, s) in cases {
            floats += [Float(spin), Float(c.angularMomentum), Float(c.carter), Float(s.u), Float(s.vu), Float(s.mu), Float(s.vmu), Float(s.phi), Float(stepSize)]
        }
        return floats
    }

    func evaluateDerivative(_ cases: [(Double, PhotonConstants, RayState)]) throws -> [[Float]] {
        let out = try runKernel(named: "testDerivative", input: caseFloats(cases, stepSize: 0), count: cases.count, inputStride: 9, outputStride: 10) as [Float]
        return (0..<cases.count).map { Array(out[($0 * 10)..<($0 * 10 + 5)]) }
    }

    func evaluateStep(_ cases: [(Double, PhotonConstants, RayState)], stepSize: Double) throws -> [(y: [Float], err: [Float])] {
        let out = try runKernel(named: "testStep", input: caseFloats(cases, stepSize: stepSize), count: cases.count, inputStride: 9, outputStride: 10) as [Float]
        return (0..<cases.count).map { (Array(out[($0 * 10)..<($0 * 10 + 5)]), Array(out[($0 * 10 + 5)..<($0 * 10 + 10)])) }
    }

    func evaluateResidual(_ cases: [(Double, PhotonConstants, RayState)]) throws -> [Float] {
        try runKernel(named: "testResidual", input: caseFloats(cases, stepSize: 0), count: cases.count, inputStride: 9, outputStride: 1)
    }

    /// Runs a test kernel with one thread per case.
    private func runKernel<T: Numeric>(named name: String, input: [Float], count: Int, inputStride: Int, outputStride: Int, threads: Int? = nil) throws -> [T] {
        let pipeline = try context.pipeline(named: name)
        let device = context.device
        let outLength = max(count * outputStride * MemoryLayout<T>.stride, 16)
        guard let outBuffer = device.makeBuffer(length: outLength, options: .storageModeShared),
              let commandBuffer = context.queue.makeCommandBuffer(), let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw BackendError.unavailable("could not set up the test kernel '\(name)'")
        }
        encoder.setComputePipelineState(pipeline)
        if inputStride > 0 {
            guard let inBuffer = device.makeBuffer(bytes: input, length: input.count * MemoryLayout<Float>.stride, options: .storageModeShared) else {
                throw BackendError.unavailable("could not allocate the test kernel input")
            }
            encoder.setBuffer(inBuffer, offset: 0, index: 0)
            encoder.setBuffer(outBuffer, offset: 0, index: 1)
        } else {
            encoder.setBuffer(outBuffer, offset: 0, index: 0)
        }
        encoder.dispatchThreads(MTLSize(width: threads ?? count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error { throw BackendError.unavailable("test kernel '\(name)' failed: \(error.localizedDescription)") }
        let pointer = outBuffer.contents().bindMemory(to: T.self, capacity: count * outputStride)
        return Array(UnsafeBufferPointer(start: pointer, count: count * outputStride))
    }
}
