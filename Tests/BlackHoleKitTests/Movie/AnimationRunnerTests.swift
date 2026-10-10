import Foundation
import Testing
@testable import BlackHoleKit

@Suite(.serialized) struct AnimationRunnerTests {
    private func animation(samples: Int = 1, seed: UInt64 = 1, backend: Backend = .cpu) -> Animation {
        var base = RenderConfig()
        base.width = 64; base.height = 36; base.samplesPerPixel = samples; base.sky.seed = seed; base.backend = backend
        return Animation(parameter: .inclination, from: 85, to: 60, duration: 1, fps: 8, base: base)  // 8 frames
    }

    private func options(_ dir: TempDirectory, name: String = "frames", keepEXR: Bool = false) -> AnimationRunner.Options {
        AnimationRunner.Options(framesFolder: dir.file(name), keepEXR: keepEXR)
    }

    private func frameURL(_ dir: TempDirectory, folder: String = "frames", _ i: Int, ext: String = "png") -> URL {
        dir.file("\(folder)/frame_\(String(format: "%04d", i)).\(ext)")
    }

    @Test func rendersEveryFrameWithItsRecordAndNoEXRByDefault() throws {
        let dir = try TempDirectory()
        let result = try AnimationRunner.run(animation(), options: options(dir))
        #expect(result.rendered == 8 && result.skipped == 0)
        for i in 1...8 {
            #expect(FileManager.default.fileExists(atPath: frameURL(dir, i).path))
            #expect(FileManager.default.fileExists(atPath: frameURL(dir, i, ext: "json").path))
            #expect(!FileManager.default.fileExists(atPath: frameURL(dir, i, ext: "exr").path))
        }
        let sequence = try FrameSequence.discover(in: dir.file("frames"))
        #expect(sequence.files.count == 8 && sequence.width == 64 && sequence.height == 36)
        #expect(result.diagnostics.raysTotal == 8 * 64 * 36)

        let withEXR = try AnimationRunner.run(animation(), options: options(dir, name: "exr", keepEXR: true))
        #expect(withEXR.rendered == 8)
        #expect(FileManager.default.fileExists(atPath: frameURL(dir, folder: "exr", 3, ext: "exr").path))
    }

    @Test func firstAndLastFramesAreByteIdenticalToSingleRenders() throws {
        let dir = try TempDirectory()
        let a = animation()
        _ = try AnimationRunner.run(a, options: options(dir))
        for i in [0, 7] {
            let config = a.frameConfig(i)
            let image = try Renderer(config: config).render()
            let single = dir.file("single\(i).png")
            try PNGWriter.write(rgb8: ToneMap.rgb8(from: image.hdr, exposureStops: config.exposureStops), width: image.width, height: image.height, to: single)
            #expect(try Data(contentsOf: single) == Data(contentsOf: frameURL(dir, i + 1)), "frame \(i + 1)")
        }
    }

    @Test func aStoppedRunResumesAndEndsIdenticalToAnUninterruptedOne() throws {
        let dir = try TempDirectory()
        let rendered = LockedBox(0)
        #expect(throws: MovieError.cancelled) {
            try AnimationRunner.run(animation(), options: options(dir), progress: { _, _ in rendered.mutate { $0 += 1 } },
                                    isCancelled: { rendered.value >= 3 })
        }
        #expect(FileManager.default.fileExists(atPath: frameURL(dir, 3, ext: "json").path))
        #expect(!FileManager.default.fileExists(atPath: frameURL(dir, 4).path))
        let resumed = try AnimationRunner.run(animation(), options: options(dir))
        #expect(resumed.skipped == 3 && resumed.rendered == 5)

        _ = try AnimationRunner.run(animation(), options: options(dir, name: "whole"))
        for i in 1...8 {
            #expect(try Data(contentsOf: frameURL(dir, i)) == Data(contentsOf: frameURL(dir, folder: "whole", i)), "frame \(i)")
        }
        #expect(resumed.diagnostics.raysTotal == 8 * 64 * 36, "the diagnostics of the whole movie include the frames kept")
    }

    @Test func anIncompleteFrameIsRenderedAgain() throws {
        let dir = try TempDirectory()
        _ = try AnimationRunner.run(animation(), options: options(dir))
        try FileManager.default.removeItem(at: frameURL(dir, 4, ext: "json"))   // PNG present, completion marker missing
        let result = try AnimationRunner.run(animation(), options: options(dir))
        #expect(result.rendered == 1 && result.skipped == 7)
        #expect(FileManager.default.fileExists(atPath: frameURL(dir, 4, ext: "json").path))
    }

    @Test func aFrameOfTheWrongSizeIsRenderedAgain() throws {
        let dir = try TempDirectory()
        _ = try AnimationRunner.run(animation(), options: options(dir))
        try PNGWriter.write(rgb8: [UInt8](repeating: 0, count: 10 * 10 * 3), width: 10, height: 10, to: frameURL(dir, 2))
        let result = try AnimationRunner.run(animation(), options: options(dir))
        #expect(result.rendered == 1)
        #expect(try FrameSequence.discover(in: dir.file("frames")).width == 64)
    }

    @Test func changingAnyOptionInvalidatesTheFramesItAffects() throws {
        let dir = try TempDirectory()
        _ = try AnimationRunner.run(animation(seed: 1), options: options(dir))
        let sameAgain = try AnimationRunner.run(animation(seed: 1), options: options(dir))
        #expect(sameAgain.rendered == 0 && sameAgain.skipped == 8)
        let otherSeed = try AnimationRunner.run(animation(seed: 2), options: options(dir))
        #expect(otherSeed.rendered == 8, "a different seed is a different image")
        let moreSamples = try AnimationRunner.run(animation(samples: 4, seed: 2), options: options(dir))
        #expect(moreSamples.rendered == 8)
    }

    @Test func progressNamesEveryFrameInOrderIncludingKeptOnes() throws {
        let dir = try TempDirectory()
        let seen = LockedBox<[Int]>([])
        _ = try AnimationRunner.run(animation(), options: options(dir), progress: { frame, total in
            #expect(total == 8); seen.mutate { $0.append(frame) }
        })
        #expect(seen.value == Array(1...8))
        seen.mutate { $0 = [] }
        _ = try AnimationRunner.run(animation(), options: options(dir), progress: { frame, _ in seen.mutate { $0.append(frame) } })
        #expect(seen.value == Array(1...8), "kept frames are reported too")
    }

    @Test func theDiskEstimateIsFramesTimesPixelsTimesBytes() {
        let a = animation()
        #expect(AnimationRunner.diskEstimateBytes(a, keepEXR: false) == 8 * 64 * 36 * 3)
        #expect(AnimationRunner.diskEstimateBytes(a, keepEXR: true) == 8 * 64 * 36 * (3 + 12))
    }

    @Test func eachFrameRecordCarriesItsInputsAndDiagnostics() throws {
        let dir = try TempDirectory()
        _ = try AnimationRunner.run(animation(), options: options(dir))
        let data = try Data(contentsOf: frameURL(dir, 5, ext: "json"))
        let record = try JSONDecoder().decode(FrameRecord.self, from: data)
        #expect(record.index == 5 && record.parameter == "inclination")
        #expect(abs(record.value - animation().value(at: 4)) < 1e-12)
        #expect(record.metadata.diagnostics.raysTotal == 64 * 36)
        #expect(record.metadata.observer.inclinationDeg == record.value)
        #expect(record.metadata.hdr.referenceRadiance == animation().referenceRadiance)
    }
}
