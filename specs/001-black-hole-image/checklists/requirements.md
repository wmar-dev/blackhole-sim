# Specification Quality Checklist: Physically Accurate Black Hole Image

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-09
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Physics terms (geodesics, conserved quantities, shadow) are domain requirements mandated by the project constitution, not implementation details.
- Tolerances in success criteria are initial targets and may be refined during planning.

## SC-007 review (task T064)

**Status: implementer self-review recorded; sign-off by a human domain expert is still pending.** SC-007 asks for an
expert's confirmation, which the implementing agent cannot supply.

Self-review of `out/default.png` / `out/default.exr` (default scene, 1920×1080, 4 samples per pixel) against the
SC-007 list, including a zoomed inspection of the shadow edge:

- Shadow: dark, circular, centred; radius within 0.006 % of arcsin(3√3·√(1 − 2M/r)/r) (ray-level and from the EXR).
- Photon ring: a thin bright ring just outside the shadow edge, from the higher-order (second and third crossing)
  images of the disk's inner region.
- Secondary disk image: the far side of the disk is lensed over the top of the shadow and a second image curls
  underneath it; the dark band between the arch and the ring is lensed sky seen through the empty space inside r_isco.
- Doppler asymmetry: with the default (hot, Rayleigh–Jeans) disk the approaching side is about 1.6× brighter with
  unchanged hue; with a cool disk it is about 11× brighter and bluer (see research.md §Validation).
- Artifacts: no NaN or non-finite pixels, 0 unresolved rays, residual ≤ 2.3×10⁻⁹. The only visible blemish is
  faint single-pixel Monte Carlo speckle along the very thin photon ring at 4 samples per pixel; more samples
  (`--samples 9` or 16) reduce it.

A domain expert should still confirm the image, in particular the relative brightness of the primary and
higher-order images and the colour choices (visible-band blackbody, ACES display curve).
