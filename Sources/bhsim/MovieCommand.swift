import ArgumentParser
import BlackHoleKit
import Foundation

enum EncoderOption: String, ExpressibleByArgument, CaseIterable {
    case auto, ffmpeg, avfoundation
}

enum QualityOption: String, ExpressibleByArgument, CaseIterable {
    case high, standard, small
}

struct Movie: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Make movies from frames.",
        discussion: """
            `assemble` turns a folder of numbered PNG frames into an MP4. `animate` renders a frame sequence by sweeping one
            viewing parameter, then assembles it.

            Exit codes: 0 success; 2 invalid input; 3 output could not be written; 4 more than 0.1% of rays unresolved or out of tolerance (movie still written); 5 backend unavailable; 6 the video could not be encoded (frames are kept); 130 interrupted.
            """,
        subcommands: [MovieAssemble.self, MovieAnimate.self]
    )
}

struct MovieAssemble: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assemble",
        abstract: "Encode a folder of numbered PNG frames into an MP4 movie.",
        discussion: "Frames are files named <prefix><number>.png, played in numerical order. Uses ffmpeg (libx264) when it is installed, otherwise the encoder built into macOS."
    )

    @Option(help: "Folder containing the frames.") var frames: String
    @Option(help: "File-name prefix before the frame number (detected if omitted).") var prefix: String?
    @Option(parsing: .unconditional, help: "Frame rate, 1 to 240.") var fps: Double = 24
    @Option(help: "Output movie file.") var out: String = "movie.mp4"
    @Option(help: "Encoder: auto (ffmpeg if found, else built in), ffmpeg, or avfoundation.") var encoder: EncoderOption = .auto
    @Option(help: "Path of the ffmpeg executable (searched for if omitted).") var ffmpeg: String?
    @Option(help: "Compression quality: high, standard or small.") var quality: QualityOption = .standard
    @Flag(name: .customLong("allow-gaps"), help: "Accept missing frame numbers.") var allowGaps = false
    @Flag(help: "Overwrite an existing movie.") var force = false

    func run() throws {
        var options = MovieAssembler.Options(folder: URL(fileURLWithPath: frames), output: URL(fileURLWithPath: out))
        options.prefix = prefix
        options.fps = fps
        options.allowGaps = allowGaps
        options.force = force
        options.encoder = EncoderChoice(rawValue: encoder.rawValue) ?? .auto
        options.ffmpegPath = ffmpeg
        options.quality = MovieQuality(rawValue: quality.rawValue) ?? .standard

        let reporter = FrameProgress(label: "Encoding")
        do {
            let summary = try MovieAssembler.assemble(options, progress: { reporter.update($0) })
            print("")
            printSummary(summary)
        } catch let error as MovieError {
            print("")
            throw movieExit(error)
        }
    }
}

func printSummary(_ summary: MovieAssembler.Summary) {
    print("Wrote \(summary.path.path) and \(summary.record.path)")
    print(String(format: "%d frames, %.3f s, %dx%d pixels, %g fps", summary.frameCount, summary.duration, summary.width, summary.height, summary.fps))
    print("Encoder: \(summary.encoder.name) \(summary.encoder.version), quality \(summary.encoder.quality) (\(summary.encoder.setting))")
}

/// Prints the error and returns the exit code of `contracts/cli.md`.
func movieExit(_ error: MovieError) -> ExitCode {
    FileHandle.standardError.write(Data("error: \(error.errorDescription ?? "movie error")\n".utf8))
    switch error {
    case .cannotWrite: return ExitCode(3)
    case .encoderUnavailable, .encodingFailed: return ExitCode(6)
    case .cancelled: return ExitCode(130)
    default: return ExitCode(2)
    }
}

/// Prints progress at most once per whole percent.
final class FrameProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1
    private let label: String
    init(label: String) { self.label = label }

    func update(_ fraction: Double) {
        let percent = Int(fraction * 100)
        lock.lock(); defer { lock.unlock() }
        guard percent > last, percent % 5 == 0 || percent == 100 else { return }
        last = percent
        print("\r\(label): \(percent)%", terminator: "")
        fflush(stdout)
    }
}

enum SweepOption: String, ExpressibleByArgument, CaseIterable {
    case inclination, distance, spin
}

/// Set by SIGINT; polled between frames. A second SIGINT ends the process at once.
nonisolated(unsafe) private var interrupted: Int32 = 0

