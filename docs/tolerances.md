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
