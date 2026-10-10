import ArgumentParser
import BlackHoleKit
import Foundation

@main
struct Bhsim: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bhsim",
        abstract: "Physically accurate images of a Kerr black hole by backward null-geodesic tracing.",
        version: BlackHoleKit.version,
        subcommands: [Render.self, Validate.self, Compare.self, Movie.self]
    )

    /// Runs the command like the default `main`, except that command-line usage errors (unknown option,
    /// unparsable value) exit with 2, the same code as invalid values, as documented in contracts/cli.md.
    static func main() {
        do {
            var command = try parseAsRoot(nil)
            try command.run()
        } catch {
            if exitCode(for: error) == .validationFailure {
                FileHandle.standardError.write(Data((fullMessage(for: error) + "\n").utf8))
                Foundation.exit(2)
            }
            exit(withError: error)
        }
    }
}
