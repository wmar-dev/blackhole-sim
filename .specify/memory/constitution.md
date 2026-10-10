<!--
Sync Impact Report
- Version change: (template, unversioned) → 1.0.0
- Modified principles: none renamed (all placeholders replaced with first concrete content)
- Added sections: Core Principles I–IV, Physical Fidelity Constraints, Development Workflow &
  Quality Gates, Governance
- Removed sections: none
- Templates requiring updates:
  - ✅ .specify/templates/plan-template.md (Constitution Check is generic; reads this file, no edit)
  - ✅ .specify/templates/spec-template.md (no conflicting mandatory sections)
  - ✅ .specify/templates/tasks-template.md (no conflicting task categories)
  - ✅ .specify/templates/checklist-template.md (no edit needed)
- Follow-up TODOs: none. Technology stack is intentionally not constrained here; it is
  decided per feature in plan.md.
-->
# Blackhole Sim Constitution

## Core Principles

### I. Accurate Physics (NON-NEGOTIABLE)
The simulation MUST implement real physics, not visual approximations that merely resemble it.
Rendered and computed results MUST derive from the governing equations of general relativity
(e.g., null geodesics in Schwarzschild or Kerr spacetime for light propagation), not from
artistic shortcuts such as faked lensing distortions or hand-tuned warping.

- Where an exact treatment is feasible, it MUST be used.
- Where an approximation is used for tractability, it MUST be documented with its governing
  assumption, its regime of validity, and an estimate of its error.
- No visual effect MAY be added that has no physical basis unless it is explicitly labeled
  as non-physical and can be disabled.

Rationale: The purpose of the project is a trustworthy simulation. A plausible-looking but
incorrect result is a defect, not a trade-off.

### II. Explicit Units and Conventions
Every physical quantity MUST have a documented unit system and sign/metric convention.

- The unit system (e.g., geometrized units with G = c = 1, mass in units of M) MUST be stated
  once and applied consistently across the codebase.
- Conversions to SI or other units MUST happen only at input/output boundaries.
- The metric signature, coordinate system (e.g., Boyer–Lindquist), and any gauge choices MUST
  be documented where they are first used.
- Magic numbers are prohibited; physical constants MUST be named and sourced (e.g., CODATA).

Rationale: Unit and convention mismatches are the most common source of silent physics errors.

### III. Validation Against Known Results (Test-First)
Physics code MUST be verified against analytically known or published results before it is
considered correct. Tests MUST be written before or alongside the implementation.

- Reference checks MUST include applicable cases such as: photon sphere at r = 3M and
  innermost stable circular orbit at r = 6M (Schwarzschild), critical impact parameter
  b = 3√3 M, event-horizon location at r = 2M, weak-field deflection angle 4M/b, and
  conserved quantities (energy, angular momentum, and the null condition) along geodesics.
- Numerical integrators MUST demonstrate that conserved quantities remain within a stated
  tolerance, and convergence under step-size refinement MUST be tested.
- A change that causes a reference test to fail MUST NOT be merged by loosening the test
  tolerance without a written physical justification.

Rationale: Agreement with known results is the only objective evidence the simulation is
accurate.

### IV. Numerical Rigor and Reproducibility
Numerical methods MUST be chosen and configured so errors are bounded and understood.

- Integration schemes, step-size control, and coordinate-singularity handling (at the horizon
  and poles) MUST be documented with their accuracy order and known failure modes.
- Floating-point precision choices (e.g., float32 vs. float64) MUST be justified; where
  reduced precision measurably degrades physical accuracy, higher precision MUST be used or
  the limitation documented.
- Results MUST be reproducible: simulation inputs, parameters (e.g., mass, spin, observer
  position), and random seeds MUST be recorded or deterministic.

Rationale: Black-hole geometry is numerically sensitive near the horizon and photon sphere;
unmanaged error produces wrong images.

## Physical Fidelity Constraints

- Scope of physics for each feature (e.g., Schwarzschild vs. Kerr, accretion disk model,
  relativistic Doppler beaming, gravitational redshift) MUST be stated in its spec, along with
  what is explicitly excluded.
- Every approximation or simplification MUST be recorded in the feature's plan.md and
  user-facing documentation, so users know which effects are and are not modeled.
- Observable claims (e.g., shadow size, disk brightness asymmetry) MUST cite the equation or
  source from which they are derived.
- Performance optimizations MUST NOT reduce physical accuracy beyond the documented tolerance.

## Development Workflow & Quality Gates

- Every plan MUST pass the Constitution Check, confirming compliance with Principles I–IV
  before design begins and again after design.
- Specs and plans MUST name the governing equations or references for each physical model
  introduced.
- Pull requests that touch physics code MUST include or update validation tests (Principle
  III) and note any new approximation (Principle I).
- Reviewers MUST verify units, conventions, and cited equations, not only code correctness.

## Governance

This constitution supersedes other project practices where they conflict. Compliance MUST be
verified in plan Constitution Checks and in code review.

- **Amendments**: Proposed in writing with rationale, reflected in this file with an updated
  Sync Impact Report, and propagated to dependent templates in the same change.
- **Versioning**: Semantic versioning. MAJOR for backward-incompatible principle removals or
  redefinitions; MINOR for new principles/sections or materially expanded guidance; PATCH for
  clarifications and wording fixes.
- **Compliance review**: Any deviation from a principle MUST be justified in the plan's
  Complexity Tracking section and approved before implementation. Principle I deviations
  additionally require a documented error estimate.
- Runtime development guidance lives in CLAUDE.md and the current feature plan.

**Version**: 1.0.0 | **Ratified**: 2026-10-09 | **Last Amended**: 2026-10-09
