import Foundation
import Testing
@testable import BlackHoleKit

/// What a repeated command guarantees (spec FR-011, SC-005): identical frames always; with ffmpeg an identical file; with the
/// built-in encoder an equivalent one (its hardware encoder is not deterministic: research.md, T019).
@Suite(.serialized) struct MovieDeterminismTests {
    private func animation() -> Animation {
        var base = RenderConfig()
        base.width = 96; base.height = 54; base.samplesPerPixel = 4; base.sky.seed = 3; base.blackHole.spin = 0.7
        return Animation(parameter: .inclination, from: 85, to: 50, duration: 0.75, fps: 8, base: base)  // 6 frames
    }

    private func make(_ encoder: EncoderChoice, in dir: TempDirectory, cancelAfter: Int? = nil) throws -> MovieRecord {
        var options = MovieAssembler.Options(folder: dir.file("x"), output: dir.file("m.mp4"))
        options.encoder = encoder
        let counted = LockedBox(0)
        let limit = cancelAfter ?? Int.max
        _ = try AnimationMovie.make(animation(), framesFolder: dir.file("m_frames"), assemble: options,
                                    frameProgress: { _, _ in counted.mutate { $0 += 1 } },
                                    isCancelled: { counted.value >= limit })
        return try JSONDecoder().decode(MovieRecord.self, from: Data(contentsOf: dir.file("m.mp4.json")))
    }

    private func withoutWallTime(_ record: MovieRecord) -> MovieRecord {
        var copy = record
        copy.diagnostics?.wallTimeSeconds = 0
        return copy
    }

    private func samePNGs(_ a: TempDirectory, _ b: TempDirectory) throws -> Bool {
        for i in 1...6 {
            let name = String(format: "m_frames/frame_%04d.png", i)
            if try Data(contentsOf: a.file(name)) != Data(contentsOf: b.file(name)) { return false }
        }
        return true
    }

    @Test(.enabled(if: MovieTestSupport.ffmpegAvailable)) func withFFmpegFramesFileAndRecordRepeatExactly() throws {
        let a = try TempDirectory(), b = try TempDirectory()
        let ra = try make(.ffmpeg, in: a), rb = try make(.ffmpeg, in: b)
        #expect(try samePNGs(a, b))
        #expect(try Data(contentsOf: a.file("m.mp4")) == Data(contentsOf: b.file("m.mp4")), "the movie files differ")
        #expect(withoutWallTime(ra) == withoutWallTime(rb))
        #expect(ra.movie.encoder.reproducibleFile)
    }

    @Test func withTheBuiltInEncoderFramesAndRecordRepeatAndTheMovieIsEquivalent() async throws {
        let a = try TempDirectory(), b = try TempDirectory()
        let ra = try make(.avfoundation, in: a), rb = try make(.avfoundation, in: b)
        #expect(try samePNGs(a, b), "the PNG frames are exactly reproducible with either encoder")
        #expect(withoutWallTime(ra) == withoutWallTime(rb))
        #expect(!ra.movie.encoder.reproducibleFile)
        let readerA = try await MovieReader.open(a.file("m.mp4")), readerB = try await MovieReader.open(b.file("m.mp4"))
        #expect(readerA.frameCount == 6 && readerB.frameCount == 6)
        for i in 0..<6 {
            let psnr = MovieTestSupport.psnr(try await readerA.frame(at: i), try await readerB.frame(at: i))
            #expect(psnr >= 35, "frame \(i) differs between runs by more than compression noise: \(psnr) dB")
        }
    }

    @Test func aResumedRunEqualsAnUninterruptedOneInFramesAndRecord() throws {
        let whole = try TempDirectory(), split = try TempDirectory()
        let expected = try make(.avfoundation, in: whole)
        #expect(throws: MovieError.cancelled) { _ = try make(.avfoundation, in: split, cancelAfter: 3) }
        #expect(!FileManager.default.fileExists(atPath: split.file("m.mp4").path))
        let resumed = try make(.avfoundation, in: split)
        #expect(try samePNGs(whole, split))
        #expect(withoutWallTime(resumed).frames == withoutWallTime(expected).frames)
        #expect(withoutWallTime(resumed).diagnostics?.raysTotal == withoutWallTime(expected).diagnostics?.raysTotal)
        #expect(resumed.common == expected.common && resumed.referenceRadiance == expected.referenceRadiance && resumed.animation == expected.animation)
    }
}
