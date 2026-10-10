# blackhole-sim

Physically accurate images of a black hole. Every pixel is a light ray traced backward through the curved
spacetime of a Kerr (rotating) black hole, from a static observer to the horizon, a thin accretion disk, or the
distant sky. The disk's colour and brightness come from the Novikov–Thorne temperature profile with the full
relativistic frequency shift.

The approach is the one behind the black hole "Gargantua" in the film *Interstellar* (2014), whose images were
produced by ray tracing in a Kerr spacetime, as described by the film's science team (James, von Tunzelmann,
Franklin and Thorne, [Gravitational lensing by spinning black holes in astrophysics, and in the movie
Interstellar](https://arxiv.org/abs/1502.03808), 2015). This project is an independent implementation, not the film's
code. It is much simpler: it traces single rays (the film's renderer, DNGR, propagates ray bundles for
flicker-free IMAX frames) for a static observer, and produces still images.

![A non-spinning stellar-mass black hole with its accretion disk, seen from 80°](docs/images/default.png)

The default scene: a non-spinning, 10 M☉ black hole, disk viewed at 80°. The far side of the disk is lensed over
the top of the shadow, a second image of the disk curls under it, and the thin bright ring at the shadow's edge
is the photon ring. Stars near the hole are stretched into arcs.

![A spinning (a = 0.9) supermassive black hole with a cool disk](docs/images/spin09-cool-disk.png)

A spinning black hole (a/M = 0.9) with a cool disk (10⁹ M☉, low accretion rate). The shadow is flattened on the
side where the disk approaches the observer (left), the approaching gas is Doppler-boosted and bluer, and the
receding side is dimmed and reddened.

## Requirements

- macOS 14 or later (developed on Apple Silicon), Swift 6 toolchain (Xcode 16 or later).
- Optional: [uv](https://docs.astral.sh/uv/) to regenerate the independent reference values in `tools/reference/`.

## Build and run

```bash
swift build -c release
.build/release/bhsim render --out out/default      # 1920×1080, 4 samples per pixel: about 22 s on an Apple M4
.build/release/bhsim validate                      # physics checks against independent reference values
swift test                                         # the full test suite
.build/release/bhsim render --backend metal --out out/gpu   # same image on the GPU: 5–7× faster on an M4
.build/release/bhsim compare                       # CPU vs GPU agreement on five scenes (about 40 s)
```

`render` writes three files next to the chosen basename:

| File | Content |
|------|---------|
| `<out>.png` | Tone-mapped 8-bit sRGB image for viewing |
| `<out>.exr` | 32-bit float linear radiance, unmodified (1.0 = brightest unshifted disk emission) |
| `<out>.json` | All inputs, units, derived radii, seed, reference radiance and ray diagnostics |

Identical options (including `--seed`) give byte-identical `.png` and `.exr` files on a given machine,
regardless of core count.

Common options (all have defaults; `bhsim render --help` lists them):

| Option | Default | Meaning |
|--------|---------|---------|
| `--spin <a>` | 0 | Dimensionless spin, 0 ≤ a < 1 |
| `--inclination <deg>` | 80 | Observer angle from the spin axis |
| `--distance <r>` | 100 | Observer radius in M |
| `--fov <deg>` | 30 | Horizontal field of view |
| `--width`, `--height`, `--samples` | 1920, 1080, 4 | Image size and samples per pixel (a perfect square) |
| `--mass <Msun>`, `--accretion-rate <f>` | 10, 0.1 | Disk temperature scale (mass and Eddington fraction) |
| `--disk-outer <r>`, `--no-disk` | 20, off | Outer disk radius; omit the disk entirely |
| `--sky <starfield\|grid>`, `--seed <n>` | starfield, 1 | Background and its seed |
| `--exposure <stops>` | 0 | Display exposure for the PNG only |
| `--backend <cpu\|metal>` | cpu | `metal` traces rays on the Apple GPU in float32 (validated against the CPU reference by `bhsim compare`) |

Invalid input is rejected with a message naming the option and its valid range (exit code 2). Exit code 4
means the image was written but more than 0.1 % of rays were unresolved or out of tolerance. Exit code 5 means
`--backend metal` was requested but no usable GPU exists (there is no silent fallback to the CPU). See
[the CLI contract](specs/001-black-hole-image/contracts/cli.md).

## How accurate is it?

The renderer is checked against independent calculations (high-precision Python in `tools/reference/`, closed
forms, and published values), not against itself:

- Shadow of a non-spinning hole: angular radius within 0.006 % of arcsin(3√3·√(1 − 2M/r)/r).
- Kerr shadow outline for a = 0.5, 0.9, 0.998 at 45°, 85°, 90°: within 1.5×10⁻⁴ at the ray level; within 0.8 %
  in a rendered image.
- Light deflection against exact quadrature; Einstein ring of a source directly behind the hole at the
  predicted radius.
- Integration residual (the Carter first integrals) below 3×10⁻⁹ for every ray of the default image; none
  unresolved.
- Novikov–Thorne flux against the Page–Thorne closed form and the conservation-law integral (they agree to
  10⁻²⁵); shift factors against a metric-tensor reference.

`bhsim validate` runs a quick subset; `swift test` runs everything. Tolerances and the evidence behind them are
in [docs/tolerances.md](docs/tolerances.md).

## What is and isn't modeled

Modeled: Kerr geodesics, a static observer with a pinhole camera, an opaque thin equatorial disk with the
Novikov–Thorne flux, gravitational redshift, Doppler shift and beaming, blackbody colour, higher-order disk
images (up to 3 plane crossings), a seeded synthetic star field.

Not modeled: disk thickness, jets, polarization, radiative transfer, observer motion, charge, animation,
real sky surveys. A hot (stellar-mass) disk looks nearly uniform blue-white in the visible band because it is in
the Rayleigh–Jeans tail; use `--mass 1e9 --accretion-rate 1e-4` for a disk whose colour varies visibly. Every
approximation, with its validity and error, is listed in [docs/physics.md](docs/physics.md).
For a physicist's walk-through of the method, from Kerr geodesics to the colour of a pixel, with a worked
example ray, see [docs/how-it-works.md](docs/how-it-works.md).

## Project layout

```
Sources/BlackHoleKit/   Spacetime, Geodesic, Camera, Disk, Sky, Radiometry, Render, Output, Validation
Sources/bhsim/          Command-line tool (render, validate)
Tests/BlackHoleKitTests Tests and the JSON reference fixtures they compare against
tools/reference/        Python scripts that generate the fixtures (uv run python tools/reference/<script>.py)
docs/                   physics.md (equations, approximations), tolerances.md
specs/001-black-hole-image/   Specification, plan, research, data model, contracts, tasks
```

The design process is recorded under `specs/`; the project principles (accurate physics, explicit units,
validation against known results, numerical rigor) are in `.specify/memory/constitution.md`.

## Related video

- Veritasium, [How to Understand What Black Holes Look Like](https://www.youtube.com/watch?v=zUyH3XhpLTo) (YouTube)

## License

MIT, see [LICENSE](LICENSE).
