# Feature Specification: Movies from Individual Frames

**Feature Branch**: `003-movie-from-frames`

**Created**: 2026-10-10

**Status**: Draft

**Input**: User description: "Add the ability to generate a movie from individual frames"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Turn a folder of rendered frames into a movie (Priority: P1)

A user has a numbered sequence of rendered images (for example the display images written by the renderer) and asks for a movie. They get a single video file that plays the frames in order at the requested frame rate and resolution, which they can open in any ordinary video player.

**Why this priority**: This is the capability the user asked for. It is useful on its own, for frames from this project's renderer, from an earlier run, or from any other source, and everything else builds on it.

**Independent Test**: Render a short numbered sequence of frames by hand (varying one setting between renders), run the movie command on the folder, open the result in a video player, and check that it has the right number of frames, duration and picture size.

**Acceptance Scenarios**:

1. **Given** a folder of 48 numbered display images of equal size and a frame rate of 24, **When** the user asks for a movie, **Then** a video file of 2 seconds containing all 48 frames in numerical order is written, and the command reports its path, frame count, duration and size.
2. **Given** the same folder, **When** the user chooses a different frame rate, **Then** the movie has the same frames and a duration that follows from the new rate.
3. **Given** frames whose numbers are not zero-padded to the same width (for example `frame_2`, `frame_10`), **When** the movie is made, **Then** they play in numerical order, not alphabetical order.

---

### User Story 2 - Render an animation and make the movie in one step (Priority: P2)

A user asks for a movie in which one viewing parameter changes smoothly from a start value to an end value over a chosen duration, for example the observer's inclination sweeping from edge-on to face-on, or the observer's distance closing in. The tool renders every frame with the full physical renderer on the chosen backend, writes the frames, and assembles the movie.

**Why this priority**: This is how a movie of a black hole is normally made, and it avoids scripting hundreds of separate renders. It depends on User Story 1 for the assembly.

**Independent Test**: Request a 2-second, 24-frame inclination sweep at small size. Check that 48 frames and a movie appear, that the first and last frames are identical to single renders at the start and end values, and that every frame is a complete render, not an interpolation of its neighbours.

**Acceptance Scenarios**:

1. **Given** a sweep of inclination from 85° to 20° over 3 seconds at 24 frames per second, **When** the user runs it, **Then** 72 frames are rendered, each exactly equal to a single render with that frame's inclination, and a movie of 3 seconds is written.
2. **Given** a sweep whose end value is invalid for the physics (for example an observer distance inside the ergosphere), **When** the user runs it, **Then** the run stops before rendering anything and names the parameter, the offending frame and the valid range.
3. **Given** a run that is interrupted part-way, **When** the user runs the same command again, **Then** the frames already rendered are kept and only the missing frames are rendered, and the final movie is the same as an uninterrupted run would give.
4. **Given** the same sweep requested with the CPU backend and with the GPU backend, **When** both are run, **Then** both produce a movie, and the GPU frames meet the same agreement tolerances with the CPU frames as single images do.

---

### User Story 3 - Check what a movie contains and reproduce it (Priority: P3)

A user can see afterwards exactly how a movie was made: which frames and settings, which backend and precision, and the frame rate. Running the same command again gives the same frames.

**Why this priority**: The project requires results to be reproducible and inputs to be recorded. It is lower priority because the movie is useful without it.

**Independent Test**: Make a movie, read its record, rerun the command with the recorded settings, and compare the frames.

**Acceptance Scenarios**:

1. **Given** a finished movie, **When** its record is read, **Then** it lists the frame rate, frame count, picture size, the swept parameter with its start and end values (if any), the common settings of all frames, the backend and precision, and the seed.
2. **Given** the same command run twice on the same machine, **When** the frames are compared, **Then** they are identical image for image.

---

### Edge Cases

