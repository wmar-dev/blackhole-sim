# Implementation Plan: Movies from Individual Frames

**Branch**: `003-movie-from-frames` | **Date**: 2026-10-10 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-movie-from-frames/spec.md`

## Summary

Add two commands under `bhsim movie`: `assemble` turns a numbered folder of display PNGs into an MP4 (User Story 1), and `animate` renders a frame sequence by sweeping one viewing parameter, with the existing renderer on the chosen backend, then assembles it (User Story 2). Each movie gets a JSON record of how it was made (User Story 3).

No physics changes. Each frame is a normal render; the new code sequences renders, keeps one common brightness reference across the movie, writes frames to disk as it goes (bounded memory, resumable), and encodes through a small encoder interface with two implementations. **ffmpeg** (libx264), when installed, is preferred: a spike (research D1) showed it gives byte-identical files on repeated runs and files about 2.7× smaller than AVFoundation at equal quality. **AVFoundation**, part of macOS, is the fallback, so the feature works with nothing installed. The movie record states which encoder, and which version, made the file.

## Technical Context

**Language/Version**: Swift 6.4 (existing package)

**Primary Dependencies**: Apple system frameworks AVFoundation, CoreVideo, CoreMedia and ImageIO (already part of macOS) for the fallback encoder and for reading PNGs. The external program `ffmpeg` (with libx264) is used when found (`PATH`, `/opt/homebrew/bin`, `/usr/local/bin`) but is optional. No new package dependencies.

**Storage**: Files: frame PNGs and per-frame JSON in a frames folder, one MP4, one JSON record

**Testing**: Swift Testing. Movies are read back with AVAssetReader (independent of the encoder that wrote them) to check frame count, order, size, duration and colour. Each encoder has its own tests; those for an encoder that is not present are skipped, not failed. Animation tests use small images.

**Target Platform**: macOS 14+ on Apple silicon (reference machine: Apple M4)

**Project Type**: Library plus command-line tool (extends the existing package)

**Performance Goals**: Assemble 120 frames of 1920×1080 in under 30 s with either encoder (measured spike rates are far higher); a 120-frame 1280×720 animation at 4 samples per pixel on the GPU backend in under 5 minutes (estimate: 1.2 s per frame from the 1080p GPU timing of 2.75 s, so about 2.5 minutes); invalid sweep rejected in under 2 s.

**Constraints**: Memory independent of the number of frames; frames written to disk as rendered; identical frames on repeated runs (and, with ffmpeg, an identical movie file); resumable; CPU and GPU renders of single images unchanged (byte-identical CPU output).

**Scale/Scope**: Up to a few thousand frames per movie; frame sizes up to 3840×2160.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Accurate Physics | No new physics. Each frame is a complete render by the validated renderer; nothing is interpolated, blurred or synthesised (FR-007). The one approximation added, lossy video compression, is documented with its measured error (research D1, D7); the PNG/EXR frames remain the physical record. The physical scope of an animation (a sequence of static-observer views of a stationary hole) is stated in the docs (FR-015). | PASS |
| II. Explicit Units and Conventions | Swept parameters keep their existing units (degrees, M, dimensionless spin) and validity ranges. The video's colour encoding is stated explicitly: sRGB transfer function with BT.709 primaries and matrix, limited range, 4:2:0 (research D1). | PASS |
| III. Validation Against Known Results (Test-First) | Tests are written first: frame order and count read back from the movie, colour fidelity against the source PNGs with a stated PSNR floor, first/last frame equal to single renders, resume equals uninterrupted, determinism. The PSNR floor is justified in research D7, not tuned to pass. | PASS (enforced in tasks) |
| IV. Numerical Rigor and Reproducibility | Frames are deterministic (existing guarantee); the movie record stores every input and the common exposure reference (D5); with ffmpeg the movie file itself is byte-identical across runs (spike), and with the AVFoundation fallback the decoded frames are identical while the container bytes differ (embedded creation time); this is documented, not hidden. | PASS |

**Post-design re-check (after Phase 1)**: PASS. Carried as risks, not violations: the fallback hardware encoder's output may differ between Mac models (R1), and a spin sweep changes the brightness reference (handled by D5).

## Project Structure

### Documentation (this feature)

```text
specs/003-movie-from-frames/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── cli.md                    # `bhsim movie assemble|animate`, `--reference-radiance`, exit codes
│   └── movie-record.schema.json  # the JSON record written next to each movie
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks, not created here)
```

### Source Code (repository root)

```text
Sources/BlackHoleKit/
├── Movie/                           # NEW
│   ├── FrameSequence.swift          # find, number-sort and validate frames (gaps, sizes, odd dimensions)
│   ├── MovieEncoder.swift           # encoder interface, quality presets, encoder selection (auto/ffmpeg/avfoundation)
│   ├── FFmpegEncoder.swift          # finds ffmpeg, pipes frames to libx264, bit-exact flags, colour tags, version capture
│   ├── AVFoundationEncoder.swift    # fallback: AVAssetWriter H.264/MP4, colour tags
│   ├── MovieReader.swift            # AVAssetReader read-back (tests and `assemble` self-check)
│   ├── Animation.swift              # sweep definition, per-frame RenderConfig, up-front validation, common reference
│   ├── AnimationRunner.swift        # render frames in order, resume, progress, per-frame diagnostics, atomic writes
│   └── MovieRecord.swift            # the JSON record (Codable)
├── Render/
│   ├── RenderConfig.swift           # edited: optional `referenceRadianceOverride` (nil = unchanged behaviour)
│   └── Renderer.swift               # edited: use the override when set; share one MetalContext across frames
├── Metal/MetalContext.swift         # edited: process-wide cache so frames do not recompile the kernel
└── Output/RenderOutput.swift        # edited: choose which of PNG/EXR/JSON to write (animation: PNG + JSON)

Sources/bhsim/
├── Bhsim.swift                      # edited: register `movie`
├── RenderCommand.swift              # edited: shared option group (`RenderOptions`) reused by `animate`; behaviour unchanged
└── MovieCommand.swift               # NEW: `bhsim movie assemble` and `bhsim movie animate`

Tests/BlackHoleKitTests/Movie/       # NEW: FrameSequenceTests, FFmpegEncoderTests, AVFoundationEncoderTests,
                                     #      AnimationTests, AnimationRunnerTests, MovieCommandTests

docs/                                # physics.md (scope of an animation, video approximations), how-it-works.md, tolerances.md
README.md                            # movie commands
```

**Structure Decision**: Extend the existing library-plus-CLI package. The movie code lives in its own `Movie/` folder of `BlackHoleKit` so it is testable without the CLI; the CLI adds one command group. The render path is touched only to add an optional reference-radiance override (default behaviour unchanged, guarded by the existing byte-identity test) and to reuse the GPU context between frames.

## Complexity Tracking

No constitution violations. Nothing to justify.
