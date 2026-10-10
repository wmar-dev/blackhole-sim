import Foundation

/// Which implementation traces the rays (spec FR-001, data-model.md).
///
/// `cpu` is the float64 reference and the default. `metal` traces on the Apple GPU in float32 and shades on the CPU.
public enum Backend: String, Sendable, CaseIterable, Equatable {
    case cpu
    case metal

    public var name: String { rawValue }

    /// Precision of the ray integration (shading is float64 for both).
    public var precision: String { self == .cpu ? "float64" : "float32" }
}

/// The record of the backend in a render's metadata.
public struct BackendInfo: Codable, Sendable, Equatable {
    public var name: String
    public var precision: String

    public init(backend: Backend) {
        name = backend.name
        precision = backend.precision
    }
}

/// The requested backend cannot be used. It is never turned into a silent fallback to the CPU (FR-008).
public enum BackendError: Error, LocalizedError, Equatable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        }
    }
}
