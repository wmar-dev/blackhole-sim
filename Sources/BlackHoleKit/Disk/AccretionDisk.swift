import Foundation

/// Geometry of the thin equatorial disk (research.md D5): the annulus from the innermost stable circular
/// orbit to the outer radius, rotating prograde on circular geodesics.
public struct DiskGeometry: Sendable, Equatable {
    public let innerRadius: Double
    public let outerRadius: Double

    public init(innerRadius: Double, outerRadius: Double) {
        precondition(outerRadius > innerRadius, "outer radius must exceed the inner radius")
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
    }

    /// The Novikov–Thorne disk: inner edge at r_isco of `kerr`.
    public init(kerr: Kerr, outerRadius: Double) {
        self.init(innerRadius: kerr.iscoRadius, outerRadius: outerRadius)
    }

    public func contains(radius: Double) -> Bool {
        radius >= innerRadius && radius <= outerRadius
    }
}
