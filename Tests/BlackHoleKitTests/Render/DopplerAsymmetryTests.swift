import Foundation
import Testing
@testable import BlackHoleKit

/// Relativistic Doppler beaming and gravitational redshift in the rendered image (User Story 3).
@Suite struct DopplerAsymmetryTests {
    /// A disk cool enough that its visible colour varies with temperature (peak a few thousand kelvin).
    static func coolDiskConfig(width: Int = 240, height: Int = 135) -> RenderConfig {
        var c = RenderConfig()
        c.blackHole = BlackHole(spin: 0, massSolar: 1e9)
        c.disk = AccretionDisk(outerRadius: 20, accretionRateEddington: 1e-4)
        c.observer.inclinationDegrees = 80
        c.width = width
        c.height = height
        c.samplesPerPixel = 1
        c.sky = SkyConfig(kind: .grid, seed: 1, starCount: 0)
        return c
    }

    private func luminance(_ p: SIMD3<Float>) -> Double { 0.2126 * Double(p.x) + 0.7152 * Double(p.y) + 0.0722 * Double(p.z) }

    @Test func theCoolDiskHasAVisibleColourRange() {
        let c = Self.coolDiskConfig()
        let nt = NovikovThorne(kerr: c.kerr, massSolar: c.blackHole.massSolar, eddingtonFraction: c.disk.accretionRateEddington)
        let peak = nt.peakTemperature(upTo: c.disk.outerRadius)
        #expect(peak > 3000 && peak < 30000, "peak temperature \(peak) K")
    }

    @Test func approachingSideIsBrighterAndBluerThanTheRecedingSide() throws {
        let config = Self.coolDiskConfig()
        let image = try Renderer(config: config).render()
        var left = SIMD3<Double>.zero, right = SIMD3<Double>.zero
        var nLeft = 0, nRight = 0
        for y in 0..<config.height {
            for x in 0..<config.width where image.diskFraction[y * config.width + x] > 0.5 {
                let p = SIMD3<Double>(image.hdr[y * config.width + x])
                if x < config.width / 2 { left += p; nLeft += 1 } else if x >= config.width / 2 { right += p; nRight += 1 }
            }
        }
        #expect(nLeft > 100 && nRight > 100)
        // Equal numbers of disk pixels on each side (a = 0 is left-right symmetric) so the comparison is fair.
        #expect(abs(nLeft - nRight) <= nLeft / 25, "\(nLeft) vs \(nRight) disk pixels")
        let yLeft = luminance(SIMD3<Float>(left)) / Double(nLeft), yRight = luminance(SIMD3<Float>(right)) / Double(nRight)
        #expect(yLeft > 1.2 * yRight, "approaching side (left) should be brighter: \(yLeft) vs \(yRight)")
        let blueToRedLeft = left.z / left.x, blueToRedRight = right.z / right.x
        #expect(blueToRedLeft > blueToRedRight, "approaching side should be bluer: \(blueToRedLeft) vs \(blueToRedRight)")
    }

