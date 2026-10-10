import Foundation

/// Runs the built `bhsim` executable for command-line tests.
enum CLIRunner {
    struct Result {
        var status: Int32
        var stdout: String
        var stderr: String
        var seconds: Double
    }

    /// The built `bhsim` next to the test products, if it exists. The resource bundle may sit inside the `.xctest`
    /// bundle or beside it; walk up until `bhsim` is found.
    static var bhsim: URL? {
        var directory = Bundle.module.bundleURL
        for _ in 0..<6 {
            directory = directory.deletingLastPathComponent()
            let candidate = directory.appendingPathComponent("bhsim")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static func run(_ arguments: [String], environment: [String: String] = [:]) throws -> Result {
        guard let url = bhsim else { throw RunnerError.notBuilt }
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        for (k, v) in environment { env[k] = v }
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let start = ContinuousClock.now
        try process.run()
        process.waitUntilExit()
        let elapsed = ContinuousClock.now - start
        return Result(status: process.terminationStatus,
                      stdout: String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                      stderr: String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                      seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18)
    }

    enum RunnerError: Error { case notBuilt }
}
