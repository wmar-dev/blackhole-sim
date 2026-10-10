# Feature Specification: GPU Acceleration on Apple Silicon

**Feature Branch**: `002-metal-gpu-backend`

**Created**: 2026-10-09

**Status**: Implemented (all targets met; see research.md §Final results)

**Input**: User description: "try acceleration with metal"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Render the same image faster on the Mac's GPU (Priority: P1)

A user selects the GPU backend and renders any scene the existing renderer supports. They get the same three outputs (display image, physical-intensity image, metadata) and the same picture the reference (CPU) backend would give, in a fraction of the time.

**Why this priority**: This is the whole feature. The CPU backend already meets the original 10-minute goal (about 21 s for the default image), so the value is headroom: much larger or many-sample renders become practical. Without parity of results the speed-up is worthless, so speed and agreement are delivered together.

**Independent Test**: Render the default scene with each backend on the same machine. Compare wall time and compare the two images ray by ray and pixel by pixel.

**Acceptance Scenarios**:

1. **Given** the default scene on an Apple-silicon Mac, **When** it is rendered with the GPU backend, **Then** the display image, the physical-intensity image and the metadata are written, and the run takes at most one third of the CPU backend's time.
2. **Given** the same scene rendered by both backends, **When** the results are compared, **Then** at least 99.9 % of rays reach the same outcome (captured, disk, or sky), and the crossing-radius, sky-direction and disk/horizon-pixel radiance criteria of FR-003 hold.
3. **Given** non-spinning and spinning black holes at several inclinations, **When** they are rendered with the GPU backend, **Then** the shadow size and outline meet the same accuracy requirements as the CPU backend (non-spinning shadow radius within 1 % of the analytic value, Kerr outline within 2 %).

---

### User Story 2 - Verify the GPU against the reference (Priority: P2)

A user or developer can check, at any time, how well the GPU backend agrees with the reference. A single check renders a standard set of scenes with both backends and reports the agreement, failing loudly if the GPU deviates beyond the tolerances. Every rendered image also records which backend and numerical precision produced it.

**Why this priority**: The project's principle is that physics results are validated against independent references, not trusted. A GPU path with weaker arithmetic must be held to that standard continuously, not once.

**Independent Test**: Run the agreement check on the development machine and read the report; deliberately degrade the GPU path (or tighten a tolerance) and confirm the check fails.

**Acceptance Scenarios**:

1. **Given** the agreement check is run, **When** it finishes, **Then** it reports, per scene, the fraction of rays with matching outcomes, the largest and typical radiance differences, the shadow-outline error, the residual statistics and the speed-up, with a pass or fail verdict, and exits with success only if every scene passes.
2. **Given** a rendered image, **When** its metadata is read, **Then** it states which backend produced it and the numerical precision that backend used.
3. **Given** the GPU backend exceeds a tolerance on some scene, **When** the agreement check runs, **Then** it fails and names the scene and the quantity.

---

### User Story 3 - Very large and many-sample renders (Priority: P3)

A user renders a 3840×2160 image at 16 samples per pixel, a size that takes several minutes on the CPU, with the GPU backend. It completes reliably, shows progress, and gives the same quality of result.

**Why this priority**: This is where acceleration pays off, but a correct, validated result at ordinary sizes (User Story 1) comes first.

**Independent Test**: Render the large scene with the GPU backend; compare the time with the CPU backend and check the result against the CPU render.

**Acceptance Scenarios**:

1. **Given** a 3840×2160 render at 16 samples per pixel, **When** the GPU backend runs, **Then** it finishes without error, reports progress while running, and takes at most one third of the CPU time.
2. **Given** the same large render run twice on the same machine, **When** the outputs are compared, **Then** they are identical.

---

### Edge Cases

