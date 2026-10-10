import Dispatch
import Foundation

/// Tolerances of the backend agreement check (FR-003, FR-007; docs/tolerances.md, GPU section).
public enum AgreementTolerances {
    public static let outcomeMatchFraction = 0.999
    public static let radiusRelativeP99 = 1e-3
    public static let skyDirectionRadians = 1e-4
    public static let skyDirectionFraction = 0.999
    public static let radianceRelativeP99 = 0.01
    /// Radiance differences are relative to max(reference value, `radianceFloorOfPeak` × the reference image's peak).
    public static let radianceFloorOfPeak = 1e-3
    public static let shadowAreaRelative = 0.01
    public static let shadowRadiusRelative = 0.01
    public static let speedup = 3.0
}

/// One pass/fail judgement of a compared quantity.
public struct AgreementVerdict: Sendable, Equatable {
    public var quantity: String
    public var value: Double
    public var limit: String
    public var passed: Bool
}

/// Agreement of the two backends on one ray set (outcome, crossing radius, sky direction).
public struct RayAgreement: Sendable, Equatable {
    public var rays = 0
    public var outcomeMatchFraction = 1.0
    public var radiusP99 = 0.0
    public var radiusMax = 0.0
    public var diskPairs = 0
    public var skyPairs = 0
    public var skyWithinToleranceFraction = 1.0
    public var skyMaxAngle = 0.0
}

/// Agreement of the two backends' pixels.
public struct PixelAgreement: Sendable, Equatable {
    public var pixels = 0
    public var radianceP99 = 0.0
    public var radianceMax = 0.0
    public var shadowAreaDifference = 0.0
}

/// A scene of the standard set.
public struct AgreementScene: Sendable {
    public var name: String
    public var config: RenderConfig
}

public struct SceneAgreement: Sendable {
    public var scene: String
    public var rays: RayAgreement
    public var pixels: PixelAgreement
    /// Error of each backend's shadow radius against the analytic value (non-spinning scenes only).
    public var shadowRadiusErrorCPU: Double?
    public var shadowRadiusErrorGPU: Double?
    public var gpuP999Residual: Double
    public var gpuBadRayFraction: Double
    public var gpuUnresolvedFraction: Double
    public var refinedFraction: Double
    public var cpuSeconds: Double
    public var gpuSeconds: Double
    public var speedup: Double { gpuSeconds > 0 ? cpuSeconds / gpuSeconds : 0 }
    public var verdicts: [AgreementVerdict]
    public var passed: Bool { verdicts.allSatisfy(\.passed) }
    public var failures: [AgreementVerdict] { verdicts.filter { !$0.passed } }
}

public struct AgreementReport: Sendable {
    public var scenes: [SceneAgreement]
    public var passed: Bool { scenes.allSatisfy(\.passed) }
    public init(scenes: [SceneAgreement]) { self.scenes = scenes }
}

public enum BackendAgreement {
    // MARK: Standard scenes

    /// The five standard scenes: 960×540 at 4 samples per pixel (SC-007), or 240×135 for the quick smoke test.
    public static func standardScenes(quick: Bool) -> [AgreementScene] {
        func scene(_ name: String, _ edit: (inout RenderConfig) -> Void) -> AgreementScene {
            var config = RenderConfig()
            config.width = quick ? 240 : 960
            config.height = quick ? 135 : 540
            config.samplesPerPixel = 4
            edit(&config)
            return AgreementScene(name: name, config: config)
        }
        return [
            scene("default") { _ in },
            scene("spin 0.9, 85°") { $0.blackHole.spin = 0.9; $0.observer.inclinationDegrees = 85 },
            scene("spin 0.998, 60°") { $0.blackHole.spin = 0.998; $0.observer.inclinationDegrees = 60 },
            scene("bare hole, grid sky") {
                $0.blackHole.spin = 0; $0.observer.inclinationDegrees = 90; $0.observer.fieldOfViewDegrees = 12
                $0.diskEnabled = false; $0.sky.kind = .grid
            },
            scene("cool disk") { $0.disk.accretionRateEddington = 0.01 },
        ]
    }

