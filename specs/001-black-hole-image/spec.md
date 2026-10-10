# Feature Specification: Physically Accurate Black Hole Image

**Feature Branch**: `001-black-hole-image`

**Created**: 2026-10-09

**Status**: Draft

**Input**: User description: "Create an image of a black hole by doing a physics accurate simulation"

## Clarifications

### Session 2026-10-09

- Q: Which accretion disk emission model? → A: Novikov–Thorne thin-disk temperature profile, with zero-torque inner boundary at the innermost stable orbit
- Q: Which observer and camera model? → A: Static observer at finite distance with a pinhole camera and configurable field of view
- Q: Which output format and dynamic range? → A: Both a tone-mapped display-ready PNG and a high-dynamic-range file holding unmodified physical intensities
- Q: What is the background sky content? → A: Seeded procedural star field by default, with a regular reference pattern selectable for validation
- Q: How far are light rays followed? → A: Up to 3 disk-plane crossings, giving primary, secondary and tertiary disk images and the photon ring (here meaning the superposition of these higher-order images)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Render a Black Hole Image (Priority: P1)

A user specifies a black hole (mass and spin), an observer position and orientation, and an image size, and receives an image of what an observer would see: the dark shadow, the gravitationally lensed accretion disk (including the bright secondary image of the disk's far side warped over and under the shadow), and the lensed background sky. The image is produced by tracing the paths of light through curved spacetime, not by artistic distortion.

**Why this priority**: This is the whole point of the project. A single correct image is a viable MVP on its own.

**Independent Test**: Run the simulation with default parameters (non-spinning black hole, observer at moderate distance, thin accretion disk viewed ~80° from the spin axis) and confirm an image file is produced whose shadow size, disk shape and lensing match published reference values.

**Acceptance Scenarios**:

1. **Given** a non-spinning black hole and a distant observer, **When** the image is rendered, **Then** the shadow appears as a circle whose angular size matches the theoretical critical impact parameter of 3√3 M within the documented tolerance.
2. **Given** an accretion disk viewed nearly edge-on, **When** the image is rendered, **Then** the far side of the disk appears lensed above and below the shadow, in addition to the directly visible near side.
3. **Given** a background star field or reference pattern, **When** the image is rendered, **Then** the background shows lensing, including multiple images and an Einstein ring for sources aligned behind the hole.
4. **Given** the same inputs and seed, **When** the image is rendered twice, **Then** the two images are identical.

---

### User Story 2 - Spinning Black Hole (Priority: P2)

A user sets a nonzero spin and sees the characteristic effects of a rotating black hole: a flattened, off-center shadow and a left-right brightness asymmetry in the disk from frame dragging and relativistic motion.

**Why this priority**: Spin is the main real-world variation, but a non-spinning image already delivers value.

**Independent Test**: Render with spin a/M = 0.9 and compare shadow shape and offset against published rotating-black-hole shadow results.

**Acceptance Scenarios**:

1. **Given** a spin of 0.9 M and an observer near the equatorial plane, **When** the image is rendered, **Then** the shadow is visibly flattened on the approaching side and displaced from the image center, matching reference shadow outlines within tolerance.
2. **Given** spin of zero, **When** the image is rendered, **Then** the result equals the non-spinning image from User Story 1.

---

### User Story 3 - Physically Meaningful Color and Brightness (Priority: P3)

A user sees the disk with relativistic Doppler shift, beaming and gravitational redshift applied, so the approaching side is brighter and bluer and the receding side dimmer and redder, and light from near the horizon is strongly dimmed and reddened.

**Why this priority**: It improves realism and physical fidelity, but the geometry of the image is valuable without it.

**Independent Test**: Compare per-pixel frequency shift and intensity ratios against the analytically computed values for known emitter positions.

**Acceptance Scenarios**:

1. **Given** an edge-on disk, **When** the image is rendered, **Then** the side moving toward the observer is brighter than the side moving away.
2. **Given** emission near the innermost stable orbit, **When** the image is rendered, **Then** the combined shift factor at sampled points matches the analytic redshift within tolerance.

---

### Edge Cases

- Rays that fall into the horizon MUST produce the shadow's black pixels, not artifacts or errors.
- Rays that skim the photon sphere and orbit multiple times MUST resolve to a finite, well-defined color within a documented limit on tracked windings; beyond 3 disk-plane crossings, further contributions are neglected and the neglect is documented. Rays that still cannot be resolved within the step budget MUST be flagged in the diagnostics and MUST NOT be silently assigned a color.
- Observers inside the ergosphere or horizon (where no static observer exists), or exactly on the spin axis, MUST be rejected with a clear message rather than producing singular or NaN results; observers arbitrarily close to the axis MUST render without NaN results.
- Spin values at or beyond the physical limit (a/M ≥ 1) MUST be rejected with a clear message.
- Invalid or nonsensical inputs (non-positive mass or image size, observer inside the horizon) MUST be rejected with a clear message.
- Rendering time for very large images MUST not run silently without progress indication.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST produce an image of a black hole as seen by a configurable observer, computed by tracing light paths through the curved spacetime of the black hole.
- **FR-002**: System MUST allow the user to set black hole spin (dimensionless, 0 ≤ a/M < 1), observer distance, observer inclination, and image resolution, with sensible defaults so a run requires no input.
- **FR-002a**: The observer MUST be static (at rest relative to the black hole) at a finite distance, viewing through a pinhole camera with a configurable field of view; the observer's own motion is not modeled.
- **FR-003**: System MUST render a dark shadow whose size and shape agree with the theoretical prediction for the chosen spin and inclination, within a documented tolerance.
- **FR-004**: System MUST render a thin accretion disk lying in the equatorial plane, between the innermost stable orbit and a configurable outer radius, including higher-order lensed images: each ray MUST be followed through up to 3 disk-plane crossings, giving primary, secondary and tertiary images; the visible photon ring is the superposition of the higher-order images within this cap. The disk's temperature and emitted flux MUST follow the Novikov–Thorne thin-disk profile for the chosen spin, with zero emission at the innermost stable orbit.
- **FR-005**: System MUST render a lensed background sky so gravitational lensing of distant sources is visible. The default sky MUST be a procedurally generated star field driven by a recorded seed, and a regular reference pattern (e.g., celestial grid) MUST be selectable for validation.
- **FR-006**: System MUST apply gravitational redshift and relativistic Doppler shift and beaming to the disk's color and brightness.
- **FR-007**: System MUST save two outputs: a tone-mapped, display-ready PNG that opens in common viewers, and a high-dynamic-range file holding the unmodified physical intensities. Intensity-based validation (FR-011 and the User Story 3 checks) MUST use the high-dynamic-range data, not the tone-mapped image.
- **FR-008**: System MUST verify the constants of motion and the null-geodesic consistency of each traced ray and report when a ray exceeds the documented tolerance.
- **FR-009**: System MUST produce identical output for identical inputs.
- **FR-010**: System MUST document the unit system, coordinate conventions, governing equations, and every approximation made (per the project constitution), including the disk model and its limits.
- **FR-011**: System MUST include automated validation checks against known results (photon sphere, critical impact parameter, weak-field deflection 4M/b, horizon location, shadow outline for nonzero spin).
- **FR-012**: System MUST show progress while rendering and reject invalid inputs with clear messages.

### Key Entities

- **Black Hole**: Defined by mass (sets the length scale) and dimensionless spin; determines the spacetime geometry.
- **Observer**: Defined by distance, inclination relative to the spin axis, and field of view; the viewpoint of the image.
- **Accretion Disk**: A thin, equatorial emitting structure with inner and outer radii and a brightness/temperature profile.
- **Background Sky**: The distant source of light behind the black hole, a star field or reference pattern.
- **Light Ray**: A path from the observer through each image pixel, traced back through spacetime until it reaches the horizon, the disk, or the sky.
- **Rendered Image**: The final pixel grid, with the parameters used to produce it recorded alongside it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For a non-spinning black hole, the shadow's measured angular radius matches the theoretical value for a static observer at the stated distance, arcsin(3√3·√(1 − 2M/r)/r), which corresponds to the critical impact parameter 3√3 M, to within 1%.
- **SC-002**: For spin 0.9 M, the shadow outline matches published reference outlines to within 2%.
- **SC-003**: The normalized first-integral residuals of traced rays (the null-geodesic consistency conditions defined in plan.md) stay below 0.1% for at least 99.9% of rays.
- **SC-004**: Weak-field deflection for rays at large impact parameter agrees with 4M/b to within 1%.
- **SC-005**: A user with the project's build prerequisites installed can produce a default 1080p image with one command in under 10 minutes on a recent Apple-silicon laptop.
- **SC-006**: Two runs with identical inputs produce byte-identical or pixel-identical images.
- **SC-007**: A domain expert reviewing the default image confirms it shows the expected features (shadow, photon ring, secondary disk image, Doppler asymmetry) with no non-physical artifacts.

## Assumptions

- The primary user is a researcher, student or enthusiast who wants a faithful visualization, not a real-time experience; offline rendering is acceptable.
- Output is a single still image; animation and interactive exploration are out of scope.
- The black hole is isolated and stationary (Kerr family, uncharged); no black hole mergers, binaries, or charge.
- The accretion disk is geometrically thin, optically thick and equatorial; volumetric plasma, jets, turbulence, and polarization are out of scope.
- The background sky is a synthetic star field or reference pattern, not a real astronomical survey; user-supplied sky images are out of scope.
- Disk colors use a blackbody spectrum at the local Novikov–Thorne temperature; spectral hardening, atmosphere models and radiative transfer are out of scope.
- Default parameters are chosen so a fresh run produces a recognizable, reference-comparable image.
