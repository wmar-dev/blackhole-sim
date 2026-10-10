import Foundation
import Testing
import simd
@testable import BlackHoleKit

/// A sky that is dim everywhere except a bright disc exactly behind the black hole, as seen by the observer.
struct AntipodeSpotSky: SkyModel {
    let center: SIMD3<Double>
    let angularRadius: Double
    func radiance(direction: SIMD3<Double>) -> SIMD3<Double> {
        let angle = acos(min(max(simd_dot(direction, center), -1), 1))
        return angle < angularRadius ? SIMD3(1, 1, 1) : SIMD3(0.02, 0.02, 0.02)
    }
}

/// Visible lensing features (User Story 1 acceptance scenarios).
@Suite struct RenderFeaturesTests {
    @Test func inclinedDiskShowsPrimaryAndHigherOrderImagesAroundTheShadow() throws {
        var config = RenderConfig()
        config.blackHole.spin = 0
        config.observer.inclinationDegrees = 80
        config.width = 240
        config.height = 135
        config.samplesPerPixel = 1
        config.sky = SkyConfig(kind: .grid, seed: 1, starCount: 0)
        let image = try Renderer(config: config).render()
        let outline = ShadowOutline(image: image, fieldOfViewDegrees: config.observer.fieldOfViewDegrees)
        let radius = outline.equivalentRadiusPixels
        #expect(radius > 5)
        let xc = config.width / 2, yc = config.height / 2

        func diskPixels(rows: Range<Int>, columns: Range<Int>) -> Int {
            var n = 0
            for y in rows { for x in columns where image.diskFraction[y * config.width + x] > 0.5 { n += 1 } }
            return n
        }
        let band = (xc - 3)..<(xc + 4)
        // The far side of the disk, lensed over the top of the shadow, and the near side in front of it.
        #expect(diskPixels(rows: 0..<max(1, yc - Int(0.8 * radius)), columns: band) > 0, "no disk image above the shadow")
        #expect(diskPixels(rows: (yc + Int(0.2 * radius))..<config.height, columns: band) > 0, "no disk image below the shadow centre")
        // Secondary images (rays that crossed the plane without hitting the disk, then met its far face).
        var higherOrder = 0
        for p in image.higherOrderFraction where p > 0.5 { higherOrder += 1 }
        #expect(higherOrder > 0, "no secondary/tertiary disk image")
        #expect(image.diagnostics.disk > 0 && image.diagnostics.captured > 0 && image.diagnostics.sky > 0)
    }

    @Test func aSourceExactlyBehindTheHoleIsImagedAsAnEinsteinRing() throws {
        let fixture: DeflectionFixture = try Fixture.load("schwarzschild_deflection")
        var config = RenderConfig()
        config.blackHole.spin = 0
        config.observer.distance = fixture.einstein_ring.r_observer
        config.observer.inclinationDegrees = 80
        config.observer.fieldOfViewDegrees = 30
        config.disk.outerRadius = 7  // keep the disk away from the ring
        config.width = 300
        config.height = 300
        config.samplesPerPixel = 1
        let theta = 80.0 * Double.pi / 180
        let towardObserver = SIMD3(sin(theta), 0, cos(theta))
        let sky = AntipodeSpotSky(center: -towardObserver, angularRadius: 0.03)
        let image = try Renderer(config: config, sky: sky).render()

        let centre = SIMD2(Double(config.width) / 2, Double(config.height) / 2)
        var radii: [Double] = []
        var bins = Set<Int>()
        for y in 0..<config.height {
            for x in 0..<config.width where image.hdr[y * config.width + x].x > 0.5 && image.diskFraction[y * config.width + x] == 0 {
                let d = SIMD2(Double(x) + 0.5, Double(y) + 0.5) - centre
                radii.append(simd_length(d))
                var a = atan2(d.y, d.x)
                if a < 0 { a += 2 * Double.pi }
                bins.insert(Int(a / (2 * Double.pi) * 36))
            }
        }
        #expect(radii.count > 100, "ring not found: \(radii.count) bright pixels")
        let meanRadius = radii.reduce(0, +) / Double(radii.count)
        let outline = ShadowOutline(image: image, fieldOfViewDegrees: config.observer.fieldOfViewDegrees)
        let measured = outline.angle(forPixelOffset: meanRadius)
        #expect(approxEqual(measured, fixture.einstein_ring.local_angle, relative: 0.02),
                "ring at \(measured) rad vs expected \(fixture.einstein_ring.local_angle) rad")
        #expect(bins.count == 36, "the ring has gaps: only \(bins.count)/36 azimuth bins are lit")
        // A thin ring: most bright pixels lie within 15% of the mean radius.
        let near = radii.filter { abs($0 - meanRadius) < 0.15 * meanRadius }.count
        #expect(Double(near) / Double(radii.count) > 0.95)
    }

    @Test func observerNearTheSpinAxisProducesNoNonFinitePixels() throws {
        for spin in [0.0, 0.9] {
            for inclination in [0.01, 179.99] {
                var config = RenderConfig()
                config.blackHole.spin = spin
                config.observer.inclinationDegrees = inclination
                config.width = 32
                config.height = 18
                config.samplesPerPixel = 1
                config.sky = SkyConfig(kind: .starfield, seed: 1, starCount: 2000)
                let image = try Renderer(config: config).render()
                for p in image.hdr {
                    #expect(p.x.isFinite && p.y.isFinite && p.z.isFinite && p.x >= 0 && p.y >= 0 && p.z >= 0, "a=\(spin) i=\(inclination)")
                }
                #expect(image.diagnostics.unresolved == 0, "a=\(spin) i=\(inclination): \(image.diagnostics.unresolved) unresolved")
            }
        }
    }
}
