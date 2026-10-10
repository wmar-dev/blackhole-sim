/// The Metal Shading Language source of the ray-tracing kernels, compiled at run time (research.md D5).
///
/// A float32 port of `GeodesicIntegrator` (research.md D2, D3): the same equations in the same variables (u = 1/r, μ, φ in
/// Mino time), a Dormand–Prince 5(4) step with FSAL, and the same termination rules. The buffer layouts are fixed by
/// `contracts/gpu-buffers.md`. Test-only kernels are compiled when `BHSIM_TEST_KERNELS` is defined.
enum GeodesicKernelSource {
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    // ---- Buffer layouts (contracts/gpu-buffers.md): only 4-byte scalars, no vector members.
    struct RayInput {
        float u; float vu; float mu; float vmu; float phi; float L; float Q; float pad;
    };
    struct RayState {
        float u; float vu; float mu; float vmu; float phi; float step; float maxResidual; float minSin2;
        uint steps; uint crossings; int side; uint landing; uint status; uint pad1; uint pad2; uint pad3;
    };
    struct RayResult {
        uint outcome; uint crossingIndex; uint face; float radius;
        float u; float vu; float mu; float vmu; float phi;
        float maxResidual; uint steps; uint pad;
    };
    struct KernelParameters {
        float spin; float skyU; float horizonU; float captureU;
        float diskInner; float diskOuter; float relativeTolerance; float absoluteTolerance;
        uint rayCount; uint stepsPerPass; uint stepBudget; uint maxCrossings;
        float angleTolerance; float polarFlagSin2; uint pad2; uint pad3;
    };

    constant uint OUTCOME_CAPTURED = 1u;
    constant uint OUTCOME_DISK = 2u;
    constant uint OUTCOME_SKY = 3u;
    constant uint OUTCOME_BUDGET = 4u;
    constant uint OUTCOME_FAILURE = 5u;

    // ---- Per-ray constants (E = 1).
    struct Ctx {
        float a; float a2; float L; float Q;
        float K;          // (L - aE)^2 + Q
        float aaeMinusL;  // a (aE - L)
        float polarCoeff; // a^2 E^2 - Q - L^2
    };

    inline Ctx makeCtx(float a, float L, float Q) {
        Ctx c;
        c.a = a; c.a2 = a * a; c.L = L; c.Q = Q;
        float la = L - a;
        c.K = la * la + Q;
        c.aaeMinusL = a * (a - L);
        c.polarCoeff = c.a2 - Q - L * L;
        return c;
    }

    // ---- State: (u, du/dl', mu, dmu/dl') in q and phi in p.
    struct S { float4 q; float p; };
    inline S operator+(S a, S b) { S r; r.q = a.q + b.q; r.p = a.p + b.p; return r; }
    inline S operator-(S a, S b) { S r; r.q = a.q - b.q; r.p = a.p - b.p; return r; }
    inline S operator*(S a, float s) { S r; r.q = a.q * s; r.p = a.p * s; return r; }
    inline S operator*(float s, S a) { S r; r.q = a.q * s; r.p = a.p * s; return r; }

    // State derivative with respect to l' = -lambda (see RayState in the Swift sources).
    inline S deriv(S y, thread const Ctx &c) {
        float u = y.q.x;
        float mu = y.q.z;
        float u2 = u * u;
        float pTilde = 1.0f + c.aaeMinusL * u2;                 // P / r^2
        float deltaTilde = 1.0f - 2.0f * u + c.a2 * u2;          // Delta / r^2
        float sin2 = 1.0f - mu * mu;
        float axis = (c.L == 0.0f) ? 0.0f : c.L / max(sin2, 1e-30f);
        S d;
        d.q.x = y.q.y;
        d.q.y = 2.0f * c.aaeMinusL * u * pTilde - c.K * u * (1.0f - 3.0f * u + 2.0f * c.a2 * u2);  // R~'(u) / 2
        d.q.z = y.q.w;
        d.q.w = mu * (c.polarCoeff - 2.0f * c.a2 * mu * mu);       // Theta_mu'(mu) / 2
        d.p = -(axis - c.a + c.a * pTilde / deltaTilde);            // phi'
        return d;
    }

    // Normalized first-integral residual, max(delta_r, delta_mu).
    inline float residualOf(S y, thread const Ctx &c) {
        float u = y.q.x, mu = y.q.z;
        float u2 = u * u;
        float pTilde = 1.0f + c.aaeMinusL * u2;
        float deltaTilde = 1.0f - 2.0f * u + c.a2 * u2;
        float radial = pTilde * pTilde - deltaTilde * c.K * u2;
        float m2 = mu * mu;
        float polar = c.Q + m2 * (c.polarCoeff - c.a2 * m2);
        float radialScale = (1.0f + c.a2 * u2) * (1.0f + c.a2 * u2);
        float polarScale = c.Q + c.L * c.L + c.a2 + 1e-12f;
        return max(abs(y.q.y * y.q.y - radial) / radialScale, abs(y.q.w * y.q.w - polar) / polarScale);
    }

