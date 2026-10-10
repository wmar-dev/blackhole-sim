"""Exact Schwarzschild light deflection by quadrature (G = c = M = 1).

A null geodesic with impact parameter b obeys, in its orbital plane, (du/dpsi)^2 = F(u) with
F(u) = 1/b^2 - u^2 (1 - 2u) and u = 1/r. For b > 3 sqrt(3) the ray has a turning point at u_t, the
smallest positive root of F.

Writes Tests/BlackHoleKitTests/Fixtures/schwarzschild_deflection.json with:
  * deflection:  alpha(b) = 2 * integral_0^{u_t} du/sqrt(F) - pi  (observer and source at infinity)
  * sweeps:      Delta psi_inf(b, r_obs): in-plane angle swept by a ray that starts at r_obs moving
                 inward and ends at infinity. The direction of travel at infinity makes this angle with
                 the observer's position direction.
  * einstein_ring: the b for which Delta psi_inf = pi at r_obs = 100 (a source exactly behind the hole),
                 and the angle that ring subtends at a static observer.

Run:  uv run python tools/reference/schwarzschild_deflection.py
"""

import json
from pathlib import Path

import mpmath as mp

mp.mp.dps = 40
OUT = Path(__file__).resolve().parents[2] / "Tests/BlackHoleKitTests/Fixtures/schwarzschild_deflection.json"
R_OBSERVER = mp.mpf(100)


def turning_u(b):
    roots = mp.polyroots([2, -1, 0, 1 / b**2], maxsteps=200, extraprec=100)  # 2u^3 - u^2 + 1/b^2 = 0
    real = sorted(mp.re(r) for r in roots if abs(mp.im(r)) < mp.mpf(10) ** -30 and mp.re(r) > 0)
    return real[0]


def integral(b, u_from, u_to):
    """Integral of du/sqrt(F(u)) from u_from to the turning point u_to = u_t (u_from < u_t).

    The square-root singularity at u_t is removed analytically: F(u) = 2 (t - u) G(u) with
    G(u) = -(u^2 + a u + c), a = t - 1/2, c = a t, and the substitution u = t - s^2 gives the smooth
    integrand 2 / sqrt(2 G(t - s^2)).
    """
    t = u_to
    alpha = t - mp.mpf(1) / 2
    beta = alpha * t

    def smooth(s):
        u = t - s * s
        g = -(u * u + alpha * u + beta)
        return 2 / mp.sqrt(2 * g)

    return mp.quad(smooth, [0, mp.sqrt(t - u_from)])


def sweep_to_infinity(b, r_obs):
    ut = turning_u(b)
    inbound = integral(b, 1 / r_obs, ut)
    outbound = integral(b, 0, ut)
    return inbound + outbound


def deflection(b):
    ut = turning_u(b)
    return 2 * integral(b, 0, ut) - mp.pi


def main():
    critical = 3 * mp.sqrt(3)
    deflections = [{"b": float(b), "alpha": float(deflection(mp.mpf(b)))} for b in (6, 8, 10, 20, 50, 100)]
    sweep_bs = (6, 7, 8, 10, 15, 20, 30, 50)
    sweeps = [
        {"b": float(b), "r_observer": float(R_OBSERVER), "delta_psi": float(sweep_to_infinity(mp.mpf(b), R_OBSERVER))}
        for b in sweep_bs
    ]
    b_e = mp.findroot(lambda b: sweep_to_infinity(b, R_OBSERVER) - mp.pi, mp.mpf(20))
    local = mp.asin(b_e * mp.sqrt(1 - 2 / R_OBSERVER) / R_OBSERVER)
    ring = {"b": float(b_e), "r_observer": float(R_OBSERVER), "local_angle": float(local)}
    OUT.write_text(
        json.dumps(
            {"critical_b": float(critical), "deflection": deflections, "sweeps": sweeps, "einstein_ring": ring}, indent=1
        )
        + "\n"
    )
    print(f"wrote {OUT.name}")
    for d in deflections:
        print(f"b={d['b']:>6}: alpha={d['alpha']:.9f}  4/b={4 / d['b']:.9f}")
    for s in sweeps:
        print(f"b={s['b']:>6}: delta_psi={s['delta_psi']:.9f} rad")
    print(f"Einstein ring at r_obs=100: b={ring['b']:.9f}, local angle={ring['local_angle']:.9f} rad = {float(local) * 180 / float(mp.pi):.4f} deg")


if __name__ == "__main__":
    main()
