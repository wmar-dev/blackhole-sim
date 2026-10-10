# Research: GPU Acceleration on Apple Silicon

All Technical Context unknowns are resolved below, together with the facts established on the reference machine.
Equations and conventions are those of [feature 001](../001-black-hole-image/research.md); this document covers only
what is new.

## Facts established on the reference machine (probe, 2026-10-09)

| Fact | Value | Consequence |
|------|-------|-------------|
| GPU | Apple M4, Metal 4, all Apple GPU families 1–9 | Modern feature set available |
| Memory | Unified (`hasUnifiedMemory = true`); max buffer 9.5 GB; recommended working set 12.7 GB | Buffers are shared with the CPU with no copies; memory is bounded by banding, not by the device |
| SIMD width | 32 lanes (`threadExecutionWidth = 32`), up to 1024 threads per threadgroup | Divergence between rays in a group costs speed (D3) |
| 64-bit floats | `'double' is not supported in Metal` (compile error) | Float32 is a hard limit, not a choice (D2) |
| Run-time compilation | Works with `makeLibrary(source:)`; `precise::` functions live in `metal::precise::` | No offline toolchain needed to build or run (D5) |
| CPU for comparison | 4 performance + 6 efficiency cores; CPU backend does ≈ 4.9×10⁵ rays/s (integration only) | The baseline the GPU must beat |

## Baseline: CPU backend, measured before any change (T001)

Release build, Apple M4 (4 performance + 6 efficiency cores), nothing else running, `/usr/bin/time -l`:

| Scene | Rays | Wall time | Peak memory | GPU target (SC-001, SC-006) |
|-------|------|-----------|-------------|-----------------------------|
| Default, 1920×1080, 4 samples per pixel | 8.29 M | 21.8 s (integration 21.2 s) | 346 MB | ≤ 7.3 s |
| 3840×2160, 16 samples per pixel | 132.7 M | 331.9 s (5.5 min) | 964 MB | ≤ 110 s |

Both runs: 0 unresolved rays, maximum residual 2.3×10⁻⁹ and 2.7×10⁻⁹.

## Decisions

### D1. Work split: GPU traces, CPU shades

- **Decision**: The GPU kernel integrates each ray and classifies it. It returns, per ray, an outcome (captured,
  disk hit, sky, unresolved), the crossing index and face, the radius at the hit or the final state, the maximum
  residual and the step count. The CPU uses the existing float64 code for everything after that: camera rays before
  the call, and after it the shift factor, blackbody colour, star-field and grid lookup, sample averaging, tone
  mapping and file output.
- **Rationale**: Integration is about 90 % of the cost (a 1080p render spends ≈ 17 s of 21 s in it). Shading needs
  a 32 MB star-grid structure and the Planck integral, which are awkward on a GPU and would add float32 colour
  error for no speed-up. With this split, a colour difference between the backends can only come from a ray whose
  *outcome or hit radius* differs, which is exactly what the agreement report measures. The camera rays are
  generated in float64 on the CPU and converted to float32 for upload (relative error 6×10⁻⁸ in L and Q, harmless).
- **Alternatives considered**: (a) Full GPU pipeline including shading: more speed-up in principle but the extra
  float32 error and complexity are unjustified, and it would be a second implementation of the radiometry.
  (b) GPU for only part of each ray: no benefit. (c) CPU and GPU sharing each ray: complexity without gain.

### D2. Float32: precision analysis and the mitigation ladder

- **Decision**: Run the integrator in float32 with a relaxed tolerance for the radial pair (10⁻⁵) and a tighter one for the
  angular components (10⁻⁶), fast-math disabled, in the same variables as the CPU (u = 1/r, μ, φ in Mino time). **M3 is
  adopted from the start** (see Spike S1 results): rays that come close to a pole are flagged and re-traced on the CPU.
  The original ladder, kept for reference, was: measure agreement; if it falls short, apply in order: **M1** tighter step cap and tolerance near the photon region; **M2** compensated
  (two-float) accumulation of φ and u; **M3** re-trace only the delicate rays on the CPU in float64 (rays flagged
  by the kernel: many steps, or minimum radius within a small band of the photon orbit). If M1–M3 cannot reach the
  tolerances, FR-012 applies: document the findings and keep the backend off.
