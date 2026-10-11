import Foundation
import Testing
@testable import BlackHoleKit

/// The built-in AVFoundation encoder (always available).
@Suite(.serialized, .enabled(if: MovieTestSupport.avfoundationCanEncode)) struct AVFoundationEncoderTests {
    private func encoder() -> any MovieEncoder { AVFoundationEncoder() }

    @Test func flatColourFramesComeOutInOrderWithTheRightTimingAndSize() async throws {
        let dir = try TempDirectory()
        let colours = MovieTestSupport.distinctColours(24)
        let files = try MovieTestSupport.writeFlatFrames(colours, width: 64, height: 48, directory: dir.file("f"))
        let movie = dir.file("out.mp4")
        try MovieTestSupport.encode(encoder(), files: files, width: 64, height: 48, output: movie)
        let reader = try await MovieReader.open(movie)
        #expect(reader.frameCount == 24 && reader.width == 64 && reader.height == 48)
        #expect(abs(reader.fps - 24) < 0.01 && abs(reader.duration - 1.0) < 0.01)
        for (i, colour) in colours.enumerated() {
            let difference = MovieTestSupport.centreDifference(try await reader.frame(at: i), width: 64, height: 48, from: colour)
            #expect(difference <= 8, "frame \(i) is \(difference) levels from its colour")
        }
    }

    @Test func realFramesKeepTheirColoursInAppleAndFFmpegDecoders() async throws {
        let dir = try TempDirectory()
        let files = try MovieTestSupport.writeRenderedFrames(count: 6, directory: dir.file("f"))
        let movie = dir.file("out.mp4")
        try MovieTestSupport.encode(encoder(), files: files, width: 160, height: 90, output: movie)
        let reader = try await MovieReader.open(movie)
        let sources = try files.map { try MovieTestSupport.decodePNG($0).rgb }
        for (i, source) in sources.enumerated() {
            let psnr = MovieTestSupport.psnr(source, try await reader.frame(at: i))
            #expect(psnr >= 35, "Apple decoder, frame \(i): \(psnr) dB (risk R4: was 36.2 dB before the colour attachments)")
        }
        if MovieTestSupport.ffmpegAvailable {
            let decoded = try MovieTestSupport.decodeWithFFmpeg(movie, width: 160, height: 90)
            #expect(decoded.count == 6)
            for (i, frame) in decoded.enumerated() {
                let psnr = MovieTestSupport.psnr(sources[i], frame)
                #expect(psnr >= 35, "ffmpeg decoder, frame \(i): \(psnr) dB")
            }
        }
    }

    @Test func theTrackIsTaggedBT709() async throws {
        let dir = try TempDirectory()
        let files = try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(3), width: 64, height: 48, directory: dir.file("f"))
        let movie = dir.file("out.mp4")
        try MovieTestSupport.encode(encoder(), files: files, width: 64, height: 48, output: movie)
        let reader = try await MovieReader.open(movie)
        #expect(reader.colour.primaries?.contains("709") == true && reader.colour.matrix?.contains("709") == true)
        #expect(reader.colour.transfer != nil)
    }

    @Test func twoRunsGiveEquivalentMoviesButAreNotGuaranteedIdentical() async throws {
        // The hardware encoder is not deterministic: at 640x360 x 48 frames two runs decoded to different frames
        // (research.md, "Reproducibility of the AVFoundation encoder"). What is guaranteed is equivalence: the same
        // frames, in the same order, each within the fidelity floor of the source, and `reproducibleFile == false`.
        let dir = try TempDirectory()
        let files = try MovieTestSupport.writeRenderedFrames(count: 6, width: 320, height: 180, directory: dir.file("f"))
        let a = dir.file("a.mp4"), b = dir.file("b.mp4")
        let first = encoder()
        try MovieTestSupport.encode(first, files: files, width: 320, height: 180, output: a)
        try MovieTestSupport.encode(encoder(), files: files, width: 320, height: 180, output: b)
        let ra = try await MovieReader.open(a), rb = try await MovieReader.open(b)
        #expect(ra.frameCount == 6 && rb.frameCount == 6)
        for i in 0..<6 {
            let psnr = MovieTestSupport.psnr(try await ra.frame(at: i), try await rb.frame(at: i))
            #expect(psnr >= 35, "frame \(i) differs between runs by more than compression noise: \(psnr) dB")
        }
        #expect(!first.describe(quality: .standard).reproducibleFile)
    }

    @Test func oddDimensionsAreRejectedBeforeEncoding() throws {
        let dir = try TempDirectory()
        let encoder = encoder()
        #expect(throws: MovieError.oddDimensions(width: 64, height: 47)) {
            try encoder.begin(width: 64, height: 47, fps: 24, quality: .standard, output: dir.file("x.mp4"))
        }
    }

    @Test func cancelLeavesNoFile() throws {
        let dir = try TempDirectory()
        let files = try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(4), width: 64, height: 48, directory: dir.file("f"))
        let encoder = encoder()
        let movie = dir.file("out.mp4")
        try encoder.begin(width: 64, height: 48, fps: 24, quality: .standard, output: movie)
        try encoder.append(frame: files[0])
        encoder.cancel()
        #expect(!FileManager.default.fileExists(atPath: movie.path))
    }

    @Test func memoryDoesNotGrowWithTheNumberOfFrames() throws {
        let dir = try TempDirectory()
        let files = try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(10), width: 640, height: 360, directory: dir.file("f"))
        let encoder = encoder()
        try encoder.begin(width: 640, height: 360, fps: 24, quality: .small, output: dir.file("long.mp4"))
        for i in 0..<20 { try encoder.append(frame: files[i % 10]) }
        let before = MovieTestSupport.footprintBytes()
        for i in 0..<300 { try encoder.append(frame: files[i % 10]) }
        let after = MovieTestSupport.footprintBytes()
        try encoder.finish()
        #expect(after - before < 60_000_000, "footprint grew by \(after - before) bytes over 300 frames")
    }
}
