import Foundation

/// A primary ray for one image position: the photon constants and the integrator's initial state.
public struct CameraRay: Sendable {
    /// Constants of the **physical** photon (the one arriving at the observer), scaled so E = 1.
    public var constants: PhotonConstants
    /// Initial state for backward tracing (see `RayState`).
    public var state: RayState
    /// Photon energy measured by the static observer, in units where the photon's E = 1:
    /// −p·u_obs = E / √(−g_tt) · (1/E_raw) = 1/E_raw. Needed for the shift factor g = ν_obs/ν_emit.
    public var observerEnergy: Double

    public init(constants: PhotonConstants, state: RayState, observerEnergy: Double) {
        self.constants = constants
        self.state = state
        self.observerEnergy = observerEnergy
    }
}

/// Pinhole camera carried by a static observer, looking at the black hole (research.md D4).
///
/// Image axes: forward = −r̂ (toward the hole), up = −θ̂ (toward the spin axis, north), right =
/// forward × up = +φ̂. A pixel direction n is the direction from the observer toward that part of the
/// sky; the physical photon travels along −n.
public struct Camera: Sendable {
    public let kerr: Kerr
    public let observer: Observer
    public let tetrad: StaticTetrad
    public let width: Int
    public let height: Int
    private let tanHalfFov: Double
    private let aspect: Double  // height / width
    private let sinTheta: Double
    private let azimuth: Double

    public init(kerr: Kerr, observer: Observer, width: Int, height: Int) {
        self.kerr = kerr
        self.observer = observer
        self.width = width
        self.height = height
        tetrad = StaticTetrad(kerr: kerr, radius: observer.distance, mu: observer.mu)
        tanHalfFov = tan(observer.fieldOfViewDegrees * Double.pi / 360)
        aspect = Double(height) / Double(width)
        sinTheta = (1 - observer.mu * observer.mu).squareRoot()
        azimuth = observer.azimuthDegrees * Double.pi / 180
    }

    /// Unit direction toward the pixel at normalized device coordinates (x right, y up, each in [−1, 1]),
    /// in the basis (forward, right, up).
    public func localDirection(ndcX: Double, ndcY: Double) -> SIMD3<Double> {
        let v = SIMD3(1, ndcX * tanHalfFov, ndcY * tanHalfFov * aspect)
        return v / (v * v).sum().squareRoot()
    }

    /// Ray through continuous pixel coordinates (x to the right, y downward, origin at the top-left
    /// corner of the top-left pixel; pixel centres are at half-integers).
    public func ray(pixelX: Double, pixelY: Double) -> CameraRay {
        ray(ndcX: 2 * pixelX / Double(width) - 1, ndcY: 1 - 2 * pixelY / Double(height))
    }

    public func ray(ndcX: Double, ndcY: Double) -> CameraRay {
        let n = localDirection(ndcX: ndcX, ndcY: ndcY)
        // Physical photon direction in the tetrad's (r̂, θ̂, φ̂): p̂ = −n, with n = (−n_f) r̂ + (−n_u) θ̂ + n_ρ φ̂.
        let pr = n.x, ptheta = n.z, pphi = -n.y

        // Contravariant momentum with unit local energy: p = e₀ + p̂_r e_r + p̂_θ e_θ + p̂_φ e_φ.
        let p = tetrad.e0 + pr * tetrad.er + ptheta * tetrad.etheta + pphi * tetrad.ephi
        let g = tetrad.metric
        let energyRaw = -(g.tt * p[0] + g.tphi * p[3])  // E = −p_t
        let lRaw = g.tphi * p[0] + g.phiphi * p[3]  // L = p_φ
        let scale = 1 / energyRaw  // normalize so E = 1 (path is independent of the overall scale)

        let mu = observer.mu
        let sigma = g.thth  // Σ = g_θθ
        let sigmaPr = sigma * p[1] * scale  // Σ p^r = dr/dλ (physical)
        let pTheta = g.thth * p[2] * scale  // p_θ = Σ p^θ
        let l = lRaw * scale
        let a = kerr.spin
        let q = pTheta * pTheta + mu * mu * (l * l / (sinTheta * sinTheta) - a * a)

        let u = 1 / observer.distance
        let state = RayState(u: u, vu: sigmaPr * u * u, mu: mu, vmu: sinTheta * pTheta, phi: azimuth)
        return CameraRay(constants: PhotonConstants(energy: 1, angularMomentum: l, carter: q),
                         state: state, observerEnergy: scale)
    }
}
