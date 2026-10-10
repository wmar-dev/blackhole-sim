# Research: Movies from Individual Frames

All Technical Context unknowns are resolved below. Physics and conventions are those of
[feature 001](../001-black-hole-image/research.md); this document covers only what is new.

## Facts established on the reference machine (spike, 2026-10-10)

Six 640×360 display PNGs (inclination 80° to 30°) were encoded with a throwaway Swift program using `AVAssetWriter` and, for comparison, with the installed `ffmpeg` 9.0.2 (GPL build with libx264, libx265, ProRes, AV1, FFV1 and VideoToolbox encoders).

| Fact | Result | Consequence |
|------|--------|-------------|
| Headless encode from a command-line process | Works; status "completed" in 0.47 s total | No GUI session or app bundle needed (D1) |
| Output | `h264`, 640×360, `yuv420p`, 24 fps, 6 frames, 0.25 s, profile High | Plays in QuickTime and any common player (SC-008) |
| Colour tags | Without tags: unknown. With `AVVideoColorPropertiesKey`: primaries/matrix BT.709, and transfer `iec61966-2-1` (sRGB) accepted | The video can be tagged with exactly the encoding of the PNGs (D1) |
| Fidelity | Decoded frame vs source PNG: PSNR 40.0 dB and 41.1 dB (8 Mbit/s, 640×360) | Lossy but visually transparent; a floor is set in D7 |
| Determinism | Two encodes: decoded-frame MD5s identical; the files differ in header bytes (creation time) | Reproducibility is defined on decoded frames (D6) |
| ffmpeg libx264, CRF 18, `-fflags +bitexact -flags:v +bitexact`, BT.709 + sRGB tags | `h264`, `yuv420p`, 56 KB for the 6 frames; PSNR 39.0 dB (first frame) | Same quality class as AVFoundation (154 KB, 40.0 dB) at 36 % of the size |
| ffmpeg determinism | Two encodes are **byte-identical** | Reproducible movie files (D6), which AVFoundation cannot give |
| ffmpeg availability | Not part of macOS; installed here via Homebrew at `/opt/homebrew/bin/ffmpeg` | Optional, with a fallback (D1) |

## Decisions

### D1. Encoder: ffmpeg preferred, AVFoundation as the built-in fallback

- **Decision**: A small `MovieEncoder` interface with two implementations, selected by `--encoder auto|ffmpeg|avfoundation` (default `auto`).
  - **ffmpeg** (`libx264`, MP4, `yuv420p`): frames are streamed to the process's standard input as PNG images (one at a time, so memory stays bounded). Flags: `-fflags +bitexact -flags:v +bitexact` for reproducible files, `-movflags +faststart`, and colour tags BT.709 primaries and matrix, sRGB transfer, limited range. Quality is a constant rate factor (CRF).
  - **AVFoundation** (`AVAssetWriter`, H.264, MP4): one 32-bit BGRA sRGB `CVPixelBuffer` per frame, the same colour tags, an average bit rate.
  - `auto` uses ffmpeg when an executable with libx264 is found (the `PATH`, then `/opt/homebrew/bin`, then `/usr/local/bin`; `--ffmpeg <path>` overrides), otherwise AVFoundation. `--encoder ffmpeg` fails with exit code 6 if ffmpeg is not usable; it never silently falls back.
  - One quality setting for both: `--quality high|standard|small` (default `standard`) = CRF 16 / 18 / 23 for ffmpeg and 0.35 / 0.25 / 0.12 bit per pixel per frame for AVFoundation. Both are tagged with the sRGB transfer function of the PNGs so players decode with the curve the tone map used (tagging BT.709 would change contrast).
  - The record states the encoder, its version string and the settings used (FR-012, Constitution IV).
- **Rationale**: Measured on the same six frames (spike table): libx264 gave 36 % of the file size at the same quality, **byte-identical files** across runs (the project values reproducibility), and the option of other codecs later (HEVC, ProRes, AV1 and lossless FFV1 are present). AVFoundation needs nothing installed, so the feature works on any Mac and SC-008 holds everywhere. Preferring ffmpeg when present but never requiring it uses the better tool without making it a build or run prerequisite.
- **Costs accepted**: Two code paths to test; results differ slightly between encoders (compression noise, file size) so the record must say which was used; `auto` can give a different encoder on a different machine, so a user who needs the same encoder everywhere passes `--encoder`. The ffmpeg build here is GPL-licensed; it is run as a separate program and not linked or redistributed, so the project's MIT licence is unaffected.
- **Alternatives considered**: (a) AVFoundation only: nothing to install, but larger files and no byte-identical output; rejected as the sole path. (b) ffmpeg only: simplest code and best output, but makes an external program a hard requirement and gives a poor failure mode where it is missing; rejected as the sole path. (c) Linking libx264 or libav*: licensing and build complexity for no benefit over a subprocess. (d) HEVC, ProRes or 10-bit now: more compatibility questions and out of scope (spec Assumptions); the interface leaves room for `--codec` later.

