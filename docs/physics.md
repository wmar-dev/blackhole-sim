# Physics reference

What the renderer computes, in what units, with which equations, and where it approximates. A narrative
explanation with a worked example is in [how-it-works.md](how-it-works.md). Derivations and
design decisions are in [specs/001-black-hole-image/research.md](../specs/001-black-hole-image/research.md);
numeric tolerances in [tolerances.md](tolerances.md).

## Units and conventions

- Geometrized units G = c = 1, black hole mass M = 1. Lengths are in GM/c², times in GM/c³.
- Kerr spacetime in Boyer–Lindquist coordinates (t, r, θ, φ), signature (−, +, +, +), spin a = J/M along +z,
  0 ≤ a < 1. μ = cos θ.
- Σ = r² + a²μ², Δ = r² − 2r + a², horizon r₊ = 1 + √(1 − a²).
- Photon constants of motion: E = −p_t, L = p_φ, Carter constant Q. Only ratios matter, so rays are
  normalized to E = 1.
- Physical units appear only at the radiometry boundary (disk temperature scale), from CODATA 2018
  constants and the IAU nominal GM☉ (`PhysicalConstants`).

## Governing equations

**Carter potentials.** With P(r) = E(r² + a²) − aL and K = (L − aE)² + Q:

    R(r)   = P² − Δ K                 radial
    Θ_μ(μ) = (1 − μ²)(Q + a²E²μ²) − L²μ²     polar, a polynomial in μ² (regular on the spin axis)

**Geodesics in Mino time** (dλ = dσ/Σ). The ray is traced *backward* from the observer, so the integration
variable is λ′ = −λ. The radial coordinate is carried as u = 1/r, which keeps u, u′ and φ′ of order one from the
sky radius to the horizon (the first implementation, in r, lost absolute accuracy at large r):

    u″ = R̃′(u)/2,  R̃(u) = R/r⁴ = p̃² − δ̃ K u²,  p̃ = E + a(aE − L)u²,  δ̃ = 1 − 2u + a²u²
    μ″ = Θ_μ′(μ)/2
    φ′ = −[ L/(1 − μ²) − aE + a P/Δ ]

The second-order forms pass smoothly through turning points. The first integrals (u′)² = R̃(u) and
(μ′)² = Θ_μ(μ) are conserved by the exact flow; their drift is the integration-accuracy diagnostic
(δ_r = |u′² − R̃| / (E²(1 + a²u²)²), δ_μ = |μ′² − Θ_μ| / (Q + L² + a²E²); SC-003).

**Integrator.** Adaptive Dormand–Prince 5(4), float64, relative tolerance 10⁻⁹, absolute 10⁻¹²; the last step
is shortened (secant on u) to land on the sky radius. Rays stop at r ≤ r₊ + 10⁻³ (captured), at the sky
radius max(1000, 10 r_observer) moving outward, or at a step budget (unresolved).

**Observer and camera.** A static observer's orthonormal frame is built by Gram–Schmidt on (∂_t, ∂_r, ∂_θ, ∂_φ):

    e₀ = ∂_t/√(−g_tt),  e_r = ∂_r/√g_rr,  e_θ = ∂_θ/√g_θθ,
    e_φ = [∂_φ + (g_tφ/(−g_tt)) ∂_t] / √(g_φφ + g_tφ²/(−g_tt))

It exists only outside the ergosphere. A pinhole camera looks along −r̂ with up = −θ̂ (toward the spin axis)
and right = +φ̂. The physical photon from a pixel travels along −n; its (E, L, Q) follow from the covariant
momentum in this frame. The side of the image on the left is therefore where the disk gas approaches the
observer.

**Plane crossings and the disk.** A change of sign of μ between accepted steps is a crossing of the
equatorial plane; the crossing point is refined with a Hermite interpolant plus one Newton correction. The disk is
opaque, so a ray ends at its first crossing inside [r_isco, r_out]. At most 3 crossings per ray are tested.

**Disk emission** (Novikov & Thorne 1973; Page & Thorne 1974). Prograde circular geodesics,
Ω = 1/(r^{3/2} + a), with r_isco from Bardeen, Press & Teukolsky (1972). Flux per face with zero torque at
r_isco (x = √r, x₀ = √r_isco, x₁, x₂, x₃ the roots of x³ − 3x + 2a = 0):

    F = (3 Ṁ / 8π M²) · [ x − x₀ − (3/2) a ln(x/x₀) − Σᵢ 3(xᵢ − a)² / (xᵢ(xᵢ − xⱼ)(xᵢ − xₖ)) ln((x − xᵢ)/(x₀ − xᵢ)) ] / [x⁴ (x³ − 3x + 2a)]

verified against the defining conservation-law integral to 10⁻²⁵. Ṁ follows from L = η Ṁ c² = f L_Edd with
η = 1 − E(r_isco) and the user's Eddington fraction f. The local temperature is T = (F/σ_SB)^(1/4).

