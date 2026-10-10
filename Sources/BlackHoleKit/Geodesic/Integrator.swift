import Foundation

typealias StateVector = SIMD8<Double>  // components 0...4 used: u, vu, mu, vmu, phi

extension StateVector {
    init(_ s: RayState) {
        self.init(s.u, s.vu, s.mu, s.vmu, s.phi, 0, 0, 0)
    }
    var rayState: RayState { RayState(u: self[0], vu: self[1], mu: self[2], vmu: self[3], phi: self[4]) }
}

/// Adaptive Dormand–Prince 5(4) integrator for Kerr null geodesics in Mino time (research.md D2, D3).
///
/// Equations (derivatives with respect to λ′, see `RayState`), with u = 1/r:
///
///     u″ = R̃′(u)/2,    μ″ = Θ_μ′(μ)/2,    φ′ = −dφ/dλ
///
/// where R̃(u) = R(r)/r⁴ = p̃² − δ̃Ku², p̃ = E + a(aE − L)u², δ̃ = 1 − 2u + a²u², K = (L − aE)² + Q.
/// The second-order forms pass smoothly through radial and polar turning points. The first integrals
/// (u′)² = R̃(u) and (μ′)² = Θ_μ(μ) are conserved by the exact flow, so their residuals measure
/// integration accuracy.
public struct GeodesicIntegrator: Sendable {
    public let kerr: Kerr
    public let constants: PhotonConstants
    public let settings: IntegratorSettings

    // Precomputed constants for the right-hand side.
    private let a: Double
    private let a2: Double
    private let energy: Double
    private let angularMomentum: Double
    private let radialK: Double  // (L − aE)² + Q
    private let a2e2: Double  // a²E²
    private let polarCoefficient: Double  // a²E² − Q − L²
    private let aaeMinusL: Double  // a(aE − L)
    private let horizonU: Double  // 1 / r₊

    public init(kerr: Kerr, constants: PhotonConstants, settings: IntegratorSettings) {
        self.kerr = kerr
        self.constants = constants
        self.settings = settings
        a = kerr.spin
        a2 = kerr.spin * kerr.spin
        energy = constants.energy
        angularMomentum = constants.angularMomentum
        let la = constants.angularMomentum - kerr.spin * constants.energy
        radialK = la * la + constants.carter
        a2e2 = kerr.spin * kerr.spin * constants.energy * constants.energy
        polarCoefficient = a2e2 - constants.carter - constants.angularMomentum * constants.angularMomentum
        aaeMinusL = kerr.spin * (kerr.spin * constants.energy - constants.angularMomentum)
        horizonU = 1 / kerr.horizonRadius
    }

    // MARK: Right-hand side

    /// State derivative with respect to λ′.
    func derivative(_ y: StateVector) -> StateVector {
        let u = y[0]
        let mu = y[2]
        let u2 = u * u
        let pTilde = energy + aaeMinusL * u2  // P/r²
        let deltaTilde = 1 - 2 * u + a2 * u2  // Δ/r²
        let sin2 = 1 - mu * mu
        let axisTerm = angularMomentum == 0 ? 0 : angularMomentum / max(sin2, 1e-300)
        var d = StateVector()
        d[0] = y[1]
        d[1] = 2 * aaeMinusL * u * pTilde - radialK * u * (1 - 3 * u + 2 * a2 * u2)  // R̃′(u)/2
        d[2] = y[3]
        d[3] = mu * (polarCoefficient - 2 * a2e2 * mu * mu)  // Θ_μ′(μ)/2
        d[4] = -(axisTerm - a * energy + a * pTilde / deltaTilde)
        return d
    }

    /// R̃(u) = R(r)/r⁴.
    func radialPotentialInverse(u: Double) -> Double {
        let u2 = u * u
        let pTilde = energy + aaeMinusL * u2
        let deltaTilde = 1 - 2 * u + a2 * u2
        return pTilde * pTilde - deltaTilde * radialK * u2
    }