- No usable GPU is available (unsupported machine or device): the run stops immediately with a message naming the problem, exits non-zero, writes no partial output, and the user can rerun with the CPU backend. There is no silent fallback to the CPU.
- Limited numerical precision: Apple GPUs compute in 32-bit floating point at most. Rays that skim the photon ring are the most sensitive and may be classified differently from the CPU. Such disagreements are counted and reported, never hidden, and the CPU result remains the reference.
- Long-running GPU work can be terminated by the operating system's watchdog: the work must be divided so that no single piece runs long enough to be cut off.
- Device memory limits for very large images: the render must be divided into parts so memory use stays bounded, however large the image.
- Rays that need more steps than the budget allows are reported as unresolved exactly as on the CPU, excluded from averaging, counted, and subject to the same exit-code rule.
- Every option the CPU backend accepts (spin, inclination, distance, field of view, disk on or off, sky kind, seed, samples, mass, accretion rate, and so on) works identically on the GPU backend.
- Results are deterministic on one machine; different GPU models may legitimately differ in the last digits, and this is documented.
- If the agreement targets cannot be met, the feature concludes by documenting the measured disagreement and leaving the GPU backend switched off with a clear message, rather than offering unvalidated images.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST offer a GPU backend, selectable by the user, that renders any scene the CPU backend supports and produces the same three outputs (display image, physical-intensity image, metadata).
- **FR-002**: The CPU backend MUST remain the reference and the default; renders that do not select the GPU backend MUST be unchanged: the display image and the physical-intensity image byte for byte, and the metadata except for the added backend record (FR-006).
- **FR-003**: The GPU backend MUST agree with the CPU reference. On the default scene: at least 99.9 % of rays reach the same outcome; for rays that hit the disk on both backends the crossing radius agrees to within 10⁻³ (relative) at the 99th percentile; for rays that reach the sky the assigned direction agrees to within 10⁻⁴ rad for 99.9 % of them; and pixels whose samples all hit the disk or fall into the horizon differ in linear radiance by less than 1 % at the 99th percentile (relative to the larger of the reference value and 10⁻³ of the peak, so that zero-radiance pixels do not divide by zero). Star-field pixels are judged through the sky-direction criterion, because a star's brightness changes steeply with direction and a harmless direction difference of 10⁻⁵ rad would otherwise show up as a large radiance difference. The exact tolerances MUST be recorded in the project's tolerance table and MUST NOT be loosened without a written physical justification.
- **FR-004**: GPU-rendered images MUST satisfy the same accuracy requirements as CPU-rendered images (shadow radius, Kerr shadow outline, light deflection, integration-residual diagnostics).
- **FR-005**: A GPU run MUST report the same diagnostics as a CPU run (ray counts by outcome, residual statistics, unresolved count, wall time) and follow the same exit-code policy for unresolved or out-of-tolerance rays.
- **FR-006**: The metadata of every render MUST record which backend produced it and the numerical precision used.
- **FR-007**: The system MUST provide a backend agreement check that renders a standard set of scenes with both backends, reports the agreement and speed-up, and exits with success only if all scenes are within tolerance.
- **FR-008**: When the GPU backend is requested but unavailable, the system MUST fail with a clear message and non-zero exit status, and MUST NOT silently substitute the CPU backend.
- **FR-009**: The GPU backend MUST bound its memory use and the duration of any single piece of GPU work regardless of image size, and MUST report progress during long renders.
- **FR-010**: Repeated GPU renders of the same inputs on the same machine MUST produce identical output.
- **FR-011**: The numerical precision of the GPU backend, the reasons for it, the mitigations used, and the measured limits MUST be documented alongside the other approximations.
- **FR-012**: If the agreement requirements cannot be met after the mitigation steps listed in the plan, the GPU backend MUST remain disabled with an explanatory message and the measured findings MUST be documented.
- **FR-013**: Input validation, error messages and exit codes for invalid input MUST be the same for both backends.

### Key Entities

- **Backend**: The component that traces rays and produces radiance for an image. The CPU backend is the reference; the GPU backend is the accelerated alternative. Each has a name and a numerical precision recorded in the render metadata.
- **Agreement Report**: The result of comparing the two backends on a scene: fraction of rays with matching outcomes, radiance difference statistics, shadow-outline error, residual statistics, speed-up, and a pass/fail verdict per quantity.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The default scene (1920×1080, 4 samples per pixel) renders at least 3 times faster with the GPU backend than with the CPU backend on the reference machine (an Apple M4; CPU baseline about 21 s).
- **SC-002**: On the default scene, at least 99.9 % of rays reach the same outcome on both backends; the crossing-radius, sky-direction and disk/horizon-pixel radiance criteria of FR-003 hold.
- **SC-003**: With the GPU backend, a non-spinning shadow's radius is within 1 % of the analytic value and the outline of a spin-0.9 shadow viewed at 85° is within 2 % of the analytic outline.
- **SC-004**: With the GPU backend, at least 99.9 % of rays satisfy the integration-residual bound used for the CPU backend, and fewer than 0.1 % of rays are unresolved.
- **SC-005**: Two GPU renders of the same inputs on the same machine produce identical output files (apart from the recorded wall time).
- **SC-006**: A 3840×2160 render at 16 samples per pixel completes without error with the GPU backend and takes at most one third of the CPU time.
- **SC-007**: The backend agreement check (five standard scenes, each 960×540 at 4 samples per pixel on both backends) completes in under 2 minutes on the reference machine.
- **SC-008**: Requesting the GPU backend on a machine without a usable GPU produces a clear error and a non-zero exit within 2 seconds.

## Assumptions

- This is an exploratory feature ("try acceleration"): its first deliverable is a measured answer to whether the GPU can match the CPU reference within the tolerances, and a working backend if it can.
- The user's Mac has an Apple-silicon GPU; the reference and test machine is an Apple M4. Other GPU vendors, other platforms, and multiple GPUs are out of scope.
- The existing CPU backend already meets the original performance goal (about 21 s for the default image); the motivation is headroom for large or many-sample renders, not rescuing a missed target.
- Apple GPUs do not provide 64-bit floating-point arithmetic, so the GPU backend works in 32-bit precision. This is the main risk to accuracy, and the ways to manage it are a planning question.
- The tolerances stated here are initial targets. They may be refined from measurement, but loosening any of them requires a written physical justification (project constitution, Principle III).
- The GPU backend is opt-in: the CPU backend stays the default until the GPU has demonstrated agreement. The command-line option for choosing a backend already exists and currently rejects the GPU choice.
- The physics model, output formats and command-line interface are unchanged apart from the backend choice, the new metadata fields and the agreement check.
- Real-time or interactive viewing, animation, and changes to the physical model are out of scope.
- Bit-identical results across different GPU models are not required, only across repeated runs on one machine.