    struct Step { S y; S err; S k7; };

    // Dormand-Prince 5(4), k1 = f(y) supplied (FSAL).
    inline Step dp5(S y, float h, S k1, thread const Ctx &c) {
        S k2 = deriv(y + (h * (1.0f / 5.0f)) * k1, c);
        S k3 = deriv(y + h * ((3.0f / 40.0f) * k1 + (9.0f / 40.0f) * k2), c);
        S k4 = deriv(y + h * ((44.0f / 45.0f) * k1 - (56.0f / 15.0f) * k2 + (32.0f / 9.0f) * k3), c);
        S k5 = deriv(y + h * ((19372.0f / 6561.0f) * k1 - (25360.0f / 2187.0f) * k2 + (64448.0f / 6561.0f) * k3
                              - (212.0f / 729.0f) * k4), c);
        S k6 = deriv(y + h * ((9017.0f / 3168.0f) * k1 - (355.0f / 33.0f) * k2 + (46732.0f / 5247.0f) * k3
                              + (49.0f / 176.0f) * k4 - (5103.0f / 18656.0f) * k5), c);
        Step s;
        s.y = y + h * ((35.0f / 384.0f) * k1 + (500.0f / 1113.0f) * k3 + (125.0f / 192.0f) * k4
                       - (2187.0f / 6784.0f) * k5 + (11.0f / 84.0f) * k6);
        s.k7 = deriv(s.y, c);
        s.err = h * ((71.0f / 57600.0f) * k1 - (71.0f / 16695.0f) * k3 + (71.0f / 1920.0f) * k4
                     - (17253.0f / 339200.0f) * k5 + (22.0f / 525.0f) * k6 - (1.0f / 40.0f) * s.k7);
        return s;
    }

    // The radial pair (u, du/dl') uses the relative tolerance; the angular components (mu, dmu/dl', phi), which alone
    // fix the final direction of a ray, use the tighter angleTolerance (relative, with the same absolute floor).
    inline float scaledError(S err, S y, S yn, constant KernelParameters &P) {
        float atol = P.absoluteTolerance;
        float2 radial = abs(err.q.xy) / (atol + P.relativeTolerance * max(abs(y.q.xy), abs(yn.q.xy)));
        float2 polar = abs(err.q.zw) / (atol + P.angleTolerance * max(abs(y.q.zw), abs(yn.q.zw)));
        float azimuth = abs(err.p) / (atol + P.angleTolerance * max(abs(y.p), abs(yn.p)));
        return max(max(radial.x, radial.y), max(max(polar.x, polar.y), azimuth));
    }

    // Locates mu = 0 inside the accepted step previous -> (previous + hStep) and returns the state there. A cubic
    // Hermite interpolant of mu gives the starting fraction (bisection); one Newton correction with a real
    // Dormand-Prince step makes the root accurate to the integrator's tolerance (mirrors RayTracer.refine).
    inline S refineCrossing(S previous, S kPrev, float hStep, float m1, float d1Rate, thread const Ctx &c) {
        float m0 = previous.q.z;
        float d0 = previous.q.w * hStep, d1 = d1Rate * hStep;
        float lo = 0.0f, hi = 1.0f;
        float flo = m0;
        for (int i = 0; i < 24; ++i) {
            float mid = 0.5f * (lo + hi);
            float s2 = mid * mid, s3 = s2 * mid;
            float fm = (2.0f * s3 - 3.0f * s2 + 1.0f) * m0 + (s3 - 2.0f * s2 + mid) * d0
                     + (-2.0f * s3 + 3.0f * s2) * m1 + (s3 - s2) * d1;
            if ((fm > 0.0f) == (flo > 0.0f)) { lo = mid; flo = fm; } else { hi = mid; }
        }
        float f = 0.5f * (lo + hi);
        for (int i = 0; i < 2; ++i) {
            Step t = dp5(previous, f * hStep, kPrev, c);
            float slope = t.y.q.w * hStep;
            if (slope == 0.0f) break;
            f = clamp(f - t.y.q.z / slope, 0.0f, 1.0f);
        }
        return dp5(previous, f * hStep, kPrev, c).y;
    }

