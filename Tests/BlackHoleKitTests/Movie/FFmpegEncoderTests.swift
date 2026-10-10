import Foundation
import Testing
@testable import BlackHoleKit

/// The ffmpeg (libx264) encoder. Skipped when no usable ffmpeg is installed.
@Suite(.enabled(if: MovieTestSupport.ffmpegAvailable), .serialized) struct FFmpegEncoderTests {
    private func encoder() throws -> any MovieEncoder { try EncoderSelection.select(.ffmpeg) }

    @Test func flatColourFramesComeOutInOrderWithTheRightTimingAndSize() async throws {
        let dir = try TempDirectory()
        let colours = MovieTestSupport.distinctColours(24)
        let files = try MovieTestSupport.writeFlatFrames(colours, width: 64, height: 48, directory: dir.file("f"))
        let movie = dir.file("out.mp4")
        try MovieTestSupport.encode(try encoder(), files: files, width: 64, height: 48, output: movie)
        let reader = try await MovieReader.open(movie)
        #expect(reader.frameCount == 24 && reader.width == 64 && reader.height == 48)
        #expect(abs(reader.fps - 24) < 0.01 && abs(reader.duration - 1.0) < 0.01)
        for (i, colour) in colours.enumerated() {
            let difference = MovieTestSupport.centreDifference(try await reader.frame(at: i), width: 64, height: 48, from: colour)
            #expect(difference <= 8, "frame \(i) is \(difference) levels from its colour")
        }
    }

    @Test func realFramesKeepTheirColoursAndTheTrackIsTagged() async throws {
        // 640x360 is the smallest picture size the fidelity floor is claimed for (research.md, ffmpeg calibration).
        let dir = try TempDirectory()
        let files = try MovieTestSupport.writeRenderedFrames(count: 6, width: 640, height: 360, directory: dir.file("f"))
        let movie = dir.file("out.mp4")
        try MovieTestSupport.encode(try encoder(), files: files, width: 640, height: 360, output: movie)
        let reader = try await MovieReader.open(movie)
        for (i, file) in files.enumerated() {
            let source = try MovieTestSupport.decodePNG(file).rgb
            let psnr = MovieTestSupport.psnr(source, try await reader.frame(at: i))
            #expect(psnr >= 35, "frame \(i): \(psnr) dB")
        }
        #expect(reader.colour.primaries?.contains("709") == true, "primaries \(reader.colour.primaries ?? "none")")
        #expect(reader.colour.matrix?.contains("709") == true, "matrix \(reader.colour.matrix ?? "none")")
        #expect(reader.colour.transfer?.lowercased().contains("srgb") == true, "transfer \(reader.colour.transfer ?? "none")")
    }

    @Test func saturatedColoursSurviveAndAMisTaggedMovieFailsTheSameCheck() async throws {
        // Saturated flat colours show a wrong colour matrix; grey-ish renders would not. The same check applied to a movie
        // relabelled as BT.601 while its pixels are BT.709 must fail, so the test can detect a tagging error.
        let dir = try TempDirectory()
        let colours: [MovieTestSupport.RGB] = [(220, 40, 40), (40, 200, 60), (60, 60, 230)]
        let files = try MovieTestSupport.writeFlatFrames(colours, width: 64, height: 48, directory: dir.file("f"))
        let good = dir.file("good.mp4"), bad = dir.file("bad.mp4")
        try MovieTestSupport.encode(try encoder(), files: files, width: 64, height: 48, output: good)
        let location = try FFmpegEncoder.locate(explicit: nil, searchPaths: EncoderSelection.defaultSearchPaths)
        // Relabel the matrix of the good movie as BT.601 (SMPTE 170M) without touching the pixels.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: location.path)
        process.arguments = ["-v", "error", "-y", "-i", good.path, "-c", "copy", "-bsf:v", "h264_metadata=matrix_coefficients=6",
                             "-colorspace", "smpte170m", "-fflags", "+bitexact", bad.path]
        try process.run(); process.waitUntilExit()
        let goodReader = try await MovieReader.open(good), badReader = try await MovieReader.open(bad)
        var worstGood = 0, worstBad = 0
        for (i, colour) in colours.enumerated() {
            worstGood = max(worstGood, MovieTestSupport.centreDifference(try await goodReader.frame(at: i), width: 64, height: 48, from: colour))
            worstBad = max(worstBad, MovieTestSupport.centreDifference(try await badReader.frame(at: i), width: 64, height: 48, from: colour))
        }
        #expect(worstGood <= 8, "correctly tagged movie is \(worstGood) levels off")
        #expect(worstBad > 12, "mislabelled movie is only \(worstBad) levels off: the test would not catch a tagging error")
    }

    @Test func twoRunsGiveByteIdenticalFiles() throws {
        let dir = try TempDirectory()
        let files = try MovieTestSupport.writeRenderedFrames(count: 6, directory: dir.file("f"))
        let a = dir.file("a.mp4"), b = dir.file("b.mp4")
        let first = try encoder()
        try MovieTestSupport.encode(first, files: files, width: 160, height: 90, output: a)
        try MovieTestSupport.encode(try encoder(), files: files, width: 160, height: 90, output: b)
        #expect(try Data(contentsOf: a) == Data(contentsOf: b))
        #expect(first.describe(quality: .standard).reproducibleFile)
    }

    @Test func oddDimensionsAreRejectedBeforeFFmpegStarts() throws {
        let dir = try TempDirectory()
        let encoder = try encoder()
        #expect(throws: MovieError.oddDimensions(width: 63, height: 48)) {
            try encoder.begin(width: 63, height: 48, fps: 24, quality: .standard, output: dir.file("x.mp4"))
        }
        #expect(!FileManager.default.fileExists(atPath: dir.file("x.mp4").path))
    }

    @Test func aFailingFFmpegGivesItsErrorTextAndLeavesNoFile() throws {
        let fake = try MovieTestSupport.fakeFailingFFmpeg()
        let dir = try TempDirectory()
        let files = try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(4), width: 64, height: 48, directory: dir.file("f"))
        let encoder = try EncoderSelection.select(.ffmpeg, searchPaths: [fake.url.path])
        let movie = dir.file("out.mp4")
        do {
            try MovieTestSupport.encode(encoder, files: files, width: 64, height: 48, output: movie)
            Issue.record("expected an error")
        } catch let error as MovieError {
            guard case .encodingFailed(let text) = error else { Issue.record("wrong error \(error)"); return }
            #expect(text.contains("boom"), "\(text)")
        }
        #expect(!FileManager.default.fileExists(atPath: movie.path))
    }

    @Test func memoryDoesNotGrowWithTheNumberOfFrames() throws {
        let dir = try TempDirectory()
        let files = try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(10), width: 640, height: 360, directory: dir.file("f"))
        let encoder = try encoder()
        try encoder.begin(width: 640, height: 360, fps: 24, quality: .small, output: dir.file("long.mp4"))
        for i in 0..<20 { try encoder.append(frame: files[i % 10]) }  // warm up
        let before = MovieTestSupport.footprintBytes()
        for i in 0..<300 { try encoder.append(frame: files[i % 10]) }
        let after = MovieTestSupport.footprintBytes()
        try encoder.finish()
        #expect(after - before < 60_000_000, "footprint grew by \(after - before) bytes over 300 frames")
    }
}
