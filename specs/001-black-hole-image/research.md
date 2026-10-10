# Research: Physically Accurate Black Hole Image

All Technical Context unknowns are resolved below. Equations are cited so each can be checked against its source (Constitution Principles I and II).

## Conventions (Principle II)

- Units: geometrized, G = c = 1, black hole mass M = 1 for all internal computation. Physical scale (solar masses, accretion rate) enters only at the radiometry/output boundary.
- Spacetime: Kerr, Boyer–Lindquist coordinates (t, r, θ, φ), signature (−,+,+,+), spin a = J/M with 0 ≤ a < 1 along +z.
- Definitions: Σ = r² + a²cos²θ, Δ = r² − 2r + a², horizon r₊ = 1 + √(1 − a²).
- Photon constants of motion: E = −p_t, L = p_φ, Carter constant Q. Carter's potentials: R(r) = [E(r²+a²) − aL]² − Δ[(L − aE)² + Q]; Θ(θ) = Q + a²E²cos²θ − L²cot²θ.
- Physical constants (needed only for temperature scale): CODATA 2018 or newer, recorded in code with source.

## Decisions

### D1. Language and platform

- **Decision**: Swift 6.4 on macOS 14+, Apple Silicon. Library plus CLI in one Swift package.
- **Rationale**: Native toolchain is installed (Swift 6.4, `swift test` verified). One language covers the float64 CPU reference, ImageIO output (PNG and OpenEXR, both verified writable here), and Metal later without a language boundary. No dependency on Python environments or a Rust toolchain (not installed).
- **Alternatives**: Python with NumPy/Numba (fast to prototype, but slower per-ray and no direct GPU path); Rust (good performance, toolchain not installed, no native Metal); C++ (works, but more build-system friction and no testing framework out of the box).

### D2. Geodesic formulation

- **Decision**: Integrate in Mino time λ (dλ = dτ_affine / Σ) using the second-order forms d²r/dλ² = R′(r)/2 and d²μ/dλ² = Θ_μ′(μ)/2 with μ = cos θ, where (dμ/dλ)² = Θ_μ(μ) = (1 − μ²)(Q + a²E²μ²) − L²μ². Coordinates φ and t advance by dφ/dλ = L/(1 − μ²) − aE + a[E(r²+a²) − aL]/Δ and dt/dλ = a(L − aE(1 − μ²)) + (r²+a²)[E(r²+a²) − aL]/Δ.
- **Rationale**: E, L, Q are constants fixed at launch, so there is no drift in them; accuracy is monitored by the first-integral residuals (dr/dλ)² − R(r) and (dμ/dλ)² − Θ_μ(μ), which implements the spec's FR-008 conserved-quantity check. With E = 1, the normalized residuals are δ_r = |ṙ² − R|/(r²+a²)² and δ_μ = |μ̇² − Θ_μ|/(Q + L² + a²). Second-order forms pass smoothly through radial and polar turning points (no sign-flip logic). Using μ instead of θ removes the coordinate singularity on the spin axis. The 1/Δ terms are singular only at the horizon, where rays are terminated.
- **Alternatives**: Hamiltonian integration in (r, θ) (simple, but pole singularity and turning-point handling are awkward, and E, L, Q are only approximately conserved); Kerr–Schild coordinates (regular at the horizon, but the geodesic equations are costlier); closed-form elliptic-integral solutions (Gralla & Lupsasca 2020; exact and fast, but considerably more complex). The elliptic solution is kept as a possible independent cross-check, not a dependency.

### D3. Integrator

- **Decision**: Adaptive Dormand–Prince 5(4), float64, with relative tolerance ~1e-10 as the starting value (final value set by the step-size convergence test), integrating the 6-component state (r, dr/dλ, μ, dμ/dλ, φ, t) backward from the observer. Termination: (a) r ≤ r₊ + 1e-3 → horizon; (b) disk-annulus hit (D5); (c) r ≥ r_sky with dr/dλ > 0 → sky; (d) step budget exhausted → flagged as unresolved. Unresolved samples are excluded from pixel averaging and counted in the diagnostics; a pixel whose samples are all unresolved is black and counted; more than 0.1% unresolved rays gives exit code 4.
- **Rationale**: Well understood, embedded error control, dense output is not required (plane crossings are refined by a local root-find on the last step). Mino time makes the step near the horizon finite, so no special handling beyond the cutoff.
- **Alternatives**: Fixed-step RK4 (cannot bound error near the photon sphere); Gauss–Radau or symplectic schemes (benefit is energy preservation for massive orbits, little gain for null rays whose invariants are exact here).

### D4. Observer and camera (spec FR-002a)

