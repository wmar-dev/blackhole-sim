"""Reference values for basic Kerr quantities (geometrized units G = c = M = 1).

Independent of the Swift implementation:
  * ISCO: largest-r real root of the circular-orbit stability polynomial
    x^4 - 6 x^2 + 8 a x - 3 a^2 = 0 with x = sqrt(r), cross-checked against the
    Bardeen-Press-Teukolsky closed form.
  * Photon orbits: closed form r = 2 [1 + cos((2/3) arccos(-+a))].
  * Potentials R(r) and Theta_mu(mu): obtained from the *Hamiltonian* null condition
    g^{mu nu} p_mu p_nu = 0 using a numerically inverted metric, not from the Carter formulas.

Writes Tests/BlackHoleKitTests/Fixtures/kerr_basic.json.
"""

import json
from pathlib import Path

import mpmath as mp

mp.mp.dps = 50

SPINS = ["0", "0.5", "0.9", "0.998"]
OUT = Path(__file__).resolve().parents[2] / "Tests/BlackHoleKitTests/Fixtures/kerr_basic.json"


def horizon(a):
    return 1 + mp.sqrt(1 - a * a)


def isco_bpt(a):
    z1 = 1 + (1 - a * a) ** (mp.mpf(1) / 3) * ((1 + a) ** (mp.mpf(1) / 3) + (1 - a) ** (mp.mpf(1) / 3))
    z2 = mp.sqrt(3 * a * a + z1 * z1)
    return 3 + z2 - mp.sqrt((3 - z1) * (3 + z1 + 2 * z2))


def isco_polynomial(a):
    roots = mp.polyroots([1, 0, -6, 8 * a, -3 * a * a], maxsteps=500, extraprec=200)
    real = [mp.re(x) for x in roots if abs(mp.im(x)) < mp.mpf(10) ** -30 and mp.re(x) > 0]
    target = isco_bpt(a)
    best = min(real, key=lambda x: abs(x * x - target))
    return best * best


def photon_orbit(a, prograde):
    sign = -1 if prograde else 1
    return 2 * (1 + mp.cos(mp.mpf(2) / 3 * mp.acos(sign * a)))


def metric_inverse(a, r, theta):
    sig = r * r + a * a * mp.cos(theta) ** 2
    dlt = r * r - 2 * r + a * a
    s2 = mp.sin(theta) ** 2
    gtt = -(1 - 2 * r / sig)
    gtp = -2 * a * r * s2 / sig
    gpp = (r * r + a * a + 2 * a * a * r * s2 / sig) * s2
    block = mp.matrix([[gtt, gtp], [gtp, gpp]])
    inv = block ** -1
    return inv, sig, dlt


def potentials_from_hamiltonian(a, r, theta, ell, p_theta):
    """Return (Q, R, Theta_mu) for a null covector with E=1, p_phi=ell, given p_theta."""
    inv, sig, dlt = metric_inverse(a, r, theta)
    energy = mp.mpf(1)
    pt, pp = -energy, ell
    rest = inv[0, 0] * pt * pt + 2 * inv[0, 1] * pt * pp + inv[1, 1] * pp * pp + p_theta ** 2 / sig
    p_r_sq = -rest * sig / dlt  # g^{rr} = Delta / Sigma
    big_r = dlt * dlt * p_r_sq
    mu = mp.cos(theta)
    carter_q = p_theta ** 2 + mu ** 2 * (ell ** 2 / mp.sin(theta) ** 2 - a * a * energy ** 2)
    theta_mu = (1 - mu ** 2) * p_theta ** 2
    return carter_q, big_r, theta_mu


def main():
    cases = []
    potentials = []
    for a_str in SPINS:
        a = mp.mpf(a_str)
        r_bpt = isco_bpt(a)
        r_poly = isco_polynomial(a)
        assert abs(r_bpt - r_poly) < mp.mpf(10) ** -25, (a_str, r_bpt, r_poly)
        omega = [
            {"r": float(r), "omega": float(1 / (mp.mpf(r) ** mp.mpf(1.5) + a))}
            for r in (r_poly, 3, 6, 10, 50)
        ]
        ergo = [
            {"mu": float(m), "r": float(1 + mp.sqrt(1 - a * a * mp.mpf(m) ** 2))} for m in (0, 0.5, 0.9, 1)
        ]
        cases.append(
            {
                "a": float(a),
                "horizon": float(horizon(a)),
                "isco": float(r_poly),
                "photon_orbit_prograde": float(photon_orbit(a, True)),
                "photon_orbit_retrograde": float(photon_orbit(a, False)),
                "omega": omega,
                "ergosphere": ergo,
            }
        )
        for r in (mp.mpf(x) for x in ("3.5", "6", "10", "50")):
            for theta in (mp.pi / 4, mp.pi / 2, mp.mpf("2.2")):
                for ell in (mp.mpf("-3"), mp.mpf("0.5"), mp.mpf("2")):
                    for p_theta in (mp.mpf("0.7"), mp.mpf("3")):
                        q, big_r, theta_mu = potentials_from_hamiltonian(a, r, theta, ell, p_theta)
                        potentials.append(
                            {
                                "a": float(a),
                                "E": 1.0,
                                "L": float(ell),
                                "Q": float(q),
                                "r": float(r),
                                "mu": float(mp.cos(theta)),
                                "R": float(big_r),
                                "theta_mu": float(theta_mu),
                            }
                        )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"cases": cases, "potentials": potentials}, indent=1) + "\n")
    print(f"wrote {OUT} ({len(cases)} spins, {len(potentials)} potential samples)")
    for c in cases:
        print(f"a={c['a']}: r+={c['horizon']:.9f} isco={c['isco']:.9f} photon(pro)={c['photon_orbit_prograde']:.9f}")


if __name__ == "__main__":
    main()
