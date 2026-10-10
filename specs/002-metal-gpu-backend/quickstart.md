# Quickstart: Validate the GPU Backend

Prerequisites: an Apple-silicon Mac (reference: Apple M4), macOS 14+, Swift 6.x, the repository built with
`swift build -c release`. Expected values below are the targets from [spec.md](spec.md); the results of the actual
run are recorded in [research.md](research.md) as the work proceeds. All commands run from the repository root.

## 1. Confirm the CPU backend is untouched (FR-002)

```bash
git worktree add ../blackhole-sim-main main          # a checkout of the version without this feature
(cd ../blackhole-sim-main && swift build -c release && .build/release/bhsim render --width 400 --height 225 --out out/main)
.build/release/bhsim render --width 400 --height 225 --out out/branch
cmp ../blackhole-sim-main/out/main.exr out/branch.exr && cmp ../blackhole-sim-main/out/main.png out/branch.png && echo identical
git worktree remove --force ../blackhole-sim-main
```

Expected: a CPU render produces byte-identical `.png` and `.exr` to a render made before this feature (the JSON gains
only the `backend` key). The test suite pins this with the existing geometry fingerprint and determinism tests.

## 2. Render the default scene on the GPU (User Story 1)

```bash
.build/release/bhsim render --backend metal --out out/gpu_default
.build/release/bhsim render --backend cpu   --out out/cpu_default
```

Expected: both finish; the GPU run takes at most one third of the CPU run's time (CPU about 21 s on an M4); both write
`.png`, `.exr` and `.json`; the GPU JSON says `"backend": {"name": "metal", "precision": "float32"}` and the CPU JSON says
`"cpu"`/`"float64"`. Open both PNGs: they are visually indistinguishable.

## 3. Compare the backends (User Story 2)

```bash
.build/release/bhsim compare
```

Expected: a table with one row per scene (default; spin 0.9 at 85°; spin 0.998 at 60°; bare hole with grid sky; cool
disk), each showing at least 99.9 % ray-outcome match, a 99th-percentile radiance difference below 1 %, GPU shadow
errors within 1 % (non-spinning) and 2 % (Kerr outline), residuals within 10⁻³ for at least 99.9 % of rays, and a
speed-up of 3× or more; overall `PASS`; exit code 0; under 2 minutes. Try `bhsim compare --quick` for a fast check.

## 4. Accuracy of GPU images themselves (FR-004)

```bash
.build/release/bhsim render --backend metal --spin 0 --inclination 90 --width 800 --height 800 --fov 12 --out out/gpu_shadow
uv run python tools/reference/exr_tools.py out/gpu_shadow.exr --shadow 12
```

Expected: `shadow angular radius = 0.0514…` rad, within 1 % of the analytic 0.051462 rad (same as the CPU check).

## 5. Determinism (SC-005)

```bash
.build/release/bhsim render --backend metal --width 400 --height 225 --out out/g1
.build/release/bhsim render --backend metal --width 400 --height 225 --out out/g2
cmp out/g1.exr out/g2.exr && echo identical
```

Expected: `identical` (and the PNG too; the JSON differs only in the wall time).

## 6. Very large render (User Story 3, SC-006)

```bash
.build/release/bhsim render --backend metal --width 3840 --height 2160 --samples 16 --out out/gpu_4k
```

Expected: completes without error, shows progress, and takes at most one third of the CPU time for the same
render (the CPU takes several minutes). Memory stays bounded (check with `/usr/bin/time -l`).

## 7. No GPU (SC-008, FR-008)

```bash
BHSIM_FORCE_NO_GPU=1 .build/release/bhsim render --backend metal --out out/nogpu; echo "exit $?"
ls out/nogpu.* 2>&1 | head -1
```

Expected: `error: --backend: ...` on stderr within 2 seconds, `exit 5`, and no output files. The same render with
`--backend cpu` is unaffected.

## 8. Tests

```bash
swift test
```

Expected: all tests pass; the GPU tests run on a machine with a GPU and are skipped (not failed) elsewhere. See
[contracts/cli.md](contracts/cli.md), [contracts/gpu-buffers.md](contracts/gpu-buffers.md) and
[data-model.md](data-model.md).