    // MARK: Residuals

    /// Normalized first-integral residual (research.md D2), with E scaled out:
    /// δ_r = |u′² − R̃(u)| / (E²(1 + a²u²)²), which equals |r′² − R| / (E²(r² + a²)²);
    /// δ_μ = |μ′² − Θ_μ| / (Q + L² + a²E²).
    /// Returns max(δ_r, δ_μ).
    public func residual(of s: RayState) -> Double {
        let tt = kerr.polarPotential(mu: s.mu, constants: constants)
        let radialScale = energy * energy * (1 + a2 * s.u * s.u) * (1 + a2 * s.u * s.u)
        let polarScale = constants.carter + angularMomentum * angularMomentum + a2e2 + 1e-12 * energy * energy
        return max(abs(s.vu * s.vu - radialPotentialInverse(u: s.u)) / radialScale,
                   abs(s.vmu * s.vmu - tt) / polarScale)
    }

    // MARK: Initial conditions

    /// Builds a state at (r, μ) satisfying both first integrals. `radialSign` is the sign of dr/dλ′
    /// (−1 for a ray going inward from the observer) and `polarSign` that of dμ/dλ′.
    /// Returns nil when the ray cannot exist there (R < 0 or Θ_μ < 0).
    public func initialState(r: Double, mu: Double, radialSign: Double, polarSign: Double, phi: Double = 0) -> RayState? {
        let u = 1 / r
        let rr = radialPotentialInverse(u: u)
        let tt = kerr.polarPotential(mu: mu, constants: constants)
        guard rr >= 0, tt >= 0 else { return nil }
        // dr/dλ′ has sign `radialSign`, so du/dλ′ = −(dr/dλ′)/r² has the opposite sign.
        return RayState(u: u, vu: -radialSign * rr.squareRoot(), mu: mu, vmu: polarSign * tt.squareRoot(), phi: phi)
    }

    // MARK: Dormand–Prince 5(4)

    /// One Dormand–Prince step of size `h` from `y`, with `k1 = f(y)` supplied (FSAL).
    /// Returns the fifth-order solution, the embedded error estimate, and k7 = f(y_new).
    func dormandPrince(_ y: StateVector, _ h: Double, _ k1: StateVector) -> (y: StateVector, err: StateVector, k7: StateVector) {
        let k2 = derivative(y + h * (1.0 / 5.0) * k1)
        let k3 = derivative(y + h * (3.0 / 40.0 * k1 + 9.0 / 40.0 * k2))
        let k4 = derivative(y + h * (44.0 / 45.0 * k1 - 56.0 / 15.0 * k2 + 32.0 / 9.0 * k3))
        let k5 = derivative(y + h * (19372.0 / 6561.0 * k1 - 25360.0 / 2187.0 * k2 + 64448.0 / 6561.0 * k3 - 212.0 / 729.0 * k4))
        let k6 = derivative(y + h * (9017.0 / 3168.0 * k1 - 355.0 / 33.0 * k2 + 46732.0 / 5247.0 * k3
                                    + 49.0 / 176.0 * k4 - 5103.0 / 18656.0 * k5))
        let yNew = y + h * (35.0 / 384.0 * k1 + 500.0 / 1113.0 * k3 + 125.0 / 192.0 * k4
                            - 2187.0 / 6784.0 * k5 + 11.0 / 84.0 * k6)
        let k7 = derivative(yNew)
        let err = h * (71.0 / 57600.0 * k1 - 71.0 / 16695.0 * k3 + 71.0 / 1920.0 * k4
                       - 17253.0 / 339200.0 * k5 + 22.0 / 525.0 * k6 - 1.0 / 40.0 * k7)
        return (yNew, err, k7)
    }

    /// Advances `s` by exactly `h` with one fifth-order step (no error control). Used to refine events
    /// such as plane crossings inside an accepted step.
    public func advance(_ s: RayState, by h: Double) -> RayState {
        let y = StateVector(s)
        return dormandPrince(y, h, derivative(y)).y.rayState
    }

