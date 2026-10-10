# Implementation Plan: Physically Accurate Black Hole Image

**Branch**: `001-black-hole-image` | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-black-hole-image/spec.md`

## Summary

Render a still image of a Kerr black hole (spin 0 ≤ a/M < 1) with a thin Novikov–Thorne accretion disk and a lensed star-field sky, seen by a static pinhole observer at finite distance. Every pixel is a backward-traced null geodesic integrated in float64 on the CPU across all cores. Geodesics use the Carter/Mino-time form of the Kerr equations, whose constants of motion (E, L, Q) are fixed at launch, so integration accuracy is checked by the first-integral residuals of the radial and polar potentials. Disk color comes from the exact Doppler/gravitational shift factor g applied to a blackbody at the local Novikov–Thorne temperature. Outputs are a tone-mapped PNG, a 32-bit float OpenEXR holding physical intensities, and a JSON metadata sidecar. A Metal GPU backend is a later, optional, gated addition; the float64 CPU path is the reference and meets the performance goal on its own (to be confirmed by measurement).

## Technical Context

**Language/Version**: Swift 6.4 (installed toolchain), Swift Package Manager

**Primary Dependencies**: Apple system frameworks only for the core (Foundation, ImageIO, CoreGraphics; Dispatch for threading); swift-argument-parser for the CLI. Metal is used only by the optional GPU backend.

**Storage**: Files only: PNG, OpenEXR, JSON metadata sidecar

**Testing**: Swift Testing (`swift test`; verified working on this machine)

**Target Platform**: macOS 14+ on Apple Silicon (developed on M4, arm64)

**Project Type**: Library plus command-line tool

**Performance Goals**: Default 1080p image in under 10 minutes on a typical laptop (SC-005), on the CPU backend. Estimate (to be confirmed by benchmark): ~1e6 flops/ray × ~8M rays (2×2 supersampling) ≈ minutes on 10 performance cores.

**Constraints**: float64 throughout the reference path; deterministic output independent of thread count; no network at runtime; normalized first-integral residuals δ_r = |ṙ² − R|/(r²+a²)² and δ_μ = |μ̇² − Θ_μ|/(Q + L² + a²) (with E = 1) below 1e-3 for at least 99.9% of rays, and below 1e-6 in integrator tests

**Scale/Scope**: One still image per run; ~2–8M rays; single machine

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Accurate Physics | Light follows Kerr null geodesics; disk is Novikov–Thorne; color uses exact shift factor; all approximations listed in research.md §Approximations with validity and error | PASS |
| II. Explicit Units and Conventions | G = c = M = 1 geometrized; Boyer–Lindquist coordinates, signature (−,+,+,+); SI conversion only at the output/metadata boundary; constants named and sourced (CODATA 2018 or newer) | PASS |
| III. Validation (Test-First) | Reference tests listed in research.md §Validation and quickstart.md; written before the physics code they cover | PASS (enforced in tasks) |
| IV. Numerical Rigor and Reproducibility | Adaptive Dormand–Prince 5(4) in float64; residual monitoring; pole-safe variable μ = cos θ; horizon cutoff documented; seeded sky and jitter; thread-count independent | PASS |

**Post-design re-check (after Phase 1)**: PASS. Two items are carried as explicit risks, not violations: (1) the 3-crossing cap truncates the photon ring (research.md §Risks); (2) any float32 Metal path must reproduce the float64 reference within tolerance before it can be enabled (Principle IV).

## Project Structure

### Documentation (this feature)

```text
specs/001-black-hole-image/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── cli.md           # Command-line contract
│   └── render-metadata.schema.json  # Metadata sidecar schema
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks, not created here)
```

### Source Code (repository root)

```text
Package.swift
pyproject.toml, uv.lock   # Python reference tooling (uv)
README.md
docs/
└── physics.md           # Units, equations, approximations, known limits
tools/reference/         # Python scripts that generate test fixtures
Sources/
├── BlackHoleKit/
│   ├── Spacetime/       # Kerr metric, horizons, ISCO, potentials R(r) and Θ(μ), constants
│   ├── Geodesic/        # Mino-time equations, Dormand–Prince integrator, plane-crossing detection
│   ├── Camera/          # Static-observer tetrad, pixel → initial photon momentum
│   ├── Disk/            # Novikov–Thorne flux, Keplerian velocity, shift factor
│   ├── Sky/             # Seeded star field, reference grid
│   ├── Radiometry/      # Planck → CIE XYZ → linear sRGB, tone mapping
│   ├── Render/          # Tiled parallel renderer, per-pixel sampling, diagnostics
│   └── Output/          # PNG, OpenEXR, metadata JSON
├── bhsim/               # CLI executable
└── (later, optional) BlackHoleKit/Metal/   # GPU backend, gated on agreement with CPU reference
Tests/
└── BlackHoleKitTests/
    ├── Analytic/        # Photon sphere, ISCO, horizon, shadow, weak-field deflection
    ├── Geodesic/        # First-integral residuals, step-size convergence
    ├── Disk/            # Flux vs. independent numerical integral, shift factor spot checks
    ├── Render/          # Shadow radius in rendered image, determinism, thread invariance
    ├── Output/          # EXR round-trip, PNG, metadata schema
    └── Fixtures/        # JSON reference values from tools/reference
```

**Structure Decision**: Single Swift package with one library (all physics, testable without the CLI) and one thin CLI target. Physics modules are separated by concept so each maps to a validation test group.

## Complexity Tracking

No constitution violations. The optional Metal backend adds a second code path; it is justified only if benchmarks show the CPU path misses SC-005, and it is gated on matching the CPU reference.
