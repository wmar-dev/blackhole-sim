import Foundation

/// Display transform for the PNG (the EXR keeps the unmodified physical values).
///
/// Linear radiance (reference units, 1.0 = brightest unshifted disk emission) is scaled by
/// 2^(baseExposureStops + exposure), where the base exposure of −1 stop leaves headroom for gas that is
/// Doppler-boosted above the unshifted peak,
/// compressed per channel with the Narkowicz ACES filmic curve
///     f(x) = x(2.51x + 0.03) / (x(2.43x + 0.59) + 0.14),
/// and encoded with the sRGB transfer function. This is a presentation choice, not physics.
public enum ToneMap {
    /// Fixed display exposure applied before the user's `--exposure` offset.
    public static let baseExposureStops = -1.0

    public static func filmic(_ x: Double) -> Double {
        let v = max(x, 0)
        return min(max((v * (2.51 * v + 0.03)) / (v * (2.43 * v + 0.59) + 0.14), 0), 1)
    }

    public static func srgbEncode(_ x: Double) -> Double {
        let v = min(max(x, 0), 1)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    /// 8-bit sRGB, `width × height × 3` bytes in the same order as `hdr`.
    public static func rgb8(from hdr: [SIMD3<Float>], exposureStops: Double) -> [UInt8] {
        let gain = pow(2.0, baseExposureStops + exposureStops)
        var out = [UInt8]()
        out.reserveCapacity(hdr.count * 3)
        for p in hdr {
            for c in 0..<3 {
                let encoded = srgbEncode(filmic(Double(p[c]) * gain))
                out.append(UInt8((encoded * 255).rounded()))
            }
        }
        return out
    }
}
