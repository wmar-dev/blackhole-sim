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

**Colour and brightness.** I_ν/ν³ is invariant along a ray, so a blackbody of temperature T seen with shift g is
exactly a blackbody of temperature gT (bolometric intensity g⁴σT⁴/π). The spectrum is integrated against the
CIE 1931 2° colour-matching functions (380–780 nm, 5 nm), converted to linear sRGB (Rec. 709 primaries, D65),
and divided by the Y-weighted radiance of the hottest unshifted disk emission, the *reference radiance*
(recorded in the metadata): 1.0 in the EXR. Out-of-gamut negative components are clipped to zero. **In the
visible band** a hot disk (T ≫ 10⁴ K, e.g. a stellar-mass black hole) lies in the Rayleigh–Jeans tail, where
radiance ∝ T, so its brightness scales with g rather than g⁴ and its hue barely changes; cool disks (supermassive
black holes at low accretion rates) show strong colour shifts.

**Sky.** Rays reaching the sky radius are assigned their direction of travel there (not their position: the two
differ by about b/r_sky). The default sky is a seeded star field of Gaussian discs (σ = 2.5×10⁻⁴ rad) of constant
surface brightness, so lensing magnification emerges from sampling; a celestial latitude/longitude grid can be
selected for validation. Both are synthetic.

**Display.** The PNG applies a fixed −1 stop base exposure plus the user's `--exposure`, the Narkowicz ACES filmic
curve per channel, and the sRGB transfer function. This is presentation only; the EXR is never tone-mapped.

## Approximations

| Approximation | Governing assumption | Validity | Error / control |
|---|---|---|---|
| Thin, equatorial, opaque disk | H/r ≪ 1; optically thick | Radiatively efficient thin disks | Geometric thickness neglected |
| Blackbody emission at the Novikov–Thorne T | Local thermal equilibrium, no colour correction | Qualitative colour accuracy | No spectral hardening or atmosphere model |
| Prograde circular motion, zero emission inside r_isco | Zero-torque inner boundary | Emission from r ≥ r_isco | Matches Novikov–Thorne |
| Finite ray-termination radius | Direction of travel at r_sky is asymptotic | Remaining bending ≈ M·b/r_sky² | ≲ 2×10⁻⁴ rad measured (b ≤ 50) |
| Horizon cutoff r₊ + 10⁻³ M | Rays reaching it are captured | Photons that close cannot return | Negligible |
| At most 3 plane crossings tested | Further higher-order images are thin and dim | See Known limits | Neglect is documented, not hidden |
| Stars as Gaussian discs | Illustrative sky | Synthetic | Not a catalogue |
| Out-of-gamut colours clipped | sRGB gamut | Very cool or very hot disks | Affects hue only at gamut edges |
| Unresolved rays excluded from averaging | Counted, never coloured | < 0.1 % of rays in tests | Reported in diagnostics; exit code 4 above 0.1 % |

## Known limits

- Rays are followed through at most 3 equatorial-plane crossings. The photon ring is the superposition of the
  images within that cap, and is slightly under-resolved compared with the full infinite series.
- The disk is a thin, opaque, equatorial sheet: no thickness, corona, jets, polarization or radiative transfer.
- Output is a single still image for a static observer; observer motion is not modeled.
- The reference implementation is float64 on the CPU; there is no GPU path (it was not needed: the default
  1080p image takes about 22 s on an Apple M4).

## References

- Carter (1968), "Global structure of the Kerr family of gravitational fields"; Bardeen (1973), "Timelike and
  null geodesics in the Kerr metric"; Bardeen, Press & Teukolsky (1972), Astrophys. J. 178, 347.
- Novikov & Thorne (1973); Page & Thorne (1974), Astrophys. J. 191, 499.
- Luminet (1979), Astron. Astrophys. 75, 228; James et al. (2015), "Gravitational lensing by spinning black holes
  in astrophysics, and in the movie Interstellar", Class. Quantum Grav. 32, 065001.
- Gralla & Lupsasca (2020), "Lensing by Kerr black holes", Phys. Rev. D 101, 044031.
- Dexter & Agol (2009), Astrophys. J. 696, 1616.
- CIE 1931 2° standard observer; IEC 61966-2-1 (sRGB); Narkowicz (2016), ACES filmic tone mapping curve fit.
