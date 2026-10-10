# Data Model: Movies from Individual Frames

## FrameSequence

| Field | Meaning |
|-------|---------|
| folder | Directory holding the frames |
| prefix | Common file-name prefix before the number |
| numbers | Sorted integer frame numbers found |
| width, height | Pixel size common to all frames (even numbers) |
| files | URLs in playing order |

Validation (FR-004): at least one frame; one prefix; no gaps unless allowed; equal sizes; even dimensions.

## SweepParameter and Animation

| Field | Meaning |
|-------|---------|
| parameter | `inclination` (degrees), `distance` (M) or `spin` (dimensionless) |
| from, to | Start and end values; frame i uses from + (to − from)·i/(N − 1) |
| fps, duration | Frame rate and length in seconds; N = round(duration × fps), N ≥ 1 |
| base | The `RenderConfig` shared by all frames (including backend, seed, size, samples) |
| referenceRadiance | Common normalisation: the largest per-frame reference over the sweep (research D5) |
| frameConfig(i) | `base` with the parameter set and `referenceRadianceOverride` set |

Validation: every `frameConfig(i)` passes `RenderConfig.validate()` before any frame is rendered.

## FrameRecord (per-frame JSON, `frame_NNNN.json`)

The existing render metadata (inputs, units, backend, precision, reference radiance, diagnostics) of that frame, plus `index` and the swept value. A frame is complete when this file exists, matches the expected inputs, and its PNG exists with the right size.

## Movie

| Field | Meaning |
|-------|---------|
| path | The `.mp4` file |
| codec, container | `h264`, `mp4` |
| fps, frameCount, duration | Timing |
| width, height | Picture size |
| colour | Primaries BT.709, matrix BT.709, transfer sRGB, limited range, 4:2:0 |
| encoder | name (`ffmpeg` or `avfoundation`), version, quality preset and the setting it maps to, and whether the file bytes are reproducible |

## MovieRecord (`<movie>.json`, schema in `contracts/movie-record.schema.json`)

| Field | Meaning |
|-------|---------|
| version | bhsim version |
| movie | the Movie fields above, including the encoder and its settings |
| source | `assembled` (frames folder) or `animation` |
| animation | for animations: parameter, from, to, duration, fps, frame count |
| common | the render settings shared by all frames (for animations; the swept parameter excluded) |
| backend | name and precision of the backend that rendered the frames |
| referenceRadiance | the common exposure reference |
| seed | sky and jitter seed |
| diagnostics | summed ray counts, unresolved count, rays over the residual bound, worst residual, wall time |
| frames | per frame: index, swept value, unresolved fraction, bad-ray fraction |

## Relationships

An `Animation` produces one `RenderConfig` per frame; each render yields a PNG and a `FrameRecord`; the PNGs form a `FrameSequence`, which `MovieEncoder` turns into a `Movie`; the `MovieRecord` summarises all of it. `assemble` starts from an existing `FrameSequence` and writes a `MovieRecord` with `source = assembled` (no animation or per-frame diagnostics unless the frame JSONs are present).
