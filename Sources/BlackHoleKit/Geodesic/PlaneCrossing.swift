import Foundation

/// One crossing of the equatorial plane (μ = 0) by a traced ray.
public struct PlaneCrossing: Sendable, Equatable {
    /// Boyer–Lindquist radius at the crossing.
    public var radius: Double
    public var phi: Double
    /// 1-based index along the ray.
    public var index: Int
    /// Side of the plane the (backward-traced) ray came from.
    public var face: DiskFace
    /// Whether the crossing radius lies inside the disk annulus.
    public var insideDisk: Bool
}

/// Traces one camera ray to a `RayOutcome`, detecting equatorial-plane crossings and testing them against
/// the (opaque, two-sided) disk annulus (FR-004; research.md D5).
///
/// At most `maxPlaneCrossings` crossings are tested against the disk (default 3, from the spec
/// clarification). A ray still active after that continues to the horizon or the sky with no further disk
/// tests; the neglected contributions are documented in docs/physics.md.
public struct RayTracer: Sendable {
    public struct Result: Sendable {
        public var outcome: RayOutcome
        /// Maximum normalized first-integral residual along the ray.
        public var maxResidual: Double
        public var steps: Int
        /// Every crossing seen (up to `maxPlaneCrossings`), inside the annulus or not.
        public var crossings: [PlaneCrossing]
    }

    public let kerr: Kerr
    public let disk: DiskGeometry
    public let settings: IntegratorSettings
    public let maxPlaneCrossings: Int

    public init(kerr: Kerr, diskInnerRadius: Double, diskOuterRadius: Double, skyRadius: Double,
                maxPlaneCrossings: Int = NumericalDefaults.maxPlaneCrossings,
                settings: IntegratorSettings? = nil) {
        self.kerr = kerr
        disk = DiskGeometry(innerRadius: diskInnerRadius, outerRadius: diskOuterRadius)
        self.settings = settings ?? .standard(skyRadius: skyRadius)
        self.maxPlaneCrossings = maxPlaneCrossings
    }

    public init(config: RenderConfig, settings: IntegratorSettings? = nil) {
        let kerr = config.kerr
        self.init(kerr: kerr, diskInnerRadius: kerr.iscoRadius, diskOuterRadius: config.disk.outerRadius,
                  skyRadius: config.skyRadius, maxPlaneCrossings: config.diskEnabled ? NumericalDefaults.maxPlaneCrossings : 0,
                  settings: settings)
    }

    public func trace(_ ray: CameraRay) -> Result {
        let integrator = GeodesicIntegrator(kerr: kerr, constants: ray.constants, settings: settings)
        var crossings: [PlaneCrossing] = []
        var hit: PlaneCrossing?
        var side = ray.state.mu > 0 ? 1 : (ray.state.mu < 0 ? -1 : 0)  // 0: starting exactly in the plane

        let result = integrator.integrate(from: ray.state) { previous, new, step in
            guard crossings.count < maxPlaneCrossings else { return false }
            let newSide = new.mu > 0 ? 1 : (new.mu < 0 ? -1 : 0)
            if side == 0 {
                side = newSide  // leaving the plane from the start is not a crossing
                return false
            }
            guard newSide != 0, newSide != side else { return false }

            let (radius, phi) = refine(integrator: integrator, previous: previous, new: new, step: step)
            let crossing = PlaneCrossing(radius: radius, phi: phi, index: crossings.count + 1,
                                         face: side > 0 ? .upper : .lower, insideDisk: disk.contains(radius: radius))
            crossings.append(crossing)
            side = newSide
            if crossing.insideDisk {
                hit = crossing
                return true
            }
            return false
        }

        let outcome: RayOutcome
        switch result.termination {
        case .stopped:
            outcome = hit.map { .disk(radius: $0.radius, crossingIndex: $0.index, face: $0.face) } ?? .unresolved(.integrationFailure)
        case .horizon:
            outcome = .captured
        case .sky:
            outcome = .sky(direction: AsymptoticDirection.direction(of: result.state, constants: ray.constants, kerr: kerr))
        case .stepBudget:
            outcome = .unresolved(.stepBudget)
        case .failed:
            outcome = .unresolved(.integrationFailure)
        }
        return Result(outcome: outcome, maxResidual: result.maxResidual, steps: result.steps, crossings: crossings)
    }

    /// Locates μ = 0 inside the accepted step `previous → new` and returns (r, φ) there.
    /// A cubic Hermite interpolant of μ gives the starting fraction; one Newton correction using a real
    /// Dormand–Prince step to that fraction makes the root accurate to the integrator's tolerance.
    private func refine(integrator: GeodesicIntegrator, previous: RayState, new: RayState, step: Double) -> (Double, Double) {
        let m0 = previous.mu, m1 = new.mu
        let d0 = previous.vmu * step, d1 = new.vmu * step
        func hermite(_ s: Double) -> Double {
            let s2 = s * s, s3 = s2 * s
            return (2 * s3 - 3 * s2 + 1) * m0 + (s3 - 2 * s2 + s) * d0 + (-2 * s3 + 3 * s2) * m1 + (s3 - s2) * d1
        }
        // Bisection on the Hermite cubic (it brackets the root: m0 and m1 have opposite signs).
        var lo = 0.0, hi = 1.0
        var flo = hermite(lo)
        for _ in 0..<60 {
            let mid = 0.5 * (lo + hi)
            let fm = hermite(mid)
            if (fm > 0) == (flo > 0) { lo = mid; flo = fm } else { hi = mid }
        }
        var s = 0.5 * (lo + hi)
        // Newton correction with the actual integrator step.
        for _ in 0..<2 {
            let y = integrator.advance(previous, by: s * step)
            let slope = y.vmu * step
            if slope == 0 { break }
            s = min(max(s - y.mu / slope, 0), 1)
        }
        let y = integrator.advance(previous, by: s * step)
        return (y.r, y.phi)
    }
}
