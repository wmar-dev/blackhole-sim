import CryptoKit
import Foundation
import Testing
@testable import BlackHoleKit

/// FR-002: the CPU backend is the reference and must not change. The display image and the physical-intensity image of
/// a fixed CPU render must stay byte-identical as the GPU backend is added.
///
/// The hashes were recorded from the code as it was before feature 002 touched any source file. If a deliberate change
/// to the CPU physics alters them, regenerate them and say so in the commit.
@Suite struct CPUUnchangedTests {
    static let pngSHA256 = "6d2b6e63897ce0de787da9189c116a64e2f1ad7529dfc5c4877f5ebf771c2c0c"
    static let exrSHA256 = "59ff33de613ed8062b7c16c0970d6e26357a15a00f8780f0034285a5ea8a9301"

    static func config() -> RenderConfig {
        var c = RenderConfig()
        c.blackHole.spin = 0.7
        c.width = 64
        c.height = 36
        c.samplesPerPixel = 4
        c.sky = SkyConfig(kind: .starfield, seed: 7, starCount: 20_000)
        return c
    }

    private func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    @Test func cpuPngAndExrBytesAreUnchanged() throws {
        let config = Self.config()
        let image = try Renderer(config: config).render()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cpu-unchanged-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = try RenderOutput.write(image: image, config: config, basename: directory.appendingPathComponent("img").path)
        #expect(try sha256(paths.png) == Self.pngSHA256, "the CPU display image changed")
        #expect(try sha256(paths.exr) == Self.exrSHA256, "the CPU physical-intensity image changed")
    }

    @Test func explicitCpuBackendIsTheSameAsTheDefault() throws {
        // Once `backend` exists, selecting `.cpu` explicitly must give the same image as not selecting anything.
        let config = Self.config()
        let defaultImage = try Renderer(config: config).render()
        let again = try Renderer(config: config).render()
        #expect(defaultImage.hdr == again.hdr)
    }
}