    // MARK: Pure comparison

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(p * Double(sorted.count)))]
    }

    /// Compares the outcomes of the same rays on the two backends.
    public static func compareRays(cpu: [RayOutcome], gpu: [RayOutcome]) -> RayAgreement {
        precondition(cpu.count == gpu.count)
        var same = 0
        var radiusErrors: [Double] = [], angles: [Double] = []
        for (a, b) in zip(cpu, gpu) {
            switch (a, b) {
            case (.captured, .captured): same += 1
            case (.disk(let r1, let i1, let f1), .disk(let r2, let i2, let f2)):
                if i1 == i2 && f1 == f2 { same += 1 }
                radiusErrors.append(abs(r1 - r2) / r1)
            case (.sky(let d1), .sky(let d2)):
                same += 1
                angles.append(acos(min(1, max(-1, (d1 * d2).sum()))))
            case (.unresolved(let x), .unresolved(let y)) where x == y: same += 1
            default: break
            }
        }
        var result = RayAgreement()
        result.rays = cpu.count
        result.outcomeMatchFraction = cpu.isEmpty ? 1 : Double(same) / Double(cpu.count)
        result.diskPairs = radiusErrors.count
        result.radiusP99 = percentile(radiusErrors, 0.99)
        result.radiusMax = radiusErrors.max() ?? 0
        result.skyPairs = angles.count
        result.skyWithinToleranceFraction = angles.isEmpty ? 1 : Double(angles.filter { $0 <= AgreementTolerances.skyDirectionRadians }.count) / Double(angles.count)
        result.skyMaxAngle = angles.max() ?? 0
        return result
    }

    /// Compares two rendered images pixel by pixel over the pixels whose samples all hit the disk or fell into the horizon.
    public static func comparePixels(cpu: RenderedImage, gpu: RenderedImage) -> PixelAgreement {
        precondition(cpu.hdr.count == gpu.hdr.count)
        let peak = Double(cpu.hdr.map { max($0.x, $0.y, $0.z) }.max() ?? 1)
        var errors: [Double] = []
        func solid(_ image: RenderedImage, _ i: Int) -> Bool {
            image.unresolvedFraction[i] == 0 && image.diskFraction[i] + image.capturedFraction[i] > 0.999_999
        }
        for i in cpu.hdr.indices where solid(cpu, i) && solid(gpu, i) {
            let a = cpu.hdr[i], b = gpu.hdr[i]
            let scale = max(Double(max(a.x, a.y, a.z)), AgreementTolerances.radianceFloorOfPeak * peak)
            errors.append(Double(max(abs(a.x - b.x), abs(a.y - b.y), abs(a.z - b.z))) / scale)
        }
        let areaCPU = cpu.capturedFraction.reduce(0.0) { $0 + Double($1) }
        let areaGPU = gpu.capturedFraction.reduce(0.0) { $0 + Double($1) }
        var result = PixelAgreement()
        result.pixels = errors.count
        result.radianceP99 = percentile(errors, 0.99)
        result.radianceMax = errors.max() ?? 0
        result.shadowAreaDifference = areaCPU > 0 ? abs(areaCPU - areaGPU) / areaCPU : abs(areaGPU)
        return result
    }

    /// Angular tangent-plane radius of the shadow of a non-spinning hole seen edge-on, from the captured area.
    static func shadowTangentRadius(of image: RenderedImage, config: RenderConfig) -> Double {
        let area = image.capturedFraction.reduce(0.0) { $0 + Double($1) }
        let pixelSize = 2 * tan(config.observer.fieldOfViewDegrees * Double.pi / 360) / Double(config.width)
        return (area / Double.pi).squareRoot() * pixelSize
    }

    /// Analytic tangent of the angular radius of a Schwarzschild shadow for a static observer at `distance` (M).
    static func analyticShadowTangent(distance d: Double) -> Double {
        tan(asin(27.0.squareRoot() / d * (1 - 2 / d).squareRoot()))
    }

    /// Judges a scene against the tolerances. `speedupChecked` is false for the quick set (too small for a fair timing).
    public static func verdicts(rays: RayAgreement, pixels: PixelAgreement, shadowRadiusErrorGPU: Double?, gpuBadRayFraction: Double,
                                gpuUnresolvedFraction: Double, speedup: Double, speedupChecked: Bool) -> [AgreementVerdict] {
        var list = [
            AgreementVerdict(quantity: "ray outcome match", value: rays.outcomeMatchFraction,
                             limit: "≥ \(AgreementTolerances.outcomeMatchFraction)", passed: rays.outcomeMatchFraction >= AgreementTolerances.outcomeMatchFraction),
            AgreementVerdict(quantity: "crossing radius p99", value: rays.radiusP99,
                             limit: "< \(AgreementTolerances.radiusRelativeP99)", passed: rays.radiusP99 < AgreementTolerances.radiusRelativeP99),
            AgreementVerdict(quantity: "sky direction within \(AgreementTolerances.skyDirectionRadians) rad", value: rays.skyWithinToleranceFraction,
                             limit: "≥ \(AgreementTolerances.skyDirectionFraction)", passed: rays.skyWithinToleranceFraction >= AgreementTolerances.skyDirectionFraction),
            AgreementVerdict(quantity: "radiance p99", value: pixels.radianceP99,
                             limit: "< \(AgreementTolerances.radianceRelativeP99)", passed: pixels.radianceP99 < AgreementTolerances.radianceRelativeP99),
            AgreementVerdict(quantity: "shadow area difference", value: pixels.shadowAreaDifference,
                             limit: "< \(AgreementTolerances.shadowAreaRelative)", passed: pixels.shadowAreaDifference < AgreementTolerances.shadowAreaRelative),
            AgreementVerdict(quantity: "GPU bad rays (unresolved or residual)", value: gpuBadRayFraction,
                             limit: "< \(NumericalDefaults.allowedBadRayFraction)", passed: gpuBadRayFraction < NumericalDefaults.allowedBadRayFraction),
            AgreementVerdict(quantity: "GPU unresolved", value: gpuUnresolvedFraction,
                             limit: "< \(NumericalDefaults.allowedBadRayFraction)", passed: gpuUnresolvedFraction < NumericalDefaults.allowedBadRayFraction),
        ]
        if let error = shadowRadiusErrorGPU {
            list.append(AgreementVerdict(quantity: "GPU shadow radius vs analytic", value: error,
                                         limit: "< \(AgreementTolerances.shadowRadiusRelative)", passed: error < AgreementTolerances.shadowRadiusRelative))
        }
        if speedupChecked {
            list.append(AgreementVerdict(quantity: "speed-up", value: speedup, limit: "≥ \(AgreementTolerances.speedup)", passed: speedup >= AgreementTolerances.speedup))
        }
        return list
    }

    // MARK: Running the check

    /// Renders the scene on both backends and compares them. The ray-level comparison uses one ray per pixel centre.
    public static func run(scene: AgreementScene, quick: Bool, forceGPUUnavailable: Bool = false) throws -> SceneAgreement {
        var gpuConfig = scene.config
        gpuConfig.backend = .metal
        let gpuRenderer = try Renderer(config: gpuConfig, forceGPUUnavailable: forceGPUUnavailable)  // fails first if there is no GPU
        var cpuConfig = scene.config
        cpuConfig.backend = .cpu
        let cpuRenderer = try Renderer(config: cpuConfig)

        let cpuImage = cpuRenderer.render()
        let gpuImage = try gpuRenderer.renderOnBackend()

        let width = scene.config.width, height = scene.config.height
        let rays = (0..<(width * height)).map { cpuRenderer.camera.ray(pixelX: Double($0 % width) + 0.5, pixelY: Double($0 / width) + 0.5) }
        var cpuOutcomes = [RayOutcome](repeating: .captured, count: rays.count)
        cpuOutcomes.withUnsafeMutableBufferPointer { out in
            let target = SendablePointer(out.baseAddress!)
            let tracer = cpuRenderer.tracer
            DispatchQueue.concurrentPerform(iterations: (rays.count + 255) / 256) { chunk in
                for i in (chunk * 256)..<min(rays.count, (chunk + 1) * 256) { target[i] = tracer.trace(rays[i]).outcome }
            }
        }
        let gpuOutcomes = try gpuRenderer.gpuOutcomes(of: rays)

        let rayAgreement = compareRays(cpu: cpuOutcomes, gpu: gpuOutcomes)
        let pixelAgreement = comparePixels(cpu: cpuImage, gpu: gpuImage)

        var errorCPU: Double?, errorGPU: Double?
        if scene.config.blackHole.spin == 0 && !scene.config.diskEnabled && abs(scene.config.observer.mu) < 1e-12 {
            let analytic = analyticShadowTangent(distance: scene.config.observer.distance)
            errorCPU = abs(shadowTangentRadius(of: cpuImage, config: scene.config) - analytic) / analytic
            errorGPU = abs(shadowTangentRadius(of: gpuImage, config: scene.config) - analytic) / analytic
        }
        let total = Double(max(gpuImage.diagnostics.raysTotal, 1))
        let unresolved = Double(gpuImage.diagnostics.unresolved) / total
        let cpuSeconds = cpuImage.diagnostics.wallTimeSeconds, gpuSeconds = gpuImage.diagnostics.wallTimeSeconds
        let bad = gpuImage.diagnostics.badRayFraction
        let verdictList = verdicts(rays: rayAgreement, pixels: pixelAgreement, shadowRadiusErrorGPU: errorGPU, gpuBadRayFraction: bad,
                                   gpuUnresolvedFraction: unresolved, speedup: gpuSeconds > 0 ? cpuSeconds / gpuSeconds : 0, speedupChecked: !quick)
        return SceneAgreement(scene: scene.name, rays: rayAgreement, pixels: pixelAgreement,
                              shadowRadiusErrorCPU: errorCPU, shadowRadiusErrorGPU: errorGPU,
                              gpuP999Residual: gpuImage.diagnostics.p999Residual, gpuBadRayFraction: bad, gpuUnresolvedFraction: unresolved,
                              refinedFraction: Double(gpuImage.gpuStatistics?.refinedRays ?? 0) / total,
                              cpuSeconds: cpuSeconds, gpuSeconds: gpuSeconds, verdicts: verdictList)
    }
}
