import Foundation
import Testing
@testable import BlackHoleKit

@Suite struct ReferenceOverrideTests {
    private func config() -> RenderConfig {
        var c = RenderConfig()
        c.width = 48; c.height = 27; c.samplesPerPixel = 1; c.blackHole.spin = 0.6
        return c
    }

    @Test func noOverrideLeavesTheImageAndReferenceUnchanged() throws {
        let c = config()
        #expect(c.referenceRadianceOverride == nil)
        let plain = try Renderer(config: c)
        var own = c
        own.referenceRadianceOverride = plain.referenceRadiance
        let a = plain.render(), b = try Renderer(config: own).render()
        #expect(a.hdr == b.hdr, "overriding with the renderer's own reference changes nothing")
        #expect(a.referenceRadiance == b.referenceRadiance)
    }

    @Test func anOverrideRescalesTheDiskExactlyAndLeavesTheSkyAlone() throws {
        // Disk radiance is divided by the reference; the sky is defined directly in reference units (a fixed backdrop).
        var c = config()
        c.observer.inclinationDegrees = 80
        let plain = try Renderer(config: c)
        var doubled = c
        doubled.referenceRadianceOverride = 2 * plain.referenceRadiance
        let a = plain.render(), b = try Renderer(config: doubled).render()
        #expect(b.referenceRadiance == 2 * plain.referenceRadiance)
        var disk = 0, sky = 0, captured = 0
        for i in a.hdr.indices {
            if a.diskFraction[i] == 1 { disk += 1; #expect(b.hdr[i] == a.hdr[i] * 0.5, "disk pixel \(i)") }
            else if a.capturedFraction[i] == 1 { captured += 1; #expect(b.hdr[i] == .zero && a.hdr[i] == .zero) }
            else if a.diskFraction[i] == 0 && a.capturedFraction[i] == 0 { sky += 1; #expect(b.hdr[i] == a.hdr[i], "sky pixel \(i)") }
        }
        #expect(disk > 20 && sky > 100 && captured > 5, "the test scene has disk (\(disk)), sky (\(sky)) and shadow (\(captured)) pixels")
    }

    @Test func theOverrideIsRecordedInTheMetadata() throws {
        var c = config()
        c.referenceRadianceOverride = 1.5e12
        let image = try Renderer(config: c).render()
        let metadata = RenderMetadata(config: c, shading: image.shading, referenceRadiance: image.referenceRadiance, diagnostics: image.diagnostics)
        #expect(metadata.hdr.referenceRadiance == 1.5e12)
    }

    @Test(arguments: [0.0, -1.0, Double.nan, Double.infinity])
    func invalidOverridesAreRejectedNamingTheOption(value: Double) {
        var c = config()
        c.referenceRadianceOverride = value
        do { try c.validate(); Issue.record("expected an error") } catch let error as ConfigError {
            #expect(error.option == "--reference-radiance", "\(error)")
        } catch { Issue.record("wrong error \(error)") }
        #expect(throws: ConfigError.self) { _ = try Renderer(config: c) }
    }

    @Test func theCommandLineAcceptsAndRecordsTheOption() throws {
        let dir = try TempDirectory()
        let out = dir.file("r").path
        let run = try CLIRunner.run(["render", "--width", "32", "--height", "18", "--samples", "1", "--reference-radiance", "1e12", "--out", out])
        #expect(run.status == 0, "\(run.stderr)")
        let json = try String(contentsOf: URL(fileURLWithPath: out + ".json"), encoding: .utf8)
        #expect(json.contains("\"referenceRadiance\" : 1000000000000"), "\(json.prefix(900))")
        let bad = try CLIRunner.run(["render", "--width", "32", "--height", "18", "--reference-radiance", "0", "--out", dir.file("bad").path])
        #expect(bad.status == 2 && bad.stderr.contains("--reference-radiance"), "\(bad.stderr)")
        #expect(!FileManager.default.fileExists(atPath: dir.file("bad.png").path))
    }
}