    // ---- Kernels.
    kernel void initializeStates(constant KernelParameters &P [[buffer(0)]],
                                 device const RayInput *inputs [[buffer(1)]],
                                 device RayState *states [[buffer(2)]],
                                 device RayResult *results [[buffer(3)]],
                                 uint gid [[thread_position_in_grid]]) {
        if (gid >= P.rayCount) return;
        RayInput in = inputs[gid];
        Ctx c = makeCtx(P.spin, in.L, in.Q);
        S y; y.q = float4(in.u, in.vu, in.mu, in.vmu); y.p = in.phi;
        RayState s;
        s.u = in.u; s.vu = in.vu; s.mu = in.mu; s.vmu = in.vmu; s.phi = in.phi;
        s.step = 1e-3f;
        s.maxResidual = residualOf(y, c);
        s.minSin2 = 1.0f - in.mu * in.mu;
        s.steps = 0u; s.crossings = 0u;
        s.side = (in.mu > 0.0f) ? 1 : ((in.mu < 0.0f) ? -1 : 0);
        s.landing = 0u; s.status = 0u; s.pad1 = 0u; s.pad2 = 0u; s.pad3 = 0u;
        states[gid] = s;
        RayResult r;
        r.outcome = 0u; r.crossingIndex = 0u; r.face = 0u; r.radius = 0.0f;
        r.u = in.u; r.vu = in.vu; r.mu = in.mu; r.vmu = in.vmu; r.phi = in.phi;
        r.maxResidual = s.maxResidual; r.steps = 0u; r.pad = 0u;
        results[gid] = r;
    }

    kernel void traceRays(constant KernelParameters &P [[buffer(0)]],
                          device const RayInput *inputs [[buffer(1)]],
                          device RayState *states [[buffer(2)]],
                          device RayResult *results [[buffer(3)]],
                          device atomic_uint *unfinished [[buffer(4)]],
                          uint gid [[thread_position_in_grid]]) {
        if (gid >= P.rayCount) return;
        RayState st = states[gid];
        if (st.status == 1u) return;
        RayInput in = inputs[gid];
        Ctx c = makeCtx(P.spin, in.L, in.Q);

        S y; y.q = float4(st.u, st.vu, st.mu, st.vmu); y.p = st.phi;
        S k1 = deriv(y, c);
        float h = st.step;
        float maxRes = st.maxResidual;
        float minSin2 = st.minSin2;
        uint steps = st.steps;
        uint landing = st.landing;
        uint crossings = st.crossings;
        int side = st.side;
        uint face = 0u;
        float hitRadius = 0.0f;
        uint outcome = 0u;
        uint iterations = 0u;

        while (outcome == 0u && iterations < P.stepsPerPass) {
            iterations += 1u;
            if (steps >= P.stepBudget) { outcome = OUTCOME_BUDGET; break; }

            // Keep the stages of an inward step outside the horizon; land just beyond the sky radius going out.
            float hTry = h;
            if (y.q.y > 0.0f) {
                hTry = min(hTry, 0.4f * (P.horizonU - y.q.x) / y.q.y);
            } else if (y.q.y < 0.0f && y.q.x > P.skyU) {
                hTry = min(hTry, 3.0f * (y.q.x - P.skyU) / (-y.q.y));
            }

            Step s = dp5(y, hTry, k1, c);
            float en = scaledError(s.err, y, s.y, P);

            if (isfinite(en) && en <= 1.0f) {
                // Landing: shorten a step that crosses the sky radius until it ends within 1e-6 (relative) of it.
                if (y.q.y < 0.0f && s.y.q.x < P.skyU * (1.0f - 1e-6f) && landing < 12u) {
                    landing += 1u;
                    h = hTry * (y.q.x - P.skyU) / (y.q.x - s.y.q.x);
                    continue;
                }
                landing = 0u;
                steps += 1u;
                S previous = y;
                S kPrev = k1;
                y = s.y;
                k1 = s.k7;
                maxRes = max(maxRes, residualOf(y, c));
                minSin2 = min(minSin2, 1.0f - y.q.z * y.q.z);
                if (y.q.x >= P.captureU) { outcome = OUTCOME_CAPTURED; break; }
                if (y.q.x <= P.skyU && y.q.y < 0.0f) { outcome = OUTCOME_SKY; break; }
                if (crossings < P.maxCrossings) {
                    int newSide = (y.q.z > 0.0f) ? 1 : ((y.q.z < 0.0f) ? -1 : 0);
                    if (side == 0) {
                        side = newSide;  // leaving the plane from the start is not a crossing
                    } else if (newSide != 0 && newSide != side) {
                        S at = refineCrossing(previous, kPrev, hTry, y.q.z, y.q.w, c);
                        float radius = 1.0f / at.q.x;
                        crossings += 1u;
                        uint fromSide = (side > 0) ? 0u : 1u;
                        side = newSide;
                        if (radius >= P.diskInner && radius <= P.diskOuter) {
                            outcome = OUTCOME_DISK; face = fromSide; hitRadius = radius;
                            break;
                        }
                    }
                }
                float factor = (en == 0.0f) ? 5.0f : min(5.0f, max(0.2f, 0.9f * pow(en, -0.2f)));
                h = hTry * factor;
            } else {
                float factor = isfinite(en) ? max(0.2f, 0.9f * pow(en, -0.2f)) : 0.2f;
                h = hTry * factor;
                if (h < 1e-9f) { outcome = OUTCOME_FAILURE; break; }
            }
        }

        if (outcome != 0u) {
            RayResult r;
            r.outcome = outcome; r.crossingIndex = (outcome == OUTCOME_DISK) ? crossings : 0u; r.face = face; r.radius = hitRadius;
            // face: bit 0 = lower face (disk hits); bit 1 = delicate (the path came close to a pole, where float32
            // cannot follow phi accurately; the host re-traces such rays in float64).
            r.face |= (minSin2 < P.polarFlagSin2) ? 2u : 0u;
            r.u = y.q.x; r.vu = y.q.y; r.mu = y.q.z; r.vmu = y.q.w; r.phi = y.p;
            r.maxResidual = maxRes; r.steps = steps; r.pad = 0u;
            results[gid] = r;
            st.status = 1u;
        } else {
            atomic_fetch_add_explicit(unfinished, 1u, memory_order_relaxed);
        }
        st.u = y.q.x; st.vu = y.q.y; st.mu = y.q.z; st.vmu = y.q.w; st.phi = y.p; st.minSin2 = minSin2;
        st.step = h; st.maxResidual = maxRes; st.steps = steps; st.landing = landing;
        st.crossings = crossings; st.side = side;
        states[gid] = st;
    }