- **Where float32 hurts, quantified**:
  - Accumulated φ reaches ≈ 10–20 rad over 100–800 steps: absolute error ≈ 10⁻⁶–10⁻⁵ rad, well inside the
    2×10⁻⁴ rad sky-direction bound (CPU measures 5×10⁻⁵).
  - Near-critical rays amplify errors by e^π per half-orbit. A ray is misclassified only if its impact parameter lies
    within the float32 error δ of the critical curve. With δ ≈ 10⁻⁵ the affected band is ≈ 10⁻³ pixel wide, so the
    expected fraction of rays that differ is ≈ 10⁻⁶, three orders below the 10⁻³ allowance.
  - Higher-order (photon-ring) images are the most sensitive: they cover ≈ 10⁻³ of the image and could see ≈ 10 %
    misclassification, still ≈ 10⁻⁴ of rays.
  - **Star radiance is steeper than the geometry.** A star is a Gaussian of width σ = 2.5×10⁻⁴ rad, so a sample at distance d from its centre changes by about d·Δ/σ² relative for a direction error Δ: 10⁻⁵ rad gives up to ~4 % at d = σ, although the geometry agrees to 10⁻⁵. Roughly 3 % of pixels see a star (200,000 stars), more than a 99th-percentile statistic ignores, so radiance agreement is judged on disk and horizon pixels, and sky rays through their direction (angular difference ≤ 10⁻⁴ rad). This was found in the pre-implementation analysis (F1).
  - The CPU's own residual bound (10⁻⁶) is a float64 test bound; for the GPU the requirement is the spec's
    10⁻³ for 99.9 % of rays, which float32 meets comfortably.
- **Rationale**: Hardware forces float32; the rest follows from measuring against the validated float64 reference
  rather than trusting the estimate. The ladder orders the mitigations by cost, cheapest first.
- **Alternatives considered**: Emulated double (double-float) for the whole integrator: about 10× the arithmetic,
  likely erasing the speed-up. Using the GPU only for coarse classification and refining on the CPU: this is M3,
  kept as a fallback.

### D3. Passes, watchdog and divergence

- **Decision**: One thread per ray sample. The kernel advances each unfinished ray by at most a fixed number of
  steps per command (a *pass*, initially 1024 steps), saves its state in a buffer, and the host repeats passes
  until every ray has finished or hit the total step budget. Finished threads exit at once.
- **Rationale**: Bounds the duration of every GPU command (a few milliseconds), which avoids the operating system's
  GPU watchdog regardless of the slowest ray, and makes progress reporting natural. Rays take 50–150 steps typically
  but up to ≈ 800 near the critical curve, so most rays finish in the first pass and stragglers cost only cheap
  early-exit threads in later passes. Neighbouring pixels have similar step counts, so SIMD-group divergence is
  moderate.
- **Alternatives considered**: One long kernel per band (risks the watchdog and gives no progress); queue compaction
  with persistent threads (more complex; revisit only if the spike shows divergence is the bottleneck, risk R2).

### D4. Memory: row bands

- **Decision**: Process the image in horizontal bands of rows sized so a band holds about 10⁶ samples. Per band: the
  CPU builds the camera rays in parallel, uploads them (shared memory, no copy), the GPU runs the passes, and the CPU
  shades the band in parallel and writes its pixels. Band buffers are reused. A band of 10⁶ samples needs about
  144 MB of GPU buffers (32 + 64 + 48 bytes per sample); with double buffering two bands are in flight.
- **Rationale**: Memory is bounded independently of image size (FR-009): a 3840×2160×16 render is ≈ 133 bands
  of 10⁶ samples, never resident at once. The CPU shading of one band can overlap the GPU tracing of the next (double
  buffering), which is an optimization after correctness.
- **Alternatives considered**: Whole image at once (≈ 8–70 GB for the large case; rejected).

### D5. Kernel source and compilation

- **Decision**: The kernel is Metal Shading Language source embedded as a Swift string and compiled at run time
  with `makeLibrary(source:)`; compilation takes about 50–100 ms per process.
