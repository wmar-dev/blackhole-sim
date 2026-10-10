import Foundation
import Testing
@testable import BlackHoleKit

/// Remaining spec edge cases (Edge Cases section of spec.md) and the command-line contract.
@Suite struct EdgeCaseTests {
    static func smallConfig() -> RenderConfig {
        var c = RenderConfig()
        c.width = 16
        c.height = 9
        c.samplesPerPixel = 4
        c.sky = SkyConfig(kind: .grid, seed: 1, starCount: 0)
        return c
    }

    @Test func unresolvedRaysAreCountedExcludedAndNeverSilentlyColoured() throws {
        let config = Self.smallConfig()
        var settings = IntegratorSettings.standard(skyRadius: config.skyRadius)
        settings.stepBudget = 3  // far too small: every ray runs out of steps
        let image = try Renderer(config: config, integratorSettings: settings).render()
        let total = config.width * config.height * config.samplesPerPixel
        #expect(image.diagnostics.raysTotal == total)
        #expect(image.diagnostics.unresolved == total)
        #expect(image.unresolvedFraction.allSatisfy { $0 == 1 })
        #expect(image.hdr.allSatisfy { $0 == .zero }, "a pixel with no resolved samples must be black, not sky-coloured")
        #expect(image.diagnostics.badRayFraction == 1)
        #expect(image.diagnostics.badRayFraction > NumericalDefaults.allowedBadRayFraction)  // would give exit code 4
    }

    @Test func partiallyUnresolvedPixelsAverageOnlyTheirResolvedSamples() throws {
        let config = Self.smallConfig()
        var settings = IntegratorSettings.standard(skyRadius: config.skyRadius)
        settings.stepBudget = 60  // some rays finish in fewer steps, others do not
        let image = try Renderer(config: config, integratorSettings: settings).render()
        let unresolvedSamples = image.unresolvedFraction.reduce(0.0) { $0 + Double($1) } * Double(config.samplesPerPixel)
        #expect(Int(unresolvedSamples.rounded()) == image.diagnostics.unresolved)
        #expect(image.diagnostics.unresolved > 0 && image.diagnostics.unresolved < image.diagnostics.raysTotal)
        #expect(image.hdr.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.x >= 0 })
        // A pixel with some unresolved samples keeps the colour of the resolved ones (not diluted toward black).
        let mixed = image.unresolvedFraction.indices.filter { image.unresolvedFraction[$0] > 0 && image.unresolvedFraction[$0] < 1 }
        for i in mixed where image.capturedFraction[i] == 0 {
            #expect(image.hdr[i].x > 0.015, "pixel \(i) was diluted by its unresolved samples")
        }
    }

    @Test func observersAtOrInsideTheHorizonAreRejected() {
        for distance in [0.5, 1.0, 1.9, 2.0] {
            var c = Self.smallConfig()
            c.observer.distance = distance
            #expect(throws: ConfigError.self, "r=\(distance)") { try Renderer(config: c) }
        }
    }

