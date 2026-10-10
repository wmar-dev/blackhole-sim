import Foundation

/// A rendered image and the per-pixel maps used to inspect and test it.
public struct RenderedImage: Sendable {
    public var width: Int
    public var height: Int
    /// Linear sRGB radiance in reference units, row-major, top row first.
    public var hdr: [SIMD3<Float>]
    /// Per pixel, the fraction of its samples that hit the disk / fell into the horizon / hit the disk at
    /// the second or third plane crossing / were unresolved.
    public var diskFraction: [Float]
    public var capturedFraction: [Float]
    public var higherOrderFraction: [Float]
    public var unresolvedFraction: [Float]
    public var diagnostics: Diagnostics
    public var shading: Shading
    /// The backend that traced the rays.
    public var backend: Backend
    /// Y-weighted radiance (W m⁻² sr⁻¹) equal to 1.0 in `hdr`: that of the hottest unshifted disk emission.
    public var referenceRadiance: Double
    /// GPU work statistics; nil for the CPU backend.
    public var gpuStatistics: GPUStatistics? = nil
}

/// Renders an image by backward ray tracing: every pixel sample is a null geodesic from the static observer
/// (FR-001), traced to the horizon, the disk, or the sky.
public struct Renderer: Sendable {
    public let config: RenderConfig
    public let sky: any SkyModel
    let camera: Camera
    let tracer: RayTracer
    let disk: NovikovThorne
    /// The GPU ray tracer (`config.backend == .metal`), nil for the CPU backend.
    let gpu: MetalRayTracer?
    /// Samples per GPU band (clamped to `NumericalDefaults.gpuMaxBufferBytes`).
    let gpuBandSamples: Int
    /// Y-weighted radiance of the hottest unshifted disk emission: 1.0 in the HDR output.
    public let referenceRadiance: Double

    private struct PixelResult: Sendable {
        var color: SIMD3<Float>
        var disk: Float
        var captured: Float
        var higherOrder: Float
        var unresolved: Float
    }

    /// - Parameters:
    ///   - sky: overrides the sky built from `config.sky` (used by tests).
    ///   - integratorSettings: overrides the default integrator settings (used by tests, e.g. a tiny step budget).
    ///   - forceGPUUnavailable: test hook that simulates a missing GPU for `backend == .metal`.
    ///   - gpuBandSamples: samples per GPU band (tests vary it to show that the image does not depend on it).
    public init(config: RenderConfig, sky: (any SkyModel)? = nil, integratorSettings: IntegratorSettings? = nil,
                forceGPUUnavailable: Bool = false, gpuBandSamples: Int = NumericalDefaults.gpuBandSamples) throws {
        self.gpuBandSamples = min(max(gpuBandSamples, 1), NumericalDefaults.gpuMaxBufferBytes / NumericalDefaults.gpuBytesPerSample)
        try config.validate()
        if config.backend == .metal {
            // No silent fallback to the CPU (FR-008): an unavailable GPU is an error.
            gpu = MetalRayTracer(context: try MetalContext.make(forceUnavailable: forceGPUUnavailable))
        } else {
            gpu = nil
        }
        self.config = config
        self.sky = sky ?? Sky.make(config.sky)
        camera = Camera(kerr: config.kerr, observer: config.observer, width: config.width, height: config.height)
        var settings = integratorSettings ?? .standard(skyRadius: config.skyRadius)
        if integratorSettings == nil { settings.stepBudget = config.maxStepsPerRay }
        tracer = RayTracer(config: config, settings: settings)
        disk = NovikovThorne(kerr: config.kerr, massSolar: config.blackHole.massSolar,
                             eddingtonFraction: config.disk.accretionRateEddington)
        referenceRadiance = disk.referenceLuminance(upTo: config.disk.outerRadius)
    }

    /// Traces the ray through continuous pixel coordinates (pixel centres at half-integers).
    public func trace(pixelX: Double, pixelY: Double) -> RayTracer.Result {
        tracer.trace(camera.ray(pixelX: pixelX, pixelY: pixelY))
    }