struct MovieAnimate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "animate",
        abstract: "Render a frame sequence by sweeping one parameter, then assemble the movie.",
        discussion: """
            Every frame is a complete render (no interpolation) of a stationary black hole seen by a static observer, with \
            one exposure reference for the whole movie. Frames are written to <out>_frames/ as they are made; rerunning the \
            same command continues where an interrupted run stopped. Use --samples 4 for a quick draft (default 9).
            """
    )

    @OptionGroup var options: RenderOptions
    @Option(parsing: .unconditional, help: "Samples per pixel (a perfect square); movies default to 9.") var samples: Int = 9
    @Option(help: "The parameter that changes: inclination (degrees), distance (M) or spin.") var sweep: SweepOption
    @Option(parsing: .unconditional, help: "Start value of the swept parameter.") var from: Double
    @Option(parsing: .unconditional, help: "End value of the swept parameter.") var to: Double
    @Option(parsing: .unconditional, help: "Movie length in seconds.") var duration: Double
    @Option(parsing: .unconditional, help: "Frame rate, 1 to 240.") var fps: Double = 24
    @Option(help: "Output movie file; frames go to <name>_frames/.") var out: String = "movie.mp4"
    @Option(help: "Encoder: auto (ffmpeg if found, else built in), ffmpeg, or avfoundation.") var encoder: EncoderOption = .auto
    @Option(help: "Path of the ffmpeg executable (searched for if omitted).") var ffmpeg: String?
    @Option(help: "Compression quality: high, standard or small.") var quality: QualityOption = .standard
    @Flag(name: .customLong("keep-exr"), help: "Also keep each frame's 32-bit physical-intensity image.") var keepEXR = false
    @Flag(help: "Overwrite an existing movie.") var force = false

    func run() throws {
        let animation = Animation(parameter: SweepParameter(rawValue: sweep.rawValue) ?? .inclination, from: from, to: to,
                                  duration: duration, fps: fps, base: options.config(samples: samples))
        let output = URL(fileURLWithPath: out)
        let framesFolder = output.deletingPathExtension().deletingLastPathComponent()
            .appendingPathComponent(output.deletingPathExtension().lastPathComponent + "_frames")

        // Everything that can be checked is checked before the first frame is rendered.
        let choice = EncoderChoice(rawValue: encoder.rawValue) ?? .auto
        do {
            try animation.validate()
            if FileManager.default.fileExists(atPath: output.path), !force { throw MovieError.outputExists(output.path) }
            _ = try EncoderSelection.select(choice, ffmpegPath: ffmpeg)
        } catch let error as MovieError {
            throw movieExit(error)
        }
        do {
            _ = try Renderer(config: animation.frameConfig(0))
        } catch let error as BackendError {
            FileHandle.standardError.write(Data("error: --backend: \(error.errorDescription ?? "the requested backend is unavailable")\n".utf8))
            throw ExitCode(5)
        } catch let error as ConfigError {
            FileHandle.standardError.write(Data("error: \(error.errorDescription ?? "invalid input")\n".utf8))
            throw ExitCode(2)
        }

        let n = animation.frameCount
        let estimate = Double(AnimationRunner.diskEstimateBytes(animation, keepEXR: keepEXR)) / 1e6
        print("Rendering \(n) frames of \(animation.base.width)x\(animation.base.height) at \(samples) samples/pixel: \(sweep.rawValue) \(from) to \(to) over \(duration) s at \(fps) fps")
        print(String(format: "Disk space for the frames: up to %.0f MB in %@", estimate, framesFolder.path))

        signal(SIGINT) { _ in
            if interrupted != 0 { _exit(130) }
            interrupted = 1
        }
        let cancelled: @Sendable () -> Bool = { interrupted != 0 }

        var assemble = MovieAssembler.Options(folder: framesFolder, output: output)
        assemble.force = force
        assemble.encoder = choice
        assemble.ffmpegPath = ffmpeg
        assemble.quality = MovieQuality(rawValue: quality.rawValue) ?? .standard
        let reporter = FrameProgress(label: "Encoding")
        let made: AnimationMovie.Output
        do {
            made = try AnimationMovie.make(animation, framesFolder: framesFolder, keepEXR: keepEXR, assemble: assemble,
                                           frameProgress: { frame, total in
                                               print("\rframe \(frame)/\(total)", terminator: frame == total ? "\n" : "")
                                               fflush(stdout)
                                           },
                                           onFramesDone: { frames in
                                               print("Frames: rendered \(frames.rendered), kept \(frames.skipped) from an earlier run")
                                           },
                                           encodeProgress: { reporter.update($0) }, isCancelled: cancelled)
            print("")
            printSummary(made.summary)
        } catch let error as MovieError {
            print("")
            if case .cancelled = error { reportInterruption(framesFolder) }
            throw movieExit(error)
        } catch let error as BackendError {
            print("")
            FileHandle.standardError.write(Data("error: --backend: \(error.errorDescription ?? "the requested backend is unavailable")\n".utf8))
            throw ExitCode(5)
        }
        let result = made.frames

        let d = result.diagnostics
        print("Rays: \(d.raysTotal) total, \(d.unresolved) unresolved, \(d.raysOverTolerance) over the residual bound; worst residual \(String(format: "%.2e", d.maxResidual))")
        if d.badRayFraction > NumericalDefaults.allowedBadRayFraction {
            FileHandle.standardError.write(Data(String(format: "error: %.3f%% of the movie's rays were unresolved or exceeded the residual bound (limit %.1f%%); the movie was still written\n",
                                                       100 * d.badRayFraction, 100 * NumericalDefaults.allowedBadRayFraction).utf8))
            throw ExitCode(4)
        }
    }

    private func reportInterruption(_ folder: URL) {
        FileHandle.standardError.write(Data("Interrupted: the finished frames in \(folder.path) are kept; run the same command again to continue.\n".utf8))
    }
}