    @Test func progressIsReportedInIncreasingOrderUpToOne() throws {
        final class Log: @unchecked Sendable {
            let lock = NSLock(); var values: [Double] = []
            func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() }
        }
        let log = Log()
        _ = try Renderer(config: Self.smallConfig()).render(progress: { log.add($0) })
        #expect(!log.values.isEmpty)
        #expect(log.values == log.values.sorted())
        #expect(log.values.last == 1.0)
    }

    @Test func stronglyLensedConfigurationsStayFinite() throws {
        var c = Self.smallConfig()
        c.blackHole.spin = 0.998
        c.observer.distance = 5
        c.observer.inclinationDegrees = 60
        c.observer.fieldOfViewDegrees = 120
        c.disk.outerRadius = 4
        let image = try Renderer(config: c).render()
        #expect(image.hdr.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        #expect(image.diagnostics.raysTotal == c.width * c.height * c.samplesPerPixel)
    }

    // MARK: Command line

    /// The built `bhsim` next to the test products, if it exists.
    static var bhsim: URL? {
        // The resource bundle may sit inside the .xctest bundle or beside it; walk up until `bhsim` is found.
        var directory = Bundle.module.bundleURL
        for _ in 0..<6 {
            directory = directory.deletingLastPathComponent()
            let candidate = directory.appendingPathComponent("bhsim")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func run(_ arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let url = try #require(Self.bhsim, "bhsim was not built next to the tests")
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus,
                String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    @Test(.enabled(if: EdgeCaseTests.bhsim != nil)) func cliRendersAndWritesAllOutputs() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("bhsim-cli-\(UUID().uuidString)/img").path
        defer { try? FileManager.default.removeItem(atPath: (base as NSString).deletingLastPathComponent) }
        let r = try run(["render", "--width", "32", "--height", "18", "--samples", "1", "--sky", "grid", "--out", base])
        #expect(r.status == 0, "stderr: \(r.stderr)")
        for ext in ["png", "exr", "json"] { #expect(FileManager.default.fileExists(atPath: "\(base).\(ext)"), "missing .\(ext)") }
        #expect(r.stdout.contains("Progress"))
    }

    @Test(.enabled(if: EdgeCaseTests.bhsim != nil)) func cliRejectsInvalidInputWithExitCodeTwoAndAClearMessage() throws {
        let cases: [(args: [String], mention: String)] = [
            (["--spin", "1.2"], "--spin"),
            (["--spin", "-0.5"], "--spin"),
            (["--spin=-0.5"], "--spin"),
            (["--bogus", "1"], "Unknown option"),
            (["--width", "abc"], "--width"),
            (["--samples", "3"], "--samples"),
            (["--distance", "1.5"], "--distance"),
            (["--inclination", "0"], "--inclination"),
            (["--disk-outer", "3"], "--disk-outer"),
            (["--width", "0"], "--width"),
        ]
        for c in cases {
            let r = try run(["render", "--width", "16", "--height", "9", "--out", "/nonexistent-should-not-be-written/x"] + c.args)
            #expect(r.status == 2, "\(c.args): exit \(r.status), stderr: \(r.stderr)")
            #expect(r.stderr.contains(c.mention), "\(c.args): \(r.stderr)")
        }
    }

    @Test(.enabled(if: EdgeCaseTests.bhsim != nil)) func cliFailsWithExitCodeThreeWhenOutputCannotBeWritten() throws {
        let r = try run(["render", "--width", "8", "--height", "4", "--samples", "1", "--sky", "grid", "--out", "/proc/definitely/not/writable/x"])
        #expect(r.status == 3, "exit \(r.status), stderr: \(r.stderr)")
    }

    @Test(.enabled(if: EdgeCaseTests.bhsim != nil)) func cliExitsWithFourWhenTooManyRaysAreUnresolvedButStillWritesTheImages() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("bhsim-cli4-\(UUID().uuidString)/img").path
        defer { try? FileManager.default.removeItem(atPath: (base as NSString).deletingLastPathComponent) }
        let r = try run(["render", "--width", "16", "--height", "9", "--samples", "1", "--sky", "grid", "--max-steps", "5", "--out", base])
        #expect(r.status == 4, "exit \(r.status), stderr: \(r.stderr)")
        #expect(r.stderr.contains("unresolved"))
        for ext in ["png", "exr", "json"] { #expect(FileManager.default.fileExists(atPath: "\(base).\(ext)"), "images must still be written (.\(ext))") }
        #expect(try run(["render", "--max-steps", "0"]).status == 2)
    }

    @Test(.enabled(if: EdgeCaseTests.bhsim != nil)) func cliValidatePrintsATableAndExitsZero() throws {
        let r = try run(["validate"])
        #expect(r.status == 0, "stdout: \(r.stdout)\nstderr: \(r.stderr)")
        #expect(r.stdout.contains("PASS") && !r.stdout.contains("FAIL"))
        #expect(r.stdout.contains("checks passed"))
    }
}