**Shift factor.** For gas on a circular orbit, u_emit = uᵗ(1, 0, 0, Ω) with uᵗ = [−g_tt − 2Ωg_tφ − Ω²g_φφ]^(−1/2),
and a photon with E = 1 and angular momentum L received with energy ν_obs by the static observer:

    g = ν_obs / ν_emit = ν_obs / [ uᵗ (1 − ΩL) ]

This contains gravitational redshift, transverse Doppler shift and Doppler beaming at once.

**Color and brightness.** I_ν/ν³ is invariant along a ray, so a blackbody of temperature T seen with shift g is
exactly a blackbody of temperature gT (bolometric intensity g⁴σT⁴/π). The spectrum is integrated against the
CIE 1931 2° color-matching functions (380–780 nm, 5 nm), converted to linear sRGB (Rec. 709 primaries, D65),
and divided by the Y-weighted radiance of the hottest unshifted disk emission, the *reference radiance*
(recorded in the metadata): 1.0 in the EXR. Out-of-gamut negative components are clipped to zero. **In the
visible band** a hot disk (T ≫ 10⁴ K, e.g. a stellar-mass black hole) lies in the Rayleigh–Jeans tail, where
radiance ∝ T, so its brightness scales with g rather than g⁴ and its hue barely changes; cool disks (supermassive
black holes at low accretion rates) show strong color shifts.

**Sky.** Rays reaching the sky radius are assigned their direction of travel there (not their position: the two
differ by about b/r_sky). The default sky is a seeded star field of Gaussian disks (σ = 2.5×10⁻⁴ rad) of constant
surface brightness, so lensing magnification emerges from sampling; a celestial latitude/longitude grid can be
selected for validation. Both are synthetic.

**Display.** The PNG applies a fixed −1 stop base exposure plus the user's `--exposure`, the Narkowicz ACES filmic
curve per channel, and the sRGB transfer function. This is presentation only; the EXR is never tone-mapped.

## Approximations

| Approximation | Governing assumption | Validity | Error / control |
|---|---|---|---|
| Thin, equatorial, opaque disk | H/r ≪ 1; optically thick | Radiatively efficient thin disks | Geometric thickness neglected |
| Blackbody emission at the Novikov–Thorne T | Local thermal equilibrium, no color correction | Qualitative color accuracy | No spectral hardening or atmosphere model |
| Prograde circular motion, zero emission inside r_isco | Zero-torque inner boundary | Emission from r ≥ r_isco | Matches Novikov–Thorne |
| Finite ray-termination radius | Direction of travel at r_sky is asymptotic | Remaining bending ≈ M·b/r_sky² | ≲ 2×10⁻⁴ rad measured (b ≤ 50) |
| Horizon cutoff r₊ + 10⁻³ M | Rays reaching it are captured | Photons that close cannot return | Negligible |
| At most 3 plane crossings tested | Further higher-order images are thin and dim | See Known limits | Neglect is documented, not hidden |
| Stars as Gaussian disks | Illustrative sky | Synthetic | Not a catalog |
| Out-of-gamut colors clipped | sRGB gamut | Very cool or very hot disks | Affects hue only at gamut edges |
| GPU backend: float32 integration | Apple GPUs have no 64-bit floats; step control tightened (radial 10⁻⁵, angular 10⁻⁶); rays passing within sin²θ < 0.02 of a pole re-traced in float64 on the CPU | Same physics, lower arithmetic precision | Measured vs the CPU: 100 % same outcome, crossing radius 99th percentile 7×10⁻⁷, sky direction within 10⁻⁴ rad for ≥ 99.9 % of sky rays, radiance 99th percentile ≤ 10⁻⁴ (see below) |
| Animation = a sequence of static-observer views | Each frame is a complete, independent render of a stationary, axisymmetric hole and disk; the sweep changes the viewpoint (inclination, distance) or the parameter (spin) between frames | Viewpoint changes of a static scene | No motion of the gas, no light-travel-time delay between frames, no observer-velocity aberration; nothing is interpolated, blurred or synthesized between frames |
| One exposure reference per movie | The reference radiance (hottest unshifted disk emission) is fixed for all frames at the largest value of the sweep | Spin sweeps, where the reference differs per frame | Without it brightness would jump for a non-physical reason; measured frame-to-frame luma change 0.7 % in a spin sweep |
| Lossy video (H.264, 4:2:0 chroma) | The movie is for viewing; the PNG/EXR frames remain the physical record | All sizes | PSNR ≥ 35 dB against the source frames at 640×360 and above (ffmpeg 36–41 dB, built-in encoder 38–42 dB at the default quality); color of single-pixel stars is blurred by the 4:2:0 subsampling |
| Unresolved rays excluded from averaging | Counted, never colored | < 0.1 % of rays in tests | Reported in diagnostics; exit code 4 above 0.1 % |

## Animations and movies

