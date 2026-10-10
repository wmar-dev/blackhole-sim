import Foundation
import Testing
@testable import BlackHoleKit

@Suite(.serialized) struct MovieAssemblerTests {
    private func options(_ dir: TempDirectory, output: String = "out/movie.mp4", force: Bool = false) -> MovieAssembler.Options {
        var o = MovieAssembler.Options(folder: dir.file("frames"), output: dir.file(output))
        o.fps = 24; o.force = force; o.encoder = .avfoundation
        return o
    }

    @Test func assemblesAndReportsTheSummary() async throws {
        let dir = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(12), width: 64, height: 48, directory: dir.file("frames"))
        let summary = try MovieAssembler.assemble(options(dir))
        #expect(summary.frameCount == 12 && summary.width == 64 && summary.height == 48)
        #expect(abs(summary.duration - 0.5) < 1e-9 && summary.fps == 24)
        #expect(summary.path == dir.file("out/movie.mp4"))
        #expect(summary.encoder.name == "avfoundation")
        let reader = try await MovieReader.open(summary.path)
        #expect(reader.frameCount == 12)
        #expect(FileManager.default.fileExists(atPath: dir.file("out/movie.mp4.json").path), "the record is written next to the movie")
    }

    @Test func framesCreatedInReverseOrderStillPlayInNumericalOrder() async throws {
        let dir = try TempDirectory()
        let colours = MovieTestSupport.distinctColours(6)
        for (i, colour) in colours.enumerated().reversed() {
            try MovieTestSupport.writeFlatFrames([colour], width: 64, height: 48, directory: dir.file("frames"), firstNumber: i + 1)
        }
        let summary = try MovieAssembler.assemble(options(dir))
        let reader = try await MovieReader.open(summary.path)
        for (i, colour) in colours.enumerated() {
            #expect(MovieTestSupport.centreDifference(try await reader.frame(at: i), width: 64, height: 48, from: colour) <= 8)
        }
    }

    @Test func anExistingOutputIsRefusedUnlessForced() throws {
        let dir = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(4), width: 64, height: 48, directory: dir.file("frames"))
        try FileManager.default.createDirectory(at: dir.file("out"), withIntermediateDirectories: true)
        try Data("precious".utf8).write(to: dir.file("out/movie.mp4"))
        #expect(throws: MovieError.outputExists(dir.file("out/movie.mp4").path)) { try MovieAssembler.assemble(options(dir)) }
        #expect(try Data(contentsOf: dir.file("out/movie.mp4")) == Data("precious".utf8), "the existing file is untouched")
        _ = try MovieAssembler.assemble(options(dir, force: true))
        #expect(try Data(contentsOf: dir.file("out/movie.mp4")).count > 100)
    }

    @Test func aFailedEncodeLeavesNothingAtTheFinalPathOrBesideIt() throws {
        let dir = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(4), width: 64, height: 48, directory: dir.file("frames"))
        let failing = MovieTestSupport.FailingEncoder()
        #expect(throws: MovieError.self) { try MovieAssembler.assemble(options(dir), encoder: failing) }
        #expect(failing.appended == 4)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.file("out").path)) ?? []
        #expect(leftovers.isEmpty, "left behind: \(leftovers)")
    }

    @Test func progressIsReportedOncePerFrameAndEndsAtOne() throws {
        let dir = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(8), width: 64, height: 48, directory: dir.file("frames"))
        let seen = LockedBox<[Double]>([])
        _ = try MovieAssembler.assemble(options(dir), progress: { fraction in seen.mutate { $0.append(fraction) } })
        let values = seen.value
        #expect(values.count == 8 && values.last == 1)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func cancellationStopsAndCleansUp() throws {
        let dir = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(10), width: 64, height: 48, directory: dir.file("frames"))
        let count = LockedBox(0)
        #expect(throws: MovieError.cancelled) {
            try MovieAssembler.assemble(options(dir), progress: { _ in count.mutate { $0 += 1 } }, isCancelled: { count.value >= 3 })
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.file("out").path)) ?? []
        #expect(leftovers.isEmpty, "left behind: \(leftovers)")
    }

    @Test func theFrameFilesAreNeverModified() throws {
        let dir = try TempDirectory()
        let files = try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(4), width: 64, height: 48, directory: dir.file("frames"))
        let before = try files.map { try Data(contentsOf: $0) }
        _ = try MovieAssembler.assemble(options(dir))
        #expect(try files.map { try Data(contentsOf: $0) } == before)
    }
}
