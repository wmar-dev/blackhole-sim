# CLI Contract changes: movies

Additions to the contract of [feature 001](../../001-black-hole-image/contracts/cli.md) (as updated by feature 002). Everything not listed is unchanged.

## `bhsim movie assemble`

Encodes a folder of numbered display PNGs into an MP4.

| Option | Default | Meaning |
|--------|---------|---------|
| `--frames <dir>` | required | Folder containing the frames |
| `--prefix <text>` | detected | File-name prefix before the number (`frame_` in `frame_0001.png`) |
| `--fps <n>` | 24 | Frame rate, 1 ≤ n ≤ 240 |
| `--out <file>` | `movie.mp4` | Output movie; its record is written next to it as `<file>.json` (`movie.mp4.json`) |
| `--encoder <auto\|ffmpeg\|avfoundation>` | auto | `auto` uses ffmpeg if found, else the built-in encoder; `ffmpeg` fails with exit 6 if ffmpeg is unusable (no silent fallback) |
| `--ffmpeg <path>` | searched | Path of the ffmpeg executable |
| `--quality <high\|standard\|small>` | standard | Compression quality: CRF 16 / 18 / 23 (ffmpeg), 0.35 / 0.25 / 0.12 bit per pixel per frame (AVFoundation) |
| `--allow-gaps` | off | Accept missing frame numbers (the frames present play in order) |
| `--force` | off | Overwrite an existing movie |

**stdout**: progress while encoding, then the path, frame count, duration, picture size and frame rate of the movie, and the encoder used.

## `bhsim movie animate`

Renders a frame sequence by sweeping one parameter, then assembles it. Accepts every option of `bhsim render` (except `--out`, which is replaced by the one below) and holds them constant across frames, including `--backend`.

| Option | Default | Meaning |
|--------|---------|---------|
| `--sweep <inclination\|distance\|spin>` | required | The parameter that changes |
| `--from <v>` / `--to <v>` | required | Start and end values (units as for `render`: degrees, M, dimensionless) |
| `--duration <s>` | required | Movie length in seconds |
| `--fps <n>` | 24 | Frame rate; frame count = round(duration × fps), at least 1 |
| `--out <file>` | `movie.mp4` | Output movie; frames go to `<file without extension>_frames/`; record in `<file>.json` |
| `--keep-exr` | off | Also write each frame's 32-bit physical-intensity image |
| `--encoder`, `--ffmpeg`, `--quality`, `--force` | as above | As above |

Behaviour:

- Every frame's settings are validated before any frame is rendered. The first invalid frame stops the run with exit code 2 and a message naming the frame number, the swept value and the valid range.
- Frames already complete from an earlier identical run are kept and skipped; the others are rendered. Changing any option invalidates the frames it affects.
- The movie uses one exposure reference for all frames (the largest over the sweep) and records it.
- Progress is printed as `frame k/N`.
- Before rendering, the estimated disk space for the frames is printed.

## `bhsim render --reference-radiance <value>` (new, advanced)

Normalise radiance to `value` (Y-weighted W m⁻² sr⁻¹) instead of the hottest unshifted disk emission. Lets a single frame be reproduced exactly as it appears in an animation. Default: unchanged behaviour. `value` must be positive and finite (exit code 2 otherwise).

## Exit codes (complete list after this feature)

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | `validate` or `compare` found a failing check |
| 2 | Invalid input: unknown options, unparsable values, invalid parameter in any frame, no frames or bad numbering, differing or odd frame sizes, existing output without `--force` |
| 3 | Frames or records could not be written |
| 4 | Rendering completed but more than 0.1 % of all rays of the movie were unresolved or out of tolerance (frames and movie still written) |
| 5 | The requested backend is unavailable (frames already rendered are kept) |
| **6** | The video could not be encoded or written (the requested encoder is unavailable, or it failed); frames are kept |
