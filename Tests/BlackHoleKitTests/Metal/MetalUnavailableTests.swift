import Foundation
import Testing
@testable import BlackHoleKit

/// The "no usable GPU" path (FR-008, SC-008). `BHSIM_FORCE_NO_GPU=1` and the `forceUnavailable` parameter simulate a
/// missing GPU, so the path is tested on machines that have one. There is never a silent fallback to the CPU.
@Suite struct MetalUnavailableTests {
    @Test func contextCreationFailsWithAClearReason() {
        do {
            _ = try MetalContext.make(forceUnavailable: true)
            Issue.record("expected the context creation to fail")
        } catch let error as BackendError {
            guard case .unavailable(let reason) = error else { Issue.record("wrong error \(error)"); return }
            #expect(reason.localizedCaseInsensitiveContains("GPU"), "reason should name the GPU: \(reason)")
        } catch {
            Issue.record("unexpected error type \(error)")
        }
    }

    @Test func aMetalRendererCannotBeCreatedWithoutAGPUAndDoesNotFallBack() {
        var config = RenderConfig()
        config.backend = .metal
        config.width = 8
        config.height = 4
        #expect(throws: BackendError.self) { try Renderer(config: config, forceGPUUnavailable: true) }
    }

    @Test func invalidInputIsReportedBeforeTheBackendIsChecked() {
        var config = RenderConfig()
        config.backend = .metal
        config.blackHole.spin = 1.2
        do {
            _ = try Renderer(config: config, forceGPUUnavailable: true)
            Issue.record("expected an error")
        } catch is ConfigError {
            // expected: input validation first
        } catch {
            Issue.record("expected a ConfigError, got \(error)")
        }
    }

    @Test(.enabled(if: CLIRunner.bhsim != nil)) func cliExitsWithFiveWritesNothingAndIsFast() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("bhsim-nogpu-\(UUID().uuidString)/img").path
        defer { try? FileManager.default.removeItem(atPath: (base as NSString).deletingLastPathComponent) }
        let r = try CLIRunner.run(["render", "--backend", "metal", "--width", "16", "--height", "9", "--out", base],
                                  environment: ["BHSIM_FORCE_NO_GPU": "1"])
        #expect(r.status == 5, "exit \(r.status), stderr: \(r.stderr)")
        #expect(r.stderr.contains("error: --backend:"), "stderr: \(r.stderr)")
        #expect(r.seconds < 2, "took \(r.seconds) s")
        for ext in ["png", "exr", "json"] { #expect(!FileManager.default.fileExists(atPath: "\(base).\(ext)"), "no .\(ext) may be written") }
    }

    @Test(.enabled(if: CLIRunner.bhsim != nil)) func cpuBackendIsUnaffectedByTheMissingGPU() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("bhsim-nogpu-cpu-\(UUID().uuidString)/img").path
        defer { try? FileManager.default.removeItem(atPath: (base as NSString).deletingLastPathComponent) }
        let r = try CLIRunner.run(["render", "--backend", "cpu", "--width", "16", "--height", "9", "--samples", "1", "--sky", "grid", "--out", base],
                                  environment: ["BHSIM_FORCE_NO_GPU": "1"])
        #expect(r.status == 0, "exit \(r.status), stderr: \(r.stderr)")
        #expect(FileManager.default.fileExists(atPath: "\(base).png"))
    }

    @Test(.enabled(if: CLIRunner.bhsim != nil)) func cliInvalidInputStillExitsTwoWithoutAGPU() throws {
        let r = try CLIRunner.run(["render", "--spin", "1.2", "--backend", "metal", "--out", "/nonexistent-should-not-be-written/x"],
                                  environment: ["BHSIM_FORCE_NO_GPU": "1"])
        #expect(r.status == 2, "exit \(r.status), stderr: \(r.stderr)")
        #expect(r.stderr.contains("--spin"))
    }
}
