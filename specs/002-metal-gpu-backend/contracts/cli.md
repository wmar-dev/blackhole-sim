# CLI Contract changes: GPU backend

Additions and changes to the contract of [feature 001](../../001-black-hole-image/contracts/cli.md). Everything not
listed is unchanged.

## `bhsim render --backend <cpu|metal>`

| Value | Behavior |
|-------|-----------|
| `cpu` (default) | The float64 reference backend. Output is byte-identical to previous versions. |
| `metal` | Traces rays on the GPU in float32 and shades on the CPU. Accepts every other `render` option unchanged and writes the same three files. |

- The metadata (`<out>.json`) records the backend and its precision (see `render-metadata.delta.md`).
- Progress lines are printed during GPU renders as they are for CPU renders.
- If `metal` is requested and no usable GPU, device or pipeline exists, the run prints
  `error: --backend: <reason>` to stderr, writes no files, and exits with **5**. There is no automatic fallback to
  `cpu`. Setting the environment variable `BHSIM_FORCE_NO_GPU=1` simulates a missing GPU.
- All input validation, messages and exit codes 2, 3 and 4 behave identically for both backends.

## `bhsim compare`

Runs the backend agreement check (FR-007): renders a standard set of scenes with both backends and compares them.

| Option | Default | Meaning |
|--------|---------|---------|
| `--quick` | off | Use smaller images (for a fast smoke test) |

**stdout**: a table with one row per scene: ray-outcome match fraction, crossing-radius difference, sky-direction difference,
99th-percentile and maximum radiance difference (disk and horizon pixels), shadow-area difference between the backends (and, for the non-spinning edge-on scene, each backend's shadow-radius error against the analytic value), GPU residual statistics, CPU and GPU time and the speed-up, each
with a PASS or FAIL against its tolerance, then an overall line.

**Exit codes**: 0 all scenes pass; 1 at least one quantity is outside its tolerance (the failing scene and
quantity are named); 5 the GPU backend is unavailable.

The default run completes in under 2 minutes on the reference machine (SC-007).

## Exit codes (complete list after this feature)

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | `validate` or `compare` found a failing check |
| 2 | Invalid input (including unknown options and unparsable values) |
| 3 | Output could not be written |
| 4 | Render completed but more than 0.1 % of rays were unresolved or out of tolerance (images still written) |
| 5 | The requested backend is unavailable (no usable GPU) |
