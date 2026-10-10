import Foundation
import Testing
@testable import BlackHoleKit

@Suite struct EncoderSelectionTests {
    /// A directory holding a fake `ffmpeg` shell script that answers `-version` and `-encoders` like the real program.
    private func fakeFFmpeg(version: String = "ffmpeg version 9.9-test", encoders: String = " V....D libx264  H.264", named name: String = "ffmpeg") throws -> TempDirectory {
        let dir = try TempDirectory()
        let script = """
        #!/bin/sh
        case "$1" in
          -version) echo "\(version) Copyright" ;;
          -hide_banner) echo "Encoders:"; echo "\(encoders)" ;;
        esac
        """
        let url = dir.file(name)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return dir
    }

    @Test func autoPicksFFmpegWhenAUsableOneIsOnTheSearchPath() throws {
        let dir = try fakeFFmpeg()
        let encoder = try EncoderSelection.select(.auto, searchPaths: [dir.url.path])
        #expect(encoder.describe(quality: .standard).name == "ffmpeg")
        #expect(encoder.describe(quality: .standard).version.contains("9.9-test"))
    }

    @Test func autoFallsBackToAVFoundationWhenThereIsNoFFmpeg() throws {
        let empty = try TempDirectory()
        let encoder = try EncoderSelection.select(.auto, searchPaths: [empty.url.path])
        #expect(encoder.describe(quality: .standard).name == "avfoundation")
    }

    @Test func requestingFFmpegWithoutOneNeverFallsBack() throws {
        let empty = try TempDirectory()
        do {
            _ = try EncoderSelection.select(.ffmpeg, searchPaths: [empty.url.path])
            Issue.record("expected an error")
        } catch let error as MovieError {
            guard case .encoderUnavailable(let text) = error else { Issue.record("wrong error \(error)"); return }
            #expect(text.contains(empty.url.path), "the message names the searched locations: \(text)")
        }
    }

    @Test func avfoundationIsAlwaysSelectedWhenAsked() throws {
        let dir = try fakeFFmpeg()
        let encoder = try EncoderSelection.select(.avfoundation, searchPaths: [dir.url.path])
        #expect(encoder.describe(quality: .standard).name == "avfoundation")
    }

    @Test func anExecutableThatIsNotFFmpegIsRejected() throws {
        let notFFmpeg = try fakeFFmpeg(version: "something else entirely")
        do {
            _ = try EncoderSelection.select(.ffmpeg, searchPaths: [notFFmpeg.url.path])
            Issue.record("expected an error")
        } catch let error as MovieError {
            #expect((error.errorDescription ?? "").contains("not ffmpeg"), "\(error.errorDescription ?? "")")
        }
    }

    @Test func anFFmpegWithoutLibx264IsRejected() throws {
        let noX264 = try fakeFFmpeg(encoders: " V....D mpeg4  MPEG-4")
        do {
            _ = try EncoderSelection.select(.ffmpeg, searchPaths: [noX264.url.path])
            Issue.record("expected an error")
        } catch let error as MovieError {
            #expect((error.errorDescription ?? "").contains("libx264"), "\(error.errorDescription ?? "")")
        }
        // and `auto` skips it
        #expect(try EncoderSelection.select(.auto, searchPaths: [noX264.url.path]).describe(quality: .standard).name == "avfoundation")
    }

    @Test func anExplicitPathOverridesTheSearch() throws {
        let dir = try fakeFFmpeg(named: "my-ffmpeg")
        let encoder = try EncoderSelection.select(.ffmpeg, ffmpegPath: dir.file("my-ffmpeg").path, searchPaths: [])
        #expect(encoder.describe(quality: .standard).name == "ffmpeg")
    }

    @Test func qualityPresetsMapToTheDocumentedSettings() throws {
        #expect(MovieQuality.high.crf == 16 && MovieQuality.standard.crf == 18 && MovieQuality.small.crf == 23)
        #expect(MovieQuality.high.bitsPerPixelPerFrame == 0.35)
        #expect(MovieQuality.standard.bitsPerPixelPerFrame == 0.25)
        #expect(MovieQuality.small.bitsPerPixelPerFrame == 0.12)
        #expect(MovieQuality.high.minimumBitRate == 2_000_000 && MovieQuality.standard.minimumBitRate == 1_000_000 && MovieQuality.small.minimumBitRate == 500_000)
        let dir = try fakeFFmpeg()
        let ffmpeg = try EncoderSelection.select(.ffmpeg, searchPaths: [dir.url.path])
        #expect(ffmpeg.describe(quality: .small).setting == "crf=23" && ffmpeg.describe(quality: .small).reproducibleFile)
        let av = try EncoderSelection.select(.avfoundation, searchPaths: [])
        #expect(av.describe(quality: .high).setting == "bitsPerPixel=0.35,min=2000kbit/s" && !av.describe(quality: .high).reproducibleFile)
    }
}
