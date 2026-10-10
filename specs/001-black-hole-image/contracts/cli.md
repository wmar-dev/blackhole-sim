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
| `--out <basename>` | `blackhole` | Output basename |
| `--backend <cpu\|metal>` | cpu | `metal` is available only once the GPU backend passes its agreement tests |

**Outputs**: `<basename>.png` (tone-mapped sRGB, 8-bit), `<basename>.exr` (32-bit float linear), `<basename>.json` (metadata, validated by [render-metadata.schema.json](render-metadata.schema.json)).

**stdout**: progress (percent complete) and a final diagnostics summary. **stderr**: errors and warnings.

**Exit codes**: 0 success; 2 invalid input, including unknown options and unparsable values (the message names the offending option and the valid range); 3 output could not be written; 4 render completed but more than 0.1% of rays exceeded the first-integral bound or ended unresolved (images are still written).

**Input rejection (clear messages)**: a ≥ 1 or a < 0; non-positive mass, size, samples or FoV; non-square sample count; observer at or inside the ergosphere (static observer does not exist), including inside the horizon; inclination exactly 0° or 180° (use a value such as 0.01° instead); `r_out` ≤ r_isco.

### `bhsim validate`

Runs the built-in physics checks (the analytic subset of the test suite) and prints a pass/fail table with measured values and tolerances. Exit 0 if all pass, 1 otherwise.

## Determinism

Identical options (including `--seed`) produce identical `.exr`, `.png` and `.json` content (apart from the wall-time field in diagnostics), independent of core count.
