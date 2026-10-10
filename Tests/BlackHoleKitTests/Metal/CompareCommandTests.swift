import Foundation
import Testing
@testable import BlackHoleKit

@Suite struct CompareCommandTests {
    static let hasGPU = (try? MetalContext.make()) != nil

    @Test(.enabled(if: CompareCommandTests.hasGPU)) func quickCompareExitsZeroAndPrintsPassRows() throws {
        let run = try CLIRunner.run(["compare", "--quick"])
        #expect(run.status == 0, "stderr: \(run.stderr)")
        #expect(run.stdout.components(separatedBy: "PASS").count - 1 >= 6, "five PASS rows and the overall line")
        #expect(run.stdout.contains("PASS: all 5 scenes"))
    }

    @Test func noGPUExitsFive() throws {
        let run = try CLIRunner.run(["compare", "--quick"], environment: ["BHSIM_FORCE_NO_GPU": "1"])
        #expect(run.status == 5)
        #expect(run.stderr.contains("error: --backend:"))
    }

    @Test func unknownOptionExitsTwo() throws {
        #expect(try CLIRunner.run(["compare", "--bogus"]).status == 2)
    }
}