### D2. Frame discovery and ordering

- **Decision**: Frames are files `<prefix><digits>.png` in one folder. The prefix is taken from the first matching file (or `--prefix`); all frames must share it. They are sorted by the integer value of the digits, so `frame_2` precedes `frame_10`. A gap in the integer sequence is an error naming the missing number, unless `--allow-gaps` is given. A frame whose pixel size differs from the first is an error naming it. Odd widths or heights are rejected with a message suggesting an even size, because the H.264 encoder needs even dimensions (cropping silently would alter the picture).
- **Rationale**: Predictable, testable rules that match FR-004 and the edge cases.
- **Alternatives considered**: Sorting by name (breaks on unpadded numbers); sorting by modification time (not reproducible).

### D3. Animation: linear sweep of one parameter

- **Decision**: `animate` takes `--sweep inclination|distance|spin`, `--from`, `--to`, `--duration <s>` and `--fps <n>` (frame count N = round(duration × fps), at least 1). Frame i (0-based) uses `from + (to − from) · i/(N − 1)`, with i/(N − 1) = 0 for N = 1, so the first and last frames are exactly the start and end values. All other render options apply unchanged and are held constant. Every frame's `RenderConfig` is built and validated with the existing `validate()` before the first frame is rendered; the first invalid frame is reported with its number and value and the run exits with code 2.
- **Rationale**: Meets FR-006 to FR-008 with the validation that already exists, so messages and exit codes are the same as for a single render. Endpoints are included so SC-004 can be checked exactly.
- **Alternatives considered**: Easing curves and keyframes (out of scope); sweeping several parameters (out of scope); sweeping field of view or azimuth (azimuth does nothing for an axisymmetric hole; field of view is a camera zoom, not a physical change, and can be added later).

### D4. Frame storage, atomicity and resume

- **Decision**: Frames go to `<out>_frames/frame_0001.png` with a per-frame JSON `frame_0001.json` (its render metadata and diagnostics). The EXR is not written by default (about 8 MB per 1080p frame), and `--keep-exr` writes it. The PNG is written first to a temporary name and renamed; the JSON is written last and is the completion marker. A frame counts as done only if its JSON exists, records exactly the inputs this run would use (full configuration including backend and reference radiance, ignoring wall time), and its PNG exists with the right size. Done frames are skipped; others are rendered. Disk space needed (frames × width × height × 3 bytes as an upper bound, plus EXR if kept) is printed before rendering.
- **Rationale**: An interrupted run (killed, power, Ctrl-C) never leaves a half-written frame that is mistaken for a good one; changing any option never reuses stale frames; memory does not grow with the frame count (FR-009).
- **Alternatives considered**: Hashing the configuration (same effect, less readable); keeping all frames in memory (unbounded).

### D5. One brightness reference for the whole movie

- **Decision**: The renderer normalises radiance to the hottest unshifted disk emission, which depends on the spin (through r_isco), mass and accretion rate. For an inclination or distance sweep this reference is the same for all frames. For a spin sweep it differs per frame, which would make brightness jump or drift for a non-physical reason. `RenderConfig` gains an optional `referenceRadianceOverride`; `animate` sets it to the largest per-frame reference of the sweep (computed up front from `NovikovThorne.referenceLuminance`, which is cheap), so all frames share one normalisation and the brighter frames are not clipped differently. The value is recorded in the movie record and in each frame's metadata. `render` also gets `--reference-radiance <value>` so any frame can be reproduced as a single render. With the override unset, behaviour and output are unchanged.
- **Rationale**: FR-013. The largest value is independent of frame order and makes every frame's absolute brightness comparable.
- **Alternatives considered**: First frame's reference (depends on sweep direction); per-frame normalisation (the problem to avoid); automatic exposure (non-physical).

### D6. Determinism of a movie

