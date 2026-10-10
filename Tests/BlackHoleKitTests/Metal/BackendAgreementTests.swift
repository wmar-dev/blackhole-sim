import Foundation
import simd
import Testing
@testable import BlackHoleKit

@Suite struct BackendAgreementTests {
    static let hasGPU = (try? MetalContext.make()) != nil

    @Test func identicalOutcomesMatchCompletely() {
        let outcomes: [RayOutcome] = [.captured, .disk(radius: 8, crossingIndex: 1, face: .upper), .sky(direction: SIMD3(0, 0, 1))]
        let a = BackendAgreement.compareRays(cpu: outcomes, gpu: outcomes)
        #expect(a.outcomeMatchFraction == 1 && a.radiusP99 == 0 && a.skyMaxAngle == 0 && a.skyWithinToleranceFraction == 1)
    }

    @Test func differencesAreMeasured() {
        let cpu: [RayOutcome] = [.captured, .disk(radius: 10, crossingIndex: 1, face: .upper), .sky(direction: SIMD3(0, 0, 1)), .captured]
        let gpu: [RayOutcome] = [.sky(direction: SIMD3(0, 0, 1)), .disk(radius: 10.01, crossingIndex: 1, face: .upper),
                                 .sky(direction: simd_normalize(SIMD3<Double>(1e-3, 0, 1))), .captured]
        let a = BackendAgreement.compareRays(cpu: cpu, gpu: gpu)
        #expect(a.outcomeMatchFraction == 0.75)
        #expect(abs(a.radiusMax - 1e-3) < 1e-9)
        #expect(a.skyWithinToleranceFraction == 0 && abs(a.skyMaxAngle - 1e-3) < 1e-6)
    }

    @Test func injectedDisagreementFailsAndNamesTheQuantity() {
        var rays = RayAgreement(); rays.radiusP99 = 5e-3
        let verdicts = BackendAgreement.verdicts(rays: rays, pixels: PixelAgreement(), shadowRadiusErrorGPU: nil,
                                                 gpuBadRayFraction: 0, gpuUnresolvedFraction: 0, speedup: 5, speedupChecked: true)
        let failed = verdicts.filter { !$0.passed }
        #expect(failed.map(\.quantity) == ["crossing radius p99"])
        let slow = BackendAgreement.verdicts(rays: RayAgreement(), pixels: PixelAgreement(), shadowRadiusErrorGPU: 0.05,
                                             gpuBadRayFraction: 0, gpuUnresolvedFraction: 0, speedup: 2, speedupChecked: true)
        #expect(Set(slow.filter { !$0.passed }.map(\.quantity)) == ["GPU shadow radius vs analytic", "speed-up"])
    }

    @Test func standardScenesAreFiveAndQuickIsSmaller() {
        let full = BackendAgreement.standardScenes(quick: false), quick = BackendAgreement.standardScenes(quick: true)
        #expect(full.count == 5 && quick.count == 5)
        #expect(full.allSatisfy { $0.config.width == 960 && $0.config.height == 540 && $0.config.samplesPerPixel == 4 })
        #expect(quick.allSatisfy { $0.config.width == 240 })
    }

    @Test(.enabled(if: BackendAgreementTests.hasGPU)) func aRealQuickRunPasses() throws {
        for scene in BackendAgreement.standardScenes(quick: true) {
            let result = try BackendAgreement.run(scene: scene, quick: true)
            #expect(result.passed, "\(scene.name): \(result.failures.map { "\($0.quantity)=\($0.value)" })")
        }
    }
}
