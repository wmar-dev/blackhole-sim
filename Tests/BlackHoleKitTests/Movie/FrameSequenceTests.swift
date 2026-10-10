import Foundation
import Testing
@testable import BlackHoleKit

@Suite struct FrameSequenceTests {
    private func message(_ body: () throws -> Void) -> String {
        do { try body(); return "no error" } catch let e as MovieError { return e.errorDescription ?? "\(e)" } catch { return "\(error)" }
    }

    @Test func framesSortNumericallyNotAlphabetically() throws {
        let dir = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(12), width: 8, height: 6, directory: dir.url, prefix: "frame_", padding: 0)
        let sequence = try FrameSequence.discover(in: dir.url)
        #expect(sequence.numbers == Array(1...12))
        #expect(sequence.files.map(\.lastPathComponent).prefix(3) == ["frame_1.png", "frame_2.png", "frame_3.png"])
        #expect(sequence.files[9].lastPathComponent == "frame_10.png")
        #expect(sequence.prefix == "frame_" && sequence.width == 8 && sequence.height == 6)
    }

    @Test func zeroPaddedNamesWork() throws {
        let dir = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(5), width: 8, height: 6, directory: dir.url, padding: 4)
        #expect(try FrameSequence.discover(in: dir.url).numbers == [1, 2, 3, 4, 5])
    }

    @Test func theExplicitPrefixOverridesDetectionAndMixedPrefixesAreAnError() throws {
        let dir = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(3), width: 8, height: 6, directory: dir.url, prefix: "a_")
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(3), width: 8, height: 6, directory: dir.url, prefix: "b_")
        let text = message { _ = try FrameSequence.discover(in: dir.url) }
        #expect(text.contains("a_") && text.contains("b_"), "\(text)")
        let only = try FrameSequence.discover(in: dir.url, prefix: "b_")
        #expect(only.prefix == "b_" && only.numbers == [1, 2, 3])
    }

    @Test func missingAndEmptyFoldersNameTheFolderAndThePattern() throws {
        let missing = message { _ = try FrameSequence.discover(in: URL(fileURLWithPath: "/nonexistent/frames-xyz")) }
        #expect(missing.contains("/nonexistent/frames-xyz"), "\(missing)")
        let dir = try TempDirectory()
        let empty = message { _ = try FrameSequence.discover(in: dir.url) }
        #expect(empty.contains(dir.url.path) && empty.contains(".png"), "\(empty)")
    }

    @Test func aGapNamesTheMissingFrameUnlessAllowed() throws {
        let dir = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(10), width: 8, height: 6, directory: dir.url, firstNumber: 1)
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(9), width: 8, height: 6, directory: dir.url, firstNumber: 12)
        let text = message { _ = try FrameSequence.discover(in: dir.url) }
        #expect(text.contains("11"), "\(text)")
        let allowed = try FrameSequence.discover(in: dir.url, allowGaps: true)
        #expect(allowed.files.count == 19 && !allowed.numbers.contains(11))
        #expect(allowed.numbers == allowed.numbers.sorted())
    }

    @Test func aFrameOfAnotherSizeNamesTheFirstOffender() throws {
        let dir = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(4), width: 8, height: 6, directory: dir.url)
        try MovieTestSupport.writeFlatFrames([(1, 2, 3)], width: 10, height: 6, directory: dir.url, firstNumber: 3)  // overwrites frame 3
        let text = message { _ = try FrameSequence.discover(in: dir.url) }
        #expect(text.contains("frame_0003.png") && text.contains("10") && text.contains("8"), "\(text)")
    }

    @Test(arguments: [(9, 6), (8, 7)])
    func oddDimensionsAreRejectedWithAnEvenSuggestion(width: Int, height: Int) throws {
        let dir = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(2), width: width, height: height, directory: dir.url)
        let text = message { _ = try FrameSequence.discover(in: dir.url) }
        #expect(text.contains("even") && text.contains("\(width)x\(height)"), "\(text)")
    }

    @Test func unrelatedFilesAreIgnoredAndSizesComeFromTheHeader() throws {
        let dir = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(3), width: 16, height: 10, directory: dir.url)
        try Data("notes".utf8).write(to: dir.file("readme.txt"))
        try Data("x".utf8).write(to: dir.file("frame_0004.jpg"))
        try Data("x".utf8).write(to: dir.file("other.png"))
        let sequence = try FrameSequence.discover(in: dir.url, prefix: "frame_")
        #expect(sequence.files.count == 3 && sequence.width == 16 && sequence.height == 10)
    }
}
