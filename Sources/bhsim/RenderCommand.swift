import ArgumentParser
import BlackHoleKit
import Foundation

struct Render: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render an image of a black hole.",
        discussion: """
            With no options, renders the default scene: a non-spinning black hole seen from 100 M at \
            80° inclination, with a thin Novikov–Thorne disk and a seeded star field.

            Writes <out>.png (tone-mapped), <out>.exr (physical intensities, 32-bit float) and \
            <out>.json (all inputs, units, diagnostics).

            Exit codes: 0 success; 2 invalid input (including unknown options and unparsable values); 3 output could not be written; 4 render completed but \
            more than 0.1% of rays were unresolved or exceeded the residual bound; 5 the requested backend is unavailable.
            """
    )

    @OptionGroup var options: RenderOptions
    @Option(parsing: .unconditional, help: "Samples per pixel (a perfect square).") var samples: Int = 4
    @Option(name: .customLong("reference-radiance"), parsing: .unconditional,
            help: "Radiance (Y-weighted W m^-2 sr^-1) that maps to 1.0 in the output; default: the hottest unshifted disk emission.")
    var referenceRadiance: Double?
    @Option(help: "Output basename, without extension.") var out: String = "blackhole"

    func run() throws {
        var config = options.config(samples: samples)
        config.referenceRadianceOverride = referenceRadiance

        let renderer: Renderer
        do {
            renderer = try Renderer(config: config)
        } catch let error as ConfigError {
            fail(error.errorDescription ?? "invalid input")
            throw ExitCode(2)
        } catch let error as BackendError {
            fail("--backend: \(error.errorDescription ?? "the requested backend is unavailable")")
            throw ExitCode(5)
        }

        print("Rendering \(config.width)x\(config.height) at \(samples) samples/pixel (spin \(options.spin), i = \(options.inclination)°, r = \(options.distance) M)")
        let reporter = ProgressReporter()
        let image = try renderer.renderOnBackend(progress: { reporter.update($0) })
        print("")

        let paths: RenderOutput.Paths
        do {
            paths = try RenderOutput.write(image: image, config: config, basename: out)
        } catch {
            fail("\(error.localizedDescription)")
            throw ExitCode(3)
        }

        let d = image.diagnostics
        print("Wrote \(paths.png.path), \(paths.exr.path), \(paths.json.path)")
        print("Rays: \(d.raysTotal) total, \(d.captured) captured, \(d.disk) disk, \(d.sky) sky, \(d.unresolved) unresolved")
        print(String(format: "Residual: max %.2e, 99.9th percentile %.2e; %.1f s", d.maxResidual, d.p999Residual, d.wallTimeSeconds))
        if d.badRayFraction > NumericalDefaults.allowedBadRayFraction {
            fail(String(format: "%.3f%% of rays were unresolved or exceeded the residual bound (limit %.1f%%); images were still written",
                        100 * d.badRayFraction, 100 * NumericalDefaults.allowedBadRayFraction))
            throw ExitCode(4)
        }
    }
}

private func fail(_ message: String) {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
}

/// Prints progress at most once per whole percent. Updates arrive from several threads.
private final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPercent = -1

    func update(_ fraction: Double) {
        let percent = Int(fraction * 100)
        lock.lock()
        defer { lock.unlock() }
        guard percent > lastPercent, percent % 5 == 0 || percent == 100 else { return }
        lastPercent = percent
        print("\rProgress: \(percent)%", terminator: "")
        fflush(stdout)
    }
}