- **Decision**: Static observer at (r_o, θ_o). Orthonormal tetrad by Gram–Schmidt on (∂_t, ∂_r, ∂_θ, ∂_φ): e₀ = ∂_t/√(−g_tt); e_r ∝ ∂_r; e_θ ∝ ∂_θ; e_φ ∝ ∂_φ + (g_tφ/(−g_tt))∂_t, normalized. Pinhole camera looks along −e_r, with up = −e_θ (toward the spin axis). A pixel at angular offsets maps to a unit direction n in the tetrad, giving local photon momentum p^(a) = ω(1, n) with ω = 1 (overall scale is irrelevant to the path). Covariant components give E, L, Q.
- **Validity**: A static observer exists only outside the ergosphere, r_o > 1 + √(1 − a²cos²θ_o); inputs violating this are rejected (spec edge case).
- **Alternatives**: ZAMO observer (always exists outside the horizon, but is not static, contradicting the clarified spec); observer at infinity (rejected in clarification).

### D5. Accretion disk

- **Decision**: Geometrically thin, optically thick, equatorial (θ = π/2), prograde Keplerian rotation, annulus from the innermost stable circular orbit r_isco to a configurable r_out (default 20 M). Both faces emit identically.
  - ISCO (Bardeen, Press & Teukolsky 1972): Z₁ = 1 + (1−a²)^(1/3)[(1+a)^(1/3) + (1−a)^(1/3)], Z₂ = √(3a² + Z₁²), r_isco = 3 + Z₂ − √((3−Z₁)(3+Z₁+2Z₂)).
  - Angular velocity: Ω = 1/(r^(3/2) + a).
  - Flux: Novikov–Thorne / Page & Thorne (1974) F(r), with zero-torque inner boundary at r_isco; T(r) = (F/σ_SB)^(1/4).
  - Shift factor: g = (−p·u_obs)/(−p·u_em), with u_em = u^t(1, 0, 0, Ω), u^t = [−g_tt − 2Ωg_tφ − Ω²g_φφ]^(−1/2), so −p·u_em = u^t(E − ΩL); the static observer gives −p·u_obs = E/√(−g_tt).
  - Observed emission: since I_ν/ν³ is invariant along rays, a blackbody of temperature T is observed as an exact blackbody of temperature gT, with bolometric intensity g⁴σT⁴/π.
  - Hit detection: a sign change of μ between steps marks a plane crossing; the crossing point is refined by a local bracketed root-find. The crossing counts toward the 3-crossing budget. If the crossing radius lies in [r_isco, r_out], the ray terminates there (the disk is opaque); otherwise tracing continues.
- **Rationale**: Directly implements the clarified spec (Novikov–Thorne, 3 crossings) with an exact, closed-form color/brightness mapping, no radiative-transfer approximation needed for an opaque blackbody disk.
- **Independent check**: F(r) is verified against a direct numerical evaluation of the conservation-law integral form, F = Ṁ/(4π√−g)·f·(E−ΩL)^(−2) ∫(E−ΩL) L_,r dr, and against the Schwarzschild closed form.

### D6. Background sky (spec FR-005)

