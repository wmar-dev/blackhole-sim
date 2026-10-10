"""Novikov-Thorne thin-disk flux and shift-factor reference values (G = c = M = 1).

Flux, computed two independent ways, per unit accretion rate (so F-hat has units of 1/M^2):

  closed form (Page & Thorne 1974, eq. 15n), x = sqrt(r), x0 = sqrt(r_isco):
      F = 3/(8 pi) * 1/(x^4 (x^3 - 3x + 2a)) *
          [ x - x0 - (3/2) a ln(x/x0) - sum_i 3 (x_i - a)^2 / (x_i (x_i - x_j)(x_i - x_k)) ln((x - x_i)/(x0 - x_i)) ]
      with x_1 = 2 cos(arccos(a)/3 - pi/3), x_2 = 2 cos(arccos(a)/3 + pi/3), x_3 = -2 cos(arccos(a)/3).

  conservation-law integral (defining relation):
      F = 1/(4 pi r) * (-dOmega/dr) / (E - Omega L)^2 * integral_{r_isco}^{r} (E - Omega L) dL/dr' dr'
  with E, L, Omega the specific energy, angular momentum and angular velocity of prograde circular
  geodesics (Bardeen, Press & Teukolsky 1972).

The two must agree; the script asserts it and records the agreement.

Shift factor g = nu_obs / nu_emit = (-p.u_obs) / (-p.u_emit) for a photon with E = 1 and angular momentum L,
emitted by gas on a circular equatorial geodesic and received by a static observer at r_o, computed from the
full metric tensor (not from the closed-form u^t). For a = 0 and L = 0 this reduces to
sqrt(1 - 3/r) / sqrt(1 - 2/r_o).

Also records the disk temperature scale for a physical black hole (mass in solar masses, luminosity as a
fraction of Eddington) from CODATA constants.

Writes Tests/BlackHoleKitTests/Fixtures/novikov_thorne.json.   Run: uv run python tools/reference/novikov_thorne.py
"""

import json
from pathlib import Path

import mpmath as mp
from scipy import constants as sc

mp.mp.dps = 30
OUT = Path(__file__).resolve().parents[2] / "Tests/BlackHoleKitTests/Fixtures/novikov_thorne.json"
SPINS = ["0", "0.5", "0.9", "0.998"]
R_OBSERVER = mp.mpf(100)


def isco(a):
    roots = mp.polyroots([1, 0, -6, 8 * a, -3 * a * a], maxsteps=500, extraprec=200)
    z1 = 1 + (1 - a * a) ** (mp.mpf(1) / 3) * ((1 + a) ** (mp.mpf(1) / 3) + (1 - a) ** (mp.mpf(1) / 3))
    z2 = mp.sqrt(3 * a * a + z1 * z1)
    target = 3 + z2 - mp.sqrt((3 - z1) * (3 + z1 + 2 * z2))
    real = [mp.re(x) for x in roots if abs(mp.im(x)) < mp.mpf(10) ** -20 and mp.re(x) > 0]
    best = min(real, key=lambda x: abs(x * x - target))
    return best * best


def omega(a, r):
    return 1 / (r ** mp.mpf(1.5) + a)


def energy(a, r):
    d = r ** mp.mpf(0.75) * mp.sqrt(r ** mp.mpf(1.5) - 3 * mp.sqrt(r) + 2 * a)
    return (r ** mp.mpf(1.5) - 2 * mp.sqrt(r) + a) / d


def ang_mom(a, r):
    d = r ** mp.mpf(0.75) * mp.sqrt(r ** mp.mpf(1.5) - 3 * mp.sqrt(r) + 2 * a)
    return (r * r - 2 * a * mp.sqrt(r) + a * a) / d


def flux_closed(a, r):
    x, x0 = mp.sqrt(r), mp.sqrt(isco(a))
    if a == 0:
        roots = [mp.sqrt(3), mp.mpf(0), -mp.sqrt(3)]
    else:
        th = mp.acos(a) / 3
        roots = [2 * mp.cos(th - mp.pi / 3), 2 * mp.cos(th + mp.pi / 3), -2 * mp.cos(th)]
    bracket = x - x0 - mp.mpf(3) / 2 * a * mp.log(x / x0) if a != 0 else x - x0
    for i, xi in enumerate(roots):
        if a == 0 and xi == 0:
            continue  # the x_2 = 0 term vanishes for a = 0: (x_2 - a)^2 / x_2 -> 0
        xj, xk = [roots[j] for j in range(3) if j != i]
        bracket -= 3 * (xi - a) ** 2 / (xi * (xi - xj) * (xi - xk)) * mp.log((x - xi) / (x0 - xi))
    return 3 / (8 * mp.pi) * bracket / (x**4 * (x**3 - 3 * x + 2 * a))