`bhsim movie animate` renders a sequence of frames, each a full render by the same validated code (CPU or GPU
backend) with one viewing parameter changed linearly from frame to frame: the observer's inclination, the observer's
distance, or the black hole's spin. The model is stationary and axisymmetric, so the sequence is a series of static
observers at different positions (or of different holes for a spin sweep), **not** the time evolution of one system:
the disk gas does not move, light-travel time between frames is not modeled, and an observer who actually moved would
also see relativistic aberration, which is not included. Nothing is interpolated between frames.

All frames share one brightness reference, the largest per-frame reference of the sweep (research D5). The sky is a
fixed backdrop defined in these reference units, so it keeps its brightness while the disk brightens or dims with the
physics. The sample pattern is the same for every frame (the seed is fixed), so a frame is a pure function of its
settings; the photon ring can still speckle between frames at low sample counts, which is why movies default to 9
samples per pixel.

The movie file is lossy H.264 (4:2:0 chroma), tagged with BT.709 primaries and matrix and the sRGB transfer function of
the PNG frames. Measured fidelity against the source frames is in `docs/tolerances.md`. With ffmpeg the file repeats
byte for byte on one machine and ffmpeg version; the built-in macOS encoder is not deterministic and gives equivalent but
not identical movies. The frames themselves are exactly reproducible with either.

## Known limits

- Rays are followed through at most 3 equatorial-plane crossings. The photon ring is the superposition of the
  images within that cap, and is slightly under-resolved compared with the full infinite series.
- The disk is a thin, opaque, equatorial sheet: no thickness, corona, jets, polarization or radiative transfer.
- Output is a single still image for a static observer; observer motion is not modeled.
- The reference implementation is float64 on the CPU. An optional GPU backend (below) is validated against it.

## GPU backend precision (`--backend metal`)

**What runs where.** The GPU traces each ray with the same equations and integrator as the CPU (Mino time, u = 1/r,
Dormand–Prince 5(4)) but in **32-bit floating point**, because Apple GPUs provide no 64-bit arithmetic, and reports the
outcome (captured, disk hit with crossing radius and index, or sky with the final state). The CPU builds the camera rays,
computes the asymptotic sky direction, shading, averaging and output in float64. The render metadata records
`backend: metal / float32`.

**Why float32 needs care.** A ray's final direction is set by accumulated angles; a relative state error of ε in the
angular components turns into an error of order ε × (number of steps) in the direction. With the CPU's tolerance of 10⁻⁹
that is negligible; float32 resolves only ≈ 6×10⁻⁸. Two measures keep the result at CPU quality:

1. **Tighter angular step control.** The angular state (μ, dμ/dλ, φ) uses a relative tolerance of 10⁻⁶ (radial 10⁻⁵).
   Loosening it to 10⁻⁵ gave sky-direction errors up to 0.03 rad for 3–5 % of rays; the same errors appear in float64
   at that tolerance, so this is a step-control property, not an arithmetic limit.
2. **Polar rays re-traced on the CPU.** The azimuth rate φ′ contains L/(1 − μ²), which is ill-conditioned for a path
   passing near a pole; float32 hits a conditioning floor there. The kernel flags any ray whose path comes within
   sin²θ < 0.02 of an axis and the host re-traces it in float64 (≈ 3–4 % of rays in the standard scenes). Rays the GPU
   did not finish (step budget, step collapse) are also re-traced, so unresolved rays are decided by the reference code.
   Remedies tried and rejected by measurement: integrating w = 1 − μ² as the state variable and a polar step limiter.

**Measured agreement** (`bhsim compare`, five scenes, 960×540 at 4 samples per pixel, Apple M4; research.md §Agreement):
outcome match 100 %; crossing radius, 99th percentile 3×10⁻⁷ – 7×10⁻⁷ (limit 10⁻³); sky direction within 10⁻⁴ rad for
99.93–100 % of sky rays (limit 99.9 %; the few outliers, up to 10⁻² rad, graze the photon sphere); pixel radiance of
disk/horizon pixels, 99th percentile ≤ 10⁻⁶ relative, maximum 0.13 % (limit 1 %). Star pixels are judged by the
direction criterion, since a star's brightness changes steeply with direction. Results are deterministic on one
machine; different GPU models may differ in the last digits.

## References

- Carter (1968), "Global structure of the Kerr family of gravitational fields"; Bardeen (1973), "Timelike and
  null geodesics in the Kerr metric"; Bardeen, Press & Teukolsky (1972), Astrophys. J. 178, 347.
- Novikov & Thorne (1973); Page & Thorne (1974), Astrophys. J. 191, 499.
- Luminet (1979), Astron. Astrophys. 75, 228; James et al. (2015), "Gravitational lensing by spinning black holes
  in astrophysics, and in the movie Interstellar", Class. Quantum Grav. 32, 065001.
- Gralla & Lupsasca (2020), "Lensing by Kerr black holes", Phys. Rev. D 101, 044031.
- Dexter & Agol (2009), Astrophys. J. 696, 1616.
- CIE 1931 2° standard observer; IEC 61966-2-1 (sRGB); Narkowicz (2016), ACES filmic tone mapping curve fit.
