---

description: "Task list for GPU Acceleration on Apple Silicon"
---

# Tasks: GPU Acceleration on Apple Silicon

**Input**: Design documents from `/specs/002-metal-gpu-backend/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: REQUIRED. Constitution Principle III mandates test-first validation against known results. Within every phase, write the test tasks first and confirm they FAIL before starting the implementation tasks they cover. The exception is T003, a regression guard that must pass before and after.

**Organization**: Tasks are grouped by user story. A feasibility spike (Phase 2) gates all user-story work: if the GPU cannot reach the agreement and speed targets, Phase 7 (mitigation ladder, then the FR-012 conclusion) replaces the rest.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1, US2, US3 (maps to spec.md); none for Setup, Foundational, Polish and the conditional phase
- Include exact file paths in descriptions

## Path Conventions

Swift package at the repository root, as in feature 001: `Sources/BlackHoleKit/<Module>/`, `Sources/bhsim/`, `Tests/BlackHoleKitTests/<Group>/`, `docs/`. New code lives in `Sources/BlackHoleKit/Metal/` and `Tests/BlackHoleKitTests/Metal/`. Units and conventions are unchanged (geometrized, Boyer–Lindquist). GPU tests skip themselves when no GPU is present. Benchmarks are skipped unless `BHSIM_BENCH=1`.

---

## Phase 1: Setup

**Purpose**: Baselines to compare against and the directories for the new code

- [X] T001 Record CPU baselines with the current release build: wall time and peak memory (`/usr/bin/time -l`) of the default 1920×1080×4 render and of a 3840×2160×16 render (several minutes, run once), in `specs/002-metal-gpu-backend/research.md` §Baseline
- [X] T002 [P] Create the directories `Sources/BlackHoleKit/Metal/` and `Tests/BlackHoleKitTests/Metal/` (a `.gitkeep` in each until files exist)

**Checkpoint**: Baselines are on record; `swift build` still succeeds.

---

## Phase 2: Foundational (Blocking Prerequisites, includes the feasibility spike)

**Purpose**: Backend plumbing, the "no GPU" path, and spike S1 (research.md D12): a bare-black-hole float32 kernel measured for speed and agreement. No user story starts until the spike returns GO.

**⚠️ CRITICAL**: Tests T003–T005, T009 and T010 are written first and must fail before their implementations (T003 must pass throughout).

### CPU regression guard

- [X] T003 [P] Write `Tests/BlackHoleKitTests/Render/CPUUnchangedTests.swift`: render a small CPU scene (spin 0.7, 64×36, 4 samples per pixel, star field with seed 7 and 20,000 stars, other options default), write it with `RenderOutput.write`, and compare the SHA-256 of the `.png` and `.exr` bytes with literals recorded from the current code BEFORE any other task in this feature changes the sources (FR-002). The test passes now and must keep passing

### Backend types, metadata and the unavailable path

- [X] T004 [P] Write `Tests/BlackHoleKitTests/Metal/BackendTests.swift`: `Backend` names and precisions (`cpu`→`float64`, `metal`→`float32`); `RenderConfig().backend == .cpu`; the metadata JSON contains `backend.name` and `backend.precision` and validates against the updated `specs/001-black-hole-image/contracts/render-metadata.schema.json`; input validation messages and errors are identical for both backends (FR-013)
- [X] T005 [P] Write `Tests/BlackHoleKitTests/Metal/MetalUnavailableTests.swift`: `MetalContext.make(forceUnavailable: true)` throws `BackendError.unavailable` with a message naming the cause; `Renderer(config:)` with `backend = .metal` throws it too; the CLI with `BHSIM_FORCE_NO_GPU=1` and `--backend metal` exits 5 within 2 seconds, prints `error: --backend:` to stderr and writes no files (FR-008, SC-008); the same command with `--backend cpu` is unaffected; invalid input (for example `--spin 1.2 --backend metal`) still exits 2 before any backend check
- [X] T006 Implement `Sources/BlackHoleKit/Render/Backend.swift` (`Backend` enum with `name` and `precision`, `BackendInfo`, `BackendError.unavailable(reason)`), add `backend` to `RenderConfig` and to `RenderedImage`, add the `backend` object to `Sources/BlackHoleKit/Output/Metadata.swift`, add it as a required key to `specs/001-black-hole-image/contracts/render-metadata.schema.json` (per `contracts/render-metadata.delta.md`), and in `Sources/bhsim/RenderCommand.swift` validate input first (exit 2), then create the renderer and map `BackendError.unavailable` to `error: --backend: <reason>` with exit code 5 (the rendering itself is enabled later, in T021)
- [X] T007 Implement `Sources/BlackHoleKit/Metal/MetalContext.swift`: acquire the device and command queue, compile the library from the embedded source with fast-math off (research D5, D6), create the pipeline states, honour `BHSIM_FORCE_NO_GPU` and the `forceUnavailable` parameter, accept an `includeTestKernels` option that compiles the test-only kernels (preprocessor flag), and turn every failure into `BackendError.unavailable` with a specific reason; wrap Metal objects in a documented `@unchecked Sendable` class (research R4)
- [X] T008 Run T003–T005 until they pass (the kernel source needed by T007 can be a minimal placeholder until T011)

### Spike S1: bare black hole on the GPU

- [X] T009 [P] Write `Tests/BlackHoleKitTests/Metal/MetalKernelTests.swift`: the Swift `MemoryLayout` sizes and field offsets of `GPURayInput`, `GPURayState`, `GPURayResult` and `KernelParameters` equal the sizes and offsets the kernel reports (`contracts/gpu-buffers.md`); the kernel's derivative, one Dormand–Prince step, and normalized residual agree with `GeodesicIntegrator` (`derivative`, `advance`, `residual`) to 10⁻⁵ relative on sample states for a = 0, 0.5, 0.9, 0.998
- [X] T010 [P] Write `Tests/BlackHoleKitTests/Metal/MetalSpikeTests.swift`: an always-run test that traces 4,096 pixel rays of a bare black hole (a = 0 and 0.9, inclinations 45° and 85°) on both backends and requires at least 99.9 % identical outcomes (captured or sky), and a benchmark (skipped unless `BHSIM_BENCH=1`) that reports GPU versus CPU rays per second on the 1,024-ray set of `IntegratorBenchmarkTests` plus 10⁵ pixel rays, and the agreement and speed for kernel relative tolerances 10⁻⁴, 3×10⁻⁵, 10⁻⁵, 3×10⁻⁶
- [X] T011 Implement `Sources/BlackHoleKit/Metal/GeodesicKernelSource.swift`: the Metal Shading Language source as an embedded string with the structs of `contracts/gpu-buffers.md`, the derivative (u″, μ″, φ′), the Dormand–Prince 5(4) step with FSAL, the normalized residual, horizon and sky termination (disk disabled), and the `initializeStates` and `traceRays` kernels, plus test-only kernels (`testDerivative`, `testStep`, `testResidual`, `queryLayout`) enabled by a preprocessor flag
- [X] T012 Implement `Sources/BlackHoleKit/Metal/MetalRayTracer.swift`: Swift structs matching the layouts, buffer allocation (shared storage), the host loop (`initializeStates`, then repeated `traceRays` passes until the unfinished counter is 0, each pass its own command buffer), conversion of `GPURayResult` to `RayOutcome`, and the layout/test-kernel accessors used by T009
- [X] T013 Run T009 and T010 and the benchmark; record in `research.md` §Spike S1 the measured throughput versus CPU, the outcome agreement and the tolerance sweep; decide **GO** (throughput ≥ 3× CPU and agreement ≥ 99.9 %) or **NO-GO**. On NO-GO skip Phases 3–6 and go to Phase 7

**Checkpoint**: Backend plumbing exists, the "no GPU" path works, and the spike has returned a recorded GO. User-story work may begin.

---

## Phase 3: User Story 1 - Render the same image faster on the Mac's GPU (Priority: P1) 🎯 MVP

**Goal**: `bhsim render --backend metal` renders any supported scene, with disk and sky, producing the same three outputs as the CPU backend, in at most a third of the time and in agreement with the CPU reference.

**Independent Test**: Render the default scene with each backend; the GPU run takes at most one third of the time; at least 99.9 % of rays match; shadow accuracy requirements hold.

### Tests for User Story 1 (write first, confirm failing)

- [X] T014 [P] [US1] Write `Tests/BlackHoleKitTests/Metal/MetalCrossingTests.swift`: with the orbits and the independent Binet reference of `PlaneCrossingTests`, the GPU's disk logic reports the same crossing indices and faces as the CPU and crossing radii within 10⁻⁴ relative; a narrow annulus around the k-th crossing yields a disk hit at index k (k = 1, 2, 3); a hit at a fourth crossing is not tested; equatorial rays never cross; an observer in the disk plane gets no crossing at the start; a ray that plunges is captured
- [X] T015 [P] [US1] Write `Tests/BlackHoleKitTests/Metal/MetalAgreementTests.swift`: for the default scene, spin 0.9 at 85°, spin 0.998 at 60°, a bare hole with a grid sky, and a cool-disk scene (reduced sizes): at least 99.9 % of ray samples have the same outcome on both backends; the 99th percentile of the relative crossing-radius difference of disk hits is below 10⁻³; the sky direction differs by at most 10⁻⁴ rad for 99.9 % of sky rays; and over pixels whose samples all hit the disk or the horizon the 99th percentile of the relative radiance difference is below 1 % (FR-003, SC-002; star-field pixels are judged through the sky-direction criterion); GPU shadow radius within 1 % of the analytic value for a = 0 and the a = 0.9 outline at 85° within 2 % (SC-003); at least 99.9 % of GPU rays have normalized residual below 10⁻³ and fewer than 0.1 % are unresolved (SC-004)
- [X] T016 [P] [US1] Write `Tests/BlackHoleKitTests/Metal/MetalRenderTests.swift`: `Renderer` with `backend = .metal` renders and `RenderOutput.write` produces the `.png`, `.exr` and `.json`, with `backend` recorded as `metal`/`float32`; options are honoured (disk off, grid and star sky, seeds, 1, 4 and 9 samples per pixel, several spins); progress is monotonic and reaches 1; diagnostics total equals the number of samples; a tiny step budget gives unresolved counts and the same exit-code rule as the CPU; the CLI `render --backend metal` exits 0 and writes the files; invalid input gives identical messages and exit codes on both backends (FR-001, FR-005, FR-006, FR-013)
- [X] T017 [P] [US1] Write `Tests/BlackHoleKitTests/Metal/MetalSpeedTests.swift` (skipped unless `BHSIM_BENCH=1`): the default scene is at least 3× faster on the GPU than on the CPU on the same machine (SC-001); print the time of each stage (camera rays, GPU passes, shading, output)

### Implementation for User Story 1

- [X] T018 [US1] Extend `GeodesicKernelSource.swift` with the disk logic: sign change of μ between accepted steps, refinement by bisection on the cubic Hermite interpolant plus one Newton correction with a Dormand–Prince step, the annulus test, the three-crossing cap (0 disables the disk), the face and index, the secant-shortened last step to land on the sky radius, and the step-budget and step-collapse terminations
- [X] T019 [US1] Refactor `Sources/BlackHoleKit/Render/Renderer.swift`: extract the per-pixel sample averaging and outcome counting into a helper shared by both backends without changing the CPU arithmetic (T003 must still pass), add backend selection to `Renderer`, and add an outcome-map API (`traceOutcomes`) that both backends implement (CPU via `RayTracer`) for the agreement tests and check
- [X] T020 [US1] Implement `Sources/BlackHoleKit/Render/Renderer+GPU.swift`: plan row bands of about 10⁶ samples, build the float64 camera rays in parallel and convert them to `GPURayInput`, run `MetalRayTracer`, convert results to `RayOutcome` (sky direction from the float32 final state via `AsymptoticDirection` in float64), shade with the existing `radiance(of:ray:)`, aggregate diagnostics (including wall time), and report progress
- [X] T021 [US1] Enable the GPU backend in `Sources/bhsim/RenderCommand.swift`: remove the rejection of `--backend metal`, validate input first (exit 2), then create the renderer and map `BackendError.unavailable` to `error: --backend: <reason>` and exit code 5; update the help text and exit-code list
- [X] T022 [US1] Run T014–T016 until they pass; choose the kernel's float32 tolerance from the sweep (relative 10⁻⁴ to 3×10⁻⁶), store it as named constants in `Sources/BlackHoleKit/Spacetime/NumericalDefaults.swift`, and record the sweep (agreement and speed per tolerance) in `research.md` §Tolerance sweep and in `docs/tolerances.md`
- [ ] T023 [US1] Overlap the CPU shading of band k with the GPU tracing of band k+1 (double buffering) in `Renderer+GPU.swift`, measure each stage separately, run T017, and record the stage times and speed-up in `research.md` §Performance
- [X] T024 [US1] Run quickstart steps 2 and 4 on this machine (default render with both backends, GPU shadow check with `tools/reference/exr_tools.py`) and record the results in `research.md` §Results

**Checkpoint**: User Story 1 works on its own: the GPU renders the same image faster, in agreement with the CPU. This is the MVP.

---

## Phase 4: User Story 2 - Verify the GPU against the reference (Priority: P2)

**Goal**: A single command renders a standard set of scenes on both backends, reports the agreement and speed-up, and fails if the GPU is out of tolerance.

**Independent Test**: Run `bhsim compare`; read the table; confirm a deliberately worsened comparison fails and names the scene and quantity.

### Tests for User Story 2 (write first, confirm failing)

- [X] T025 [P] [US2] Write `Tests/BlackHoleKitTests/Metal/BackendAgreementTests.swift`: the pure comparison function computes the outcome-match fraction, the crossing-radius and radiance difference percentiles and the verdicts correctly on synthetic inputs; a comparison with injected disagreement fails and names the scene and the quantity; the report holds the columns of `contracts/cli.md`; the overall verdict is pass only if every scene passes; a real run of the quick scene set passes on a machine with a GPU
- [X] T026 [P] [US2] Write `Tests/BlackHoleKitTests/Metal/CompareCommandTests.swift`: `bhsim compare --quick` exits 0 and prints a PASS row per scene and an overall line; with `BHSIM_FORCE_NO_GPU=1` it exits 5; an unknown option exits 2

### Implementation for User Story 2

- [X] T027 [US2] Implement `Sources/BlackHoleKit/Validation/BackendAgreement.swift`: the standard scenes (default; spin 0.9 at 85°; spin 0.998 at 60°; bare black hole with grid sky at 90°; cool disk), each 960×540 at 4 samples per pixel in the full set (SC-007) and 240×135 in the quick set, the pure comparison function, the metrics of data-model.md `SceneAgreement`, the tolerances from `docs/tolerances.md`, and the `AgreementReport`
- [X] T028 [US2] Implement `Sources/bhsim/CompareCommand.swift` (`bhsim compare [--quick]`, table output, exit codes 0, 1 and 5) and register it in `Sources/bhsim/Bhsim.swift`
- [X] T029 [US2] Run `bhsim compare` in full on this machine; record the per-scene agreement in `research.md` §Agreement and `docs/tolerances.md`; confirm it finishes in under 2 minutes (SC-007) and that a render's JSON states `metal`/`float32`

**Checkpoint**: User Stories 1 and 2 both work; the agreement is measurable on demand.

---

## Phase 5: User Story 3 - Very large and many-sample renders (Priority: P3)

**Goal**: A 3840×2160 render at 16 samples per pixel completes reliably on the GPU, with bounded memory, short GPU commands and progress, and is deterministic.

**Independent Test**: Render the large scene with the GPU backend; compare time with the CPU baseline and the image with a CPU render.

### Tests for User Story 3 (write first, confirm failing)

- [ ] T030 [P] [US3] Write `Tests/BlackHoleKitTests/Metal/MetalDeterminismTests.swift`: two GPU renders of the same inputs have identical `.png` and `.exr` bytes and identical JSON except wall time; renders with different band sizes (test hook `bandSampleCount`) are identical to each other (SC-005, FR-010)
- [ ] T031 [P] [US3] Write `Tests/BlackHoleKitTests/Metal/MetalLargeRenderTests.swift`: a stress test of 10⁶ near-critical rays (a = 0.998 around the shadow edge) completes, recording the longest single GPU pass and requiring it under 200 ms (watchdog safety, FR-009); the memory held by the GPU buffers of all bands in flight is bounded (at most 320 MB, i.e. two bands of about 144 MB at 144 bytes per sample) for any image size; and, skipped unless `BHSIM_BENCH=1`, a 3840×2160×16 render completes with progress, bounded peak memory, and at least 3× the speed of the CPU baseline (SC-006)

### Implementation for User Story 3

- [ ] T032 [US3] In `Renderer+GPU.swift` and `MetalRayTracer.swift`: make the band size configurable (default about 10⁶ samples, with a hard bound on buffer bytes), record the duration of every pass, tune `stepsPerPass` to keep each pass short, name the pass length, band size and pass-duration bound as constants in `NumericalDefaults.swift` (constitution Principle II), and report progress per band and pass
- [ ] T033 [US3] Run T030 and T031 and the 3840×2160×16 render under `/usr/bin/time -l`; record the time, the speed-up over the T001 baseline, the peak memory and the longest pass in `research.md` §Results

**Checkpoint**: All three stories work; large renders are fast and bounded.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T034 [P] Update `docs/physics.md`: the GPU backend, float32 integration (why: no 64-bit floats on the GPU), the mitigations used, the measured agreement, the row in the approximations table, and the note that results may differ in the last digits between GPU models (FR-011)
- [ ] T035 [P] Update `docs/how-it-works.md`: a section on the GPU backend (what runs where, passes, bands, precision, what to trust) and the new rows in the evidence table
- [ ] T036 [P] Update `docs/tolerances.md` with the final GPU tolerances and the evidence behind them (from T022, T029, T033); any loosening relative to the spec's targets carries a written physical justification
- [ ] T037 [P] Update `README.md`: the `--backend` option, the measured speed-up, exit code 5 and the `compare` command
- [ ] T038 [P] Merge the changes of `contracts/cli.md` into `specs/001-black-hole-image/contracts/cli.md` (backend values, `compare`, exit code 5) so the main contract is current
- [ ] T039 Run the whole of `quickstart.md` end to end on a clean copy of the repository and fix any discrepancy between the document and the actual behavior
- [ ] T040 Run the full test suite (`swift test`), `bhsim validate` and `bhsim compare`; confirm the CPU renders are unchanged (T003), there are no build warnings, and record the final results in `research.md` §Results
- [ ] T041 Apply the agreement gate: confirm every tolerance of the spec is met, or that every loosening is justified in writing in `docs/tolerances.md`; set the status of `spec.md` and add the outcome to `checklists/requirements.md` §Notes

---

## Phase 7 (Conditional): Mitigation ladder and conclusion

**Entry condition**: Only if the spike (T013) returns NO-GO, or the agreement tests of T015 or the comparison of T029 miss a tolerance. Otherwise skip this phase and note "not needed" in `research.md` §D2.

- [ ] T042 [P] Mitigation M1: tighten the step cap and tolerance near the photon region in the kernel (`GeodesicKernelSource.swift`); rerun T010, T015 and the sweep; record the effect on agreement and speed in `research.md`
- [ ] T043 Mitigation M2 (if M1 is not enough): compensated (two-float) accumulation of φ and u in the kernel; rerun the agreement tests; record the effect
- [ ] T044 Mitigation M3 (if M2 is not enough): have the kernel flag delicate rays (many steps, or a minimum radius within a band of the photon orbit) and re-trace only those on the CPU in float64 in `Renderer+GPU.swift`; rerun the agreement tests and the speed test; record the fraction re-traced and the effect
- [ ] T045 If the targets are still not met: leave `--backend metal` disabled in `RenderCommand.swift` with a message pointing to the findings, document the measured disagreement in `research.md` and `docs/physics.md`, and set the status of `spec.md` to "not achievable" (FR-012)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup; **BLOCKS all user stories**; ends with the recorded spike decision (T013)
- **US1 (Phase 3)**: depends on a GO from T013; this is the MVP
- **US2 (Phase 4)**: depends on US1 (compares the two working backends)
- **US3 (Phase 5)**: depends on US1; independent of US2, can run in parallel with it
- **Polish (Phase 6)**: depends on the stories being delivered
- **Conditional (Phase 7)**: only on NO-GO or a missed tolerance; replaces the remaining phases if the targets cannot be met

### Within Each Phase

- Tests first and failing, then implementation (T003 is the regression guard and passes throughout)
- Backend types (T006) before the Metal context (T007) before everything that creates a renderer for the GPU
- The kernel source (T011) before the host (T012) before the spike run (T013)
- Kernel disk logic (T018) and the renderer refactor (T019) before the GPU render path (T020)

### Task-Level Dependencies

- T003 before T006 (the literals are recorded before any source change)
- T006 → T007 → T008
- T009, T010 → T011 → T012 → T013 (GO/NO-GO gate)
- T018, T019 → T020 → T021 → T022 → T023 → T024
- T019, T020 → T027 → T028 → T029
- T020 → T032 → T033
- T029, T033 → T036

### Parallel Opportunities

- Setup: T001 and T002 together
- Foundational tests: T003, T004, T005, T009, T010 together
- US1 tests: T014, T015, T016, T017 together
- US2 tests: T025 and T026 together; US3 tests: T030 and T031 together
- US2 and US3 can proceed in parallel after US1
- Polish: T034, T035, T036, T037, T038 together
- Conditional: T042 can start as soon as the spike fails

### Parallel Example: User Story 1 tests

```text
Task: "Write MetalCrossingTests in Tests/BlackHoleKitTests/Metal/MetalCrossingTests.swift"     (T014)
Task: "Write MetalAgreementTests in Tests/BlackHoleKitTests/Metal/MetalAgreementTests.swift"   (T015)
Task: "Write MetalRenderTests in Tests/BlackHoleKitTests/Metal/MetalRenderTests.swift"         (T016)
Task: "Write MetalSpeedTests in Tests/BlackHoleKitTests/Metal/MetalSpeedTests.swift"           (T017)
```

---

## Implementation Strategy

### MVP First (Foundational spike, then User Story 1)

1. Phase 1 Setup and Phase 2 Foundational, ending with the spike decision (T013)
2. **Stop and decide**: GO continues; NO-GO jumps to Phase 7
3. Phase 3 User Story 1
4. **Stop and validate**: quickstart steps 2 and 4; agreement at least 99.9 %; at least 3× faster
5. Demonstrate the first GPU-rendered image next to the CPU one

### Incremental Delivery

1. Setup + Foundational → backend plumbing and a measured spike
2. + US1 → faster renders in agreement with the reference (MVP)
3. + US2 → on-demand agreement check
4. + US3 → large renders, bounded and deterministic
5. Polish → documentation, final evidence, the agreement gate
6. Phase 7 only if the targets are missed

### Notes

- Never loosen a tolerance without a written physical justification (constitution Principle III)
- The CPU backend is the reference; it must stay byte-identical (T003)
- Commit after each task or logical group
