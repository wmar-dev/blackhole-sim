import Foundation
import simd
import Testing
@testable import BlackHoleKit

/// Synthetic sky (FR-005): seeded star field and reference grid.
@Suite struct SkyTests {
    private func sphericalDirection(thetaDegrees: Double, phiDegrees: Double) -> SIMD3<Double> {
        let t = thetaDegrees * Double.pi / 180, p = phiDegrees * Double.pi / 180
        return SIMD3(sin(t) * cos(p), sin(t) * sin(p), cos(t))
    }

    // MARK: Star field

    @Test func sameSeedGivesTheSameSkyAndDifferentSeedsDiffer() {
        let a = StarField(seed: 7, count: 2000)
        let b = StarField(seed: 7, count: 2000)
        let c = StarField(seed: 8, count: 2000)
        #expect(a.stars == b.stars)
        #expect(a.stars != c.stars)
        var different = 0
        for star in a.stars.prefix(50) {
            #expect(a.radiance(direction: star.direction) == b.radiance(direction: star.direction))
            if a.radiance(direction: star.direction) != c.radiance(direction: star.direction) { different += 1 }
        }
        #expect(different > 40)
    }

    @Test func starPositionsAreUniformOnTheSphere() {
        let field = StarField(seed: 3, count: 100_000)
        // Equal-area bins: cos θ uniform in [−1, 1] and φ uniform in [0, 2π).
        let bins = 20
        var byZ = [Int](repeating: 0, count: bins)
        var byPhi = [Int](repeating: 0, count: bins)
        for star in field.stars {
            let z = star.direction.z
            byZ[min(bins - 1, Int((z + 1) / 2 * Double(bins)))] += 1
            var phi = atan2(star.direction.y, star.direction.x)
            if phi < 0 { phi += 2 * Double.pi }
            byPhi[min(bins - 1, Int(phi / (2 * Double.pi) * Double(bins)))] += 1
        }
        let expected = Double(field.stars.count) / Double(bins)
        func chiSquared(_ counts: [Int]) -> Double { counts.reduce(0) { $0 + pow(Double($1) - expected, 2) / expected } }
        // 19 degrees of freedom: χ² < 43.8 at p = 0.001.
        #expect(chiSquared(byZ) < 43.8, "cos θ bins \(byZ)")
        #expect(chiSquared(byPhi) < 43.8, "φ bins \(byPhi)")
        for star in field.stars.prefix(1000) {
            let d = star.direction
            #expect(abs(d.x * d.x + d.y * d.y + d.z * d.z - 1) < 1e-12)
        }
    }

    @Test func starProfileIsGaussianInAngularDistance() {
        let sigma = StarField.defaultSigma
        let peak = SIMD3<Double>(0.8, 0.5, 0.2)
        let direction = SIMD3<Double>(0, 0, 1)
        let field = StarField(stars: [Star(direction: direction, peakRadiance: peak)], sigma: sigma)
        #expect(field.radiance(direction: direction) == peak + field.background)
        for k in [0.5, 1.0, 2.0, 3.0] {
            let angle = k * sigma
            let probe = SIMD3(sin(angle), 0, cos(angle))
            let expected = peak * exp(-0.5 * k * k) + field.background
            let got = field.radiance(direction: probe)
            for c in 0..<3 { #expect(abs(got[c] - expected[c]) < 1e-9 * peak.x + 1e-12, "k=\(k)") }
        }
        // Beyond the cutoff only the background remains.
        let far = SIMD3(sin(10 * sigma), 0, cos(10 * sigma))
        #expect(field.radiance(direction: far) == field.background)
    }

    @Test func spatialLookupMatchesBruteForce() {
        let field = StarField(seed: 11, count: 5000)
        var checked = 0
        for star in field.stars.prefix(300) {
            // Probe near a star, on the cutoff edge, and at random offsets (including across cell boundaries).
            for offset in [0.0, 0.3, 0.9, 2.5] {
                let delta = offset * field.sigma
                let up = abs(star.direction.z) < 0.9 ? SIMD3<Double>(0, 0, 1) : SIMD3(1, 0, 0)
                let tangent = simd_normalize(simd_cross(star.direction, up))
                let probe = simd_normalize(star.direction + delta * tangent)
                let fast = field.radiance(direction: probe)
                let slow = field.bruteForceRadiance(direction: probe)
                for c in 0..<3 { #expect(abs(fast[c] - slow[c]) <= 1e-12 * max(1, slow[c])) }
                checked += 1
            }
        }
        #expect(checked == 1200)
    }

    @Test func skyIsNeverCompletelyBlack() {
        // Background light is needed so shadow pixels (zero radiance) are distinguishable from sky.
        let field = StarField(seed: 1, count: 1000)
        for d in [SIMD3<Double>(1, 0, 0), SIMD3(0, 0, -1), simd_normalize(SIMD3<Double>(1, 2, 3))] {
            let r = field.radiance(direction: d)
            #expect(r.x > 0 && r.y > 0 && r.z > 0)
        }
    }

    // MARK: Reference grid

    @Test func gridLinesAtKnownDirections() {
        let grid = ReferenceGrid()
        #expect(grid.isOnLine(direction: sphericalDirection(thetaDegrees: 90, phiDegrees: 0)))  // equator ∩ prime meridian
        #expect(grid.isOnLine(direction: sphericalDirection(thetaDegrees: 80, phiDegrees: 33)))  // latitude line
        #expect(grid.isOnLine(direction: sphericalDirection(thetaDegrees: 47, phiDegrees: 120)))  // longitude line
        #expect(!grid.isOnLine(direction: sphericalDirection(thetaDegrees: 85, phiDegrees: 5)))  // between lines
        #expect(!grid.isOnLine(direction: sphericalDirection(thetaDegrees: 55, phiDegrees: 65)))
        // No longitude lines converge into a solid disc at the poles.
        #expect(!grid.isOnLine(direction: sphericalDirection(thetaDegrees: 3, phiDegrees: 5)))
    }

    @Test func gridLinesAreBrighterThanTheBackgroundAndTheBackgroundIsNonzero() {
        let grid = ReferenceGrid()
        let line = grid.radiance(direction: sphericalDirection(thetaDegrees: 80, phiDegrees: 33))
        let background = grid.radiance(direction: sphericalDirection(thetaDegrees: 85, phiDegrees: 5))
        #expect(line.x > background.x && line.y > background.y && line.z > background.z)
        #expect(background.x > 0 && background.y > 0 && background.z > 0)
    }

    @Test func skyFactorySelectsTheRequestedKind() {
        let grid = Sky.make(SkyConfig(kind: .grid, seed: 1, starCount: 10))
        let stars = Sky.make(SkyConfig(kind: .starfield, seed: 1, starCount: 10))
        #expect(grid is ReferenceGrid)
        #expect(stars is StarField)
    }
}
