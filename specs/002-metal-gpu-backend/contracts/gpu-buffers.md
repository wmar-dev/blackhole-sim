# GPU buffer layouts and kernel interface

The contract between the Swift host (`MetalRayTracer`) and the Metal kernel. Layout mismatches between the two are
silent and catastrophic, so the layouts below are fixed, use only 4-byte scalars (no vector types, which have
alignment surprises), and are checked by a test that compares `MemoryLayout` sizes and offsets in Swift with sizes
reported by the kernel.

All structs are 4-byte aligned, tightly packed, little-endian. `float` = 32-bit IEEE float, `uint` = 32-bit unsigned,
`int` = 32-bit signed.

## Structures

### RayInput (32 bytes)

| Offset | Type | Field | Meaning |
|--------|------|-------|---------|
| 0 | float | u | 1/r at the observer |
| 4 | float | vu | du/dλ′ |
| 8 | float | mu | cos θ |
| 12 | float | vmu | dμ/dλ′ |
| 16 | float | phi | azimuth |
| 20 | float | L | photon angular momentum (E = 1) |
| 24 | float | Q | Carter constant (E = 1) |
| 28 | float | pad | reserved, zero |

### RayState (64 bytes)

| Offset | Type | Field |
|--------|------|-------|
| 0 | float | u |
| 4 | float | vu |
| 8 | float | mu |
| 12 | float | vmu |
| 16 | float | phi |
| 20 | float | step (current step size h) |
| 24 | float | maxResidual |
| 28 | float | minSin2 (smallest sin²θ = 1 − μ² along the path so far) |
| 32 | uint | steps (accepted so far) |
| 36 | uint | crossings (plane crossings seen, ≤ cap) |
| 40 | int | side (sign of μ at the last accepted step: −1, 0, +1) |
| 44 | uint | landing (secant landing attempts at the sky radius) |
| 48 | uint | status (0 running, 1 finished) |
| 52 | uint | pad |
| 56 | uint | pad |
| 60 | uint | pad |

### RayResult (48 bytes)

| Offset | Type | Field | Meaning |
|--------|------|-------|---------|
| 0 | uint | outcome | 1 captured, 2 disk, 3 sky, 4 unresolved (step budget), 5 unresolved (failure); 0 only while running |
| 4 | uint | crossingIndex | disk hits: 1–3 |
| 8 | uint | face | bit field: bit 0 = lower face (disk hits; 0 upper, ray came from μ > 0); bit 1 = **delicate**: the path came closer to a pole than `polarFlagSin2`, so the host must re-trace this ray in float64 |
| 12 | float | radius | disk hits: Boyer–Lindquist radius at the crossing |
| 16 | float | u | final state |
| 20 | float | vu | |
| 24 | float | mu | |
| 28 | float | vmu | |
| 32 | float | phi | |
| 36 | float | maxResidual | maximum normalized first-integral residual |
| 40 | uint | steps | accepted steps |
| 44 | uint | pad | |

### KernelParameters (64 bytes, constant buffer)

| Offset | Type | Field |
|--------|------|-------|
| 0 | float | spin (a) |
| 4 | float | skyU (1/r_sky) |
| 8 | float | horizonU (1/r₊) |
| 12 | float | captureU (1/(r₊ + 10⁻³)) |
| 16 | float | diskInner |
| 20 | float | diskOuter |
| 24 | float | relativeTolerance (u and du/dλ′) |
| 28 | float | absoluteTolerance (floor for every component) |
| 32 | uint | rayCount (rays in this band) |
| 36 | uint | stepsPerPass |
| 40 | uint | stepBudget (total accepted steps per ray) |
| 44 | uint | maxCrossings (0 disables the disk) |
| 48 | float | angleTolerance (relative tolerance of μ, dμ/dλ′ and φ) |
| 52 | float | polarFlagSin2 (rays whose path comes closer to a pole than this sin²θ are flagged delicate) |
| 56 | uint | pad |
| 60 | uint | pad |

## Kernels

| Kernel | Purpose |
|--------|---------|
| `initializeStates` | one thread per ray: build `RayState` from `RayInput` (step size, counters, side from the sign of μ) |
| `traceRays` | one thread per ray: advance an unfinished ray by up to `stepsPerPass` accepted steps, writing back the state; on termination fill `RayResult` and set `status = 1`; add 1 to the unfinished counter if still running |

### `initializeStates` buffers

| Index | Address space | Type | Content |
|-------|---------------|------|---------|
| 0 | constant | KernelParameters | |
| 1 | device const | RayInput[] | input |
| 2 | device | RayState[] | output |
| 3 | device | RayResult[] | zeroed |

### `traceRays` buffers

| Index | Address space | Type | Content |
|-------|---------------|------|---------|
| 0 | constant | KernelParameters | |
| 1 | device const | RayInput[] | read (the ray's L and Q; they are not stored in RayState) |
| 2 | device | RayState[] | read and written |
| 3 | device | RayResult[] | written when a ray finishes |
| 4 | device | atomic_uint | count of rays still running after this pass (host zeroes it before each pass) |

Grid: one dimension, `rayCount` threads; threadgroup width a multiple of the pipeline's `threadExecutionWidth` (32).
Threads with `gid ≥ rayCount` or `status == 1` return immediately.

## Host loop

1. Fill the `RayInput` buffer (shared storage, written by the CPU in parallel).
2. Dispatch `initializeStates`.
3. Repeat: zero the unfinished counter; dispatch `traceRays`; wait; read the counter; stop when it is 0. Each dispatch
   is its own command buffer, so no command runs longer than one pass.
4. Read `RayResult` and convert each to a `RayOutcome`.

Arithmetic: compiled with fast-math disabled; all operations float32.