def flux_integral(a, r):
    r_in = isco(a)
    if r <= r_in:
        return mp.mpf(0)
    dl = lambda rr: mp.diff(lambda t: ang_mom(a, t), rr)
    integral = mp.quad(lambda rr: (energy(a, rr) - omega(a, rr) * ang_mom(a, rr)) * dl(rr), [r_in, r])
    domega = mp.diff(lambda t: omega(a, t), r)
    return 1 / (4 * mp.pi * r) * (-domega) / (energy(a, r) - omega(a, r) * ang_mom(a, r)) ** 2 * integral


def metric_matrix(a, r):
    """Full covariant metric at (r, theta = pi/2) in the order (t, r, theta, phi)."""
    sig = r * r
    dlt = r * r - 2 * r + a * a
    gtt = -(1 - 2 * r / sig)
    gtp = -2 * a * r / sig
    gpp = r * r + a * a + 2 * a * a * r / sig
    return mp.matrix([[gtt, 0, 0, gtp], [0, sig / dlt, 0, 0], [0, 0, sig, 0], [gtp, 0, 0, gpp]])


def shift_factor(a, r, ell, r_o):
    g = metric_matrix(a, r)
    om = omega(a, r)
    u = mp.matrix([1, 0, 0, om])
    norm = (u.T * g * u)[0]
    u = u / mp.sqrt(-norm)  # u^t u^phi normalised so u.u = -1
    p_low = mp.matrix([-1, 0, 0, ell])  # p_t = -E, p_phi = L (p_r, p_theta do not contribute: u has no r/theta part)
    p_dot_u_em = (p_low.T * u)[0]
    go = metric_matrix(a, r_o)
    uo = mp.matrix([1 / mp.sqrt(-go[0, 0]), 0, 0, 0])
    p_dot_u_obs = (p_low.T * uo)[0]
    return p_dot_u_obs / p_dot_u_em


def temperature_scale(a, mass_solar, fraction, radii):
    """T(r) in kelvin at the given radii (units of M), from CODATA constants."""
    g_newton, c, sigma_sb = sc.G, sc.c, sc.Stefan_Boltzmann
    m_sun = 1.32712440018e20 / g_newton  # IAU nominal GM_sun / G
    mass = mass_solar * m_sun
    l_edd = 4 * mp.pi * g_newton * mass * sc.m_p * c / sc.physical_constants["Thomson cross section"][0]
    eta = 1 - energy(a, isco(a))
    mdot = fraction * l_edd / (eta * c**2)
    length = g_newton * mass / c**2
    out = []
    for r in radii:
        f_phys = mdot * c**2 / length**2 * flux_closed(a, r)
        out.append(float((f_phys / sigma_sb) ** mp.mpf(0.25)))
    return out, float(eta), float(mdot)


def main():
    cases = []
    worst = 0.0
    for a_str in SPINS:
        a = mp.mpf(a_str)
        r_in = isco(a)
        factors = [1.0, 1.001, 1.01, 1.1, 1.5, 2.0, 3.0, 5.0, 10.0, 30.0, 100.0]
        flux = []
        for f in factors:
            r = r_in * f
            closed = flux_closed(a, r) if f > 1 else mp.mpf(0)
            integral = flux_integral(a, r)
            if f > 1.0001:
                rel = abs(closed - integral) / integral
                worst = max(worst, float(rel))
                assert rel < mp.mpf(10) ** -8, (a_str, f, closed, integral, rel)
            flux.append({"r": float(r), "closed": float(closed), "integral": float(integral)})
        eta = float(1 - energy(a, r_in))
        shifts = []
        for r in (r_in * mp.mpf("1.05"), 8, 20):
            for ell in (-5, 0, 5):
                shifts.append(
                    {"r": float(r), "L": float(ell), "r_observer": float(R_OBSERVER), "g": float(shift_factor(a, mp.mpf(r), mp.mpf(ell), R_OBSERVER))}
                )
        scale_radii = [float(r_in * f) for f in (1.05, 1.5, 3.0, 10.0)]
        temps, eta2, mdot = temperature_scale(a, 10.0, 0.1, [mp.mpf(r) for r in scale_radii])
        cases.append(
            {
                "a": float(a),
                "isco": float(r_in),
                "efficiency": eta,
                "flux": flux,
                "shifts": shifts,
                "temperature_scale": {"mass_solar": 10.0, "fraction": 0.1, "radii": scale_radii, "T": temps, "mdot_kg_per_s": mdot},
            }
        )
        print(f"a={a_str}: r_isco={float(r_in):.6f} efficiency={eta:.5f}  T(1.05 r_isco, 10 Msun, 0.1 Edd)={temps[0]:.4g} K")
    face_on = [
        {"r": r, "r_observer": float(R_OBSERVER), "g": float(mp.sqrt(1 - 3 / mp.mpf(r)) / mp.sqrt(1 - 2 / R_OBSERVER))} for r in (6, 10, 20, 60)
    ]
    OUT.write_text(json.dumps({"cases": cases, "schwarzschild_face_on": face_on}, indent=1) + "\n")
    print(f"closed form vs conservation integral: worst relative difference {worst:.3e}")
    print(f"wrote {OUT.name}")


if __name__ == "__main__":
    main()