    @Test func emissionNearTheIscoIsDimmedAndReddenedRelativeToUnshiftedEmission() throws {
        // Seen almost face-on, only gravitational redshift and transverse Doppler act: g = √(1 − 3/r)/√(1 − 2/r_o) < 1.
        var config = Self.coolDiskConfig(width: 400, height: 400)
        config.observer.inclinationDegrees = 0.5
        config.observer.fieldOfViewDegrees = 20
        let renderer = try Renderer(config: config)
        let nt = NovikovThorne(kerr: config.kerr, massSolar: config.blackHole.massSolar, eddingtonFraction: config.disk.accretionRateEddington)
        let isco = config.kerr.iscoRadius
        // Walk outward along the image's horizontal midline to find a disk pixel at about 1.3 r_isco.
        var found: (ray: CameraRay, radius: Double)?
        let camera = Camera(kerr: config.kerr, observer: config.observer, width: config.width, height: config.height)
        for x in stride(from: 200.5, to: 400, by: 0.25) {
            let ray = camera.ray(pixelX: x, pixelY: 200.5)
            let result = RayTracer(config: config).trace(ray)
            if case .disk(let r, _, _) = result.outcome, r > 1.28 * isco, r < 1.35 * isco { found = (ray, r); break }
        }
        let hit = try #require(found, "no disk pixel near 1.3 r_isco")
        let result = RayTracer(config: config).trace(hit.ray)
        let observed = try #require(renderer.radiance(of: result, ray: hit.ray))
        let temperature = nt.temperature(r: hit.radius)
        let reference = nt.referenceLuminance(upTo: config.disk.outerRadius)
        var unshifted = Blackbody.linearSRGB(temperature: temperature) / reference
        unshifted = SIMD3(max(unshifted.x, 0), max(unshifted.y, 0), max(unshifted.z, 0))

        func lum(_ v: SIMD3<Double>) -> Double { 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z }
        #expect(lum(observed) < 0.8 * lum(unshifted), "emission near the ISCO must be dimmed")
        #expect(observed.x / observed.z > unshifted.x / unshifted.z, "and reddened")

        // The shift factor of this ray matches the face-on closed form.
        let obsMetric = config.kerr.metric(r: config.observer.distance, mu: config.observer.mu)
        let g = ShiftFactor.g(kerr: config.kerr, radius: hit.radius, angularMomentum: hit.ray.constants.angularMomentum,
                              observerEnergy: hit.ray.observerEnergy)
        _ = obsMetric
        let faceOn = (1 - 3 / hit.radius).squareRoot() / (1 - 2 / config.observer.distance).squareRoot()
        // The ray's small angular momentum L (from the 0.5° inclination) shifts g by ΩL ≈ a few 10⁻³.
        #expect(approxEqual(g, faceOn, relative: 6e-3), "g=\(g) vs face-on \(faceOn)")
        #expect(g < 1)
    }

    @Test func renderedDiskRadianceIsABlackbodyAtTheShiftedTemperature() throws {
        let config = Self.coolDiskConfig()
        let renderer = try Renderer(config: config)
        let nt = NovikovThorne(kerr: config.kerr, massSolar: config.blackHole.massSolar, eddingtonFraction: config.disk.accretionRateEddington)
        let reference = nt.referenceLuminance(upTo: config.disk.outerRadius)
        let camera = Camera(kerr: config.kerr, observer: config.observer, width: config.width, height: config.height)
        let tracer = RayTracer(config: config)
        var checked = 0
        for x in stride(from: 5.5, to: Double(config.width), by: 17) {
            for y in stride(from: 40.5, to: 100, by: 7) {
                let ray = camera.ray(pixelX: x, pixelY: y)
                let result = tracer.trace(ray)
                guard case .disk(let r, _, _) = result.outcome else { continue }
                let g = ShiftFactor.g(kerr: config.kerr, radius: r, angularMomentum: ray.constants.angularMomentum, observerEnergy: ray.observerEnergy)
                var expected = Blackbody.linearSRGB(temperature: g * nt.temperature(r: r)) / reference
                expected = SIMD3(max(expected.x, 0), max(expected.y, 0), max(expected.z, 0))
                let got = try #require(renderer.radiance(of: result, ray: ray))
                for c in 0..<3 { #expect(abs(got[c] - expected[c]) <= 1e-12 * max(1, expected[c]), "pixel (\(x),\(y)) channel \(c)") }
                checked += 1
            }
        }
        #expect(checked > 20)
    }

    @Test func imageMetadataRecordsPhysicalShadingAndTheReferenceRadiance() throws {
        let config = Self.coolDiskConfig(width: 32, height: 18)
        let image = try Renderer(config: config).render()
        #expect(image.shading == .physical)
        let reference = try #require(image.referenceRadiance)
        #expect(reference > 0 && reference.isFinite)
        let nt = NovikovThorne(kerr: config.kerr, massSolar: config.blackHole.massSolar, eddingtonFraction: config.disk.accretionRateEddington)
        #expect(approxEqual(reference, nt.referenceLuminance(upTo: config.disk.outerRadius), relative: 1e-12))
    }
}