- **Decision**: The same command gives identical PNG frames (existing guarantee). With the ffmpeg encoder it also gives a **byte-identical movie file** on the same machine and ffmpeg version (spike: bit-exact flags, software encoder). With the AVFoundation fallback the movie is only equivalent, not reproducible: the file bytes differ (creation time) and, as found in T019, even the decoded frames can differ between runs because the hardware encoder is not deterministic (see "Reproducibility of the AVFoundation encoder"); a different Mac model may also produce a different bit stream. This is documented. Tests assert byte identity for ffmpeg and equivalence (same frames, each within the fidelity floor) for AVFoundation.
- **Rationale**: Honest statement of what each encoder guarantees (Constitution IV).
- **Alternatives considered**: Forcing a fixed creation time in AVFoundation: not available through the system API.

### D7. Tolerance for the lossy encode

- **Decision**: The video is lossy (H.264, 4:2:0 chroma). The test compares each decoded frame with its source PNG and requires a PSNR of at least 35 dB at the default quality with either encoder, on the standard test frames, and requires the frame order to be exactly right by decoding frames of distinct flat colours (which are not affected by compression artefacts in the middle of a frame). The spike measured 39–41 dB for both encoders; 35 dB leaves a margin for scenes with fine star fields, where 4:2:0 subsampling blurs colour at single-pixel stars.
- **Rationale**: Constitution III: the tolerance is justified from measurement and from the nature of the codec, not tuned to pass. The EXR/PNG frames remain the physical record; the movie is for viewing.
- **Alternatives considered**: Lossless video (large files, narrow compatibility); no fidelity test (leaves colour tagging errors undetected).

### D8. Command-line shape and exit codes

- **Decision**: A command group `bhsim movie` with subcommands `assemble` and `animate`. `animate` reuses the option set of `render` through a shared option group. Existing exit codes keep their meaning: 0 success, 2 invalid input (including an existing output without `--force`, bad numbering, odd size), 3 output could not be written, 4 more than 0.1 % of rays over the whole movie unresolved or out of tolerance (movie still written), 5 requested backend unavailable. New: **6** the video could not be encoded or written (encoder unavailable or failed); frames are kept. See [contracts/cli.md](contracts/cli.md).
- **Rationale**: Consistent with the existing contract (FR-004, FR-005, FR-008, FR-011, FR-014).
- **Alternatives considered**: Top-level `assemble` and `animate`: flatter but crowds the command list.

### D9. Reusing the GPU between frames

- **Decision**: The Metal device, queue and compiled kernels are cached for the life of the process, so frame 2 onwards does not recompile the kernel (about 0.2 s each) and a 120-frame animation spends no time on repeated set-up.
- **Rationale**: SC-002 headroom, and no behaviour change.
- **Alternatives considered**: One `Renderer` for all frames (not possible since the configuration changes each frame).

## Risks

- **R1**: The fallback hardware encoder's output differs between Mac models or macOS versions, and ffmpeg output can change with the ffmpeg version; this affects only the compressed bytes, not the frames, and the record states the encoder and version (D1, D6, D7).
- **R2**: Rays are re-traced for every frame, so a long 4K animation is slow even on the GPU (7× faster than the CPU, about 45 s for 4K at 16 samples). The tool reports progress and supports resume; no change to the physics is made to speed it up.
- **R3**: Very small stars blur in 4:2:0 chroma; documented in the physics notes and visible only on close inspection (D7).
- **R4**: The AVFoundation path currently decodes ~4 dB worse in Apple's decoder than ffmpeg's decoder shows for the same file (see Additional checks); fix with colour attachments on the pixel buffers and re-measure before relying on the 35 dB floor.

## Additional checks (2026-10-10, before tasks)

| Check | Result | Consequence |
|-------|--------|-------------|
| RGB→YUV matrix in ffmpeg | Identical output with and without an explicit BT.709 matrix (the colour tags select it) | Pass `out_color_matrix=bt709` explicitly anyway, so the result does not depend on that default |
| Streaming PNGs to ffmpeg's standard input (`image2pipe`) | Byte-identical to reading the same files directly | The encoder can stream one frame at a time (bounded memory) and handle gaps and unpadded numbers without ffmpeg's own file patterns |
| Odd picture size | libx264 refuses 639×359 ("width not divisible by 2") | Confirms the rule in D2: reject odd sizes up front with a clear message |
| PNG colour information | The renderer's PNGs carry an `sRGB` chunk | Reading them as sRGB is correct, not an assumption |
| Apple's own decoder (the QuickTime pipeline) on the **ffmpeg** file | 39.1 dB vs the source PNG, matching ffmpeg's own decode (39.0 dB) | Players that use Apple's decoder show the right colours (SC-008) |
| Apple's decoder on the **AVFoundation** file | 36.2 dB, against 40.0 dB when the same file is decoded by ffmpeg | A ~4 dB colour disagreement: the writer converts BGRA to YUV without being told the buffers' colour space. Fix to apply in implementation: attach BT.709 / sRGB colour attachments to every pixel buffer; then re-measure. Until it is fixed the 35 dB floor has only 1.2 dB of margin on this path |

