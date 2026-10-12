# Quickstart: Validate the Black Hole Renderer

Prerequisites: macOS 14+ on Apple Silicon, Swift 6.x toolchain (`swift --version`). Steps 4 and 6 also use
[uv](https://docs.astral.sh/uv/) (`uv sync` once) to read the EXR output with an independent Python reader.

All commands run from the repository root. This guide was executed end to end on a clean copy of the repository
(task T063); the expected results below are what that run produced.

## 1. Build

```bash
swift build -c release
```

Expected: builds the `BlackHoleKit` library and the `bhsim` executable with no warnings (about 25 s from scratch).

## 2. Run the physics validation

```bash
swift test
.build/release/bhsim validate
```

Expected: all tests pass; `validate` prints a table of measured vs. reference values (horizon, ISCO, photon sphere,
critical impact parameter 3√3, light deflection, sky direction, integration residuals, shadow outline for a = 0 and
0.9, Novikov–Thorne flux, shift factor, determinism) ending in `22/22 checks passed`, exit code 0. See
[research.md](research.md) §Validation and the tolerances in [../../docs/tolerances.md](../../docs/tolerances.md).

## 3. Render the default image (User Story 1)

```bash
.build/release/bhsim render --out out/default
```

Expected: `out/default.png`, `out/default.exr`, `out/default.json`; about 20 s on an Apple M4 at the default
1920×1080 with 4 samples per pixel (SC-005 allows 10 minutes); `0 unresolved` rays and a residual far below 10⁻³.
Open the PNG: a dark shadow, a thin bright photon ring at its edge, the near side of the disk in front, the far
side lensed over the top, a second image of the disk curling underneath, and lensed stars.

## 4. Check the shadow size (SC-001)

```bash
.build/release/bhsim render --spin 0 --inclination 90 --width 800 --height 800 --fov 12 --out out/shadow
uv run python tools/reference/exr_tools.py out/shadow.exr --shadow 12
```

Expected: `shadow angular radius = 0.0514…` rad, within 1 % of the analytic value for a static observer at
r = 100 M, arcsin(3√3·√(1 − 2M/r)/r) = 0.051462 rad (measured on the clean run: 0.17 % apart with the default
4 samples per pixel; the test suite measures 0.006 % at the ray level).

## 5. Spinning black hole (User Story 2)

```bash
.build/release/bhsim render --spin 0.9 --inclination 85 --out out/spin09
.build/release/bhsim render --spin 0 --out out/spin0
cmp out/default.exr out/spin0.exr && echo identical
```

Expected: the a = 0.9 shadow is flattened on the left (approaching) side and offset to the right, the disk's inner
edge is pulled in to r_isco ≈ 2.32 M; its outline matches the analytic Kerr curve (the test suite measures
1.5×10⁻⁴ at the ray level and 0.8 % in a rendered image, against the 2 % requirement). `--spin 0` reproduces the
default image byte for byte.

## 6. Doppler and redshift (User Story 3)

A cool disk (10⁹ M☉, low accretion rate) shows the color shift clearly:

```bash
.build/release/bhsim render --spin 0.9 --inclination 80 --mass 1e9 --accretion-rate 1e-4 --out out/cool
```

Expected: the approaching (left) side is far brighter and bluer than the receding (right) side. Measured on the
clean run from the EXR, left/right luminance ≈ 11× and blue/red ≈ 1.62 vs 0.67. The default hot disk (a
stellar-mass hole, T ≈ 4×10⁶ K) is in the Rayleigh–Jeans tail in the visible band: about 1.6× brighter on the
left with unchanged hue. `swift test --filter Disk` checks the shift factor g and the flux against independent
references.

## 7. Determinism (SC-006)

```bash
.build/release/bhsim render --width 400 --height 225 --out out/a
.build/release/bhsim render --width 400 --height 225 --out out/b
cmp out/a.exr out/b.exr && echo identical
```

Expected: `identical` (the EXR holds no timestamps; the PNG is identical too; the JSON differs only in the wall
time).

## 8. Invalid input

```bash
.build/release/bhsim render --spin 1.2
```

Expected: `error: --spin: spin must satisfy 0 <= a < 1 (got 1.2)` and exit code 2. Unknown options and unparsable
values also exit with 2.

See [contracts/cli.md](contracts/cli.md) for all options and exit codes, and [data-model.md](data-model.md) for
entities.
