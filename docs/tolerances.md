# Numeric tolerances

Every numeric tolerance used by a test or diagnostic, with its source. Tests refer to this table instead
of hard-coding unexplained numbers. A tolerance may be tightened freely. It may be loosened only with a
written physical justification in the "Justification" column (Constitution Principle III).

Values marked *provisional* are initial proposals to be confirmed by measurement (task T014).

| Quantity | Tolerance | Source | Status | Justification |
|----------|-----------|--------|--------|---------------|
| Non-spinning shadow angular radius vs. arcsin(3√3·√(1−2/r)/r) | 1 % | SC-001 | fixed | |
| Spin 0.9 shadow outline vs. analytic Kerr outline | 2 % | SC-002 | fixed | |
| Normalized first-integral residual in full renders | < 1e-3 for ≥ 99.9 % of rays | SC-003 | fixed | |
| Weak-field deflection vs. 4M/b | 1 % | SC-004 | fixed | |
| Unresolved rays in a full render | < 0.1 % | plan / cli.md exit code 4 | fixed | |
| Normalized first-integral residual in integrator tests | < 1e-6 | plan.md | confirmed (T014) | Measured worst case 1.9e-9 over 18 scenarios |
| Final-angle change when integrator tolerance is tightened 10× | < 1e-6 rad | plan.md | confirmed (T014) | Measured worst case 1.3e-9 rad |
| Sky direction at r_sky = 1000 vs. exact asymptotic direction (b ≤ 50) | < 2e-4 rad | research D6 | confirmed (T032) | Measured worst case 5.0e-5 rad (b = 50), matching the estimate M·b/r_sky²; the naive position direction is off by ≈ b/r_sky ≈ 1e-2 rad |
| Swift closed-form disk flux vs. 30-digit reference | 1e-10 for r > 1.05 r_isco, 1e-6 closer in | research D5 | confirmed (T051) | Measured 3.6e-14 and 8.3e-11; closed form and conservation integral agree to 1e-25 |

## GPU backend (float32; feature 002)

The GPU kernel runs in 32-bit floating point; the CPU float64 backend remains the reference. Evidence: `specs/002-metal-gpu-backend/research.md` §Spike S1 results.

| Quantity | Tolerance | Source | Status | Justification |
|----------|-----------|--------|--------|---------------|
| Kernel step control, radial pair (u, du/dλ′) | relative 1e-5, absolute 1e-8 | research D2 | chosen (T022) | Float32 has ~6e-8 relative resolution; 1e-5 leaves two orders of margin and gave 99.9 %+ outcome agreement |
| Kernel step control, angular components (μ, dμ/dλ′, φ) | relative 1e-6 | research S1 | chosen (T022) | These alone fix a ray's final direction; at 1e-5 the sky direction was off by up to 0.03 rad for 3–5 % of rays, and the same errors appear in float64 at 1e-5, so this is a step-control choice, not a float32 limit |
| Polar flag: rays with sin²θ < 0.02 anywhere on the path | re-traced on the CPU in float64 | research S1, M3 | chosen (T022) | Float32 cannot follow φ accurately past a pole (conditioning floor of dφ/dμ); such rays are not trusted on the GPU |
| GPU vs. CPU: same ray outcome | ≥ 99.9 % | FR-003 | fixed | |
| GPU vs. CPU: disk crossing radius, 99th percentile | < 1e-3 relative | FR-003 | fixed | |
| GPU vs. CPU: sky direction | ≤ 1e-4 rad for ≥ 99.9 % of sky rays | FR-003 | fixed | |
| GPU vs. CPU: disk/horizon pixel radiance, 99th percentile | < 1 % (relative to max(reference, 1e-3 × peak)) | FR-003 | fixed | |
