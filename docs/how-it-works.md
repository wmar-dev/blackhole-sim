# How it works

A walk-through of the renderer for a physics graduate student: someone comfortable with general relativity
(geodesics, Killing vectors, Hamilton–Jacobi, tetrads) but who has not worked through the Kerr photon region or the
radiometry of accretion-disk images. It explains what is computed and why; [physics.md](physics.md) is the terse
reference of equations, units and approximations, and [tolerances.md](tolerances.md) lists the numbers the tests hold
it to.

Conventions throughout: G = c = M = 1, Boyer–Lindquist coordinates, signature (−,+,+,+), spin a along +z,
μ = cos θ, Σ = r² + a²μ², Δ = r² − 2r + a², r₊ = 1 + √(1 − a²).

## 1. The idea

An image of a black hole is a map from the observer's sky to what light arriving from each direction has seen. We
compute it backward: for every pixel (and several samples inside it), launch the *time-reverse* of the photon that
would arrive through that pixel, follow it through the Kerr geometry, and ask what it hits first.

```
pixel ──► static-observer tetrad ──► (E, L, Q) and initial state ──► integrate geodesic (u, μ, φ in Mino time)
                                                                          │
                       ┌──────────────────────────────────────────────────┼──────────────────────────┐
                       ▼                                                  ▼                          ▼
              r ≤ r₊ + 10⁻³ : captured                    μ changes sign at r in [r_isco, r_out]    r ≥ r_sky, moving out
              (black, part of the shadow)                 (opaque disk: stop, shade with g and T)   (look up the sky in the
                                                                                                   direction of travel)
```

Every pixel is independent, so the work parallelizes trivially and the result does not depend on thread count.
Nothing here is approximated by "lensing distortion" or a texture warp: the only approximations are the physical
ones listed in [physics.md](physics.md#approximations) (a thin disk, a blackbody spectrum, at most three plane
crossings, a synthetic sky).

## 2. Null geodesics in Kerr

**Separation.** The Hamilton–Jacobi equation for a null geodesic, H = ½ g^{μν} p_μ p_ν = 0, separates in
Boyer–Lindquist coordinates with S = −Et + Lφ + S_r(r) + S_θ(θ) (Carter 1968). Besides E = −p_t and L = p_φ there is
a third constant, the Carter constant Q, and with an affine parameter σ

    Σ dr/dσ = ±√R(r),    R(r) = [E(r² + a²) − aL]² − Δ [(L − aE)² + Q]
    Σ dθ/dσ = ±√Θ(θ),   Θ(θ) = Q + a²E² cos²θ − L² cot²θ

Q is the constant associated with the Killing tensor of Kerr (Walker & Penrose 1970); for a ray at the observer it is
fixed by the polar momentum: Q = p_θ² + μ²(L²/sin²θ − a²E²).

**Mino time.** Defining dλ = dσ/Σ removes the Σ from both equations, so r and θ decouple completely:

    (dr/dλ)² = R(r),    (dμ/dλ)² = Θ_μ(μ) = (1 − μ²)(Q + a²E²μ²) − L²μ²

with dφ/dλ = L/(1 − μ²) − aE + a P/Δ and dt/dλ = a[L − aE(1 − μ²)] + (r² + a²)P/Δ, where P = E(r² + a²) − aL.
(We never integrate t.) Working in μ rather than θ makes Θ_μ a polynomial in μ², regular on the spin axis.

**Why integrate an ODE rather than use elliptic integrals.** The closed forms (Gralla & Lupsasca 2020) are exact and
fast, but handling turning points, windings and signs is intricate. Instead the code integrates the *second-order*
equations d²r/dλ² = R′(r)/2 and d²μ/dλ² = Θ_μ′(μ)/2. They carry the ray smoothly through turning points with no sign
bookkeeping, and the first integrals (dr/dλ)² = R and (dμ/dλ)² = Θ_μ are conserved by the exact flow, so their
numerical drift is a direct, ray-by-ray measure of integration error. That residual, normalized, is what the
diagnostics report (SC-003).

