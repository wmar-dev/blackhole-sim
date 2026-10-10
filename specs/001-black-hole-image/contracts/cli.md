# CLI Contract: `bhsim`

## Commands

### `bhsim render [options]`

Render an image. With no options it renders the default scene.

| Option | Default | Meaning |
|--------|---------|---------|
| `--spin <a>` | 0.0 | Dimensionless spin, 0 ≤ a < 1 |
| `--distance <r>` | 100 | Observer radius in M |
| `--inclination <deg>` | 80 | Angle from the spin axis, degrees, 0 < i < 180 |
| `--fov <deg>` | 30 | Horizontal field of view, degrees (default frames the disk out to 20 M from 100 M) |
| `--width <px>` / `--height <px>` | 1920 / 1080 | Image size |
| `--samples <n>` | 4 | Samples per pixel (perfect square) |
| `--disk-outer <r>` | 20 | Outer disk radius in M |
| `--accretion-rate <f>` | 0.1 | Eddington fraction (temperature scale) |
| `--mass <Msun>` | 10 | Black hole mass in solar masses (scale only) |
| `--no-disk` | off | Omit the accretion disk (bare black hole and sky) |
| `--sky <starfield\|grid>` | starfield | Background |
| `--seed <n>` | 1 | Seed for sky and sample jitter |
| `--exposure <ev>` | 0 | Display exposure offset in stops (PNG only) |
| `--max-steps <n>` | 100000 | Integrator step budget per ray; rays needing more are counted as unresolved (diagnostic knob) |
| `--reference-radiance <value>` | hottest unshifted disk emission | Radiance (Y-weighted W m⁻² sr⁻¹) that maps to 1.0 in the output; lets a frame of a movie be reproduced as a single render (positive, finite; exit 2 otherwise) |
| `--out <basename>` | `blackhole` | Output basename |
| `--backend <cpu\|metal>` | cpu | `cpu` is the float64 reference; `metal` traces rays on the Apple GPU in float32 (feature 002). Metadata records the backend and precision. If no usable GPU exists: `error: --backend: ...`, exit 5, no files written, no CPU fallback |

**Outputs**: `<basename>.png` (tone-mapped sRGB, 8-bit), `<basename>.exr` (32-bit float linear), `<basename>.json` (metadata, validated by [render-metadata.schema.json](render-metadata.schema.json)).

**stdout**: progress (percent complete) and a final diagnostics summary. **stderr**: errors and warnings.

**Exit codes**: 0 success; 2 invalid input, including unknown options and unparsable values (the message names the offending option and the valid range); 3 output could not be written; 4 render completed but more than 0.1% of rays exceeded the first-integral bound or ended unresolved (images are still written); 5 the requested backend (`metal`) is unavailable; 6 (movie commands) the video could not be encoded or written, the frames are kept; 130 a movie command was interrupted (finished frames are kept).

**Input rejection (clear messages)**: a ≥ 1 or a < 0; non-positive mass, size, samples or FoV; non-square sample count; observer at or inside the ergosphere (static observer does not exist), including inside the horizon; inclination exactly 0° or 180° (use a value such as 0.01° instead); `r_out` ≤ r_isco.

### `bhsim validate`

Runs the built-in physics checks (the analytic subset of the test suite) and prints a pass/fail table with measured values and tolerances. Exit 0 if all pass, 1 otherwise.

### `bhsim compare [--quick]`

Renders five standard scenes (960×540 at 4 samples per pixel; `--quick`: 240×135) with both backends and reports, per scene, ray-outcome match, crossing-radius and sky-direction differences, radiance differences, shadow agreement, GPU residual statistics, times and speed-up, each with PASS/FAIL against the tolerances in `docs/tolerances.md`. Exit 0 if every scene passes, 1 otherwise (the scene and quantity are named), 5 if the GPU is unavailable. Takes about 40 s on an Apple M4.

### `bhsim movie assemble` and `bhsim movie animate`

Make an MP4 from numbered PNG frames (`assemble --frames <dir> [--prefix] [--fps] [--out] [--encoder auto|ffmpeg|avfoundation] [--ffmpeg <path>] [--quality high|standard|small] [--allow-gaps] [--force]`) or render the frames first by sweeping one parameter (`animate --sweep inclination|distance|spin --from --to --duration [--fps] [every render option] [--keep-exr] ...`, default 9 samples per pixel, frames in `<out>_frames/`, resumable). Both write `<movie>.json` (schema: `specs/003-movie-from-frames/contracts/movie-record.schema.json`). Exit codes: 0; 2 invalid input (including an invalid frame of a sweep, no or inconsistent frames, an existing output without `--force`); 3 cannot write; 4 more than 0.1 % of the movie's rays unresolved or out of tolerance (movie still written); 5 backend unavailable; 6 the video could not be encoded or written; 130 interrupted. Full contract: [specs/003-movie-from-frames/contracts/cli.md](../../003-movie-from-frames/contracts/cli.md).

## Determinism

Identical options (including `--seed`) produce identical `.exr`, `.png` and `.json` content (apart from the wall-time field in diagnostics), independent of core count.
