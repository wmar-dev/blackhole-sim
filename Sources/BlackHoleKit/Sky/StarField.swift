import Foundation

public struct Star: Sendable, Equatable {
    /// Unit vector toward the star (Cartesian, z along the spin axis).
    public var direction: SIMD3<Double>
    /// Peak surface brightness (linear sRGB, reference units), reached at the star's centre.
    public var peakRadiance: SIMD3<Double>

    public init(direction: SIMD3<Double>, peakRadiance: SIMD3<Double>) {
        self.direction = direction
        self.peakRadiance = peakRadiance
    }
}

/// Seeded procedural star field (research.md D6).
///
/// Each star is a small Gaussian disc of angular width σ with constant surface brightness profile
/// I(α) = I₀ exp(−α²/2σ²). Because surface brightness is conserved by lensing, a lensed star is stretched
/// into an arc and its flux magnified in proportion, with no analytic Jacobian: it simply covers more
/// samples. Stars are synthetic and illustrative (not a real catalogue).
///
/// Distributions (documented approximations):
///  * positions uniform on the sphere;
///  * temperature log-uniform in 3000–30000 K, colour from the blackbody spectrum at that temperature;
///  * peak surface brightness 10^(−2.5 u) × `peakLuminance`, u uniform in [0, 1).
public struct StarField: SkyModel, Sendable {
    /// Angular width σ of every star, radians. 2.5×10⁻⁴ rad is about one pixel at the default field of view.
    public static let defaultSigma = 2.5e-4
    /// Luminance of the brightest star's peak, in reference units (1.0 = brightest unshifted disk emission).
    public static let peakLuminance = 1.0
    /// Faint uniform sky light, so that shadow pixels (exactly zero) are distinguishable from sky.
    public static let defaultBackground = SIMD3<Double>(0.002, 0.002, 0.003)

    public let stars: [Star]
    public let sigma: Double
    public let background: SIMD3<Double>

    // Uniform 3D grid over [−1, 1]³ with `cellsPerAxis` cells per axis; stars are bucketed by cell.
    private static let cellsPerAxis = 200
    private let cellStart: [Int32]
    private let cellStars: [Int32]
    private let cutoff: Double

    public init(stars: [Star], sigma: Double = StarField.defaultSigma, background: SIMD3<Double> = StarField.defaultBackground) {
        self.stars = stars
        self.sigma = sigma
        self.background = background
        cutoff = 6 * sigma
        let cells = Self.cellsPerAxis
        var counts = [Int32](repeating: 0, count: cells * cells * cells + 1)
        let keys = stars.map { Self.cellKey(for: $0.direction) }
        for k in keys { counts[k + 1] += 1 }
        for i in 1..<counts.count { counts[i] += counts[i - 1] }
        var fill = counts
        var sorted = [Int32](repeating: 0, count: stars.count)
        for (index, k) in keys.enumerated() {
            sorted[Int(fill[k])] = Int32(index)
            fill[k] += 1
        }
        cellStart = counts
        cellStars = sorted
    }

    public init(seed: UInt64, count: Int, sigma: Double = StarField.defaultSigma) {
        var rng = SplitMix64(seed: seed &* 0x2545_F491_4F6C_DD1D &+ 0x1234_5678)
        var stars: [Star] = []
        stars.reserveCapacity(count)
        for _ in 0..<count {
            let z = 2 * rng.nextDouble() - 1
            let phi = 2 * Double.pi * rng.nextDouble()
            let s = (1 - z * z).squareRoot()
            let temperature = 3000 * pow(10, rng.nextDouble())
            let brightness = pow(10, -2.5 * rng.nextDouble()) * StarField.peakLuminance
            let xyz = Blackbody.xyz(temperature: temperature)
            var rgb = Blackbody.linearSRGB(fromXYZ: xyz) / xyz.y  // unit luminance
            rgb = SIMD3(max(rgb.x, 0), max(rgb.y, 0), max(rgb.z, 0))
            stars.append(Star(direction: SIMD3(s * cos(phi), s * sin(phi), z), peakRadiance: brightness * rgb))
        }
        self.init(stars: stars, sigma: sigma)
    }

    private static func axisCell(_ v: Double) -> Int {
        min(max(Int((v + 1) * 0.5 * Double(cellsPerAxis)), 0), cellsPerAxis - 1)
    }

    private static func cellKey(for d: SIMD3<Double>) -> Int {
        (axisCell(d.x) * cellsPerAxis + axisCell(d.y)) * cellsPerAxis + axisCell(d.z)
    }

    @inline(__always)
    private func contribution(of star: Star, to direction: SIMD3<Double>) -> SIMD3<Double>? {
        let delta = star.direction - direction
        let chord2 = (delta * delta).sum()
        guard chord2 < cutoff * cutoff * 1.0000001 else { return nil }
        let angle = 2 * asin(min(chord2.squareRoot() * 0.5, 1))
        guard angle < cutoff else { return nil }
        return star.peakRadiance * exp(-0.5 * angle * angle / (sigma * sigma))
    }

    public func radiance(direction: SIMD3<Double>) -> SIMD3<Double> {
        var sum = background
        let cells = Self.cellsPerAxis
        let lo = SIMD3(Self.axisCell(direction.x - cutoff), Self.axisCell(direction.y - cutoff), Self.axisCell(direction.z - cutoff))
        let hi = SIMD3(Self.axisCell(direction.x + cutoff), Self.axisCell(direction.y + cutoff), Self.axisCell(direction.z + cutoff))
        for ix in lo.x...hi.x {
            for iy in lo.y...hi.y {
                for iz in lo.z...hi.z {
                    let key = (ix * cells + iy) * cells + iz
                    for slot in Int(cellStart[key])..<Int(cellStart[key + 1]) {
                        if let c = contribution(of: stars[Int(cellStars[slot])], to: direction) { sum += c }
                    }
                }
            }
        }
        return sum
    }

    /// Reference implementation summing every star; used to test the spatial grid.
    func bruteForceRadiance(direction: SIMD3<Double>) -> SIMD3<Double> {
        var sum = background
        for star in stars { if let c = contribution(of: star, to: direction) { sum += c } }
        return sum
    }
}