**Use u = 1/r.** A first version integrated r directly. With the observer at r = 100, dr/dλ ~ r² ~ 10⁴, so a relative
tolerance admitted an absolute error of order 10⁻² in (dr/dλ)² − R, which stayed constant while r fell to ~1.4, where
it looked like a 10⁻³ relative error. In u = 1/r, Mino time gives du/dλ → −E at large r, and u, u′, φ′ are all O(1)
over the whole range from r_sky to the horizon, so a fixed tolerance means the same thing everywhere. The equation is
u″ = R̃′(u)/2 with R̃(u) = R/r⁴ = p̃² − δ̃Ku², p̃ = E + a(aE − L)u², δ̃ = 1 − 2u + a²u², K = (L − aE)² + Q.

**Direction of integration.** We want the photon that *arrives* at the observer (E > 0, future-directed), traced into
its past. We keep that photon's constants (E, L, Q) and integrate the same equations with decreasing affine
parameter, i.e. in λ′ = −λ. All velocities in the code (`vu`, `vmu`) are derivatives with respect to λ′, and φ′ has the
opposite sign to dφ/dλ. (Reversing a Kerr geodesic in space alone would give a different curve; the reflection
(t, φ) → (−t, −φ) is a symmetry, which is why reversing the affine parameter is the correct operation.)

**The critical curve.** Rays asymptote to spherical photon orbits at radius r_p, which exist where η = Q/E² ≥ 0:

    ξ = L/E = −(r³ − 3r² + a²r + a²) / [a (r − 1)],    η = r³ [4a² − r (r − 3)²] / [a² (r − 1)²]

between the prograde and retrograde equatorial photon orbits r = 2[1 + cos((2/3) arccos(∓a))] (3 for a = 0). The set of
(ξ, η) on this one-parameter family is the boundary between captured rays and rays that escape: the edge of the
shadow. For an observer at infinity it appears at α = −ξ/sin θ_o, β = ±√(η + a²cos²θ_o − ξ²cot²θ_o) (Bardeen 1973);
the code and its tests use the exact mapping for an observer at finite distance (section 3).

## 3. From a pixel to a ray

**The observer.** A *static* observer (at rest in the Boyer–Lindquist coordinates; spec decision) exists only where
g_tt < 0, outside the ergosphere r > 1 + √(1 − a²cos²θ). The inputs are validated against this. A static observer is
not the ZAMO and is not on a geodesic: it needs a thrust to hold position, and sees frame-dragged light as such. Its
orthonormal frame is built by Gram–Schmidt on (∂_t, ∂_r, ∂_θ, ∂_φ):

    e₀ = ∂_t/√(−g_tt),   e_r = ∂_r/√g_rr,   e_θ = ∂_θ/√g_θθ,   e_φ = [∂_φ + (g_tφ/(−g_tt))∂_t] / √(g_φφ + g_tφ²/(−g_tt))

Orthonormality, and that e₀ has only a t component, are unit-tested at several (a, r, θ).

**The camera.** A pinhole camera looks along −r̂ with up = −θ̂ (north) and right = forward × up = +φ̂. A pixel at
normalized coordinates (x, y) has direction n ∝ (1, x tan(fov/2), y tan(fov/2)·H/W) in (forward, right, up). The
physical photon travels along −n. In the tetrad, p^(a) = (1, p̂) with p̂ = −n, so p̂_r = n_f, p̂_θ = n_u, p̂_φ = −n_ρ. The
contravariant momentum p^μ = e₀ + p̂_r e_r + p̂_θ e_θ + p̂_φ e_φ gives

    E = −(g_tt p^t + g_tφ p^φ),   L = g_tφ p^t + g_φφ p^φ,   p_θ = g_θθ p^θ,   Σ dr/dλ = Σ p^r

and the whole ray is then rescaled by 1/E so E = 1 (null paths do not depend on the overall scale). The energy the
observer measures for that photon, in units where E = 1, is 1/E_raw; it is needed for the shift factor. As a check,
the initial state is built from the tetrad rather than from the potentials R and Θ, so the null-condition residual
at launch (tested < 10⁻¹² over spins and inclinations) verifies the tetrad and the extraction of (E, L, Q) together.

**Orientation, physically.** Image right is +φ̂. With the spin axis up, the disk rotates counter-clockwise seen from
the north, so gas on the *left* of the image moves toward the observer: the left side is the approaching, Doppler-boosted
side, and prograde photons (L > 0) arrive from the left. The tests check this chain: the camera gives L > 0 on the left,
the shift factor gives g > 1 there, and the Kerr shadow is flattened on the left, where prograde photon orbits lie
closest to the hole.

