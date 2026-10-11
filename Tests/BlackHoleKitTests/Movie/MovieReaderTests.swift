import Foundation
import Testing
@testable import BlackHoleKit

@Suite(.serialized) struct MovieReaderTests {
    @Test(.enabled(if: MovieTestSupport.avfoundationCanEncode)) func readsCountSizeDurationAndRateOfAMovie() async throws {
        let dir = try TempDirectory()
        let colours = MovieTestSupport.distinctColours(12)
        let movie = dir.file("flat.mp4")
        try await MovieTestSupport.makeReferenceMovie(colours: colours, width: 64, height: 48, fps: 24, to: movie)
        let reader = try await MovieReader.open(movie)
        #expect(reader.frameCount == 12)
        #expect(reader.width == 64 && reader.height == 48)
        #expect(abs(reader.fps - 24) < 0.01)
        #expect(abs(reader.duration - 0.5) < 0.01)
    }

    @Test(.enabled(if: MovieTestSupport.avfoundationCanEncode)) func decodedFramesAreInTheOrderTheyWereWritten() async throws {
        let dir = try TempDirectory()
        let colours = MovieTestSupport.distinctColours(12)
        let movie = dir.file("flat.mp4")
        try await MovieTestSupport.makeReferenceMovie(colours: colours, width: 64, height: 48, fps: 24, to: movie)
        let reader = try await MovieReader.open(movie)
        for (i, colour) in colours.enumerated() {
            let rgb = try await reader.frame(at: i)
            #expect(rgb.count == 64 * 48 * 3)
            let difference = MovieTestSupport.centreDifference(rgb, width: 64, height: 48, from: colour)
            #expect(difference <= 8, "frame \(i) differs from its colour by \(difference) levels")
        }
    }

    @Test func aMissingFileIsAnError() async throws {
        await #expect(throws: (any Error).self) { _ = try await MovieReader.open(URL(fileURLWithPath: "/nonexistent/none.mp4")) }
    }
}
