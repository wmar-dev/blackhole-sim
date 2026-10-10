import Foundation
import Testing
@testable import BlackHoleKit

/// Speed-up of the GPU backend on the default scene (SC-001). A wall-clock measurement, so it runs only with BHSIM_BENCH=1.
@Suite struct MetalSpeedTests {
    static let enabled = ProcessInfo.processInfo.environment["BHSIM_BENCH"] == "1" && (try? MetalContext.make()) != nil

    @Test(.enabled(if: MetalSpeedTests.enabled)) func gpuIsAtLeastThreeTimesFasterOnTheDefaultScene() throws {
        var config = RenderConfig()
        config.width = 1920; config.height = 1080; config.samplesPerPixel = 4
        let cpu = try Renderer(config: config).render().diagnostics.wallTimeSeconds
        config.backend = .metal
        let gpu = try Renderer(config: config).renderOnBackend().diagnostics.wallTimeSeconds
        print("default scene: CPU \(cpu) s, GPU \(gpu) s, speed-up \(cpu / gpu)")
        #expect(cpu / gpu >= 3, "speed-up \(cpu / gpu)")
    }
}
