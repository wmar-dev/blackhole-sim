---

description: "Task list for Movies from Individual Frames"
---

# Tasks: Movies from Individual Frames

**Input**: Design documents from `/specs/003-movie-from-frames/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: REQUIRED. Constitution Principle III mandates test-first validation. Within every phase, write the test tasks first and confirm they FAIL before starting the implementation tasks they cover. Encoder-dependent tests are skipped (not failed) when that encoder is absent.

**Organization**: Tasks are grouped by user story: US1 assemble existing frames (P1, the MVP), US2 render and assemble an animation (P2), US3 record and reproducibility (P3).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1, US2, US3 (maps to spec.md); none for Setup, Foundational and Polish
- Include exact file paths in descriptions

## Path Conventions

Swift package at the repository root: `Sources/BlackHoleKit/Movie/` (new), `Sources/bhsim/`, `Tests/BlackHoleKitTests/Movie/` (new), `docs/`. The encoder, the quality presets, the color tags and the exit codes are fixed by `research.md` D1, D5, D8 and `contracts/cli.md`.

---

## Phase 1: Setup

**Purpose**: Directories and shared test support

- [X] T001 Create the directories `Sources/BlackHoleKit/Movie/` and `Tests/BlackHoleKitTests/Movie/` (a `.gitkeep` in each until files exist); confirm `swift build` still succeeds
- [X] T002 [P] Write `Tests/BlackHoleKitTests/Movie/MovieTestSupport.swift`: a temporary-directory helper that cleans up; a generator of synthetic frame sets (flat distinct colors for order checks, a gradient, and small real renders of the default scene at 160×90) written with `PNGWriter`; a PSNR function between two RGB8 buffers; `ffmpegAvailable` (an executable ffmpeg with libx264 found) used by `.enabled(if:)`; a helper that runs `ffprobe`-free checks only (the tests read movies back through `MovieReader`, not external tools)

**Checkpoint**: Support code compiles; no behavior yet.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Frame discovery, the encoder interface and its selection, and the movie reader. Every user story uses these.

**⚠️ CRITICAL**: Tests T003–T005 are written first and must fail before their implementations.

- [X] T003 [P] Write `Tests/BlackHoleKitTests/Movie/FrameSequenceTests.swift`: files `frame_1…frame_12` sort numerically (`frame_2` before `frame_10`); zero-padded and unpadded names; the prefix is detected from the first match and `--prefix` overrides it; two different prefixes in one folder is an error naming both; a missing folder and an empty folder give messages naming the folder and the expected pattern; a gap (1–10 and 12–20) is an error naming frame 11 unless `allowGaps` (then the frames play in order); a frame of a different size is an error naming the first such file; odd width or height is an error suggesting an even size; non-PNG files and unrelated names are ignored; sizes are read from the PNG header without decoding the pixels
- [X] T004 [P] Write `Tests/BlackHoleKitTests/Movie/MovieReaderTests.swift`: `MovieReader` returns frame count, picture size, duration and frame rate of a movie, and decodes frame k to RGB8; use a small movie produced by whichever encoder is available in the test (flat colors, one per frame) and require each decoded frame to be within 8 levels per channel of its color, which proves the order; the reader is independent of how the file was made
- [X] T005 [P] Write `Tests/BlackHoleKitTests/Movie/EncoderSelectionTests.swift`: `auto` picks ffmpeg when a usable executable is on the injected search path and AVFoundation otherwise; `ffmpeg` with no usable executable throws `MovieError.encoderUnavailable` naming the searched locations (never falls back); `avfoundation` is always selected as asked; the quality presets map to CRF 16 / 18 / 23 and to 0.35 / 0.25 / 0.12 bit per pixel per frame; an executable that is not ffmpeg, or has no libx264, is rejected with a clear message; `--ffmpeg <path>` overrides the search
- [X] T006 Implement `Sources/BlackHoleKit/Movie/FrameSequence.swift` per research D2 and data-model `FrameSequence` (discovery, numeric sort, prefix, gaps, size check from the PNG header via ImageIO, even-size check) with `MovieError` cases carrying the messages of the edge cases in spec.md
- [X] T007 Implement `Sources/BlackHoleKit/Movie/MovieEncoder.swift`: the `MovieEncoder` protocol (`begin(width:height:fps:quality:)`, `append(frame:)` from a PNG URL, `finish()`, `cancel()`, plus an `EncoderInfo` with name, version, setting and `reproducibleFile`); `MovieQuality` (`high`, `standard`, `small`) with the mappings of D1; `EncoderChoice` (`auto`, `ffmpeg`, `avfoundation`) and the selection function with an injectable search path list (`PATH`, `/opt/homebrew/bin`, `/usr/local/bin`); `MovieError` (invalid frames, output exists, encoder unavailable, encoding failed, cannot write)
- [X] T008 Implement `Sources/BlackHoleKit/Movie/MovieReader.swift`: read back a movie with `AVAssetReader`/`AVAssetImageGenerator` (frame count, size, duration, nominal fps, color properties of the track, decode of frame k to RGB8 in sRGB); used by tests and by `assemble` as an optional self-check
- [X] T009 Run T003–T005 until they pass

**Checkpoint**: Frames can be discovered and validated, encoders can be selected, movies can be read back. No encoder is implemented yet.

---

## Phase 3: User Story 1 - Turn a folder of rendered frames into a movie (Priority: P1) 🎯 MVP

**Goal**: `bhsim movie assemble` makes an MP4 from a folder of numbered PNGs, with either encoder, with the correct order, size, duration and colors.

**Independent Test**: Render a short numbered sequence by hand, run `bhsim movie assemble`, read the result back: frame count, duration, size, order, colors.

### Tests for User Story 1 (write first, confirm failing)

- [X] T010 [P] [US1] Write `Tests/BlackHoleKitTests/Movie/FFmpegEncoderTests.swift` (skipped without ffmpeg): 24 flat-color frames give a movie with 24 frames at 24 fps, 1.0 s, the right size, frames in order (`MovieReader`); on real small renders each decoded frame has PSNR ≥ 35 dB against its source PNG using Apple's decoder; the track carries BT.709 primaries and matrix and the sRGB transfer function; a movie deliberately tagged BT.709 transfer is shown to differ in decoded color, so the color test can detect a tagging error; two runs give byte-identical files and `EncoderInfo.reproducibleFile == true`; odd dimensions are rejected before ffmpeg starts; an ffmpeg that fails mid-way (for example killed) gives `encodingFailed` with its error text and leaves no file; the memory used does not grow with the frame count (frames are streamed)
- [X] T011 [P] [US1] Write `Tests/BlackHoleKitTests/Movie/AVFoundationEncoderTests.swift`: the same checks as T010 except byte identity, which is replaced by identical decoded frames across two runs and `reproducibleFile == false`; the PSNR floor of 35 dB is measured with Apple's decoder, and with ffmpeg's decoder when ffmpeg is available; this test is expected to expose risk R4 (research.md Additional checks: about 36.2 dB before the color-attachment fix)
- [X] T012 [P] [US1] Write `Tests/BlackHoleKitTests/Movie/MovieAssemblerTests.swift`: `MovieAssembler.assemble` writes to a temporary name in the output folder and renames at the end (a failure leaves nothing at the final path); an existing output is refused with `outputExists` unless `force`; the result reports path, frame count, duration, size, fps and encoder; progress is reported from 0 to 1 once per frame; frames out of numerical order on disk (created in reverse order) still play in numerical order; a cancelation removes the temporary file
- [X] T013 [P] [US1] Write `Tests/BlackHoleKitTests/Movie/MovieCommandTests.swift` using `CLIRunner`: `bhsim movie assemble` on a generated folder exits 0 and prints the path, frame count, duration, picture size, frame rate and encoder; a missing or empty folder, a gap, differing sizes, odd size and an existing output each exit 2 with the message naming the problem; `--encoder ffmpeg --ffmpeg /nonexistent` exits 6 with no fallback and no movie; `--encoder avfoundation` works regardless of ffmpeg; `--fps 0` and `--fps 241` exit 2; an unknown option exits 2; frames are untouched by the command (hash before and after)

### Implementation for User Story 1

- [X] T014 [US1] Implement `Sources/BlackHoleKit/Movie/FFmpegEncoder.swift` per research D1: locate and validate the executable (version string from `ffmpeg -version`, `libx264` present in `-encoders`), start `ffmpeg -f image2pipe -framerate <fps> -c:v png -i - -vf scale=in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p -c:v libx264 -crf <q> -colorspace bt709 -color_primaries bt709 -color_trc iec61966-2-1 -color_range tv -fflags +bitexact -flags:v +bitexact -movflags +faststart <tmp>`, stream each PNG file to its standard input one at a time, capture standard error for the failure message, terminate the process on `cancel`, and report `EncoderInfo` (name `ffmpeg`, version, `crf=N`, `reproducibleFile: true`)
- [X] T015 [US1] Implement `Sources/BlackHoleKit/Movie/AVFoundationEncoder.swift` per research D1 and the spike: `AVAssetWriter` (H.264, MP4) with `AVVideoColorPropertiesKey` (BT.709 primaries and matrix, sRGB transfer), BGRA `CVPixelBuffer` per frame drawn from the ImageIO-decoded PNG in an sRGB `CGContext`, **and color attachments (primaries, transfer function, YCbCr matrix) set on every pixel buffer** so the conversion to YUV uses the right color space (risk R4), average bit rate from the bits-per-pixel preset; wait for `isReadyForMoreMediaData`; report `EncoderInfo` (name `avfoundation`, macOS version, `bitsPerPixel=N`, `reproducibleFile: false`); after the fix, re-measure and record the PSNR with Apple's decoder
- [X] T016 [US1] Implement `Sources/BlackHoleKit/Movie/MovieRecord.swift`: the `Codable` record of `contracts/movie-record.schema.json` and data-model `MovieRecord` for `source: assembled` (movie fields, encoder info, backend taken from the frame JSONs if they exist, otherwise omitted fields), `jsonData()` with sorted keys; the animation fields are added in T035
- [X] T017 [US1] Implement `Sources/BlackHoleKit/Movie/MovieAssembler.swift`: validate the sequence, select the encoder, encode to a temporary file in the output directory, rename atomically, refuse to overwrite without `force`, write the record next to the movie (`<file>.json`), report progress and the summary, support cancelation (removes the temporary file)
- [X] T018 [US1] Implement the `assemble` subcommand in `Sources/bhsim/MovieCommand.swift` (group `movie`, options of `contracts/cli.md`) and register `Movie` in `Sources/bhsim/Bhsim.swift`; map errors to exit codes 2 (invalid input, output exists), 3 (cannot write) and 6 (encoder unavailable or failed); print the summary of FR-003
- [X] T019 [US1] Run T010–T013 until they pass; measure SC-001 (120 frames of 1920×1080 assembled in under 30 s) with each encoder and the file sizes; confirm the AVFoundation PSNR after the T015 fix (≥ 35 dB with Apple's decoder, and note the margin); run quickstart steps 1 and 2 and record all results in `research.md` §Results

**Checkpoint**: User Story 1 works on its own: any numbered PNG folder becomes a playable, correctly ordered, correctly colored movie. This is the MVP.

---

## Phase 4: User Story 2 - Render an animation and make the movie in one step (Priority: P2)

**Goal**: `bhsim movie animate` renders a linear sweep of inclination, distance or spin on the chosen backend, writes frames as it goes, resumes after interruption, and assembles the movie with one common exposure reference.

**Independent Test**: Request a small inclination sweep; check the frames, the movie, that the first and last frames equal single renders, that an invalid sweep is rejected before any rendering, and that an interrupted run resumes.

### Tests for User Story 2 (write first, confirm failing)

- [X] T020 [P] [US2] Write `Tests/BlackHoleKitTests/Movie/AnimationTests.swift`: the value of frame i is `from + (to − from)·i/(N − 1)`, with the first and last exactly the end values and N = 1 giving `from`; N = round(duration × fps) with N ≥ 1 (a duration shorter than one frame gives 1); the other settings are identical in every frame; the common reference is the largest per-frame `NovikovThorne.referenceLuminance` over the sweep, equal to a single render's reference for inclination and distance sweeps and different per frame for a spin sweep; validation runs `RenderConfig.validate()` for every frame before any rendering and reports the first invalid frame by number and value (distance sweep ending inside the ergosphere, inclination ending at 0° or 180°, spin ≥ 1), with the same message as a single render, in under 2 s even for 1,000 frames
- [X] T021 [P] [US2] Write `Tests/BlackHoleKitTests/Render/ReferenceOverrideTests.swift`: `RenderConfig.referenceRadianceOverride == nil` leaves the HDR image bit-identical to before (the existing `CPUUnchangedTests` hashes stay valid); an override R multiplies the normalized HDR by exactly `referenceRadiance / R`; the override is recorded in the metadata and EXR attribute; a non-positive or non-finite override fails `validate()` with a message naming `--reference-radiance`
- [X] T022 [P] [US2] Write `Tests/BlackHoleKitTests/Movie/AnimationRunnerTests.swift`: a small CPU animation (8 frames, 64×36, 4 samples per pixel) writes `frame_0001.png` … and a JSON per frame, no EXR unless `keepEXR`; the first and last frame PNGs are byte-identical to single renders with the start and end values and the movie's reference; frames are rendered strictly in order and none is held in memory after writing; resume: stopping after k frames (injected stop) and rerunning renders exactly the missing frames, and the final frames are byte-identical to an uninterrupted run; a frame with a PNG but no JSON (killed mid-write) is re-rendered; a frame whose JSON records different inputs (changed option, backend or reference) is re-rendered; a PNG of the wrong size is re-rendered; progress is reported as `frame k/N`; the disk estimate is reported before rendering and equals frames × width × height × 3 bytes (plus EXR if kept)
- [X] T023 [P] [US2] Write `Tests/BlackHoleKitTests/Movie/GPUAnimationTests.swift` (skipped without a GPU): a 4-frame animation on the Metal backend renders and assembles; each GPU frame agrees with the CPU frame of the same settings within the tolerances of `BackendAgreement.comparePixels` (radiance 99th percentile < 1 %); the metadata of each frame says `metal`/`float32`; the compiled kernel is created once for the whole animation (a counter on the context cache)
- [X] T024 [P] [US2] Write `Tests/BlackHoleKitTests/Movie/MovieInterruptTests.swift`: run the built `bhsim movie animate` as a child process, send SIGINT after the first frame appears, and require that the process ends, no movie and no temporary file remain at or beside the final path, the finished frames and their JSON are intact, no ffmpeg child process is left running, and a rerun completes the movie
- [X] T025 [P] [US2] Extend `Tests/BlackHoleKitTests/Movie/MovieCommandTests.swift` for `animate`: a small sweep exits 0 and prints `frame k/N`, the disk estimate and the summary; the default `--samples` is 9 (read from the record) and `--samples 4` overrides it; an invalid sweep exits 2 in under 2 s with the frame number, value and valid range and writes no frames and no movie; `--backend metal` with `BHSIM_FORCE_NO_GPU=1` exits 5 and writes nothing; a movie-wide bad-ray fraction above 0.1 % exits 4 with the movie still written (use a tiny `--max-steps`); no usable encoder exits 6 with the frames kept; an existing output without `--force` exits 2 before rendering; `--duration`, `--from` and `--to` are required; unparsable values and unknown options exit 2

### Implementation for User Story 2

- [X] T026 [US2] Add `referenceRadianceOverride: Double?` to `Sources/BlackHoleKit/Render/RenderConfig.swift` (validated: positive and finite), use it in `Sources/BlackHoleKit/Render/Renderer.swift` in place of the computed reference when set, record it in `Sources/BlackHoleKit/Output/Metadata.swift` and the render metadata schema (`specs/001-black-hole-image/contracts/render-metadata.schema.json`, optional field), and add `--reference-radiance <value>` to `Sources/bhsim/RenderCommand.swift`; the CPU path with the override unset must stay byte-identical (run `CPUUnchangedTests`)
- [X] T027 [US2] In `Sources/BlackHoleKit/Metal/MetalContext.swift` add a process-wide cache of the device, queue and compiled pipelines (research D9) used by `Renderer` for the Metal backend, with a creation counter for T023 and the existing `forceUnavailable` path unchanged
- [X] T028 [US2] In `Sources/BlackHoleKit/Output/RenderOutput.swift` let the caller choose which of PNG, EXR and JSON are written, and write each file to a temporary name and rename it (the JSON last, as the completion marker); the single-render behavior and file contents are unchanged
- [X] T029 [US2] Implement `Sources/BlackHoleKit/Movie/Animation.swift` per research D3, D5 and data-model (`SweepParameter`, `Animation`, `frameConfig(i)`, the common reference, up-front validation reporting the first invalid frame)
- [X] T030 [US2] Implement `Sources/BlackHoleKit/Movie/AnimationRunner.swift` per research D4: render frames in order on the chosen backend, skip complete frames (JSON present, matching inputs, PNG of the right size), write PNG and JSON per frame via T028, release each frame's memory, aggregate diagnostics over the movie, report progress and the disk estimate, support cancelation between and within frames, keep finished frames on any failure
- [X] T031 [US2] In `Sources/bhsim/RenderCommand.swift` move the render options into a shared `RenderOptions` group (behavior and help text unchanged), then implement `bhsim movie animate` in `Sources/bhsim/MovieCommand.swift`: the options of `contracts/cli.md`, `--samples` defaulting to 9, `--out` giving the movie file and the `_frames` folder, validation first (exit 2), backend errors exit 5, movie-wide bad-ray policy exit 4, encoder errors exit 6, assembly through `MovieAssembler`, SIGINT handling that cancels the runner and encoder; run `CPUUnchangedTests` and `EdgeCaseTests` to confirm `render` is unchanged
- [X] T032 [US2] Run T020–T025 until they pass; measure SC-002 (120 frames, 1280×720, 4 samples per pixel, GPU, under 5 minutes) and the same at the 9-sample default, SC-004, SC-006 and SC-007; run quickstart steps 3 to 6 (including a spin sweep with one reference and no brightness steps); record all results, frame rates and peak memory in `research.md` §Results

**Checkpoint**: User Stories 1 and 2 work: a sweep becomes a movie in one command, resumable, with consistent brightness.

---

## Phase 5: User Story 3 - Check what a movie contains and reproduce it (Priority: P3)

**Goal**: Every movie has a complete record, and the same command gives the same frames (and, with ffmpeg, the same file).

**Independent Test**: Make a movie, read its record, rerun, and compare frames and file.

### Tests for User Story 3 (write first, confirm failing)

- [X] T033 [P] [US3] Write `Tests/BlackHoleKitTests/Movie/MovieRecordTests.swift`: the record of an animation holds every field of data-model `MovieRecord` (frame rate, count, size, swept parameter with start and end, common settings without the swept parameter, backend and precision, seed, reference radiance, encoder with version and setting, summed diagnostics, per-frame list) and that of an assembled movie holds its subset; all required keys of `contracts/movie-record.schema.json` are present with the right types and enums; the record can be decoded again; the summed diagnostics equal the sum of the per-frame JSONs
- [X] T034 [P] [US3] Write `Tests/BlackHoleKitTests/Movie/MovieDeterminismTests.swift`: the same small animation run twice from scratch gives byte-identical PNG frames; with ffmpeg the two `.mp4` files are byte-identical; with AVFoundation the two movies are equivalent (same frame count, each frame within the 35 dB floor of the same source; the hardware encoder is not deterministic, research.md T019 findings) and the record says `reproducibleFile: false`; the two records are equal except `wallTimeSeconds`; a run split by an interruption and resumed equals an uninterrupted run in frames and record (except wall time)

### Implementation for User Story 3

- [X] T035 [US3] Complete `Sources/BlackHoleKit/Movie/MovieRecord.swift` and the callers in `AnimationRunner` and `MovieAssembler`: animation block, common settings (from `RenderMetadata`, swept parameter excluded), per-frame list with swept value and bad-ray fraction, summed `Diagnostics`, reference radiance, seed, backend, encoder (including `reproducibleFile`), written atomically next to the movie as `<file>.json`
- [X] T036 [US3] Add `tools/reference/check_movie_record.py` that validates a movie record against `contracts/movie-record.schema.json` with the `jsonschema` package (added to `pyproject.toml` and `uv.lock`), run on a record produced by a real animation
- [X] T037 [US3] Run T033–T034 until they pass; run the schema check; run the determinism steps of quickstart step 1 and record the results in `research.md` §Results

**Checkpoint**: All three stories work; movies are documented and reproducible.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T038 [P] Update `docs/physics.md`: the physical scope of an animation (stationary, axisymmetric hole and disk seen by a sequence of static observers; no gas motion, no observer-velocity aberration, no synthesized frames; FR-015), the common exposure reference, and the video approximations (lossy H.264, 4:2:0 chroma blurs single-pixel stars, sRGB/BT.709 tagging) with their measured error; add the rows to the approximations table
- [X] T039 [P] Update `docs/how-it-works.md`: a section on movies (what `assemble` and `animate` do, why the frames are complete renders, the fixed sample pattern and why `animate` defaults to 9 samples per pixel, ffmpeg versus the built-in encoder and what each guarantees) and the new rows in the evidence table; add to "where to be skeptical" the speckle of the photon ring at low sample counts
- [X] T040 [P] Update `docs/tolerances.md`: the 35 dB fidelity floor with its justification from the measurements (research D7 and T019), the ordering tolerance of 8 levels on flat colors, and the performance targets
- [X] T041 [P] Update `README.md`: the `movie` commands, ffmpeg as optional (and how to install it), the AVFoundation fallback, `--samples 9` for movies, exit code 6
- [X] T042 [P] Merge the changes of `contracts/cli.md` into `specs/001-black-hole-image/contracts/cli.md` (movie commands, `--reference-radiance`, exit code 6) so the main contract is current
- [X] T043 Run the whole of `quickstart.md` end to end on a clean copy of the repository and fix any discrepancy between the document and the actual behavior
- [X] T044 Run the full test suite (`swift test`), `bhsim validate` and `bhsim compare`; confirm the CPU renders are unchanged (`CPUUnchangedTests`), there are no build warnings, and record the final results in `research.md` §Results
- [X] T045 Inspect a star-field crop and a photon-ring crop of an assembled movie against its source frames by eye with each encoder (risk R3) and record the observation; confirm every success criterion SC-001 to SC-008 is met or that any miss is written up with its cause; set the status of `spec.md` and add the outcome to `checklists/requirements.md` §Notes

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → Phase 3 (US1) → Phase 4 (US2) → Phase 5 (US3) → Phase 6.
- US2 needs the encoders and the assembler of US1. US3 needs the record of US1 and the runner of US2. US1 alone is a complete, shippable MVP.
- Inside Phase 2: T003–T005 → T006–T008 → T009.
- Inside Phase 3: T010–T013 → T014, T015 (independent of each other) → T016 → T017 → T018 → T019.
- Inside Phase 4: T020–T025 → T026, T027, T028 (independent) → T029 → T030 → T031 → T032. T026 and T028 touch files used by single renders, so run `CPUUnchangedTests` after each.
- T036 can start as soon as T016 exists but is run after T035.

### Parallel opportunities

- Phase 1: T002 alongside T001.
- Phase 2 tests: T003, T004, T005 together.
- Phase 3 tests: T010, T011, T012, T013 together; encoders T014 and T015 together.
- Phase 4 tests: T020–T025 together; T026, T027, T028 together.
- Phase 5 tests: T033 and T034 together.
- Polish: T038–T042 together.

## Implementation Strategy

1. **MVP first**: Phases 1–3. Stop and demonstrate `bhsim movie assemble` on a real folder before starting US2.
2. **Measure as you go**: T019, T032 and T037 record measurements in `research.md`; do not defer them to the end.
3. **Risks to retire early**: R4 (AVFoundation color) in T011/T015/T019; byte identity of ffmpeg output in T010; the cost of 9 samples per pixel in T032.
4. **Guard the existing behavior**: after T026, T028 and T031 run `CPUUnchangedTests`, `EdgeCaseTests` and the GPU suites; single renders must not change.