    /// Radiance carried by a traced ray, or nil if the ray is unresolved.
    func radiance(of result: RayTracer.Result, ray: CameraRay) -> SIMD3<Double>? {
        radiance(of: result.outcome, ray: ray)
    }

    /// Radiance carried by a ray with the given outcome, or nil if the ray is unresolved.
    func radiance(of outcome: RayOutcome, ray: CameraRay) -> SIMD3<Double>? {
        switch outcome {
        case .captured: return .zero
        case .disk(let radius, _, _):
            // The observed spectrum is exactly a blackbody at g·T (I_ν/ν³ is invariant along the ray).
            let g = ShiftFactor.g(kerr: config.kerr, radius: radius, angularMomentum: ray.constants.angularMomentum,
                                  observerEnergy: ray.observerEnergy)
            let rgb = Blackbody.linearSRGB(temperature: g * disk.temperature(r: radius)) / referenceRadiance
            return SIMD3(max(rgb.x, 0), max(rgb.y, 0), max(rgb.z, 0))  // clip out-of-gamut negatives
        case .sky(let direction): return sky.radiance(direction: direction)
        case .unresolved: return nil
        }
    }

    /// Renders on the configured backend. GPU failures (a command error, memory exhaustion) are thrown.
    public func renderOnBackend(maxConcurrency: Int? = nil, progress: (@Sendable (Double) -> Void)? = nil) throws -> RenderedImage {
        gpu == nil ? render(maxConcurrency: maxConcurrency, progress: progress) : try renderGPU(progress: progress)
    }

    /// Renders on the CPU (the reference backend). Use `renderOnBackend` for a renderer configured with the GPU.
    public func render(maxConcurrency: Int? = nil, progress: (@Sendable (Double) -> Void)? = nil) -> RenderedImage {
        precondition(gpu == nil, "this renderer uses the GPU backend: call renderOnBackend")
        let start = ContinuousClock.now
        let samplesPerAxis = Int(Double(config.samplesPerPixel).squareRoot().rounded())
        let seed = config.sky.seed
        let output = ParallelTiles.render(width: config.width, height: config.height, tileSize: 16,
                                          maxConcurrency: maxConcurrency, progress: progress) { x, y, diagnostics in
            var sum = SIMD3<Double>.zero
            var resolved = 0, disk = 0, captured = 0, higherOrder = 0, unresolved = 0
            for s in 0..<samplesPerAxis * samplesPerAxis {
                let jitter = SampleJitter.offset(seed: seed, pixelX: x, pixelY: y, sample: s)
                let px = Double(x) + (Double(s % samplesPerAxis) + jitter.x) / Double(samplesPerAxis)
                let py = Double(y) + (Double(s / samplesPerAxis) + jitter.y) / Double(samplesPerAxis)
                let ray = camera.ray(pixelX: px, pixelY: py)
                let result = tracer.trace(ray)
                diagnostics.record(result.outcome, residual: result.maxResidual)
                switch result.outcome {
                case .disk(_, let index, _):
                    disk += 1
                    if index >= 2 { higherOrder += 1 }
                case .captured: captured += 1
                case .unresolved: unresolved += 1
                case .sky: break
                }
                if let radiance = self.radiance(of: result, ray: ray) {
                    sum += radiance
                    resolved += 1
                }
            }
            let total = Float(samplesPerAxis * samplesPerAxis)
            let color = resolved > 0 ? SIMD3<Float>(sum / Double(resolved)) : .zero
            return PixelResult(color: color, disk: Float(disk) / total, captured: Float(captured) / total,
                               higherOrder: Float(higherOrder) / total, unresolved: Float(unresolved) / total)
        }
        var diagnostics = output.diagnostics
        let elapsed = ContinuousClock.now - start
        diagnostics.wallTimeSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        return RenderedImage(width: config.width, height: config.height,
                             hdr: output.pixels.map(\.color),
                             diskFraction: output.pixels.map(\.disk),
                             capturedFraction: output.pixels.map(\.captured),
                             higherOrderFraction: output.pixels.map(\.higherOrder),
                             unresolvedFraction: output.pixels.map(\.unresolved),
                             diagnostics: diagnostics, shading: .physical, backend: .cpu, referenceRadiance: referenceRadiance)
    }
}
