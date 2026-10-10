import Foundation

extension Observer {
    /// True when a static observer can exist at this position: outside the ergosphere.
    public func isStaticObserverPossible(in kerr: Kerr) -> Bool {
        distance > kerr.ergosphereRadius(mu: mu)
    }
}
