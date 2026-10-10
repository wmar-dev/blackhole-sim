import Foundation
@testable import BlackHoleKit

/// Shadow measurement from a rendered image. The shadow is the set of samples that fell into the horizon;
/// each pixel carries the fraction of its samples that did (`capturedFraction`), so edges are measured with
/// sub-pixel accuracy from the partially covered pixels.
struct ShadowOutline {
    let width: Int
    let height: Int
    let coverage: [Float]
    let fieldOfViewDegrees: Double

    init(image: RenderedImage, fieldOfViewDegrees: Double) {
        width = image.width
        height = image.height
        coverage = image.capturedFraction
        self.fieldOfViewDegrees = fieldOfViewDegrees
    }

    /// Shadow area in pixels (sum of coverage).
    var areaPixels: Double { coverage.reduce(0.0) { $0 + Double($1) } }

    /// Number of pixels completely inside the shadow.
    var area: Int { coverage.reduce(0) { $0 + ($1 >= 0.9999 ? 1 : 0) } }

    /// Coverage-weighted centroid in pixel coordinates (pixel centres at half-integers).
    var centroid: SIMD2<Double> {
        var sum = SIMD2<Double>(0, 0)
        var n = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let f = Double(coverage[y * width + x])
                sum += f * SIMD2(Double(x) + 0.5, Double(y) + 0.5)
                n += f
            }
        }
        return n > 0 ? sum / n : SIMD2(0, 0)
    }

    /// Radius of the circle with the same area, in pixels.
    var equivalentRadiusPixels: Double { (areaPixels / Double.pi).squareRoot() }

    /// Converts a radial offset in pixels from the image centre to an angle from the optical axis.
    func angle(forPixelOffset p: Double) -> Double {
        atan(p * 2 * tan(fieldOfViewDegrees * Double.pi / 360) / Double(width))
    }

    /// Angular radius of the shadow (from the equal-area circle).
    var angularRadius: Double { angle(forPixelOffset: equivalentRadiusPixels) }

    /// Distance in pixels from `center` along image direction `theta` (radians, image coordinates with y down) to
    /// the shadow edge: the coverage integrated along the line until the first uncovered pixel.
    func edgeDistance(from center: SIMD2<Double>, direction theta: Double) -> Double {
        var d = 0.0
        var covered = 0.0
        let step = 0.25
        while true {
            let x = Int((center.x + d * cos(theta)).rounded(.down)), y = Int((center.y + d * sin(theta)).rounded(.down))
            if x < 0 || y < 0 || x >= width || y >= height { return covered }
            let f = Double(coverage[y * width + x])
            if f == 0 { return covered }
            covered += f * step
            d += step
        }
    }

    /// Tangent-plane radial distance ρ (units of tan(angle) from the optical axis) from the image centre to the
    /// shadow edge along each image-plane direction `angles` (radians, counter-clockwise from image right, y up).
    func outlineSamples(angles: [Double]) -> [Double] {
        let center = SIMD2(Double(width) / 2, Double(height) / 2)
        let tangentPerPixel = 2 * tan(fieldOfViewDegrees * Double.pi / 360) / Double(width)
        return angles.map { phi in
            edgeDistance(from: center, direction: -phi) * tangentPerPixel  // image y points down
        }
    }
}