**Consequences for the tests (D7):** fidelity is measured with Apple's decoder (always available, and what QuickTime uses) and, when ffmpeg is present, also with ffmpeg's decoder; both must reach 35 dB. A deliberately mis-tagged movie must fail the test, so the test is shown to be able to detect a colour error.

**Open design points for `tasks.md`:**

1. **Interruption.** Ctrl-C during `animate` must stop the encoder process, remove its temporary output, and leave finished frames (D4). During `assemble` a partial movie must never be left at the final path (write to a temporary name, then rename).
2. **Fixed sample pattern (DECIDED: keep).** The sample jitter depends on the seed and pixel, not the frame, so every frame has the same sub-pixel sample offsets. This is stable (stars do not shimmer, the first and last frames equal single renders, and every frame is a pure function of its inputs) but it is a fixed pattern. The thin photon ring at 4 samples per pixel will speckle differently from frame to frame because the geometry moves. Decision (2026-10-10): determinism comes first, so there is **no per-frame seed variation and no `--vary-seed` option**; `animate` defaults to `--samples 9` (a single `render` keeps 4) and the docs recommend 9 or more for movies. Cost: about 2.25× the render time of 4 samples per pixel, so the SC-002 scene (120 frames, 1280×720) takes roughly 5–6 minutes at 9 on the GPU; SC-002 itself is stated at 4 samples per pixel. Rejected: varying `--seed` per frame (it also drives the star field, so stars would jump); a separate per-frame jitter seed (stars shimmer, larger files, SC-004 only for the first frame, a metadata-schema change).
3. **ffmpeg version drift.** Byte-identical files hold for the same machine and ffmpeg version; the record stores the version (D1).
4. **Memory of the GPU context per frame.** Each frame builds a renderer; the kernel cache (D9) avoids recompiling, and the band buffers are released between frames. Measure on the 120-frame run.
5. **Colour of the movie versus the PNG.** 4:2:0 subsampling blurs colour at single-pixel stars (R3); compare a star-field crop by eye once implemented.

## Implementation findings (running log)

- **R4 confirmed and fixed in principle (T008/T009).** A flat-colour test movie written with `AVAssetWriter` and no colour information decoded up to **28 levels** off in a plain reader. Adding the colour properties to the writer settings **and** BT.709/sRGB attachments to every pixel buffer brought every frame within 8 levels. T015 applies the same to the production encoder.
- **Availability.** `AVVideoTransferFunction_IEC_sRGB` exists only on macOS 15 and later, and the package targets macOS 14. The AVFoundation encoder uses the sRGB transfer tag on macOS 15+ and falls back to the BT.709 transfer tag on macOS 14 (a small contrast difference there, to be documented); the ffmpeg encoder is unaffected.
- **Frame counting.** Reading compressed samples of an AVFoundation-written file gave 16 samples for 12 frames; the reader therefore counts decoded, displayed frames.

### AVFoundation bit-rate calibration (T015)

