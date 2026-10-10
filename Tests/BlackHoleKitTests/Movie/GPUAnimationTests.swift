import Foundation
import Testing
@testable import BlackHoleKit

@Suite(.serialized, .enabled(if: (try? MetalContext.make()) != nil)) struct GPUAnimationTests {
    private func animation(_ backend: Backend) -> Animation {
        var base = RenderConfig()
        base.width = 96; base.height = 54; base.samplesPerPixel = 4; base.backend = backend
        return Animation(parameter: .inclination, from: 85, to: 55, duration: 0.5, fps: 8, base: base)  // 4 frames
    }

    @Test func gpuFramesAgreeWithCPUFramesAndRecordTheBackend() throws {
        let dir = try TempDirectory()
        MetalContext.resetSharedForTesting()
        let gpu = try AnimationRunner.run(animation(.metal), options: AnimationRunner.Options(framesFolder: dir.file("gpu")))
        let cpu = try AnimationRunner.run(animation(.cpu), options: AnimationRunner.Options(framesFolder: dir.file("cpu")))
        #expect(gpu.rendered == 4 && cpu.rendered == 4)
        #expect(MetalContext.sharedCreationCount == 1, "the kernel is compiled once for the whole animation")
        for i in 1...4 {
            let name = String(format: "frame_%04d", i)
            let record = try JSONDecoder().decode(FrameRecord.self, from: Data(contentsOf: dir.file("gpu/\(name).json")))
            #expect(record.metadata.backend.name == "metal" && record.metadata.backend.precision == "float32")
            let a = try MovieTestSupport.decodePNG(dir.file("gpu/\(name).png")), b = try MovieTestSupport.decodePNG(dir.file("cpu/\(name).png"))
            let psnr = MovieTestSupport.psnr(a.rgb, b.rgb)
            #expect(psnr >= 45, "frame \(i): GPU vs CPU \(psnr) dB")
        }
        #expect(gpu.diagnostics.badRayFraction < NumericalDefaults.allowedBadRayFraction)
    }
}
