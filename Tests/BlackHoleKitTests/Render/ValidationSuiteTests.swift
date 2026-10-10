import Foundation
import Testing
@testable import BlackHoleKit

/// The built-in `bhsim validate` checks (FR-011).
@Suite struct ValidationSuiteTests {
    @Test func everyBuiltInCheckPasses() {
        let checks = ValidationSuite.run()
        #expect(checks.count >= 20)
        for c in checks { #expect(c.passed, "\(c.name): measured \(c.measured), reference \(c.reference), \(c.tolerance)") }
    }

    @Test func checksCoverTheRequiredPhysics() {
        let names = ValidationSuite.run().map(\.name).joined(separator: "\n").lowercased()
        for required in ["horizon", "isco", "photon sphere", "critical impact parameter", "deflection", "residual", "shadow", "flux", "shift factor", "determinism"] {
            #expect(names.contains(required), "missing check for \(required)")
        }
    }

    @Test func aBrokenMeasurementIsReportedAsAFailure() {
        #expect(!ValidationCheck(name: "x", measured: 1.0, reference: 2.0, tolerance: .relative(1e-3)).passed)
        #expect(!ValidationCheck(name: "x", measured: .nan, reference: 2.0, tolerance: .relative(1e-3)).passed)
        #expect(!ValidationCheck(name: "x", measured: 1e-3, reference: 0, tolerance: .absolute(1e-6)).passed)
        #expect(ValidationCheck(name: "x", measured: 2.0 + 1e-9, reference: 2.0, tolerance: .relative(1e-6)).passed)
    }
}
