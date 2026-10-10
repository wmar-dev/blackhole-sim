"""Analytic Kerr shadow outline for a static observer at finite distance (G = c = M = 1).

The shadow boundary is the image of the spherical photon orbits. For a photon orbit at radius r the
constants of motion (E = 1) are

    xi  = L/E  = -(r^3 - 3 r^2 + a^2 r + a^2) / (a (r - 1))
    eta = Q/E^2 =  r^3 (4 a^2 - r (r - 3)^2) / (a^2 (r - 1)^2)          (Bardeen 1973)

and orbits exist for eta >= 0, i.e. r between the prograde and retrograde equatorial photon orbits.
For an observer at (r_o, theta_o) such a photon arrives with

    p_t = -1, p_phi = xi, p_theta = +-sqrt(eta + a^2 cos^2 + ... ), p_r = +sqrt(R(r_o)) / Delta

(R and Theta are the Carter potentials). Its direction in the static observer's orthonormal frame
(Gram-Schmidt on d_t, d_r, d_theta, d_phi) fixes the point where it appears on a pinhole camera that looks
along -r with up = -theta: with p-hat the direction of the physical photon in (r, theta, phi),

    X = tan(angle right of the axis) = -p_phi_hat / p_r_hat,   Y = tan(angle up) = +p_theta_hat / p_r_hat.

(The traced ray travels the opposite way, so image right is +phi and up is -theta.)

Writes Tests/BlackHoleKitTests/Fixtures/kerr_shadow.json: for each (a, inclination) the radial distance
rho(angle) = sqrt(X^2 + Y^2) of the outline in the tangent plane, sampled in 72 image directions.

Run:  uv run python tools/reference/kerr_shadow.py
"""

import json
from pathlib import Path

import numpy as np

OUT = Path(__file__).resolve().parents[2] / "Tests/BlackHoleKitTests/Fixtures/kerr_shadow.json"
DISTANCE = 100.0
SPINS = (0.5, 0.9, 0.998)
INCLINATIONS = (45.0, 85.0, 90.0)
DIRECTIONS = 72


def photon_orbit_radii(a):
    r_pro = 2 * (1 + np.cos(2 / 3 * np.arccos(-a)))
    r_retro = 2 * (1 + np.cos(2 / 3 * np.arccos(a)))
    return r_pro, r_retro


def constants(a, r):
    xi = -(r**3 - 3 * r**2 + a**2 * r + a**2) / (a * (r - 1))
    eta = r**3 * (4 * a**2 - r * (r - 3) ** 2) / (a**2 * (r - 1) ** 2)
    return xi, eta


def outline_points(a, theta_o, r_o):
    """Image-plane points (X, Y) of the critical curve for a static observer at (r_o, theta_o)."""
    mu = np.cos(theta_o)
    s2 = 1 - mu**2
    sig = r_o**2 + a**2 * mu**2
    dlt = r_o**2 - 2 * r_o + a**2
    gtt = -(1 - 2 * r_o / sig)
    gtp = -2 * a * r_o * s2 / sig
    gpp = (r_o**2 + a**2 + 2 * a**2 * r_o * s2 / sig) * s2
    grr = sig / dlt
    gthth = sig
    nphi = np.sqrt(gpp + gtp**2 / (-gtt))
    energy_local = 1 / np.sqrt(-gtt)  # -p.e0 with E = 1

    r_pro, r_retro = photon_orbit_radii(a)
    points = []
    for r in np.linspace(r_pro, r_retro, 200001)[1:-1]:
        xi, eta = constants(a, r)
        theta_pot = eta + a**2 * mu**2 - xi**2 * mu**2 / s2  # Theta(theta_o) = eta + a^2 cos^2 - xi^2 cot^2
        radial = ((r_o**2 + a**2) - a * xi) ** 2 - dlt * ((xi - a) ** 2 + eta)
        if theta_pot < 0 or radial <= 0:
            continue
        p_r = np.sqrt(radial) / dlt  # outward (the photon arrives from the sky)
        for sign in (1.0, -1.0):
            p_th = sign * np.sqrt(theta_pot)
            r_hat = p_r / np.sqrt(grr)
            th_hat = p_th / np.sqrt(gthth)
            ph_hat = (xi - gtp / (-gtt)) / nphi  # p_phi - (g_tphi/g_tt) p_t ... with p_t = -1: xi + gtp/gtt*(-1)*(-1)
            # e_phi component of the covector: (p_phi + (g_tphi/(-g_tt)) p_t) / norm, p_t = -1
            ph_hat = (xi - gtp / (-gtt)) / nphi
            # direction cosines relative to the local energy
            n_r, n_th, n_ph = r_hat / energy_local, th_hat / energy_local, ph_hat / energy_local
            points.append((-n_ph / n_r, n_th / n_r))
    return np.array(points)


def radial_profile(points):
    angles = np.arctan2(points[:, 1], points[:, 0])
    rho = np.hypot(points[:, 0], points[:, 1])
    order = np.argsort(angles)
    angles, rho = angles[order], rho[order]
    targets = np.linspace(-np.pi, np.pi, DIRECTIONS, endpoint=False)
    # Periodic interpolation.
    a_ext = np.concatenate([angles - 2 * np.pi, angles, angles + 2 * np.pi])
    r_ext = np.concatenate([rho, rho, rho])
    return targets, np.interp(targets, a_ext, r_ext)


def main():
    cases = []
    for a in SPINS:
        for inc in INCLINATIONS:
            pts = outline_points(a, np.radians(inc), DISTANCE)
            angles, rho = radial_profile(pts)
            cases.append(
                {
                    "a": a,
                    "inclination_deg": inc,
                    "distance": DISTANCE,
                    "angles": angles.tolist(),
                    "rho": rho.tolist(),
                    "rho_left": float(np.interp(np.pi, np.concatenate([angles, [np.pi]]), np.concatenate([rho, [rho[0]]]))),
                    "rho_right": float(np.interp(0.0, angles, rho)),
                }
            )
            print(f"a={a} i={inc}: rho right={cases[-1]['rho_right']:.5f} left={cases[-1]['rho_left']:.5f}  ({len(pts)} outline points)")
    OUT.write_text(json.dumps({"distance": DISTANCE, "cases": cases}) + "\n")
    print(f"wrote {OUT.name}")


if __name__ == "__main__":
    main()