- No frames match, or the folder does not exist: stop with a message naming the folder and the expected file-name pattern; no movie is written.
- A gap in the numbering (for example frames 1–10 and 12–20): stop and name the missing frame, unless the user explicitly allows gaps.
- Frames of differing sizes: stop and name the first frame that differs.
- A picture size that the video format cannot hold (for example an odd number of pixels): report it clearly, or crop by one pixel with a notice, never fail silently.
- The output file already exists: do not overwrite it unless the user explicitly asks to.
- No video encoder is available on the machine, or the movie cannot be written: stop with a clear message and a non-zero exit status, and leave the frames in place so no work is lost.
- Very long or very large movies: frames are written to disk as they are made and never all held in memory; disk space needed is reported before rendering starts.
- A single frame in a sweep is unresolved or out of tolerance: counted and reported for that frame and for the movie as a whole, with the same rules as a single image; the movie is still written.
- A sweep that changes the black hole's spin changes the brightness reference of each frame; the tool applies one common exposure reference to the whole movie so brightness does not jump between frames, and says which one it used.
- A sweep of zero length (start equals end) or of one frame: allowed; it gives a still movie or a single-frame movie.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST create a single video file from a numbered sequence of image files, playing the frames in numerical order at a user-chosen frame rate.
- **FR-002**: The system MUST accept the display images (8-bit PNG) written by the existing renderer as frames, and MUST keep them unmodified apart from the conversion to the video's colour encoding.
- **FR-003**: The system MUST report the path, frame count, duration, picture size and frame rate of every movie it writes.
- **FR-004**: The system MUST validate the frame sequence before encoding (existence, numbering, equal sizes) and MUST reject an invalid sequence with a message naming the problem and the first offending frame.
- **FR-005**: The system MUST NOT overwrite an existing movie file unless the user explicitly asks for it.
- **FR-006**: The system MUST let the user request an animation in which one viewing parameter (at least the observer's inclination, the observer's distance and the black hole's spin) changes linearly from a start value to an end value over a chosen number of frames or duration.
- **FR-007**: Every animation frame MUST be a complete render by the existing renderer, on the backend the user selects, with every other option of a single render available and held constant across frames. The system MUST NOT synthesise in-between frames, motion blur or other effects that have no physical basis.
- **FR-008**: The system MUST validate every frame's settings against the same rules as a single render before any frame is rendered, and MUST stop with the same messages and exit code as a single render if any frame is invalid, naming the frame.
- **FR-009**: The system MUST write animation frames to disk as they are rendered, MUST skip frames already present from an earlier identical run so that an interrupted run can be resumed, and MUST bound its memory use independently of the number of frames.
- **FR-010**: The system MUST report progress (frame number out of total) during an animation and during encoding.
- **FR-011**: Rendering the same animation twice on the same machine MUST give identical frames. Per-frame diagnostics (ray counts, residual statistics, unresolved count) MUST be reported for each frame and summarised for the whole movie, with the exit-code policy of a single render applied to the movie as a whole.
- **FR-012**: The system MUST write a record next to each movie listing the frame rate, frame count, picture size, the swept parameter and range, the settings common to all frames, the backend and precision, the seed, and the exposure reference used.
- **FR-013**: In an animation, one exposure reference MUST be used for all frames, so that frame-to-frame brightness changes reflect the physics and not a changing normalisation.
- **FR-014**: When the video encoder is unavailable or the movie cannot be written, the system MUST fail with a clear message and non-zero exit status and MUST keep the rendered frames.
- **FR-015**: The scope of the physics of an animation MUST be documented: each frame shows a stationary, axisymmetric black hole and disk seen by a static observer, so a sequence of frames describes a changing viewpoint or changing parameter, not time evolution of the hole, motion of the disk gas, or the relativistic aberration of a moving observer.

### Key Entities

- **Frame sequence**: An ordered set of numbered images of equal size that forms the movie. Has a first number, a count, and a picture size.
- **Animation**: A request to render a frame sequence by varying one parameter linearly between a start and an end value, with fixed common settings, a frame rate and a duration (or frame count).
- **Movie**: The video file produced from a frame sequence, with its frame rate, duration and picture size.
- **Movie record**: The description of how a movie was made (inputs, settings, backend, precision, seed, exposure reference, diagnostics), stored next to it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can turn an existing folder of 120 frames of 1920×1080 into a movie with one command, and the movie is written in under 30 seconds on the reference machine (an Apple M4).
- **SC-002**: A 5-second, 24 frames-per-second, 1280×720 animation (120 frames, 4 samples per pixel) can be rendered and assembled with the GPU backend in under 5 minutes on the reference machine.
- **SC-003**: The movie contains exactly the requested number of frames, at the requested frame rate and picture size, in the correct order, in 100 % of test cases, checked by reading the movie back.
- **SC-004**: The first and last frames of an animation are pixel-identical to single renders with the start and end parameter values.
- **SC-005**: Running the same animation twice on the same machine gives identical frames in 100 % of frames.
- **SC-006**: After an interruption at any frame, rerunning the command renders only the missing frames, and the resulting frame set is identical to an uninterrupted run.
- **SC-007**: An invalid animation (invalid parameter value in any frame) is rejected in under 2 seconds without rendering any frame.
- **SC-008**: The resulting movie plays in the default video player of the Mac and in at least one other common player without conversion.

## Assumptions

- The movie is a standard, widely playable video file; the default container and codec are chosen in planning for compatibility with ordinary players. High-dynamic-range or lossless video is out of scope for this first version.
- The video is built from the display (tone-mapped, 8-bit) images. Building video from the 32-bit physical-radiance images, with a single tone curve applied across the whole movie, is out of scope for this feature.
- A video-encoding capability must be present on the Mac. Which one is used is a planning decision; the tool reports clearly if none is found.
- The renderer and its backends, including the GPU backend, already exist and are used unchanged to render each frame; this feature adds sequencing, assembly and recording, not new physics.
- Only linear sweeps of one parameter are in scope. Multiple parameters at once, easing curves, camera paths defined by keyframes, and audio are out of scope for this version.
- The reference machine is an Apple M4; other platforms are out of scope.
- Sound, subtitles, titles and overlays (such as a parameter read-out on each frame) are out of scope.
