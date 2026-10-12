# Implementation Plan: GPU Acceleration on Apple Silicon

**Branch**: `002-metal-gpu-backend` | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-metal-gpu-backend/spec.md`

## Summary

Add an opt-in GPU backend that traces the rays on the Mac's GPU while everything that decides the *color* of a pixel stays on the CPU in float64. The GPU does the one expensive thing, integrating the Kerr geodesics in float32 and classifying each ray (horizon, disk crossing, sky), and returns a compact record per ray. The existing CPU code then shades from those records exactly as it does today (blackbody at g·T, star-field lookup, averaging, tone mapping, output). The CPU backend is untouched and remains the reference.

Because Apple GPUs have no 64-bit floats, the plan is built around proving agreement: a spike first measures speed and agreement on a small ray set (go/no-go); work is split into short passes so the system watchdog never fires; images are processed in row bands so memory is bounded; and a backend agreement check compares both backends ray by ray. If float32 cannot meet the tolerances, a documented mitigation ladder applies (tighter control, compensated accumulation, re-tracing only the delicate rays on the CPU), and if that fails the feature ends by documenting findings and leaving the backend disabled (FR-012).

## Technical Context

**Language/Version**: Swift 6.4 plus a Metal Shading Language compute kernel, compiled at run time from an embedded source string (no offline shader toolchain needed to run or build)

**Primary Dependencies**: Apple's Metal framework (system). No new package dependencies.

**Storage**: Files only (PNG, OpenEXR, JSON), as before

**Testing**: Swift Testing. GPU tests are skipped when no GPU is present; agreement tests compare the backends ray by ray and pixel by pixel against the CPU reference.

**Target Platform**: macOS 14+ on Apple silicon (reference machine: Apple M4, unified memory, 32-lane SIMD groups)

**Project Type**: Library plus command-line tool (extends the existing package)

**Performance Goals**: Default scene (1920×1080, 4 samples per pixel) at least 3× faster than the CPU backend (CPU about 21 s); 3840×2160 at 16 samples per pixel at least 3× faster; agreement check under 2 minutes; "no GPU" error within 2 s. Estimated headroom is 5–10× (about 6×10⁴ lane-operations per ray against roughly 1.4×10¹² per second of GPU capability), unmeasured until the spike.

**Constraints**: GPU arithmetic is float32 only; no single GPU command may run long enough for the system watchdog to cut it off; memory use bounded independently of image size; same-machine determinism; CPU renders byte-identical to before; no silent CPU fallback.

**Scale/Scope**: Up to 3840×2160×16 ≈ 133 million samples per image, processed in bands of rows.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Accurate Physics | The GPU integrates the same equations (Mino time in u = 1/r, same potentials, same crossing logic). The one new approximation, float32 arithmetic, is documented with its regime, mitigation and a *measured* error (the agreement report). Shading is not ported, so color physics is identical by construction. | PASS, conditional on the agreement gate below |
| II. Explicit Units and Conventions | No change: geometrized units, same conventions; the buffer layouts between Swift and the kernel are specified in `contracts/gpu-buffers.md` so units and field meanings are explicit | PASS |
| III. Validation Against Known Results (Test-First) | Agreement tests (backend vs. CPU reference, which is itself validated against independent references) are written before the kernel passes them; GPU renders must also meet the original shadow, outline, deflection and residual criteria | PASS (enforced in tasks) |
| IV. Numerical Rigor and Reproducibility | Precision choice is forced by hardware and justified in research D2; mitigation ladder and measurement plan defined; determinism on one machine is a requirement and a test; fast-math is disabled | PASS |

**Agreement gate**: the GPU backend may be switched on only if the agreement tests pass (spec FR-003, FR-004, FR-012). This is a gate on enabling the feature, not on starting it.

**Post-design re-check (after Phase 1)**: PASS. Carried as risks, not violations: float32 sensitivity of rays near the photon ring (research D2, R1) and SIMD divergence limiting the speed-up (research D3, R2).

## Project Structure

### Documentation (this feature)

```text
specs/002-metal-gpu-backend/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── cli.md                    # CLI changes: --backend, compare command, exit code 5
│   ├── render-metadata.delta.md  # Metadata schema addition (backend, precision)
│   └── gpu-buffers.md            # Swift ⇄ kernel buffer layouts and kernel interface
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks, not created here)
```

### Source Code (repository root)

```text
Sources/BlackHoleKit/
├── Metal/                          # NEW
│   ├── MetalContext.swift          # device, queue, pipeline; availability errors; BHSIM_FORCE_NO_GPU override
│   ├── GeodesicKernelSource.swift  # the MSL source (embedded string)
│   └── MetalRayTracer.swift        # buffers, pass loop, band execution, result download
├── Render/
│   ├── Backend.swift               # NEW: Backend enum (cpu, metal), BackendInfo, BackendError
│   ├── Renderer+GPU.swift          # NEW: band pipeline, CPU shading from GPU ray records
│   └── Renderer.swift              # edited: backend selection; CPU path unchanged
├── Validation/
│   └── BackendAgreement.swift      # NEW: standard scenes, agreement metrics, verdicts
└── Output/Metadata.swift           # edited: backend and precision fields
Sources/bhsim/
├── RenderCommand.swift             # edited: --backend metal enabled; exit code 5
└── CompareCommand.swift            # NEW: `bhsim compare` (backend agreement check)
Tests/BlackHoleKitTests/
└── Metal/                          # NEW
    ├── MetalKernelTests.swift      # derivative, step and potentials vs. the CPU implementation
    ├── MetalAgreementTests.swift   # ray-by-ray and pixel agreement, accuracy criteria on GPU renders
    ├── MetalDeterminismTests.swift # repeated and banded renders identical
    └── MetalUnavailableTests.swift # no-GPU error, no silent fallback
```

**Structure Decision**: One new `Metal/` module inside the existing library, one new renderer extension, and one new command. The CPU physics modules are not modified; the GPU kernel is a deliberate second implementation of the integrator and crossing logic, kept in step with the CPU one by direct unit tests of its pieces and by the ray-by-ray agreement tests.

## Complexity Tracking

No constitution violations. One deliberate cost is recorded:

| Added complexity | Why needed | Simpler alternative rejected because |
|------------------|------------|--------------------------------------|
| A second implementation of the integrator and plane-crossing logic (in the kernel) | The feature is GPU acceleration; the kernel must run the integration | Running everything on the CPU is the status quo and gives no acceleration. Porting shading as well was rejected (research D1) as it adds float32 color error and a 32 MB star-grid structure for no speed benefit. |
