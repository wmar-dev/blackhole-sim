import Foundation
import Testing
@testable import BlackHoleKit

/// `bhsim movie ...` through the built executable.
@Suite(.serialized) struct MovieCommandTests {
    private func frames(_ count: Int = 12, width: Int = 64, height: Int = 48) throws -> TempDirectory {
        let dir = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(count), width: width, height: height, directory: dir.file("frames"))
        return dir
    }

    @Test func assembleSucceedsAndPrintsTheSummary() async throws {
        let dir = try frames(24)
        let out = dir.file("m.mp4").path
        let run = try CLIRunner.run(["movie", "assemble", "--frames", dir.file("frames").path, "--out", out, "--encoder", "avfoundation", "--fps", "24"])
        #expect(run.status == 0, "stderr: \(run.stderr)")
        #expect(run.stdout.contains(out) && run.stdout.contains("24 frames") && run.stdout.contains("64x48") && run.stdout.contains("24 fps"))
        #expect(run.stdout.contains("avfoundation"))
        let reader = try await MovieReader.open(URL(fileURLWithPath: out))
        #expect(reader.frameCount == 24)
    }

    @Test(.enabled(if: MovieTestSupport.ffmpegAvailable)) func assembleWithFFmpegIsReproducible() throws {
        let dir = try frames(12)
        let a = dir.file("a.mp4").path, b = dir.file("b.mp4").path
        for out in [a, b] {
            let run = try CLIRunner.run(["movie", "assemble", "--frames", dir.file("frames").path, "--out", out, "--encoder", "ffmpeg"])
            #expect(run.status == 0, "stderr: \(run.stderr)")
            #expect(run.stdout.contains("ffmpeg"))
        }
        #expect(try Data(contentsOf: URL(fileURLWithPath: a)) == Data(contentsOf: URL(fileURLWithPath: b)))
    }

    @Test func invalidFramesExitTwoWithAMessageNamingTheProblem() throws {
        let missing = try CLIRunner.run(["movie", "assemble", "--frames", "/nonexistent/frames-xyz", "--out", "/tmp/never.mp4"])
        #expect(missing.status == 2 && missing.stderr.contains("/nonexistent/frames-xyz"), "\(missing.stderr)")

        let gap = try frames(10)
        try FileManager.default.removeItem(at: gap.file("frames/frame_0005.png"))
        let gapRun = try CLIRunner.run(["movie", "assemble", "--frames", gap.file("frames").path, "--out", gap.file("m.mp4").path, "--encoder", "avfoundation"])
        #expect(gapRun.status == 2 && gapRun.stderr.contains("5"), "\(gapRun.stderr)")
        let allowed = try CLIRunner.run(["movie", "assemble", "--frames", gap.file("frames").path, "--out", gap.file("m.mp4").path, "--encoder", "avfoundation", "--allow-gaps"])
        #expect(allowed.status == 0, "\(allowed.stderr)")

        let odd = try frames(3, width: 63, height: 48)
        let oddRun = try CLIRunner.run(["movie", "assemble", "--frames", odd.file("frames").path, "--out", odd.file("m.mp4").path])
        #expect(oddRun.status == 2 && oddRun.stderr.contains("even"), "\(oddRun.stderr)")

        let mixed = try frames(3)
        try MovieTestSupport.writeFlatFrames([(9, 9, 9)], width: 80, height: 48, directory: mixed.file("frames"), firstNumber: 2)
        let mixedRun = try CLIRunner.run(["movie", "assemble", "--frames", mixed.file("frames").path, "--out", mixed.file("m.mp4").path])
        #expect(mixedRun.status == 2 && mixedRun.stderr.contains("frame_0002.png"), "\(mixedRun.stderr)")
    }

    @Test func anExistingOutputExitsTwoUnlessForced() throws {
        let dir = try frames(4)
        let out = dir.file("m.mp4").path
        let args = ["movie", "assemble", "--frames", dir.file("frames").path, "--out", out, "--encoder", "avfoundation"]
        #expect(try CLIRunner.run(args).status == 0)
        let again = try CLIRunner.run(args)
        #expect(again.status == 2 && again.stderr.contains("--force"), "\(again.stderr)")
        #expect(try CLIRunner.run(args + ["--force"]).status == 0)
    }

    @Test func aMissingFFmpegWhenRequiredExitsSixWithNoMovieAndNoFallback() throws {
        let dir = try frames(4)
        let out = dir.file("m.mp4").path
        let run = try CLIRunner.run(["movie", "assemble", "--frames", dir.file("frames").path, "--out", out, "--encoder", "ffmpeg", "--ffmpeg", "/nonexistent/ffmpeg"])
        #expect(run.status == 6, "stderr: \(run.stderr)")
        #expect(run.stderr.contains("/nonexistent/ffmpeg"))
        #expect(!FileManager.default.fileExists(atPath: out))
    }

    @Test func badOptionValuesAndUnknownOptionsExitTwo() throws {
        let dir = try frames(4)
        let base = ["movie", "assemble", "--frames", dir.file("frames").path, "--out", dir.file("m.mp4").path, "--encoder", "avfoundation"]
        #expect(try CLIRunner.run(base + ["--fps", "0"]).status == 2)
        #expect(try CLIRunner.run(base + ["--fps", "241"]).status == 2)
        #expect(try CLIRunner.run(base + ["--bogus"]).status == 2)
        #expect(try CLIRunner.run(base + ["--quality", "ultra"]).status == 2)
        #expect(try CLIRunner.run(["movie", "assemble", "--out", "x.mp4"]).status == 2, "--frames is required")
    }

    @Test func theFrameFilesAreUntouched() throws {
        let dir = try frames(6)
        let files = try FileManager.default.contentsOfDirectory(at: dir.file("frames"), includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
        let before = try files.map { try Data(contentsOf: $0) }
        _ = try CLIRunner.run(["movie", "assemble", "--frames", dir.file("frames").path, "--out", dir.file("m.mp4").path, "--encoder", "avfoundation"])
        #expect(try files.map { try Data(contentsOf: $0) } == before)
    }

    // MARK: animate

    private func animateArguments(_ dir: TempDirectory, extra: [String] = []) -> [String] {
        ["movie", "animate", "--sweep", "inclination", "--from", "85", "--to", "60", "--duration", "1", "--fps", "8",
         "--width", "64", "--height", "36", "--encoder", "avfoundation", "--out", dir.file("a.mp4").path] + extra
    }

    @Test func animateRendersAssemblesAndReports() async throws {
        let dir = try TempDirectory()
        let run = try CLIRunner.run(animateArguments(dir, extra: ["--samples", "1"]))
        #expect(run.status == 0, "stderr: \(run.stderr)")
        #expect(run.stdout.contains("frame 8/8") && run.stdout.contains("8 frames") && run.stdout.contains("64x36"), "\(run.stdout.suffix(500))")
        #expect(run.stdout.lowercased().contains("disk space"), "the disk estimate is printed before rendering")
        let reader = try await MovieReader.open(dir.file("a.mp4"))
        #expect(reader.frameCount == 8)
        #expect(FileManager.default.fileExists(atPath: dir.file("a_frames/frame_0008.png").path))
        #expect(FileManager.default.fileExists(atPath: dir.file("a.mp4.json").path))
    }

    @Test func animateDefaultsToNineSamplesPerPixelAndHonoursAnOverride() throws {
        let dir = try TempDirectory()
        #expect(try CLIRunner.run(animateArguments(dir, extra: ["--duration", "0.125"])).status == 0)
        let nine = try JSONDecoder().decode(FrameRecord.self, from: Data(contentsOf: dir.file("a_frames/frame_0001.json")))
        #expect(nine.metadata.image.samplesPerPixel == 9)
        let other = try TempDirectory()
        #expect(try CLIRunner.run(animateArguments(other, extra: ["--duration", "0.125", "--samples", "4"])).status == 0)
        let four = try JSONDecoder().decode(FrameRecord.self, from: Data(contentsOf: other.file("a_frames/frame_0001.json")))
        #expect(four.metadata.image.samplesPerPixel == 4)
    }

    @Test func anInvalidSweepIsRejectedQuicklyBeforeAnyRendering() throws {
        let dir = try TempDirectory()
        let start = Date()
        let run = try CLIRunner.run(["movie", "animate", "--sweep", "distance", "--from", "100", "--to", "1.2", "--duration", "2",
                                     "--out", dir.file("bad.mp4").path])
        #expect(run.status == 2, "\(run.stderr)")
        #expect(Date().timeIntervalSince(start) < 2.5, "took \(Date().timeIntervalSince(start)) s")
        #expect(run.stderr.contains("frame") && run.stderr.contains("--distance"), "\(run.stderr)")
        #expect(!FileManager.default.fileExists(atPath: dir.file("bad_frames").path))
        #expect(!FileManager.default.fileExists(atPath: dir.file("bad.mp4").path))
    }

    @Test func animateExitCodesForBackendOutputsEncoderAndInput() throws {
        // the GPU is unavailable
        let a = try TempDirectory()
        let noGPU = try CLIRunner.run(animateArguments(a, extra: ["--samples", "1", "--backend", "metal"]), environment: ["BHSIM_FORCE_NO_GPU": "1"])
        #expect(noGPU.status == 5, "\(noGPU.stderr)")
        #expect(!FileManager.default.fileExists(atPath: a.file("a_frames").path) && !FileManager.default.fileExists(atPath: a.file("a.mp4").path))

        // an existing output, before any rendering
        let b = try TempDirectory()
        try Data("precious".utf8).write(to: b.file("a.mp4"))
        let exists = try CLIRunner.run(animateArguments(b, extra: ["--samples", "1"]))
        #expect(exists.status == 2 && exists.stderr.contains("--force"), "\(exists.stderr)")
        #expect(!FileManager.default.fileExists(atPath: b.file("a_frames").path))

        // a requested encoder that is not there fails before rendering
        let c = try TempDirectory()
        let noEncoder = try CLIRunner.run(animateArguments(c, extra: ["--samples", "1", "--encoder", "ffmpeg", "--ffmpeg", "/nonexistent/ffmpeg"]))
        #expect(noEncoder.status == 6, "\(noEncoder.stderr)")
        #expect(!FileManager.default.fileExists(atPath: c.file("a_frames").path), "failing fast: nothing was rendered")

        // an encoder that starts and then fails: exit 6 and the frames are kept
        let fake = try MovieTestSupport.fakeFailingFFmpeg()
        let d = try TempDirectory()
        let failing = try CLIRunner.run(animateArguments(d, extra: ["--samples", "1", "--encoder", "ffmpeg", "--ffmpeg", fake.file("ffmpeg").path]))
        #expect(failing.status == 6 && failing.stderr.contains("boom"), "\(failing.stderr)")
        #expect(FileManager.default.fileExists(atPath: d.file("a_frames/frame_0008.png").path), "frames are kept")
        #expect(!FileManager.default.fileExists(atPath: d.file("a.mp4").path))

        // too many unresolved rays: exit 4, with the movie still written
        let e = try TempDirectory()
        let unresolved = try CLIRunner.run(animateArguments(e, extra: ["--samples", "1", "--max-steps", "5"]))
        #expect(unresolved.status == 4, "\(unresolved.stderr)")
        #expect(FileManager.default.fileExists(atPath: e.file("a.mp4").path))

        // missing required options and bad values
        let f = try TempDirectory()
        #expect(try CLIRunner.run(["movie", "animate", "--sweep", "inclination", "--from", "85", "--out", f.file("x.mp4").path]).status == 2)
        #expect(try CLIRunner.run(["movie", "animate", "--sweep", "azimuth", "--from", "1", "--to", "2", "--duration", "1", "--out", f.file("x.mp4").path]).status == 2)
        #expect(try CLIRunner.run(animateArguments(f, extra: ["--bogus"])).status == 2)
        #expect(try CLIRunner.run(animateArguments(f, extra: ["--fps", "0"])).status == 2)
    }

    @Test func forceReplacesAnExistingMovie() throws {
        let dir = try TempDirectory()
        let args = animateArguments(dir, extra: ["--samples", "1"])
        #expect(try CLIRunner.run(args).status == 0)
        let again = try CLIRunner.run(args)
        #expect(again.status == 2)
        let forced = try CLIRunner.run(args + ["--force"])
        #expect(forced.status == 0, "\(forced.stderr)")
        #expect(forced.stdout.contains("kept") || forced.stdout.contains("skipped"), "finished frames are reused")
    }
}