- **Rationale**: One self-contained binary; no dependency on SwiftPM shader processing or on the Metal toolchain at
  run time (it is installed on this machine, but need not be elsewhere). Errors in the source surface as a Swift
  error with the compiler's message.
- **Alternatives considered**: A precompiled `.metallib` resource (needs the Metal toolchain at build time and a
  resource bundle next to the executable); `.metal` files processed by SwiftPM (build-system dependent).

### D6. Arithmetic settings

- **Decision**: Fast-math off (`fastMathEnabled = false`; `mathMode = .safe` where available), so square roots,
  divisions and NaN handling follow IEEE rules; use `metal::precise::` only where the default safe functions are not
  enough, decided by the kernel unit tests.
- **Rationale**: Fast-math may reorder arithmetic and assume no NaN/∞, which is unacceptable for a code that relies
  on the first-integral residual as a diagnostic and on reproducible results.

### D7. Plane crossings and termination on the GPU

- **Decision**: The kernel ports the CPU logic: sign change of μ between accepted steps, refinement by bisection on
  the cubic Hermite interpolant followed by one Newton correction with a Dormand–Prince step, disk-annulus test,
  three-crossing cap, horizon capture at r₊ + 10⁻³, and sky termination with a secant-shortened last step. The final
  state (not a direction) is returned for escaped rays; the CPU computes the direction of travel in float64 with the
  existing `AsymptoticDirection` code.
- **Rationale**: Reusing the CPU functions for the direction and the shading keeps the GPU kernel small and
  makes differences traceable to the integration alone.

### D8. Agreement metrics

- **Decision**: Compare on a fixed set of scenes (default; spin 0.9 at 85°; spin 0.998 at 60°; bare black hole
  with a grid sky at 90°; a cool disk). Per scene, ray by ray: the fraction with matching outcomes; for hits, the
  relative difference of the crossing radius; per pixel: the 99th percentile and maximum of the relative radiance
  difference over pixels whose samples all hit the disk or the horizon, and the distribution of the sky-direction difference for sky rays; shadow-outline error of each backend against the analytic curve;
  residual statistics and unresolved counts; and the speed-up. Ray-level outcomes are obtained from an
  outcome-map API on both backends.
- **Rationale**: Directly measures the spec's criteria (SC-002 to SC-004, SC-007) and separates "the GPU is
  different" from "the physics is wrong" because the CPU backend is validated independently.

### D9. Determinism

- **Decision**: Each ray is computed by one thread from its own inputs; the only cross-thread operation is an atomic
  counter of unfinished rays, which does not influence any ray's arithmetic. With fast-math off, the same inputs on
  the same GPU give the same bits, regardless of scheduling or of how the image is divided into bands. Output files
  hold no timestamps.
- **Rationale**: Gives SC-005. Different GPU models may differ in the last digits (documented, FR-011/assumptions).

### D10. Backend selection and failure

- **Decision**: `--backend cpu` (default) or `--backend metal`. If the GPU backend is requested and no device or
  pipeline is available, exit with the new code 5 and a message naming the cause; no fallback. An environment
  variable `BHSIM_FORCE_NO_GPU=1` simulates the missing GPU so the error path is testable on machines that have one.
  The metadata always records the backend and precision.
- **Rationale**: FR-008 and SC-008; avoids a user believing a GPU image was produced when the CPU produced it.

### D11. Tolerances and the measurement plan

- **Decision**: Targets are the spec's: ≥ 99.9 % outcome match; 99th-percentile relative radiance difference < 1 %;
  GPU shadow radius within 1 % and Kerr outline within 2 %; 99.9 % of rays with residual < 10⁻³; < 0.1 % unresolved.
  The kernel's float32 tolerance is chosen by a sweep (relative tolerance 10⁻⁴ to 3×10⁻⁶) that records agreement and
  speed for each value; the chosen value and its evidence go into `docs/tolerances.md`. Tolerances are never
  loosened without a written physical justification.

### D12. Spike S1 (go/no-go), done first

