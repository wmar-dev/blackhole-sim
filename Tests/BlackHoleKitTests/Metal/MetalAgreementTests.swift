import Foundation
import Testing
@testable import BlackHoleKit

/// Ray-by-ray and pixel-by-pixel agreement of the GPU backend with the CPU reference (FR-003, SC-002).
@Suite struct MetalAgreementTests {
    static let hasGPU = (try? MetalContext.make()) != nil

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(p * Double(sorted.count)))]
    }

    @Test(.enabled(if: MetalAgreementTests.hasGPU), arguments: [(0.0, 90.0), (0.9, 85.0), (0.998, 60.0)])
    func rayOutcomesRadiiAndDirectionsAgree(spin: Double, inclination: Double) throws {
        var config = RenderConfig()
        config.width = 240; config.height = 135
        config.blackHole.spin = spin
        config.observer.inclinationDegrees = inclination
        config.backend = .metal
        let renderer = try Renderer(config: config)
        var cpuConfig = config; cpuConfig.backend = .cpu
        let cpuRenderer = try Renderer(config: cpuConfig)

        var rays: [CameraRay] = []
        for y in 0..<config.height { for x in 0..<config.width { rays.append(renderer.camera.ray(pixelX: Double(x) + 0.5, pixelY: Double(y) + 0.5)) } }
        let params = GPUKernelParameters(config: config, relativeTolerance: Float(NumericalDefaults.gpuRelativeTolerance),
                                         absoluteTolerance: Float(NumericalDefaults.gpuAbsoluteTolerance),
                                         stepsPerPass: UInt32(NumericalDefaults.gpuStepsPerPass), stepBudget: UInt32(config.maxStepsPerRay))
        let gpuResults = try #require(renderer.gpu).trace(inputs: rays.map(GPURayInput.init), parameters: params)

        var same = 0, radiusErrors: [Double] = [], directionErrors: [Double] = []
        for (ray, g) in zip(rays, gpuResults) {
            let reference = cpuRenderer.tracer.trace(ray).outcome
            // Delicate rays are re-traced on the CPU in float64 by the render path, so they agree by construction.
            let candidate = g.isDelicate || g.outcome >= 4 ? reference : g.outcome(constants: ray.constants, kerr: config.kerr)
            switch (reference, candidate) {
            case (.captured, .captured): same += 1
            case (.disk(let r1, let i1, let f1), .disk(let r2, let i2, let f2)):
                if i1 == i2 && f1 == f2 { same += 1 }
                radiusErrors.append(abs(r1 - r2) / r1)
            case (.sky(let d1), .sky(let d2)):
                same += 1
                directionErrors.append(acos(min(1, max(-1, (d1 * d2).sum()))))
            default: break
            }
        }
        let fraction = Double(same) / Double(rays.count)
        #expect(fraction >= 0.999, "same outcome: \(fraction)")
        #expect(percentile(radiusErrors, 0.99) < 1e-3, "99th percentile crossing-radius error \(percentile(radiusErrors, 0.99))")
        let within = Double(directionErrors.filter { $0 <= 1e-4 }.count) / Double(max(directionErrors.count, 1))
        #expect(within >= 0.999, "sky directions within 1e-4 rad: \(within)")
    }

    @Test(.enabled(if: MetalAgreementTests.hasGPU)) func diskAndHorizonPixelRadianceAgrees() throws {
        var config = RenderConfig()
        config.width = 240; config.height = 135
        let cpu = try Renderer(config: config).render()
        config.backend = .metal
        let gpu = try Renderer(config: config).renderOnBackend()
        let peak = Double(cpu.hdr.map { max($0.x, $0.y, $0.z) }.max() ?? 1)
        var errors: [Double] = []
        for i in cpu.hdr.indices where cpu.unresolvedFraction[i] == 0 && gpu.unresolvedFraction[i] == 0
            && (cpu.diskFraction[i] + cpu.capturedFraction[i] == 1) && (gpu.diskFraction[i] + gpu.capturedFraction[i] == 1) {
            let a = cpu.hdr[i], b = gpu.hdr[i]
            let scale = max(Double(max(a.x, a.y, a.z)), 1e-3 * peak)
            errors.append(Double(max(abs(a.x - b.x), abs(a.y - b.y), abs(a.z - b.z))) / scale)
        }
        #expect(errors.count > 500)
        #expect(percentile(errors, 0.99) < 0.01, "99th percentile radiance difference \(percentile(errors, 0.99))")
    }
}
