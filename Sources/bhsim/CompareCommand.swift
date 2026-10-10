import ArgumentParser
import BlackHoleKit
import Foundation

struct Compare: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render a standard set of scenes with the CPU and GPU backends and report their agreement.",
        discussion: "Exit code 0 only if every scene is within tolerance, 1 otherwise (the failing scene and quantity are named), 5 if the GPU is unavailable."
    )

    @Flag(help: "Use smaller images for a fast smoke test.")
    var quick = false

    func run() throws {
        var scenes: [SceneAgreement] = []
        for scene in BackendAgreement.standardScenes(quick: quick) {
            do {
                FileHandle.standardError.write(Data("comparing \(scene.name)...\n".utf8))
                scenes.append(try BackendAgreement.run(scene: scene, quick: quick))
            } catch let error as BackendError {
                guard case .unavailable(let reason) = error else { throw error }
                FileHandle.standardError.write(Data("error: --backend: \(reason)\n".utf8))
                throw ExitCode(5)
            }
        }
        let report = AgreementReport(scenes: scenes)
        func pad(_ s: String, _ n: Int) -> String { s.padding(toLength: n, withPad: " ", startingAt: 0) }
        func pct(_ x: Double) -> String { String(format: "%.4f%%", 100 * x) }
        func sci(_ x: Double) -> String { String(format: "%.1e", x) }
        print(pad("scene", 22) + pad("match", 10) + pad("radius p99", 12) + pad("sky ≤1e-4", 11) + pad("sky max", 10) + pad("radiance p99 / max", 22)
              + pad("shadow Δ", 10) + pad("shadow err C/G", 17) + pad("GPU res p99.9", 14) + pad("GPU bad", 9) + pad("refined", 9)
              + pad("CPU s", 8) + pad("GPU s", 8) + pad("speed-up", 9) + "result")
        for s in report.scenes {
            let shadow = s.shadowRadiusErrorGPU.map { "\(pct(s.shadowRadiusErrorCPU ?? 0))/\(pct($0))" } ?? "-"
            print(pad(s.scene, 22) + pad(pct(s.rays.outcomeMatchFraction), 10) + pad(sci(s.rays.radiusP99), 12)
                  + pad(pct(s.rays.skyWithinToleranceFraction), 11) + pad(sci(s.rays.skyMaxAngle), 10)
                  + pad("\(pct(s.pixels.radianceP99)) / \(pct(s.pixels.radianceMax))", 22)
                  + pad(pct(s.pixels.shadowAreaDifference), 10) + pad(shadow, 17) + pad(sci(s.gpuP999Residual), 14)
                  + pad(sci(s.gpuBadRayFraction), 9) + pad(pct(s.refinedFraction), 9)
                  + pad(String(format: "%.2f", s.cpuSeconds), 8) + pad(String(format: "%.2f", s.gpuSeconds), 8)
                  + pad(String(format: "%.1f×", s.speedup), 9) + (s.passed ? "PASS" : "FAIL"))
            for f in s.failures {
                print("  FAIL \(s.scene): \(f.quantity) = \(f.value) (limit \(f.limit))")
            }
        }
        print("\n" + (report.passed ? "PASS: all \(report.scenes.count) scenes within tolerance" : "FAIL: \(report.scenes.filter { !$0.passed }.count) of \(report.scenes.count) scenes outside tolerance"))
        if !report.passed { throw ExitCode(1) }
    }
}
