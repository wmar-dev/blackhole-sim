# Reference-value scripts

Independent Python implementations that produce the reference values the Swift tests compare against.
Keeping them separate means the renderer is never checked against itself (Constitution Principle III).

## Running

From the repository root (the environment is defined by `pyproject.toml` and `uv.lock`):

```bash
uv sync
uv run python tools/reference/<script>.py
```

## Convention

Each script writes one JSON fixture to `Tests/BlackHoleKitTests/Fixtures/` and prints a short summary.
Fixtures are committed, so the Swift tests run without Python. Re-run a script whenever its
inputs change, and commit the regenerated fixture together with the script.

Units are geometrized (G = c = M = 1); see `docs/physics.md`.

| Script | Fixture | Purpose |
|--------|---------|---------|
| `kerr_basic.py` | `kerr_basic.json` | Horizon, ISCO, Keplerian Ω, ergosphere, R(r) and Θ_μ(μ) samples |
| `schwarzschild_deflection.py` | `schwarzschild_deflection.json` | Exact asymptotic deflection angle vs. impact parameter |
| `kerr_shadow.py` | `kerr_shadow.json` | Analytic Kerr shadow outline for a static observer at finite distance |
| `novikov_thorne.py` | `novikov_thorne.json` | Disk flux (closed form and numerical integral) and shift-factor spot values |
