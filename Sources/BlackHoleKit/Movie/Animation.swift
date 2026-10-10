import Foundation

/// The viewing parameter an animation changes (research D3). Each is a physically valid input of a single render.
public enum SweepParameter: String, CaseIterable, Sendable, Codable {
    case inclination  // degrees from the spin axis
    case distance     // observer radius in M
    case spin         // dimensionless a/M

    func apply(_ value: Double, to config: inout RenderConfig) {
        switch self {
        case .inclination: config.observer.inclinationDegrees = value
        case .distance: config.observer.distance = value
        case .spin: config.blackHole.spin = value
        }
    }
}

/// A request to render a frame sequence by varying one parameter linearly (data-model.md).
///
/// Every frame is a complete render of a stationary, axisymmetric black hole and disk seen by a static observer at that
/// parameter value: the sequence describes a changing viewpoint or parameter, not time evolution (FR-015). Nothing is
/// interpolated between frames.
public struct Animation: Sendable {
    public var parameter: SweepParameter
    public var from: Double
    public var to: Double
    /// Movie length in seconds.
    public var duration: Double
    public var fps: Double
    /// The settings shared by all frames.
    public var base: RenderConfig

    public init(parameter: SweepParameter, from: Double, to: Double, duration: Double, fps: Double, base: RenderConfig) {
        self.parameter = parameter; self.from = from; self.to = to
        self.duration = duration; self.fps = fps; self.base = base
        referenceRadiance = Animation.commonReference(parameter: parameter, from: from, to: to, count: Animation.count(duration: duration, fps: fps), base: base)
    }

    private static func count(duration: Double, fps: Double) -> Int {
        let frames = duration * fps
        guard frames.isFinite, frames < 1e7 else { return 1 }
        return max(1, Int(frames.rounded()))
    }

    /// N = round(duration × fps), at least 1.
    public var frameCount: Int { Animation.count(duration: duration, fps: fps) }

    /// The swept value of frame `i` (0-based): from + (to − from)·i/(N − 1); the first and last frames are exactly
    /// `from` and `to`, and a one-frame animation is `from`.
    public func value(at i: Int) -> Double {
        let n = frameCount
        guard n > 1 else { return from }
        if i >= n - 1 { return to }
        return from + (to - from) * Double(i) / Double(n - 1)
    }

    /// The common exposure reference of the movie (research D5): the largest per-frame reference over the sweep. It is the
    /// same for every frame, so brightness changes between frames are physical. For inclination and distance sweeps it
    /// equals the reference of a single render of the base configuration.
    public let referenceRadiance: Double

    private static func commonReference(parameter: SweepParameter, from: Double, to: Double, count: Int, base: RenderConfig) -> Double {
        func reference(_ config: RenderConfig) -> Double? {
            guard (try? config.validate()) != nil else { return nil }
            let disk = NovikovThorne(kerr: config.kerr, massSolar: config.blackHole.massSolar, eddingtonFraction: config.disk.accretionRateEddington)
            return disk.referenceLuminance(upTo: config.disk.outerRadius)
        }
        var probe = base
        probe.referenceRadianceOverride = nil
        if parameter != .spin { return reference(probe) ?? 1 }
        // The reference depends on the spin only through r_isco: take the largest over the frames that are valid renders.
        var best: Double?
        for i in 0..<count {
            let value = count > 1 ? (i >= count - 1 ? to : from + (to - from) * Double(i) / Double(count - 1)) : from
            parameter.apply(value, to: &probe)
            if let r = reference(probe) { best = max(best ?? r, r) }
        }
        return best ?? 1
    }

    /// The configuration of frame `i` (0-based): the base with the swept value and the common reference.
    public func frameConfig(_ i: Int) -> RenderConfig {
        var config = base
        parameter.apply(value(at: i), to: &config)
        config.referenceRadianceOverride = referenceRadiance
        return config
    }

    /// Checks the timing and every frame's configuration before anything is rendered (FR-008). The first invalid frame is
    /// reported with its number, its value and the reason a single render of it would give.
    public func validate() throws {
        guard duration.isFinite, duration > 0 else {
            throw MovieError.invalidOption("--duration: the duration must be a positive number of seconds (got \(duration))")
        }
        guard MovieAssembler.fpsRange.contains(fps) else {
            throw MovieError.invalidOption("--fps: the frame rate must be between 1 and 240 (got \(fps))")
        }
        guard from.isFinite, to.isFinite else {
            throw MovieError.invalidOption("--from and --to must be finite numbers (got \(from) and \(to))")
        }
        let n = frameCount
        for i in 0..<n {
            do { try frameConfig(i).validate() } catch {
                throw MovieError.invalidAnimation(frame: i + 1, of: n, parameter: parameter.rawValue, value: value(at: i),
                                                  reason: (error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
        }
    }
}
