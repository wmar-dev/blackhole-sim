import Foundation
import Testing
@testable import BlackHoleKit

/// Ctrl-C during `bhsim movie animate` (User Story 2, scenario 3; plan: interruption).
@Suite(.serialized, .enabled(if: MovieTestSupport.avfoundationCanEncode)) struct MovieInterruptTests {
    @Test func sigintStopsCleanlyKeepsFinishedFramesAndARerunCompletes() throws {
        let dir = try TempDirectory()
        let movie = dir.file("sweep.mp4")
        let arguments = ["movie", "animate", "--sweep", "inclination", "--from", "85", "--to", "30", "--duration", "6", "--fps", "10",
                         "--width", "320", "--height", "180", "--samples", "4", "--encoder", "avfoundation", "--out", movie.path]
        let url = try #require(CLIRunner.bhsim)
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let second = dir.file("sweep_frames/frame_0002.json")
        let start = Date()
        while !FileManager.default.fileExists(atPath: second.path), Date().timeIntervalSince(start) < 120, process.isRunning { Thread.sleep(forTimeInterval: 0.05) }
        try #require(process.isRunning, "the animation ended before it could be interrupted")
        kill(process.processIdentifier, SIGINT)
        let interruptedAt = Date()
        while process.isRunning, Date().timeIntervalSince(interruptedAt) < 30 { Thread.sleep(forTimeInterval: 0.05) }
        #expect(!process.isRunning, "the process did not stop after SIGINT")
        #expect(process.terminationStatus == 130, "exit status \(process.terminationStatus)")

        #expect(!FileManager.default.fileExists(atPath: movie.path), "no movie after an interruption")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.url.path)) ?? []
        #expect(!leftovers.contains { $0.hasSuffix(".partial") }, "left behind: \(leftovers)")
        let frames = try FileManager.default.contentsOfDirectory(atPath: dir.file("sweep_frames").path)
        let pngs = frames.filter { $0.hasSuffix(".png") }, jsons = frames.filter { $0.hasSuffix(".json") }
        #expect(pngs.count >= 2 && jsons.count >= 2)
        for json in jsons { #expect(frames.contains(json.replacingOccurrences(of: ".json", with: ".png"))) }
        for png in pngs where jsons.contains(png.replacingOccurrences(of: ".png", with: ".json")) {
            #expect(FrameSequence.pixelSize(of: dir.file("sweep_frames/\(png)")) != nil, "\(png) is a complete image")
        }

        let again = try CLIRunner.run(arguments)
        #expect(again.status == 0, "rerun: \(again.stderr)")
        #expect(again.stdout.contains("kept") || again.stdout.contains("skipped"), "the rerun says it kept finished frames: \(again.stdout.suffix(400))")
        #expect(FileManager.default.fileExists(atPath: movie.path))
    }
}
