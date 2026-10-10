# Data Model: GPU Acceleration on Apple Silicon

Existing entities (BlackHole, Observer, AccretionDisk, Sky, RenderConfig, RayOutcome, RenderedImage, Diagnostics) are
unchanged; see [feature 001](../001-black-hole-image/data-model.md). New and extended entities:

## Backend

| Field | Type | Rule |
|-------|------|------|
| name | enum `cpu` \| `metal` | `cpu` is the default and the reference |
| precision | enum `float64` \| `float32` | Fixed by the backend: `cpu` → `float64`, `metal` → `float32` |

Selected by the user (`--backend`). Recorded in every render's metadata as `BackendInfo`. `RenderConfig` gains a
`backend` field (default `cpu`); validation of every other input is identical for both backends (FR-013).

**Errors**: `BackendError.unavailable(reason)` when `metal` is requested and there is no usable GPU, pipeline or
device (also when `BHSIM_FORCE_NO_GPU=1`). It is never converted into a CPU fallback.

## GPURayInput (one per sample, host → GPU)

All values are the float32 conversion of the float64 camera ray; E = 1 for every ray.

| Field | Meaning |
|-------|---------|
| u, vu | 1/r and du/dλ′ at the observer |
| mu, vmu | cos θ and dμ/dλ′ at the observer |
| phi | azimuth at the observer |
| L, Q | photon angular momentum and Carter constant (E = 1) |

The exact byte layout is in [contracts/gpu-buffers.md](contracts/gpu-buffers.md).

## GPURayState (persistent across passes, GPU only)

The integration state of an unfinished ray, so a ray can be advanced a few hundred steps per command and resumed.

| Field | Meaning |
|-------|---------|
| u, vu, mu, vmu, phi | current `RayState` |
| step | current step size h |
| steps | accepted steps so far |
| crossings | plane crossings seen (≤ 3) |
| side | sign of μ on the last accepted step (−1, 0, +1) |
| maxResidual | largest normalized first-integral residual so far |
| minSin2 | smallest sin²θ = 1 − μ² along the path so far (how close the ray came to a pole) |
| landing | counter for the secant landing at the sky radius |
| status | running or finished |

**State transitions**: `running` → `finished` with one outcome, exactly as for the CPU `RayTracer`: captured
(horizon), disk (crossing inside the annulus), sky, or unresolved (step budget or step collapse).

## GPURayResult (one per sample, GPU → host)

| Field | Meaning |
|-------|---------|
| outcome | captured, disk, sky, unresolved (budget), unresolved (failure) |
| crossingIndex, face | for disk hits: which crossing (1–3) and which side the ray came from; `face` also carries the **delicate** flag (bit 1) for rays that came close to a pole |
| radius | Boyer–Lindquist radius at the disk hit |
| u, vu, mu, vmu, phi | final state (used for sky rays; the CPU computes the direction in float64) |
| maxResidual | maximum normalized residual along the ray |
| steps | accepted steps |

The host converts a `GPURayResult` into the existing `RayOutcome` and feeds the unchanged shading code.

## KernelParameters (constant for a render)

Spin; the sky stop 1/r_sky; the horizon capture u = 1/(r₊ + 10⁻³) and 1/r₊; disk inner and outer radius and the
crossing cap (0 when the disk is disabled); the relative tolerance of u and du/dλ′, the tighter relative tolerance of the
angular components, and the absolute floor; the sin²θ below which a ray is flagged delicate; steps per pass; total step
budget; ray count in the band.

## Band

A horizontal group of image rows processed as a unit: its camera rays (host), its `GPURayInput`/`GPURayState`/
`GPURayResult` buffers, and its shaded pixels. Size chosen for about 10⁶ samples (bounded memory, FR-009).

## SceneAgreement (backend agreement check)

| Field | Meaning |
|-------|---------|
| scene | name and configuration (spin, inclination, disk, sky, size, samples) |
| rays | number of ray samples compared |
| outcomeMatchFraction | fraction of samples with the same outcome on both backends |
| radiusDifference | for samples that hit the disk on both, the 99th percentile and maximum relative difference of the crossing radius |
| radianceDifference | over pixels whose samples all hit the disk or the horizon: 99th percentile and maximum relative difference of linear radiance |
| skyDirectionDifference | for sky rays: the fraction within 10⁻⁴ rad and the maximum angular difference of the assigned direction |
| shadowErrorCPU, shadowErrorGPU | shadow-outline error of each backend against the analytic curve |
| residualGPU | maximum and 99.9th percentile residual; fraction over 10⁻³; unresolved fraction |
| cpuSeconds, gpuSeconds, speedup | timings |
| verdicts | pass/fail per quantity against the tolerances |

An `AgreementReport` is the list of scenes plus an overall verdict; `bhsim compare` exits with success only if all pass.

## Relationships

`RenderConfig.backend` selects the `Backend`. For the `metal` backend a render is a sequence of `Band`s; each band turns
its camera rays into `GPURayInput`s, the kernel produces `GPURayResult`s, each of which becomes a `RayOutcome` that
the existing shading code turns into pixels. `AgreementReport` is built by running both backends on the same
scenes and comparing their `RayOutcome`s and pixels.
