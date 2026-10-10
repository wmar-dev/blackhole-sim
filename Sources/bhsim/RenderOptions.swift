import ArgumentParser
import BlackHoleKit
import Foundation

enum SkyChoice: String, ExpressibleByArgument, CaseIterable {
    case starfield, grid
}

enum BackendChoice: String, ExpressibleByArgument, CaseIterable {
    case cpu, metal
}

/// The options that describe a scene and how it is traced; shared by `render` and `movie animate` so both accept exactly
/// the same settings. (`--samples` and the output options differ and stay with their commands.)
struct RenderOptions: ParsableArguments {
    @Option(parsing: .unconditional, help: "Dimensionless spin a/M, 0 <= a < 1.") var spin: Double = 0
    @Option(parsing: .unconditional, help: "Observer radius in M.") var distance: Double = 100
    @Option(parsing: .unconditional, help: "Observer angle from the spin axis in degrees, 0 < i < 180.") var inclination: Double = 80
    @Option(parsing: .unconditional, help: "Horizontal field of view in degrees.") var fov: Double = 30
    @Option(parsing: .unconditional, help: "Image width in pixels.") var width: Int = 1920
    @Option(parsing: .unconditional, help: "Image height in pixels.") var height: Int = 1080
    @Option(name: .customLong("disk-outer"), parsing: .unconditional, help: "Outer disk radius in M.") var diskOuter: Double = 20
    @Option(name: .customLong("accretion-rate"), parsing: .unconditional, help: "Disk luminosity as a fraction of the Eddington luminosity.")
    var accretionRate: Double = 0.1
    @Option(parsing: .unconditional, help: "Black hole mass in solar masses (sets the physical scale only).") var mass: Double = 10
    @Option(help: "Background: starfield or grid.") var sky: SkyChoice = .starfield
    @Option(parsing: .unconditional, help: "Seed for the sky and the sample jitter.") var seed: UInt64 = 1
    @Option(parsing: .unconditional, help: "Display exposure offset in stops (PNG only).") var exposure: Double = 0
    @Flag(name: .customLong("no-disk"), help: "Omit the accretion disk: render a bare black hole and sky.") var noDisk = false
    @Option(name: .customLong("max-steps"), parsing: .unconditional,
            help: "Integrator step budget per ray; rays needing more are reported as unresolved.")
    var maxSteps: Int = NumericalDefaults.stepBudget
    @Option(help: "Ray-tracing backend: cpu (float64 reference, default) or metal (Apple GPU, float32).") var backend: BackendChoice = .cpu

    func config(samples: Int) -> RenderConfig {
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
        config.backend = backend == .metal ? .metal : .cpu
        return config
    }
}
