# Data Model: Physically Accurate Black Hole Image

Units are geometrized (G = c = M = 1) unless stated. Angles are radians internally; the CLI accepts degrees.

## BlackHole

| Field | Type | Rule |
|-------|------|------|
| spin `a` | Double | 0 ≤ a < 1 (a ≥ 1 rejected, FR-002/edge case) |
| derived `horizonRadius` | Double | 1 + √(1 − a²) |
| derived `iscoRadius` | Double | Bardeen–Press–Teukolsky prograde ISCO |
| mass (solar masses) | Double > 0 | Scale only; used at the radiometry boundary |

## Observer

| Field | Type | Rule |
|-------|------|------|
| distance `r_o` | Double | Must exceed the ergosphere radius 1 + √(1 − a²cos²θ_o) (static observer exists) |
| inclination `θ_o` | Double | 0 < θ_o < π (exactly 0 or π is rejected with a clear message; angles arbitrarily close to the axis are supported) |
| azimuth `φ_o` | Double | Default 0 (irrelevant for axisymmetric spacetime and disk; matters only for the sky) |
| fieldOfView | Double | 0 < FoV < π; applies to the image's horizontal angle |
| derived `tetrad` | 4 vectors | Static-observer orthonormal frame (research D4) |

## AccretionDisk

| Field | Type | Rule |
|-------|------|------|
| outerRadius `r_out` | Double | > r_isco, default 20 |
| accretionRate `Ṁ` | Double | Eddington fraction, sets the temperature scale (units at output boundary) |
| derived `Ω(r)`, `F(r)`, `T(r)` | functions | Keplerian angular velocity, Novikov–Thorne flux and temperature for r_isco ≤ r ≤ r_out |
| Invariant | | Inner edge is r_isco; F(r_isco) = 0 |

## Sky

| Field | Type | Rule |
|-------|------|------|
| kind | enum | `starfield` (default) or `grid` |
| seed | UInt64 | Recorded in metadata; drives star positions, colors and brightness |
| starCount, starRadius | Int, Double | Defaults documented; star radius is angular |

## RenderConfig

| Field | Type | Rule |
|-------|------|------|
| width, height | Int > 0 | Default 1920 × 1080 |
| samplesPerPixel | Int ≥ 1 | Perfect-square grid (1, 4, 9 …), default 4 |
| maxPlaneCrossings | Int | Fixed at 3 for this feature (spec clarification) |
| integrator tolerance, step budget | Double, Int | Defaults per research D3 |
| exposure, tonemap | Double, enum | Display PNG only; HDR output unaffected |
| outputBasename | Path | Produces `<name>.png`, `<name>.exr`, `<name>.json` |

## PhotonState (per ray, transient)

State vector `(r, ṙ, μ, μ̇, φ, t)` in Mino time λ, plus constants `(E, L, Q)` fixed at launch, plus `crossings` (Int 0…3).

## RayOutcome (per ray, result)

One of:

| Case | Payload |
|------|---------|
| `captured` | none (shadow, black) |
| `disk` | crossing radius `r`, shift factor `g`, crossing index (1–3), emitting face |
| `sky` | asymptotic direction `(θ, φ)` |
| `unresolved` | reason (step budget exhausted or integration failure) |

Transitions: a ray starts active at the observer and ends in exactly one outcome. Crossing the equatorial plane inside the disk annulus ends the ray as `disk`. Crossing it outside the annulus keeps the ray active and increments `crossings`. A ray still active after the third crossing is traced on to the horizon or the sky without further disk tests, so contributions from further crossings are neglected (research.md §Approximations). A ray that exhausts its step budget ends as `unresolved`. Unresolved samples are excluded from the pixel average and counted; a pixel with no resolved samples is black and counted in `diagnostics.unresolved`.

## RenderResult

| Field | Type | Meaning |
|-------|------|---------|
| hdr | width × height × 3 Float32 | Linear sRGB in reference-radiance units |
| display | width × height × 3 UInt8 | Tone-mapped sRGB |
| diagnostics | struct | Counts per outcome; max and 99.9th-percentile first-integral residual; rays over tolerance (FR-008); unresolved count; wall time |
| metadata | struct | All inputs, derived radii, seed, units, reference radiance (null while shading is `geometry-only`), `hdr.shading` (`geometry-only` until User Story 3, then `physical`), software version (`contracts/render-metadata.schema.json`) |

## Relationships

`RenderConfig` aggregates `BlackHole`, `Observer`, `AccretionDisk`, `Sky`. Each pixel sample produces one `PhotonState` → one `RayOutcome`; outcomes are shaded (disk: Planck at gT; sky: star/grid lookup; captured: zero) and averaged into `RenderResult`.
