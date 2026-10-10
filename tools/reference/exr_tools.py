"""Minimal reader for the OpenEXR files written by bhsim (uncompressed scanline, B/G/R float channels).

Independent of the Swift reader, so it also checks that the files are well-formed. Used for analysis
from the command line, e.g.

    uv run python tools/reference/exr_tools.py out/shadow.exr          # print a summary
    uv run python tools/reference/exr_tools.py out/shadow.exr --shadow 12   # measure the shadow (fov in degrees)
"""

import argparse
import struct
from pathlib import Path

import numpy as np


def read_exr(path):
    """Return (rgb array of shape (h, w, 3), attributes dict)."""
    data = Path(path).read_bytes()
    assert data[:4] == bytes([0x76, 0x2F, 0x31, 0x01]), "not an OpenEXR file"
    assert data[4] == 2 and data[5:8] == b"\0\0\0", "unsupported EXR version/flags"
    pos = 8
    attributes = {}
    width = height = 0
    while True:
        end = data.index(b"\0", pos)
        name = data[pos:end].decode()
        pos = end + 1
        if not name:
            break
        end = data.index(b"\0", pos)
        kind = data[pos:end].decode()
        pos = end + 1
        (size,) = struct.unpack_from("<i", data, pos)
        pos += 4
        payload = data[pos : pos + size]
        pos += size
        if name == "dataWindow":
            x0, y0, x1, y1 = struct.unpack("<4i", payload)
            width, height = x1 - x0 + 1, y1 - y0 + 1
        elif name == "compression":
            assert payload[0] == 0, "compressed EXR not supported"
        elif kind == "float" and size == 4:
            attributes[name] = struct.unpack("<f", payload)[0]
        elif kind == "string":
            attributes[name] = payload.decode()
    offsets = struct.unpack_from(f"<{height}Q", data, pos)
    rgb = np.empty((height, width, 3), dtype=np.float32)
    for y in range(height):
        base = offsets[y] + 8
        row = np.frombuffer(data, dtype="<f4", count=3 * width, offset=base).reshape(3, width)  # B, G, R planes
        rgb[y, :, 0], rgb[y, :, 1], rgb[y, :, 2] = row[2], row[1], row[0]
    return rgb, attributes


def shadow_angular_radius(rgb, fov_degrees):
    """Angular radius of the shadow: the zero-radiance region, as the equal-area circle (radians)."""
    h, w, _ = rgb.shape
    dark = (rgb.max(axis=2) == 0)
    radius_px = np.sqrt(dark.sum() / np.pi)
    return np.arctan(radius_px * 2 * np.tan(np.radians(fov_degrees) / 2) / w)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("exr")
    parser.add_argument("--shadow", type=float, metavar="FOV_DEG", help="measure the shadow radius")
    args = parser.parse_args()
    rgb, attrs = read_exr(args.exr)
    print(f"{args.exr}: {rgb.shape[1]}x{rgb.shape[0]}, min {rgb.min():.4g}, max {rgb.max():.4g}, attributes {attrs}")
    if args.shadow:
        print(f"shadow angular radius = {shadow_angular_radius(rgb, args.shadow):.6f} rad")


if __name__ == "__main__":
    main()