## 4. Anatomy of the image

**Shadow.** The captured region. Its angular radius for a = 0 and a static observer at r is
arcsin[3√3 √(1 − 2/r) / r]: the 3√3 is the critical impact parameter, the √(1 − 2/r) is the static observer's
redshift of angles. For a spinning hole it is the D-shaped outline of section 2, displaced from the line of sight to
the centre: for a = 0.9 at i = 90° and r_o = 100 it extends 6.76 on the right and 2.84 on the left (in units of
r_o·tan θ).

**Crossings and image order.** Let the *n-th image* of the disk be the set of pixels whose ray reaches the disk at its
n-th crossing of the equatorial plane. The disk is opaque and occupies [r_isco, r_out] on both faces, so a ray ends at
the first crossing that lies inside the annulus. The n = 1 image is the direct one: the near side in front of the
shadow, and the far side lifted over the top, because a ray passing above the hole is bent down onto the far side of
the plane. For n ≥ 2 the ray must first cross the plane *without* hitting the disk, i.e. through the gap r < r_isco or
beyond r_out, loop around, and meet the disk from the other side. These rays hug the critical curve, and the
corresponding images are the secondary image under the shadow and the thin bright photon ring.

**The photon ring.** Near the critical curve a ray lingers near a spherical photon orbit, and the deviation grows as
e^{γ n} per half-orbit with Lyapunov exponent γ = π for a = 0 (Gralla & Lupsasca 2020; Johnson et al. 2020). So
successive images are demagnified by e^{−π} ≈ 0.043, and each crossing radius approaches r = 3. This is visible in
the code: for a ray at b = b_c(1 + 10⁻⁹) the plane-crossing radii are 3.3024, 3.0123, 3.0005, 3.0001, with
r − 3 shrinking by a factor ≈ 0.041 per crossing. The cap of three crossings (FR-004) means the ring in the image is
the sum of images 1–3 and omits n ≥ 4, each narrower than the last by the same factor; this is documented in
[physics.md](physics.md#known-limits) rather than hidden.

**Einstein ring.** A source exactly behind the hole must be deflected so that the in-plane sweep from the observer to
infinity is π. For r_o = 100 the exact quadrature (tools/reference/schwarzschild_deflection.py) gives b = 21.5069,
a ring of angular radius 12.29° at the static observer; a test renders a bright spot placed at the antipode and finds
the ring at that radius with no gaps.

## 5. Light from the disk

**Emission.** The disk is Novikov–Thorne: thin, opaque, equatorial, on prograde circular geodesics
(Ω = 1/(r^{3/2} + a)) from r_isco, zero torque at the inner edge. The flux per face is the Page–Thorne closed form
(the long expression in [physics.md](physics.md)); it vanishes at r_isco, peaks at about 1.6 r_isco (r ≈ 9.5) for a = 0 and falls as
3Ṁ/(8π r³) far away. It was checked against the defining conservation-law integral, F = (Ṁ/4πr)(−Ω′)(E − ΩL)⁻²
∫(E − ΩL)L′ dr, which agrees to 10⁻²⁵ in 30-digit arithmetic. The radiated luminosity fixes Ṁ: L = f L_Edd = η Ṁ c² with
η = 1 − E(r_isco), and each face radiates a blackbody at T = (F/σ)^{1/4}.

**The shift factor.** For emission from gas with 4-velocity u = uᵗ(1, 0, 0, Ω), received by the static observer,

    g = ν_obs / ν_emit = (−p·u_obs) / (−p·u_emit) = ν_obs / [uᵗ (E − ΩL)]    (with E = 1 in the code)

where uᵗ = [−g_tt − 2Ωg_tφ − Ω²g_φφ]^{−1/2} and ν_obs is the observer-measured energy from section 3. It contains
gravitational redshift, transverse Doppler shift and Doppler beaming in one factor, and for a = 0 face-on (L = 0) it
reduces to √(1 − 3/r)/√(1 − 2/r_o), which the tests check.

**Brightness and colour.** Along a ray I_ν/ν³ is invariant (Liouville), so I_ν,obs(ν) = g³ I_ν,em(ν/g). For a
blackbody, B_ν/ν³ depends on ν/T only, hence the observed spectrum is exactly a blackbody at temperature gT; the
bolometric intensity scales as g⁴. The pixel colour is that Planck spectrum integrated against the CIE 1931 colour
matching functions, converted to linear sRGB (negative out-of-gamut components clipped), and divided by the
Y-weighted radiance of the hottest unshifted disk emission ("reference radiance", stored in the metadata), so 1.0 in
the EXR means "as bright as the brightest unshifted gas".

*A consequence worth knowing.* In the visible band a hot disk is in the Rayleigh–Jeans tail: for a stellar-mass hole
at f = 0.1, T_peak ≈ 4×10⁶ K and B_ν(gT) ≈ 2ν²k·gT/c², so the visible brightness scales as g, not g⁴, and the hue is
nearly constant. The default image is therefore uniformly blue-white with a modest left–right asymmetry (about 1.6×).
A supermassive hole at low accretion rate (peak ≈ 7000 K, `--mass 1e9 --accretion-rate 1e-4`) shows the 11× asymmetry
and strong colour shift. This is physics, not a rendering choice: it is what a visible-light camera would record.

**Sky.** Rays that escape are looked up by their direction of travel in the static frame at r_sky (not by position,
which is off by ≈ b/r_sky: at r_sky = 1000 and b = 10 that is 0.6°, a larger error than the whole lensing feature). The
star field consists of Gaussian discs of constant surface brightness, so lensing magnification emerges from sampling
without computing a Jacobian: a lensed star is stretched into an arc and brightened in proportion because it covers
more samples. Surface brightness is conserved, but no shift factor is applied to the synthetic stars.

## 6. Numerical methods

- **Integrator:** adaptive Dormand–Prince 5(4), float64, relative tolerance 10⁻⁹, absolute 10⁻¹², on the state
  (u, u′, μ, μ′, φ). Ordinary rays take 50–150 accepted steps; near-critical rays 650–800 (the step count grows like
  log(1/|b − b_c|)).
- **Horizon:** φ and t diverge at r₊ in these coordinates, so a ray stops at r ≤ r₊ + 10⁻³ and the step is limited so
  that no stage evaluates inside the horizon.
- **Sky radius:** rays stop at max(1000, 10 r_o); the last step is shortened by a secant iteration so the exit state
  sits at a well-defined radius. The residual error from treating the direction there as asymptotic is ≈ b/r_sky² ≲
  2×10⁻⁴ rad for b ≤ 50 (measured 5×10⁻⁵).
- **Plane crossings:** a sign change of μ between accepted steps brackets a crossing; a cubic Hermite interpolant
  gives the starting point and one Newton correction with a real Dormand–Prince step sets the crossing radius. It agrees
  with an independent integration of the Schwarzschild orbit equation to 3×10⁻⁹.
- **Accuracy diagnostic:** the normalized first-integral residuals δ_r = |u′² − R̃|/(E²(1 + a²u²)²) and
  δ_μ = |μ′² − Θ_μ|/(Q + L² + a²E²) are recorded per ray; the default image has a maximum of 2.3×10⁻⁹ against a
  requirement of 10⁻³. Rays that exhaust the step budget are counted as unresolved and excluded from the average,
  never silently coloured.
- **Determinism:** each pixel's sample jitter is a hash of (seed, pixel, sample), and tiles are assembled in fixed
  order, so images are byte-identical for any thread count.

## 7. One ray, start to finish

Default scene (a = 0, 10 M☉ at f = 0.1, observer at r = 100, i = 80°, 1920×1080, 30° field of view). Take the pixel at
x = 960.5 (the vertical centre line), y = 726.5, 186 pixels below the image centre.

1. **Camera.** The pixel lies 0.0005 of the half-width to the right of centre and 0.345 of the half-height below it; the tetrad turns it into E_raw, and after rescaling E = 1, **L = −0.0139, Q = 27.575**, so b = √(L² + Q) =
   5.2512: only 1.06 % above the critical value 3√3 = 5.1962. The observer measures the photon's energy as 1.0102
   (the static observer's blueshift 1/√(1 − 2/100)). The launch state satisfies the null condition to machine precision (below 10⁻¹²).
2. **Integration.** The ray falls toward the hole in u = 1/r, nearly skims the photon sphere, and is bent through
   more than a half-turn. It takes 350 steps; the maximum residual is 8.7×10⁻¹⁰.
3. **Plane crossings.** μ changes sign three times: at r = 23.31 coming from the upper side (outside the disk's outer
   edge r_out = 20: no hit), at r = 3.294 from the lower side (inside the gap r < r_isco = 6: no hit), and at
   r = 7.113 from the upper side, inside [6, 20]: **hit, crossing index 3**. The pixel belongs to the tertiary image.
4. **Emission.** Novikov–Thorne gives T(7.113) = 3.33×10⁶ K for this mass and accretion rate.
5. **Shift.** Ω = 0.0527 and uᵗ gives g = 0.7676: redshifted, mainly by gravity and the transverse Doppler shift
   (L is tiny, so there is almost no line-of-sight Doppler term for this central-column ray).
6. **Colour.** The observed spectrum is a blackbody at gT = 2.55×10⁶ K; integrated against the CIE functions and
   converted to linear sRGB, divided by the reference radiance 3.74×10¹⁰ W m⁻² sr⁻¹, it is (0.429, 0.631, 1.436). Over the
   whole pixel this sample is averaged with its neighbours (4 samples), tone-mapped for the PNG, and stored unmodified in
   the EXR.

For contrast the central pixel has b = 0.020 (almost radial): it takes 19 steps and is captured. A pixel at the very
top of the disk's far-side arch (y = 305.5) is a direct n = 1 hit at r = 6.00, the inner edge, where the flux vanishes:
T there is 3.2×10⁴ K rather than the millions of kelvin a little further out.

## 8. How we know it is right

| Claim | Evidence | Where |
|---|---|---|
| Potentials R, Θ are the Carter potentials | Matched to 10⁻¹⁰ against the null condition from a numerically inverted metric (independent of the Carter formulas) | `KerrTests`, `tools/reference/kerr_basic.py` |
| Integration is accurate | Normalized residuals ≤ 2×10⁻⁹ over dozens of rays at several spins and inclinations (including near-critical and on-axis); exit angles change < 1.3×10⁻⁹ rad when the tolerance is tightened 10× | `ResidualTests`, research.md §D3 |
| Light bending is right | α = 4/b + 15π/(4b²) + 128/(3b³) to 10⁻³ for b = 50–1000; critical b = 3√3 separates capture from escape at 10⁻⁶ | `DeflectionTests` |
| Sky direction is right | Matches the exact Schwarzschild in-plane sweep (30-digit quadrature) to 5×10⁻⁵ rad | `SkyDirectionTests` |
| Crossings are right | Radii agree with a separate RK4 integration of the orbit equation to 3×10⁻⁹ | `PlaneCrossingTests` |
| Camera and tetrad are right | Null condition at launch to 10⁻¹²; orientation checks | `CameraTests` |
| The shadow is right | a = 0: 0.006 % from arcsin(3√3√(1 − 2/r)/r), measured from the EXR by independent Python; Kerr: outline vs the analytic critical curve to 1.5×10⁻⁴ (rays) and 0.8 % (images) | `ShadowRadiusTests`, `KerrShadowTests`, `tools/reference/kerr_shadow.py` |
| Strong lensing is right | A source directly behind the hole forms a closed ring at the predicted 12.29° | `RenderFeaturesTests` |
| The disk flux is right | Closed form vs conservation integral to 10⁻²⁵; Swift vs reference to 10⁻¹⁴ | `DiskPhysicsTests`, `tools/reference/novikov_thorne.py` |
| The shift factor is right | Matches a metric-tensor computation to 10⁻¹²; face-on closed form; sign of the Doppler effect | `DiskPhysicsTests` |
| The colour pipeline is right | Planck → XYZ → sRGB against 1 nm integration of the CIE tables; the g³/g⁴ identities; σ and h, k_B consistency | `PlanckColorTests`, `RadiometryTests` |
| The GPU backend agrees with the CPU | Five scenes, 960×540 at 4 spp: 100 % same outcome, crossing radius 7×10⁻⁷, radiance 99th percentile ≤ 10⁻⁶ | `bhsim compare`, `MetalAgreementTests` |
| The renderer is deterministic | Byte-identical output across runs and thread counts | `DeterminismTests`, quickstart |

The reference computations live in `tools/reference/` and are independent of the Swift code (Python with mpmath and
SciPy), so the renderer is never checked against itself. `bhsim validate` runs a compact version of this table.

### The GPU backend

`--backend metal` moves the expensive part, following each ray, to the GPU; everything else stays on the CPU in
float64. Rays are processed in **bands** of about a million samples (bounded memory). Per band the CPU builds the camera
rays, the GPU kernel traces them in float32 in **passes** of at most 1024 integrator steps per ray (so no single GPU
command runs long enough for the OS to cut it off; the longest measured pass is 60 ms), then the CPU re-traces the few
rays the GPU flagged (paths near the poles, where float32 loses accuracy) and shades and averages exactly as before.
Each ray is independent, so output is reproducible and does not depend on band size. What to trust: it agrees with the
CPU to the tolerances of `docs/tolerances.md` (`bhsim compare` checks this); the CPU backend remains the reference.
On an M4 it is 5–12× faster (default scene 5–7×, 4K at 16 samples 7.3×).

## 9. Where to be skeptical

- **Static observer.** Not a geodesic observer; the image is what a hovering observer sees. For r_o ≫ M the
  difference from a distant inertial observer is small, but it is a choice.
- **Thin opaque disk.** No vertical structure, corona, jet or radiative transfer; disk emission is a pure blackbody
  with no colour correction, and gas inside r_isco does not radiate.
- **Three crossings.** Images with n ≥ 4 are dropped, so the photon ring is under-resolved.
- **Gamut and display.** Out-of-gamut colours are clipped; the PNG uses a fixed −1 stop exposure and an ACES-style
  curve. The EXR is the physical record.
- **GPU precision.** The GPU backend is float32; it is validated against, not equal to, the CPU reference. A few sky rays near the photon sphere differ by more than 10⁻⁴ rad.
- **Synthetic sky.** Stars are illustrative, drawn from simple distributions, and receive no shift factor.
- **Single-sample noise.** At 4 samples per pixel the thin photon ring shows single-pixel speckle; use `--samples 9`
  or more.

## 10. Glossary and further reading

**Affine parameter σ / Mino time λ**: dλ = dσ/Σ; separates r and θ motion. **Carter constant Q**: third separation
constant of Kerr geodesics. **Critical curve**: boundary in the observer's sky between rays that fall in and rays that
escape. **Shadow**: the region inside it. **Photon ring**: the sequence of thin, nested images of the disk (and
anything behind the hole) formed by rays that loop near the photon orbits. **Static observer**: at rest in
Boyer–Lindquist coordinates. **Shift factor g**: ν_obs/ν_emit. **ISCO**: innermost stable circular orbit. **Reference
radiance**: Y-weighted radiance of the hottest unshifted disk gas; 1.0 in the EXR.

Where each piece comes from:

- Kerr geodesics and separability: Carter (1968); Bardeen (1973), *Timelike and null geodesics in the Kerr metric*
  (Les Houches lectures); Chandrasekhar, *The Mathematical Theory of Black Holes* (Kerr chapters); MTW ch. 33.
- Mino time for Kerr geodesics and fast tracing: Dexter & Agol (2009); closed-form elliptic solutions and the photon
  ring: Gralla & Lupsasca (2020), *Lensing by Kerr black holes*; Johnson et al. (2020), *Universal interferometric
  signatures of a black hole's photon ring*.
- Thin accretion disks: Novikov & Thorne (1973); Page & Thorne (1974); circular orbits: Bardeen, Press & Teukolsky
  (1972).
- Images of disks around black holes: Luminet (1979); James et al. (2015), *Gravitational lensing by spinning black
  holes in astrophysics, and in the movie Interstellar*.
- Invariance of I_ν/ν³: any relativistic radiative-transfer text (e.g. Rybicki & Lightman, *Radiative Processes in
  Astrophysics*; Mihalas & Mihalas).
- A popular introduction to what these images mean: Veritasium,
  [How to Understand What Black Holes Look Like](https://www.youtube.com/watch?v=zUyH3XhpLTo).