Before building the band pipeline, port the derivative, the Dormand–Prince step and the termination logic to the
kernel for a bare black hole (no disk) and run the same 1,024-ray benchmark set used for the CPU
(`IntegratorBenchmarkTests`) plus 10⁵ pixel rays. **Go** if (a) integration throughput is at least 3× the CPU's
(≈ 1.5×10⁶ rays/s) and (b) outcome agreement with the CPU is ≥ 99.9 %. If (a) fails, investigate divergence
(R2: compaction or ray sorting); if (b) fails, climb the mitigation ladder (D2). If neither can be met, conclude with
FR-012.

## Spike S1 results (T009–T013, 2026-10-09)

A bare-black-hole float32 kernel, measured against the float64 CPU backend on 64×64 pixel grids (a = 0 and 0.9, inclinations 45° and 85°, 30° field of view) and a 4×10⁵-ray benchmark (a = 0.9, 80°). **Decision: GO.**

**What the kernel reproduces.** Layouts, derivative, Dormand–Prince step and error estimate, and normalized residual agree with the CPU implementation to about 10⁻⁵ relative (`MetalKernelTests`). Ray outcomes (captured or sky) agree for 100 % of the 16,384 rays tested.

**What float32 cannot do, and what was found about it.** The first run met the outcome criterion but not the sky-direction criterion (3–5 % of sky rays more than 10⁻⁴ rad off, worst 0.033 rad). Investigation, in order:

1. The float64 CPU integrator run at the GPU's tolerance (10⁻⁵) shows the same 740 bad rays and the same 0.028 rad worst case, so a tolerance of 10⁻⁵ on all components is simply too loose for direction accuracy. This is not a float32 effect.
2. Tightening only the angular components (μ, dμ/dλ′, φ), which alone fix the final direction, to 10⁻⁶ removes the error for every ray that stays away from a pole (max|μ| < 0.99): 2 of 14,304 rays above 10⁻⁴ rad, worst 3.5×10⁻⁴ rad at first; with the final settings the worst is 5.7×10⁻⁵ rad.
3. All the remaining bad rays pass close to a pole (|μ| > 0.99; all of them with L ≈ 0.14, the strip of the image around the vertical centre line). Tightening the tolerance to 3×10⁻⁷ does not help them, and the worst error grows (0.14 rad), while the float64 integrator needs 10⁻⁸ for them. This is consistent with a conditioning floor: near the pole the polar first integral is a difference of nearly equal numbers, so float32 drift in that invariant shifts the ray's closest approach to the axis by a few percent, and the azimuthal jump of π across the pole inherits that error (about 0.05 rad).
4. Two remedies were tried and **rejected by measurement**: carrying sin²θ as its own state variable (it made the non-polar rays slightly worse and did not fix the polar ones) and limiting the step near the pole (no effect).
5. **Adopted: mitigation M3.** The kernel records the smallest sin²θ along each ray and flags rays that come closer to a pole than sin²θ = 0.02; the host re-traces exactly those rays in float64 on the CPU. About 7 % of rays (a = 0 and 0.9 at 85°) to 10 % (45°) are flagged.

**Accuracy with the adopted settings** (relative tolerance 10⁻⁵ for u and du/dλ′, 10⁻⁶ for the angular components, polar flag at sin²θ < 0.02):

| Scene | Outcome match | Rays flagged | Hybrid sky within 10⁻⁴ rad | Worst sky error, unflagged rays |
|-------|---------------|--------------|----------------------------|---------------------------------|
| a = 0, 85° | 100 % | 7.0 % | 100 % | 3.5×10⁻⁵ rad |
| a = 0.9, 85° | 100 % | 7.1 % | 100 % | 5.7×10⁻⁵ rad |
| a = 0, 45° | 100 % | 10.2 % | 100 % | 3.5×10⁻⁵ rad |
| a = 0.9, 45° | 100 % | 10.2 % | 100 % | 3.7×10⁻⁵ rad |

**Speed** (release build, 3.99×10⁵ rays, a = 0.9, 80°; CPU 5.4×10⁵ rays/s; GPU time excludes the CPU re-trace of flagged rays):