The first rule (0.25 bit per pixel per frame, proportional to picture size) gave only 32.8 dB on 160×90 frames, below the 35 dB floor, because small pictures with fine detail need more bits per pixel. Worst-frame PSNR against the source PNGs (Apple's decoder), six renders of the default scene per size:

| Size | 0.5 Mbit/s | 1 | 2 | 4 | 8 | 16 |
|------|-----------|---|---|---|---|----|
| 160×90 | 37.1 dB | 37.8 | 38.0 | 38.0 | 38.0 | 38.0 |
| 640×360 | 34.4 | 37.4 | 38.1 | 39.9 | 41.6 | 42.0 |
| 1280×720 | 32.7 | 34.0 | 37.8 | 39.2 | 40.0 | 41.7 |

Rule adopted: bit rate = max(floor, bits-per-pixel × pixels × fps) with 0.35 / 0.25 / 0.12 bit per pixel per frame and floors of 2 / 1 / 0.5 Mbit/s for high / standard / small. At 24 fps this gives for `standard` 1.0 Mbit/s at 160×90 (37.8 dB), 1.4 at 640×360 (about 37.7) and 5.5 at 1280×720 (about 39.5); every combination of size and preset reaches at least 35 dB by the table. ffmpeg's CRF 18 gave 39.0 dB on the same kind of frame at a third of the AVFoundation size.

### Reproducibility of the AVFoundation encoder (T019)

D6 assumed that AVFoundation gives identical decoded frames on repeated runs (spike: 6 frames at 640×360, same MD5s). A larger check (48 frames at 640×360, two runs, decoded with ffmpeg) found **different decoded frames from line 12 onward**: the hardware encoder is not deterministic (its rate control can vary between runs). The unit test on 6 small frames had passed by luck. Consequences, applied in the plan, tests and docs:

- AVFoundation output is **equivalent, not reproducible**: same frames in the same order, each within the fidelity floor of its source, but neither file bytes nor decoded pixels are guaranteed to repeat. `reproducibleFile == false` is the record's statement of this.
- Only the ffmpeg encoder gives reproducible movies (byte-identical files verified on 48 frames); a user who needs reproducible movies should use `--encoder ffmpeg`, and the CLI says so in `--help`.
- The determinism test (T034) asserts byte identity for ffmpeg and equivalence for AVFoundation.
- The PNG frames remain exactly reproducible with either encoder; only the compressed video is affected.

### Measurements (T019)

- SC-001: 120 frames of 1920×1080 assembled in **4.6 s with ffmpeg** (3.6 MB) and **2.9 s with AVFoundation** (7.6 MB) against the 30 s target.
- ffmpeg fidelity by picture size (worst of 6 frames, Apple's decoder): 160×90 34.2 dB (standard), 320×180 36.6, 640×360 38.8, 1280×720 40.7; `small` (CRF 23) gives 31.5 / 34.1 / 36.2 / 38.1 dB, `high` (CRF 16) 35.0 / 37.3 / 39.5 / 41.4 dB. The 35 dB floor therefore holds for all presets at 640×360 and above and for standard/high at 320×180 and above; pictures smaller than that should use `--quality high`.
- Quickstart steps 1 and 2 run: 48 frames of 640×360 give a 2.0 s, 24 fps, H.264 movie; ffmpeg files byte-identical; unpadded numbers play in numerical order; a missing folder, a gap and an existing output each exit 2 with a message naming the problem.

### Results of Phase 4 (T032)

| Criterion | Target | Measured (Apple M4, release build, Metal backend) |
|-----------|--------|---------------------------------------------------|
| SC-002: 120 frames, 1280×720, 4 samples per pixel, rendered and assembled | < 5 min | **148 s** (442 M rays, 0 unresolved, worst residual 3.0×10⁻⁶) |
| Same at the `animate` default of 9 samples per pixel | (estimate 5–6 min) | **278 s** = 4.6 min (995 M rays, 0 unresolved, worst residual 3.4×10⁻⁶) |
| SC-004: first and last frame equal single renders | pixel-identical | `cmp` identical for frames 1 and 120 (GPU, 1280×720, 9 samples) |
| SC-006: resume after interruption | identical to uninterrupted | stopped with SIGINT after 35 of 72 frames; the rerun said "rendered 37, kept 35"; 0 of 72 frames differ from an uninterrupted run |
| SC-007: invalid sweep rejected | < 2 s, nothing rendered | **0.04 s**, exit 2, no frames written: "frame 48 of 48 (distance = 1.2) is not a valid render: --distance: no static observer exists at r = 1.2 M …" |
| Spin sweep brightness (D5) | one reference, no steps | 24 frames, one `referenceRadiance` in all frame records; largest frame-to-frame change of mean luma 0.7 % (mean 0.5 %) |

**Memory leak found and fixed (FR-009).** The first 120-frame run had a peak footprint of 9.9 GB. Measuring 30 and 60 frames showed linear growth (2.5 GB and 4.8 GB, about 75 MB per 1280×720 frame): a command-line loop never drains the main thread's autorelease pool, so the Metal buffers of every frame stayed alive. Wrapping each frame's render in `autoreleasepool` made the footprint flat (434 MB at 30 and 60 frames; 454 MB over all 120 frames at 9 samples per pixel). A single render was never affected, which is why feature 002's measurements did not show it.

**Other findings.** The sky is defined directly in reference units, so a reference override rescales the disk but not the star field (the test was corrected to say so); this is the existing convention and is the right behaviour for a fixed backdrop. `animate` checks everything it can before rendering: timing and every frame's settings, an existing output, the requested encoder, and backend availability (exit 5), so a mistake costs no render time.

### Results of Phase 5 (T033–T037)

- The movie record of an animation holds every field of data-model `MovieRecord`; `tools/reference/check_movie_record.py` (the `jsonschema` package, independent of the Swift code) validates real records from `animate` (inclination and spin sweeps) and from `assemble`, and rejects a record with `referenceRadiance` removed and `codec` changed. The Swift tests use their own small JSON-Schema checker against the same schema file.
- The schema makes the render information (`animation`, `common`, `backend`, `referenceRadiance`, `seed`, `diagnostics`, `frames`) required only for `source: animation`; a plain `assemble` of arbitrary PNGs has only the movie fields, and `assemble` of an `animate` frames folder recovers the render information from the frame records.
- Determinism (`MovieDeterminismTests`): PNG frames and the record (except wall time) repeat exactly with either encoder; the ffmpeg movie file repeats byte for byte; the AVFoundation movie is equivalent (6 frames, each pair within the 35 dB floor); an interrupted and resumed run equals an uninterrupted one in frames, record and the common settings.
- Stale-binary lesson: the release binary used for a quickstart check was older than the code; always rebuild before running the quickstart (the Python checker showed `assembled` for an animation, which exposed it).

### Visual check of the encoded frames (T045, risks R3 and R4)

Frame 50 of a 120-frame 1280×720 GPU animation (9 samples per pixel) was compared with the same frame decoded from the movie made by each encoder (3× nearest-neighbour crops, source | ffmpeg CRF 18 | built-in encoder, 1.7 MB and 2.7 MB for the 5 s movie):

- **Photon ring and disk edge**: the thin lensed arc and the bright inner rim are intact in both movies; ffmpeg is slightly softer at the one-pixel scale. No colour shift is visible.
- **Stars**: the brightest stars keep their shape and colour in both movies. At ffmpeg's standard quality the faintest stars lose contrast or vanish and the colour of single-pixel stars is blurred (the 4:2:0 chroma subsampling, risk R3); the built-in encoder, which spends more bits here, keeps more of them. For star-rich scenes use `--quality high` (CRF 16) with ffmpeg. This is the expected cost of a lossy viewing format; the PNG and EXR frames keep every star.

## Final results (Phase 6)

- Clean copy of the repository (no `.build`, `out`, `.venv`): release build, all of `quickstart.md` steps 1 to 7 run as written. `swift test`: **254 tests in 50 suites pass**; warning-free build; `bhsim validate` 22/22; `bhsim compare` passes all five scenes; CPU renders unchanged (`CPUUnchangedTests` and the existing suites pass after the `RenderOptions` refactor and the optional reference override).
- Success criteria: SC-001 met (120 frames of 1920×1080 in 4.6 s with ffmpeg, 2.9 s built in; target 30 s). SC-002 met (148 s at 4 samples per pixel, 278 s at the default 9; target 5 min at 4). SC-003 met (frame count, rate, size and order read back from the movie in every encoder test). SC-004 met (first and last frames identical to single renders). SC-005 met for the frames with either encoder and for the whole file with ffmpeg; the built-in encoder is equivalent, not identical (documented). SC-006 met (0 of 72 frames differ after a resumed run). SC-007 met (0.04 s). SC-008: the movies decode correctly with Apple's decoder (the player pipeline of QuickTime) and with ffmpeg; the default player application itself was not opened in this session.
- Defects found and fixed by measurement during implementation: untagged-colour error of the built-in writer (R4, up to 28 levels); bit-rate floors for small pictures; a thread-pool deadlock when many tests block in the built-in encoder at once (suites serialized, caveat documented in the encoder); a linear memory leak across frames (autorelease pool per frame, 75 MB per 1280×720 frame before the fix); the stale-binary and `PATH`-search quickstart errors.
- Not covered: HEVC, ProRes, HDR video, multi-parameter sweeps, easing or keyframes, overlays, audio (out of scope by the spec); other Mac models and macOS versions (the sRGB transfer tag needs macOS 15; macOS 14 falls back to the BT.709 tag, a small contrast difference there, untested); a manual check in the QuickTime Player application.