    /// State derivative as a `RayState` (u′ = vu, vu′ = R̃′/2, μ′ = vmu, vmu′ = Θ′/2, φ′).
    public func derivativeState(_ s: RayState) -> RayState {
        derivative(StateVector(s)).rayState
    }

    private func scaledError(_ err: StateVector, _ y: StateVector, _ yNew: StateVector) -> Double {
        var worst = 0.0
        for i in 0..<5 {
            let scale = settings.absoluteTolerance + settings.relativeTolerance * max(abs(y[i]), abs(yNew[i]))
            worst = max(worst, abs(err[i]) / scale)
        }
        return worst
    }

    // MARK: Integration loop

    /// Integrates from `initial` until the ray reaches the horizon cutoff, the sky radius, the step
    /// budget, or `stop(previous, new, stepSize)` returns true for an accepted step.
    public func integrate(from initial: RayState,
                          stop: (_ previous: RayState, _ new: RayState, _ step: Double) -> Bool = { _, _, _ in false }) -> IntegrationResult {
        var y = StateVector(initial)
        var k1 = derivative(y)
        var h = 1e-3
        var steps = 0
        var landingTries = 0
        var maxResidual = residual(of: initial)
        let horizonStop = 1 / (kerr.horizonRadius + settings.horizonCutoff)  // u at the capture radius
        let skyStop = 1 / settings.skyRadius

        while true {
            if steps >= settings.stepBudget {
                return IntegrationResult(state: y.rayState, termination: .stepBudget, steps: steps, maxResidual: maxResidual)
            }
            // Keep the stages of an inward step (u increasing) outside the horizon, where Δ → 0 makes the
            // rates blow up.
            var hTry = h
            if y[1] > 0 {
                hTry = min(hTry, 0.4 * (horizonU - y[0]) / y[1])
            } else if y[1] < 0 && y[0] > skyStop {
                // Outgoing: never step more than ~3x the distance to the sky radius, so the landing
                // correction below always starts from a bracketing step (and never overshoots through u = 0).
                hTry = min(hTry, 3 * (y[0] - skyStop) / -y[1])
            }
            let (yNew, err, k7) = dormandPrince(y, hTry, k1)
            let errNorm = scaledError(err, y, yNew)

            if errNorm.isFinite && errNorm <= 1 {
                // Landing: if this step crosses the sky radius, shrink it (secant on u) until it ends
                // within 1e-9 (relative) of the sky radius, so the exit state is at a well-defined radius.
                if y[1] < 0 && yNew[0] < skyStop * (1 - 1e-9) && landingTries < 12 {
                    landingTries += 1
                    h = hTry * (y[0] - skyStop) / (y[0] - yNew[0])
                    continue
                }
                landingTries = 0
                steps += 1
                let previous = y.rayState
                y = yNew
                k1 = k7
                let state = y.rayState
                maxResidual = max(maxResidual, residual(of: state))
                if state.u >= horizonStop {
                    return IntegrationResult(state: state, termination: .horizon, steps: steps, maxResidual: maxResidual)
                }
                if state.u <= skyStop && state.vu < 0 {
                    return IntegrationResult(state: state, termination: .sky, steps: steps, maxResidual: maxResidual)
                }
                if stop(previous, state, hTry) {
                    return IntegrationResult(state: state, termination: .stopped, steps: steps, maxResidual: maxResidual)
                }
                let factor = errNorm == 0 ? 5.0 : min(5.0, max(0.2, 0.9 * pow(errNorm, -0.2)))
                h = hTry * factor
            } else {
                let factor = errNorm.isFinite ? max(0.2, 0.9 * pow(errNorm, -0.2)) : 0.2
                h = hTry * factor
                if h < 1e-16 {
                    return IntegrationResult(state: y.rayState, termination: .failed, steps: steps, maxResidual: maxResidual)
                }
            }
        }
    }
}