| Radial / angular tolerance | GPU rays/s | vs CPU | Steps per ray | Unflagged sky within 10⁻⁴ rad | Hybrid serial speed-up |
|---|---|---|---|---|---|
| 10⁻⁴ / 10⁻⁵ | 24.7 M | 46× | 16 | 99.86 % | 7.4× |
| 10⁻⁵ / 10⁻⁵ | 32.8 M | 61× | 16 | 99.87 % | 5.8× |
| **10⁻⁵ / 10⁻⁶ (chosen)** | **17.1 M** | **32×** | **23** | **99.995 %** | **5.5×** |
| 10⁻⁵ / 3×10⁻⁷ | 11.9 M | 22× | 29 | 99.995 % | 5.5× |
| 10⁻⁶ / 3×10⁻⁷ | 9.2 M | 17× | 29 | 99.995 % | 5.4× |

The serial hybrid bound is set by the CPU re-trace of the flagged 7 % of rays (the polar rays are slower per ray than average), not by the GPU; overlapping the re-trace with the next band's GPU work and the CPU shading is the remaining optimization (task T023). Settings tighter than 10⁻⁶ cost speed and gain nothing; looser ones fall below the 99.9 % target.

**Design changes forced by the spike** (reflected in `contracts/gpu-buffers.md` and `data-model.md`): `traceRays` also binds the ray inputs (L and Q are not stored in the state); the kernel parameters gain `angleTolerance` and `polarFlagSin2`; `RayState` records `minSin2`; `RayResult.face` becomes a bit field (bit 0 lower face, bit 1 delicate).

## Risks

- **R1, float32 near the photon ring**: some rays misclassify. Estimated ≈ 10⁻⁶–10⁻⁴ of rays; measured by the
  agreement report; mitigation ladder in D2.
- **R2, SIMD divergence**: rays in one 32-lane group may differ greatly in step count, wasting lanes. Mitigation:
  ray ordering follows the image (similar neighbours), multi-pass early exit; fall back to compaction if the spike
  shows it matters.
- **R3, speed-up smaller than estimated**: CPU work (camera rays, shading, output) is serial with the GPU unless
  double-buffered. Mitigation: overlap bands; measure each stage separately.
- **R4, Swift 6 concurrency with Metal objects**: Metal devices and buffers are not `Sendable`; wrap them in a
  small `@unchecked Sendable` class with documented single-queue use.
- **R5, watchdog or thermal throttling on very long renders**: passes are short (D3); long renders are timed in the
  large-image test.

## References

- Feature 001 research (equations, tolerances) and `docs/physics.md`.
- Apple, *Metal Shading Language Specification* (data types, math functions, `precise`/fast-math options) and
  *Metal Best Practices Guide* (command buffer sizing, shared storage on unified memory).

## Results (Phase 3, US1)

- Default-scene speed (1920×1080, 4 spp, debug-test build with `-O` library): CPU 19.9 s, GPU 2.75 s, **7.2×** (target ≥ 3×). 960×540 release: CPU 5.85 s, GPU 1.79 s, identical ray counts by outcome.
- Agreement tests (`MetalAgreementTests`, 240×135, spin 0/0.9/0.998): outcome ≥ 99.9 %, crossing radius p99 < 1e-3, sky direction ≤ 1e-4 rad for ≥ 99.9 %, disk/horizon pixel radiance p99 < 1 % all pass. GPU shadow radius of a Schwarzschild hole is within 1 % of analytic.
- The tolerance sweep of the spike fixed the values recorded in `docs/tolerances.md` (GPU section). T023 (double-buffered overlap of CPU shading with GPU tracing) was not needed to meet SC-001 and is deferred to the T033 measurement at 4K×16 spp.
- Quickstart step 4 (GPU, spin 0, 90°, fov 12): shadow angular radius 0.051373 rad vs analytic 0.051462 (0.17 %).

## Agreement (Phase 4, US2)

`bhsim compare` (5 scenes, 960×540 at 4 spp; ray-level comparison on one ray per pixel centre, pixel-level on the full renders) on the M4 finished in **40 s** (SC-007: < 2 min) and passed every scene:

| scene | outcome match | radius p99 | sky ≤ 1e-4 rad | sky max | radiance p99 / max | refined on CPU | speed-up |
|-------|---------------|-----------|----------------|---------|--------------------|----------------|----------|
| default | 100 % | 6.2e-7 | 99.993 % | 2.5e-3 | 0.0001 % / 0.040 % | 3.9 % | 5.0× |
| spin 0.9, 85° | 100 % | 6.9e-7 | 99.9985 % | 2.9e-3 | 0.0001 % / 0.13 % | 4.0 % | 8.2× |
| spin 0.998, 60° | 100 % | 3.2e-7 | 100 % | 5.3e-5 | 0.0000 % / 0.032 % | 3.2 % | 7.4× |
| bare hole, grid | 100 % | 0 | 99.941 % | 1.1e-2 | 0 / 0 | 3.2 % | 11.7× |
| cool disk | 100 % | 6.2e-7 | 99.993 % | 2.5e-3 | 0.0001 % / 0.040 % | 3.9 % | 8.9× |

Notes: (1) a handful of sky rays (≤ 0.06 %) differ by more than 1e-4 rad (worst 1.1e-2 rad, near-critical rays that graze the photon sphere); this is within the FR-003 allowance of 0.1 %. (2) The shadow check in `compare` is the GPU–CPU shadow-area difference (< 1 %) for all scenes plus the analytic radius error for the non-spinning edge-on scene (CPU 0.0010 %, GPU 0.0011 %); the Kerr-outline (2 %) check for the GPU is covered in the test suite. (3) The "cool disk" scene's image equals the default's because the HDR output is normalised to the hottest unshifted gas; it still exercises a different accretion-rate path. (4) The first scene's speed-up (5.0×) includes GPU pipeline compilation.

## Large renders (Phase 5, US3)

- 3840×2160 at 16 spp, `--backend metal` (release): **45.6 s** against the 331.9 s CPU baseline = **7.3×** (SC-006: ≥ 3×). 132,710,400 rays, 0 unresolved. Peak resident memory 913 MB for the whole process, of which the GPU band buffers are 144 MB (10⁶ samples × 144 B) and the camera rays of a band about 72 MB; the rest is the output image planes (HDR, per-pixel fractions) and the PNG/EXR writers, which scale with the image, not the sample count.
- Stress test: 10⁶ rays swept across the whole image radius (a = 0.998, 60°) finish in 2 passes; the longest single GPU command is **60 ms** (bound 200 ms, `NumericalDefaults.gpuMaxPassSeconds`), well inside the OS watchdog.
- Band buffers are bounded by `NumericalDefaults.gpuMaxBufferBytes` (160 MB) however large a band is requested. Renders are bit-identical across runs and across band sizes (1, 1000 and 10⁶ samples), including the `.png` and `.exr` bytes.

## Final results (Phase 6)

- `swift test`: 170 tests in 36 suites pass; no build warnings; `bhsim validate`: 22/22; `bhsim compare`: PASS on all five scenes (40 s). CPU renders are byte-identical to `main` (quickstart step 1: `.png` and `.exr` identical; `CPUUnchangedTests` pins the hashes). GPU renders are byte-identical across runs; the JSON states `metal`/`float32`; `BHSIM_FORCE_NO_GPU=1` gives `error: --backend: ...`, exit 5, no files, in 0.01 s.
- Targets: SC-001 7.2× (≥ 3×), SC-002/FR-003 met, SC-003 shadow 0.17 % (≤ 1 %), SC-004 0 unresolved and GPU residual p99.9 ≤ 4.5×10⁻⁶, SC-005 identical, SC-006 7.3× (≥ 3×), SC-007 40 s (< 2 min), SC-008 0.01 s.
- Phase 7 (conditional mitigations M1/M2/M3 and disabling the backend, T042–T045) is **not needed**: M3 (CPU float64 re-trace of delicate rays) was adopted during the spike and all tolerances are met without loosening any of them. T023 (CPU/GPU overlap) was skipped because SC-001 is met by a wide margin.
- Not covered: the 2 % Kerr-outline criterion (spin 0.9 at 85°) is checked on the CPU by `KerrShadowTests`; for the GPU `compare` verifies the shadow area equals the CPU's to < 0.01 %, which implies the same outline. Other GPU models were not tested.
