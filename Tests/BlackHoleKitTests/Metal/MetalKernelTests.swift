import Foundation
import Testing
@testable import BlackHoleKit

/// Unit tests of the kernel's building blocks against the CPU implementation (research.md D12, contracts/gpu-buffers.md).
/// Skipped on machines without a GPU.
@Suite struct MetalKernelTests {
    static let context = try? MetalContext.make(includeTestKernels: true)
    static var hasGPU: Bool { context != nil }

    /// Valid ray states (satisfying both first integrals) at several radii and polar positions.
    struct Sample {
        let spin: Double
        let constants: PhotonConstants
        let state: RayState
    }

    static let samples: [Sample] = {
        var list: [Sample] = []
        let rays: [(L: Double, Q: Double, r: Double, mu: Double)] = [
            (3.0, 30.0, 100, 0.17), (-4.0, 12.0, 20, 0.4), (6.5, 2.0, 8, -0.3), (1.0, 40.0, 4, 0.8),
            (-2.0, 9.0, 2.6, -0.5), (0.0, 25.0, 50, 0.3), (7.0, 0.0, 30, 0.0), (5.0, 22.0, 3.3, 0.2),
        ]
        for a in [0.0, 0.5, 0.9, 0.998] {
            for ray in rays {
                let constants = PhotonConstants(energy: 1, angularMomentum: ray.L, carter: ray.Q)
                let integrator = GeodesicIntegrator(kerr: Kerr(spin: a), constants: constants, settings: .standard(skyRadius: 1000))
                for sign in [-1.0, 1.0] {
                    if let s = integrator.initialState(r: ray.r, mu: ray.mu, radialSign: sign, polarSign: sign, phi: 0.7) {
                        list.append(Sample(spin: a, constants: constants, state: s))
                    }
                }
            }
        }
        return list
    }()

    private func close(_ gpu: Float, _ cpu: Double, tolerance: Double = 2e-5) -> Bool {
        abs(Double(gpu) - cpu) <= tolerance * max(abs(cpu), 1.0)
    }

    @Test(.enabled(if: MetalKernelTests.hasGPU)) func structLayoutsMatchTheKernel() throws {
        let tracer = MetalRayTracer(context: try #require(Self.context))
        let layout = try tracer.queryLayout()
        #expect(layout.sizes == [MemoryLayout<GPURayInput>.stride, MemoryLayout<GPURayState>.stride,
                                 MemoryLayout<GPURayResult>.stride, MemoryLayout<GPUKernelParameters>.stride])
        #expect(layout.sizes == [32, 64, 48, 64], "contract sizes (contracts/gpu-buffers.md)")
        #expect(MemoryLayout<GPURayInput>.size == 32 && MemoryLayout<GPURayState>.size == 64)
        #expect(MemoryLayout<GPURayResult>.size == 48 && MemoryLayout<GPUKernelParameters>.size == 64)
        // Field offsets reported by the kernel equal the Swift offsets.
        #expect(layout.stateOffsets == [
            MemoryLayout<GPURayState>.offset(of: \.steps)!, MemoryLayout<GPURayState>.offset(of: \.crossings)!,
            MemoryLayout<GPURayState>.offset(of: \.side)!, MemoryLayout<GPURayState>.offset(of: \.landing)!,
            MemoryLayout<GPURayState>.offset(of: \.status)!,
        ])
        #expect(layout.resultOffsets == [
            MemoryLayout<GPURayResult>.offset(of: \.radius)!, MemoryLayout<GPURayResult>.offset(of: \.u)!,
            MemoryLayout<GPURayResult>.offset(of: \.maxResidual)!, MemoryLayout<GPURayResult>.offset(of: \.steps)!,
        ])
        #expect(layout.parameterOffsets == [
            MemoryLayout<GPUKernelParameters>.offset(of: \.rayCount)!, MemoryLayout<GPUKernelParameters>.offset(of: \.maxCrossings)!,
        ])
    }

    @Test(.enabled(if: MetalKernelTests.hasGPU)) func derivativeMatchesTheCPU() throws {
        let tracer = MetalRayTracer(context: try #require(Self.context))
        let gpu = try tracer.evaluateDerivative(Self.samples.map { ($0.spin, $0.constants, $0.state) })
        for (sample, g) in zip(Self.samples, gpu) {
            let integrator = GeodesicIntegrator(kerr: Kerr(spin: sample.spin), constants: sample.constants, settings: .standard(skyRadius: 1000))
            let cpu = integrator.derivative(StateVector(sample.state))
            for i in 0..<5 {
                #expect(close(g[i], cpu[i]), "a=\(sample.spin) L=\(sample.constants.angularMomentum) component \(i): gpu \(g[i]) cpu \(cpu[i])")
            }
        }
    }

    @Test(.enabled(if: MetalKernelTests.hasGPU)) func dormandPrinceStepAndErrorMatchTheCPU() throws {
        let tracer = MetalRayTracer(context: try #require(Self.context))
        let h = 2e-3
        let gpu = try tracer.evaluateStep(Self.samples.map { ($0.spin, $0.constants, $0.state) }, stepSize: h)
        for (sample, g) in zip(Self.samples, gpu) {
            let integrator = GeodesicIntegrator(kerr: Kerr(spin: sample.spin), constants: sample.constants, settings: .standard(skyRadius: 1000))
            let y = StateVector(sample.state)
            let cpu = integrator.dormandPrince(y, h, integrator.derivative(y))
            for i in 0..<5 {
                #expect(close(g.y[i], cpu.y[i]), "a=\(sample.spin) state component \(i): gpu \(g.y[i]) cpu \(cpu.y[i])")
                // The embedded error estimate is tiny and float32 rounding noise dominates: compare on an absolute scale.
                #expect(abs(Double(g.err[i]) - cpu.err[i]) <= 1e-6, "a=\(sample.spin) error component \(i): gpu \(g.err[i]) cpu \(cpu.err[i])")
            }
        }
    }

    @Test(.enabled(if: MetalKernelTests.hasGPU)) func normalizedResidualMatchesTheCPU() throws {
        let tracer = MetalRayTracer(context: try #require(Self.context))
        // Perturb the velocity so the residual is not ~0: both implementations must agree on a non-trivial value.
        let perturbed = Self.samples.map { s -> (Double, PhotonConstants, RayState) in
            var st = s.state
            st.vu *= 1.001
            st.vmu *= 0.999
            return (s.spin, s.constants, st)
        }
        let gpu = try tracer.evaluateResidual(perturbed)
        for ((spin, constants, state), g) in zip(perturbed, gpu) {
            let integrator = GeodesicIntegrator(kerr: Kerr(spin: spin), constants: constants, settings: .standard(skyRadius: 1000))
            let cpu = integrator.residual(of: state)
            #expect(abs(Double(g) - cpu) <= 1e-4 * max(cpu, 1e-3), "a=\(spin): gpu \(g) cpu \(cpu)")
        }
    }
}
