import ArgumentParser
import BlackHoleKit
import Foundation

enum SkyChoice: String, ExpressibleByArgument, CaseIterable {
    case starfield, grid
}

enum BackendChoice: String, ExpressibleByArgument, CaseIterable {
    case cpu, metal
}

struct Render: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render an image of a black hole.",
        discussion: """
            With no options, renders the default scene: a non-spinning black hole seen from 100 M at \
            80° inclination, with a thin Novikov–Thorne disk and a seeded star field.

            Writes <out>.png (tone-mapped), <out>.exr (physical intensities, 32-bit float) and \
            <out>.json (all inputs, units, diagnostics).

            Exit codes: 0 success; 2 invalid input (including unknown options and unparsable values); 3 output could not be written; 4 render completed but \
            more than 0.1% of rays were unresolved or exceeded the residual bound.
            """
    )

    @Option(parsing: .unconditional, help: "Dimensionless spin a/M, 0 <= a < 1.") var spin: Double = 0
    @Option(parsing: .unconditional, help: "Observer radius in M.") var distance: Double = 100
    @Option(parsing: .unconditional, help: "Observer angle from the spin axis in degrees, 0 < i < 180.") var inclination: Double = 80
    @Option(parsing: .unconditional, help: "Horizontal field of view in degrees.") var fov: Double = 30
    @Option(parsing: .unconditional, help: "Image width in pixels.") var width: Int = 1920
    @Option(parsing: .unconditional, help: "Image height in pixels.") var height: Int = 1080
    @Option(parsing: .unconditional, help: "Samples per pixel (a perfect square).") var samples: Int = 4
    @Option(name: .customLong("disk-outer"), parsing: .unconditional, help: "Outer disk radius in M.") var diskOuter: Double = 20
    @Option(name: .customLong("accretion-rate"), parsing: .unconditional, help: "Disk luminosity as a fraction of the Eddington luminosity.")
    var accretionRate: Double = 0.1
    @Option(parsing: .unconditional, help: "Black hole mass in solar masses (sets the physical scale only).") var mass: Double = 10
    @Option(help: "Background: starfield or grid.") var sky: SkyChoice = .starfield
    @Option(parsing: .unconditional, help: "Seed for the sky and the sample jitter.") var seed: UInt64 = 1
    @Option(parsing: .unconditional, help: "Display exposure offset in stops (PNG only).") var exposure: Double = 0
    @Option(help: "Output basename, without extension.") var out: String = "blackhole"
    @Flag(name: .customLong("no-disk"), help: "Omit the accretion disk: render a bare black hole and sky.") var noDisk = false
    @Option(name: .customLong("max-steps"), parsing: .unconditional,
            help: "Integrator step budget per ray; rays needing more are reported as unresolved.")
    var maxSteps: Int = NumericalDefaults.stepBudget
    @Option(help: "Compute backend: cpu (float64 reference). metal is not available yet.") var backend: BackendChoice = .cpu

    func run() throws {
        var config = RenderConfig()
        config.blackHole = BlackHole(spin: spin, massSolar: mass)
        config.observer = Observer(distance: distance, inclinationDegrees: inclination, fieldOfViewDegrees: fov)
        config.disk = AccretionDisk(outerRadius: diskOuter, accretionRateEddington: accretionRate)
        config.sky = SkyConfig(kind: sky == .grid ? .grid : .starfield, seed: seed)
        config.diskEnabled = !noDisk
        config.width = width
        config.height = height
        config.samplesPerPixel = samples
        config.exposureStops = exposure
        config.maxStepsPerRay = maxSteps

        guard backend == .cpu else {
            fail("--backend: the metal backend is not available; use cpu")
            throw ExitCode(2)
        }
        let renderer: Renderer
        do {
            renderer = try Renderer(config: config)
        } catch let error as ConfigError {
            fail(error.errorDescription ?? "invalid input")
            throw ExitCode(2)
        }

        print("Rendering \(width)x\(height) at \(samples) samples/pixel (spin \(spin), i = \(inclination)°, r = \(distance) M)")
        let reporter = ProgressReporter()
        let image = renderer.render(progress: { reporter.update($0) })
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