- **Decision**: Rays that reach r_sky are assigned their asymptotic direction, taken as their direction of travel in the static orthonormal frame at r_sky, with components (v_r, v_θ, v_φ) converted to the Cartesian unit vector v_r r̂ + v_θ θ̂ + v_φ φ̂. (A point's position direction differs from the asymptotic direction by about b/r_sky, so position is not used.) Default sky is a seeded procedural star field: N stars drawn uniformly on the sphere with blackbody colors from a documented temperature distribution and a documented brightness distribution. Each star is a small angular disc of constant surface brightness, so lensing magnifies the star's apparent size and flux automatically (surface brightness is conserved). The selectable reference pattern is a celestial latitude/longitude grid.
- **Rationale**: Treating stars as discs rather than points makes lensing magnification emerge from sampling, which is physically correct and needs no analytic Jacobian.
- **Approximation**: Stopping at finite r_sky and treating the direction of travel there as asymptotic. The bending remaining beyond r_sky is about M·b/r_sky². With r_sky = max(1000, 10 r_o) M this is at most about 1e-4 rad for b up to 100 M. It is bounded by the sky-direction test (Validation 11) against the exact Schwarzschild deflection.

### D7. Radiometry and output

- **Decision**: Spectrum → CIE 1931 XYZ (2° observer) by numerical integration of the Planck spectrum at temperature gT → linear sRGB (Rec. 709 primaries, D65). HDR output stores linear values in units of a documented reference radiance (recorded in metadata). Display PNG applies a documented exposure plus tone-mapping curve and sRGB transfer function.
- **File formats**: PNG and 32-bit float OpenEXR via ImageIO (both confirmed writable on the target machine). Metadata JSON sidecar records all inputs, seed, version, units, reference radiance and diagnostics.
- **Alternatives**: Radiance .hdr (shared 8-bit exponent loses precision); TIFF float (less common in viewers).

### D8. Determinism and parallelism

- **Decision**: Tile the image; render tiles with `DispatchQueue.concurrentPerform`. Each pixel's sub-sample jitter is a pure function of (seed, pixel index, sample index), and each pixel is computed independently, so output is independent of thread count and scheduling.
- **Rationale**: Satisfies FR-009 and SC-006 by construction.

### D9. Mac acceleration (Metal)

- **Decision**: CPU float64 is the reference and the first deliverable. A Metal compute backend is optional, added only if measured CPU time misses SC-005.
- **Findings on this machine**: Apple M4, Metal device present, runtime shader compilation from source works (the offline `metal` compiler is not installed, so no precompiled `.metallib` build step is needed).
- **Constraint**: Apple GPUs have no float64. The GPU path must therefore run float32 and would be enabled only if it reproduces the CPU reference within the SC-003/SC-001 tolerances on the validation suite. Likely mitigations: smaller steps near the photon sphere, compensated arithmetic for r and μ, or computing only the ray integration on the GPU and shading on the CPU.
- **Alternatives**: Accelerate/SIMD vectorization on CPU (viable first optimization, no precision loss); keep CPU-only if fast enough.

## Approximations (Principle I)

| Approximation | Governing assumption | Validity | Error / control |
|---|---|---|---|
| Thin, equatorial, opaque disk | H/r ≪ 1; optically thick | Radiatively efficient thin disks (sub-Eddington) | Geometric thickness neglected; documented in user docs |
| Blackbody emission at Novikov–Thorne T | Local thermal equilibrium, no color correction | Qualitative color accuracy; no spectral hardening | Out of scope per spec |
| Prograde circular Keplerian disk motion | No radial infall inside r_isco emission (zero torque, zero flux there) | Emission from r ≥ r_isco | Matches Novikov–Thorne boundary |
| Finite ray-termination radius | Rays beyond r_sky travel straight; direction of travel at r_sky is used | Remaining bending about M·b/r_sky² (≲ 1e-4 rad at b = 100 M) | Sky-direction test vs. exact deflection |
| Horizon cutoff at r₊ + 1e-3 | Rays that reach this radius are captured | Photons that near the horizon cannot return | Negligible; rays here are black by definition |
| Neglected beyond 3 plane crossings | Contributions from higher-order images are small and thin | Visible as slightly under-resolved photon ring | See Risks |
| Star discs of constant surface brightness | Stars unresolved in reality | Illustrative sky | Documented as synthetic |

## Validation (Principle III)

Tests are written before the corresponding physics code.

1. **Horizon / ISCO / photon sphere**: r₊ = 2 (a=0); r_isco = 6 (a=0), 1 (a→1 prograde, within tolerance), 9 (a=0 retrograde reference if implemented); photon sphere r = 3 (a=0).
2. **Critical impact parameter**: a=0: b_c = 3√3; rays launched at b slightly below and above are captured/escape.
3. **Weak-field deflection**: for large b, α ≈ 4M/b within 1% (with higher-order correction 15π/4·(M/b)² as a tighter check).
4. **First-integral residuals**: relative residual of (dr/dλ)² − R and (dμ/dλ)² − Θ_μ stays below 1e-6 in the integrator tests (and below the SC-003 bound of 1e-3 for at least 99.9% of rays in full renders), using the normalized definitions in D2, along representative rays (including near-critical and near-axis rays); step-size/tolerance refinement converges.
5. **Kerr shadow**: for a=0.9, a given inclination, shadow outline vs. the analytic curve from the spherical photon-orbit conditions (Bardeen 1973); tolerance 2% (SC-002).
6. **Rendered shadow radius**: a=0 image, shadow radius measured in the HDR output vs. 3√3 within 1% (SC-001).
7. **Disk flux**: F(r) vs. independent numerical integral; Schwarzschild closed form; F = 0 at r_isco.
8. **shift-factor spot checks**: analytic values at selected points (e.g., face-on gravitational redshift only, edge-on approaching/receding limbs).
9. **Determinism**: identical outputs for repeated runs and for different thread counts (SC-006).
10. **Axis/edge cases**: observer on the axis, spin at the limit, observer inside the ergosphere or horizon all behave per the spec edge cases.
11. **Sky direction**: for Schwarzschild rays at several impact parameters, the direction assigned at r_sky matches the exact asymptotic exit direction (from numerical quadrature in `tools/reference/schwarzschild_deflection.py`) within 1e-3 rad.

## Risks

- **Photon ring truncation**: capping at 3 plane crossings (clarification Q5) means n ≥ 4 sub-rings are not drawn. The visible photon ring is the superposition of the n = 2 and 3 images and is slightly dimmer than the full ring. This is documented as a known limit, not hidden.
- **Performance estimate is unmeasured**: the CPU estimate must be benchmarked early (a single-row render) before committing to supersampling defaults.
- **Float32 GPU accuracy** may not meet SC-003; mitigation above, and CPU remains the reference.
- **Near-critical rays** take many steps; the step budget and the "unresolved" count must be reported so they cannot silently bias the image.

## References

- Carter (1968), Bardeen (1973), Bardeen–Press–Teukolsky (1972): Kerr geodesics, shadow, ISCO.
- Novikov & Thorne (1973), Page & Thorne (1974): relativistic thin-disk flux.
- Luminet (1979), James et al. (2015, "Gravitational lensing by spinning black holes in astrophysics, and in the movie Interstellar"): reference lensed disk images.
- Gralla & Lupsasca (2020): analytic Kerr null geodesics and photon-ring structure.
- Dexter & Agol (2009): efficient Kerr photon tracing.
