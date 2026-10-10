import Foundation
import Testing
@testable import BlackHoleKit

/// The GPU's equatorial-plane crossing and disk logic against the CPU and the independent Binet orbit reference
/// (FR-004, spec User Story 1). Uses the orbits of `PlaneCrossingTests`. Skipped without a GPU.
@Suite struct MetalCrossingTests {
    static let context = try? MetalContext.make()
    static var hasGPU: Bool { context != nil }
    static let farAway = 1e5

    private func parameters(spin: Double = 0, inner: Double, outer: Double, maxCrossings: Int = 3) -> GPUKernelParameters {
        GPUKernelParameters(spin: spin, skyRadius: 1000, diskInner: inner, diskOuter: outer, maxCrossings: maxCrossings)
    }

    private func trace(_ ray: CameraRay, spin: Double = 0, inner: Double, outer: Double, maxCrossings: Int = 3) throws -> GPURayResult {
        let tracer = MetalRayTracer(context: try #require(Self.context))
        return try tracer.trace(inputs: [GPURayInput(ray)], parameters: parameters(spin: spin, inner: inner, outer: outer, maxCrossings: maxCrossings))[0]
    }

    @Test(.enabled(if: MetalCrossingTests.hasGPU), arguments: [60.0, 100.0], [1.0, -1.0])
    func aNarrowAnnulusAroundTheKthCrossingGivesADiskHitAtIndexK(inclinationDegrees: Double, polarSign: Double) throws {
        let i = inclinationDegrees * Double.pi / 180
        let orbit = PlaneCrossingTests.Orbit(b: PlaneCrossingTests.criticalB * (1 + 1e-3), inclination: i, mu0: 0.4 * sin(i), polarSign: polarSign)
        let ray = try #require(PlaneCrossingTests.makeRay(orbit))
        let cpu = PlaneCrossingTests.tracerFar.trace(ray).crossings  // float64 reference: radius, face, index
        #expect(cpu.count >= 2)
        let binet = PlaneCrossingTests.binetCrossingRadii(orbit, ray: ray, count: cpu.count)
        for (k, crossing) in cpu.enumerated() {
            let others = cpu.enumerated().filter { $0.offset != k }.map { abs($0.element.radius - crossing.radius) }
            let half = 0.3 * min(others.min() ?? 1, crossing.radius)
            let result = try trace(ray, inner: crossing.radius - half, outer: crossing.radius + half)
            let outcome = result.outcome(constants: ray.constants, kerr: Kerr(spin: 0))
            guard case .disk(let radius, let index, let face) = outcome else {
                Issue.record("expected a disk hit at crossing \(k + 1), got \(outcome)")
                continue
            }
            #expect(index == k + 1, "crossing index")
            #expect(face == crossing.face, "face of crossing \(k + 1)")
            #expect(approxEqual(radius, crossing.radius, relative: 1e-3), "GPU radius \(radius) vs CPU \(crossing.radius) at crossing \(k + 1)")
            #expect(approxEqual(radius, binet[k].radius, relative: 1e-3), "GPU radius \(radius) vs Binet \(binet[k].radius) at crossing \(k + 1)")
            #expect(!result.isDelicate)
        }
    }

    @Test(.enabled(if: MetalCrossingTests.hasGPU)) func rayOutsideTheAnnulusContinuesAndEndsOnTheSkyOrHorizon() throws {
        let orbit = PlaneCrossingTests.winding
        let ray = try #require(PlaneCrossingTests.makeRay(orbit))
        let result = try trace(ray, inner: Self.farAway, outer: Self.farAway + 1)
        let outcome = result.outcome(constants: ray.constants, kerr: Kerr(spin: 0))
        if case .disk = outcome { Issue.record("no disk hit expected") }
        #expect(result.outcome == 3 || result.outcome == 1)
    }

    @Test(.enabled(if: MetalCrossingTests.hasGPU)) func disablingTheDiskGivesNoDiskOutcomesAndAWideAnnulusStopsAtTheFirstCrossing() throws {
        let tracer = MetalRayTracer(context: try #require(Self.context))
        // A spread of rays from the default camera.
        var config = RenderConfig()
        config.width = 48; config.height = 27
        let camera = Camera(kerr: config.kerr, observer: config.observer, width: config.width, height: config.height)
        var rays: [CameraRay] = []
        for y in 0..<config.height { for x in 0..<config.width { rays.append(camera.ray(pixelX: Double(x) + 0.5, pixelY: Double(y) + 0.5)) } }
        let inputs = rays.map(GPURayInput.init)

        let none = try tracer.trace(inputs: inputs, parameters: parameters(inner: 1, outer: 1e4, maxCrossings: 0))
        #expect(none.allSatisfy { $0.outcome != 2 }, "disk disabled: no disk outcomes")

        let wide = try tracer.trace(inputs: inputs, parameters: parameters(inner: 1.5, outer: 1e4))
        let hits = wide.filter { $0.outcome == 2 }
        #expect(hits.count > 100)
        #expect(hits.allSatisfy { $0.crossingIndex == 1 }, "an annulus covering the whole plane stops every ray at its first crossing")
        #expect(wide.allSatisfy { $0.crossingIndex <= 3 }, "the crossing cap is 3")
    }

    @Test(.enabled(if: MetalCrossingTests.hasGPU), arguments: [0.0, 0.9])
    func equatorialRaysNeverCross(spin: Double) throws {
        let kerr = Kerr(spin: spin)
        let constants = PhotonConstants(energy: 1, angularMomentum: 6, carter: 0)
        let integrator = GeodesicIntegrator(kerr: kerr, constants: constants, settings: .standard(skyRadius: 1000))
        let state = try #require(integrator.initialState(r: 50, mu: 0, radialSign: -1, polarSign: 1))
        let ray = CameraRay(constants: constants, state: state, observerEnergy: 1)
        let result = try trace(ray, spin: spin, inner: kerr.iscoRadius, outer: 1e4)
        #expect(result.outcome == 3, "an equatorial ray escapes without touching the disk plane crossing logic (got \(result.outcome))")
    }

    @Test(.enabled(if: MetalCrossingTests.hasGPU)) func anObserverInThePlaneIsNotACrossingAtStart() throws {
        let orbit = PlaneCrossingTests.Orbit(b: PlaneCrossingTests.criticalB * (1 + 1e-3), inclination: 60 * Double.pi / 180, mu0: 0, polarSign: 1)
        let ray = try #require(PlaneCrossingTests.makeRay(orbit))
        let cpu = PlaneCrossingTests.tracerFar.trace(ray).crossings
        #expect(cpu.count >= 2)
        let first = cpu[0]
        let result = try trace(ray, inner: first.radius - 0.2, outer: first.radius + 0.2)
        guard case .disk(let radius, let index, _) = result.outcome(constants: ray.constants, kerr: Kerr(spin: 0)) else {
            Issue.record("expected a hit at the first crossing"); return
        }
        #expect(index == 1)
        #expect(approxEqual(radius, first.radius, relative: 1e-3))
    }

    @Test(.enabled(if: MetalCrossingTests.hasGPU)) func aPlungingRayIsCaptured() throws {
        let constants = PhotonConstants(energy: 1, angularMomentum: 1, carter: 1)
        let integrator = GeodesicIntegrator(kerr: Kerr(spin: 0), constants: constants, settings: .standard(skyRadius: 1000))
        let state = try #require(integrator.initialState(r: 50, mu: 0.2, radialSign: -1, polarSign: 1))
        let result = try trace(CameraRay(constants: constants, state: state, observerEnergy: 1), inner: Self.farAway, outer: Self.farAway + 1)
        #expect(result.outcome == 1)
    }

    @Test(.enabled(if: MetalCrossingTests.hasGPU)) func theFaceIsTheSideTheRayCameFrom() throws {
        let above = try #require(PlaneCrossingTests.makeRay(PlaneCrossingTests.Orbit(b: PlaneCrossingTests.criticalB * (1 + 1e-3), inclination: 1.0, mu0: 0.3, polarSign: 1)))
        let first = PlaneCrossingTests.tracerFar.trace(above).crossings[0]
        let up = try trace(above, inner: first.radius - 0.2, outer: first.radius + 0.2)
        #expect(up.outcome == 2 && up.face & 1 == 0)
        let below = try #require(PlaneCrossingTests.makeRay(PlaneCrossingTests.Orbit(b: PlaneCrossingTests.criticalB * (1 + 1e-3), inclination: 1.0, mu0: -0.3, polarSign: -1)))
        let firstBelow = PlaneCrossingTests.tracerFar.trace(below).crossings[0]
        let down = try trace(below, inner: firstBelow.radius - 0.2, outer: firstBelow.radius + 0.2)
        #expect(down.outcome == 2 && down.face & 1 == 1)
    }
}
