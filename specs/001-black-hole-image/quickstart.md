# Quickstart: Validate the Black Hole Renderer

Prerequisites: macOS 14+ on Apple Silicon, Swift 6.x toolchain (`swift --version`).

## 1. Build

```bash
swift build -c release
```

Expected: builds the `BlackHoleKit` library and the `bhsim` executable with no warnings.

## 2. Run the physics validation

```bash
swift test
.build/release/bhsim validate
```

Expected: all tests pass. `validate` prints a table of measured vs. reference values, covering photon sphere, ISCO, critical impact parameter (3√3), weak-field deflection (4M/b), first-integral residuals, disk flux, and shadow outline. See [research.md](research.md) §Validation and the tolerances in [spec.md](spec.md) (SC-001 to SC-004).

## 3. Render the default image (User Story 1)

```bash
.build/release/bhsim render --out out/default
```

Expected: `out/default.png`, `out/default.exr`, `out/default.json`; completes in under 10 minutes at the default 1920×1080 (SC-005). Open the PNG: a dark circular shadow, a bright ring-like photon ring, the disk with its far side lensed above and below the shadow, and a lensed star field.

## 4. Check the shadow size (SC-001)

```bash
.build/release/bhsim render --spin 0 --inclination 90 --width 800 --height 800 --fov 12 --out out/shadow
```

Expected: the measured shadow angular radius in `out/shadow.exr` is within 1% of the analytic value for a static observer at r = 100 M, arcsin(3√3·√(1 − 2M/r)/r), which corresponds to the critical impact parameter 3√3 M (`bhsim validate` automates this).

## 5. Spinning black hole (User Story 2)

```bash
.build/release/bhsim render --spin 0.9 --inclination 85 --out out/spin09
```

Expected: shadow visibly flattened and offset relative to `--spin 0`; outline within 2% of the analytic Kerr shadow curve (SC-002). Rendering `--spin 0` reproduces the User Story 1 image exactly.

## 6. Doppler and redshift (User Story 3)

Open `out/default.exr` and compare the two sides of the disk. Expected: the side moving toward the observer is brighter and bluer; `swift test --filter Disk` checks the shift factor g against analytic values.

## 7. Determinism (SC-006)

```bash
.build/release/bhsim render --width 400 --height 225 --out out/a
.build/release/bhsim render --width 400 --height 225 --out out/b
cmp out/a.exr out/b.exr && echo identical
```

Expected: `identical`. If ImageIO embeds a timestamp and `cmp` reports a difference, compare pixel data instead (T029 checks which applies).

## 8. Invalid input

```bash
.build/release/bhsim render --spin 1.2
```

Expected: exit code 2 and a message stating spin must satisfy 0 ≤ a < 1.

See [contracts/cli.md](contracts/cli.md) for all options and exit codes, and [data-model.md](data-model.md) for entities.
