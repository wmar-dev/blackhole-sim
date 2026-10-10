import Foundation

/// Celestial latitude/longitude grid for validating lensing (FR-005): lines every 10°, with the equator
/// and the prime meridian (φ = 0) coloured so orientation can be read from the image.
public struct ReferenceGrid: SkyModel, Sendable {
    public static let spacingDegrees = 10.0
    /// Half-width of a line in degrees of great-circle distance.
    public static let halfWidthDegrees = 0.35
    /// Longitude lines are not drawn within this polar distance (sin θ below it), where they would merge.
    static let minimumSinTheta = 0.25

    public static let background = SIMD3<Double>(0.02, 0.02, 0.025)
    public static let lineColor = SIMD3<Double>(0.45, 0.45, 0.5)
    public static let equatorColor = SIMD3<Double>(0.2, 0.7, 0.3)
    public static let primeMeridianColor = SIMD3<Double>(0.8, 0.25, 0.2)

    public init() {}

    private enum Line { case none, ordinary, equator, primeMeridian }

    private func classify(_ d: SIMD3<Double>) -> Line {
        let spacing = Self.spacingDegrees * Double.pi / 180
        let halfWidth = Self.halfWidthDegrees * Double.pi / 180
        let theta = acos(min(max(d.z, -1), 1))
        let sinTheta = max(1 - d.z * d.z, 0).squareRoot()

        func distanceToMultiple(_ x: Double) -> Double {
            let k = (x / spacing).rounded()
            return abs(x - k * spacing)
        }

        let latitudeDistance = distanceToMultiple(theta)
        if abs(theta - Double.pi / 2) < halfWidth { return .equator }
        var longitudeLine = Line.none
        if sinTheta > Self.minimumSinTheta {
            var phi = atan2(d.y, d.x)
            if phi < 0 { phi += 2 * Double.pi }
            let wrapped = min(phi, 2 * Double.pi - phi)  // distance to the prime meridian
            if wrapped * sinTheta < halfWidth { return .primeMeridian }
            if distanceToMultiple(phi) * sinTheta < halfWidth { longitudeLine = .ordinary }
        }
        if latitudeDistance < halfWidth { return .ordinary }
        return longitudeLine
    }

    /// True if `direction` lies on a drawn line.
    public func isOnLine(direction: SIMD3<Double>) -> Bool {
        if case .none = classify(direction) { return false }
        return true
    }

    public func radiance(direction: SIMD3<Double>) -> SIMD3<Double> {
        switch classify(direction) {
        case .none: return Self.background
        case .ordinary: return Self.lineColor
        case .equator: return Self.equatorColor
        case .primeMeridian: return Self.primeMeridianColor
        }
    }
}