    #ifdef BHSIM_TEST_KERNELS
    // ---- Test-only kernels (unit tests compare these with the CPU implementation).
    kernel void queryLayout(device uint *out [[buffer(0)]], uint gid [[thread_position_in_grid]]) {
        if (gid != 0u) return;
        out[0] = sizeof(RayInput); out[1] = sizeof(RayState); out[2] = sizeof(RayResult); out[3] = sizeof(KernelParameters);
        out[4] = __builtin_offsetof(RayState, steps); out[5] = __builtin_offsetof(RayState, crossings);
        out[6] = __builtin_offsetof(RayState, side); out[7] = __builtin_offsetof(RayState, landing);
        out[8] = __builtin_offsetof(RayState, status);
        out[9] = __builtin_offsetof(RayResult, radius); out[10] = __builtin_offsetof(RayResult, u);
        out[11] = __builtin_offsetof(RayResult, maxResidual); out[12] = __builtin_offsetof(RayResult, steps);
        out[13] = __builtin_offsetof(KernelParameters, rayCount); out[14] = __builtin_offsetof(KernelParameters, maxCrossings);
    }

    // Input record per case: a, L, Q, u, vu, mu, vmu, phi, h (9 floats). Output: 10 floats (5 + 5).
    inline S caseState(device const float *in, thread Ctx &c) {
        c = makeCtx(in[0], in[1], in[2]);
        S y; y.q = float4(in[3], in[4], in[5], in[6]); y.p = in[7];
        return y;
    }
    kernel void testDerivative(device const float *in [[buffer(0)]], device float *out [[buffer(1)]], uint gid [[thread_position_in_grid]]) {
        Ctx c; S y = caseState(in + gid * 9u, c);
        S d = deriv(y, c);
        device float *o = out + gid * 10u;
        o[0] = d.q.x; o[1] = d.q.y; o[2] = d.q.z; o[3] = d.q.w; o[4] = d.p;
    }
    kernel void testStep(device const float *in [[buffer(0)]], device float *out [[buffer(1)]], uint gid [[thread_position_in_grid]]) {
        Ctx c; S y = caseState(in + gid * 9u, c);
        Step s = dp5(y, in[gid * 9u + 8u], deriv(y, c), c);
        device float *o = out + gid * 10u;
        o[0] = s.y.q.x; o[1] = s.y.q.y; o[2] = s.y.q.z; o[3] = s.y.q.w; o[4] = s.y.p;
        o[5] = s.err.q.x; o[6] = s.err.q.y; o[7] = s.err.q.z; o[8] = s.err.q.w; o[9] = s.err.p;
    }
    kernel void testResidual(device const float *in [[buffer(0)]], device float *out [[buffer(1)]], uint gid [[thread_position_in_grid]]) {
        Ctx c; S y = caseState(in + gid * 9u, c);
        out[gid] = residualOf(y, c);
    }
    #endif
    """#
}
