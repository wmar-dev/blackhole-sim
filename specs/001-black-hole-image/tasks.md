---

description: "Task list for Physically Accurate Black Hole Image"
---

# Tasks: Physically Accurate Black Hole Image

**Input**: Design documents from `/specs/001-black-hole-image/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: REQUIRED. Constitution Principle III mandates test-first validation against known results. Within every phase, write the test tasks first and confirm they FAIL before starting the implementation tasks they cover.

**Organization**: Tasks are grouped by user story. Foundational physics (Kerr geodesics, output writers, config) is shared and lives in Phase 2.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1, US2, US3 (maps to spec.md); none for Setup, Foundational, Polish
- Reference values come from independent Python scripts in `tools/reference/` (run with `uv run`); results are stored as JSON fixtures in `Tests/BlackHoleKitTests/Fixtures/`

## Path Conventions

Swift package at the repository root: `Sources/BlackHoleKit/<Module>/`, `Sources/bhsim/`, `Tests/BlackHoleKitTests/<Group>/`, `tools/reference/`, `docs/`. Units are geometrized (G = c = M = 1); see research.md §Conventions.

---

## Phase 1: Setup

**Purpose**: Package skeleton and shared conventions

- [ ] T001 Create `Package.swift` (swift-tools-version 6.0, platform macOS 14) with library target `BlackHoleKit`, executable target `bhsim` depending on `BlackHoleKit` and swift-argument-parser (from 1.5.0), and test target `BlackHoleKitTests` with `resources: [.copy("Fixtures")]`
- [ ] T002 [P] Create module directories with one placeholder source file each so the package builds: `Sources/BlackHoleKit/{Spacetime,Geodesic,Camera,Disk,Sky,Radiometry,Render,Output}/`, `Sources/bhsim/main.swift`, `Tests/BlackHoleKitTests/{Analytic,Geodesic,Disk,Render,Output}/`, `Tests/BlackHoleKitTests/Fixtures/.gitkeep`
- [ ] T003 [P] Create `Sources/BlackHoleKit/Spacetime/Units.swift` documenting the unit system and conventions (G = c = M = 1, Boyer–Lindquist, signature −+++) and defining named, sourced physical constants (CODATA 2018 or newer: Stefan–Boltzmann, Planck, Boltzmann, speed of light, solar mass, Eddington luminosity constant), plus `Sources/BlackHoleKit/Spacetime/NumericalDefaults.swift` with named, documented numerical constants (horizon cutoff 1e-3 M, r_sky, default integrator tolerance, step budget)
- [ ] T004 [P] Create `tools/reference/README.md` describing how to run reference scripts (`uv run python tools/reference/<script>.py`) and the convention that each script writes a JSON fixture under `Tests/BlackHoleKitTests/Fixtures/`
- [ ] T005 [P] Create `docs/tolerances.md` listing every numeric test tolerance with its source (SC-001 1%, SC-002 2%, SC-003 residual 1e-3 for 99.9% of rays, SC-004 1%, integrator residual 1e-6, sky-direction 1e-3 rad, and any others added later); tests (T008, T011, T012, T028, T046, T032) reference this table instead of hard-coding unexplained numbers
- [ ] T006 [P] Create `docs/physics.md` skeleton with sections: Units and conventions, Governing equations, Approximations (copy the table from research.md), Known limits (3-crossing photon-ring truncation), References

**Checkpoint**: `swift build` succeeds on the empty skeleton.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Kerr spacetime, geodesic integration, validated configuration, parallel rendering skeleton and output writers. No user story can start until this is complete.

**⚠️ CRITICAL**: Tests T007, T008, T011, T012, T015, T018, T020 and T023 are written first and must fail before their implementations.

### Kerr spacetime

- [ ] T007 [P] Write `tools/reference/kerr_basic.py` (mpmath) producing `Tests/BlackHoleKitTests/Fixtures/kerr_basic.json`: horizon radius, prograde ISCO, Keplerian Ω, ergosphere radius at several θ, and R(r), Θ_μ(μ) for sample (a, E, L, Q, r, μ), for a ∈ {0, 0.5, 0.9, 0.998}
- [ ] T008 [P] Write `Tests/BlackHoleKitTests/Analytic/KerrTests.swift`: horizon, ISCO and Ω against `kerr_basic.json`; a = 0 closed forms (horizon 2, ISCO 6, photon sphere 3, critical impact parameter 3√3); potentials R and Θ_μ against fixture values; metric symmetric and signature (−,+,+,+) at sample points
- [ ] T009 Implement `Sources/BlackHoleKit/Spacetime/Kerr.swift`: covariant metric components, horizon radius, ergosphere radius, prograde ISCO (Bardeen–Press–Teukolsky), Keplerian Ω = 1/(r^(3/2) + a)
- [ ] T010 Implement `Sources/BlackHoleKit/Spacetime/Potentials.swift`: radial potential R(r) and R′(r), polar potential Θ_μ(μ) and Θ_μ′(μ), and the Mino-time rates dφ/dλ and dt/dλ per research.md D2, safe at the axis (guard L = 0, μ² = 1)

### Geodesic integrator

- [ ] T011 [P] Write `Tests/BlackHoleKitTests/Geodesic/DeflectionTests.swift`: equatorial Schwarzschild ray from r = 1e4 with large b gives deflection within 1% of 4M/b after subtracting the straight-line angle subtended between the finite start and end radius, or extrapolating to infinity (and within 1% of the next-order 4/b + 15π/(4b²) expansion); rays with b just below and just above 3√3 are captured and escape respectively
- [ ] T012 [P] Write `Tests/BlackHoleKitTests/Geodesic/ResidualTests.swift`: along representative rays (a = 0, 0.9; equatorial, inclined, near-critical, near-axis with L = 0) the first-integral residuals (dr/dλ)² − R and (dμ/dλ)² − Θ_μ stay below 1e-6 using the normalized δ_r and δ_μ defined in research D2; tightening tolerance by 10× changes final angles by less than 1e-6 rad
- [ ] T013 Implement `Sources/BlackHoleKit/Geodesic/GeodesicState.swift` and `Sources/BlackHoleKit/Geodesic/Integrator.swift`: state (r, ṙ, μ, μ̇, φ, t) with constants (E, L, Q); adaptive Dormand–Prince 5(4) in Mino time using d²r/dλ² = R′/2 and d²μ/dλ² = Θ_μ′/2; termination reasons (horizon at r ≤ r₊ + 1e-3, sky at r ≥ r_sky outward, returning the direction of travel in the static orthonormal frame at r_sky (research D6), step budget, caller-supplied stop); per-ray maximum residual reported
- [ ] T014 Run T011 and T012 until they pass; if the residual or convergence bounds cannot be met, adjust tolerance defaults (not the test bounds without a written physical justification, per the constitution) and record the chosen tolerance and measured residuals in `specs/001-black-hole-image/research.md` §D3 and in `docs/tolerances.md` (T005)

### Configuration and validation

- [ ] T015 [P] Write `Tests/BlackHoleKitTests/Render/ConfigValidationTests.swift`: rejects spin < 0 or ≥ 1, non-positive mass/width/height/samples/FoV, non-square sample count, observer at or inside the ergosphere (static observer does not exist) or horizon, inclination exactly 0° or 180°, r_out ≤ r_isco; each error message names the option and the valid range (cli.md)
- [ ] T016 Implement `Sources/BlackHoleKit/Render/RenderConfig.swift` with `BlackHole`, `Observer`, `AccretionDisk`, `SkyConfig`, `RenderConfig` per data-model.md, a `validate()` throwing typed errors with the messages above, and the defaults from contracts/cli.md

### Results, diagnostics, parallelism

- [ ] T017 [P] Implement `Sources/BlackHoleKit/Render/RayOutcome.swift` (captured / disk(r, g, crossingIndex, face) / sky(asymptotic direction) / unresolved(reason)) and `Sources/BlackHoleKit/Render/Diagnostics.swift` (counts per outcome, maximum and 99.9th-percentile residual, rays over tolerance, unresolved count, wall time)
- [ ] T018 [P] Write `Tests/BlackHoleKitTests/Render/ParallelTilesTests.swift`: a tiled parallel renderer driven by a pure per-pixel function yields identical buffers for 1, 2 and all available threads and for repeated runs
- [ ] T019 Implement `Sources/BlackHoleKit/Render/ParallelTiles.swift`: tile scheduler using `DispatchQueue.concurrentPerform`, per-pixel pure function interface, per-pixel jitter as a pure function of (seed, pixel index, sample index), progress callback
- [ ] T020 [P] Write `Tests/BlackHoleKitTests/Output/OutputTests.swift`: EXR write then read back through ImageIO returns the exact Float32 values; PNG has the expected size and sRGB profile; metadata JSON contains every required key of `contracts/render-metadata.schema.json` and validates against it
- [ ] T021 [P] Implement `Sources/BlackHoleKit/Output/EXRWriter.swift` (32-bit float, via ImageIO), `Sources/BlackHoleKit/Output/PNGWriter.swift` (8-bit sRGB, via ImageIO), `Sources/BlackHoleKit/Output/Metadata.swift` (Codable matching contracts/render-metadata.schema.json, including units, derived radii, seed, reference radiance and diagnostics)
- [ ] T022 Add `Tests/BlackHoleKitTests/Geodesic/IntegratorBenchmarkTests.swift` (skipped unless `BHSIM_BENCH=1`) that times a 1,000-ray sample from a representative scene (rays built directly from (E, L, Q) samples, so no camera is needed); run it and record rays/second and the projected 1080p × 4-sample time in `specs/001-black-hole-image/research.md` §Risks (resolves the unmeasured-performance risk early)
- [ ] T023 [P] Write `Tests/BlackHoleKitTests/Render/PlanckColorTests.swift`: Planck → CIE XYZ → linear sRGB for known temperatures (6504 K ≈ D65 white point within a stated chromaticity tolerance; lower temperatures redder, higher bluer); write before T024
- [ ] T024 [P] Implement `Sources/BlackHoleKit/Radiometry/Planck.swift` and `Sources/BlackHoleKit/Radiometry/ColorMatching.swift`: Planck spectrum, CIE 1931 2° color-matching integration, XYZ → linear sRGB (Rec. 709, D65) (moved from Phase 5 so US1 star colors do not depend on US3)

**Checkpoint**: `swift test` passes; the integrator reproduces analytic deflection, critical impact parameter and bounded residuals; the measured performance projection is on record.

---

## Phase 3: User Story 1 - Render a Black Hole Image (Priority: P1) 🎯 MVP

**Goal**: Render a lensed image of a black hole (default a = 0): shadow, thin disk with higher-order images, lensed star field, written as PNG, EXR and JSON.

**Independent Test**: `bhsim render` with defaults produces the three files; measured shadow radius matches the theoretical value within 1% (SC-001); output is deterministic (SC-006).

**Scope note**: Disk shading in this phase is a labeled **geometry-only** mode (uniform emitted brightness, no shift factor), recorded as `"shading": "geometry-only"` in the metadata. It exists so geometry can be validated before US3 and is removed in T056.

### Tests for User Story 1 (write first, confirm failing)

- [ ] T025 [P] [US1] Write `Tests/BlackHoleKitTests/Render/CameraTests.swift`: static-observer tetrad is orthonormal (g_ab e^a e^b = η) and e₀ is proportional to ∂_t; the center pixel's photon moves purely radially inward (L = 0, Q = 0 at a = 0); FoV maps edge pixels to the expected angles
- [ ] T026 [P] [US1] Write `Tests/BlackHoleKitTests/Geodesic/PlaneCrossingTests.swift`: crossing detection counts equatorial crossings of a known inclined ray; refined crossing radius matches the analytic value within tolerance; crossings inside [r_isco, r_out] terminate the ray, outside continue and increment the counter; the counter stops disk tests after 3
- [ ] T027 [P] [US1] Write `Tests/BlackHoleKitTests/Render/SkyTests.swift`: star field is identical for equal seeds and different for different seeds; star positions are uniform on the sphere (chi-squared on latitude bins); the reference grid returns lines at known (θ, φ)
- [ ] T028 [P] [US1] Write `Tests/BlackHoleKitTests/Render/ShadowRadiusTests.swift`: render a = 0, inclination 90°, 800×800, FoV 12°, grid sky; measure the shadow angular radius from the EXR buffer; compare to arcsin(3√3·√(1 − 2/r_o)/r_o) within 1% (SC-001), using a shadow-outline helper created in `Tests/BlackHoleKitTests/Render/ShadowOutline.swift` (outline from captured pixels in an EXR buffer); also check a ray fired at the measured edge changes outcome across the edge
- [ ] T029 [P] [US1] Write `Tests/BlackHoleKitTests/Render/DeterminismTests.swift`: two renders with identical inputs produce identical EXR buffers and metadata (except wall time); results are identical across thread counts (SC-006); the same seed gives the same star field and jitter
- [ ] T030 [P] [US1] Write `Tests/BlackHoleKitTests/Render/RenderFeaturesTests.swift`: for a = 0 at 80° inclination the image contains disk pixels both above and below the shadow (secondary image), the lensed grid shows an Einstein-ring-like closed curve for sources aligned behind the hole, and an observer at inclination 0.01° produces no NaN or infinite pixels
- [ ] T031 [P] [US1] Write `tools/reference/schwarzschild_deflection.py` (scipy quadrature) producing `Tests/BlackHoleKitTests/Fixtures/schwarzschild_deflection.json`: exact asymptotic deflection angle for impact parameters b ∈ {6, 8, 10, 20, 50, 100}
- [ ] T032 [P] [US1] Write `Tests/BlackHoleKitTests/Render/SkyDirectionTests.swift`: the direction assigned to a Schwarzschild ray at r_sky matches the exact exit direction from `schwarzschild_deflection.json` within 1e-3 rad; assigning the position direction instead is shown to exceed that bound (guards against regression)

### Implementation for User Story 1

- [ ] T033 [US1] Implement `Sources/BlackHoleKit/Camera/Observer.swift` and `Sources/BlackHoleKit/Camera/Tetrad.swift`: Gram–Schmidt static-observer tetrad (research D4) and the ergosphere-radius validity check
- [ ] T034 [US1] Implement `Sources/BlackHoleKit/Camera/Camera.swift`: pinhole camera with configurable FoV, up = −e_θ, pixel (with sub-pixel offset) → local direction → covariant photon momentum → (E, L, Q) and initial state at the observer
- [ ] T035 [P] [US1] Implement `Sources/BlackHoleKit/Disk/AccretionDisk.swift`: annulus [r_isco, r_out], containment test, prograde Keplerian Ω (geometry only in this phase)
- [ ] T036 [US1] Implement `Sources/BlackHoleKit/Geodesic/PlaneCrossing.swift`: detect μ sign change between steps, refine the crossing with a bracketed root-find on the last step, count crossings up to 3, and terminate on first crossing inside the disk annulus (opaque disk)
- [ ] T037 [P] [US1] Implement `Sources/BlackHoleKit/Sky/StarField.swift`: seeded generation of stars as small angular discs of constant surface brightness with blackbody-derived colors from a documented temperature distribution and a documented brightness distribution, and a direction → radiance lookup that gives lensing magnification through sampling
- [ ] T038 [P] [US1] Implement `Sources/BlackHoleKit/Sky/ReferenceGrid.swift` and `Sources/BlackHoleKit/Sky/Sky.swift` (celestial latitude/longitude grid; common `Sky` interface selecting `starfield` or `grid`)
- [ ] T039 [US1] Implement `Sources/BlackHoleKit/Render/Renderer.swift`: for each pixel and sample, build the ray (T034), integrate (T013) with plane-crossing handling (T036), map the outcome (T017) to a color (geometry-only disk shading, sky lookup using the ray's direction of travel at r_sky, black for captured), average resolved samples only (a pixel whose samples are all unresolved is black and counted in the diagnostics), aggregate diagnostics, report progress; rays still active after the third crossing continue to the horizon or sky with no further disk tests
- [ ] T040 [US1] Implement tone mapping for the display image in `Sources/BlackHoleKit/Radiometry/ToneMap.swift` (documented exposure plus curve plus sRGB transfer) and wire the PNG, EXR and metadata writers (T021) into the renderer output path with `"shading": "geometry-only"` recorded
- [ ] T041 [US1] Implement `Sources/bhsim/RenderCommand.swift` and `Sources/bhsim/main.swift`: `bhsim render` with every option and default from contracts/cli.md, progress on stdout, errors on stderr, exit codes 0/2/3/4 as specified
- [ ] T042 [US1] Run T025–T030, T031 and T032 until they pass; handle any failures at the physics level (not by loosening tolerances without written justification); then run quickstart.md steps 3, 4, 7 and 8 and confirm the expected results
- [ ] T043 [US1] Add handling and tests for the remaining spec edge cases in `Tests/BlackHoleKitTests/Render/EdgeCaseTests.swift` and the renderer: multi-winding rays resolve to finite colors or are counted as `unresolved` (never silent), observer near the horizon is rejected cleanly, progress is shown for large images

**Checkpoint**: User Story 1 works on its own. The default render produces PNG, EXR and JSON; shadow radius within 1%; deterministic. This is the MVP.

---

## Phase 4: User Story 2 - Spinning Black Hole (Priority: P2)

**Goal**: Nonzero spin gives a flattened, off-center shadow and the correct Kerr geometry for the disk.

**Independent Test**: a/M = 0.9 shadow outline matches the analytic Kerr outline within 2% (SC-002); a = 0 reproduces the User Story 1 image exactly.

### Tests for User Story 2 (write first, confirm failing)

- [ ] T044 [P] [US2] Write `tools/reference/kerr_shadow.py` (numpy/scipy) producing `Tests/BlackHoleKitTests/Fixtures/kerr_shadow.json`: the analytic shadow outline in celestial coordinates (Bardeen 1973, via the spherical photon-orbit conditions) for a ∈ {0.5, 0.9, 0.998} and inclinations {45°, 85°, 90°} as seen by a static observer at r_o = 100 (convert Bardeen's celestial-coordinate curve to local static-frame angles at finite r_o, or generate the outline by independent ray shooting in Python)
- [ ] T045 [US2] Extend the shadow-outline helper in `Tests/BlackHoleKitTests/Render/ShadowOutline.swift` (created in T028) to return the full outline as (angle, radius) samples for comparison with `kerr_shadow.json` in T046
- [ ] T046 [P] [US2] Write `Tests/BlackHoleKitTests/Render/KerrShadowTests.swift`: rendered a = 0.9 outline at 85° inclination matches `kerr_shadow.json` within 2% (SC-002); the shadow is flattened and offset toward the expected side; a = 0 render equals the US1 render bit-for-bit; observers inside the ergosphere are rejected with the specified message
- [ ] T047 [P] [US2] Extend `Tests/BlackHoleKitTests/Geodesic/ResidualTests.swift` with spin sweeps (a ∈ {0.5, 0.9, 0.998}) at multiple inclinations to confirm residual and convergence bounds hold for rapidly spinning cases

### Implementation for User Story 2

- [ ] T048 [US2] Make T046 and T047 pass by verifying, and correcting where needed, the spin-dependent terms (frame dragging, g_tφ in the tetrad, ergosphere check) in `Sources/BlackHoleKit/Spacetime/Kerr.swift`, `Sources/BlackHoleKit/Spacetime/Potentials.swift` and `Sources/BlackHoleKit/Camera/Tetrad.swift`
- [ ] T049 [US2] Run quickstart.md step 5 and confirm the flattened, offset shadow and that `--spin 0` reproduces the US1 image; record the measured outline error in `specs/001-black-hole-image/research.md` §Validation

**Checkpoint**: User Stories 1 and 2 both work; Kerr shadow within 2%.

---

## Phase 5: User Story 3 - Physically Meaningful Color and Brightness (Priority: P3)

**Goal**: Disk color and brightness from the Novikov–Thorne temperature, exact blackbody at the shifted temperature gT, with Doppler beaming and gravitational redshift.

**Independent Test**: Shift factor and flux at sampled points match analytic and independent numerical references; the approaching side of the disk is brighter and bluer.

### Tests for User Story 3 (write first, confirm failing)

- [ ] T050 [P] [US3] Write `tools/reference/novikov_thorne.py` (mpmath) producing `Tests/BlackHoleKitTests/Fixtures/novikov_thorne.json`: flux F(r) from the Page–Thorne closed form AND from direct numerical integration of the conservation-law integral, for a ∈ {0, 0.5, 0.9, 0.998}, with the two methods' agreement recorded; plus analytic shift factors g at selected (r, photon direction) points (face-on gravitational redshift only; edge-on approaching and receding limbs)
- [ ] T051 [P] [US3] Write `Tests/BlackHoleKitTests/Disk/DiskPhysicsTests.swift`: F(r_isco) = 0; F(r) matches the fixture within tolerance; T(r) = (F/σ)^(1/4); g at the fixture points matches within tolerance; g > 1 on the approaching side and g < 1 on the receding side
- [ ] T052 [P] [US3] Write `Tests/BlackHoleKitTests/Render/RadiometryTests.swift`: a blackbody at gT has the same normalized spectrum as the shifted spectrum; bolometric intensity scales as g⁴ (the Planck → sRGB conversion itself is tested in T023)
- [ ] T053 [P] [US3] Write `Tests/BlackHoleKitTests/Render/DopplerAsymmetryTests.swift`: for an edge-on disk the mean EXR luminance on the approaching side exceeds the receding side, with a bluer color; emission near the ISCO is strongly dimmed and reddened relative to unshifted emission

### Implementation for User Story 3

- [ ] T054 [US3] Implement `Sources/BlackHoleKit/Disk/NovikovThorne.swift`: Page–Thorne flux with zero-torque inner boundary, T(r) and the temperature scale from mass and accretion rate (Eddington fraction) using constants from T003
- [ ] T055 [P] [US3] Implement `Sources/BlackHoleKit/Disk/ShiftFactor.swift`: u_em = u^t(1, 0, 0, Ω), g = (E/√(−g_tt)) / (u^t(E − ΩL)) per research D5
- [ ] T056 [US3] Replace geometry-only disk shading in `Sources/BlackHoleKit/Render/Renderer.swift` with radiance from a blackbody at T_obs = g·T(r) (bolometric g⁴σT⁴/π), remove the `"geometry-only"` metadata flag, and record the HDR reference radiance (T054 scale) in the metadata and EXR normalization
- [ ] T057 [US3] Run T050–T053 until they pass and run quickstart.md step 6; record F(r) agreement between the closed form and the numerical integral in `specs/001-black-hole-image/research.md` §Validation

**Checkpoint**: All three stories work; the default image has physically derived color and brightness.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T058 Implement `Sources/bhsim/ValidateCommand.swift`: `bhsim validate` runs the analytic checks (horizon, ISCO, photon sphere, 3√3, deflection, residual sample, shadow, flux, g) and prints a table of measured value, reference and tolerance; exit 0 only if all pass
- [ ] T059 Benchmark the default 1080p render with the shipped defaults (4 samples per pixel): confirm under 10 minutes (SC-005); if not, apply CPU optimizations first (tolerance/step tuning, SIMD) and re-measure; record the result in `specs/001-black-hole-image/research.md` §Risks
- [ ] T060 Verify SC-003 on a full-size render: normalized first-integral residual below 1e-3 for at least 99.9% of rays and unresolved fraction below 0.1%, read from the metadata diagnostics; verify exit code 4 when either threshold is exceeded
- [ ] T061 [P] Complete `docs/physics.md` (FR-010): governing equations, units, coordinate and gauge conventions, every approximation with validity and error, the 3-crossing photon-ring limit, and references
- [ ] T062 [P] Write `README.md` at the repository root: what the project does, build and run commands (from quickstart.md), output files, defaults, link to `docs/physics.md`
- [ ] T063 Run the whole of `quickstart.md` end to end on a clean checkout (`swift build -c release`, `swift test`, `bhsim validate`, steps 3–8) and fix any discrepancy between the document and actual behavior
- [ ] T064 Manual domain-expert review of `out/default.png` and `out/default.exr` against the checklist in SC-007 (shadow, photon ring, secondary disk image, Doppler asymmetry, no non-physical artifacts); record the outcome and any follow-ups in `specs/001-black-hole-image/checklists/requirements.md` §Notes

---

## Phase 7 (Optional, conditional): Metal GPU Backend

**Entry condition**: Only start if T059 shows the CPU path misses SC-005 even after CPU optimization. Otherwise skip and note "not needed" in research.md §D9.

- [ ] T065 [P] Write `Tests/BlackHoleKitTests/Render/MetalAgreementTests.swift`: for a fixed set of rays and a small image, the Metal backend (float32) reproduces the CPU float64 reference within the SC-001, SC-002 and SC-003 tolerances; the test fails if any tolerance is exceeded
- [ ] T066 Implement `Sources/BlackHoleKit/Metal/GeodesicKernel.metal` and `Sources/BlackHoleKit/Metal/MetalBackend.swift` (ray integration on the GPU; shading on the CPU; mitigations from research D9: smaller steps near the photon sphere, compensated arithmetic for r and μ)
- [ ] T067 Enable `--backend metal` in `Sources/bhsim/RenderCommand.swift` only if T065 passes; otherwise keep the flag rejected with a clear message and document the measured float32 error in research.md §D9

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup; BLOCKS all user stories
- **US1 (Phase 3)**: depends on Foundational; this is the MVP
- **US2 (Phase 4)**: depends on US1 (reuses renderer and shadow tests)
- **US3 (Phase 5)**: depends on US1 (replaces geometry-only shading); independent of US2, can run in parallel with it
- **Polish (Phase 6)**: depends on the stories being delivered
- **Metal (Phase 7)**: depends on T059 and Polish; conditional

### Within Each Phase

- Tests first and failing, then implementation
- Kerr (T009–T010) before the integrator (T013); integrator before camera and renderer
- Config (T016) before the CLI (T041); writers (T021) before output wiring (T040)
- Renderer (T039) before the shadow, determinism and feature tests can pass

### Task-Level Dependencies

- T009 → T010 → T013 → T014
- T016 → T039, T041
- T033 → T034 → T039
- T036 → T039
- T039 → T040 → T041 → T042 → T043
- T024 → T037 (star colors); T023 → T024
- T054, T055 → T056 → T057
- T058, T059, T060 → T063 → T064

### Parallel Opportunities

- Setup: T002, T003, T004, T005, T006 together
- Foundational tests and references: T007, T008, T011, T012, T015, T018, T020, T023 together; then T017 and T021 together
- US1 tests: T025–T030, T031, T032 together; implementations T035, T037, T038 together
- US3 tests and references: T050–T053 together; T054 and T055 can follow
- US2 and US3 can proceed in parallel after US1
- Polish: T061 and T062 together

### Parallel Example: User Story 1 tests

```text
Task: "Write CameraTests in Tests/BlackHoleKitTests/Render/CameraTests.swift"           (T025)
Task: "Write PlaneCrossingTests in Tests/BlackHoleKitTests/Geodesic/PlaneCrossingTests.swift" (T026)
Task: "Write SkyTests in Tests/BlackHoleKitTests/Render/SkyTests.swift"                 (T027)
Task: "Write ShadowRadiusTests in Tests/BlackHoleKitTests/Render/ShadowRadiusTests.swift" (T028)
Task: "Write DeterminismTests in Tests/BlackHoleKitTests/Render/DeterminismTests.swift" (T029)
Task: "Write RenderFeaturesTests in Tests/BlackHoleKitTests/Render/RenderFeaturesTests.swift" (T030)
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup, Phase 2 Foundational (includes the early performance measurement, T022)
2. Phase 3 User Story 1
3. **Stop and validate**: run quickstart.md steps 3, 4, 7 and 8; shadow within 1%, deterministic output
4. Demo the first physically correct image (geometry only)

### Incremental Delivery

1. Setup + Foundational → verified geodesic engine
2. + US1 → lensed geometry image (MVP)
3. + US2 → spinning black hole, Kerr shadow within 2%
4. + US3 → physically derived color and brightness
5. Polish → validate command, performance and documentation
6. Metal only if the CPU benchmark requires it

### Notes

- Never loosen a reference-test tolerance without a written physical justification (constitution Principle III)
- Reference fixtures come from independent Python code so that the Swift implementation is not checked against itself
- Commit after each task or logical group
