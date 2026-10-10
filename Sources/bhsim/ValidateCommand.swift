import ArgumentParser
import BlackHoleKit
import Foundation

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run the built-in physics checks against independent reference values.",
        discussion: "Prints each check with its measured value, the reference and the tolerance. Exit code 0 only if every check passes, 1 otherwise."
    )

    func run() throws {
        let checks = ValidationSuite.run()
        let nameWidth = checks.map(\.name.count).max() ?? 0
        print("\("check".padding(toLength: nameWidth, withPad: " ", startingAt: 0))  \("measured".padding(toLength: 16, withPad: " ", startingAt: 0))  \("reference".padding(toLength: 16, withPad: " ", startingAt: 0))  tolerance      result")
        for c in checks {
            let tolerance: String
            switch c.tolerance {
            case .relative(let t): tolerance = String(format: "rel %.0e", t)
            case .absolute(let t): tolerance = String(format: "abs %.0e", t)
            }
            print("\(c.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0))  \(String(format: "%-16.10g", c.measured))  \(String(format: "%-16.10g", c.reference))  \(tolerance.padding(toLength: 12, withPad: " ", startingAt: 0))  \(c.passed ? "PASS" : "FAIL")")
        }
        let failed = checks.filter { !$0.passed }
        print("\n\(checks.count - failed.count)/\(checks.count) checks passed")
        if !failed.isEmpty { throw ExitCode(1) }
    }
}
